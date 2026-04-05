import SwiftUI
import ManifoldKit

struct DashboardView: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        List {
            sourcesContent
            recentActivityGlance
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .navigationTitle("Sources")
        .navigationSubtitle(sourceSummary)
        .task { await store.loadSummary() }
    }

    private var sourceSummary: String {
        let visible = visibleWorkspaces
        let active = visible.filter { $0.status != "archived" }
        if visible.isEmpty { return "No folders added" }
        if active.count == visible.count { return "\(active.count) source\(active.count == 1 ? "" : "s")" }
        return "\(active.count) active, \(visible.count - active.count) paused"
    }

    // MARK: - Sources

    /// Workspaces visible in the dashboard — excludes removed sources.
    private var visibleWorkspaces: [WorkspaceRecord] {
        store.workspaces.filter { $0.status != "removed" }
    }

    @ViewBuilder
    private var sourcesContent: some View {
        if visibleWorkspaces.isEmpty {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No folders added yet")
                        .font(.headline)
                    Text("Add a folder to let AI agents access your files.\nEverything they touch is versioned and recoverable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Add Folder") {
                        store.addSourceFromPicker()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.large)
            }
        } else {
            Section {
                ForEach(visibleWorkspaces, id: \.workspaceID) { ws in
                    SourceCardRow(workspace: ws)
                }
            }
        }
    }

    // MARK: - Recent Activity Glance

    @ViewBuilder
    private var recentActivityGlance: some View {
        if !store.activityEntries.isEmpty {
            Section {
                ForEach(store.activityEntries.prefix(3)) { entry in
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
            } header: {
                Text("Recent Activity")
            }
        }
    }
}

// MARK: - Source Card Row

struct SourceCardRow: View {
    @Environment(ManifoldStore.self) var store
    let workspace: WorkspaceRecord

    @State private var fileCount: Int = 0
    @State private var confirmRemove = false

    private var folderName: String { URL(fileURLWithPath: workspace.rootPath).lastPathComponent }
    private var shortenedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return workspace.rootPath.hasPrefix(home) ? "~" + workspace.rootPath.dropFirst(home.count) : workspace.rootPath
    }
    private var isActive: Bool { workspace.status != "archived" }

    var body: some View {
        HStack(spacing: 12) {
            // Folder icon
            Image(systemName: isActive ? "folder.fill" : "folder")
                .font(.title2)
                .foregroundStyle(isActive ? .blue : .secondary)
                .frame(width: 32)

            // Name + path
            VStack(alignment: .leading, spacing: 2) {
                Text(folderName)
                    .font(.body.weight(.medium))
                Text(shortenedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // File count
            Text("\(fileCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            Text("files")
                .font(.caption)
                .foregroundStyle(.tertiary)

            // Toggle: Active / Paused
            Button {
                Task {
                    if isActive {
                        await store.pauseSource(workspaceID: workspace.workspaceID)
                    } else {
                        await store.resumeSource(workspaceID: workspace.workspaceID)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isActive ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(isActive ? "Active" : "Paused")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .accessibilityLabel("Source \(isActive ? "active" : "paused"), tap to toggle")
                }
                .padding(.horizontal, Spacing.standard)
                .padding(.vertical, Spacing.tight)
                .background(isActive ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Overflow menu
            Menu {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(workspace.rootPath, inFileViewerRootedAtPath: "")
                }
                Divider()
                if isActive {
                    Button("Pause Access") {
                        Task { await store.pauseSource(workspaceID: workspace.workspaceID) }
                    }
                } else {
                    Button("Resume Access") {
                        Task { await store.resumeSource(workspaceID: workspace.workspaceID) }
                    }
                }
                Divider()
                Button("Remove from Manifold...", role: .destructive) {
                    confirmRemove = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.vertical, Spacing.tight)
        .alert("Remove Source?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { store.removeSource(path: workspace.rootPath) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("File history for \"\(folderName)\" will remain. You can re-add this folder later.")
        }
        .task { await countFiles() }
    }

    private func countFiles() async {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: workspace.rootPath),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var count = 0
        while enumerator.nextObject() != nil { count += 1 }
        fileCount = count
    }
}
