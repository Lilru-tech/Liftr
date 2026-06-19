import XCTest

final class ProfileMenuRegressionTests: RegressionTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        app = LiftrUIApplication()
        app.launchForRegression()
    }

    @MainActor
    func testProfileMenuOpensGoalsAndAchievements() throws {
        let tabs = TabBarPage(app: app)
        let profile = ProfilePage(app: app)
        let goals = GoalsPage(app: app)

        try step("Open goals from profile menu") {
            tabs.selectProfile()
            profile.dismissUpdateBannerIfPresent()
            profile.waitForAuthenticatedProfile()
            profile.openGoalsFromMenu()
            goals.waitForScreen()
        }

        try step("Navigate back to profile") {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        try step("Open achievements from profile menu") {
            profile.openAchievementsFromMenu()
            XCTAssertTrue(
                app.navigationBars.matching(
                    NSPredicate(format: "identifier CONTAINS 'Achievements' OR label CONTAINS 'Achievements'")
                ).firstMatch.waitForExistence(timeout: UITestWait.network)
                    || app.staticTexts.matching(
                        NSPredicate(format: "label CONTAINS 'Achievements'")
                    ).firstMatch.waitForExistence(timeout: UITestWait.network)
            )
        }
    }
}
