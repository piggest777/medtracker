import XCTest
@testable import MedTrackerCore

final class PracticeSessionTests: XCTestCase {
    func testTwoImmediateDosesMustBothResolve() throws {
        var practice = PracticeSession()
        XCTAssertEqual(practice.pendingCount, 2)
        let first = practice.currentDoses[0]
        let second = practice.currentDoses[1]
        practice.record(first.id, outcome: .taken)
        XCTAssertEqual(practice.pendingCount, 1)
        practice.record(second.id, outcome: .skipped)
        XCTAssertEqual(practice.pendingCount, 0)
        XCTAssertEqual(practice.history.map(\.outcome), [.skipped, .taken])
    }

    func testReportsAreIdempotentAndCannotInventMissedOutcomes() {
        var practice = PracticeSession()
        let first = practice.currentDoses[0]
        practice.record(first.id, outcome: .missed)
        XCTAssertEqual(practice.pendingCount, 2)
        practice.record(first.id, outcome: .taken)
        practice.record(first.id, outcome: .skipped)
        XCTAssertEqual(practice.doses.first?.outcome, .taken)
        XCTAssertEqual(practice.pendingCount, 1)
    }

    func testSimulatedMidnightMarksMissedAndResetsBlockingWithoutAdvancingRealClock() {
        var practice = PracticeSession()
        let yesterday = practice.currentDoses[0]
        practice.advanceDay()
        XCTAssertEqual(practice.day, 2)
        XCTAssertEqual(practice.history.filter { $0.outcome == .missed }.count, 2)
        XCTAssertEqual(practice.pendingCount, 0)
        XCTAssertTrue(practice.currentDoses.isEmpty)
        practice.record(yesterday.id, outcome: .taken)
        XCTAssertEqual(practice.history.filter { $0.outcome == .missed }.count, 2)
        practice.makeDosesDue()
        practice.makeDosesDue() // Repeated taps must not duplicate pending doses.
        XCTAssertEqual(practice.pendingCount, 2)
        XCTAssertEqual(practice.doses.count, 4)
        XCTAssertTrue(practice.currentDoses.allSatisfy { $0.day == 2 })
    }

    func testReplayingShowsFreshDosesAndRetainsPracticeHistory() {
        var practice = PracticeSession()
        for dose in practice.currentDoses { practice.record(dose.id, outcome: .taken) }
        let completedIDs = Set(practice.currentDoses.map(\.id))
        practice.makeDosesDue()
        XCTAssertEqual(practice.pendingCount, 2)
        XCTAssertEqual(practice.history.count, 2)
        XCTAssertTrue(completedIDs.isDisjoint(with: practice.currentDoses.map(\.id)))
    }

    func testPracticeIsIsolatedAndEndingRestoresRealBlockingDemand() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!
        let now = start.addingTimeInterval(9 * 3_600)
        var state = TrackerState(now: start)
        try DoseEngine.upsert(Medication(name: "Real medication", times: [.init(hour: 8, minute: 0)], effectiveFrom: start),
                              in: &state, now: start, calendar: calendar)
        DoseEngine.reconcile(&state, now: now, calendar: calendar)
        let realOccurrences = state.occurrences
        let realMedications = state.medications
        let preferences = state.preferences
        state.selectionData = Data([1, 2, 3])
        XCTAssertEqual(BlockingDemand.dueCount(state, now: now, calendar: calendar), 1)
        state.practiceSession = PracticeSession()
        XCTAssertEqual(BlockingDemand.dueCount(state, now: now, calendar: calendar), 2)
        for dose in state.practiceSession!.currentDoses { state.practiceSession?.record(dose.id, outcome: .taken) }
        XCTAssertEqual(BlockingDemand.dueCount(state, now: now, calendar: calendar), 0)
        state.practiceSession?.advanceDay()
        XCTAssertEqual(state.lastReconciledAt, now)
        state.practiceSession = nil
        XCTAssertEqual(BlockingDemand.dueCount(state, now: now, calendar: calendar), 1)
        XCTAssertEqual(state.occurrences, realOccurrences)
        XCTAssertEqual(state.medications, realMedications)
        XCTAssertEqual(state.preferences, preferences)
        XCTAssertEqual(state.selectionData, Data([1, 2, 3]))
        XCTAssertTrue(state.occurrences.allSatisfy { $0.outcome == nil })
    }

    func testPracticePersistsAndOlderStateWithoutPracticeStillDecodes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SharedStore(url: directory.appendingPathComponent("state.json"))
        let saved = try store.transaction { $0.practiceSession = PracticeSession() }
        let reloaded = try SharedStore(url: store.url).read()
        XCTAssertEqual(reloaded.practiceSession, saved.practiceSession)
        XCTAssertEqual(reloaded.practiceSession?.pendingCount, 2)
        XCTAssertTrue(reloaded.medications.isEmpty)
        XCTAssertTrue(reloaded.occurrences.isEmpty)

        var original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        original.removeValue(forKey: "practiceSession")
        let oldData = try JSONSerialization.data(withJSONObject: original)
        let olderState = try JSONDecoder().decode(TrackerState.self, from: oldData)
        XCTAssertNil(olderState.practiceSession)
        XCTAssertEqual(olderState.schemaVersion, 1)
    }
}
