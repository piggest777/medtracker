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

extension AppEnvironment {
    @MainActor
    static func makeNotificationService() -> NotificationService {
        #if DEBUG && targetEnvironment(simulator)
        if isUITesting {
            Diagnostics.record("Notifications", "using in-memory notification center for UI testing; no system requests")
            return NotificationService(center: InMemoryNotificationCenter())
        }
        #endif
        return NotificationService()
    }
}
