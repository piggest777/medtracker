import Foundation
import Testing
import UserNotifications
@testable import MedTrackerCore

@MainActor
struct NotificationServiceTests {
    @Test
    func testAlertUsesTimeSensitiveContentAndFiveSecondTrigger() async throws {
        let center = TestNotificationCenter()
        let service = NotificationService(center: center)

        try await service.sendTestAlert()

        let request = try #require(center.requests.first)
        #expect(center.requests.count == 1)
        #expect(request.identifier == NotificationService.testAlertIdentifier)
        #expect(request.content.interruptionLevel == .timeSensitive)
        #expect(request.content.sound != nil)
        #expect(request.content.body.contains("No medication is needed"))
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 5)
        #expect(!trigger.repeats)
    }

    @Test(arguments: [true, false])
    func dailyReschedulingPreservesTestAndUnrelatedAlerts(revealNames: Bool) async throws {
        let center = TestNotificationCenter()
        center.requests = [request("unrelated"), request("medtracker.stale")]
        let service = NotificationService(center: center)
        try await service.sendTestAlert()
        var state = TrackerState()
        state.preferences.notificationsEnabled = true
        state.preferences.revealMedicationNames = revealNames
        let medication = Medication(name: "Private medication", times: [DailyTime(hour: 9, minute: 30)], effectiveFrom: Date())
        state.medications = [medication]

        let status = try await service.configure(state)

        #expect(status == "Enabled")
        #expect(Set(center.requests.map(\.identifier)) == ["unrelated", NotificationService.testAlertIdentifier,
                                                         "medtracker.\(medication.id).570"])
        let daily = try #require(center.requests.first { $0.identifier == "medtracker.\(medication.id).570" })
        #expect(daily.content.body.contains(medication.name) == revealNames)
        #expect(daily.content.interruptionLevel == .timeSensitive)
        #expect(daily.content.sound != nil)
        let trigger = try #require(daily.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.hour == 9)
        #expect(trigger.dateComponents.minute == 30)
        #expect(trigger.repeats)
    }

    @Test(arguments: [UNAuthorizationStatus.notDetermined, .denied])
    func unauthorizedSchedulingRemovesOldDailyRequestsOnly(status: UNAuthorizationStatus) async throws {
        let center = TestNotificationCenter()
        center.notificationSettings.authorizationStatus = status
        center.requests = [request("unrelated"), request("medtracker.stale"),
                           request(NotificationService.testAlertIdentifier)]
        let service = NotificationService(center: center)
        var state = TrackerState()
        state.preferences.notificationsEnabled = true

        let result = try await service.configure(state)

        #expect(result == (status == .notDetermined ? "Not requested" : "Disabled in iOS Settings"))
        #expect(Set(center.requests.map(\.identifier)) == ["unrelated", NotificationService.testAlertIdentifier])
    }

    @Test
    func schedulingFailureRemovesPartiallyInstalledDailySchedule() async throws {
        let center = TestNotificationCenter()
        center.requests = [request("unrelated"), request(NotificationService.testAlertIdentifier)]
        center.successfulAddsBeforeFailure = 1
        let service = NotificationService(center: center)
        var state = TrackerState()
        state.preferences.notificationsEnabled = true
        state.medications = [Medication(name: "Private medication",
                                       times: [DailyTime(hour: 9, minute: 0), DailyTime(hour: 18, minute: 0)],
                                       effectiveFrom: Date())]

        await #expect(throws: SchedulingFailure.self) {
            try await service.configure(state)
        }

        #expect(Set(center.requests.map(\.identifier)) == ["unrelated", NotificationService.testAlertIdentifier])
    }

    @Test
    func testAlertSchedulingFailureIsReportedToCaller() async {
        let center = TestNotificationCenter()
        center.successfulAddsBeforeFailure = 0
        let service = NotificationService(center: center)

        await #expect(throws: SchedulingFailure.self) { try await service.sendTestAlert() }

        #expect(center.requests.isEmpty)
    }

    @Test(arguments: [UNNotificationSetting.enabled, .disabled, .notSupported])
    func timeSensitiveStatusReflectsSystemSetting(setting: UNNotificationSetting) async {
        let center = TestNotificationCenter()
        center.notificationSettings.timeSensitiveSetting = setting
        let service = NotificationService(center: center)

        let result = await service.timeSensitiveStatus()

        let expected = setting == .enabled ? "Enabled" : setting == .disabled ? "Disabled in iOS Settings" : "Unavailable"
        #expect(result == expected)
    }

    private func request(_ identifier: String) -> UNNotificationRequest {
        UNNotificationRequest(identifier: identifier, content: UNMutableNotificationContent(), trigger: nil)
    }
}

private enum SchedulingFailure: Error { case unavailable }

@MainActor
private final class TestNotificationCenter: NotificationCenterClient {
    var requests: [UNNotificationRequest] = []
    var successfulAddsBeforeFailure: Int?
    var notificationSettings = NotificationSettings(authorizationStatus: .authorized,
                                                    timeSensitiveSetting: .enabled, soundSetting: .enabled)

    func requestAuthorization() async throws -> Bool { notificationSettings.authorizationStatus == .authorized }
    func settings() async -> NotificationSettings { notificationSettings }
    func pendingRequests() async -> [UNNotificationRequest] { requests }

    func add(_ request: UNNotificationRequest) async throws {
        if let remaining = successfulAddsBeforeFailure {
            guard remaining > 0 else { throw SchedulingFailure.unavailable }
            successfulAddsBeforeFailure = remaining - 1
        }
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        requests.removeAll { identifiers.contains($0.identifier) }
    }
}
