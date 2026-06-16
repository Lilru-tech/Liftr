import XCTest

struct LoginPage {
    let app: XCUIApplication

    var emailField: XCUIElement { app.textFields["login.email"] }
    var passwordField: XCUIElement { app.secureTextFields["login.password"] }
    var submitButton: XCUIElement { app.buttons["login.submit"] }

    func signIn(email: String, password: String) {
        XCTAssertTrue(emailField.waitForExistence(timeout: UITestWait.standard))
        emailField.tap()
        emailField.typeText(email)

        XCTAssertTrue(passwordField.waitForExistence(timeout: UITestWait.standard))
        passwordField.tap()
        passwordField.typeText(password)

        XCTAssertTrue(submitButton.waitForExistence(timeout: UITestWait.standard))
        submitButton.tap()
    }

    func signInWithConfiguredCredentials() {
        signIn(email: UITestCredentials.email, password: UITestCredentials.password)
    }
}
