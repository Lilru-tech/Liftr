import XCTest

final class MarketTransactionRegressionTests: XCTestCase {
    private var app: LiftrUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = LiftrUIApplication()
        app.launchForRegression()
    }

    @MainActor
    func testPurchasePetFoodUpdatesCoinBalance() throws {
        let tabs = TabBarPage(app: app)
        let login = LoginPage(app: app)
        let profile = ProfilePage(app: app)
        let market = MarketPage(app: app)

        tabs.selectProfile()
        profile.dismissUpdateBannerIfPresent()
        login.signInWithConfiguredCredentials()
        profile.waitForAuthenticatedProfile()

        profile.openMarketFromMenu()
        market.waitForMarket()

        let balanceBefore = try XCTUnwrap(market.currentCoinBalance())
        market.openItem(itemType: "food_baby")
        market.purchaseFoodQuantity(1)

        let deadline = Date().addingTimeInterval(UITestWait.network)
        var balanceAfter = balanceBefore
        while Date() < deadline {
            if let updated = market.currentCoinBalance(), updated < balanceBefore {
                balanceAfter = updated
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        XCTAssertLessThan(balanceAfter, balanceBefore)
        _ = market.waitForPurchaseFeedback()
    }
}
