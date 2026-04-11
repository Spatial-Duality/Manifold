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
    @State private var itemCounts: [String: Int] = [:]

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
            HStack(spacing: Spacing.standard) {
                AgentFocusControl(focus: $store.agentFocus)

                TextField("Search sources", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120, maxWidth: 200)

                Spacer()

                Button("Add Folder\u{2026}", systemImage: "folder.badge.plus") {
                    store.addSourceFromPicker()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, Spacing.section)
            .padding(.vertical, 6)
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
        VStack(spacing: 0) {
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
                    Text(source.originalRootPath.shortenedPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 150, ideal: 250)

                // 2.2: Lazy item count with placeholder
                TableColumn("Items") { source in
                    if let count = itemCounts[source.sourceID] {
                        Text("\(count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    } else {
                        Text("\u{2026}")
                            .foregroundStyle(.quaternary)
                    }
                }
                .width(60)

                // 2.3: Agent-colored access columns
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
                    let columnTitle = store.agentFocus == .codex ? "Codex" : "Claude"
                    TableColumn(columnTitle) { source in
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
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(source.originalRootPath, forType: .string)
                    }
                    Button("View Activity") {
                        store.showActivityDrawer = true
                    }
                    Divider()
                    Button("Remove from Manifold", role: .destructive) {
                        store.removeSource(path: source.originalRootPath)
                    }
                }
            }

            // 2.1: Summary footer
            if !visibleSources.isEmpty {
                HStack {
                    let totalItems = itemCounts.values.reduce(0, +)
                    Text("\(visibleSources.count) ^[\(visibleSources.count) source](inflect: true) \u{00B7} \(totalItems) files")
                        .font(Typ.numericCaption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Add Folder\u{2026}") { store.addSourceFromPicker() }
                        .buttonStyle(.plain)
                        .font(Typ.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Spacing.section)
                .padding(.vertical, Spacing.standard)
            }
        }
        .navigationTitle("Sources")
        .task(id: visibleSources.map(\.sourceID).joined(separator: ",")) {
            // Invalidate counts for removed sources
            let currentIDs = Set(visibleSources.map(\.sourceID))
            for key in itemCounts.keys where !currentIDs.contains(key) {
                itemCounts.removeValue(forKey: key)
            }
            await countItems()
        }
    }

    private func countItems() async {
        for source in visibleSources where itemCounts[source.sourceID] == nil {
            let count = await Task.detached(priority: .utility) {
                let fm = FileManager.default
                let root = URL(fileURLWithPath: source.originalRootPath)
                guard let enumerator = fm.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { return 0 }
                var n = 0
                while let url = enumerator.nextObject() as? URL {
                    guard !Task.isCancelled else { return n }
                    if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { n += 1 }
                }
                return n
            }.value
            guard !Task.isCancelled else { return }
            itemCounts[source.sourceID] = count
        }
    }

    // MARK: - Access Checkbox (per-agent via PolicyStore)

    @ViewBuilder
    private func accessCheckbox(source: SourceRecord, agent: AgentFocus) -> some View {
        let targetApp = agent.targetApp
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
                .font(Typ.caption)
            Button("Undo") {
                if let agent = undoAgent {
                    Task { await store.policy.addSource(source.sourceID, to: agent) }
                }
                showUndoToast = false
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, Spacing.section)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .toastElevation()
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

}
