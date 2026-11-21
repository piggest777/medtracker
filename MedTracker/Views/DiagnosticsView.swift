import SwiftUI

struct DiagnosticsView: View {
    @Environment(TrackerModel.self) private var model: TrackerModel
    @State private var report = ""
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Reproduce the issue, then refresh and copy this report. It contains selection counts and technical events, without app tokens or medication names.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Button("Refresh report", systemImage: "arrow.clockwise") {
                        report = model.diagnosticsReport()
                        copied = false
                    }
                    Spacer()
                    Button(copied ? "Copied" : "Copy report", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = report
                        copied = true
                    }.accessibilityIdentifier("diagnostics.copy")
                }.buttonStyle(.bordered)
                Text(report).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("diagnostics.report")
            }.padding()
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { report = model.diagnosticsReport() }
    }
}
