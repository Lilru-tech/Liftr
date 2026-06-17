import XCTest

final class AddWorkoutStrengthRegressionTests: RegressionTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        app = LiftrUIApplication()
        app.launchForRegression()
    }

    @MainActor
    func testSaveStrengthWorkoutWithExercise() throws {
        let tabs = TabBarPage(app: app)
        let addWorkout = AddWorkoutPage(app: app)

        try step("Open add workout tab") {
            tabs.selectAdd()
            addWorkout.waitForScreen()
        }

        try step("Pick exercise and enter reps") {
            addWorkout.pickFirstExercise()
            addWorkout.enterRepsForFirstSet("10")
        }

        try step("Save strength workout") {
            addWorkout.saveWorkout()
            addWorkout.waitForSaveSuccess()
        }
    }
}
