import Foundation
import Testing
@testable import MedTrackerCore

struct DoseEngineTests {
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

    @Test
    func testFutureDosesDoNotBlockAndSimultaneousDosesMustBothResolve() throws {
        var state = TrackerState(now: date())
        _ = try add(&state, name: "First")
        _ = try add(&state, name: "Second")
        #expect(DoseEngine.due(state, now: date(10, 7, 59), calendar: calendar).isEmpty)
        let due = DoseEngine.due(state, now: date(10, 8), calendar: calendar)
        try #require(due.count == 2)
        DoseEngine.report(due[0].id, outcome: .taken, in: &state, now: date(10, 8), calendar: calendar)
        #expect(DoseEngine.due(state, now: date(10, 8), calendar: calendar).count == 1)
        DoseEngine.report(due[1].id, outcome: .skipped, in: &state, now: date(10, 8), calendar: calendar)
        #expect(DoseEngine.due(state, now: date(10, 8), calendar: calendar).isEmpty)
    }

    @Test
    func testMidnightMarksMissedAndDoesNotCarryBlockingForward() throws {
        var state = TrackerState(now: date())
        _ = try add(&state)
        DoseEngine.reconcile(&state, now: date(11), calendar: calendar)
        let yesterday = state.occurrences.filter { $0.day == "2026-10-10" }
        #expect(yesterday.count == 1)
        let missed = try #require(yesterday.first)
        #expect(missed.outcome == .missed)
        #expect(missed.reportedAt == nil)
        #expect(DoseEngine.due(state, now: date(11), calendar: calendar).isEmpty)
        #expect(DoseEngine.today(state, now: date(11), calendar: calendar).count == 1)
    }

    @Test
    func testMidnightDoseStillBlocksAfterRollover() throws {
        var state = TrackerState(now: date(10, 12))
        _ = try add(&state, times: [.init(hour: 0, minute: 0)], now: date(10, 12))
        DoseEngine.reconcile(&state, now: date(11), calendar: calendar)
        #expect(DoseEngine.due(state, now: date(11), calendar: calendar).count == 1)
    }

    @Test
    func testReopeningAfterSeveralDaysRecordsEachMissedDayOnce() throws {
        var state = TrackerState(now: date())
        _ = try add(&state)
        for _ in 0..<3 { DoseEngine.reconcile(&state, now: date(14, 9), calendar: calendar) }
        #expect(state.occurrences.filter { $0.outcome == .missed }.count == 4)
        #expect(DoseEngine.due(state, now: date(14, 9), calendar: calendar).count == 1)
        #expect(Set(state.occurrences.map(\.id)).count == state.occurrences.count)
    }

    @Test
    func testDuplicateReportsAreIdempotentAndFutureOrMissedDosesCannotBeReported() throws {
        var state = TrackerState(now: date())
        _ = try add(&state)
        let id = try #require(state.occurrences.first?.id)
        DoseEngine.report(id, outcome: .taken, in: &state, now: date(10, 7), calendar: calendar)
        #expect(state.occurrences.first?.outcome == nil)
        DoseEngine.report(id, outcome: .taken, in: &state, now: date(10, 8), calendar: calendar)
        DoseEngine.report(id, outcome: .skipped, in: &state, now: date(10, 9), calendar: calendar)
        #expect(state.occurrences.first?.outcome == .taken)
        #expect(state.occurrences.first?.reportedAt == date(10, 8))
        DoseEngine.reconcile(&state, now: date(12), calendar: calendar)
        let missed = try #require(state.occurrences.first { $0.outcome == .missed })
        DoseEngine.report(missed.id, outcome: .taken, in: &state, now: date(12), calendar: calendar)
        #expect(state.occurrences.first { $0.id == missed.id }?.outcome == .missed)
    }

    @Test
    func testEditsOnlyChangeFutureOccurrencesAndKeepHistoricalSnapshots() throws {
        var state = TrackerState(now: date())
        var medication = try add(&state, name: "Original", times: [.init(hour: 8, minute: 0), .init(hour: 18, minute: 0)])
        medication.name = "Edited"
        medication.times = [.init(hour: 10, minute: 0), .init(hour: 20, minute: 0)]
        try DoseEngine.upsert(medication, in: &state, now: date(10, 12), calendar: calendar)
        let today = DoseEngine.today(state, now: date(10, 12), calendar: calendar)
        try #require(today.count == 2)
        #expect(today[0].medicationName == "Original")
        #expect(today[0].time.hour == 8)
        #expect(today[1].medicationName == "Edited")
        #expect(today[1].time.hour == 20)
        DoseEngine.reconcile(&state, now: date(11, 12), calendar: calendar)
        #expect(DoseEngine.today(state, now: date(11, 12), calendar: calendar).map(\.time.hour) == [10, 20])
    }

