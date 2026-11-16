import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import OSLog

enum AppEnvironment {
    static let logger = Logger(subsystem: "MedTracker", category: "Runtime")
    static var isUITesting: Bool {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        false
        #endif
    }

    static func makeStore() throws -> SharedStore {
        if isUITesting {
            Diagnostics.record("Storage", "using isolated UI-test container")
            return SharedStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("MedTrackerUITests/state.json"))
        }
        guard let group = Bundle.main.object(forInfoDictionaryKey: "MedTrackerAppGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            #if targetEnvironment(simulator)
            // Simulator cannot exercise Screen Time enforcement; allow the tracking UI to run.
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            Diagnostics.record("Storage", "App Group unavailable; using simulator fallback")
            return SharedStore(url: support.appendingPathComponent("MedTracker/state.json"))
            #else
            Diagnostics.record("Storage", "App Group unavailable in device build")
            throw TrackerError.unavailableContainer
            #endif
        }
        Diagnostics.record("Storage", "resolved App Group=\(group) process=\(Bundle.main.bundleIdentifier ?? "unknown")")
        return SharedStore(url: container.appendingPathComponent("MedTracker/state.json"))
    }
}

enum BlockingRuntime {
    static let storeNameRawValue: String = "medication-reminders"
    static let prefix = "medtracker."

    static func selection(in state: TrackerState) -> FamilyActivitySelection {
        guard let data = state.selectionData else { return FamilyActivitySelection() }
        do {
            return try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        } catch {
            Diagnostics.record("Selection", "decode failed bytes=\(data.count): \(Diagnostics.errorSummary(error))")
            return FamilyActivitySelection()
        }
    }

    static func selectionSummary(_ selection: FamilyActivitySelection) -> String {
        "apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) websites=\(selection.webDomainTokens.count)"
    }

