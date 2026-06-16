import XCTest

struct RegisterPage {
    let app: XCUIApplication

    var screen: XCUIElement { app.otherElements["register.screen"] }
    var emailField: XCUIElement { app.textFields["register.email"] }
    var passwordField: XCUIElement { app.secureTextFields["register.password"] }
    var usernameField: XCUIElement { app.textFields["register.username"] }
    var submitButton: XCUIElement { app.buttons["register.submit"] }

    func waitForScreen(timeout: TimeInterval = UITestWait.standard) {
        let ready = screen.waitForExistence(timeout: timeout)
            || emailField.waitForExistence(timeout: timeout)
        XCTAssertTrue(ready, "Register screen did not appear.")
    }

    func fillForm(email: String, password: String, username: String) {
        waitForScreen()
        emailField.clearAndTypeText(email)
        passwordField.clearAndTypeText(password)
        usernameField.clearAndTypeText(username)
    }

    func submitIfEnabled() {
        XCTAssertTrue(submitButton.waitForExistence(timeout: UITestWait.standard))
        submitButton.tap()
    }
}

struct ForgotPasswordPage {
    let app: XCUIApplication

    var screen: XCUIElement { app.otherElements["forgotPassword.screen"] }
    var emailField: XCUIElement { app.textFields["forgotPassword.email"] }
    var submitButton: XCUIElement { app.buttons["forgotPassword.submit"] }

    func waitForScreen(timeout: TimeInterval = UITestWait.standard) {
        let ready = screen.waitForExistence(timeout: timeout)
            || app.navigationBars["Forgot password"].waitForExistence(timeout: timeout)
        XCTAssertTrue(ready, "Forgot password screen did not appear.")
    }

    func submitEmail(_ email: String) {
        waitForScreen()
        emailField.clearAndTypeText(email)
        XCTAssertTrue(submitButton.waitForExistence(timeout: UITestWait.standard))
        XCTAssertTrue(submitButton.isEnabled, "Send reset link stayed disabled.")
        submitButton.tap()
    }

    func waitForSubmissionResult(timeout: TimeInterval = UITestWait.network) {
        let successText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'reset link'")
        ).firstMatch
        let errorText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'error' OR label CONTAINS[c] 'failed'")
        ).firstMatch
        _ = successText.waitForExistence(timeout: timeout) || errorText.waitForExistence(timeout: timeout)
    }
}

struct AddWorkoutPage {
    let app: XCUIApplication

    var screen: XCUIElement { app.otherElements["addWorkout.screen"] }
    var saveButton: XCUIElement { app.buttons["addWorkout.save"] }
    var successBanner: XCUIElement { app.otherElements["addWorkout.success"] }

    func waitForScreen(timeout: TimeInterval = UITestWait.standard) {
        let ready = screen.waitForExistence(timeout: timeout)
            || saveButton.waitForExistence(timeout: timeout)
        XCTAssertTrue(ready, "Add workout screen did not appear.")
    }

    func selectWorkoutType(_ label: String) {
        waitForScreen()
        let typeMenu = app.buttons["addWorkout.type"]
        if typeMenu.waitForExistence(timeout: 2) {
            typeMenu.tap()
        } else if app.buttons["Strength"].waitForExistence(timeout: 2) {
            app.buttons["Strength"].tap()
        } else {
            app.staticTexts["Type"].firstMatch.tap()
        }
        let option = app.buttons[label]
        if option.waitForExistence(timeout: UITestWait.standard) {
            option.tap()
            return
        }
        let menuItem = app.menuItems[label]
        XCTAssertTrue(menuItem.waitForExistence(timeout: UITestWait.standard), "Workout type \(label) not found.")
        menuItem.tap()
    }

