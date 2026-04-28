// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FilesFlatView — governance-aware Finder for every file Manifold knows
// about. Multi-select, Finder-grade sorting, Scope filter, native macOS
// search, per-agent access chips, Quick Look (Space), open with default
// app (⏎ / double-click), and a toggleable right inspector.

import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import ManifoldKit

struct FilesFlatView: View {
    @Environment(ManifoldStore.self) private var store
    @AppStorage("access.inspector.visible") private var inspectorVisible = true

    @State private var files: [SourceFile] = []
    @State private var isLoading = false
    @State private var selectedFilePaths: Set<String> = []
    @State private var selectedHistory: [SnapshotRecord] = []
    @State private var fileOverridesByAgent: [TargetApp: [FileVisibilityOverrideRecord]] = [:]
    @State private var scopeFilter: ScopeFilter = .all
    @State private var searchText = ""
    @State private var quickLookURL: URL?
    @State private var aiTouchedPaths: Set<String> = []
    @AppStorage("access.smartViews") private var smartViewsJSON: String = "[]"
    @State private var showSmartViewSheet = false
    @State private var smartViewDraftName: String = ""
    @State private var sortOrder: [KeyPathComparator<SourceFile>] = [
        KeyPathComparator(\SourceFile.sourceName),
        KeyPathComparator(\SourceFile.relativePath),
    ]

    enum ScopeFilter: Hashable, Codable {
        case all
        case shared
        case unshared
        case sharedWith(TargetApp)
        case overriddenAllow
        case overriddenHide
        case changed
        /// Files an AI has written bytes to. Drives the same sparkle-tagged
        /// rows that already render the `✦` indicator in the Name column,
        /// scoped to just those rows when this filter is active.
        case aiTouched
    }

    /// User-saved combination of (scopeFilter, searchText). Persisted via
    /// @AppStorage as JSON — Smart Views are app-level preferences, not
    /// runtime state, so they don't belong in the AccessStore database.
    struct SmartView: Codable, Identifiable, Hashable {
        let id: UUID
        var name: String
        var scopeFilter: ScopeFilter
        var searchText: String

        init(
            id: UUID = UUID(),
            name: String,
            scopeFilter: ScopeFilter,
            searchText: String
        ) {
            self.id = id
            self.name = name
            self.scopeFilter = scopeFilter
            self.searchText = searchText
        }
    }

    // MARK: - Derived

    private var connectedAgents: [TargetApp] {
        AgentMeta.connected(from: store.connectedAgents)
    }

    private var sourceReloadKey: String {
        store.sources
            .filter { $0.isAccessible && !$0.isRemoved }
            .map { "\($0.sourceID):\($0.updatedAt)" }
            .sorted()
            .joined(separator: "|")
    }

    private var defaultScopeByAgent: [TargetApp: Set<String>] {
        var result: [TargetApp: Set<String>] = [:]
        for agent in connectedAgents {
            result[agent] = Set(store.governance.policy(for: agent)?.allowedSourceIDs ?? [])
        }
        return result
    }

    private var resolverByAgent: [TargetApp: FileVisibilityResolver] {
        var result: [TargetApp: FileVisibilityResolver] = [:]
        for agent in connectedAgents {
            result[agent] = FileVisibilityResolver(overrides: fileOverridesByAgent[agent] ?? [])
        }
        return result
    }

    private func visibleAgents(for file: SourceFile) -> Set<TargetApp> {
        var set: Set<TargetApp> = []
        let defaults = defaultScopeByAgent
        let resolvers = resolverByAgent
        for agent in connectedAgents {
            guard let resolver = resolvers[agent] else { continue }
            let defaultVisible = defaults[agent]?.contains(file.sourceID) == true
            let evaluation = resolver.evaluate(
                sourceID: file.sourceID,
                relativePath: file.relativePath,
                defaultVisible: defaultVisible
            )
            switch evaluation.origin {
            case .explicitAllow, .inheritedAllow:
                set.insert(agent)
            case .explicitDeny, .inheritedHidden:
                break
            }
        }
        return set
    }