    static func currentAuthorization() -> ScreenTimePermission {
        let read = { () -> ScreenTimePermission in
            let status = AuthorizationCenter.shared.authorizationStatus
            if status == .approved { return .approved }
            if #available(iOS 26.4, *), status == .approvedWithDataAccess { return .approved }
            return status == .denied ? .denied : .notDetermined
        }
        // Apple requires authorizationStatus to be read on the main queue.
        return Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read)
    }

    static func hasSelection(_ state: TrackerState) -> Bool {
        let selected = selection(in: state)
        return !selected.applicationTokens.isEmpty || !selected.categoryTokens.isEmpty || !selected.webDomainTokens.isEmpty
    }

    static func selectionLimitIssue(_ selection: FamilyActivitySelection) -> String? {
        guard selection.applicationTokens.count <= 50, selection.categoryTokens.count <= 50,
              selection.webDomainTokens.count <= 50 else {
            return "Choose at most 50 apps, 50 categories, and 50 websites. iOS cannot shield a larger selection."
        }
        return nil
    }

    static func fingerprint(_ state: TrackerState) -> String {
        let times = Set(state.medications.flatMap(\.times).map(\.id)).sorted().map(String.init).joined(separator: ",")
        return "v1|\(times)"
    }

    static func updateAuthorization(_ state: inout TrackerState, permission: ScreenTimePermission) {
        guard !AppEnvironment.isUITesting else { return }
        Diagnostics.record("Authorization", "observed=\(permission.rawValue) lastKnownApproved=\(state.previouslyAuthorized) selectionBytes=\(state.selectionData?.count ?? 0)")
        if permission == .denied, state.selectionData != nil {
            Diagnostics.record("Authorization", "clearing saved selection after confirmed denial/revocation")
        } else if permission == .notDetermined {
            Diagnostics.record("Authorization", "status unresolved; preserving saved selection and last known authorization")
        }
        permission.reconcile(&state)
    }

    static func shouldShield(_ state: TrackerState, now: Date) -> Bool {
        guard state.previouslyAuthorized, !state.preferences.blockingPaused, hasSelection(state),
              BlockingDemand.dueCount(state, now: now) > 0 else { return false }
        // Practice uses the same actual shields, immediately, without needing a medication
        // schedule or claiming to validate DeviceActivity's scheduled background delivery.
        if state.practiceSession != nil { return true }
        return state.monitoringError == nil && state.monitoringFingerprint == fingerprint(state)
    }

    static func apply(_ state: TrackerState, now: Date = Date()) {
        guard !AppEnvironment.isUITesting else { return }
        let storeName = ManagedSettingsStore.Name(storeNameRawValue)
        let settings = ManagedSettingsStore(named: storeName)
        guard shouldShield(state, now: now) else {
            Diagnostics.record("Shield", "clearing; approved=\(state.previouslyAuthorized) paused=\(state.preferences.blockingPaused) selected=\(hasSelection(state)) scheduleReady=\(state.monitoringFingerprint == fingerprint(state)) monitoringError=\(state.monitoringError != nil) testMode=\(state.practiceSession != nil) due=\(BlockingDemand.dueCount(state, now: now))")
            settings.clearAllSettings()
            return
        }
        let selected = selection(in: state)
        Diagnostics.record("Shield", "applying testMode=\(state.practiceSession != nil) \(selectionSummary(selected))")
        settings.shield.applications = selected.applicationTokens.isEmpty ? nil : selected.applicationTokens
        settings.shield.applicationCategories = selected.categoryTokens.isEmpty ? nil : .specific(selected.categoryTokens)
        settings.shield.webDomains = selected.webDomainTokens.isEmpty ? nil : selected.webDomainTokens
        settings.shield.webDomainCategories = selected.categoryTokens.isEmpty ? nil : .specific(selected.categoryTokens)
    }

    static func clearShields() {
        guard !AppEnvironment.isUITesting else { return }
        Diagnostics.record("Shield", "explicit clear after runtime failure")
        let storeName = ManagedSettingsStore.Name(storeNameRawValue)
        ManagedSettingsStore(named: storeName).clearAllSettings()
    }

    @discardableResult
    static func reconcile(store: SharedStore, now: Date = Date(),
                          change: (inout TrackerState) throws -> Void = { _ in }) throws -> TrackerState {
        // Read before acquiring the file lock so main-queue access cannot deadlock a writer.
        let permission = currentAuthorization()
        return try store.transaction(now: now, { state in
            DoseEngine.reconcile(&state, now: now)
            updateAuthorization(&state, permission: permission)
            try change(&state)
        }, afterSave: { apply($0, now: now) })
    }

    /// Called by the app, never from inside a file-coordination accessor.
    /// Registering monitoring can immediately invoke the extension.
    static func configureMonitoring(store: SharedStore, state: TrackerState) throws -> TrackerState {
        guard !AppEnvironment.isUITesting else { return state }
        let center = DeviceActivityCenter()
        let existing = center.activities.filter { $0.rawValue.hasPrefix(prefix) }
        Diagnostics.record("Monitoring", "configure registered=\(existing.count) approved=\(state.previouslyAuthorized) paused=\(state.preferences.blockingPaused) \(selectionSummary(selection(in: state)))")
        guard state.previouslyAuthorized, !state.preferences.blockingPaused, hasSelection(state),
              !state.medications.isEmpty else {
            if !existing.isEmpty { center.stopMonitoring(existing) }
            return try reconcile(store: store) {
                $0.monitoringFingerprint = nil
                $0.monitoringError = nil
            }
        }
        let minutes = Set(state.medications.flatMap(\.times).map(\.id)).union([0]).sorted()
        let names = minutes.map { DeviceActivityName("\(prefix)time.\($0)") }
        let desired = fingerprint(state)
        let zone = "\(TimeZone.current.identifier)|\(TimeZone.current.secondsFromGMT())"
        if state.monitoringFingerprint == desired, state.monitoringTimeZone == zone,
           Set(names) == Set(existing), state.monitoringError == nil {
            return state
        }

        // Invalidate before touching OS schedules; intermediate callbacks must not apply stale shields.
        _ = try reconcile(store: store) { $0.monitoringFingerprint = nil }
        Diagnostics.record("Monitoring", "registering activities=\(names.count)")
        center.stopMonitoring(existing)
        do {
            for (minute, name) in zip(minutes, names) {
                // Keep each interval open until one minute before its next daily start.
                // A short interval can be missed entirely while the phone is idle.
                // All intervals exceed Apple's 15-minute minimum, including near midnight.
                let end = (minute + 24 * 60 - 1) % (24 * 60)
                let schedule = DeviceActivitySchedule(
                    intervalStart: DateComponents(hour: minute / 60, minute: minute % 60),
                    intervalEnd: DateComponents(hour: end / 60, minute: end % 60), repeats: true
                )
                try center.startMonitoring(name, during: schedule)
            }
            Diagnostics.record("Monitoring", "registration succeeded activities=\(names.count)")
            return try reconcile(store: store) {
                $0.monitoringFingerprint = desired
                $0.monitoringTimeZone = zone
                $0.monitoringError = nil
            }
        } catch {
            Diagnostics.record("Monitoring", "registration failed: \(Diagnostics.errorSummary(error))")
            center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(prefix) })
            let message = "Scheduled blocking could not start: \(error.localizedDescription) Try fewer distinct reminder times, then retry."
            return try reconcile(store: store) {
                $0.monitoringFingerprint = nil
                $0.monitoringError = message
            }
        }
    }
}
