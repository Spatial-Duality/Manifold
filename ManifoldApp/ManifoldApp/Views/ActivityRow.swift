import SwiftUI

struct ActivityRow: View {
    let entry: AuditEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ActionFormatting.icon(for: entry.action))
                .foregroundStyle(ActionFormatting.color(for: entry.action))
                .imageScale(.small)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(ActionFormatting.description(for: entry))
                    .font(.callout).lineLimit(1)
                Text(entry.action.replacingOccurrences(of: "_", with: " "))
                    .font(.caption2)
                    .foregroundStyle(ActionFormatting.color(for: entry.action))
            }

            Spacer()
            TimeLabel(iso8601: entry.timestamp)

            if entry.filePath != nil {
                Image(systemName: "sidebar.right")
                    .foregroundStyle(.quaternary).imageScale(.small)
            }
        }
    }
}
