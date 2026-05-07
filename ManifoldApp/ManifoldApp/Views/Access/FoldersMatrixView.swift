// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FoldersMatrixView — sources × agents coverage matrix.
//
// Columns are driven by the app's supported agents so access can be
// configured before Claude or Codex connect. Beyond four, columns collapse
// into a single Access column rendering the same checkbox strip per row.
// Cells are interactive: clicking a coverage dot toggles the source's
// membership in that agent's default scope.

import AppKit
import SwiftUI
import ManifoldKit

struct FoldersMatrixView: View {
    @Environment(ManifoldStore.self) private var store
    @Binding private var inspectorVisible: Bool

    @Binding private var searchText: String
    @State private var selectedIDs: Set<String> = []
    @State private var sortOrder: [KeyPathComparator<SourceRecord>] = [
        KeyPathComparator(\SourceRecord.displayName)
    ]
    /// Per-agent drift counts keyed by sourceID. "Drift" = files with
    /// non-baseline snapshots after that agent's most recently ended
    /// grant. Loaded lazily on appear and refreshed when the connected-
    /// agents set changes; absence means "no signal yet" not "zero drift".
    @State private var driftCountsByAgent: [TargetApp: [String: Int]] = [:]
    /// Per-agent file-level overrides. Used by the Sharing column so a
    /// folder that's *not* in any AI's source scope but still has
    /// explicit allow overrides on individual files reads as "Some files
    /// shared" instead of the misleading "Not shared".
    @State private var overridesByAgent: [TargetApp: [FileVisibilityOverrideRecord]] = [:]
    @State private var recoverySource: SourceRecord?
    @State private var recoverySuggestions: [FinderTagRecoverySuggestion] = []
    @State private var recoverySearchInFlight = false
    @State private var showingRecoverySheet = false

    init(
        searchText: Binding<String> = .constant(""),
        inspectorVisible: Binding<Bool> = .constant(true)
    ) {
        _searchText = searchText
        _inspectorVisible = inspectorVisible
    }

    // MARK: - Derived

    private var connectedAgents: [TargetApp] {
        AgentMeta.connected(from: store.connectedAgents)
    }

    private var useChipFallback: Bool {
        connectedAgents.count > 4
    }

