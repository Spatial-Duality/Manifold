import SwiftUI
import ManifoldKit

struct SidebarView: View {
    @EnvironmentObject var store: ManifoldStore

    var body: some View {
        List(selection: $store.selectedSidebarItem) {
            // Overview
            Label("Summary", systemImage: "gauge.open.with.lines.needle.33percent")
                .tag(SidebarItem.summary as SidebarItem?)

            // Sources (with sub-items for each workspace)
            Section("Sources") {
                ForEach(store.workspaces) { ws in
                    Label(shortenPath(ws.rootPath), systemImage: ws.status == "active" ? "folder.fill" : "folder")
                        .tag(SidebarItem.sourceDetail(ws.workspaceID) as SidebarItem?)
                        .badge(ws.status == "active" ? Text("Active").foregroundStyle(.green) : nil)
                }
                if store.workspaces.isEmpty {
                    Label("Add a source...", systemImage: "folder.badge.plus")
                        .foregroundStyle(.secondary)
                        .tag(SidebarItem.sources as SidebarItem?)
                }
            }

            // Emails
            Section("Emails") {
                Label("Overview", systemImage: "envelope")
                    .tag(SidebarItem.emailOverview as SidebarItem?)
                Label("Inbox", systemImage: "tray")
                    .tag(SidebarItem.emailInbox as SidebarItem?)
                    .badge(store.cachedEmails.filter(\.isShared).count)
                Label("Rules", systemImage: "list.bullet.rectangle")
                    .tag(SidebarItem.emailRules as SidebarItem?)
            }

            // Monitor
            Section("Monitor") {
                Label("Activity", systemImage: "waveform.path.ecg")
                    .tag(SidebarItem.activity as SidebarItem?)
                    .badge(store.activityEntries.count)
                Label("Versions", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .tag(SidebarItem.versions as SidebarItem?)
                    .badge(store.allTrackedFiles.count)
            }
        }
        .listStyle(.sidebar)
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

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let short = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
