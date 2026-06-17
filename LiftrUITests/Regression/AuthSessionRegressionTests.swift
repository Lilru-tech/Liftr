import XCTest

final class AuthSessionRegressionTests: RegressionTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        app = LiftrUIApplication()
        app.launchForRegression(autoSignIn: false)
    }

    @MainActor
    func testSignInShowsAuthenticatedProfile() throws {
        let tabs = TabBarPage(app: app)
        let login = LoginPage(app: app)
        let profile = ProfilePage(app: app)

        try step("Open profile tab") {
            tabs.selectProfile()
            profile.dismissUpdateBannerIfPresent()
        }
        try step("Sign in with configured credentials") {
            login.signInWithConfiguredCredentials()
        }
        try step("Wait for authenticated profile") {
            profile.waitForAuthenticatedProfile()
        }
    }
}
