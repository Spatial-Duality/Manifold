import SwiftUI
import ManifoldKit

struct ActivityView: View {
    @EnvironmentObject var store: ManifoldStore
    @State private var actionFilter = "all"
    @State private var searchText = ""
    @State private var showVersionHistory = false
    @State private var selectedFilePath: String?

    private let actionFilters = ["all", "file_read", "file_modified", "file_created", "mcp_connection", "restore"]

    private var filteredEntries: [AuditEntry] {
        var entries = store.activityEntries
        if actionFilter != "all" {
            entries = entries.filter { $0.action == actionFilter }
        }
        if !searchText.isEmpty {
            entries = entries.filter {
                ($0.filePath ?? "").localizedCaseInsensitiveContains(searchText) ||
                $0.action.localizedCaseInsensitiveContains(searchText) ||
                ($0.agent ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return entries
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 8) {
                Picker("Action", selection: $actionFilter) {
                    Text("All").tag("all")
                    Text("Reads").tag("file_read")
                    Text("Writes").tag("file_modified")
                    Text("Created").tag("file_created")
                    Text("Connections").tag("mcp_connection")
                    Text("Restores").tag("restore")
                }
                .frame(maxWidth: 200)

                Spacer()

                Text("\(filteredEntries.count) events")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "waveform.path",
                    description: Text(store.mcpInstalled
                        ? "MCP activity will appear here when agents connect."
                        : "Install the MCP server first in Setup.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            ActivityRow(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let path = entry.filePath {
                                        selectedFilePath = path
                                        showVersionHistory = true
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
        }
        .navigationTitle("Activity")
        .searchable(text: $searchText, prompt: "Search files, agents...")
        .sheet(isPresented: $showVersionHistory) {
            if let path = selectedFilePath {
                VersionDetailView(filePath: path)
                    .environmentObject(store)
                    .frame(minWidth: 700, minHeight: 450)
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

            TimeLabel(iso8601: entry.timestamp)
                .frame(width: 60, alignment: .leading)

            Text(entry.action.replacingOccurrences(of: "_", with: " ").uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(actionColor)
                .frame(width: 80, alignment: .leading)

            if let path = entry.filePath {
                Text(actionDescription(path: path))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let agent = entry.agent, !agent.isEmpty {
                AgentBadge(agent: agent)
            }

            Spacer()

            if entry.filePath != nil {
                Image(systemName: "clock.arrow.counterclockwise")
                    .foregroundStyle(.quaternary)
                    .imageScale(.small)
            }
        }
    }

    private func actionDescription(path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        switch entry.action {
        case "source_added": return "Folder \"\(name)\" added"
        case "source_removed": return "Folder \"\(name)\" removed"
        case "file_read": return path
        case "file_modified": return path
        case "file_created": return path
        default: return path
        }
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
        case "sensitivity_warning": return .yellow
        default: return .secondary
        }
    }
}
