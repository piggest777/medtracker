import Foundation

/// One coordinated read/modify/write operation across app and extension processes.
/// A decoding error is surfaced, never treated as an empty store.
final class SharedStore {
    private static let processLock = NSLock()
    let url: URL

    init(url: URL) { self.url = url }

    func read(now: Date = Date()) throws -> TrackerState {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        var coordinationError: NSError?
        var result: Result<TrackerState, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try self.decode(at: url, now: now) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    private func decode(at url: URL, now: Date) throws -> TrackerState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Diagnostics.record("Storage", "state file missing; creating initial state")
            return TrackerState(now: now)
        }
        do {
            let data = try Data(contentsOf: url)
            let state = try JSONDecoder().decode(TrackerState.self, from: data)
            guard state.schemaVersion == 1 else { throw TrackerError.unsupportedSchema }
            Diagnostics.record("Storage", "loaded stateBytes=\(data.count) selectionBytes=\(state.selectionData?.count ?? 0)")
            return state
        } catch {
            Diagnostics.record("Storage", "load failed: \(Diagnostics.errorSummary(error))")
            throw error
        }
    }

    @discardableResult
    func transaction(now: Date = Date(), _ change: (inout TrackerState) throws -> Void,
                     afterSave: ((TrackerState) -> Void)? = nil) throws -> TrackerState {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<TrackerState, Error>?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            result = Result {
                var state = try self.decode(at: coordinatedURL, now: now)
                try change(&state)
                let encoded = try JSONEncoder().encode(state)
                #if os(iOS)
                try encoded.write(to: coordinatedURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                #else
                try encoded.write(to: coordinatedURL, options: .atomic)
                #endif
                Diagnostics.record("Storage", "committed stateBytes=\(encoded.count) selectionBytes=\(state.selectionData?.count ?? 0)")
                // Shield updates happen while still coordinated, after the check-in is durable.
                afterSave?(state)
                return state
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
