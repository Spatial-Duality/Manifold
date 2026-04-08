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
        if snapshot.isDelete { "trash" }
        else if snapshot.isBaseline { "flag" }
        else if snapshot.source == "manifold-restore" { "arrow.uturn.backward" }
        else { "pencil" }
    }

    private var iconColor: Color {
        if snapshot.isDelete { .red }
        else if snapshot.isBaseline { .blue }
        else if snapshot.source == "manifold-restore" { .orange }
        else { .green }
    }

    private var label: String {
        if snapshot.isDelete { "DELETED" }
        else if snapshot.isBaseline { "BASELINE" }
        else if snapshot.source == "manifold-restore" { "RESTORED" }
        else { "MODIFIED" }
    }
}
