import SwiftUI

struct MedicationsView: View {
    @EnvironmentObject private var model: TrackerModel
    @State private var editing: Medication?
    @State private var adding = false
    @State private var deleting: Medication?

    var body: some View {
        NavigationStack {
            List {
                if model.state.medications.isEmpty {
                    ContentUnavailableView("No medications yet", systemImage: "pills",
                                           description: Text("Tap + to create your first daily schedule."))
                }
                ForEach(model.state.medications) { medication in
                    Button { editing = medication } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(medication.name).font(.headline).foregroundStyle(.primary)
                            if !medication.dose.isEmpty { Text(medication.dose).foregroundStyle(.secondary) }
                            Text(medication.times.map { $0.formatted() }.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(.teal)
                        }.padding(.vertical, 5)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { deleting = medication }
                    }
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add medication", systemImage: "plus") { adding = true }
                        .accessibilityIdentifier("medications.add")
                }
            }
            .sheet(isPresented: $adding) { MedicationEditor(medication: nil) }
            .sheet(item: $editing) { MedicationEditor(medication: $0) }
            .confirmationDialog("Delete \(deleting?.name ?? "medication")?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                if let deleting {
                    Button("Delete medication", role: .destructive) {
                        Task { await model.delete(deleting.id); self.deleting = nil }
                    }
                }
            } message: {
                Text("Unresolved reminders for this medication will be cancelled. Recorded history stays on this iPhone.")
            }
        }
    }
}

struct MedicationEditor: View {
    @EnvironmentObject private var model: TrackerModel
    @Environment(\.dismiss) private var dismiss
    let medication: Medication?
    @State private var name: String
    @State private var dose: String
    @State private var times: [TimeEntry]
    @State private var validationError: String?

    struct TimeEntry: Identifiable {
        let id = UUID()
        var date: Date
    }

    init(medication: Medication?) {
        self.medication = medication
        _name = State(initialValue: medication?.name ?? "")
        _dose = State(initialValue: medication?.dose ?? "")
        let defaults = medication?.times ?? [DailyTime(hour: 8, minute: 0)]
        _times = State(initialValue: defaults.map {
            TimeEntry(date: DoseEngine.scheduledDate(on: Date(), time: $0, calendar: .current))
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Name", text: $name).textInputAutocapitalization(.words)
                        .accessibilityIdentifier("medication.name")
                    TextField("Dose description (optional)", text: $dose)
                        .accessibilityIdentifier("medication.dose")
                }
                Section {
                    ForEach($times) { $entry in
                        HStack {
                            DatePicker("Reminder time", selection: $entry.date, displayedComponents: .hourAndMinute)
                            if times.count > 1 {
                                Button("Remove time", systemImage: "minus.circle.fill", role: .destructive) {
                                    times.removeAll { $0.id == entry.id }
                                }.labelStyle(.iconOnly).buttonStyle(.borderless)
                            }
                        }
                    }
                    Button("Add daily time", systemImage: "plus") {
                        times.append(TimeEntry(date: Calendar.current.date(byAdding: .hour, value: 1, to: times.last?.date ?? Date()) ?? Date()))
                    }
                } header: { Text("Every day") } footer: {
                    Text("Times follow this iPhone’s local time zone. Changes apply to future doses; already due reminders keep their original details.")
                }
                if let validationError { Section { Text(validationError).foregroundStyle(.red) } }
            }
            .navigationTitle(medication == nil ? "Add medication" : "Edit medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWorking)
                        .accessibilityIdentifier("medication.save")
                }
            }
            .interactiveDismissDisabled(model.isWorking)
        }
    }

    private func save() async {
        let dailyTimes = times.map { entry in
            let c = Calendar.current.dateComponents([.hour, .minute], from: entry.date)
            return DailyTime(hour: c.hour!, minute: c.minute!)
        }
        if Set(dailyTimes).count != dailyTimes.count {
            validationError = "Choose different reminder times."
            return
        }
        let edited = Medication(id: medication?.id ?? UUID(), name: name, dose: dose,
                                times: dailyTimes.sorted(), effectiveFrom: Date())
        if await model.save(edited) { dismiss() }
    }
}

extension DailyTime {
    func formatted() -> String {
        DoseEngine.scheduledDate(on: Date(), time: self, calendar: .current).formatted(date: .omitted, time: .shortened)
    }
}
