import XCTest

struct TabBarPage {
    let app: XCUIApplication

    func waitForTabBar(timeout: TimeInterval = UITestWait.launch) {
        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: timeout),
            "Main tab bar did not appear after launch."
        )
    }

    private func tabElement(_ identifier: String) -> XCUIElement {
        let candidates: [XCUIElement] = [
            app.buttons[identifier],
            app.otherElements[identifier],
            app.tabBars.buttons[identifier],
        ]
        for candidate in candidates where candidate.exists {
            return candidate
        }
        return app.buttons[identifier]
    }

    func selectTab(identifier: String, fallbackIndex: Int) {
        waitForTabBar()
        let tab = tabElement(identifier)
        if tab.waitForExistence(timeout: UITestWait.standard) {
            tab.tap()
            return
        }
        let tabButton = app.tabBars.buttons.element(boundBy: fallbackIndex)
        XCTAssertTrue(
            tabButton.waitForExistence(timeout: UITestWait.standard),
            "Tab bar button at index \(fallbackIndex) was not found."
        )
        tabButton.tap()
    }

    func selectHome() {
        selectTab(identifier: "tab.home", fallbackIndex: 0)
    }

    func selectExplore() {
        selectTab(identifier: "tab.explore", fallbackIndex: 1)
    }

    func selectAdd() {
        selectTab(identifier: "tab.add", fallbackIndex: 2)
    }

    func selectFood() {
        selectTab(identifier: "tab.food", fallbackIndex: 3)
    }

    func selectProfile() {
        selectTab(identifier: "tab.profile", fallbackIndex: 4)
    }

    func visitAllTabs() {
        waitForTabBar()
        selectHome()
        selectExplore()
        selectAdd()
        selectFood()
        selectProfile()
    }
}
