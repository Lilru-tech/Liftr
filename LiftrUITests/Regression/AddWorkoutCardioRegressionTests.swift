import XCTest

final class AddWorkoutCardioRegressionTests: RegressionTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        app = LiftrUIApplication()
        app.launchForRegression()
    }

    @MainActor
    func testSaveCardioWorkoutReturnsToHome() throws {
        let tabs = TabBarPage(app: app)
        let addWorkout = AddWorkoutPage(app: app)
        let home = HomePage(app: app)

        try step("Open add workout tab") {
            tabs.selectAdd()
            addWorkout.waitForScreen()
        }

        try step("Select cardio and save") {
            addWorkout.selectWorkoutType("Cardio")
            addWorkout.enableFinishedWorkoutIfNeeded()
            addWorkout.saveWorkout()
        }

        try step("Verify success and home feed") {
            addWorkout.waitForSaveSuccess()
            tabs.selectHome()
            home.waitForFeedLoaded()
        }
    }
}
