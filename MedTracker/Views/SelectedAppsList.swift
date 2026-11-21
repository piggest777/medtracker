import SwiftUI
import FamilyControls

struct SelectedAppsList: View {
    @Environment(TrackerModel.self) private var model: TrackerModel

    var body: some View {
        let selection = model.selection
        ForEach(selection.applicationTokens.sorted { $0.hashValue < $1.hashValue }, id: \.self) { token in
            SelectedAppRow(status: model.appStatus(isShielded: model.appliedShields.applications.contains(token))) {
                Label(token)
            }
        }
        ForEach(selection.categoryTokens.sorted { $0.hashValue < $1.hashValue }, id: \.self) { token in
            SelectedAppRow(status: model.appStatus(isShielded: model.appliedShields.categories.contains(token)), kind: "Category") {
                Label(token)
            }
        }
        ForEach(selection.webDomainTokens.sorted { $0.hashValue < $1.hashValue }, id: \.self) { token in
            SelectedAppRow(status: model.appStatus(isShielded: model.appliedShields.websites.contains(token)), kind: "Website") {
                Label(token)
            }
        }
    }
}

struct SelectedAppRow<Content: View>: View {
    let status: AppBlockingStatus
    var kind: String?
    @ViewBuilder var content: () -> Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var color: Color {
        switch status {
        case .blocked, .needsAccess, .notBlocked, .unavailable: return .orange
        case .available: return .teal
        case .paused, .notScheduled, .preview: return .secondary
        }
    }

    var body: some View {
        Group {
            // Native activity labels have flexible hosted content. Do not ask
            // ViewThatFits to measure them with an unbounded ideal height.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    activityLabel
                    statusLabel
                }
            } else {
                HStack(spacing: 12) {
                    activityLabel.frame(maxWidth: .infinity, alignment: .leading)
                    statusLabel
                }
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .padding(.vertical, 4)
        .onAppear { Diagnostics.record("UI", "selected item row appeared kind=\(kind ?? "App") status=\(status.title)") }
    }

    private var activityLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            content().labelStyle(CompactActivityLabelStyle())
            if let kind { Text(kind).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: status.icon).accessibilityHidden(true)
            Text(status.title)
        }
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.1), in: Capsule())
            .fixedSize(horizontal: true, vertical: true)
    }
}

private struct CompactActivityLabelStyle: LabelStyle {
    @ScaledMetric(relativeTo: .body) private var iconSize = 30.0
    @ScaledMetric(relativeTo: .body) private var titleHeight = 24.0

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            configuration.title
                .font(.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: titleHeight)
                .clipped()
        }
        .frame(height: max(iconSize, titleHeight))
    }
}
