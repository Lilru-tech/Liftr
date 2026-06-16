import XCTest

final class NutritionTabRegressionTests: RegressionTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        app = LiftrUIApplication()
        app.launchForRegression()
    }

    @MainActor
    func testNutritionTabLoads() throws {
        let tabs = TabBarPage(app: app)

        try step("Open nutrition tab") {
            tabs.selectFood()
        }

        try step("Assert nutrition screen loaded") {
            XCTAssertTrue(app.otherElements["nutrition.screen"].waitForExistence(timeout: UITestWait.network))
        }
    }
}
