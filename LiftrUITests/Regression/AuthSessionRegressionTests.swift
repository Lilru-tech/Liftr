import XCTest

final class AuthSessionRegressionTests: XCTestCase {
    private var app: LiftrUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = LiftrUIApplication()
        app.launchForRegression()
    }

    @MainActor
    func testSignInShowsAuthenticatedProfile() throws {
        let tabs = TabBarPage(app: app)
        let login = LoginPage(app: app)
        let profile = ProfilePage(app: app)

        tabs.selectProfile()
        profile.dismissUpdateBannerIfPresent()
        login.signInWithConfiguredCredentials()
        profile.waitForAuthenticatedProfile()
    }
}
