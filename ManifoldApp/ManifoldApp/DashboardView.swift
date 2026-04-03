import SwiftUI
import ManifoldKit

/// Single-window MCP dashboard. Status bar + live activity + rules.
struct DashboardView: View {
    @EnvironmentObject var store: ManifoldStore
    @State private var showSetup = false

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            StatusBarView()

            Divider()

            // Main content: activity feed + rules sidebar
            HSplitView {
                // Activity feed (main, larger)
                ActivityFeedView()
                    .frame(minWidth: 350)

                // Rules panel (right side, narrower)
                RulesPanel()
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
            }
        }
        .navigationTitle("Manifold")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Source", systemImage: "folder.badge.plus") {
                    store.addSourceFromPicker()
                }
            }
            if !store.mcpInstalled {
                ToolbarItem(placement: .automatic) {
                    Button("Install MCP", systemImage: "arrow.down.circle") {
                        store.installMCP()
                    }
                    .tint(.accentColor)
                }
            }
        }
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    @EnvironmentObject var store: ManifoldStore

    var body: some View {
        HStack(spacing: 12) {
            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(store.isConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                if let agent = store.connectedAgent {
                    Text("\(agent) connected")
                        .font(.callout.weight(.medium))
                } else {
                    Text("No agents connected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Stats
            Text("\(store.approvedSources.count) sources")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !store.mcpInstalled {
                Label("MCP not installed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Activity Feed

struct ActivityFeedView: View {
    @EnvironmentObject var store: ManifoldStore

    var body: some View {
        Group {
            if store.activityEntries.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "waveform.path",
                    description: Text("MCP activity will appear here when agents connect.")
                )
            } else {
                List {
                    ForEach(Array(store.activityEntries.enumerated()), id: \.offset) { _, entry in
                        ActivityEntryRow(entry: entry)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct ActivityEntryRow: View {
    let entry: AuditEntry

    var body: some View {
        HStack(spacing: 8) {
            // Action icon
            Image(systemName: actionIcon)
                .foregroundStyle(actionColor)
                .imageScale(.small)
                .frame(width: 16)

            // Timestamp
            Text(shortTimestamp)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 50, alignment: .leading)

            // Action type
            Text(entry.action.replacingOccurrences(of: "_", with: " ").uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(actionColor)
                .frame(width: 80, alignment: .leading)

            // File path or details
            if let path = entry.filePath {
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let agent = entry.agent, !agent.isEmpty {
                Text(agent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
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

    private var shortTimestamp: String {
        // Extract time from ISO 8601
        if let tIndex = entry.timestamp.firstIndex(of: "T") {
            let time = entry.timestamp[entry.timestamp.index(after: tIndex)...]
            return String(time.prefix(8))
        }
        return entry.timestamp.suffix(8).description
    }
}

// MARK: - Rules Panel

struct RulesPanel: View {
    @EnvironmentObject var store: ManifoldStore

    var body: some View {
        List {
            Section("Approved Sources") {
                if store.approvedSources.isEmpty {
                    Text("No sources. Click + in toolbar.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(store.approvedSources, id: \.self) { path in
                        HStack {
                            Label(shortenPath(path), systemImage: "folder")
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer()
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.removeSource(path: path)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("Email Rules") {
                Label("Banking domains auto-hidden", systemImage: "building.columns")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("2FA codes auto-hidden", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Healthcare auto-hidden", systemImage: "cross.case")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Menu Bar

struct MenuBarView: View {
    @EnvironmentObject var store: ManifoldStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status
            HStack {
                Circle()
                    .fill(store.isConnected ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                if let agent = store.connectedAgent {
                    Text("\(agent) connected")
                        .font(.caption.weight(.medium))
                } else {
                    Text("No agents connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Recent activity
            if store.activityEntries.isEmpty {
                Text("No recent activity")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(12)
            } else {
                ForEach(Array(store.activityEntries.prefix(5).enumerated()), id: \.offset) { _, entry in
                    HStack {
                        Text(entry.action.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                        if let path = entry.filePath {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                }
            }

            Divider()

            Button("Open Manifold") {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Button("Quit Manifold") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .frame(width: 260)
    }
}

// MARK: - Previews

#Preview("Dashboard") {
    DashboardView()
        .environmentObject(ManifoldStore())
        .frame(width: 800, height: 600)
}
