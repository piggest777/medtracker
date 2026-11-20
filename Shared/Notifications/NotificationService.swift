import Foundation
import UserNotifications

@MainActor
struct NotificationService {
    static let testAlertIdentifier = "medtracker.test-alert"
    private let center: any NotificationCenterClient

    init(center: any NotificationCenterClient = SystemNotificationCenter()) {
        self.center = center
    }

    func requestPermission() async throws -> Bool {
        Diagnostics.record("Notifications", "authorization request started options=alert,sound")
        do {
            let granted = try await center.requestAuthorization()
            Diagnostics.record("Notifications", "authorization request completed granted=\(granted)")
            return granted
        } catch {
            Diagnostics.record("Notifications", "authorization request failed: \(Diagnostics.errorSummary(error))")
            throw error
        }
    }

    static func makeContent(title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        return content
    }

    func timeSensitiveStatus() async -> String {
        Diagnostics.record("Notifications", "notification settings request started source=time-sensitive-status")
        let settings = await center.settings()
        Diagnostics.record("Notifications", "authorization=\(settings.authorizationStatus.rawValue) timeSensitiveSetting=\(settings.timeSensitiveSetting.rawValue) soundSetting=\(settings.soundSetting.rawValue)")
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return settings.authorizationStatus == .notDetermined ? "Not requested" : "Notifications disabled"
        }
        switch settings.timeSensitiveSetting {
        case .enabled: return "Enabled"
        case .disabled: return "Disabled in iOS Settings"
        case .notSupported: return "Unavailable"
        @unknown default: return "Unavailable"
        }
    }

    func sendTestAlert() async throws {
        let content = Self.makeContent(title: "Test medication reminder", body: "This is a test alert from MedTracker. No medication is needed.")
        let request = UNNotificationRequest(identifier: Self.testAlertIdentifier, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        Diagnostics.record("Notifications", "test alert add started delaySeconds=5 interruptionLevel=\(content.interruptionLevel.rawValue)")
        try await center.add(request)
        Diagnostics.record("Notifications", "test alert scheduled delaySeconds=5 interruptionLevel=\(content.interruptionLevel.rawValue)")
        Diagnostics.record("Notifications", "test alert pending request readback started")
        let pending = await center.pendingRequests()
        Diagnostics.record("Notifications", "test alert pending request readback completed requestCount=\(pending.count)")
        if let saved = pending.first(where: { $0.identifier == Self.testAlertIdentifier }) {
            Diagnostics.record("Notifications", "test alert readback interruptionLevel=\(saved.content.interruptionLevel.rawValue)")
        }
    }

    func configure(_ state: TrackerState) async throws -> String {
        let settings = await center.settings()
        let pending = await center.pendingRequests()
        let ours = pending.filter { $0.identifier.hasPrefix("medtracker.") && $0.identifier != Self.testAlertIdentifier }.map(\.identifier)
        center.removePendingRequests(withIdentifiers: ours)
        guard state.preferences.notificationsEnabled else { return "Off" }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return settings.authorizationStatus == .notDetermined ? "Not requested" : "Disabled in iOS Settings"
        }
        do {
            for medication in state.medications {
                for time in medication.times {
                    let body = state.preferences.revealMedicationNames
                        ? "Review your reminder for \(medication.name)."
                        : "Open MedTracker to review your medication reminder."
                    let content = Self.makeContent(title: "Time for a check-in", body: body)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: time.hour, minute: time.minute), repeats: true)
                    let request = UNNotificationRequest(identifier: "medtracker.\(medication.id).\(time.id)", content: content, trigger: trigger)
                    try await center.add(request)
                }
            }
        } catch {
            // Do not leave a partially installed schedule presented as fully enabled.
            let partial = await center.pendingRequests().filter {
                $0.identifier.hasPrefix("medtracker.") && $0.identifier != Self.testAlertIdentifier
            }.map(\.identifier)
            center.removePendingRequests(withIdentifiers: partial)
            throw error
        }
        return "Enabled"
    }
}
