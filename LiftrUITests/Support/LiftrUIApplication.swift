import XCTest

final class LiftrUIApplication: XCUIApplication {
    func launchForRegression() {
        let credentials = UITestCredentials.self
        XCTAssertTrue(
            credentials.isConfigured,
            "Missing UI test environment. Set SUPABASE_URL, SUPABASE_ANON_KEY, UI_TEST_EMAIL, and UI_TEST_PASSWORD."
        )

        launchEnvironment["UITESTING"] = "1"
        launchEnvironment["SUPABASE_URL"] = credentials.supabaseURL
        launchEnvironment["SUPABASE_ANON_KEY"] = credentials.supabaseAnonKey
        launchEnvironment["UI_TEST_EMAIL"] = credentials.email
        launchEnvironment["UI_TEST_PASSWORD"] = credentials.password
        launch()
    }
}

extension XCUIElement {
    @discardableResult
    func waitUntilExists(timeout: TimeInterval = 10) -> Bool {
        waitForExistence(timeout: timeout)
    }

    func tapIfExists(timeout: TimeInterval = 3) {
        guard waitForExistence(timeout: timeout) else { return }
        tap()
    }
}

enum UITestWait {
    static let standard: TimeInterval = 10
    static let network: TimeInterval = 20
}
