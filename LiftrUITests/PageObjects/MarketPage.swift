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

        let itemReady = app.buttons["market.item.food_baby"].firstMatch
            .waitForExistence(timeout: UITestWait.network)
        if !itemReady {
            XCTAssertTrue(
                app.descendants(matching: .any)["market.item.food_baby"].firstMatch
                    .waitForExistence(timeout: UITestWait.standard),
                "food_baby market item did not appear."
            )
        }
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
        let identifier = "market.item.\(itemType)"
        let item = app.buttons[identifier].firstMatch
        if !item.waitForExistence(timeout: 3) {
            let fallback = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(
                fallback.waitForExistence(timeout: UITestWait.network),
                "Market item \(itemType) was not visible."
            )
            fallback.tap()
        } else {
            item.tap()
        }
        XCTAssertTrue(
            app.buttons["market.overlay.close"].waitForExistence(timeout: UITestWait.network),
            "Market item overlay for \(itemType) did not open."
        )
    }

    func purchaseFoodQuantity(_ quantity: Int) {
        let quantityButton = app.buttons["market.overlay.qty.\(quantity)"]
        if quantityButton.waitForExistence(timeout: UITestWait.network) {
            quantityButton.tap()
            return
        }

        let quantityByLabel = app.buttons["\(quantity)"]
        XCTAssertTrue(
            quantityByLabel.waitForExistence(timeout: UITestWait.standard),
            "Market quantity button for \(quantity) was not visible."
        )
        quantityByLabel.tap()
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
