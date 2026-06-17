import XCTest

final class HomeFeedRegressionTests: RegressionTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        app = LiftrUIApplication()
        app.launchForRegression()
    }

    @MainActor
    func testHomeFeedLoadsWhenAuthenticated() throws {
        let tabs = TabBarPage(app: app)
        let home = HomePage(app: app)

        try step("Open home tab") {
            tabs.selectHome()
        }

        try step("Wait for authenticated home feed") {
            home.waitForFeedLoaded()
        }
    }
}
