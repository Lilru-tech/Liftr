import XCTest

struct LoginPage {
    let app: XCUIApplication

    var emailField: XCUIElement { app.textFields["login.email"] }
    var passwordField: XCUIElement { app.secureTextFields["login.password"] }
    var submitButton: XCUIElement { app.buttons["login.submit"] }
    var registerLink: XCUIElement { app.buttons["login.register"] }
    var forgotPasswordLink: XCUIElement { app.staticTexts["Forgot password?"] }

    func openRegister() {
        if registerLink.waitForExistence(timeout: UITestWait.standard) {
            registerLink.tap()
            return
        }
        app.staticTexts["Create an account"].tap()
    }

    func openForgotPassword() {
        XCTAssertTrue(forgotPasswordLink.waitForExistence(timeout: UITestWait.standard))
        forgotPasswordLink.tap()
    }

    func signIn(email: String, password: String) {
        XCTAssertTrue(emailField.waitForExistence(timeout: UITestWait.standard))
        emailField.clearAndTypeText(email)

        XCTAssertTrue(passwordField.waitForExistence(timeout: UITestWait.standard))
        passwordField.clearAndTypeText(password)

        XCTAssertTrue(submitButton.waitForExistence(timeout: UITestWait.standard))
        XCTAssertTrue(submitButton.isEnabled, "Sign in button stayed disabled after entering credentials.")
        submitButton.tap()

        let signingInLabel = app.staticTexts["Signing in…"]
        if signingInLabel.waitForExistence(timeout: 2) {
            let finished = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: signingInLabel
            )
            _ = XCTWaiter().wait(for: [finished], timeout: UITestWait.network)
        }
    }

    func signInWithConfiguredCredentials() {
        if emailField.waitForExistence(timeout: UITestWait.standard),
           passwordField.waitForExistence(timeout: 2),
           submitButton.waitForExistence(timeout: 2),
           submitButton.isEnabled {
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
