import XCTest

final class LiftrUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("Launch screenshot test is not run in CI regression.")
        }

        guard UITestCredentials.isConfigured else {
            throw XCTSkip("UI test credentials are not configured for launch screenshot test.")
        }

        let app = LiftrUIApplication()
        app.launchForRegression()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
