import XCTest

struct MarketPage {
    let app: XCUIApplication

    var coinBanner: XCUIElement { app.otherElements["market.coinBanner"] }
    var navigationBar: XCUIElement { app.navigationBars["Market"] }

    func waitForMarket() {
        XCTAssertTrue(navigationBar.waitForExistence(timeout: UITestWait.network))
        XCTAssertTrue(coinBanner.waitForExistence(timeout: UITestWait.standard))
    }

    func currentCoinBalance() -> Int? {
        guard coinBanner.waitForExistence(timeout: UITestWait.standard) else { return nil }
        let bannerText = coinBanner.staticTexts.firstMatch.label
        let digits = bannerText.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(digits)
    }

    func openItem(itemType: String) {
        let identifier = "market.item.\(itemType)"
        let item = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(item.waitForExistence(timeout: UITestWait.standard))
        item.tap()
    }

    func purchaseFoodQuantity(_ quantity: Int) {
        let quantityButton = app.buttons["market.overlay.qty.\(quantity)"]
        XCTAssertTrue(quantityButton.waitForExistence(timeout: UITestWait.standard))
        quantityButton.tap()
    }

    func purchaseGenericItem() {
        let buyButton = app.buttons["market.overlay.buy"]
        XCTAssertTrue(buyButton.waitForExistence(timeout: UITestWait.standard))
        buyButton.tap()
    }

    func waitForPurchaseFeedback(timeout: TimeInterval = UITestWait.network) -> Bool {
        let toast = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'purchased' OR label CONTAINS[c] 'added' OR label CONTAINS[c] 'success'")
        ).firstMatch
        if toast.waitForExistence(timeout: timeout) {
            return true
        }
        return app.buttons["market.overlay.close"].waitForExistence(timeout: 2) == false
    }
}
