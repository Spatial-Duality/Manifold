import SwiftUI
import ManifoldKit

struct SummaryView: View {
    @EnvironmentObject var store: ManifoldStore

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                // Connection
                SummaryCard(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Connection",
                    color: store.isConnected ? .green : .gray
                ) {
                    if store.isConnected {
                        AgentBadge(agent: store.connectedAgent ?? "Claude")
                    } else {
                        Text("No agents connected")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } action: {
                    store.selectedSection = .activity
                }

                // Sources
                SummaryCard(
                    icon: "folder.badge.gearshape",
                    title: "Sources",
                    color: .blue
                ) {
                    Text("\(store.approvedSources.count) folders")
                        .font(.title3.weight(.semibold))
                    Text("\(store.workspaces.filter { $0.status == "active" }.count) active")
                        .font(.caption).foregroundStyle(.secondary)
                } action: {
                    store.selectedSection = .sources
                }

                // Emails
                SummaryCard(
                    icon: "envelope.badge.shield.half.filled",
                    title: "Emails",
                    color: .orange
                ) {
                    if let classification = store.emailClassification {
                        Text("\(classification.shared) shared")
                            .font(.title3.weight(.semibold))
                        Text("\(classification.autoHidden) hidden")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Not configured")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } action: {
                    store.selectedSection = .emails
                }

                // Storage
                SummaryCard(
                    icon: "internaldrive",
                    title: "Storage",
                    color: .purple
                ) {
                    Text(formatBytes(store.storageUsed))
                        .font(.title3.weight(.semibold))
                    Text("\(store.blobCount) versions of \(store.allTrackedFiles.count) files")
                        .font(.caption).foregroundStyle(.secondary)
                } action: {
                    store.selectedSection = .versions
                }

                // Activity
                SummaryCard(
                    icon: "waveform.path.ecg",
                    title: "Recent Activity",
                    color: .green
                ) {
                    Text("\(store.activityEntries.count) events")
                        .font(.title3.weight(.semibold))
                    if let latest = store.activityEntries.first {
                        Text(latest.action.replacingOccurrences(of: "_", with: " "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } action: {
                    store.selectedSection = .activity
                }

                // Setup
                SummaryCard(
                    icon: "gearshape",
                    title: "Setup",
                    color: store.mcpInstalled ? .green : .yellow
                ) {
                    if store.mcpInstalled {
                        Text("MCP Server installed")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        Text("MCP not installed")
                            .font(.caption).foregroundStyle(.yellow)
                    }
                } action: {
                    store.selectedSection = .setup
                }
            }
            .padding(20)

            // Quick Actions
            HStack(spacing: 12) {
                Button("Add Source") { store.addSourceFromPicker() }
                    .buttonStyle(.bordered)
                if !store.mcpInstalled {
                    Button("Install MCP") { store.installMCP() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.bottom, 20)
        }
        .navigationTitle("Summary")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct SummaryCard<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let content: () -> Content
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
