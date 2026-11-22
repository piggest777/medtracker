import Foundation
import SwiftUI
import FamilyControls
import UserNotifications
import Combine

@MainActor
@Observable
final class TrackerModel {
    private(set) var state = TrackerState()
    private(set) var now = Date()
    private(set) var isWorking = false
    private(set) var isLoaded = false
    private(set) var isStatusRefreshing = false
    private(set) var storageError: String?
    private(set) var notificationStatus = "Not requested"
    private(set) var timeSensitiveStatus = "Not requested"
    private(set) var isSendingTestAlert = false
    private(set) var testAlertStatus: String?
    private(set) var appliedShields = AppliedShields()
    var error: String?
    var selectedTab = 0
    private let updateGate = UpdateGate()
    private let notifications: any NotificationServing

    @ObservationIgnored
    private var authorizationObserver: AnyCancellable?

    init(notifications: any NotificationServing) {

        self.notifications = notifications
        if AppEnvironment.isUITesting, ProcessInfo.processInfo.arguments.contains("--reset-ui-testing"),
           let store = try? AppEnvironment.makeStore() {
            try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent())
        }
        #if targetEnvironment(simulator)
        if AppEnvironment.isUITesting, ProcessInfo.processInfo.arguments.contains("--seed-due-doses") {
            do {
                let store = try AppEnvironment.makeStore()
                let now = Date()
                let start = Calendar.current.startOfDay(for: now)
                let components = Calendar.current.dateComponents([.hour, .minute], from: now)
                let time = DailyTime(hour: components.hour!, minute: components.minute!)
                _ = try store.transaction(now: start) { state in
                    state = TrackerState(now: start)
                    state.preferences.hasCompletedOnboarding = true
                    for name in ["First test medication", "Second test medication"] {
                        try DoseEngine.upsert(Medication(name: name, times: [time], effectiveFrom: start),
                                              in: &state, now: start)
                    }
                }
            } catch { self.error = error.localizedDescription }
        }
        #endif
        // Keep one subscription for the model's lifetime. Rebuilding this publisher
        // in a SwiftUI body replays its initial value and can create a refresh loop.
        authorizationObserver = AuthorizationCenter.shared.$authorizationStatus
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                Diagnostics.record("Authorization", "publisher changed status=\(status.description)")
                Task { await self?.refresh(updateReminders: false, source: "authorization-change") }
            }
    }

    var today: [DoseOccurrence] { DoseEngine.today(state, now: now) }
    var due: [DoseOccurrence] { DoseEngine.due(state, now: now) }
    var history: [DoseOccurrence] {
        state.occurrences.filter { $0.outcome != nil }.sorted { $0.scheduledAt > $1.scheduledAt }
    }
    var selection: FamilyActivitySelection { BlockingRuntime.selection(in: state) }
    var hasSelectedApps: Bool { BlockingRuntime.hasSelection(state) }
    var selectionActionTitle: String { hasSelectedApps ? "Change selection" : "Choose apps to block" }
    var isTesting: Bool { state.practiceSession != nil }
    var blockingDueCount: Int { BlockingDemand.dueCount(state, now: now) }

    func appStatus(isShielded: Bool) -> AppBlockingStatus {
        if storageError != nil { return .unavailable }
        if isSimulator { return .preview }
        if !state.previouslyAuthorized { return .needsAccess }
        if state.preferences.blockingPaused { return .paused }
        if isTesting {
            return isShielded ? .blocked : (blockingDueCount == 0 ? .available : .notBlocked)
        }
        if state.medications.isEmpty { return .notScheduled }
        if state.monitoringError != nil || state.monitoringFingerprint != BlockingRuntime.fingerprint(state) {
            return .unavailable
        }
        if isShielded { return .blocked }
        return due.isEmpty ? .available : .notBlocked
    }

    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    var blockingTitle: String {
        if storageError != nil { return "Storage unavailable" }
        if isTesting { return practiceBlockingTitle }
        if isSimulator { return "Tracking preview" }
        if state.preferences.blockingPaused { return "Blocking paused" }
        if !state.previouslyAuthorized { return "Screen Time access needed" }
        if !BlockingRuntime.hasSelection(state) { return "Choose apps to block" }
        if state.monitoringError != nil { return "Blocking needs attention" }
        if state.medications.isEmpty { return "Add your first medication" }
        if state.monitoringFingerprint != BlockingRuntime.fingerprint(state) { return "Blocking is not scheduled" }
        if due.isEmpty { return "You're all caught up" }
        return appliedShields.covers(selection) ? "Selected apps are blocked" : "Updating app blocking"
    }

    var blockingDetail: String {
        if let storageError { return storageError }
        if isTesting { return practiceBlockingDetail }
        if isSimulator { return "Medication tracking works here. Test app blocking on your iPhone." }
        if state.preferences.blockingPaused { return "Reminders and history continue. Resume blocking in Settings." }
        if !state.previouslyAuthorized { return "Enable Screen Time access in Settings to use app blocking." }
        if !BlockingRuntime.hasSelection(state) { return "Choose the apps you want to pause when a dose is due." }
        if let issue = state.monitoringError { return issue }
        if state.medications.isEmpty { return "Create a daily schedule to get started." }
        if state.monitoringFingerprint != BlockingRuntime.fingerprint(state) {
            return "Scheduled blocking is not ready. Pull down on Today to retry."
        }
        if !due.isEmpty && !appliedShields.covers(selection) {
            return "Some selected apps are not blocked yet. Pull down on Today to refresh their status."
        }
        return due.isEmpty ? "Your selected apps stay available until a dose is due." : "Record each due dose as Taken or Skipped to unlock."
    }

    private var practiceBlockingTitle: String {
        if isSimulator { return "Test mode · Preview" }
        if state.preferences.blockingPaused { return "Test mode · Blocking paused" }
        if !state.previouslyAuthorized { return "Test mode · Access needed" }
        if !hasSelectedApps { return "Test mode · Choose apps" }
        if blockingDueCount == 0 { return "Test mode · Apps available" }
        return appliedShields.covers(selection) ? "Test mode · Apps blocked" : "Test mode · Updating blocking"
    }

    private var practiceBlockingDetail: String {
        if isSimulator { return "Try practice check-ins here. Actual app blocking works on your iPhone." }
        if state.preferences.blockingPaused { return "Resume blocking in Settings to test shields. Practice check-ins still work." }
        if !state.previouslyAuthorized { return "Enable Screen Time access in Settings to test app blocking." }
        if !hasSelectedApps { return "Choose apps in Settings to test blocking. No medication schedule is needed." }
        if blockingDueCount == 0 { return "No practice doses are blocking apps. Make doses due again or end the test." }
        return "Record every practice dose as Taken or Skipped to unlock your selected apps. No medication is needed."
    }

    func startPractice() async {
        await update(updateReminders: false, source: "start-test") { $0.practiceSession = PracticeSession() }
    }

    func recordPractice(_ dose: PracticeDose, outcome: DoseOutcome) async {
        await update(updateReminders: false, source: "practice-check-in") {
            $0.practiceSession?.record(dose.id, outcome: outcome)
        }
    }

    func makePracticeDosesDue() async {
        await update(updateReminders: false, source: "practice-due-now") { $0.practiceSession?.makeDosesDue() }
    }

    func advancePracticeDay() async {
        await update(updateReminders: false, source: "practice-next-day") { $0.practiceSession?.advanceDay() }
    }

    func endPractice() async {
        await update(updateReminders: false, source: "end-test") { $0.practiceSession = nil }
    }

    func refresh(updateReminders: Bool = true, source: String = "manual-refresh") async {
        guard !updateGate.isOccupied else {
            Diagnostics.record("Model", "refresh deferred to active update source=\(source)")
            return
        }
        await update(updateReminders: updateReminders, source: source) { _ in }
    }

    @discardableResult
    func update(updateReminders: Bool = true, source: String = "user-change",
                _ change: (inout TrackerState) throws -> Void) async -> Bool {
        if updateGate.isOccupied { Diagnostics.record("Model", "queued update source=\(source) pending=\(updateGate.pendingCount)") }
        await updateGate.enter()
        isWorking = true
        Diagnostics.record("Model", "update started source=\(source)")
        defer {
            isWorking = false
            updateGate.leave()
            Diagnostics.record("Model", "update finished source=\(source)")
        }
        now = Date()
        do {
            let store = try AppEnvironment.makeStore()
            state = try BlockingRuntime.reconcile(store: store, now: now, change: change)
            state = try BlockingRuntime.configureMonitoring(store: store, state: state)
            Diagnostics.record("Selection", "published source=\(source) bytes=\(state.selectionData?.count ?? 0) \(BlockingRuntime.selectionSummary(selection))")
            appliedShields = isSimulator ? AppliedShields() : AppliedShields.read(selection: selection)
            storageError = nil
            isLoaded = true
        } catch TrackerError.invalidMedication {
            error = TrackerError.invalidMedication.localizedDescription
            return false
        } catch TrackerError.tooManyReminders {
            error = TrackerError.tooManyReminders.localizedDescription
            return false
        } catch {
            Diagnostics.record("Model", "update failed source=\(source): \(Diagnostics.errorSummary(error))")
            BlockingRuntime.clearShields()
            appliedShields = AppliedShields()
            // Preserve the last good snapshot; never replace unreadable data with defaults.
            storageError = error.localizedDescription
            self.error = error.localizedDescription
            return false
        }
        if updateReminders {
            Diagnostics.record("Notifications", "configuration started")
            do { notificationStatus = try await notifications.configure(state) }
            catch {
                Diagnostics.record("Notifications", "configuration failed: \(Diagnostics.errorSummary(error))")
                notificationStatus = "Could not schedule reminders: \(error.localizedDescription)"
            }
            Diagnostics.record("Notifications", "configuration finished")
        }
        return true
    }

    func refreshTimeSensitiveStatus() async {
        guard !isStatusRefreshing else {
            return
        }

        defer {
            isStatusRefreshing = false
        }
        isStatusRefreshing = true
        Diagnostics.record("Status refreshing", "refreshing begin")
        timeSensitiveStatus = await notifications.timeSensitiveStatus()
        Diagnostics.record("Status refreshing", "refreshing ended")
    }

    func save(_ medication: Medication) async -> Bool {
        var succeeded = false
        await update { state in
            try DoseEngine.upsert(medication, in: &state, now: Date())
            succeeded = true
        }
        return succeeded && storageError == nil
    }

    func delete(_ id: UUID) async {
        await update { DoseEngine.delete(id, from: &$0, now: Date()) }
    }

    func report(_ occurrence: DoseOccurrence, outcome: DoseOutcome) async {
        await update(updateReminders: false) { DoseEngine.report(occurrence.id, outcome: outcome, in: &$0, now: Date()) }
    }

    func saveSelection(_ selection: FamilyActivitySelection) async -> Bool {
        Diagnostics.record("Picker", "save requested \(BlockingRuntime.selectionSummary(selection))")
        if let issue = BlockingRuntime.selectionLimitIssue(selection) {
            Diagnostics.record("Picker", "save rejected: selection exceeds limits")
            error = issue
            return false
        }
        do {
            let encoded = try JSONEncoder().encode(selection)
            guard try JSONDecoder().decode(FamilyActivitySelection.self, from: encoded) == selection else {
                error = "The app selection could not be encoded correctly. Try choosing apps again."
                Diagnostics.record("Picker", "selection round-trip mismatch")
                return false
            }
            Diagnostics.record("Picker", "encoded bytes=\(encoded.count); round-trip verified")
            guard await update(updateReminders: false, source: "save-selection", { $0.selectionData = encoded }) else {
                Diagnostics.record("Picker", "save failed; keeping picker open")
                return false
            }
            let persisted = try AppEnvironment.makeStore().read()
            state = persisted
            let decoded = BlockingRuntime.selection(in: persisted)
            guard persisted.selectionData == encoded, decoded == selection else {
                Diagnostics.record("Picker", "readback mismatch expected \(BlockingRuntime.selectionSummary(selection)); actual \(BlockingRuntime.selectionSummary(decoded))")
                error = "Your selection was not retained. Check Screen Time access and retry. Diagnostics contains the save details."
                return false
            }
            Diagnostics.record("Picker", "save verified from disk \(BlockingRuntime.selectionSummary(decoded))")
            return true
        } catch {
            Diagnostics.record("Picker", "save/verification failed: \(Diagnostics.errorSummary(error))")
            self.error = "The app selection could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    func requestScreenTime() async {
        guard !isSimulator, !isWorking else { return }
        Diagnostics.record("Authorization", "individual authorization requested")
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            Diagnostics.record("Authorization", "request completed status=\(BlockingRuntime.currentAuthorization().rawValue)")
            await refresh()
        } catch {
            Diagnostics.record("Authorization", "request failed: \(Diagnostics.errorSummary(error))")
            self.error = "Screen Time access was not enabled: \(error.localizedDescription)"
        }
    }

    func requestNotifications() async {
        do {
            _ = try await notifications.requestPermission()
            await refresh()
            await refreshTimeSensitiveStatus()
        } catch { self.error = "Notifications could not be enabled: \(error.localizedDescription)" }
    }

    func sendTestAlert() async {
        guard !isSendingTestAlert else { return }
        isSendingTestAlert = true
        testAlertStatus = nil
        defer { isSendingTestAlert = false }
        do {
            let granted = try await notifications.requestPermission()
            guard granted else {
                error = "Allow notifications for MedTracker in iOS Settings, then try again."
                await refresh()
                return
            }
            try await notifications.sendTestAlert()
            testAlertStatus = "Test alert scheduled with a 5-second delay."
            // Daily rescheduling deliberately preserves the separate one-off test request.
            await refresh()
        } catch {
            Diagnostics.record("Notifications", "test alert failed: \(Diagnostics.errorSummary(error))")
            self.error = "The test alert could not be sent: \(error.localizedDescription)"
        }
    }

    func diagnosticsReport() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        var lines = [
            "MedTracker \(version) (\(build)) · \(Date().formatted(.iso8601))",
            "Process: \(Bundle.main.bundleIdentifier ?? "unknown")",
            "System: \(UIDevice.current.systemVersion) simulator=\(isSimulator)",
            "Authorization: observed=\(BlockingRuntime.currentAuthorization().rawValue) lastKnownApproved=\(state.previouslyAuthorized)",
            "In-memory selection: bytes=\(state.selectionData?.count ?? 0) \(BlockingRuntime.selectionSummary(selection))",
            "State: loaded=\(isLoaded) busy=\(isWorking) paused=\(state.preferences.blockingPaused) storageError=\(storageError != nil)",
            "Monitoring: ready=\(state.monitoringFingerprint == BlockingRuntime.fingerprint(state)) error=\(state.monitoringError != nil)",
            "Test mode: active=\(isTesting) practicePending=\(state.practiceSession?.pendingCount ?? 0)",
            "Notifications: status=\(notificationStatus) timeSensitive=\(timeSensitiveStatus)",
            "Shields: apps=\(appliedShields.applications.count) categories=\(appliedShields.categories.count) websites=\(appliedShields.websites.count)"
        ]
        do {
            let stored = try AppEnvironment.makeStore().read()
            lines.append("On-disk selection: bytes=\(stored.selectionData?.count ?? 0) \(BlockingRuntime.selectionSummary(BlockingRuntime.selection(in: stored)))")
            if let data = stored.selectionData {
                do {
                    _ = try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
                    lines.append("Selection decoding: succeeded")
                } catch { lines.append("Selection decoding: failed \(Diagnostics.errorSummary(error))") }
            }
        } catch { lines.append("Disk read: failed \(Diagnostics.errorSummary(error))") }
        lines.append("\nRecent events from this app session (extension events are in Console, subsystem MedTracker):")
        lines.append(Diagnostics.recentEvents())
        return lines.joined(separator: "\n")
    }
}
