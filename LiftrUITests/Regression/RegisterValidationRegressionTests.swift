import XCTest

final class RegisterValidationRegressionTests: RegressionTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        app = LiftrUIApplication()
        app.launchForRegression(autoSignIn: false)
    }

    @MainActor
    func testRegisterSubmitDisabledWithInvalidEmail() throws {
        let tabs = TabBarPage(app: app)
        let login = LoginPage(app: app)
        let register = RegisterPage(app: app)

        try step("Navigate to register screen") {
            tabs.selectProfile()
            login.openRegister()
            register.waitForScreen()
        }

        try step("Enter invalid email and valid other fields") {
            register.fillForm(email: "not-an-email", password: "12345678", username: "uitestuser")
        }

        try step("Assert submit stays disabled") {
            register.emailField.tap()
            let invalidLabel = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'invalid email'")
            ).firstMatch
            let createButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'Create account'")
            ).firstMatch
            XCTAssertTrue(
                invalidLabel.waitForExistence(timeout: UITestWait.network)
                    || (createButton.waitForExistence(timeout: UITestWait.standard) && !createButton.isEnabled),
                "Invalid email did not disable account creation."
            )
        }
    }
}
