import SwiftUI
import ManifoldKit

struct SnapshotRow: View {
    let snapshot: SnapshotRecord
    let isRestored: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(iconColor).imageScale(.small).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                TimeLabel(iso8601: snapshot.timestamp)
                HStack(spacing: 4) {
                    Text(label).font(.caption.weight(.medium)).foregroundStyle(iconColor)
                    if snapshot.source != "agent" {
                        Text("(\(snapshot.source))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if isRestored {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).imageScale(.small)
            }
        }
        .padding(.vertical, Spacing.tight + 2)
    }

    private var icon: String {
        if snapshot.isDelete { return "trash" }
        if snapshot.isBaseline { return "flag" }
        if snapshot.source == "manifold-restore" { return "arrow.uturn.backward" }
        return "pencil"
    }
    private var iconColor: Color {
        if snapshot.isDelete { return .red }
        if snapshot.isBaseline { return .blue }
        if snapshot.source == "manifold-restore" { return .orange }
        return .green
    }
    private var label: String {
        if snapshot.isDelete { return "DELETED" }
        if snapshot.isBaseline { return "BASELINE" }
        if snapshot.source == "manifold-restore" { return "RESTORED" }
        return "MODIFIED"
    }
}
