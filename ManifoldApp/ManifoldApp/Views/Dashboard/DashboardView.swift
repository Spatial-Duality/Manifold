import SwiftUI

struct DashboardView: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        List {
            DashboardSessionBanner()
            DashboardSourcesContent()
            DashboardRecentActivity()
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .navigationTitle("Sources")
        .navigationSubtitle(sourceSummary)
        .task { await store.loadSummary() }
    }

    private var sourceSummary: String {
        let visible = store.sources.filter { !$0.isRemoved }
        let active = visible.filter(\.isAccessible)
        if visible.isEmpty { return "No folders added" }
        if store.hasActiveSession { return "Session active — \(active.count) source\(active.count == 1 ? "" : "s")" }
        if active.count == visible.count { return "\(active.count) source\(active.count == 1 ? "" : "s")" }
        return "\(active.count) active, \(visible.count - active.count) paused"
    }
}

// MARK: - Session Banner

private struct DashboardSessionBanner: View {
    @Environment(ManifoldStore.self) var store

    private static let isoFormatter = ISO8601DateFormatter()

    private var visibleSources: [SourceRecord] {
        store.sources.filter { !$0.isRemoved }
    }

    var body: some View {
        if store.hasActiveSession, let grant = store.activeGrant {
            Section {
                VStack(alignment: .leading, spacing: Spacing.standard) {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Session Active")
                            .font(.body.weight(.medium))
                        Spacer()
                        Text(grant.grantID.prefix(12) + "...")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    HStack(spacing: Spacing.section) {
                        Label("\(store.activeGrantSources.count) sources", systemImage: "folder.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let started = Self.isoFormatter.date(from: grant.startedAt) {
                            Text(started, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("End Session") {
                        Task { await store.endSession() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.orange)
                }
                .padding(.vertical, Spacing.tight)
            }
        } else if !visibleSources.isEmpty {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No active session")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("Start a session to materialize sources for AI access.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Start Session") {
                        Task { await store.startSession() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.vertical, Spacing.tight)
            }
        }
    }
}

// MARK: - Sources Content

private struct DashboardSourcesContent: View {
    @Environment(ManifoldStore.self) var store

    private var visibleSources: [SourceRecord] {
        store.sources.filter { !$0.isRemoved }
    }

    var body: some View {
        if visibleSources.isEmpty {
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
                ForEach(visibleSources) { source in
                    SourceCardRow(source: source)
                }
            }
        }
    }
}

// MARK: - Recent Activity Glance

private struct DashboardRecentActivity: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
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
                    store.selectedSidebarItem = .history
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
    let source: SourceRecord

    @State private var fileCount: Int = 0
    @State private var confirmRemove = false

    private var shortenedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return source.originalRootPath.hasPrefix(home) ? "~" + source.originalRootPath.dropFirst(home.count) : source.originalRootPath
    }

    private var isOn: Binding<Bool> {
        Binding(
            get: { source.isAccessible },
            set: { newValue in
                Task {
                    if newValue {
                        await store.resumeSource(sourceID: source.sourceID)
                    } else {
                        await store.pauseSource(sourceID: source.sourceID)
                    }
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: Spacing.section) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(source.isAccessible ? Color(nsColor: .systemBlue) : Color.secondary.opacity(0.3))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(source.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(source.isAccessible ? .primary : .secondary)
                HStack(spacing: Spacing.tight) {
                    Text(shortenedPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if fileCount > 0 {
                        Text("·")
                        Text("\(fileCount) files")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            Toggle(source.isAccessible ? "Active" : "Paused", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(source.isAccessible ? "Active, toggle to pause" : "Paused, toggle to resume")

            Menu {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(source.originalRootPath, inFileViewerRootedAtPath: "")
                }
                Divider()
                Button("Remove from Manifold...", role: .destructive) {
                    confirmRemove = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.tertiary)
                    .imageScale(.medium)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, Spacing.tight)
        .opacity(source.isAccessible ? 1.0 : 0.6)
        .alert("Remove Source?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { store.removeSource(path: source.originalRootPath) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("File history for \"\(source.displayName)\" will remain. You can re-add this folder later.")
        }
        .task { await countFiles() }
    }

    private func countFiles() async {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: source.originalRootPath),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var count = 0
        while enumerator.nextObject() != nil { count += 1 }
        fileCount = count
    }
}
