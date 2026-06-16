import XCTest

final class NavigationRobustnessRegressionTests: XCTestCase {
    private var app: LiftrUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = LiftrUIApplication()
        app.launchForRegression()
    }

    @MainActor
    func testMainTabsRenderWithoutCrash() throws {
        let tabs = TabBarPage(app: app)

        tabs.visitAllTabs()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: UITestWait.standard))
    }
}
