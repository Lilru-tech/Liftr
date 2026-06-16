import XCTest

struct TabBarPage {
    let app: XCUIApplication

    func selectHome() {
        app.tabBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["tab.home"].waitForExistence(timeout: UITestWait.standard))
    }

    func selectExplore() {
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.otherElements["tab.explore"].waitForExistence(timeout: UITestWait.standard))
    }

    func selectAdd() {
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.otherElements["tab.add"].waitForExistence(timeout: UITestWait.standard))
    }

    func selectFood() {
        app.tabBars.buttons.element(boundBy: 3).tap()
        XCTAssertTrue(app.otherElements["tab.food"].waitForExistence(timeout: UITestWait.standard))
    }

    func selectProfile() {
        app.tabBars.buttons.element(boundBy: 4).tap()
        XCTAssertTrue(app.otherElements["tab.profile"].waitForExistence(timeout: UITestWait.standard))
    }

    func visitAllTabs() {
        selectHome()
        selectExplore()
        selectAdd()
        selectFood()
        selectProfile()
    }
}
