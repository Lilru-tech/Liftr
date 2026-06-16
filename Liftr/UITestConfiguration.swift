import UIKit

enum UITestConfiguration {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["UITESTING"] == "1"
    }

    static var autoSignInEnabled: Bool {
        ProcessInfo.processInfo.environment["UI_TEST_AUTO_SIGN_IN"] != "0"
    }

    static var testEmail: String? {
        let value = ProcessInfo.processInfo.environment["UI_TEST_EMAIL"] ?? ""
        return value.isEmpty ? nil : value
    }

    static var testPassword: String? {
        let value = ProcessInfo.processInfo.environment["UI_TEST_PASSWORD"] ?? ""
        return value.isEmpty ? nil : value
    }

    static func configureIfNeeded() {
        guard isEnabled else { return }
        UIView.setAnimationsEnabled(false)
    }
}
