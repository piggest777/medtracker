#if DEBUG && targetEnvironment(simulator)
import UserNotifications

/// Used by tests only; requests stay in memory and never reach iOS.
@MainActor
final class InMemoryNotificationCenter: NotificationCenterClient {
    var authorizationGranted = true
    var schedulingError: (any Error)?
    var notificationSettings = NotificationSettings(authorizationStatus: .notDetermined,
                                                    timeSensitiveSetting: .disabled,
                                                    soundSetting: .disabled)
    private var requests: [String: UNNotificationRequest] = [:]

    func requestAuthorization() async throws -> Bool {
        notificationSettings.authorizationStatus = authorizationGranted ? .authorized : .denied
        notificationSettings.timeSensitiveSetting = authorizationGranted ? .enabled : .disabled
        notificationSettings.soundSetting = authorizationGranted ? .enabled : .disabled
        return authorizationGranted
    }

    func settings() async -> NotificationSettings { notificationSettings }

    func add(_ request: UNNotificationRequest) async throws {
        if let schedulingError { throw schedulingError }
        requests[request.identifier] = request
    }

    func pendingRequests() async -> [UNNotificationRequest] { Array(requests.values) }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        for identifier in identifiers { requests.removeValue(forKey: identifier) }
    }
}
#endif