    func pickFirstExercise() {
        let choose = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Choose exercise' OR label CONTAINS 'Loading exercises'")
        ).firstMatch
        if choose.waitForExistence(timeout: UITestWait.standard) {
            choose.tap()
        } else {
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'Choose exercise'")).firstMatch.tap()
        }
        let firstRow = app.otherElements["exercisePicker.firstRow"]
        if firstRow.waitForExistence(timeout: UITestWait.network) {
            firstRow.tap()
            return
        }
        let firstCell = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstCell.waitForExistence(timeout: UITestWait.network), "Exercise picker row not found.")
        firstCell.tap()
    }

    func enterRepsForFirstSet(_ reps: String) {
        let repsField = app.textFields.matching(
            NSPredicate(format: "placeholderValue == '—' OR label CONTAINS 'Reps'")
        ).firstMatch
        if repsField.waitForExistence(timeout: UITestWait.standard) {
            repsField.tap()
            repsField.typeText(reps)
            return
        }
        let numericField = app.textFields.element(boundBy: 0)
        XCTAssertTrue(numericField.waitForExistence(timeout: UITestWait.standard))
        numericField.tap()
        numericField.typeText(reps)
    }

    func saveWorkout() {
        app.swipeUp()
        XCTAssertTrue(saveButton.waitForExistence(timeout: UITestWait.standard))
        XCTAssertTrue(saveButton.isEnabled, "Save button stayed disabled.")
        saveButton.tap()
    }

    func waitForSaveSuccess(timeout: TimeInterval = UITestWait.network) {
        if successBanner.waitForExistence(timeout: timeout) { return }
        let published = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Workout published'")
        ).firstMatch
        XCTAssertTrue(published.waitForExistence(timeout: timeout), "Workout save success UI did not appear.")
    }
}

struct GoalsPage {
    let app: XCUIApplication

    var screen: XCUIElement { app.otherElements["goals.screen"] }
    var createButton: XCUIElement { app.buttons["goals.create"] }
    var sheet: XCUIElement { app.otherElements["goals.sheet"] }
    var targetField: XCUIElement { app.textFields["goals.target"] }
    var submitButton: XCUIElement { app.buttons["goals.submit"] }

    func waitForScreen(timeout: TimeInterval = UITestWait.network) {
        let ready = screen.waitForExistence(timeout: timeout)
            || app.navigationBars["My Goals"].waitForExistence(timeout: timeout)
        XCTAssertTrue(ready, "Goals screen did not appear.")
    }

    func openCreateSheet() {
        XCTAssertTrue(createButton.waitForExistence(timeout: UITestWait.standard))
        createButton.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: UITestWait.standard), "New goal sheet did not open.")
    }

    func createWeeklyWorkoutsGoal(target: String = "3") {
        openCreateSheet()
        if targetField.waitForExistence(timeout: UITestWait.standard) {
            targetField.tap()
            targetField.clearAndTypeText(target)
        }
        let createEnabled = submitButton.waitForExistence(timeout: UITestWait.network)
        if createEnabled, submitButton.isEnabled {
            submitButton.tap()
            return
        }
        let createLabel = app.buttons["Create"]
        XCTAssertTrue(createLabel.waitForExistence(timeout: UITestWait.network))
        XCTAssertTrue(createLabel.isEnabled, "Create goal button stayed disabled.")
        createLabel.tap()
    }

    func waitForGoalTitle(_ title: String, timeout: TimeInterval = UITestWait.network) {
        XCTAssertTrue(
            app.staticTexts[title].waitForExistence(timeout: timeout),
            "Goal '\(title)' did not appear in the list."
        )
    }
}

struct HomePage {
    let app: XCUIApplication

    var screen: XCUIElement { app.otherElements["home.screen"] }

    func waitForFeedLoaded(timeout: TimeInterval = UITestWait.network) {
        XCTAssertTrue(screen.waitForExistence(timeout: UITestWait.standard), "Home screen did not appear.")
        let loading = app.progressIndicators.firstMatch
        if loading.waitForExistence(timeout: 2) {
            let finished = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: loading
            )
            _ = XCTWaiter().wait(for: [finished], timeout: timeout)
        }
        let feedReady = app.tables.firstMatch.waitForExistence(timeout: timeout)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'workout' OR label CONTAINS 'Follow people' OR label CONTAINS 'activity'")
            ).firstMatch.waitForExistence(timeout: timeout)
        XCTAssertTrue(feedReady, "Home feed did not finish loading.")
    }
}
