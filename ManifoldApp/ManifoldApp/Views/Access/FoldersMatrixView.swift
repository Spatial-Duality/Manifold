// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FoldersMatrixView — sources × agents coverage matrix.
//
// Columns are driven by the app's supported agents so access can be
// configured before Claude or Codex connect. Beyond four, columns collapse
// into a single Access column rendering an AccessChipStack per row.
// Cells are interactive: clicking a coverage dot toggles the source's
// membership in that agent's default scope.

import SwiftUI
import ManifoldKit

struct FoldersMatrixView: View {
    @Environment(ManifoldStore.self) private var store
    @AppStorage("access.inspector.visible") private var inspectorVisible = true

    @State private var selectedIDs: Set<String> = []
    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<SourceRecord>] = [
        KeyPathComparator(\SourceRecord.displayName)
    ]
    /// Per-agent drift counts keyed by sourceID. "Drift" = files with
    /// non-baseline snapshots after that agent's most recently ended
    /// grant. Loaded lazily on appear and refreshed when the connected-
    /// agents set changes; absence means "no signal yet" not "zero drift".
    @State private var driftCountsByAgent: [TargetApp: [String: Int]] = [:]
    /// Files dropped onto the matrix queue here until the user picks
    /// "Add the whole folder" or "Add only this file" in a confirmation
    /// dialog. Folders are added immediately on drop without prompting.
    @State private var pendingFileDrops: [URL] = []
    @State private var isDropTargeted = false

    // MARK: - Derived

    private var connectedAgents: [TargetApp] {
        AgentMeta.connected(from: store.connectedAgents)
    }

    private var useChipFallback: Bool {
        connectedAgents.count > 4
    }

    private var scopeByAgent: [TargetApp: Set<String>] {
        var result: [TargetApp: Set<String>] = [:]
        for agent in connectedAgents {
            result[agent] = Set(store.governance.policy(for: agent)?.allowedSourceIDs ?? [])
        }
        return result
    }

    private func scopedAgents(for source: SourceRecord) -> Set<TargetApp> {
        Set(connectedAgents.filter { scopeByAgent[$0]?.contains(source.sourceID) == true })
    }

    private var visibleSources: [SourceRecord] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.sources.filter { source in
            guard !trimmed.isEmpty else { return true }
            let haystack = source.displayName + "\n" + source.originalRootPath
            return haystack.localizedCaseInsensitiveContains(trimmed)
        }
        .sorted(using: sortOrder)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                table
                if !selectedIDs.isEmpty {
                    bulkBar
                }
            }

            if inspectorVisible {
                Divider()
                FileTreeInspector(source: selectedSource)
                    .frame(width: 320)
                    .background(ManifoldPalette.surface2)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search folders")
        .task(id: connectedAgentsKey) { await loadDriftCounts() }
        .dropDestination(for: URL.self) { items, _ in
            handleDroppedURLs(items)
            return !items.isEmpty
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(ManifoldPalette.selection, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .confirmationDialog(
            fileDropTitle,
            isPresented: Binding(
                get: { !pendingFileDrops.isEmpty },
                set: { if !$0 { pendingFileDrops = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Add the whole folder") {
                let drops = pendingFileDrops
                pendingFileDrops = []
                Task {
                    for url in drops {
                        await store.addSourceFromURL(url)
                    }
                }
            }
            Button("Add only \(pendingFileDrops.count == 1 ? "this file" : "these files")") {
                let drops = pendingFileDrops
                pendingFileDrops = []
                Task {
                    for url in drops {
                        await store.addSourceForSingleFile(url)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingFileDrops = []
            }
        } message: {
            Text(fileDropMessage)
        }
    }

    private var fileDropTitle: String {
        pendingFileDrops.count == 1
            ? "Add \(pendingFileDrops[0].lastPathComponent)?"
            : "Add \(pendingFileDrops.count) files?"
    }

    private var fileDropMessage: String {
        // Honest about the model: Manifold tracks at folder granularity,
        // so either choice ends up adding the parent folder. "Add only
        // this file" hides the existing siblings via per-file deny
        // overrides so only the dropped file is shared with the AIs.
        // Files added to the folder later are visible by default.
        if pendingFileDrops.count == 1 {
            return "Manifold tracks at folder granularity. Add the whole folder so every file in it is visible, or add only this file and Manifold will hide its current siblings."
        }
        return "Manifold tracks at folder granularity. Add the whole containing folder of each file, or add only the dropped files and hide existing siblings."
    }

    private func handleDroppedURLs(_ urls: [URL]) {
        let resolved = urls.map { $0.standardizedFileURL }
        var folders: [URL] = []
        var files: [URL] = []
        for url in resolved {
            if store.dropTargetIsFile(url) {
                files.append(url)
            } else {
                folders.append(url)
            }
        }
        if !folders.isEmpty {
            Task {
                for url in folders {
                    await store.addSourceFromURL(url)
                }
            }
        }
        if !files.isEmpty {
            // Append rather than replace so the user can drop again
            // before answering the previous prompt — the dialog batches.
            pendingFileDrops.append(contentsOf: files)
        }
    }

    private var connectedAgentsKey: String {
        connectedAgents.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// Loads drift counts for every connected agent in parallel, then
    /// publishes them to the table. One XPC per agent (typically 1-2
    /// roundtrips). Failure is silent — drift badges just don't render
    /// rather than the matrix erroring out.
    private func loadDriftCounts() async {
        var fresh: [TargetApp: [String: Int]] = [:]
        for agent in connectedAgents {
            do {
                fresh[agent] = try await store.runtime.sourceDriftCounts(agent: agent)
            } catch {
                fresh[agent] = [:]
            }
        }
        driftCountsByAgent = fresh
    }

    private var toolbar: some View {
        HStack(spacing: Spacing.s3) {
            Spacer()
            Text("\(visibleSources.count) of \(store.sources.count) folders")
                .font(ManifoldType.numericCaption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .background(.regularMaterial)
    }

    // MARK: - Table

    @ViewBuilder
    private var table: some View {
        Table(of: SourceRecord.self, selection: $selectedIDs, sortOrder: $sortOrder) {
            folderColumn
            if connectedAgents.count > 1 {
                allAgentsColumn
            }
            if useChipFallback {
                accessColumn
            } else {
                TableColumnForEach(connectedAgents, id: \.self) { agent in
                    agentColumn(for: agent)
                }
            }
            statusColumn
        } rows: {
            ForEach(visibleSources) { source in
                TableRow(source)
            }
        }
        .tableStyle(.inset)
    }

    private var folderColumn: TableColumn<SourceRecord, KeyPathComparator<SourceRecord>, some View, Text> {
        TableColumn("Folder", value: \.displayName) { source in
            HStack(spacing: Spacing.s2) {
                FileTypeIcon(filename: source.displayName, isFolder: true, size: 13)
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.displayName)
                        .font(ManifoldType.body)
                    Text(source.originalRootPath.shortenedPath)
                        .font(ManifoldType.mono)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let drift = driftSummary(for: source) {
                        driftBadge(drift)
                    }
                }
            }
        }
    }

    /// Drift summary for a source — agent + count. Picks the agent with
    /// the highest drift count; null when no agent has drift > 0. Render
    /// as a thin caption under the source path so the matrix stays tight
    /// while the signal is still visible.
    private struct DriftSummary {
        let agent: TargetApp
        let count: Int
    }

    private func driftSummary(for source: SourceRecord) -> DriftSummary? {
        var best: DriftSummary?
        for agent in connectedAgents {
            let count = driftCountsByAgent[agent]?[source.sourceID] ?? 0
            if count > 0, count > (best?.count ?? 0) {
                best = DriftSummary(agent: agent, count: count)
            }
        }
        return best
    }

    @ViewBuilder
    private func driftBadge(_ summary: DriftSummary) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(ManifoldPalette.attention)
                .accessibilityHidden(true)
            Text("\(summary.count) since \(displayName(for: summary.agent))'s last session")
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.attention)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help("\(summary.count) files have changed in this source since \(displayName(for: summary.agent))'s last session ended")
    }

    private func displayName(for agent: TargetApp) -> String {
        switch agent {
        case .cowork: return "Claude"
        case .codex:  return "Codex"
        }
    }

    private var allAgentsColumn: TableColumn<SourceRecord, Never, some View, Text> {
        TableColumn("Both") { (source: SourceRecord) in
            let scoped = scopedAgents(for: source)
            let allScoped = !connectedAgents.isEmpty && connectedAgents.allSatisfy { scoped.contains($0) }
            CoverageDotButton(
                state: allScoped ? .on : (scoped.isEmpty ? .off : .mixed),
                tint: ManifoldPalette.selection,
                accessibilityIdentifier: "access.folder.\(source.sourceID.manifoldAccessIdentifierComponent).all"
            ) {
                // Read live scope at click time. Two reasons:
                // 1. .mixed should always go ON (toward all-shared), never OFF —
                //    `!allScoped` would flip it OFF first, which is surprising.
                // 2. If the cell rendered with a stale snapshot of governance
                //    (TableColumn cells on macOS occasionally lag the
                //    @Observable store), recomputing here avoids a no-op
                //    click that looked like the toggle was broken.
                Task {
                    let liveScoped = scopedAgents(for: source)
                    let liveAll = !connectedAgents.isEmpty
                        && connectedAgents.allSatisfy { liveScoped.contains($0) }
                    await setSourceScope(
                        sourceID: source.sourceID,
                        agents: connectedAgents,
                        inScope: !liveAll
                    )
                }
            }
        }
        .width(min: 46, ideal: 56, max: 68)
    }

    private func agentColumn(for agent: TargetApp) -> TableColumn<SourceRecord, Never, some View, Text> {
        TableColumn(LocalizedStringKey(AgentMeta.label(agent))) { (source: SourceRecord) in
            CoverageDotButton(
                state: scopeByAgent[agent]?.contains(source.sourceID) == true ? .on : .off,
                tint: AgentMeta.color(agent),
                accessibilityIdentifier: "access.folder.\(source.sourceID.manifoldAccessIdentifierComponent).agent.\(agent.rawValue)"
            ) {
                let currently = scopeByAgent[agent]?.contains(source.sourceID) == true
                Task {
                    await store.setSourceScope(sourceID: source.sourceID, agent: agent, inScope: !currently)
                }
            }
        }
        .width(min: 54, ideal: 72, max: 90)
    }

    private var accessColumn: TableColumn<SourceRecord, Never, some View, Text> {
        TableColumn("Access") { (source: SourceRecord) in
            let visible = scopedAgents(for: source)
            AccessCheckboxStrip(
                agents: connectedAgents,
                visibleAgents: visible,
                accessibilityIDPrefix: "access.folder.\(source.sourceID.manifoldAccessIdentifierComponent)",
                onToggleAgent: { agent, wasVisible in
                    Task {
                        await store.setSourceScope(sourceID: source.sourceID, agent: agent, inScope: !wasVisible)
                    }
                },
                onSetAll: { inScope in
                    Task {
                        await setSourceScope(sourceID: source.sourceID, agents: connectedAgents, inScope: inScope)
                    }
                }
            )
        }
    }

    private var statusColumn: TableColumn<SourceRecord, Never, some View, Text> {
        TableColumn("Sharing") { (source: SourceRecord) in
            // Source health takes priority — a removed or offline folder
            // can't actually share anything regardless of scope. For the
            // common case (accessible folder) the pill describes the
            // share state across every connected AI: all / part / none.
            if source.isRemoved {
                Pill(text: "Removed", variant: .attention)
            } else if !source.isAccessible {
                Pill(text: "Offline", variant: .attention)
            } else {
                let label = sharingLabel(for: source)
                Pill(text: label.text, variant: label.variant)
                    .help(label.help)
            }
        }
        .width(min: 110, ideal: 140, max: 180)
    }

    private struct SharingLabel {
        let text: String
        let variant: Pill.Variant
        let help: String
    }

    /// Compute the sharing pill for a source. Three states the user
    /// asked for — all / part / none — each with a label that names
    /// what's happening rather than relying on a colored dot.
    private func sharingLabel(for source: SourceRecord) -> SharingLabel {
        let scoped = scopedAgents(for: source)
        let total = connectedAgents.count

        // No AIs activated yet — say so plainly. Sharing isn't possible
        // until the user wires up at least one AI.
        guard total > 0 else {
            return SharingLabel(
                text: "No AIs connected",
                variant: .neutral,
                help: "Activate Claude or Codex in Settings before sharing folders."
            )
        }

        if scoped.isEmpty {
            return SharingLabel(
                text: "Not shared",
                variant: .neutral,
                help: "No AI can see this folder."
            )
        }

        if scoped.count == total {
            let text = total == 1
                ? "Shared"
                : (total == 2 ? "Shared with both" : "Shared with all")
            let names = connectedAgents.map(displayName(for:)).joined(separator: " and ")
            return SharingLabel(
                text: text,
                variant: .defaultScope,
                help: "Visible to \(names)."
            )
        }

        // Partial: name the AI when only one sees it; otherwise say
        // "X of Y" and list the names in the tooltip.
        let scopedNames = connectedAgents
            .filter { scoped.contains($0) }
            .map(displayName(for:))
        if scoped.count == 1, let only = scopedNames.first {
            return SharingLabel(
                text: "Shared with \(only)",
                variant: .scope,
                help: "Only \(only) can see this folder."
            )
        }
        return SharingLabel(
            text: "Partly shared · \(scoped.count) of \(total)",
            variant: .scope,
            help: "Visible to \(scopedNames.joined(separator: " and "))."
        )
    }

    // MARK: - Bulk bar

    private var bulkBar: some View {
        HStack(spacing: Spacing.s2) {
            Text("\(selectedIDs.count) selected")
                .font(ManifoldType.captionMedium)

            Spacer()

            if !connectedAgents.isEmpty {
                Button {
                    Task { await bulkShare(agents: connectedAgents, inScope: true) }
                } label: {
                    Label("Share with Both", systemImage: "person.2.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(ManifoldPalette.selection)

                Button {
                    Task { await bulkShare(agents: connectedAgents, inScope: false) }
                } label: {
                    Label("Unshare from Both", systemImage: "person.2.slash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Menu {
                    if connectedAgents.count > 1 {
                        Button("Both") {
                            Task { await bulkShare(agents: connectedAgents, inScope: true) }
                        }
                        Divider()
                    }
                    ForEach(connectedAgents, id: \.self) { agent in
                        Button(AgentMeta.label(agent)) {
                            Task { await bulkShare(agent: agent, inScope: true) }
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
                            Task { await bulkShare(agents: connectedAgents, inScope: false) }
                        }
                        Divider()
                    }
                    ForEach(connectedAgents, id: \.self) { agent in
                        Button(AgentMeta.label(agent)) {
                            Task { await bulkShare(agent: agent, inScope: false) }
                        }
                    }
                } label: {
                    Label("Unshare from", systemImage: "minus.circle")
                }
                .menuStyle(.button)
                .controlSize(.small)
            }

            Button("Remove", role: .destructive) {
                let paths = store.sources
                    .filter { selectedIDs.contains($0.sourceID) }
                    .map(\.originalRootPath)
                store.removeSources(paths: Set(paths))
                selectedIDs.removeAll()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(ManifoldPalette.attention)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private func bulkShare(agent: TargetApp, inScope: Bool) async {
        for id in selectedIDs {
            await store.setSourceScope(sourceID: id, agent: agent, inScope: inScope)
        }
    }

    private func bulkShare(agents: [TargetApp], inScope: Bool) async {
        for id in selectedIDs {
            await setSourceScope(sourceID: id, agents: agents, inScope: inScope)
        }
    }

    private func setSourceScope(sourceID: String, agents: [TargetApp], inScope: Bool) async {
        for agent in agents {
            await store.setSourceScope(sourceID: sourceID, agent: agent, inScope: inScope)
        }
    }

    private var selectedSource: SourceRecord? {
        guard let id = selectedIDs.first else { return nil }
        return store.sources.first(where: { $0.sourceID == id })
    }
}

// MARK: - CoverageDotButton

/// Native checkbox glyph for the per-agent matrix cells. Replaces the
/// previous filled-circle indicator that users mistook for a non-
/// interactive status dot. SF Symbol checkbox glyphs match Apple's
/// Privacy & Security ▸ Files and Folders pane and the redesigned file
/// inspector's parent-child selector — same visual language across the
/// access surface, no ambiguity about clickability.
///
/// State map:
///   off    → hollow square        (`square`)
///   on     → tinted checked       (`checkmark.square.fill`, agent color)
///   mixed  → tinted minus         (`minus.square.fill`, agent color)
///
/// Hit region is a 28×24 rectangle around the 16pt glyph so clicks
/// inside the matrix cell reliably reach the button rather than the
/// underlying Table row's selection target.
private struct CoverageDotButton: View {
    enum State {
        case off
        case on
        case mixed
    }

    let state: State
    let tint: Color
    let accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(state == .off ? Color.secondary : tint)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    @ViewBuilder
    private var glyph: some View {
        switch state {
        case .on:    Image(systemName: "checkmark.square.fill")
        case .off:   Image(systemName: "square")
        case .mixed: Image(systemName: "minus.square.fill")
        }
    }

    private var helpText: String {
        switch state {
        case .on:    return "Shared. Click to unshare."
        case .off:   return "Not shared. Click to share."
        case .mixed: return "Partially shared. Click to share with both."
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .on:    return "shared"
        case .off:   return "not shared"
        case .mixed: return "partially shared"
        }
    }
}
