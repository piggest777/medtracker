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
        #expect(trigger.dateComponents.weekday == nil)
        #expect(trigger.repeats)
    }

    @Test(arguments: [
        [DailyTime(hour: 8, minute: 0)],
        [DailyTime(hour: 8, minute: 0), DailyTime(hour: 18, minute: 30)]
    ])
    func selectedWeekdaysScheduleEachTimeWithUniqueIdentifiers(times: [DailyTime]) async throws {
        let center = TestNotificationCenter()
        let service = NotificationService(center: center)
        var state = TrackerState()
        let medication = Medication(name: "Private medication", times: times, effectiveFrom: Date(),
                                    weekdays: [.monday, .wednesday, .friday])
        state.medications = [medication]

        let status = try await service.configure(state)

        #expect(status == "Enabled")
        #expect(center.requests.count == times.count * 3)
        #expect(Set(center.requests.map(\.identifier)).count == times.count * 3)
        for time in times {
            let requests = center.requests.filter { $0.identifier.hasPrefix("medtracker.\(medication.id).\(time.id).weekday.") }
            #expect(requests.count == 3)
            let triggers = try requests.map { try #require($0.trigger as? UNCalendarNotificationTrigger) }
            #expect(Set(triggers.compactMap { $0.dateComponents.weekday }) == [2, 4, 6])
            for trigger in triggers {
                #expect(trigger.dateComponents.hour == time.hour)
                #expect(trigger.dateComponents.minute == time.minute)
                #expect(trigger.dateComponents.year == nil)
                #expect(trigger.dateComponents.month == nil)
                #expect(trigger.dateComponents.day == nil)
                #expect(trigger.repeats)
            }
            for request in requests {
                #expect(!request.content.body.contains(medication.name))
                #expect(request.content.interruptionLevel == .timeSensitive)
                #expect(request.content.sound != nil)
            }
        }
    }

    @Test(arguments: [
        (Weekday.allCases, [.tuesday, .thursday]),
        ([.monday, .wednesday, .friday], [.tuesday, .thursday]),
        ([.monday, .wednesday, .friday], Weekday.allCases),
        ([.monday, .wednesday, .friday], [])
    ])
    func changingWeekdaysReplacesPreviousSchedule(previous: [Weekday], selected: [Weekday]) async throws {
        let center = TestNotificationCenter()
        center.requests = [request("unrelated"), request(NotificationService.testAlertIdentifier)]
        let service = NotificationService(center: center)
        var state = TrackerState()
        let medication = Medication(name: "Example", times: [DailyTime(hour: 8, minute: 0)],
                                    effectiveFrom: Date(), weekdays: Set(previous))
        state.medications = [medication]
        _ = try await service.configure(state)

        state.medications[0].weekdays = Set(selected)
        _ = try await service.configure(state)

        let medicationRequests = center.requests.filter { $0.identifier.hasPrefix("medtracker.\(medication.id).") }
        let preservedIdentifiers: Set<String> = ["unrelated", NotificationService.testAlertIdentifier]
        #expect(Set(center.requests.map(\.identifier)).subtracting(medicationRequests.map(\.identifier)) == preservedIdentifiers)
        let triggers = try medicationRequests.map { try #require($0.trigger as? UNCalendarNotificationTrigger) }
        if Set(selected) == Set(Weekday.allCases) {
            #expect(medicationRequests.count == 1)
            #expect(medicationRequests.first?.identifier == "medtracker.\(medication.id).480")
            #expect(triggers.first?.dateComponents.weekday == nil)
        } else {
            #expect(medicationRequests.count == selected.count)
            #expect(Set(triggers.compactMap { $0.dateComponents.weekday }) == Set(selected.map(\.rawValue)))
        }
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

    @Test(arguments: [Weekday.allCases, [.monday, .wednesday, .friday]])
    func schedulingFailureRemovesPartiallyInstalledSchedule(weekdays: [Weekday]) async throws {
        let center = TestNotificationCenter()
        center.requests = [request("unrelated"), request(NotificationService.testAlertIdentifier)]
        center.successfulAddsBeforeFailure = 1
        let service = NotificationService(center: center)
        var state = TrackerState()
        state.preferences.notificationsEnabled = true
        state.medications = [Medication(name: "Private medication",
                                       times: [DailyTime(hour: 9, minute: 0), DailyTime(hour: 18, minute: 0)],
                                       effectiveFrom: Date(), weekdays: Set(weekdays))]

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
