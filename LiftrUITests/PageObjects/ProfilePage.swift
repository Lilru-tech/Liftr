import XCTest

struct ProfilePage {
    let app: XCUIApplication

    var menuButton: XCUIElement { app.buttons["profile.menu"] }
    var marketMenuItem: XCUIElement { app.buttons["profile.menu.market"] }

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
