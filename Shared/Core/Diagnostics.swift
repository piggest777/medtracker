import Foundation
import OSLog

/// Messages must contain only technical state and counts, never medication names or tokens.
enum Diagnostics {
    static let subsystem = "MedTracker"
    private static let eventBuffer = OSAllocatedUnfairLock(initialState: [String]())

    static func record(_ category: String, _ message: String) {
        let line = "\(Date().formatted(.iso8601)) [\(category)] \(message)"
        eventBuffer.withLock { events in
            events.append(line)
            if events.count > 200 { events.removeFirst(events.count - 200) }
        }
        Logger(subsystem: subsystem, category: category).notice("\(message, privacy: .public)")
    }

    static func recentEvents() -> String {
        eventBuffer.withLock { events in
            events.joined(separator: "\n")
        }
    }

    static func errorSummary(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) code=\(error.code)"
    }
}