    /// Agents whose state for this file is an explicit override (not just
    /// inherited from the source default). The runtime returns this via
    /// FileVisibilityEvaluationOrigin; the per-row dot strip uses it to
    /// render a tinted underline beneath each override chip.
    private func explicitOverrideAgents(for file: SourceFile) -> Set<TargetApp> {
        var set: Set<TargetApp> = []
        let defaults = defaultScopeByAgent
        let resolvers = resolverByAgent
        for agent in connectedAgents {
            guard let resolver = resolvers[agent] else { continue }
            let defaultVisible = defaults[agent]?.contains(file.sourceID) == true
            let evaluation = resolver.evaluate(
                sourceID: file.sourceID,
                relativePath: file.relativePath,
                defaultVisible: defaultVisible
            )
            switch evaluation.origin {
            case .explicitAllow, .explicitDeny:
                set.insert(agent)
            case .inheritedAllow, .inheritedHidden:
                break
            }
        }
        return set
    }

    private func hasOverride(_ decision: FileVisibilityOverrideDecision, for file: SourceFile) -> Bool {
        for overrides in fileOverridesByAgent.values {
            if overrides.contains(where: {
                $0.sourceID == file.sourceID
                && $0.relativePath == file.relativePath
                && $0.decision == decision
            }) {
                return true
            }
        }
        return false
    }

