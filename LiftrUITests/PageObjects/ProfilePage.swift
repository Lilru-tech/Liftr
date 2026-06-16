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

        let marketByIdentifier = marketMenuItem
        if marketByIdentifier.waitForExistence(timeout: 3) {
            marketByIdentifier.tap()
            return
        }

        let marketByLabel = app.buttons["Market"]
        XCTAssertTrue(marketByLabel.waitForExistence(timeout: UITestWait.standard))
        marketByLabel.tap()
    }

    func waitForAuthenticatedProfile(timeout: TimeInterval = UITestWait.network) {
        let menuReady = menuButton.waitForExistence(timeout: timeout)
        let coinsBadge = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Liftr Coins balance'")
        ).firstMatch.waitForExistence(timeout: menuReady ? 2 : timeout)

        XCTAssertTrue(
            menuReady || coinsBadge,
            "Authenticated profile did not appear after sign in."
        )
    }
}
