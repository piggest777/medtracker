import DeviceActivity
import Foundation
import OSLog

final class ActivityMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        Diagnostics.record("Monitor", "intervalDidStart callback")
        reconcile()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        Diagnostics.record("Monitor", "intervalDidEnd callback")
        // An interval ending does not mean a dose was resolved.
        reconcile()
    }

    private func reconcile() {
        do {
            let store = try AppEnvironment.makeStore()
            _ = try BlockingRuntime.reconcile(store: store)
            Diagnostics.record("Monitor", "reconciliation completed")
        } catch {
            Diagnostics.record("Monitor", "reconciliation failed: \(Diagnostics.errorSummary(error))")
            BlockingRuntime.clearShields()
            AppEnvironment.logger.error("Monitor reconciliation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
