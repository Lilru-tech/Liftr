import XCTest

final class ForgotPasswordRegressionTests: RegressionTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        app = LiftrUIApplication()
        app.launchForRegression(autoSignIn: false)
    }

    @MainActor
    func testForgotPasswordScreenAcceptsEmail() throws {
        let tabs = TabBarPage(app: app)
        let login = LoginPage(app: app)
        let forgot = ForgotPasswordPage(app: app)

        try step("Open forgot password from login") {
            tabs.selectProfile()
            login.openForgotPassword()
        }

        try step("Submit configured email") {
            forgot.submitEmail(UITestCredentials.email)
        }

        try step("Wait for success or error UI") {
            forgot.waitForSubmissionResult()
        }
    }
}
