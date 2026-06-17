import XCTest

final class RegisterFullRegressionTests: RegressionTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        XCTAssertTrue(
            UITestCredentials.isSignupConfigured,
            "UI_TEST_SIGNUP_EMAIL and UI_TEST_SIGNUP_USERNAME must be configured."
        )
        app = LiftrUIApplication()
        app.launchForRegression(autoSignIn: false)
    }

    @MainActor
    func testRegisterCreatesAccountAndShowsProfile() throws {
        let tabs = TabBarPage(app: app)
        let login = LoginPage(app: app)
        let register = RegisterPage(app: app)
        let profile = ProfilePage(app: app)

        try step("Open register screen") {
            tabs.selectProfile()
            login.openRegister()
            register.waitForScreen()
        }

        try step("Submit signup form") {
            register.fillForm(
                email: UITestCredentials.signupEmail,
                password: UITestCredentials.signupPassword,
                username: UITestCredentials.signupUsername
            )
            register.submitWhenEnabled()
        }

        try step("Wait for authenticated profile after signup") {
            profile.waitForAuthenticatedProfile(timeout: UITestWait.network)
        }
    }
}
