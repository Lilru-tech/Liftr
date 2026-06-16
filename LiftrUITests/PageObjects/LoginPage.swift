import XCTest

struct LoginPage {
    let app: XCUIApplication

    var emailField: XCUIElement { app.textFields["login.email"] }
    var passwordField: XCUIElement { app.secureTextFields["login.password"] }
    var submitButton: XCUIElement { app.buttons["login.submit"] }

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
        signIn(email: UITestCredentials.email, password: UITestCredentials.password)
    }
}
