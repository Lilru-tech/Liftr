import XCTest

struct LoginPage {
    let app: XCUIApplication

    var emailField: XCUIElement { app.textFields["login.email"] }
    var passwordField: XCUIElement { app.secureTextFields["login.password"] }

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
            break
        } else {
            XCTFail("Register link was not found on the login screen.")
            return
        }
        let registerReady = app.textFields["register.email"].waitForExistence(timeout: UITestWait.network)
            || app.otherElements["register.screen"].waitForExistence(timeout: UITestWait.network)
            || app.staticTexts["Create your account to start tracking your workouts."].waitForExistence(timeout: UITestWait.network)
        XCTAssertTrue(registerReady, "Register screen did not appear after tapping Create an account.")
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
            break
        } else {
            XCTFail("Forgot password link was not found on the login screen.")
            return
        }
        let forgotReady = app.textFields["forgotPassword.email"].waitForExistence(timeout: UITestWait.network)
            || app.navigationBars["Forgot password"].waitForExistence(timeout: UITestWait.network)
            || app.otherElements["forgotPassword.screen"].waitForExistence(timeout: UITestWait.network)
        XCTAssertTrue(forgotReady, "Forgot password screen did not appear.")
    }

    func signIn(email: String, password: String) {
        waitForLoginScreen()
        emailField.clearAndTypeText(email)
        passwordField.clearAndTypeText(password)
        dismissKeyboardIfPresent()
        let submit = waitForEnabledSignInButton(timeout: UITestWait.network)
        submit.tap()
        waitForSignInCompletion()
    }

    func signInWithConfiguredCredentials() {
        waitForLoginScreen()
        let deadline = Date().addingTimeInterval(UITestWait.network)
        while Date() < deadline {
            if let submit = enabledSignInButton() {
                submit.tap()
                waitForSignInCompletion()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        signIn(email: UITestCredentials.email, password: UITestCredentials.password)
    }

    private func enabledSignInButton() -> XCUIElement? {
        let candidates: [XCUIElement] = [
            app.buttons["login.submit"],
            app.buttons["Sign in"],
        ]
        for candidate in candidates where candidate.exists && candidate.isEnabled {
            return candidate
        }
        return nil
    }

    @discardableResult
    private func waitForEnabledSignInButton(timeout: TimeInterval) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let submit = enabledSignInButton() {
                return submit
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Sign in button did not become enabled.")
        return app.buttons["Sign in"]
    }

    private func dismissKeyboardIfPresent() {
        app.toolbars.buttons["Done"].tapIfExists(timeout: 1)
        app.keyboards.buttons["Done"].tapIfExists(timeout: 1)
        if app.keyboards.count > 0 {
            app.tap()
        }
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
        _ = app.otherElements["uitest.authenticated"].waitForExistence(timeout: UITestWait.network)
    }
}
