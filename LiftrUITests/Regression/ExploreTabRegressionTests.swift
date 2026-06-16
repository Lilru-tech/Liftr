import XCTest

final class ExploreTabRegressionTests: RegressionTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        app = LiftrUIApplication()
        app.launchForRegression()
    }

    @MainActor
    func testExploreTabLoads() throws {
        let tabs = TabBarPage(app: app)

        try step("Open explore tab") {
            tabs.selectExplore()
        }

        try step("Assert explore search UI exists") {
            XCTAssertTrue(app.otherElements["explore.screen"].waitForExistence(timeout: UITestWait.network))
            let searchField = app.textFields.matching(
                NSPredicate(format: "placeholderValue CONTAINS 'Search'")
            ).firstMatch
            XCTAssertTrue(searchField.waitForExistence(timeout: UITestWait.standard))
        }
    }
}
