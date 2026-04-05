import SwiftUI
import ManifoldKit

struct RecentActivitySection: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        Section("Recent Activity") {
            if store.activityEntries.isEmpty {
                Text("No recent activity").foregroundStyle(.tertiary)
            } else {
                ForEach(store.activityEntries.prefix(5)) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: ActionFormatting.icon(for: entry.action))
                            .foregroundStyle(ActionFormatting.color(for: entry.action))
                            .imageScale(.small)
                            .frame(width: 16)
                        Text(ActionFormatting.description(for: entry))
                            .font(.callout).lineLimit(1)
                        Spacer()
                        TimeLabel(iso8601: entry.timestamp)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let path = entry.filePath {
                            store.inspectedFilePath = path
                        }
                    }
                }
                Button {
                    store.selectedSidebarItem = .activity
                } label: {
                    HStack {
                        Text("See All Activity")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
