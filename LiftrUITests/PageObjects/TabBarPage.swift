import XCTest

struct TabBarPage {
    let app: XCUIApplication

    func waitForTabBar(timeout: TimeInterval = UITestWait.launch) {
        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: timeout),
            "Main tab bar did not appear after launch."
        )
    }

    func selectTab(at index: Int) {
        waitForTabBar()
        let tabButton = app.tabBars.buttons.element(boundBy: index)
        XCTAssertTrue(
            tabButton.waitForExistence(timeout: UITestWait.standard),
            "Tab bar button at index \(index) was not found."
        )
        tabButton.tap()
    }

    func selectHome() {
        selectTab(at: 0)
    }

    func selectExplore() {
        selectTab(at: 1)
    }

    func selectAdd() {
        selectTab(at: 2)
    }

    func selectFood() {
        selectTab(at: 3)
    }

    func selectProfile() {
        selectTab(at: 4)
    }

    func visitAllTabs() {
        waitForTabBar()
        for index in 0..<5 {
            selectTab(at: index)
        }
    }
}
