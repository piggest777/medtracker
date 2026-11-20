import UserNotifications

struct NotificationSettings {
    var authorizationStatus: UNAuthorizationStatus
    var timeSensitiveSetting: UNNotificationSetting
    var soundSetting: UNNotificationSetting
}

/// The system boundary, shared by real scheduling and deterministic tests.
@MainActor
protocol NotificationCenterClient {
    func requestAuthorization() async throws -> Bool
    func settings() async -> NotificationSettings
    func add(_ request: UNNotificationRequest) async throws
    func pendingRequests() async -> [UNNotificationRequest]
    func removePendingRequests(withIdentifiers identifiers: [String])
}

struct SystemNotificationCenter: NotificationCenterClient {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func settings() async -> NotificationSettings {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return NotificationSettings(authorizationStatus: settings.authorizationStatus,
                                    timeSensitiveSetting: settings.timeSensitiveSetting,
                                    soundSetting: settings.soundSetting)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
