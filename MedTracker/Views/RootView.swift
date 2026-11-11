import SwiftUI
import Combine

struct RootView: View {
    @EnvironmentObject private var model: TrackerModel
    @Environment(\.scenePhase) private var scenePhase
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            #if DEBUG && targetEnvironment(simulator)
            if AppEnvironment.isUITesting, ProcessInfo.processInfo.arguments.contains("--selection-layout-preview") {
                SelectionLayoutPreview()
            } else {
                appContent
            }
            #else
            appContent
            #endif
        }
        .task { await model.refresh(source: "launch") }
        .onChange(of: scenePhase) { _, phase in
            Diagnostics.record("Lifecycle", "scene phase=\(String(describing: phase))")
            if phase == .active { Task { await model.refresh(source: "foreground") } }
        }
        .onReceive(timer) { _ in
            guard scenePhase == .active else { return }
            Task { await model.refresh(updateReminders: false, source: "foreground-timer") }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await model.refresh(source: "significant-time-change") }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openToday)) { _ in model.selectedTab = 0 }
        .alert("MedTracker", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var appContent: some View {
        Group {
            if !model.isLoaded {
                if let issue = model.storageError {
                    ContentUnavailableView {
                        Label("Unable to load MedTracker", systemImage: "externaldrive.badge.exclamationmark")
                    } description: { Text(issue) } actions: {
                        Button("Retry") { Task { await model.refresh() } }
                    }
                } else {
                    ProgressView("Loading MedTracker…")
                }
            } else if !model.state.preferences.hasCompletedOnboarding {
                OnboardingView()
            } else {
                TabView(selection: $model.selectedTab) {
                    TodayView().tabItem { Label("Today", systemImage: "sun.max") }.tag(0)
                    MedicationsView().tabItem { Label("Medications", systemImage: "pills") }.tag(1)
                    HistoryView().tabItem { Label("History", systemImage: "clock.arrow.circlepath") }.tag(2)
                    SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
                }
                .disabled(model.isWorking)
            }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: TrackerModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: "pills.circle.fill")
                        .font(.system(size: 76)).foregroundStyle(.teal).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A small pause.\nA daily check-in.").font(.largeTitle.bold())
                        Text("Make room for your medication routine before opening your favourite distractions.")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    feature("1", "Set your daily times", "Add medications and the times you want a reminder.")
                    feature("2", "Choose your apps", "Screen Time pauses your selection when a dose is due.")
                    feature("3", "Check in honestly", "Taken or Skipped resolves a reminder. Unreported doses become Missed the next day.")
                    Text("Everything stays on this iPhone. You can pause blocking at any time. Screen Time access is optional and can be revoked in iOS Settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button {
                        Task { await model.update { $0.preferences.hasCompletedOnboarding = true } }
                    } label: {
                        Text("Get started").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent).disabled(model.isWorking)
                    .accessibilityIdentifier("onboarding.start")
                }
                .padding(28)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private func feature(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number).font(.headline).foregroundStyle(.teal)
                .frame(width: 32, height: 32).background(.teal.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}
