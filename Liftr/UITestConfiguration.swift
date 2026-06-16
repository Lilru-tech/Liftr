import UIKit

enum UITestConfiguration {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["UITESTING"] == "1"
    }

    static func configureIfNeeded() {
        guard isEnabled else { return }
        UIView.setAnimationsEnabled(false)
    }
}