    @Test
    func testDeletionCancelsUnresolvedDosesButPreservesRecordedHistory() throws {
        var state = TrackerState(now: date())
        let medication = try add(&state, times: [.init(hour: 8, minute: 0), .init(hour: 9, minute: 0), .init(hour: 18, minute: 0)])
        let first = try #require(state.occurrences.first)
        DoseEngine.report(first.id, outcome: .taken, in: &state, now: date(10, 8), calendar: calendar)
        DoseEngine.delete(medication.id, from: &state, now: date(10, 12), calendar: calendar)
        DoseEngine.reconcile(&state, now: date(13), calendar: calendar)
        #expect(state.medications.isEmpty)
        #expect(state.occurrences.count == 1)
        #expect(state.occurrences.first?.outcome == .taken)
    }

    @Test
    func testNewMedicationDoesNotCreateRetroactiveDoses() throws {
        var state = TrackerState(now: date(10, 12))
        _ = try add(&state, now: date(10, 12))
        #expect(state.occurrences.isEmpty)
        DoseEngine.reconcile(&state, now: date(11, 9), calendar: calendar)
        #expect(state.occurrences.count == 1)
    }

    @Test
    func testPausingDoesNotChangeDoseOutcomes() throws {
        var state = TrackerState(now: date())
        _ = try add(&state)
        state.preferences.blockingPaused = true
        DoseEngine.reconcile(&state, now: date(10, 9), calendar: calendar)
        #expect(DoseEngine.due(state, now: date(10, 9), calendar: calendar).count == 1)
        #expect(state.occurrences.first?.outcome == nil)
    }

    @Test(arguments: [(3, 29, 3), (10, 25, 2)])
    func testDSTSpringForwardAndAutumnRepeatedHourHaveOneDosePerDay(month: Int, day: Int, expectedHour: Int) throws {
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
        var state = TrackerState(now: midnight)
        let medication = Medication(name: "DST", times: [.init(hour: 2, minute: 30)], effectiveFrom: midnight)
        try DoseEngine.upsert(medication, in: &state, now: midnight, calendar: calendar)
        let noon = try #require(calendar.date(byAdding: .hour, value: 12, to: midnight))
        DoseEngine.reconcile(&state, now: noon, calendar: calendar)
        DoseEngine.reconcile(&state, now: noon, calendar: calendar)
        #expect(state.occurrences.count == 1)
        #expect(DoseEngine.due(state, now: noon, calendar: calendar).count == 1)
        let occurrence = try #require(state.occurrences.first)
        let hour = calendar.component(.hour, from: occurrence.scheduledAt)
        #expect(hour == expectedHour)
    }

    @Test
    func testTimeZoneChangeMovesPendingDosesToLocalTimeWithoutDuplicates() throws {
        var state = TrackerState(now: date())
        _ = try add(&state, times: [.init(hour: 18, minute: 0)])
        var newCalendar = calendar
        newCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = date(10, 16)
        DoseEngine.reconcile(&state, now: now, calendar: newCalendar)
        #expect(state.occurrences.count == 1)
        let occurrence = try #require(state.occurrences.first)
        #expect(newCalendar.component(.hour, from: occurrence.scheduledAt) == 18)
        #expect(DoseEngine.due(state, now: now, calendar: newCalendar).isEmpty)
    }

    @Test
    func testInvalidMedicationRejectedAndDuplicateTimesDeduplicated() throws {
        var state = TrackerState(now: date())
        #expect(throws: TrackerError.self) { try add(&state, name: "  ") }
        #expect(throws: TrackerError.self) { try add(&state, times: [.init(hour: 24, minute: 0)]) }
        _ = try add(&state, times: [.init(hour: 8, minute: 0), .init(hour: 8, minute: 0)])
        #expect(state.medications.first?.times.count == 1)
        #expect(state.occurrences.count == 1)
    }

    @Test(arguments: [
        (12, ["2026-10-12"]),
        (13, ["2026-10-12"]),
        (14, ["2026-10-12", "2026-10-14"])
    ])
    func testWeekdays(day: Int, expectedDays: [String]) throws {
        // Arrange: configure the medication on Sunday.
        let start = date(11)
        var state = TrackerState(now: start)

        let medication = Medication(
            name: "Example",
            times: [.init(hour: 8, minute: 0)],
            effectiveFrom: start,
            weekdays: [.monday, .wednesday, .friday]
        )

        try DoseEngine.upsert(
            medication,
            in: &state,
            now: start,
            calendar: calendar
        )

        // Act: simulate reopening at 09:00 on the supplied date.
        DoseEngine.reconcile(
            &state,
            now: date(day, 9),
            calendar: calendar
        )

        // Assert: only scheduled dates have occurrences.
        #expect(state.occurrences.map(\.day).sorted() == expectedDays)
    }
}
