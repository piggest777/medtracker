#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Exercises the real row layout without inventing Screen Time tokens.
/// The title deliberately expands vertically like a hosted activity label.
struct SelectionLayoutPreview: View {
    private var largeText: Bool { ProcessInfo.processInfo.arguments.contains("--large-selection-preview") }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Pause blocking", isOn: .constant(false))
                    LabeledContent("Screen Time", value: "Enabled")
                } header: { Text("App blocking") } footer: {
                    Text("Choose distractions to pause, keeping essential apps available.")
                }
                Section {
                    sample("X", icon: "xmark.square.fill", status: .available, id: "app")
                    sample("x.com", icon: "safari", status: .blocked, kind: "Website", id: "website")
                    sample("An application with a longer display name", icon: "app.fill", status: .paused, id: "long-name")
                    Button("Change selection") {}
                } header: { Text("Selected apps") } footer: {
                    Text("Selected apps pause when a dose is due and unlock after your check-in.")
                }
                Section("Reminders") { Toggle("Daily notifications", isOn: .constant(true)) }
            }
            .navigationTitle("Settings")
        }
        .environment(\.dynamicTypeSize, largeText ? .accessibility2 : .large)
        .preferredColorScheme(.dark)
    }

    private func sample(_ name: String, icon: String, status: AppBlockingStatus,
                        kind: String? = nil, id: String) -> some View {
        SelectedAppRow(status: status, kind: kind) {
            Label {
                Text(name).frame(maxHeight: .infinity)
            } icon: {
                Image(systemName: icon).resizable().scaledToFit()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selection-preview.\(id)")
    }
}
#endif
