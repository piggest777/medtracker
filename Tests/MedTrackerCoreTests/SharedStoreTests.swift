import XCTest
@testable import MedTrackerCore

final class SharedStoreTests: XCTestCase {
    private var directory: URL!
    private var store: SharedStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = SharedStore(url: directory.appendingPathComponent("state.json"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testPersistenceAndPauseSurviveNewStoreInstance() throws {
        let now = Date()
        _ = try store.transaction(now: now) { state in
            state.preferences.blockingPaused = true
            state.preferences.revealMedicationNames = true
            state.selectionData = Data([1, 2, 3])
            try DoseEngine.upsert(Medication(name: "Persisted", times: [.init(hour: 8, minute: 0)], effectiveFrom: now), in: &state, now: now)
        }
        let reloaded = try SharedStore(url: store.url).transaction { _ in }
        XCTAssertTrue(reloaded.preferences.blockingPaused)
        XCTAssertTrue(reloaded.preferences.revealMedicationNames)
        XCTAssertEqual(reloaded.selectionData, Data([1, 2, 3]))
        XCTAssertEqual(reloaded.medications.first?.name, "Persisted")
    }

    func testCorruptDataIsNotOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corrupt = Data("unreadable".utf8)
        try corrupt.write(to: store.url)
        XCTAssertThrowsError(try store.transaction { $0.preferences.blockingPaused = true })
        XCTAssertEqual(try Data(contentsOf: store.url), corrupt)
    }

    func testReadbackForDiagnosticsDoesNotMutateState() throws {
        _ = try store.transaction { $0.selectionData = Data([1, 2, 3]) }
        let original = try Data(contentsOf: store.url)
        let readback = try store.read()
        XCTAssertEqual(readback.selectionData, Data([1, 2, 3]))
        XCTAssertEqual(try Data(contentsOf: store.url), original)
    }

    func testNewerSchemaIsNotOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var future = TrackerState()
        future.schemaVersion = 2
        let encoded = try JSONEncoder().encode(future)
        try encoded.write(to: store.url)
        XCTAssertThrowsError(try store.transaction { $0.preferences.blockingPaused = true })
        XCTAssertEqual(try Data(contentsOf: store.url), encoded)
    }

    func testIntakeAndMissedOutcomesSurviveRelaunch() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!
        let reportTime = start.addingTimeInterval(9 * 3600)
        _ = try store.transaction(now: start) { state in
            try DoseEngine.upsert(Medication(name: "Persisted", times: [.init(hour: 8, minute: 0), .init(hour: 12, minute: 0)],
                                             effectiveFrom: start), in: &state, now: start, calendar: calendar)
            let due = DoseEngine.due(state, now: reportTime, calendar: calendar)
            DoseEngine.report(try XCTUnwrap(due.first?.id), outcome: .taken, in: &state, now: reportTime, calendar: calendar)
        }
        let nextDay = start.addingTimeInterval(33 * 3600)
        let reloaded = try SharedStore(url: store.url).transaction(now: nextDay) {
            DoseEngine.reconcile(&$0, now: nextDay, calendar: calendar)
        }
        XCTAssertEqual(reloaded.occurrences.filter { $0.outcome == .taken }.count, 1)
        XCTAssertEqual(reloaded.occurrences.filter { $0.outcome == .missed }.count, 1)
        XCTAssertEqual(reloaded.occurrences.first { $0.outcome == .taken }?.reportedAt, reportTime)
        XCTAssertEqual(DoseEngine.due(reloaded, now: nextDay, calendar: calendar).count, 1)
    }

    func testThrowingMutationIsNotCommitted() throws {
        _ = try store.transaction { $0.preferences.blockingPaused = false }
        enum Failure: Error { case expected }
        XCTAssertThrowsError(try store.transaction { state in
            state.preferences.blockingPaused = true
            throw Failure.expected
        })
        let reloaded = try store.transaction { _ in }
        XCTAssertFalse(reloaded.preferences.blockingPaused)
    }

    func testAfterSaveSeesDurableCheckIn() throws {
        let expected = Date(timeIntervalSince1970: 1_000)
        var durable: TrackerState?
        _ = try store.transaction({ $0.lastReconciledAt = expected }, afterSave: { _ in
            durable = try? JSONDecoder().decode(TrackerState.self, from: Data(contentsOf: self.store.url))
        })
        XCTAssertEqual(durable?.lastReconciledAt, expected)
    }

    func testConcurrentTransactionsDoNotLoseUpdates() throws {
        let lock = NSLock()
        var errors: [Error] = []
        DispatchQueue.concurrentPerform(iterations: 30) { iteration in
            do {
                let peer = SharedStore(url: self.store.url)
                _ = try peer.transaction { state in
                    state.medications.append(Medication(name: "\(iteration)", times: [.init(hour: 8, minute: 0)], effectiveFrom: Date()))
                }
            } catch {
                lock.lock()
                errors.append(error)
                lock.unlock()
            }
        }
        XCTAssertTrue(errors.isEmpty)
        let state = try store.transaction { _ in }
        XCTAssertEqual(state.medications.count, 30)
    }
}
