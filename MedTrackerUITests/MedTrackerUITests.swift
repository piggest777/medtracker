import XCTest
import UserNotifications

final class MedTrackerUITests: XCTestCase {
    @MainActor
    func testTimeSensitiveAlertIsSavedToNotificationCenter() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing", "--seed-due-doses"]
        app.launch()
        XCTAssertTrue(app.staticTexts["2 due doses"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        let send = app.buttons["settings.test-alert"]
        for _ in 0..<5 {
            if send.isHittable { break }
            app.swipeUp()
        }
        send.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 30) { allow.tap() }
        let status = app.staticTexts["settings.test-alert-status"]
        guard status.waitForExistence(timeout: 30) else {
            XCTFail("Test alert did not succeed.\n\(app.debugDescription)")
            return
        }

        let diagnostics = app.buttons["settings.diagnostics"]
        for _ in 0..<5 {
            if diagnostics.isHittable { break }
            app.swipeUp()
        }
        diagnostics.tap()
        let report = app.staticTexts["diagnostics.report"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertTrue(report.label.contains("test alert readback interruptionLevel=\(UNNotificationInterruptionLevel.timeSensitive.rawValue)"))
    }

    @MainActor
    func testPracticeStartsWithoutMedicationAndCanSimulateNextDay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing"]
        app.launch()
        let start = app.buttons["onboarding.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        if !start.isHittable { app.swipeUp() }
        start.tap()
        app.buttons["Settings"].tap()
        let testMode = app.buttons["settings.test-mode"]
        for _ in 0..<5 {
            if testMode.isHittable { break }
            app.swipeUp()
        }
        testMode.tap()
        app.buttons["practice.start"].tap()
        XCTAssertTrue(app.staticTexts["2 practice doses due"].waitForExistence(timeout: 5))

        let nextDay = app.buttons["practice.next-day"]

        for _ in 0..<5 {
            if nextDay.exists && nextDay.isHittable { break }
            app.swipeUp()
        }
        guard nextDay.isHittable else {
            XCTFail("Simulate next day was not tappable after scrolling")
            return
        }
        nextDay.tap()
        XCTAssertTrue(app.descendants(matching: .any)["practice.complete"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["practice.due-now"].isEnabled)
        app.buttons["practice.due-now"].tap()
        XCTAssertTrue(app.staticTexts["2 practice doses due"].waitForExistence(timeout: 5))
        app.buttons["practice.end"].tap()
        XCTAssertTrue(app.buttons["practice.start"].waitForExistence(timeout: 5))
        app.buttons["Medications"].tap()
        XCTAssertTrue(app.staticTexts["No medications yet"].waitForExistence(timeout: 5))
        app.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["No check-ins yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPracticeModePersistsAndDoesNotRecordRealMedicationIntake() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing", "--seed-due-doses"]
        app.launch()
        XCTAssertTrue(app.staticTexts["2 due doses"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        let testMode = app.buttons["settings.test-mode"]
        for _ in 0..<5 {
            if testMode.isHittable { break }
            app.swipeUp()
        }
        testMode.tap()
        app.buttons["practice.start"].tap()
        XCTAssertTrue(app.staticTexts["2 practice doses due"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'practice.taken.'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1 practice dose due"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["practice.banner"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1 practice dose due"].exists)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'practice.skipped.'")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["practice.complete"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["practice.end-today"].tap()
        XCTAssertTrue(app.staticTexts["2 due doses"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["practice.banner"].firstMatch.exists)
        app.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["No check-ins yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSelectedAppRowsStayCompactAndStatusesRemainReadable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--selection-layout-preview"]
        app.launch()
        let row = app.descendants(matching: .any)["selection-preview.app"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertLessThan(row.frame.height, 90, "Hosted labels must not expand ordinary rows into tall cards.")
        XCTAssertTrue(app.staticTexts["Available"].isHittable)
        XCTAssertTrue(app.staticTexts["Blocked"].isHittable)
        XCTAssertTrue(app.staticTexts["Paused"].isHittable)
        let normal = XCTAttachment(screenshot: app.screenshot())
        normal.name = "Selected apps — dark mode"
        normal.lifetime = .keepAlways
        add(normal)

        app.terminate()
        app.launchArguments.append("--large-selection-preview")
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertLessThan(row.frame.height, 180, "Larger text should stack the badge under the app name without unbounded expansion.")
        XCTAssertTrue(app.staticTexts["Available"].isHittable)
        let large = XCTAttachment(screenshot: app.screenshot())
        large.name = "Selected apps — accessibility text"
        large.lifetime = .keepAlways
        add(large)
    }

    @MainActor
    func testDiagnosticsShowsDiskStateAndCanBeCopiedWithoutMedicationNames() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing", "--seed-due-doses"]
        app.launch()
        XCTAssertTrue(app.staticTexts["2 due doses"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        let diagnostics = app.buttons["settings.diagnostics"]
        for _ in 0..<5 {
            if diagnostics.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(diagnostics.isHittable)
        diagnostics.tap()
        let report = app.staticTexts["diagnostics.report"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertTrue(report.label.contains("In-memory selection:"))
        XCTAssertTrue(report.label.contains("On-disk selection:"))
        XCTAssertTrue(report.label.contains("[Storage]"))
        XCTAssertFalse(report.label.contains("First test medication"))
        XCTAssertFalse(report.label.contains("Second test medication"))
        for _ in 0..<3 { app.buttons["Refresh report"].tap() }
        // Redrawing the screen must not resubscribe to authorization and replay its value.
        XCTAssertEqual(report.label.components(separatedBy: "publisher changed status=").count - 1, 1)
        let copy = app.buttons["diagnostics.copy"]
        copy.tap()
        XCTAssertEqual(copy.label, "Copied")
    }

    @MainActor
    func testDueCheckInsAndHistoryPersist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing", "--seed-due-doses"]
        app.launch()
        XCTAssertTrue(app.staticTexts["2 due doses"].waitForExistence(timeout: 10))
        let taken = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dose.taken.'")).firstMatch
        taken.tap()
        XCTAssertTrue(app.staticTexts["1 due dose"].waitForExistence(timeout: 5))
        let skip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dose.skip.'")).firstMatch
        skip.tap()
        app.buttons["Record as Skipped"].tap()
        XCTAssertTrue(app.staticTexts["Skipped"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Taken"].exists)
        XCTAssertFalse(app.staticTexts["1 due dose"].exists)
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Taken"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Skipped"].exists)
    }

    @MainActor
    func testOnboardingMedicationPersistenceAndPause() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing"]
        app.launch()
        let start = app.buttons["onboarding.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        if !start.isHittable { app.swipeUp() }
        start.tap()
        app.buttons["Medications"].tap()
        app.buttons["medications.add"].tap()
        let name = app.textFields["medication.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Daily test medication")
        let dose = app.textFields["medication.dose"]
        dose.tap()
        dose.typeText("One tablet")
        app.buttons["medication.save"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Daily test medication").firstMatch.waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        let pause = app.switches["settings.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertTrue(pause.isEnabled)
        pause.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let isOn = NSPredicate(format: "value == '1'")
        expectation(for: isOn, evaluatedWith: pause)
        waitForExpectations(timeout: 5)
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["Medications"].tap()
        XCTAssertTrue(app.staticTexts["Daily test medication"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertEqual(app.switches["settings.pause"].value as? String, "1")
    }
}
