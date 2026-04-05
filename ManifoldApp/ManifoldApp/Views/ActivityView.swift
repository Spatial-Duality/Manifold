import SwiftUI
import ManifoldKit

struct ActivityView: View {
    @Environment(ManifoldStore.self) var store
    @State private var actionFilter = "all"
    @State private var searchText = ""
    @State private var filteredEntries: [AuditEntry] = []

    private func refilter() {
        var entries = store.activityEntries
        if actionFilter != "all" { entries = entries.filter { $0.action == actionFilter } }
        if !searchText.isEmpty {
            entries = entries.filter {
                ($0.filePath ?? "").localizedCaseInsensitiveContains(searchText) ||
                $0.action.localizedCaseInsensitiveContains(searchText)
            }
        }
        filteredEntries = entries
    }

    var body: some View {
        List {
            // Inline filter
            Picker("Filter", selection: $actionFilter) {
                Text("All").tag("all")
                Text("Reads").tag("file_read")
                Text("Writes").tag("file_modified")
                Text("Tool Calls").tag("tool_call")
                Text("Connections").tag("mcp_connection")
                Text("Restores").tag("restore")
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

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
        .task { refilter() }
        .onChange(of: store.activityEntries.count) { _, _ in Task { @MainActor in refilter() } }
        .onChange(of: actionFilter) { _, _ in Task { @MainActor in refilter() } }
        .onChange(of: searchText) { _, _ in Task { @MainActor in refilter() } }
    }
}
