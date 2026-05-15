import XCTest
@testable import Liftr

final class ForgotPasswordRegressionTests: XCTestCase {
    func testAuthRedirectURL() {
        XCTAssertEqual(AuthRedirect.scheme, "com.davidgomez.Liftr")
        XCTAssertEqual(AuthRedirect.host, "auth-callback")
        XCTAssertEqual(AuthRedirect.appDeepLinkURL.absoluteString, "com.davidgomez.Liftr://auth-callback")
        XCTAssertEqual(
            AuthRedirect.webCallbackURL.absoluteString,
            "https://settleit-auth.vercel.app/auth/callback"
        )
    }

    func testIsAuthCallback() {
        let url = URL(string: "com.davidgomez.Liftr://auth-callback?code=test")!
        XCTAssertTrue(AuthRedirect.isAuthCallback(url))
        let pathStyle = URL(string: "com.davidgomez.Liftr:///auth-callback?code=test")!
        XCTAssertTrue(AuthRedirect.isAuthCallback(pathStyle))
        XCTAssertFalse(AuthRedirect.isAuthCallback(URL(string: "https://example.com")!))
    }

    func testPasswordValidation() {
        XCTAssertFalse(PasswordResetValidation.isPasswordValid("short"))
        XCTAssertTrue(PasswordResetValidation.isPasswordValid("longenough"))
        XCTAssertTrue(PasswordResetValidation.passwordsMatch("abc", "abc"))
        XCTAssertFalse(PasswordResetValidation.passwordsMatch("abc", "xyz"))
    }

    @MainActor
    func testPreparePasswordRecoveryFromAuthCallback() {
        let app = AppState.shared
        let priorTab = app.selectedTab
        let priorPending = app.passwordRecoveryPending
        let priorAuthenticated = app.isAuthenticated

        app.preparePasswordRecoveryFromAuthCallback()

        XCTAssertTrue(app.passwordRecoveryPending)
        XCTAssertEqual(app.selectedTab, .profile)
        XCTAssertFalse(app.isAuthenticated)
        XCTAssertNil(app.authCallbackError)

        app.passwordRecoveryPending = priorPending
        app.selectedTab = priorTab
        app.isAuthenticated = priorAuthenticated
    }
}
