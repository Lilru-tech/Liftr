import XCTest

class RegressionTestCase: XCTestCase {
    var app: LiftrUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if testRun?.hasBeenSkipped != true,
           let failureCount = testRun?.failureCount,
           failureCount > 0,
           let app {
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Failure screenshot — \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func step(_ name: String, block: () throws -> Void) rethrows {
        try XCTContext.runActivity(named: name) { _ in
            try block()
        }
    }

    func captureScreenshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
