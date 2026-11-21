import SwiftUI
import FamilyControls

struct SettingsView: View {
    @Environment(TrackerModel.self) private var model: TrackerModel
    @Environment(\.openURL) private var openURL
    @State private var showingPicker = false
    @State private var draftSelection = FamilyActivitySelection()
    @State private var isSavingSelection = false
    @State private var selectionSaveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(model.blockingTitle, systemImage: "shield.lefthalf.filled").font(.headline)
                    Text(model.blockingDetail).font(.subheadline).foregroundStyle(.secondary)
                    Toggle("Pause blocking", isOn: preference(\.blockingPaused))
                        .accessibilityIdentifier("settings.pause")
                    if model.state.previouslyAuthorized {
                        LabeledContent("Screen Time") {
                            Label("Enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.teal)
                        }
                    } else {
                        Button("Enable Screen Time access") { Task { await model.requestScreenTime() } }
                            .disabled(model.isSimulator)
                    }
                    if model.state.monitoringError != nil {
                        Button("Retry scheduled blocking") { Task { await model.refresh() } }
                    }
                } header: { Text("App blocking") } footer: {
                    Text("Choose distractions to pause, keeping essential apps available.")
                }
                Section {
                    if model.hasSelectedApps {
                        SelectedAppsList()
                    } else {
                        Text("No apps selected").foregroundStyle(.secondary)
                    }
                    Button(model.selectionActionTitle) {
                        draftSelection = model.selection
                        selectionSaveError = nil
                        Diagnostics.record("Picker", "opened \(BlockingRuntime.selectionSummary(draftSelection))")
                        showingPicker = true
                    }
                    .disabled(model.isSimulator || !model.state.previouslyAuthorized)
                    .accessibilityIdentifier("settings.selection")
                } header: { Text("Selected apps") } footer: {
                    Text("Selected apps pause when a dose is due and unlock after your check-in.")
                }
                Section {
                    Toggle("Daily notifications", isOn: preference(\.notificationsEnabled))
                    Toggle("Include medication names", isOn: preference(\.revealMedicationNames))
                    LabeledContent("Notifications", value: model.notificationStatus)
                    LabeledContent("Time Sensitive", value: model.timeSensitiveStatus)
                    Button("Enable notifications") { Task { await model.requestNotifications() } }
                    Button("Send test alert", systemImage: "bell.badge") {
                        Task {
                          await model.sendTestAlert()
                          await model.refreshTimeSensitiveStatus()
                        }
                    }
                        .disabled(model.isSendingTestAlert)
                        .accessibilityIdentifier("settings.test-alert")
                    if let status = model.testAlertStatus {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.test-alert-status")
                    }
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } header: { Text("Reminders") } footer: {
                    Text("Time Sensitive reminders can break through Focus when allowed. Silent mode is respected. Medication names stay hidden unless enabled.")
                }
                Section {
                    NavigationLink {
                        TestModeView()
                    } label: {
                        HStack {
                            Label("Test mode", systemImage: "testtube.2")
                            Spacer()
                            if model.isTesting { Text("Active").foregroundStyle(.orange) }
                        }
                    }.accessibilityIdentifier("settings.test-mode")
                } header: { Text("Try it out") } footer: {
                    Text("Test blocking and check-ins instantly with practice doses.")
                }
                Section("About your data") {
                    Text("Schedules and check-ins stay on this iPhone in the app’s shared container. There is no account, server, analytics, or cloud sync. Device backups may include app data.")
                    Text("Taken and Skipped are self-reported. At midnight, unresolved doses become Missed and blocking resets for the new day.")
                    Text("MedTracker · Personal development build").font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("Diagnostics") { DiagnosticsView() }
                        .accessibilityIdentifier("settings.diagnostics")
                }
            }
            .navigationTitle("Settings")
            .onAppear { Diagnostics.record("UI", "Settings appeared \(BlockingRuntime.selectionSummary(model.selection))") }
            .onChange(of: model.selection) { _, value in
                Diagnostics.record("UI", "Settings selection changed \(BlockingRuntime.selectionSummary(value))")
            }
            .sheet(isPresented: $showingPicker) {
                NavigationStack {
                    FamilyActivityPicker(selection: $draftSelection)
                        .safeAreaInset(edge: .bottom) {
                            if let issue = BlockingRuntime.selectionLimitIssue(draftSelection) ?? selectionSaveError {
                                Text(issue).font(.footnote).foregroundStyle(.red).padding()
                                    .frame(maxWidth: .infinity).background(.regularMaterial)
                            }
                        }
                        .navigationTitle("Apps to pause")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    Diagnostics.record("Picker", "cancelled without saving")
                                    showingPicker = false
                                }.disabled(isSavingSelection)
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button(isSavingSelection ? "Saving…" : "Done") {
                                    // Capture the value before the native picker starts dismissing.
                                    let snapshot = draftSelection
                                    isSavingSelection = true
                                    Diagnostics.record("Picker", "Done tapped \(BlockingRuntime.selectionSummary(snapshot))")
                                    Task {
                                        let saved = await model.saveSelection(snapshot)
                                        isSavingSelection = false
                                        if saved {
                                            showingPicker = false
                                        } else {
                                            selectionSaveError = model.error ?? "Selection could not be saved. Please retry."
                                        }
                                    }
                                }
                                .disabled(isSavingSelection || BlockingRuntime.selectionLimitIssue(draftSelection) != nil)
                            }
                        }
                }
                .interactiveDismissDisabled(isSavingSelection)
                .onChange(of: draftSelection) { _, value in
                    selectionSaveError = nil
                    Diagnostics.record("Picker", "draft changed \(BlockingRuntime.selectionSummary(value))")
                }
                .onDisappear { Diagnostics.record("Picker", "closed; displayed \(BlockingRuntime.selectionSummary(model.selection))") }
            }
        }
    }

    private func preference(_ key: WritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
        Binding(get: { model.state.preferences[keyPath: key] }, set: { value in
            Task { await model.update { $0.preferences[keyPath: key] = value } }
        })
    }
}
