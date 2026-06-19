import XCTest

struct MarketPage {
    let app: XCUIApplication

    var screen: XCUIElement { app.otherElements["market.screen"] }
    var coinBanner: XCUIElement { app.descendants(matching: .any)["market.coinBanner"] }
    var navigationBar: XCUIElement { app.navigationBars["Market"] }

    func waitForMarket() {
        let screenReady = screen.waitForExistence(timeout: UITestWait.network)
        let navigationReady = navigationBar.waitForExistence(timeout: screenReady ? 2 : UITestWait.network)
        XCTAssertTrue(
            screenReady || navigationReady,
            "Market screen did not appear."
        )

        let bannerByIdentifier = coinBanner.waitForExistence(timeout: UITestWait.network)
        let bannerByLabel = app.staticTexts
            .matching(NSPredicate(format: "label ENDSWITH 'coins'"))
            .firstMatch
            .waitForExistence(timeout: bannerByIdentifier ? 2 : UITestWait.network)
        XCTAssertTrue(
            bannerByIdentifier || bannerByLabel,
            "Market coin banner did not appear."
        )

        XCTAssertTrue(
            waitForMarketItem(itemType: "food_baby"),
            "food_baby market item did not appear."
        )
    }

    func currentCoinBalance() -> Int? {
        if coinBanner.waitForExistence(timeout: UITestWait.standard) {
            let bannerText = coinBanner.label
            if !bannerText.isEmpty {
                let digits = bannerText.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if let balance = Int(digits) { return balance }
            }
        }

        let coinsLabel = app.staticTexts
            .matching(NSPredicate(format: "label ENDSWITH 'coins'"))
            .firstMatch
        guard coinsLabel.waitForExistence(timeout: UITestWait.standard) else { return nil }
        let digits = coinsLabel.label.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(digits)
    }

    func openItem(itemType: String) {
        let item = marketItemElement(itemType: itemType)
        XCTAssertTrue(
            waitForMarketItem(itemType: itemType),
            "Market item \(itemType) was not visible."
        )

        var scrollAttempts = 0
        while scrollAttempts < 8, !item.isHittable {
            app.swipeLeft()
            scrollAttempts += 1
        }

        if item.isHittable {
            item.tap()
        } else {
            item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        XCTAssertTrue(
            waitForPurchaseOverlay(),
            "Market item overlay for \(itemType) did not open."
        )
    }

    func purchaseFoodQuantity(_ quantity: Int) {
        let quantityButton = app.buttons["market.overlay.qty.\(quantity)"]
        if quantityButton.waitForExistence(timeout: UITestWait.network) {
            quantityButton.tap()
            return
        }

        let quantityByLabel = app.buttons["Buy quantity \(quantity)"]
        if quantityByLabel.waitForExistence(timeout: UITestWait.standard) {
            quantityByLabel.tap()
            return
        }

        let quantityByText = app.buttons["\(quantity)"]
        XCTAssertTrue(
            quantityByText.waitForExistence(timeout: UITestWait.standard),
            "Market quantity button for \(quantity) was not visible."
        )
        quantityByText.tap()
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

    private func marketItemElement(itemType: String) -> XCUIElement {
        let identifier = "market.item.\(itemType)"
        let button = app.buttons[identifier].firstMatch
        if button.waitForExistence(timeout: 2) {
            return button
        }
        return app.descendants(matching: .any)[identifier].firstMatch
    }

    private func waitForMarketItem(itemType: String) -> Bool {
        let item = marketItemElement(itemType: itemType)
        if item.waitForExistence(timeout: UITestWait.network) {
            return true
        }

        for _ in 0..<8 {
            app.swipeLeft()
            if item.waitForExistence(timeout: 2) {
                return true
            }
        }
        return false
    }

    private func waitForPurchaseOverlay() -> Bool {
        if app.otherElements["market.overlay"].waitForExistence(timeout: UITestWait.network) {
            return true
        }
        if app.buttons["market.overlay.close"].waitForExistence(timeout: 2) {
            return true
        }
        if app.buttons["Close"].waitForExistence(timeout: 2) {
            return true
        }
        return app.buttons["market.overlay.qty.1"].waitForExistence(timeout: UITestWait.network)
    }
}
