import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: TrackerModel

    var body: some View {
        NavigationStack {
            List {
                if model.isTesting {
                    Section {
                        Label("Test mode is active", systemImage: "testtube.2")
                            .font(.headline).foregroundStyle(.orange)
                            .accessibilityIdentifier("practice.banner")
                        Text("Practice check-ins do not affect your medication history.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        NavigationLink("Test controls") { TestModeView() }
                        Button("End test") { Task { await model.endPractice() } }
                            .accessibilityIdentifier("practice.end-today")
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.blockingTitle, systemImage: model.blockingDueCount == 0 ? "checkmark.circle.fill" : "pause.circle.fill")
                            .font(.headline).foregroundStyle(.teal)
                        Text(model.blockingDetail).font(.subheadline).foregroundStyle(.secondary)
                        if !model.isTesting && !model.due.isEmpty {
                            Text("\(model.due.count) due \(model.due.count == 1 ? "dose" : "doses")")
                                .font(.caption.bold()).foregroundStyle(.teal)
                        }
                    }.padding(.vertical, 8)
                }
                if model.isTesting {
                    PracticeDosesSection()
                } else if model.state.medications.isEmpty && model.today.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("Your routine starts here", systemImage: "pills")
                        } description: {
                            Text("Add your first medication and a daily reminder time.")
                        } actions: {
                            Button("Add a medication") { model.selectedTab = 1 }
                        }
                    }
                } else {
                    let due = model.today.filter { $0.outcome == nil && $0.scheduledAt <= model.now }
                    let upcoming = model.today.filter { $0.outcome == nil && $0.scheduledAt > model.now }
                    let completed = model.today.filter { $0.outcome != nil }
                    if !due.isEmpty {
                        Section("Due now") { ForEach(due) { DoseRow(occurrence: $0, canReport: true) } }
                    }
                    if !upcoming.isEmpty {
                        Section("Coming up") { ForEach(upcoming) { DoseRow(occurrence: $0) } }
                    }
                    if !completed.isEmpty {
                        Section("Recorded today") { ForEach(completed) { DoseRow(occurrence: $0) } }
                    }
                    if model.today.isEmpty {
                        Section { Text("No more reminders today. Your schedule starts with the next daily time.").foregroundStyle(.secondary) }
                    }
                }
                if model.hasSelectedApps {
                    Section {
                        SelectedAppsList()
                        Button("Manage apps") { model.selectedTab = 3 }
                    } header: { Text("Selected apps") } footer: {
                        Text(model.isTesting ? "Apps unlock after all practice doses are recorded." : "Apps unlock after you record all due doses.")
                    }
                }
            }
            .navigationTitle("Today")
            .refreshable { await model.refresh() }
        }
    }
}

struct DoseRow: View {
    @EnvironmentObject private var model: TrackerModel
    let occurrence: DoseOccurrence
    var canReport = false
    @State private var confirmSkip = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(occurrence.medicationName).font(.headline)
                    if !occurrence.dose.isEmpty { Text(occurrence.dose).font(.subheadline).foregroundStyle(.secondary) }
                    Text(occurrence.scheduledAt, style: .time).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                if let outcome = occurrence.outcome {
                    Text(outcome.title).font(.caption.bold())
                        .foregroundStyle(outcome == .taken ? Color.teal : Color.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }
            if canReport {
                HStack(spacing: 12) {
                    Button { Task { await model.report(occurrence, outcome: .taken) } } label: {
                        Label("Taken", systemImage: "checkmark").frame(maxWidth: .infinity).padding(.vertical, 4)
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("dose.taken.\(occurrence.id)")
                    Button("Skip") { confirmSkip = true }
                        .buttonStyle(.bordered).accessibilityIdentifier("dose.skip.\(occurrence.id)")
                }
            }
        }
        .padding(.vertical, 6)
        .confirmationDialog("Skip this dose?", isPresented: $confirmSkip, titleVisibility: .visible) {
            Button("Record as Skipped") { Task { await model.report(occurrence, outcome: .skipped) } }
        } message: { Text("This resolves the reminder without recording that you took the medication.") }
    }
}
