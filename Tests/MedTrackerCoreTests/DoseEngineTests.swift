import XCTest
@testable import MedTrackerCore

final class DoseEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }

    private func date(_ day: Int = 10, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func add(_ state: inout TrackerState, name: String = "Example", times: [DailyTime] = [.init(hour: 8, minute: 0)],
                     now: Date? = nil) throws -> Medication {
        let timestamp = now ?? date()
        let med = Medication(name: name, dose: "One tablet", times: times, effectiveFrom: timestamp)
        try DoseEngine.upsert(med, in: &state, now: timestamp, calendar: calendar)
        return med
    }

    func testFutureDosesDoNotBlockAndSimultaneousDosesMustBothResolve() throws {
        var state = TrackerState(now: date())
        _ = try add(&state, name: "First")
        _ = try add(&state, name: "Second")
        XCTAssertTrue(DoseEngine.due(state, now: date(10, 7, 59), calendar: calendar).isEmpty)
        let due = DoseEngine.due(state, now: date(10, 8), calendar: calendar)
        XCTAssertEqual(due.count, 2)
        DoseEngine.report(due[0].id, outcome: .taken, in: &state, now: date(10, 8), calendar: calendar)
        XCTAssertEqual(DoseEngine.due(state, now: date(10, 8), calendar: calendar).count, 1)
        DoseEngine.report(due[1].id, outcome: .skipped, in: &state, now: date(10, 8), calendar: calendar)
        XCTAssertTrue(DoseEngine.due(state, now: date(10, 8), calendar: calendar).isEmpty)
    }

    func testMidnightMarksMissedAndDoesNotCarryBlockingForward() throws {
        var state = TrackerState(now: date())
        _ = try add(&state)
        DoseEngine.reconcile(&state, now: date(11), calendar: calendar)
        let yesterday = state.occurrences.filter { $0.day == "2026-10-10" }
        XCTAssertEqual(yesterday.count, 1)
        XCTAssertEqual(yesterday.first?.outcome, .missed)
        XCTAssertNil(yesterday.first?.reportedAt)
        XCTAssertTrue(DoseEngine.due(state, now: date(11), calendar: calendar).isEmpty)
        XCTAssertEqual(DoseEngine.today(state, now: date(11), calendar: calendar).count, 1)
    }

    func testMidnightDoseStillBlocksAfterRollover() throws {
        var state = TrackerState(now: date(10, 12))
        _ = try add(&state, times: [.init(hour: 0, minute: 0)], now: date(10, 12))
        DoseEngine.reconcile(&state, now: date(11), calendar: calendar)
        XCTAssertEqual(DoseEngine.due(state, now: date(11), calendar: calendar).count, 1)
    }

    func testReopeningAfterSeveralDaysRecordsEachMissedDayOnce() throws {
        var state = TrackerState(now: date())
        _ = try add(&state)
        for _ in 0..<3 { DoseEngine.reconcile(&state, now: date(14, 9), calendar: calendar) }
        XCTAssertEqual(state.occurrences.filter { $0.outcome == .missed }.count, 4)
        XCTAssertEqual(DoseEngine.due(state, now: date(14, 9), calendar: calendar).count, 1)
        XCTAssertEqual(Set(state.occurrences.map(\.id)).count, state.occurrences.count)
    }

    func testDuplicateReportsAreIdempotentAndFutureOrMissedDosesCannotBeReported() throws {
        var state = TrackerState(now: date())
        _ = try add(&state)
        let id = try XCTUnwrap(state.occurrences.first?.id)
        DoseEngine.report(id, outcome: .taken, in: &state, now: date(10, 7), calendar: calendar)
        XCTAssertNil(state.occurrences.first?.outcome)
        DoseEngine.report(id, outcome: .taken, in: &state, now: date(10, 8), calendar: calendar)
        DoseEngine.report(id, outcome: .skipped, in: &state, now: date(10, 9), calendar: calendar)
        XCTAssertEqual(state.occurrences.first?.outcome, .taken)
        XCTAssertEqual(state.occurrences.first?.reportedAt, date(10, 8))
        DoseEngine.reconcile(&state, now: date(12), calendar: calendar)
        let missed = try XCTUnwrap(state.occurrences.first { $0.outcome == .missed })
        DoseEngine.report(missed.id, outcome: .taken, in: &state, now: date(12), calendar: calendar)
        XCTAssertEqual(state.occurrences.first { $0.id == missed.id }?.outcome, .missed)
    }

    func testEditsOnlyChangeFutureOccurrencesAndKeepHistoricalSnapshots() throws {
        var state = TrackerState(now: date())
        var medication = try add(&state, name: "Original", times: [.init(hour: 8, minute: 0), .init(hour: 18, minute: 0)])
        medication.name = "Edited"
        medication.times = [.init(hour: 10, minute: 0), .init(hour: 20, minute: 0)]
        try DoseEngine.upsert(medication, in: &state, now: date(10, 12), calendar: calendar)
        let today = DoseEngine.today(state, now: date(10, 12), calendar: calendar)
        XCTAssertEqual(today.count, 2)
        XCTAssertEqual(today[0].medicationName, "Original")
        XCTAssertEqual(today[0].time.hour, 8)
        XCTAssertEqual(today[1].medicationName, "Edited")
        XCTAssertEqual(today[1].time.hour, 20)
        DoseEngine.reconcile(&state, now: date(11, 12), calendar: calendar)
        XCTAssertEqual(DoseEngine.today(state, now: date(11, 12), calendar: calendar).map(\.time.hour), [10, 20])
    }

    func testDeletionCancelsUnresolvedDosesButPreservesRecordedHistory() throws {
        var state = TrackerState(now: date())
        let medication = try add(&state, times: [.init(hour: 8, minute: 0), .init(hour: 9, minute: 0), .init(hour: 18, minute: 0)])
        let first = try XCTUnwrap(state.occurrences.first)
        DoseEngine.report(first.id, outcome: .taken, in: &state, now: date(10, 8), calendar: calendar)
        DoseEngine.delete(medication.id, from: &state, now: date(10, 12), calendar: calendar)
        DoseEngine.reconcile(&state, now: date(13), calendar: calendar)
        XCTAssertTrue(state.medications.isEmpty)
        XCTAssertEqual(state.occurrences.count, 1)
        XCTAssertEqual(state.occurrences.first?.outcome, .taken)
    }

    func testNewMedicationDoesNotCreateRetroactiveDoses() throws {
        var state = TrackerState(now: date(10, 12))
        _ = try add(&state, now: date(10, 12))
        XCTAssertTrue(state.occurrences.isEmpty)
        DoseEngine.reconcile(&state, now: date(11, 9), calendar: calendar)
        XCTAssertEqual(state.occurrences.count, 1)
    }

    func testPausingDoesNotChangeDoseOutcomes() throws {
        var state = TrackerState(now: date())
        _ = try add(&state)
        state.preferences.blockingPaused = true
        DoseEngine.reconcile(&state, now: date(10, 9), calendar: calendar)
        XCTAssertEqual(DoseEngine.due(state, now: date(10, 9), calendar: calendar).count, 1)
        XCTAssertNil(state.occurrences.first?.outcome)
    }

    func testDSTSpringForwardAndAutumnRepeatedHourHaveOneDosePerDay() throws {
        for components in [DateComponents(year: 2026, month: 3, day: 29), DateComponents(year: 2026, month: 10, day: 25)] {
            let midnight = calendar.date(from: components)!
            var state = TrackerState(now: midnight)
            let medication = Medication(name: "DST", times: [.init(hour: 2, minute: 30)], effectiveFrom: midnight)
            try DoseEngine.upsert(medication, in: &state, now: midnight, calendar: calendar)
            let noon = calendar.date(byAdding: .hour, value: 12, to: midnight)!
            DoseEngine.reconcile(&state, now: noon, calendar: calendar)
            DoseEngine.reconcile(&state, now: noon, calendar: calendar)
            XCTAssertEqual(state.occurrences.count, 1)
            XCTAssertEqual(DoseEngine.due(state, now: noon, calendar: calendar).count, 1)
            let hour = calendar.component(.hour, from: state.occurrences[0].scheduledAt)
            XCTAssertEqual(hour, components.month == 3 ? 3 : 2)
        }
    }

    func testTimeZoneChangeMovesPendingDosesToLocalTimeWithoutDuplicates() throws {
        var state = TrackerState(now: date())
        _ = try add(&state, times: [.init(hour: 18, minute: 0)])
        var newCalendar = calendar
        newCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = date(10, 16)
        DoseEngine.reconcile(&state, now: now, calendar: newCalendar)
        XCTAssertEqual(state.occurrences.count, 1)
        XCTAssertEqual(newCalendar.component(.hour, from: state.occurrences[0].scheduledAt), 18)
        XCTAssertTrue(DoseEngine.due(state, now: now, calendar: newCalendar).isEmpty)
    }

    func testInvalidMedicationRejectedAndDuplicateTimesDeduplicated() throws {
        var state = TrackerState(now: date())
        XCTAssertThrowsError(try add(&state, name: "  "))
        XCTAssertThrowsError(try add(&state, times: [.init(hour: 24, minute: 0)]))
        _ = try add(&state, times: [.init(hour: 8, minute: 0), .init(hour: 8, minute: 0)])
        XCTAssertEqual(state.medications.first?.times.count, 1)
        XCTAssertEqual(state.occurrences.count, 1)
    }
}
