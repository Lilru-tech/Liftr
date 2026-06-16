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
            XCTAssertTrue(register.submitButton.waitForExistence(timeout: UITestWait.standard))
            XCTAssertFalse(register.submitButton.isEnabled)
        }
    }
}
