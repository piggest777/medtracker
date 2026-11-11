import SwiftUI

struct TestModeView: View {
    @EnvironmentObject private var model: TrackerModel

    var body: some View {
        Form {
            if let practice = model.state.practiceSession {
                Section {
                    Label("Practice only · Day \(practice.day)", systemImage: "testtube.2")
                        .font(.headline).foregroundStyle(.orange)
                    Text(model.blockingTitle).font(.subheadline.weight(.semibold))
                    Text(model.blockingDetail).font(.subheadline).foregroundStyle(.secondary)
                } footer: {
                    Text("Test mode temporarily controls app blocking. Your real schedules and notifications continue, and practice check-ins never record medication intake.")
                }
                PracticeDosesSection()
                Section("Test controls") {
                    Button("Make doses due now", systemImage: "bolt.fill") {
                        Task { await model.makePracticeDosesDue() }
                    }
                    .disabled(practice.pendingCount > 0)
                    .accessibilityIdentifier("practice.due-now")
                    Button("Simulate next day", systemImage: "sunrise") {
                        Task { await model.advancePracticeDay() }
                    }.accessibilityIdentifier("practice.next-day")
                    Button("Restart test", systemImage: "arrow.counterclockwise") {
                        Task { await model.startPractice() }
                    }.accessibilityIdentifier("practice.restart")
                }
                if !practice.history.isEmpty {
                    Section("Practice history") {
                        ForEach(practice.history) { dose in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(dose.title)
                                    Text("Practice day \(dose.day)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(dose.outcome?.title ?? "").font(.caption.weight(.semibold))
                                    .foregroundStyle(dose.outcome == .taken ? Color.teal : .secondary)
                            }
                        }
                    }
                }
            } else {
                Section {
                    Label("Try the full check-in cycle", systemImage: "testtube.2")
                        .font(.headline).foregroundStyle(.orange)
                    Text("Create two practice doses that are due immediately. Your selected apps can block until both are recorded as Taken or Skipped. No medication or waiting is needed.")
                    Button("Start test", systemImage: "play.fill") {
                        Task { await model.startPractice() }
                    }
                    .accessibilityIdentifier("practice.start")
                } footer: {
                    Text("To test actual blocking, enable Screen Time access, choose apps, and leave blocking unpaused in Settings. You can still try the check-ins without those permissions.")
                }
            }
            Section {
                Text("Practice results are separate from your medication history. Simulating a day does not change your iPhone’s clock.")
                Text("This tests immediate blocking and check-ins. Scheduled background triggers still need a timed test.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Test mode")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isWorking)
        .toolbar {
            if model.isTesting {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("End test") { Task { await model.endPractice() } }
                        .accessibilityIdentifier("practice.end")
                }
            }
        }
    }
}

struct PracticeDosesSection: View {
    @EnvironmentObject private var model: TrackerModel

    var body: some View {
        if let practice = model.state.practiceSession {
            Section {
                if practice.pendingCount > 0 {
                    Text("\(practice.pendingCount) practice \(practice.pendingCount == 1 ? "dose" : "doses") due")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                        .accessibilityIdentifier("practice.pending-count")
                }
                ForEach(practice.currentDoses) { dose in
                    PracticeDoseRow(dose: dose)
                }
                if practice.pendingCount == 0 {
                    Label("No practice doses are blocking apps.", systemImage: "checkmark.circle")
                        .foregroundStyle(.teal).accessibilityIdentifier("practice.complete")
                }
            } header: { Text("Practice doses · Day \(practice.day)") } footer: {
                Text("Practice only. You do not need to take any medication.")
            }
        }
    }
}

private struct PracticeDoseRow: View {
    @EnvironmentObject private var model: TrackerModel
    let dose: PracticeDose

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dose.title).font(.headline)
                Spacer()
                if let outcome = dose.outcome {
                    Text(outcome.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            if dose.outcome == nil {
                HStack(spacing: 12) {
                    Button("Taken") { Task { await model.recordPractice(dose, outcome: .taken) } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Simulate Taken")
                        .accessibilityIdentifier("practice.taken.\(dose.id)")
                    Button("Skipped") { Task { await model.recordPractice(dose, outcome: .skipped) } }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Simulate Skipped")
                        .accessibilityIdentifier("practice.skipped.\(dose.id)")
                }
            }
        }.padding(.vertical, 5)
    }
}