    private var visibleFiles: [SourceFile] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return files.filter { file in
            let visible = visibleAgents(for: file)

            let matches: Bool
            switch scopeFilter {
            case .all:
                matches = true
            case .shared:
                matches = !visible.isEmpty
            case .unshared:
                matches = visible.isEmpty
            case .sharedWith(let agent):
                matches = visible.contains(agent)
            case .overriddenAllow:
                matches = hasOverride(.allow, for: file)
            case .overriddenHide:
                matches = hasOverride(.deny, for: file)
            case .changed:
                matches = file.versionCount > 0
            case .aiTouched:
                matches = aiTouchedPaths.contains(file.path)
            }
            guard matches else { return false }

            guard !trimmed.isEmpty else { return true }
            let haystack = [file.name, file.relativePath, file.sourceName].joined(separator: "\n")
            return haystack.localizedCaseInsensitiveContains(trimmed)
        }
        .sorted(using: sortOrder)
    }

    private var selectedFile: SourceFile? {
        guard selectedFilePaths.count == 1, let path = selectedFilePaths.first else { return nil }
        return files.first(where: { $0.path == path })
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                table
                if !selectedFilePaths.isEmpty {
                    bulkBar
                }
            }

            if inspectorVisible {
                Divider()
                FileInspectorPane(
                    file: selectedFile,
                    selectionCount: selectedFilePaths.count,
                    activity: selectedHistory,
                    connectedAgents: connectedAgents,
                    visibleAgents: selectedFile.map(visibleAgents(for:)) ?? [],
                    explicitAgents: selectedFile.map(explicitOverrideAgents(for:)) ?? [],
                    onToggleAgent: { agent, wasVisible in
                        guard let file = selectedFile else { return }
                        Task { await toggle(agent: agent, for: file, currentlyVisible: wasVisible) }
                    },
                    onSetAllAgents: { inScope in
                        guard let file = selectedFile else { return }
                        Task {
                            await bulkSetVisibility(
                                agents: connectedAgents,
                                decision: inScope ? .allow : .deny,
                                files: [file]
                            )
                        }
                    },
                    onReset: {
                        guard let file = selectedFile else { return }
                        Task { await resetOverrides(for: file) }
                    }
                )
                .frame(width: 340)
                .background(ManifoldPalette.surface2)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search name, path, or folder")
        .quickLookPreview($quickLookURL)
        .onReceive(NotificationCenter.default.publisher(for: .manifoldFocusCurrentSearch)) { _ in
            // searchable handles focus natively; kept for forward-compat.
        }
        .manifoldFileDropTarget(store: store)
        .task(id: sourceReloadKey) {
            await loadFilesProgressively()
            await loadAITouched()
        }
        .task(id: connectedAgentsKey) {
            await loadOverrides()
        }
        .task(id: selectedFilePaths) {
            guard selectedFilePaths.count == 1, let path = selectedFilePaths.first else {
                selectedHistory = []
                return
            }
            selectedHistory = await store.fileHistory(filePath: path)
        }
    }

    private func loadAITouched() async {
        do {
            aiTouchedPaths = try await store.runtime.aiTouchedFilePaths()
        } catch {
            // Honest no-op: sparkle stays absent if the runtime call fails.
            aiTouchedPaths = []
        }
    }

    // MARK: - Smart Views

    /// Decoded list of saved Smart Views. Read-only — write through
    /// `saveSmartViews(_:)` so the @AppStorage JSON stays in sync.
    private var smartViews: [SmartView] {
        guard let data = smartViewsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SmartView].self, from: data)) ?? []
    }

    private func saveSmartViews(_ views: [SmartView]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(views),
              let json = String(data: data, encoding: .utf8) else { return }
        smartViewsJSON = json
    }

    /// True when the user has tweaked the filter/search away from defaults.
    /// Drives the "Save current view" button enable state — saving an
    /// empty filter produces a useless preset.
    private var hasNonDefaultFilter: Bool {
        scopeFilter != .all || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func applySmartView(_ view: SmartView) {
        scopeFilter = view.scopeFilter
        searchText = view.searchText
    }

    private func deleteSmartView(_ view: SmartView) {
        var updated = smartViews
        updated.removeAll { $0.id == view.id }
        saveSmartViews(updated)
    }

    private func saveCurrentAsSmartView(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = smartViews
        updated.append(SmartView(
            name: trimmed,
            scopeFilter: scopeFilter,
            searchText: searchText
        ))
        saveSmartViews(updated)
    }

    private var connectedAgentsKey: String {
        AgentMeta.stableKey(connectedAgents)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Spacing.s3) {
            Menu {
                Button("All files")         { scopeFilter = .all }
                Button("Shared")            { scopeFilter = .shared }
                Button("Unshared")          { scopeFilter = .unshared }
                if !connectedAgents.isEmpty {
                    Divider()
                    ForEach(connectedAgents, id: \.self) { agent in
                        Button("Shared with \(AgentMeta.label(agent))") {
                            scopeFilter = .sharedWith(agent)
                        }
                    }
                }
                Divider()
                Button("Allowed overrides") { scopeFilter = .overriddenAllow }
                Button("Hidden overrides")  { scopeFilter = .overriddenHide }
                Button("Changed")           { scopeFilter = .changed }
                Divider()
                Button {
                    scopeFilter = .aiTouched
                } label: {
                    Label("AI-touched", systemImage: "sparkle")
                }
            } label: {
                Label(scopeFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            smartViewsMenu

            Spacer()

            Text("\(visibleFiles.count) of \(files.count)")
                .font(ManifoldType.numericCaption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .background(.regularMaterial)
    }

    private var scopeFilterLabel: String {
        switch scopeFilter {
        case .all:                   return "All files"
        case .shared:                return "Shared"
        case .unshared:              return "Unshared"
        case .sharedWith(let agent): return "Shared with \(AgentMeta.label(agent))"
        case .overriddenAllow:       return "Allowed overrides"
        case .overriddenHide:        return "Hidden overrides"
        case .changed:               return "Changed"
        case .aiTouched:             return "AI-touched"
        }
    }

    /// Smart Views menu — saved (filter, search) combinations the user
    /// can recall in one click. Mirrors the Mail.app Smart Mailbox
    /// pattern. Save action is disabled when the current filter is the
    /// default since there's nothing meaningful to save.
    @ViewBuilder
    private var smartViewsMenu: some View {
        Menu {
            if smartViews.isEmpty {
                Text("No saved views")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(smartViews) { view in
                    Button(view.name) { applySmartView(view) }
                }
                Divider()
                Menu("Delete") {
                    ForEach(smartViews) { view in
                        Button(view.name, role: .destructive) {
                            deleteSmartView(view)
                        }
                    }
                }
            }
            Divider()
            Button("Save current view…") {
                smartViewDraftName = ""
                showSmartViewSheet = true
            }
            .disabled(!hasNonDefaultFilter)
        } label: {
            Label("Smart Views", systemImage: "star")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .sheet(isPresented: $showSmartViewSheet) {
            SmartViewSheet(
                draftName: $smartViewDraftName,
                currentDescription: currentFilterDescription,
                onSave: {
                    saveCurrentAsSmartView(name: smartViewDraftName)
                    showSmartViewSheet = false
                },
                onCancel: { showSmartViewSheet = false }
            )
        }
    }

    /// Plain-English description of the current filter shown in the
    /// save sheet so the user sees what's being captured.
    private var currentFilterDescription: String {
        var parts: [String] = [scopeFilterLabel]
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append("matching \"\(trimmed)\"")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Table

    private var table: some View {
        Table(of: SourceFile.self, selection: $selectedFilePaths, sortOrder: $sortOrder) {
            // Compact chip-stack in the row, same component the Mail
            // Share column uses. Labels were forcing the labeled strip
            // wider than the column slot and visually overflowing into
            // the Name column. The All / per-agent "Allow / Deny / Reset"
            // controls remain available in the bulk bar (when rows are
            // selected) and the file inspector.
            TableColumn("Access") { file in
                AccessChipStack(
                    agents: connectedAgents,
                    visibleAgents: visibleAgents(for: file),
                    onToggle: { agent, wasVisible in
                        Task { await toggle(agent: agent, for: file, currentlyVisible: wasVisible) }
                    }
                )
                .accessibilityIdentifier(accessIdentifierPrefix(for: file))
            }
            .width(min: 56, ideal: max(56, CGFloat(connectedAgents.count) * 18 + 12), max: 140)

            TableColumn("Name", value: \.name) { file in
                HStack(spacing: Spacing.s2) {
                    FileTypeIcon(filename: file.name, size: 13)
                    Text(file.name)
                        .font(ManifoldType.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if aiTouchedPaths.contains(file.path) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tint)
                            .help("AI has written to this file")
                            .accessibilityLabel("AI-touched")
                    }
                }
            }
            .width(min: 160, ideal: 220)

            TableColumn("Kind", value: \.fileExtension) { file in
                Text(kindLabel(for: file))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 120, max: 180)

            TableColumn("Path", value: \.relativePath) { file in
                Text(file.relativePath)
                    .font(ManifoldType.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            TableColumn("Source", value: \.sourceName) { file in
                Text(file.sourceName)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(120)

            TableColumn("Size", value: \.sizeBytes) { file in
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
                    .font(ManifoldType.numericCaption)
                    .foregroundStyle(.secondary)
            }
            .width(72)

            TableColumn("Modified", value: \.modifiedDate) { file in
                Text(Self.relativeFormatter.localizedString(for: file.modifiedDate, relativeTo: .now))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.tertiary)
            }
            .width(120)

            TableColumn("Versions", value: \.versionCount) { file in
                if file.versionCount > 0 {
                    Text("\(file.versionCount)")
                        .font(ManifoldType.numericCaption.weight(.semibold))
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(70)
        } rows: {
            ForEach(visibleFiles) { file in
                TableRow(file)
            }
        }
        .tableStyle(.inset)
        .contextMenu(forSelectionType: String.self) { selection in
            contextMenu(for: selection)
        } primaryAction: { selection in
            openWithDefaultApp(paths: selection)
        }
        .overlay {
            if isLoading && files.isEmpty {
                ProgressView().progressViewStyle(.circular)
            } else if files.isEmpty {
                EmptyStateIllustration(
                    systemImage: "doc.on.doc",
                    title: "No files indexed yet",
                    subtitle: "Once you share a folder, its files appear here with default scope, overrides, and tracked activity.",
                    tint: ManifoldPalette.selection,
                    style: .access
                )
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for selection: Set<String>) -> some View {
        let filesInSelection = files.filter { selection.contains($0.path) }

        Button("Open") { openWithDefaultApp(paths: selection) }
            .disabled(filesInSelection.isEmpty)
        Button("Quick Look") {
            if let first = filesInSelection.first {
                quickLookURL = URL(fileURLWithPath: first.path)
            }
        }
        .disabled(filesInSelection.isEmpty)

        Divider()

        if !connectedAgents.isEmpty {
            Menu("Share with") {
                if connectedAgents.count > 1 {
                    Button("Both") {
                        Task { await bulkSetVisibility(agents: connectedAgents, decision: .allow, files: filesInSelection) }
                    }
                    Divider()
                }
                ForEach(connectedAgents, id: \.self) { agent in
                    Button(AgentMeta.label(agent)) {
                        Task { await bulkSetVisibility(agent: agent, decision: .allow, files: filesInSelection) }
                    }
                }
            }
            Menu("Unshare from") {
                if connectedAgents.count > 1 {
                    Button("Both") {
                        Task { await bulkSetVisibility(agents: connectedAgents, decision: .deny, files: filesInSelection) }
                    }
                    Divider()
                }
                ForEach(connectedAgents, id: \.self) { agent in
                    Button(AgentMeta.label(agent)) {
                        Task { await bulkSetVisibility(agent: agent, decision: .deny, files: filesInSelection) }
                    }
                }
            }
        }
        Button("Reset overrides") {
            Task { await bulkReset(files: filesInSelection) }
        }

        Divider()

        Button("Reveal in Finder") {
            let urls = filesInSelection.map { URL(fileURLWithPath: $0.path) }
            if !urls.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(filesInSelection.map(\.path).joined(separator: "\n"), forType: .string)
        }
    }

    // MARK: - Bulk bar

    private var bulkBar: some View {
        HStack(spacing: Spacing.s2) {
            Text("\(selectedFilePaths.count) selected")
                .font(ManifoldType.captionMedium)

            Spacer()

            if !connectedAgents.isEmpty {
                Button {
                    Task { await bulkSetVisibility(agents: connectedAgents, decision: .allow, files: filesInSelection) }
                } label: {
                    Label("Share with Both", systemImage: "person.2.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(ManifoldPalette.selection)

                Button {
                    Task { await bulkSetVisibility(agents: connectedAgents, decision: .deny, files: filesInSelection) }
                } label: {
                    Label("Unshare from Both", systemImage: "person.2.slash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Menu {
                    if connectedAgents.count > 1 {
                        Button("Both") {
                            Task { await bulkSetVisibility(agents: connectedAgents, decision: .allow, files: filesInSelection) }
                        }
                        Divider()
                    }
                    ForEach(connectedAgents, id: \.self) { agent in
                        Button(AgentMeta.label(agent)) {
                            Task { await bulkSetVisibility(agent: agent, decision: .allow, files: filesInSelection) }
                        }
                    }
                } label: {
                    Label("Share with", systemImage: "plus.circle")
                }
                .menuStyle(.button)
                .controlSize(.small)

                Menu {
                    if connectedAgents.count > 1 {
                        Button("Both") {
                            Task { await bulkSetVisibility(agents: connectedAgents, decision: .deny, files: filesInSelection) }
                        }
                        Divider()
                    }
                    ForEach(connectedAgents, id: \.self) { agent in
                        Button(AgentMeta.label(agent)) {
                            Task { await bulkSetVisibility(agent: agent, decision: .deny, files: filesInSelection) }
                        }
                    }
                } label: {
                    Label("Unshare from", systemImage: "minus.circle")
                }
                .menuStyle(.button)
                .controlSize(.small)
            }

            Button("Reset overrides") {
                Task { await bulkReset(files: filesInSelection) }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private var filesInSelection: [SourceFile] {
        files.filter { selectedFilePaths.contains($0.path) }
    }

    // MARK: - Actions

    private func openWithDefaultApp(paths: Set<String>) {
        for path in paths {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    private func toggle(agent: TargetApp, for file: SourceFile, currentlyVisible: Bool) async {
        let decision: FileVisibilityOverrideDecision = currentlyVisible ? .deny : .allow
        await store.setFileVisibilityOverride(
            agent: agent,
            sourceID: file.sourceID,
            relativePath: file.relativePath,
            decision: decision
        )
        await reloadOverrides(agent: agent)
    }

    private func resetOverrides(for file: SourceFile) async {
        for agent in connectedAgents {
            await store.clearFileVisibilityOverride(
                agent: agent,
                sourceID: file.sourceID,
                relativePath: file.relativePath
            )
        }
        await loadOverrides()
    }

    private func bulkSetVisibility(agent: TargetApp, decision: FileVisibilityOverrideDecision, files: [SourceFile]) async {
        for file in files {
            await store.setFileVisibilityOverride(
                agent: agent,
                sourceID: file.sourceID,
                relativePath: file.relativePath,
                decision: decision
            )
        }
        await reloadOverrides(agent: agent)
    }

    private func bulkSetVisibility(agents: [TargetApp], decision: FileVisibilityOverrideDecision, files: [SourceFile]) async {
        for agent in agents {
            await bulkSetVisibility(agent: agent, decision: decision, files: files)
        }
    }

    private func bulkReset(files: [SourceFile]) async {
        for file in files {
            for agent in connectedAgents {
                await store.clearFileVisibilityOverride(
                    agent: agent,
                    sourceID: file.sourceID,
                    relativePath: file.relativePath
                )
            }
        }
        await loadOverrides()
    }

    // MARK: - Loading

    private func loadFilesProgressively() async {
        files = []
        selectedFilePaths = []
        isLoading = true
        for await batch in store.enumerateSourceFilesProgressively() {
            files.append(contentsOf: batch)
        }
        isLoading = false
    }

    private func loadOverrides() async {
        let fresh = await store.fileVisibilityOverridesByAgent(connectedAgents)
        if fresh != fileOverridesByAgent { fileOverridesByAgent = fresh }
    }

    private func reloadOverrides(agent: TargetApp) async {
        fileOverridesByAgent[agent] = await store.fileVisibilityOverrides(agent: agent)
    }

    // MARK: - Helpers

    private func kindLabel(for file: SourceFile) -> String {
        let ext = file.fileExtension.isEmpty
            ? (file.path as NSString).pathExtension
            : file.fileExtension
        if ext.isEmpty { return "File" }
        if let type = UTType(filenameExtension: ext), let desc = type.localizedDescription {
            return desc
        }
        return ext.uppercased()
    }

    private func accessIdentifierPrefix(for file: SourceFile) -> String {
        "access.file.\(file.sourceID.manifoldAccessIdentifierComponent).\(file.relativePath.manifoldAccessIdentifierComponent)"
    }

    static let relativeFormatter = RelativeDateTimeFormatter()
}

// MARK: - Smart View save sheet

private struct SmartViewSheet: View {
    @Binding var draftName: String
    let currentDescription: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text("Save Smart View")
                .font(ManifoldType.heading)
            Text(currentDescription)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSave)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.s4)
        .frame(width: 360)
    }
}
