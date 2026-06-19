import XCTest

struct RegisterPage {
    let app: XCUIApplication

    var screen: XCUIElement { app.otherElements["register.screen"] }
    var emailField: XCUIElement { app.textFields["register.email"] }
    var passwordField: XCUIElement { app.secureTextFields["register.password"] }
    var usernameField: XCUIElement { app.textFields["register.username"] }
    var submitButton: XCUIElement { app.buttons["register.submit"] }

    func waitForScreen(timeout: TimeInterval = UITestWait.network) {
        let candidates: [XCUIElement] = [
            screen,
            emailField,
            app.staticTexts["Create your account to start tracking your workouts."],
            app.buttons["Create account"],
        ]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if candidates.contains(where: { $0.exists }) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(false, "Register screen did not appear.")
    }

    func fillForm(email: String, password: String, username: String) {
        waitForScreen()
        emailField.clearAndTypeText(email)
        passwordField.clearAndTypeText(password)
        usernameField.clearAndTypeText(username)
    }

    func submitIfEnabled() {
        submitWhenEnabled()
    }

    func submitWhenEnabled(timeout: TimeInterval = UITestWait.network) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let candidates: [XCUIElement] = [
                submitButton,
                app.buttons["Create account"],
            ]
            if let button = candidates.first(where: { $0.exists && $0.isEnabled }) {
                button.tap()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Create account button did not become enabled.")
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
        if emailField.exists, (emailField.value as? String ?? "").isEmpty {
            emailField.clearAndTypeText(email)
        }
        app.toolbars.buttons["Done"].tapIfExists(timeout: 1)
        let deadline = Date().addingTimeInterval(UITestWait.network)
        while Date() < deadline {
            let candidates: [XCUIElement] = [
                submitButton,
                app.buttons["Send reset link"],
            ]
            if let button = candidates.first(where: { $0.exists && $0.isEnabled }) {
                button.tap()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Send reset link button did not become enabled.")
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

    func waitForScreen(timeout: TimeInterval = UITestWait.network) {
        app.swipeUp()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let candidates: [XCUIElement] = [
                screen,
                saveButton,
                app.buttons["Save"],
                app.staticTexts["GENERAL"],
                app.staticTexts["Type"],
            ]
            if candidates.contains(where: { $0.exists }) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertTrue(false, "Add workout screen did not appear.")
    }

    func scrollToTopOfForm() {
        let form = app.collectionViews["addWorkout.screen"]
        if form.waitForExistence(timeout: 2) {
            form.swipeDown()
            form.swipeDown()
        }
        for _ in 0..<3 {
            app.swipeDown()
        }
    }

    func selectWorkoutType(_ label: String) {
        scrollToTopOfForm()
        waitForScreen()
        let typeMenu = app.buttons["addWorkout.type"]
        if typeMenu.waitForExistence(timeout: UITestWait.standard) {
            typeMenu.tap()
        } else {
            let currentTypeButtons = ["Strength", "Cardio", "Sport"]
            var opened = false
            for typeLabel in currentTypeButtons {
                let button = app.buttons[typeLabel]
                if button.waitForExistence(timeout: 1) {
                    button.tap()
                    opened = true
                    break
                }
            }
            if !opened {
                let typeLabel = app.staticTexts.matching(
                    NSPredicate(format: "label == 'Type'")
                ).firstMatch
                XCTAssertTrue(typeLabel.waitForExistence(timeout: UITestWait.standard))
                typeLabel.tap()
            }
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
        for _ in 0..<4 {
            app.swipeUp()
        }
        let deadline = Date().addingTimeInterval(UITestWait.network)
        while Date() < deadline {
            let candidates: [XCUIElement] = [
                saveButton,
                app.buttons["Save"],
            ]
            if let save = candidates.first(where: { $0.exists && $0.isEnabled }) {
                save.tap()
                return
            }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Save button was not available.")
    }

    func enableFinishedWorkoutIfNeeded() {
        let finished = app.switches.matching(
            NSPredicate(format: "label CONTAINS[c] 'Finished'")
        ).firstMatch
        if finished.waitForExistence(timeout: UITestWait.standard) {
            finished.tap()
        }
    }

    func waitForSaveSuccess(timeout: TimeInterval = UITestWait.network) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if successBanner.exists { return }
            let published = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Workout published' OR label CONTAINS 'Workout planned'")
            ).firstMatch
            if published.exists { return }
            if app.otherElements["home.screen"].exists { return }
            if app.buttons["tab.home"].exists && app.buttons["tab.home"].isSelected { return }
            if app.otherElements["uitest.authenticated"].exists,
               !screen.exists,
               app.tabBars.firstMatch.exists {
                return
            }
            let saveError = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'error' OR label CONTAINS[c] 'failed' OR label CONTAINS[c] 'could not'")
            ).firstMatch
            if saveError.exists {
                XCTFail("Workout save showed an error: \(saveError.label)")
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(false, "Workout save success UI did not appear.")
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
        let ready = sheet.waitForExistence(timeout: UITestWait.network)
            || app.staticTexts["New Goal"].waitForExistence(timeout: UITestWait.network)
            || app.buttons["Create"].waitForExistence(timeout: UITestWait.network)
        XCTAssertTrue(ready, "New goal sheet did not open.")
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
        let candidates: [XCUIElement] = [
            screen,
            app.scrollViews.firstMatch,
            app.collectionViews.firstMatch,
            app.otherElements["uitest.authenticated"],
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Home'")).firstMatch,
        ]
        let deadline = Date().addingTimeInterval(timeout)
        var homeReady = false
        while Date() < deadline {
            if candidates.contains(where: { $0.exists }) {
                homeReady = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(homeReady, "Home screen did not appear.")
        let loading = app.progressIndicators.firstMatch
        if loading.waitForExistence(timeout: 2) {
            let finished = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: loading
            )
            _ = XCTWaiter().wait(for: [finished], timeout: timeout)
        }
    }
}