    private var shareColumnWidth: CGFloat {
        AccessCheckboxStrip.compactWidth(agentCount: connectedAgents.count)
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

    /// Color the folder icon by which assistants currently have this source
    /// in scope — reads from the live governance policies rather than the
    /// (possibly narrower) connected-agent set, so the cue stays accurate
    /// even when an assistant isn't currently connected.
    private func sharingTint(for source: SourceRecord) -> Color {
        let cowork = store.governance.policy(for: .cowork)?.allowedSourceIDs.contains(source.sourceID) ?? false
        let codex = store.governance.policy(for: .codex)?.allowedSourceIDs.contains(source.sourceID) ?? false
        return ManifoldPalette.sharingTint(coworkShared: cowork, codexShared: codex)
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
        VStack(spacing: 0) {
            toolbar
            table
            if !selectedIDs.isEmpty {
                bulkBar
            }
        }
        .inspector(isPresented: $inspectorVisible) {
            FileTreeInspector(source: selectedSource) {
                Task { await loadOverrides() }
            }
            .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
        }
        .task(id: connectedAgentsKey) {
            await loadDriftCounts()
            await loadOverrides()
        }
        .sheet(isPresented: $showingRecoverySheet) {
            FinderTagRecoverySheet(
                source: recoverySource,
                suggestions: recoverySuggestions,
                onReconnect: { suggestion in
                    guard suggestion.isSourceRoot, suggestion.isDirectory else { return }
                    Task {
                        await store.repairSource(
                            sourceID: suggestion.sourceID,
                            url: URL(fileURLWithPath: suggestion.suggestedPath)
                        )
                    }
                }
            )
        }
        .manifoldFileDropTarget(store: store)
    }

    private var connectedAgentsKey: String {
        AgentMeta.stableKey(connectedAgents)
    }

    /// Pulls drift counts for every connected agent in parallel. Failures
    /// land as empty maps so the matrix renders without drift badges
    /// instead of erroring out.
    private func loadDriftCounts() async {
        let agents = connectedAgents
        let fresh = await withTaskGroup(of: (TargetApp, [String: Int]).self) { group in
            for agent in agents {
                group.addTask {
                    let counts = (try? await store.runtime.sourceDriftCounts(agent: agent)) ?? [:]
                    return (agent, counts)
                }
            }
            var result: [TargetApp: [String: Int]] = [:]
            for await (agent, counts) in group { result[agent] = counts }
            return result
        }
        if fresh != driftCountsByAgent { driftCountsByAgent = fresh }
    }

    private func loadOverrides() async {
        let fresh = await store.fileVisibilityOverridesByAgent(connectedAgents)
        if fresh != overridesByAgent { overridesByAgent = fresh }
    }

    /// Per-source breakdown of explicit overrides — agents that have at
    /// least one allow / deny on a file inside this source. Empty sets
    /// mean "no overrides for this source," which is the common case.
    private func overrideAgentsByDecision(for source: SourceRecord) -> (allow: Set<TargetApp>, deny: Set<TargetApp>) {
        var allow: Set<TargetApp> = []
        var deny: Set<TargetApp> = []
        for agent in connectedAgents {
            guard let entries = overridesByAgent[agent] else { continue }
            for record in entries where record.sourceID == source.sourceID {
                switch record.decision {
                case .allow: allow.insert(agent)
                case .deny:  deny.insert(agent)
                }
            }
        }
        return (allow, deny)
    }

    private var toolbar: some View {
        HStack(spacing: Spacing.s3) {
            mirrorStateBadge
            Spacer()
            Text("\(visibleSources.count) of \(store.sources.count) folders")
                .font(ManifoldType.numericCaption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
    }

    /// Small badge showing whether the active Focus is mirroring or
    /// has separate-sharing on. Per HIG: "Status — always reinforced
    /// by a second channel (icon/text)" — icon + tinted text + tooltip.
    /// Drives the user's confidence about how a tick will behave.
    @ViewBuilder
    private var mirrorStateBadge: some View {
        let agent = connectedAgents.first ?? .cowork
        if let focusID = store.activeFocusID[agent],
           let focus = store.availableFocuses.first(where: { $0.presetID == focusID }) {
            HStack(spacing: 4) {
                Image(systemName: focus.mirrorToBoth ? "link" : "link.badge.plus")
                    .foregroundStyle(focus.mirrorToBoth ? ManifoldPalette.active : .secondary)
                Text(focus.mirrorToBoth
                    ? "Mirror: ticking either AI ticks both"
                    : "Separate: Claude and Codex are independent")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            .help("Mirror state is set per-Focus. Toggle 'Mirror to both AIs' on the active Focus to change.")
        }
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
                FileTypeIcon(
                    filename: source.displayName,
                    isFolder: true,
                    size: 13,
                    tint: sharingTint(for: source)
                )
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Spacing.s1) {
                        Text(source.displayName)
                            .font(ManifoldType.body)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let health = sourceHealthLabel(for: source) {
                            Pill(text: health.text, variant: health.variant, systemImage: health.systemImage)
                                .help(health.help)
                        }
                    }
                    Text(source.effectiveRootPath.shortenedPath)
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
            Text("\(summary.count) since \(AgentMeta.label(summary.agent))'s last session")
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.attention)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help("\(summary.count) files have changed in this source since \(AgentMeta.label(summary.agent))'s last session ended")
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
                // Read live scope at click time. TableColumn cells on macOS
                // occasionally lag the @Observable store; recomputing here
                // avoids a stale no-op click. For a mixed row, the aggregate
                // checkbox behaves like "share with both," matching macOS
                // mixed-checkbox convention.
                Task {
                    let liveScoped = scopedAgents(for: source)
                    await setSourceScope(
                        sourceID: source.sourceID,
                        agents: connectedAgents,
                        inScope: Self.aggregateScopeTarget(
                            connectedAgents: connectedAgents,
                            scopedAgents: liveScoped
                        )
                    )
                }
            }
        }
        .width(min: 46, ideal: 56, max: 68)
    }

