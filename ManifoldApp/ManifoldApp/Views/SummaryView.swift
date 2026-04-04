import SwiftUI
import ManifoldKit

struct SummaryView: View {
    @EnvironmentObject var store: ManifoldStore

    var body: some View {
        List {
            // Connection
            Section {
                HStack(spacing: 10) {
                    Circle()
                        .fill(store.isConnected ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.isConnected ? (store.connectedAgent ?? "Agent") + " connected" : "No agents connected")
                            .font(.body.weight(.medium))
                        if store.isConnected {
                            Text("MCP server active, monitoring file access")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            } header: {
                Text("Connection")
            }

            // Sources
            Section {
                LabeledContent("Approved folders") {
                    Text("\(store.approvedSources.count)")
                        .monospacedDigit()
                }
                LabeledContent("Active runs") {
                    Text("\(store.workspaces.filter { $0.status == "active" }.count)")
                        .monospacedDigit()
                }
                if !store.mcpInstalled {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("MCP server not installed")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Install") { store.installMCP() }
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("Sources")
            }

            // Emails
            Section {
                if let classification = store.emailClassification {
                    LabeledContent("Shared with agents") {
                        Text("\(classification.shared)")
                            .foregroundStyle(.green)
                            .monospacedDigit()
                    }
                    LabeledContent("Auto-hidden") {
                        Text("\(classification.autoHidden)")
                            .foregroundStyle(.orange)
                            .monospacedDigit()
                    }
                } else {
                    Text("Not configured")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Emails")
            }

            // Storage
            Section {
                LabeledContent("Disk usage") {
                    Text(formatBytes(store.storageUsed))
                        .monospacedDigit()
                }
                LabeledContent("Versions stored") {
                    Text("\(store.blobCount)")
                        .monospacedDigit()
                }
                LabeledContent("Files tracked") {
                    Text("\(store.allTrackedFiles.count)")
                        .monospacedDigit()
                }
            } header: {
                Text("Storage")
            }

            // Recent Activity
            Section {
                if store.activityEntries.isEmpty {
                    Text("No recent activity")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(store.activityEntries.prefix(5)) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: iconFor(entry.action))
                                .foregroundStyle(colorFor(entry.action))
                                .imageScale(.small)
                                .frame(width: 16)
                            Text(descriptionFor(entry))
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            TimeLabel(iso8601: entry.timestamp)
                        }
                    }
                }
            } header: {
                Text("Recent Activity")
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .navigationTitle("Summary")
        .navigationSubtitle(store.isConnected ? "Protected" : "Idle")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func iconFor(_ action: String) -> String {
        switch action {
        case "file_read": return "eye"
        case "file_modified", "file_created": return "pencil"
        case "file_deleted": return "trash"
        case "mcp_connection": return "antenna.radiowaves.left.and.right"
        case "source_added": return "plus.circle"
        case "source_removed": return "minus.circle"
        case "restore": return "arrow.uturn.backward"
        default: return "circle"
        }
    }

    private func colorFor(_ action: String) -> Color {
        switch action {
        case "file_read": return .blue
        case "file_modified", "file_created": return .green
        case "file_deleted": return .red
        case "mcp_connection": return .accentColor
        case "restore": return .orange
        default: return .secondary
        }
    }

    private func descriptionFor(_ entry: AuditEntry) -> String {
        if let path = entry.filePath {
            let name = URL(fileURLWithPath: path).lastPathComponent
            switch entry.action {
            case "source_added": return "Folder \"\(name)\" added"
            case "source_removed": return "Folder \"\(name)\" removed"
            default: return "\(entry.action.replacingOccurrences(of: "_", with: " ")) \(name)"
            }
        }
        return entry.action.replacingOccurrences(of: "_", with: " ")
    }
}
