import XCTest

final class NavigationRobustnessRegressionTests: RegressionTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        app = LiftrUIApplication()
        app.launchForRegression()
    }

    @MainActor
    func testMainTabsRenderWithoutCrash() throws {
        let tabs = TabBarPage(app: app)
        try step("Visit every main tab") {
            tabs.visitAllTabs()
        }
        try step("Confirm tab bar still visible") {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: UITestWait.standard))
        }
    }
}
