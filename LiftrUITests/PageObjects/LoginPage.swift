import XCTest

struct LoginPage {
    let app: XCUIApplication

    var emailField: XCUIElement { app.textFields["login.email"] }
    var passwordField: XCUIElement { app.secureTextFields["login.password"] }
    var submitButton: XCUIElement { app.buttons["login.submit"] }

    func waitForLoginScreen(timeout: TimeInterval = UITestWait.network) {
        let candidates: [XCUIElement] = [
            app.otherElements["login.screen"],
            emailField,
            app.secureTextFields["login.password"],
            app.staticTexts["Sign in to continue tracking your workouts."],
            app.buttons["Sign in"],
            app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'email'")).firstMatch,
        ]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if candidates.contains(where: { $0.exists }) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(false, "Login screen did not appear.")
    }

    func openRegister() {
        waitForLoginScreen()
        let candidates: [XCUIElement] = [
            app.buttons["login.register"],
            app.staticTexts["login.register"],
            app.otherElements["login.register"],
            app.buttons["Create an account"],
            app.staticTexts["Create an account"],
        ]
        for candidate in candidates where candidate.waitForExistence(timeout: UITestWait.standard) {
            candidate.tap()
            return
        }
        XCTFail("Register link was not found on the login screen.")
    }

    func openForgotPassword() {
        waitForLoginScreen()
        let candidates: [XCUIElement] = [
            app.buttons["forgotPassword.link"],
            app.staticTexts["forgotPassword.link"],
            app.staticTexts["Forgot password?"],
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'Forgot password'")).firstMatch,
        ]
        for candidate in candidates where candidate.waitForExistence(timeout: UITestWait.standard) {
            candidate.tap()
            return
        }
        XCTFail("Forgot password link was not found on the login screen.")
    }

    func signIn(email: String, password: String) {
        waitForLoginScreen()
        emailField.clearAndTypeText(email)
        passwordField.clearAndTypeText(password)
        XCTAssertTrue(submitButton.waitForExistence(timeout: UITestWait.standard))
        XCTAssertTrue(submitButton.isEnabled, "Sign in button stayed disabled after entering credentials.")
        submitButton.tap()
        waitForSignInCompletion()
    }

    func signInWithConfiguredCredentials() {
        waitForLoginScreen()
        if submitButton.waitForExistence(timeout: UITestWait.standard), submitButton.isEnabled {
            submitButton.tap()
            waitForSignInCompletion()
            return
        }
        signIn(email: UITestCredentials.email, password: UITestCredentials.password)
    }

    private func waitForSignInCompletion() {
        let signingInLabel = app.staticTexts["Signing in…"]
        if signingInLabel.waitForExistence(timeout: 2) {
            let finished = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: signingInLabel
            )
            _ = XCTWaiter().wait(for: [finished], timeout: UITestWait.network)
        }
    }
}
