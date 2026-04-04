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
            Image(systemName: actionIcon)
                .foregroundStyle(actionColor)
                .imageScale(.small)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(description)
                    .font(.callout)
                    .lineLimit(1)
                Text(entry.action.replacingOccurrences(of: "_", with: " "))
                    .font(.caption2)
                    .foregroundStyle(actionColor)
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

    private var description: String {
        if let path = entry.filePath {
            let name = URL(fileURLWithPath: path).lastPathComponent
            switch entry.action {
            case "source_added": return "Folder \"\(name)\" added"
            case "source_removed": return "Folder \"\(name)\" removed"
            default: return name
            }
        }
        return entry.agent ?? entry.action.replacingOccurrences(of: "_", with: " ")
    }

    private var actionIcon: String {
        switch entry.action {
        case "file_read": return "eye"
        case "file_modified", "file_created": return "pencil"
        case "file_deleted": return "trash"
        case "mcp_connection": return "antenna.radiowaves.left.and.right"
        case "run_start": return "play.circle"
        case "run_end": return "stop.circle"
        case "restore": return "arrow.uturn.backward"
        case "source_added": return "plus.circle"
        case "source_removed": return "minus.circle"
        default: return "circle"
        }
    }

    private var actionColor: Color {
        switch entry.action {
        case "file_read": return .blue
        case "file_modified", "file_created": return .green
        case "file_deleted": return .red
        case "mcp_connection": return .accentColor
        case "restore": return .orange
        default: return .secondary
        }
    }
}
