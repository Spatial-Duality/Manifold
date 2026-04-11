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
    @State private var undoAgent: TargetApp?
    @State private var showUndoToast = false
    @State private var undoTimerTask: Task<Void, Never>?
    @State private var broadenSource: (SourceRecord, TargetApp)?

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
        .safeAreaInset(edge: .top) {
            // Local controls — below the global title bar, inside the content area
            HStack(spacing: Spacing.section) {
                AgentFocusControl(focus: $store.agentFocus)
                TextField("Search sources", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Spacer()
                Button("Add Folder\u{2026}", systemImage: "folder.badge.plus") {
                    store.addSourceFromPicker()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, Spacing.edge)
            .padding(.vertical, Spacing.standard)
            .background(.bar)
        }
        .overlay(alignment: .bottom) {
            if showUndoToast, let (source, _) = undoSource {
                undoToastView(source: source)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.2), value: showUndoToast)
        .background {
            // Hidden ⌘Z handler for undo
            if showUndoToast {
                Button("") {
                    guard let (source, _) = undoSource, let agent = undoAgent else { return }
                    Task { await store.policy.addSource(source.sourceID, to: agent) }
                    showUndoToast = false
                    undoTimerTask?.cancel()
                }
                .keyboardShortcut("z", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
            }
        }
        .sheet(item: broadenBinding) { change in
            ReviewAccessSheet(pendingChange: change)
                .environment(store)
                .frame(minWidth: 560, minHeight: 500)
        }
        .onChange(of: broadenSource?.0.sourceID) { _, _ in
            // Handled by sheet binding
        }
    }

    /// Convert broadenSource state into a ReviewAccessChange for sheet presentation.
    private var broadenBinding: Binding<ReviewAccessChange?> {
        Binding(
            get: {
                guard let (source, agent) = broadenSource else { return nil }
                let agentName = agent == .codex ? "Codex" : "Claude"
                return ReviewAccessChange(
                    description: "Adding \(source.displayName) to \(agentName)",
                    kind: .addSource(sourceID: source.sourceID, sourceName: source.displayName)
                )
            },
            set: { newValue in
                if newValue == nil { broadenSource = nil }
            }
        )
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
        .tableStyle(.inset)
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

    // MARK: - Access Checkbox (per-agent via PolicyStore)

    @ViewBuilder
    private func accessCheckbox(source: SourceRecord, agent: AgentFocus) -> some View {
        let targetApp: TargetApp = agent == .codex ? .codex : .cowork
        let policy = store.policy.policy(for: targetApp)
        let isGranted = policy?.allowedSourceIDs.contains(source.sourceID) ?? false

        Toggle(isOn: Binding(
            get: { isGranted },
            set: { newValue in
                if newValue {
                    // Broadening: open Review & Update Access sheet
                    broadenSource = (source, targetApp)
                } else {
                    // Narrowing: immediate + undo toast
                    handleNarrow(source: source, agent: targetApp)
                }
            }
        )) {
            EmptyView()
        }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .accessibilityLabel("\(source.displayName) access for \(agent == .codex ? "Codex" : "Claude")")
    }

    // MARK: - Narrowing (inline, immediate + undo toast)

    private func handleNarrow(source: SourceRecord, agent: TargetApp) {
        // Immediate narrowing via PolicyStore
        Task { await store.policy.removeSource(source.sourceID, from: agent) }

        // Show undo toast
        undoSource = (source, store.agentFocus)
        undoAgent = agent
        showUndoToast = true

        // Auto-dismiss after 5 seconds — cancel previous timer
        undoTimerTask?.cancel()
        undoTimerTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { showUndoToast = false }
        }
    }

    // MARK: - Undo Toast

    private func undoToastView(source: SourceRecord) -> some View {
        let agentName = undoAgent == .codex ? "Codex" : "Claude"
        return HStack(spacing: Spacing.standard) {
            Text("Removed \(agentName) access to \(source.displayName)")
                .font(.callout)
            Button("Undo") {
                if let agent = undoAgent {
                    Task { await store.policy.addSource(source.sourceID, to: agent) }
                }
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
            Label("No Sources Added", systemImage: "folder.badge.plus")
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
