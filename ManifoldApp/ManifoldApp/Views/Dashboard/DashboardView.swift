import SwiftUI
import ManifoldKit

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
                    .glassButton()
                    .controlSize(.small)
                    .tint(.orange)
                }
                .padding(.vertical, Spacing.tight)
            }
        } else if store.session.isComputing {
            Section {
                HStack(spacing: Spacing.standard) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning sources...")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, Spacing.tight)
            }
        } else if let error = store.session.previewError {
            Section {
                VStack(alignment: .leading, spacing: Spacing.standard) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: .systemOrange))
                    Button("Try Again") {
                        Task { await store.startSession() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, Spacing.tight)
            }
        } else if store.session.isPreviewing, let preview = store.session.preview {
            Section {
                SessionPreviewCard(preview: preview)
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
                    .disabled(store.session.isComputing)
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

// MARK: - Session Preview Card

private struct SessionPreviewCard: View {
    @Environment(ManifoldStore.self) var store
    let preview: SessionPreview

    private var summaryLine: String {
        var parts: [String] = []
        parts.append("\(preview.totalFiles) files")
        parts.append(ByteCountFormatter.string(fromByteCount: preview.totalBytes, countStyle: .file))
        if preview.emailCount > 0 {
            parts.append("\(preview.visibleEmailCount) emails accessible")
        }
        return parts.joined(separator: " · ")
    }

    private var sensitivityLabel: String? {
        guard preview.emailsFiltered else { return nil }
        switch preview.sensitivityLevel {
        case .strict:
            return "\(preview.visibleEmailCount) of \(preview.emailCount) emails visible (Strict — shared only)"
        case .moderate:
            return "\(preview.visibleEmailCount) of \(preview.emailCount) emails visible (Moderate filtering)"
        case .open:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            // 1. Decision payload header
            Text("Grant AI access to \(preview.sources.count) source\(preview.sources.count == 1 ? "" : "s")")
                .font(.body.weight(.medium))

            // 2. Summary totals
            Text(summaryLine)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            // 3. Email sensitivity context
            if let sensitivity = sensitivityLabel {
                Text(sensitivity)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // 4. Per-source breakdown
            ForEach(preview.sources, id: \.sourceID) { source in
                HStack {
                    Label {
                        Text(source.displayName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "folder.fill")
                    }
                    Spacer()
                    Text("\(source.fileCount) files")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: source.totalBytes, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 5. Size warnings
            if preview.exceedsBlockThreshold {
                Label("Session exceeds 50 GB limit. Remove sources to proceed.", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .font(.caption)
                    .accessibilityLabel("Error: Session exceeds 50 gigabyte limit. Remove sources to proceed.")
            } else if preview.exceedsWarnThreshold {
                Label(
                    "Large session (\(ByteCountFormatter.string(fromByteCount: preview.totalBytes, countStyle: .file))). This may take a while.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(Color(nsColor: .systemYellow))
                .font(.caption)
                .accessibilityLabel("Warning: Large session, \(ByteCountFormatter.string(fromByteCount: preview.totalBytes, countStyle: .file)). This may take a while.")
            }

            // 6. Actions
            HStack(spacing: Spacing.section) {
                Button("Confirm") {
                    Task { await store.startSession() }
                }
                .glassProminentButton()
                .tint(.accentColor)
                .controlSize(.small)
                .disabled(preview.exceedsBlockThreshold)

                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.session.cancelPreview()
                    }
                }
                .glassButton()
                .controlSize(.small)
            }
        }
        .padding(.vertical, Spacing.tight)
    }
}
