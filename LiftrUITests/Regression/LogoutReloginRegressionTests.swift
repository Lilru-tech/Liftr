import XCTest

final class LogoutReloginRegressionTests: RegressionTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        app = LiftrUIApplication()
        app.launchForRegression()
    }

    @MainActor
    func testLogoutAndSignInAgain() throws {
        let tabs = TabBarPage(app: app)
        let profile = ProfilePage(app: app)
        let login = LoginPage(app: app)

        try step("Sign out from settings") {
            tabs.selectProfile()
            profile.dismissUpdateBannerIfPresent()
            profile.waitForAuthenticatedProfile()
            profile.signOutFromSettings()
        }

        try step("Sign in again manually") {
            tabs.selectProfile()
            login.signIn(email: UITestCredentials.email, password: UITestCredentials.password)
            profile.waitForAuthenticatedProfile()
        }
    }
}
