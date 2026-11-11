import XCTest
@testable import MedTrackerCore

final class UpdateGateTests: XCTestCase {
    @MainActor
    func testSelectionSaveWaitsForBusyRefreshAndOtherMutationsKeepSelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SharedStore(url: directory.appendingPathComponent("state.json"))
        let gate = UpdateGate()
        var committed: [String] = []
        await gate.enter() // A foreground refresh is still awaiting notification setup.

        let selectionSave = Task { @MainActor in
            await gate.enter()
            defer { gate.leave() }
            try store.transaction { $0.selectionData = Data([1, 2, 3]) }
            committed.append("selection")
        }
        await waitForPending(1, gate: gate)
        let preferenceSave = Task { @MainActor in
            await gate.enter()
            defer { gate.leave() }
            try store.transaction { $0.preferences.blockingPaused = true }
            committed.append("preference")
        }
        await waitForPending(2, gate: gate)
        XCTAssertTrue(committed.isEmpty)
        gate.leave()
        try await selectionSave.value
        try await preferenceSave.value

        XCTAssertEqual(committed, ["selection", "preference"])
        let stored = try store.read()
        XCTAssertEqual(stored.selectionData, Data([1, 2, 3]))
        XCTAssertTrue(stored.preferences.blockingPaused)
        XCTAssertFalse(gate.isOccupied)
    }

    @MainActor
    private func waitForPending(_ count: Int, gate: UpdateGate) async {
        for _ in 0..<1_000 {
            if gate.pendingCount == count { break }
            await Task.yield()
        }
        XCTAssertEqual(gate.pendingCount, count)
    }
}
