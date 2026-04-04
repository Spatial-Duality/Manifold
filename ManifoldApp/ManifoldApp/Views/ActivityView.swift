import SwiftUI
import ManifoldKit

struct ActivityView: View {
    @EnvironmentObject var store: ManifoldStore
    @State private var actionFilter = "all"
    @State private var searchText = ""

    private var filteredEntries: [AuditEntry] {
        var entries = store.activityEntries
        if actionFilter != "all" { entries = entries.filter { $0.action == actionFilter } }
        if !searchText.isEmpty {
            entries = entries.filter {
                ($0.filePath ?? "").localizedCaseInsensitiveContains(searchText) ||
                $0.action.localizedCaseInsensitiveContains(searchText)
            }
        }
        return entries
    }

    var body: some View {
        List {
            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "waveform.path",
                    description: Text(store.mcpInstalled
                        ? "Activity will appear when agents connect."
                        : "Install the MCP server in Settings first.")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredEntries) { entry in
                    ActivityRow(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let path = entry.filePath {
                                store.inspectedFilePath = path
                            }
                        }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .navigationTitle("Activity")
        .navigationSubtitle("\(filteredEntries.count) events")
        .searchable(text: $searchText, prompt: "Search files...")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Filter", selection: $actionFilter) {
                    Text("All").tag("all")
                    Divider()
                    Text("Reads").tag("file_read")
                    Text("Writes").tag("file_modified")
                    Text("Connections").tag("mcp_connection")
                    Text("Restores").tag("restore")
                }
                .pickerStyle(.menu)
            }
        }
    }
}

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
                    .font(.callout)
                    .lineLimit(1)
                Text(entry.action.replacingOccurrences(of: "_", with: " "))
                    .font(.caption2)
                    .foregroundStyle(ActionFormatting.color(for: entry.action))
            }

            Spacer()

            TimeLabel(iso8601: entry.timestamp)

            if entry.filePath != nil {
                Image(systemName: "sidebar.right")
                    .foregroundStyle(.quaternary)
                    .imageScale(.small)
            }
        }
    }
}
