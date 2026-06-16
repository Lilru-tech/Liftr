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
            let ready = app.otherElements["nutrition.screen"].waitForExistence(timeout: UITestWait.network)
                || app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add nutrition'")).firstMatch.waitForExistence(timeout: UITestWait.network)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Diary' OR label CONTAINS 'Calories'")).firstMatch.waitForExistence(timeout: UITestWait.network)
            XCTAssertTrue(ready, "Nutrition screen did not load.")
        }
    }
}
