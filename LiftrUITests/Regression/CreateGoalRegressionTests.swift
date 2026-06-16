import XCTest

final class CreateGoalRegressionTests: RegressionTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        app = LiftrUIApplication()
        app.launchForRegression()
    }

    @MainActor
    func testCreateWeeklyWorkoutsGoal() throws {
        let tabs = TabBarPage(app: app)
        let profile = ProfilePage(app: app)
        let goals = GoalsPage(app: app)

        try step("Open goals from profile menu") {
            tabs.selectProfile()
            profile.dismissUpdateBannerIfPresent()
            profile.waitForAuthenticatedProfile()
            profile.openGoalsFromMenu()
            goals.waitForScreen()
        }

        try step("Create weekly workouts goal") {
            goals.createWeeklyWorkoutsGoal(target: "3")
        }

        try step("Verify goal appears in list") {
            goals.waitForGoalTitle("Workouts goal")
        }
    }
}
