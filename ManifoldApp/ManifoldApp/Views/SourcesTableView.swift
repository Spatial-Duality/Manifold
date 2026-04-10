import SwiftUI
import ManifoldKit

/// Files tab Sources overview — the primary access management surface for files.
/// Shows a Table with per-agent access checkboxes.
/// Checking = broadening → opens Review & Update Access sheet.
/// Unchecking = narrowing → immediate + undo toast.
struct SourcesTableView: View {
    @Environment(ManifoldStore.self) var store
    @State private var selectedSourceIDs: Set<String> = []
    @State private var searchText = ""
    @State private var undoSource: (SourceRecord, AgentFocus)?
    @State private var showUndoToast = false

    private var visibleSources: [SourceRecord] {
        let sources = store.sources.filter { !$0.isRemoved }
        if searchText.isEmpty { return sources }
        return sources.filter {
            $0.displayName.localizedStandardContains(searchText)
            || $0.originalRootPath.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            if visibleSources.isEmpty && store.sources.filter({ !$0.isRemoved }).isEmpty {
                sourcesEmptyState
            } else {
                sourceTable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $searchText, prompt: "Search sources...")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                AgentFocusControl(focus: $store.agentFocus)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Folder", systemImage: "folder.badge.plus") {
                    store.addSourceFromPicker()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showUndoToast, let (source, _) = undoSource {
                undoToastView(source: source)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.2), value: showUndoToast)
    }

    // MARK: - Source Table

    @ViewBuilder
    private var sourceTable: some View {
        Table(visibleSources, selection: $selectedSourceIDs) {
            TableColumn("Name") { source in
                HStack(spacing: Spacing.standard) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(source.isAccessible ? .blue : .secondary)
                    Text(source.displayName)
                        .font(.body)
                }
            }
            .width(min: 120, ideal: 180)

            TableColumn("Path") { source in
                Text(shortenedPath(source.originalRootPath))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 150, ideal: 250)

            TableColumn("Items") { source in
                Text("—")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .width(60)

            // Agent access column(s)
            if store.agentFocus == .compare {
                TableColumn("Claude") { source in
                    accessCheckbox(source: source, agent: .claude)
                }
                .width(60)

                TableColumn("Codex") { source in
                    accessCheckbox(source: source, agent: .codex)
                }
                .width(60)
            } else {
                TableColumn("Access") { source in
                    accessCheckbox(source: source, agent: store.agentFocus)
                }
                .width(60)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: SourceRecord.ID.self) { ids in
            if let id = ids.first, let source = visibleSources.first(where: { $0.id == id }) {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(source.originalRootPath, inFileViewerRootedAtPath: "")
                }
                Divider()
                Button("Remove from Manifold", role: .destructive) {
                    store.removeSource(path: source.originalRootPath)
                }
            }
        }
    }

    // MARK: - Access Checkbox

    @ViewBuilder
    private func accessCheckbox(source: SourceRecord, agent: AgentFocus) -> some View {
        let isGranted = source.isAccessible // TODO: Phase 6 — wire to PolicyStore per-agent

        Toggle(isOn: Binding(
            get: { isGranted },
            set: { newValue in
                if newValue {
                    // Broadening: open Review & Update Access sheet
                    // TODO: Phase 8 — trigger ReviewAccessSheet
                } else {
                    // Narrowing: immediate + undo toast
                    handleNarrow(source: source, agent: agent)
                }
            }
        )) {
            EmptyView()
        }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .accessibilityLabel("\(source.displayName) access for \(agent == .codex ? "Codex" : "Claude")")
    }

    // MARK: - Narrowing (inline + undo)

    private func handleNarrow(source: SourceRecord, agent: AgentFocus) {
        // Immediate narrowing
        Task { await store.pauseSource(sourceID: source.sourceID) }

        // Show undo toast
        undoSource = (source, agent)
        showUndoToast = true

        // Auto-dismiss after 5 seconds
        Task {
            try? await Task.sleep(for: .seconds(5))
            if showUndoToast { showUndoToast = false }
        }
    }

    // MARK: - Undo Toast

    private func undoToastView(source: SourceRecord) -> some View {
        HStack(spacing: Spacing.standard) {
            Text("Removed access to \(source.displayName)")
                .font(.callout)
            Button("Undo") {
                Task { await store.resumeSource(sourceID: source.sourceID) }
                showUndoToast = false
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, Spacing.edge)
        .padding(.vertical, Spacing.standard)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, Spacing.edge)
    }

    // MARK: - Empty State

    private var sourcesEmptyState: some View {
        ContentUnavailableView {
            Label("No Sources", systemImage: "folder.badge.plus")
        } description: {
            Text("Add a folder to let AI agents access your files.\nClaude and Codex will only see files in folders you choose.")
        } actions: {
            Button("Add Folder") {
                store.addSourceFromPicker()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    private func shortenedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
