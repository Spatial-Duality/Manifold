import SwiftUI
import ManifoldKit

struct SidebarView: View {
    @EnvironmentObject var store: ManifoldStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                // Summary
                SidebarRow(
                    label: "Summary",
                    icon: "gauge.open.with.lines.needle.33percent",
                    isSelected: store.selectedSidebarItem == .summary
                ) { store.selectedSidebarItem = .summary }

                // Sources
                SidebarHeader("Sources")

                if store.workspaces.isEmpty {
                    SidebarRow(
                        label: "Add a source...",
                        icon: "folder.badge.plus",
                        isSelected: store.selectedSidebarItem == .sources,
                        dimmed: true
                    ) { store.selectedSidebarItem = .sources }
                } else {
                    ForEach(store.workspaces) { ws in
                        SidebarRow(
                            label: URL(fileURLWithPath: ws.rootPath).lastPathComponent,
                            icon: ws.status == "active" ? "folder.fill" : "folder",
                            isSelected: store.selectedSidebarItem == .sourceDetail(ws.workspaceID),
                            badge: ws.status == "active" ? "Active" : nil,
                            badgeColor: .green
                        ) { store.selectedSidebarItem = .sourceDetail(ws.workspaceID) }
                    }
                }

                // Emails
                SidebarHeader("Emails")

                SidebarRow(
                    label: "Overview",
                    icon: "envelope",
                    isSelected: store.selectedSidebarItem == .emailOverview
                ) { store.selectedSidebarItem = .emailOverview }

                SidebarRow(
                    label: "Inbox",
                    icon: "tray",
                    isSelected: store.selectedSidebarItem == .emailInbox,
                    count: store.cachedEmails.filter(\.isShared).count
                ) { store.selectedSidebarItem = .emailInbox }

                SidebarRow(
                    label: "Rules",
                    icon: "list.bullet.rectangle",
                    isSelected: store.selectedSidebarItem == .emailRules
                ) { store.selectedSidebarItem = .emailRules }

                // Monitor
                SidebarHeader("Monitor")

                SidebarRow(
                    label: "Activity",
                    icon: "waveform.path.ecg",
                    isSelected: store.selectedSidebarItem == .activity,
                    count: store.activityEntries.count
                ) { store.selectedSidebarItem = .activity }

                SidebarRow(
                    label: "Versions",
                    icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    isSelected: store.selectedSidebarItem == .versions,
                    count: store.allTrackedFiles.count
                ) { store.selectedSidebarItem = .versions }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .navigationTitle("Manifold")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Source", systemImage: "folder.badge.plus") {
                    store.addSourceFromPicker()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                Circle()
                    .fill(store.isConnected ? Color.green : Color.gray)
                    .frame(width: 7, height: 7)
                Text(store.isConnected ? (store.connectedAgent ?? "Connected") : "No agents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.mcpInstalled {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .imageScale(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .task {
            await store.loadWorkspaces()
            await store.loadTrackedFiles()
            await store.loadCachedEmails()
        }
    }
}

// MARK: - Sidebar Components

struct SidebarHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }
}

struct SidebarRow: View {
    let label: String
    let icon: String
    let isSelected: Bool
    var dimmed: Bool = false
    var badge: String? = nil
    var badgeColor: Color = .accentColor
    var count: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(dimmed ? Color.gray : (isSelected ? Color.white : Color.secondary))
                    .frame(width: 18)
                Text(label)
                    .foregroundStyle(dimmed ? Color.gray : (isSelected ? Color.white : Color.primary))
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : badgeColor)
                }
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
