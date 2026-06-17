import XCTest

struct ProfilePage {
    let app: XCUIApplication

    var menuButton: XCUIElement { app.buttons["profile.menu"] }
    var marketMenuItem: XCUIElement { app.buttons["profile.menu.market"] }
    var goalsMenuItem: XCUIElement { app.buttons["profile.menu.goals"] }
    var achievementsMenuItem: XCUIElement { app.buttons["profile.menu.achievements"] }
    var logoutButton: XCUIElement { app.buttons["profile.menu.logout"] }

    func openMenuItem(_ element: XCUIElement, fallbackLabel: String) {
        XCTAssertTrue(menuButton.waitForExistence(timeout: UITestWait.standard))
        menuButton.tap()

        if element.waitForExistence(timeout: UITestWait.standard) {
            element.tap()
            return
        }

        let candidates: [XCUIElement] = [
            app.menuItems[fallbackLabel],
            app.buttons[fallbackLabel],
            app.staticTexts[fallbackLabel],
        ]
        for candidate in candidates where candidate.waitForExistence(timeout: UITestWait.standard) {
            candidate.tap()
            return
        }
        XCTFail("\(fallbackLabel) menu item was not found.")
    }

    func openGoalsFromMenu() {
        openMenuItem(goalsMenuItem, fallbackLabel: "Goals")
    }

    func openAchievementsFromMenu() {
        openMenuItem(achievementsMenuItem, fallbackLabel: "Achievements")
    }

    func openSettingsTab() {
        let settingsCandidates: [XCUIElement] = [
            app.buttons["Settings"],
            app.staticTexts["Settings"],
        ]
        for candidate in settingsCandidates where candidate.waitForExistence(timeout: UITestWait.standard) {
            candidate.tap()
            return
        }
        app.swipeLeft()
        for candidate in settingsCandidates where candidate.waitForExistence(timeout: UITestWait.standard) {
            candidate.tap()
            return
        }
        XCTFail("Settings tab was not found on profile.")
    }

    func signOutFromSettings() {
        openSettingsTab()
        let settingsReady = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Sign out' OR label CONTAINS 'Delete account'")
        ).firstMatch
        _ = settingsReady.waitForExistence(timeout: UITestWait.standard)
        for _ in 0..<4 {
            app.swipeUp()
        }
        let candidates: [XCUIElement] = [
            logoutButton,
            app.buttons["Sign out"],
            app.staticTexts["Sign out"],
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sign out'")).firstMatch,
        ]
        for candidate in candidates where candidate.waitForExistence(timeout: UITestWait.network) {
            candidate.tap()
            return
        }
        XCTFail("Sign out control was not found in profile settings.")
    }

    func dismissUpdateBannerIfPresent() {
        app.buttons["Later"].tapIfExists(timeout: 2)
    }

    func openMarketFromMenu() {
        XCTAssertTrue(menuButton.waitForExistence(timeout: UITestWait.standard))
        menuButton.tap()

        let menuCandidates: [XCUIElement] = [
            app.menuItems["Market"],
            marketMenuItem,
            app.buttons["Market"],
            app.staticTexts["Market"],
        ]

        for candidate in menuCandidates {
            if candidate.waitForExistence(timeout: UITestWait.standard) {
                candidate.tap()
                return
            }
        }

        XCTFail("Market menu item was not found in the profile menu.")
    }

    func waitForAuthenticatedProfile(timeout: TimeInterval = UITestWait.network) {
        let sessionReady = app.otherElements["uitest.authenticated"].waitForExistence(timeout: timeout)
        let menuReady = menuButton.waitForExistence(timeout: sessionReady ? 5 : timeout)

        XCTAssertTrue(
            sessionReady || menuReady,
            "Authenticated profile did not appear after sign in."
        )
    }
}
