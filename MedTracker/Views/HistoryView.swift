import SwiftUI

struct HistoryView: View {
    @Environment(TrackerModel.self) private var model: TrackerModel

    var body: some View {
        NavigationStack {
            List {
                if model.isTesting {
                    Section {
                        Text("This is your real medication history. Practice results appear in Test mode.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if model.history.isEmpty {
                    ContentUnavailableView("No check-ins yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("Taken, skipped, and missed doses will appear here."))
                }
                ForEach(model.history) { occurrence in
                    VStack(alignment: .leading, spacing: 6) {
                        DoseRow(occurrence: occurrence)
                        Text(occurrence.scheduledAt, format: .dateTime.year().month(.abbreviated).day())
                            .font(.caption).foregroundStyle(.secondary)
                        if let reported = occurrence.reportedAt {
                            Text("Recorded \(reported.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}
