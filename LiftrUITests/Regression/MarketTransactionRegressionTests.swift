import XCTest

final class MarketTransactionRegressionTests: RegressionTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        app = LiftrUIApplication()
        app.launchForRegression()
    }

    @MainActor
    func testPurchasePetFoodUpdatesCoinBalance() throws {
        let tabs = TabBarPage(app: app)
        let profile = ProfilePage(app: app)
        let market = MarketPage(app: app)

        try step("Open market from profile menu") {
            tabs.selectProfile()
            profile.dismissUpdateBannerIfPresent()
            profile.waitForAuthenticatedProfile()
            profile.openMarketFromMenu()
            market.waitForMarket()
        }

        var balanceBefore = 0
        try step("Read coin balance") {
            balanceBefore = try XCTUnwrap(market.currentCoinBalance())
        }

        try step("Purchase food_baby") {
            market.openItem(itemType: "food_baby")
            market.purchaseFoodQuantity(1)
        }

        try step("Verify balance decreased") {
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
}
