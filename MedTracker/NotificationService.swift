import Foundation
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            NotificationCenter.default.post(name: .openToday, object: nil)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

extension Notification.Name {
    static let openToday = Notification.Name("MedTracker.openToday")
}

enum NotificationService {
    static let testAlertIdentifier = "medtracker.test-alert"

    static func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func makeContent(title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        return content
    }

    static func timeSensitiveStatus() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
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

    static func sendTestAlert() async throws {
        let content = makeContent(title: "Test medication reminder", body: "This is a test alert from MedTracker. No medication is needed.")
        let request = UNNotificationRequest(identifier: testAlertIdentifier, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        let center = UNUserNotificationCenter.current()
        try await center.add(request)
        Diagnostics.record("Notifications", "test alert scheduled delaySeconds=5 interruptionLevel=\(content.interruptionLevel.rawValue)")
        if let saved = await center.pendingNotificationRequests().first(where: { $0.identifier == testAlertIdentifier }) {
            Diagnostics.record("Notifications", "test alert readback interruptionLevel=\(saved.content.interruptionLevel.rawValue)")
        }
    }

    static func configure(_ state: TrackerState) async throws -> String {
        guard !AppEnvironment.isUITesting else { return "Not requested" }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.filter { $0.identifier.hasPrefix("medtracker.") && $0.identifier != testAlertIdentifier }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ours)
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
                    let content = makeContent(title: "Time for a check-in", body: body)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: time.hour, minute: time.minute), repeats: true)
                    let request = UNNotificationRequest(identifier: "medtracker.\(medication.id).\(time.id)", content: content, trigger: trigger)
                    try await center.add(request)
                }
            }
        } catch {
            // Do not leave a partially installed schedule presented as fully enabled.
            let partial = await center.pendingNotificationRequests().filter {
                $0.identifier.hasPrefix("medtracker.") && $0.identifier != testAlertIdentifier
            }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: partial)
            throw error
        }
        return "Enabled"
    }
}
