import Foundation

/// Serializes asynchronous model updates without dropping user actions during an await.
@MainActor
final class UpdateGate {
    private(set) var isOccupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var pendingCount: Int { waiters.count }

    func enter() async {
        if !isOccupied {
            isOccupied = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func leave() {
        if waiters.isEmpty {
            isOccupied = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