    static func aggregateScopeTarget(connectedAgents: [TargetApp], scopedAgents: Set<TargetApp>) -> Bool {
        let allScoped = !connectedAgents.isEmpty
            && connectedAgents.allSatisfy { scopedAgents.contains($0) }
        return !allScoped
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
                    await setSourceScope(sourceID: source.sourceID, agent: agent, inScope: !currently)
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
                showsTitles: false,
                accessibilityIDPrefix: "access.folder.\(source.sourceID.manifoldAccessIdentifierComponent)",
                onToggleAgent: { agent, wasVisible in
                    Task {
                        await setSourceScope(sourceID: source.sourceID, agent: agent, inScope: !wasVisible)
                    }
                },
                onSetAll: { inScope in
                    Task {
                        await setSourceScope(sourceID: source.sourceID, agents: connectedAgents, inScope: inScope)
                    }
                }
            )
        }
        .width(min: shareColumnWidth, ideal: shareColumnWidth, max: shareColumnWidth)
    }

    private var statusColumn: TableColumn<SourceRecord, Never, some View, Text> {
        TableColumn("Sharing") { (source: SourceRecord) in
            HStack(spacing: 4) {
                let label = sharingLabel(for: source)
                Pill(text: label.text, variant: label.variant)
                    .help(label.help)
                let write = writeLabel(for: source)
                Pill(text: write.text, variant: write.variant)
                    .help(write.help)
                if hasFileOverrides(for: source) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(ManifoldPalette.attention)
                        .help("Some files inside have explicit allow or deny overrides — open the inspector to see them.")
                        .accessibilityLabel("Has per-file overrides")
                }
                if source.sourceHealth != .available, source.sourceHealth != .unknown {
                    let health = sourceHealthLabel(for: source)
                    Pill(
                        text: health?.text ?? source.sourceHealth.displayName,
                        variant: health?.variant ?? .attention,
                        systemImage: health?.systemImage
                    )
                    .help(health?.help ?? source.sourceHealthDetail ?? source.sourceHealth.displayName)
                }
            }
        }
        .width(min: 110, ideal: 140, max: 180)
    }

    private struct SharingLabel {
        let text: String
        let variant: Pill.Variant
        let help: String
    }

    private struct SourceHealthLabel {
        let text: String
        let variant: Pill.Variant
        let systemImage: String?
        let help: String
    }

    private func sourceHealthLabel(for source: SourceRecord) -> SourceHealthLabel? {
        if !source.isAccessible {
            return SourceHealthLabel(
                text: "Offline",
                variant: .attention,
                systemImage: "pause.circle",
                help: "This source is paused or removed."
            )
        }
        switch source.sourceHealth {
        case .unknown:
            return SourceHealthLabel(
                text: "Check",
                variant: .neutral,
                systemImage: "questionmark.circle",
                help: "Manifold has not verified this source yet."
            )
        case .available:
            return nil
        case .moved:
            return SourceHealthLabel(
                text: "Moved",
                variant: .scope,
                systemImage: "arrow.triangle.swap",
                help: source.resolvedRootPath.map { "Resolved at \($0)" } ?? "Manifold followed this source to its new location."
            )
        case .staleBookmark:
            return SourceHealthLabel(
                text: "Refresh",
                variant: .scope,
                systemImage: "bookmark",
                help: source.sourceHealthDetail ?? "The saved bookmark works but should be refreshed."
            )
        case .missing:
            return SourceHealthLabel(
                text: "Missing",
                variant: .attention,
                systemImage: "exclamationmark.triangle",
                help: source.sourceHealthDetail ?? "The approved folder could not be found."
            )
        case .needsPermission:
            return SourceHealthLabel(
                text: "Permission",
                variant: .attention,
                systemImage: "lock",
                help: source.sourceHealthDetail ?? "Manifold needs permission to access this source."
            )
        case .replaced:
            return SourceHealthLabel(
                text: "Replaced",
                variant: .attention,
                systemImage: "xmark.octagon",
                help: source.sourceHealthDetail ?? "A different item exists at the approved location."
            )
        case .invalid:
            return SourceHealthLabel(
                text: "Invalid",
                variant: .attention,
                systemImage: "xmark.circle",
                help: source.sourceHealthDetail ?? "This source is not valid."
            )
        }
    }

    private func writeLabel(for source: SourceRecord) -> SharingLabel {
        let scoped = scopedAgents(for: source)
        guard !scoped.isEmpty else {
            return SharingLabel(
                text: "Read only",
                variant: .neutral,
                help: "This folder is not shared with an agent, so Manifold blocks reads and writes."
            )
        }
        return SharingLabel(
            text: "Versioned writes",
            variant: .defaultScope,
            help: "Claude or Codex writes to the original shared folder through Manifold. Each write records a restorable snapshot."
        )
    }

    /// Compute the sharing pill for a source. Source-level scope drives the
    /// main checked state, but explicit allow overrides are also effective
    /// runtime visibility. A row with no checked agent can still expose
    /// individual files, so call that out here instead of showing the
    /// misleading "Not shared" label.
    private func sharingLabel(for source: SourceRecord) -> SharingLabel {
        let scoped = scopedAgents(for: source)
        let total = connectedAgents.count
        let explicitAllowAgents = overrideAgentsByDecision(for: source).allow

        guard total > 0 else {
            return SharingLabel(
                text: "No AIs connected",
                variant: .neutral,
                help: "Activate Claude or Codex in Settings before sharing folders."
            )
        }

        if scoped.isEmpty {
            if !explicitAllowAgents.isEmpty {
                let names = connectedAgents
                    .filter { explicitAllowAgents.contains($0) }
                    .map(AgentMeta.label(_:))
                let target = names.isEmpty ? "an AI" : names.joined(separator: " and ")
                return SharingLabel(
                    text: explicitAllowAgents.count == 1
                        ? "Some files for \(names.first ?? "AI")"
                        : "Some files shared",
                    variant: .scope,
                    help: "Individual files or subfolders are visible to \(target). Open the inspector to review them."
                )
            }
            return SharingLabel(
                text: "Not shared",
                variant: .neutral,
                help: "No AI can see this folder."
            )
        }

        if scoped.count == total {
            let text = total == 1
                ? "Shared"
                : (total == 2 ? "Both agents" : "All agents")
            let names = connectedAgents.map(AgentMeta.label(_:)).joined(separator: " and ")
            return SharingLabel(
                text: text,
                variant: .defaultScope,
                help: "Visible to \(names)."
            )
        }

        let scopedNames = connectedAgents
            .filter { scoped.contains($0) }
            .map(AgentMeta.label(_:))
        if scoped.count == 1, let only = scopedNames.first {
            return SharingLabel(
                text: "\(only) only",
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

    /// Returns true when this source has any per-file allow or deny
    /// override across any connected AI. Used to render a small
    /// indicator next to the Sharing pill so the user knows there's
    /// extra detail in the inspector without cluttering the main
    /// label.
    ///
    /// Removed sources are excluded — overrides on a removed source
    /// have no enforcement effect (resolveAccess intersects with
    /// activeSources, which excludes status='removed'). Lighting the
    /// dot for a Removed row would falsely suggest per-file sharing
    /// is still active.
    private func hasFileOverrides(for source: SourceRecord) -> Bool {
        guard !source.isRemoved else { return false }
        let breakdown = overrideAgentsByDecision(for: source)
        return !breakdown.allow.isEmpty || !breakdown.deny.isEmpty
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
                    Label("Share with both", systemImage: "person.2.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(ManifoldPalette.selection)

                Button {
                    Task { await bulkShare(agents: connectedAgents, inScope: false) }
                } label: {
                    Label("Unshare from both", systemImage: "person.2.slash")
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

            if selectedIDs.count == 1, let selected = selectedSource {
                Button {
                    store.repairSourceFromPicker(sourceID: selected.sourceID)
                } label: {
                    Label("Locate", systemImage: "folder.badge.questionmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task { await loadFinderTagRecoverySuggestions(for: selected) }
                } label: {
                    Label(recoverySearchInFlight ? "Searching" : "Tagged Items", systemImage: "tag")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(recoverySearchInFlight)
                .help("Search Finder tags recorded for this source.")
            }

            Button("Remove", role: .destructive) {
                store.removeSources(sourceIDs: selectedIDs)
                selectedIDs.removeAll()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(ManifoldPalette.attention)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .overlay(Divider(), alignment: .top)
    }

    private func bulkShare(agent: TargetApp, inScope: Bool) async {
        for id in selectedIDs {
            await store.setSourceScope(sourceID: id, agent: agent, inScope: inScope)
        }
        await loadOverrides()
    }

    private func bulkShare(agents: [TargetApp], inScope: Bool) async {
        for id in selectedIDs {
            await setSourceScope(sourceID: id, agents: agents, inScope: inScope)
        }
    }

    private func setSourceScope(sourceID: String, agent: TargetApp, inScope: Bool) async {
        await store.setSourceScope(sourceID: sourceID, agent: agent, inScope: inScope)
        await loadOverrides()
    }

    private func setSourceScope(sourceID: String, agents: [TargetApp], inScope: Bool) async {
        for agent in agents {
            await store.setSourceScope(sourceID: sourceID, agent: agent, inScope: inScope)
        }
        await loadOverrides()
    }

    private func loadFinderTagRecoverySuggestions(for source: SourceRecord) async {
        recoverySearchInFlight = true
        recoverySource = source
        recoverySuggestions = await store.finderTagRecoverySuggestions(for: source)
        recoverySearchInFlight = false
        showingRecoverySheet = true
    }

    private var selectedSource: SourceRecord? {
        guard let id = selectedIDs.first else { return nil }
        return store.sources.first(where: { $0.sourceID == id })
    }
}

private struct FinderTagRecoverySheet: View {
    @Environment(\.dismiss) private var dismiss

    let source: SourceRecord?
    let suggestions: [FinderTagRecoverySuggestion]
    let onReconnect: (FinderTagRecoverySuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tagged Items")
                        .font(ManifoldType.heading)
                    if let source {
                        Text(source.displayName)
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if suggestions.isEmpty {
                ContentUnavailableView(
                    "No Moved Tagged Items",
                    systemImage: "tag.slash",
                    description: Text("Spotlight did not return a renamed or moved item for this source.")
                )
                .frame(minWidth: 440, minHeight: 220)
            } else {
                List(suggestions) { suggestion in
                    HStack(spacing: Spacing.s3) {
                        Image(systemName: suggestion.isDirectory ? "folder" : "doc")
                            .foregroundStyle(suggestion.isSourceRoot ? ManifoldPalette.active : .secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.suggestedPath.shortenedPath)
                                .font(ManifoldType.body)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("Was \(suggestion.originalPath.shortenedPath)")
                                .font(ManifoldType.mono)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Pill(
                            text: suggestion.matchKind == .fileIdentity ? "Identity" : "Tag",
                            variant: suggestion.matchKind == .fileIdentity ? .defaultScope : .neutral
                        )

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([
                                URL(fileURLWithPath: suggestion.suggestedPath),
                            ])
                        } label: {
                            Image(systemName: "eye")
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")

                        if suggestion.isSourceRoot, suggestion.isDirectory {
                            Button("Reconnect") {
                                onReconnect(suggestion)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minWidth: 560, minHeight: 320)
            }
        }
        .padding(Spacing.s5)
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
