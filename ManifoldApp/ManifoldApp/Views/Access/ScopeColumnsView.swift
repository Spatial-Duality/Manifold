// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ScopeColumnsView — the canonical Scope view.
//
// Three columns make the grant model spatial (Principle 4): sources
// live in whichever column their current (Claude, Codex) state implies.
// The middle "Shared" column is derived and read-only — items land
// there by virtue of being in both flanking columns. A horizontal
// sources dock at the bottom houses sources not in any agent's scope.
//
// Drag gestures move sources between columns and the mutation is
// determined by the *destination* — dropping onto Claude sets
// (Claude: on, Codex: off), onto Shared sets (on, on), onto Codex sets
// (off, on), and onto the dock revokes both. The source column's prior
// state doesn't need to be consulted; the target state is asserted.
//
// Keyboard: with a source selected, ⌘1/⌘2/⌘3/⌘0 grant/revoke per §4.3.
// Right-hand inspector reuses FileTreeInspector on the selection.
//
// Per §2.5.9 ("of course" test): if you remove the column headers, the
// spatial story still reads — Claude is left, shared is middle, Codex
// is right. The derived column wears a dashed border and a recessed
// surface tone so it signals "this is a result, not a control."

import SwiftUI
import AppKit
import ManifoldKit

struct ScopeColumnsView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var selectedSourceID: String?
    /// Session filter: .all (default scope + session adds), .sessionOnly
    /// (highlight just the session-added rows, default rows fade). Bound
    /// to the SessionBanner picker — nil when no session is live.
    @State private var sessionFilter: SessionFilter = .all

    private var claudeIDs: Set<String> {
        Set(store.policy.claudePolicy?.allowedSourceIDs ?? [])
    }
    private var codexIDs: Set<String> {
        Set(store.policy.codexPolicy?.allowedSourceIDs ?? [])
    }

    private var activeSources: [SourceRecord] {
        store.sources.filter { !$0.isRemoved }
    }

    /// Session-added source IDs, derived from PolicyModel. Empty when
    /// no session is live or nothing has been added beyond default.
    private var sessionAddIDs: Set<String> { store.policy.sessionAdditionIDs }
    /// Session-removed source IDs (default sources the session excluded).
    private var sessionRemoveIDs: Set<String> { store.policy.sessionRemovalIDs }

    enum SessionFilter: Hashable { case all, sessionOnly }

    private var claudeOnly: [SourceRecord] {
        activeSources.filter {
            claudeIDs.contains($0.sourceID) && !codexIDs.contains($0.sourceID)
        }
    }
    private var shared: [SourceRecord] {
        activeSources.filter {
            claudeIDs.contains($0.sourceID) && codexIDs.contains($0.sourceID)
        }
    }
    private var codexOnly: [SourceRecord] {
        activeSources.filter {
            !claudeIDs.contains($0.sourceID) && codexIDs.contains($0.sourceID)
        }
    }
    private var unshared: [SourceRecord] {
        activeSources.filter {
            !claudeIDs.contains($0.sourceID) && !codexIDs.contains($0.sourceID)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if let session = store.policy.activeSession {
                    SessionBanner(
                        session: session,
                        additionCount: sessionAddIDs.count,
                        removalCount: sessionRemoveIDs.count,
                        filter: $sessionFilter
                    )
                    Divider()
                }
                columns
                Divider()
                SourcesDock(
                    sources: unshared,
                    selection: $selectedSourceID,
                    onDrop: { id in
                        Task { await revokeAll(id: id) }
                    },
                    contextActions: { id in
                        rowContextMenu(for: id)
                    }
                )
            }
            Divider()
            FileTreeInspector(source: selectedSource)
                .frame(width: 320)
                .background(ManifoldPalette.surface2)
        }
        .background(keyboardBridge)
    }

    private var columns: some View {
        HStack(spacing: Spacing.s3) {
            ScopeColumn(
                kind: .claudeOnly,
                sources: claudeOnly,
                selection: $selectedSourceID,
                sessionAddIDs: sessionAddIDs,
                sessionFilter: sessionFilter,
                onAccept: { id in
                    Task { await setState(id: id, claude: true, codex: false) }
                },
                contextActions: { id in
                    rowContextMenu(for: id)
                }
            )
            ScopeColumn(
                kind: .shared,
                sources: shared,
                selection: $selectedSourceID,
                sessionAddIDs: sessionAddIDs,
                sessionFilter: sessionFilter,
                onAccept: { id in
                    Task { await setState(id: id, claude: true, codex: true) }
                },
                contextActions: { id in
                    rowContextMenu(for: id)
                }
            )
            ScopeColumn(
                kind: .codexOnly,
                sources: codexOnly,
                selection: $selectedSourceID,
                sessionAddIDs: sessionAddIDs,
                sessionFilter: sessionFilter,
                onAccept: { id in
                    Task { await setState(id: id, claude: false, codex: true) }
                },
                contextActions: { id in
                    rowContextMenu(for: id)
                }
            )
        }
        .padding(Spacing.s4)
    }

    /// Native macOS context menu per §4.3 / Priority 1. Keyboard equivalents
    /// live on the hidden `keyboardBridge` overlay so they fire whenever a
    /// source is selected — not only while the context menu is open. Do NOT
    /// attach `.keyboardShortcut` to these menu items: AppKit would treat
    /// the duplicates as conflicting registrations and silently shadow the
    /// bridge.
    @ViewBuilder
    private func rowContextMenu(for id: String) -> some View {
        let inClaude = claudeIDs.contains(id)
        let inCodex = codexIDs.contains(id)
        let source = store.sources.first(where: { $0.sourceID == id })

        Button {
            Task { await toggle(id: id, agent: .cowork) }
        } label: {
            Label(inClaude ? "Revoke from Claude" : "Share with Claude",
                  systemImage: inClaude ? "minus.circle" : "plus.circle")
        }

        Button {
            Task { await toggle(id: id, agent: .codex) }
        } label: {
            Label(inCodex ? "Revoke from Codex" : "Share with Codex",
                  systemImage: inCodex ? "minus.circle" : "plus.circle")
        }

        Button {
            Task { await setState(id: id, claude: true, codex: true) }
        } label: {
            Label("Share with Both", systemImage: "person.2.fill")
        }
        .disabled(inClaude && inCodex)

        Button(role: .destructive) {
            Task { await revokeAll(id: id) }
        } label: {
            Label("Revoke All", systemImage: "xmark.circle")
        }
        .disabled(!inClaude && !inCodex)

        Divider()

        if let source {
            Button {
                let url = URL(fileURLWithPath: source.originalRootPath)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .disabled(!source.isAccessible)

            Button(role: .destructive) {
                store.removeSource(path: source.originalRootPath)
            } label: {
                Label("Remove Source from Manifold…", systemImage: "trash")
            }
        }
    }

    /// Hidden keyboard shortcut rig — active only when a source is selected.
    @ViewBuilder
    private var keyboardBridge: some View {
        if let id = selectedSourceID {
            VStack(spacing: 0) {
                Button("Toggle Claude") {
                    Task { await toggle(id: id, agent: .cowork) }
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Toggle Codex") {
                    Task { await toggle(id: id, agent: .codex) }
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Share with both") {
                    Task { await setState(id: id, claude: true, codex: true) }
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Revoke all") {
                    Task { await revokeAll(id: id) }
                }
                .keyboardShortcut("0", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private var selectedSource: SourceRecord? {
        guard let id = selectedSourceID else { return nil }
        return store.sources.first(where: { $0.sourceID == id })
    }

    // MARK: - Mutations

    /// Assert a target (claude, codex) grant state for a source. Only
    /// issues mutations where the current state differs from the target.
    private func setState(id: String, claude: Bool, codex: Bool) async {
        let inClaude = claudeIDs.contains(id)
        let inCodex = codexIDs.contains(id)

        if claude && !inClaude {
            await store.policy.addSource(id, to: .cowork)
        } else if !claude && inClaude {
            await store.policy.removeSource(id, from: .cowork)
        }

        if codex && !inCodex {
            await store.policy.addSource(id, to: .codex)
        } else if !codex && inCodex {
            await store.policy.removeSource(id, from: .codex)
        }
    }

    private func toggle(id: String, agent: TargetApp) async {
        let inScope = (agent == .cowork ? claudeIDs : codexIDs).contains(id)
        if inScope {
            await store.policy.removeSource(id, from: agent)
        } else {
            await store.policy.addSource(id, to: agent)
        }
    }

    private func revokeAll(id: String) async {
        if claudeIDs.contains(id) {
            await store.policy.removeSource(id, from: .cowork)
        }
        if codexIDs.contains(id) {
            await store.policy.removeSource(id, from: .codex)
        }
    }
}

// MARK: - Column

private struct ScopeColumn<Actions: View>: View {
    enum Kind: Equatable {
        case claudeOnly, shared, codexOnly

        var title: String {
            switch self {
            case .claudeOnly: return "Claude"
            case .shared:     return "Shared"
            case .codexOnly:  return "Codex"
            }
        }

        var accent: Color {
            switch self {
            case .claudeOnly: return ManifoldPalette.claude
            case .shared:     return ManifoldPalette.text2
            case .codexOnly:  return ManifoldPalette.codex
            }
        }

        var isDerived: Bool { self == .shared }

        var emptyHint: String {
            switch self {
            case .claudeOnly: return "Drop a folder here to share only with Claude."
            case .shared:     return "Nothing shared with both agents yet."
            case .codexOnly:  return "Drop a folder here to share only with Codex."
            }
        }
    }

    let kind: Kind
    let sources: [SourceRecord]
    @Binding var selection: String?
    let sessionAddIDs: Set<String>
    let sessionFilter: ScopeColumnsView.SessionFilter
    let onAccept: (String) -> Void
    @ViewBuilder let contextActions: (String) -> Actions

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            header
            content
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(background)
        .overlay(overlayBorder)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            onAccept(id)
            return true
        } isTargeted: { targeted in
            withAnimation(ManifoldMotion.micro) { isTargeted = targeted }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(kind.title)
        .accessibilityHint(kind.isDerived
            ? "Derived. Sources appear here when shared with both agents."
            : "Drop a folder here to share it only with \(kind.title).")
    }

    private var header: some View {
        HStack(spacing: Spacing.s2) {
            Circle()
                .fill(kind.accent)
                .frame(width: 8, height: 8)
            Text(kind.title.uppercased())
                .font(ManifoldType.tiny.weight(.semibold))
                .foregroundStyle(kind.accent)
                .tracking(0.8)
            if kind.isDerived {
                Text("derived")
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(
                        Capsule().strokeBorder(ManifoldPalette.border, style: StrokeStyle(lineWidth: 0.6, dash: [2, 2]))
                    )
            }
            Spacer()
            if !sources.isEmpty {
                Text("\(sources.count)")
                    .font(ManifoldType.tiny.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if sources.isEmpty {
            VStack(spacing: Spacing.s2) {
                Spacer()
                Text(kind.emptyHint)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.s2)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(sources) { source in
                        let isSessionAdd = sessionAddIDs.contains(source.sourceID)
                        SourceChip(
                            source: source,
                            accent: kind.accent,
                            isSelected: selection == source.sourceID,
                            isSessionAdd: isSessionAdd
                        )
                        .opacity(dimmingOpacity(forSessionAdd: isSessionAdd))
                        .onTapGesture { selection = source.sourceID }
                        .draggable(source.sourceID) {
                            SourceChip(
                                source: source,
                                accent: kind.accent,
                                isSelected: true,
                                isSessionAdd: isSessionAdd
                            )
                            .frame(width: 200)
                        }
                        .contextMenu {
                            contextActions(source.sourceID)
                        }
                    }
                }
            }
        }
    }

    /// When the filter is set to session-only, default sources dim so the
    /// session additions read louder. Otherwise everything renders full-weight.
    private func dimmingOpacity(forSessionAdd isSessionAdd: Bool) -> Double {
        switch sessionFilter {
        case .all:         return 1
        case .sessionOnly: return isSessionAdd ? 1 : 0.38
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
            .fill(backgroundFill)
    }

    private var backgroundFill: Color {
        if isTargeted { return kind.accent.opacity(0.10) }
        return kind.isDerived ? ManifoldPalette.surface2 : ManifoldPalette.surface
    }

    private var overlayBorder: some View {
        RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
            .strokeBorder(
                isTargeted ? kind.accent.opacity(0.55) : ManifoldPalette.border,
                style: StrokeStyle(
                    lineWidth: isTargeted ? 1.2 : 0.6,
                    dash: kind.isDerived ? [3, 3] : []
                )
            )
    }
}

// MARK: - Source chip

private struct SourceChip: View {
    let source: SourceRecord
    let accent: Color
    let isSelected: Bool
    /// True when this source is in scope only because a live session added
    /// it (it's not in the agent's default policy). Renders a small
    /// "session" clock icon so the row tells the truth about why it's here.
    var isSessionAdd: Bool = false

    var body: some View {
        HStack(spacing: Spacing.s2) {
            FileTypeIcon(filename: source.displayName, isFolder: true, size: 13)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.displayName)
                    .font(ManifoldType.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: Spacing.s1) {
                    Text(source.originalRootPath.shortenedPath)
                        .font(ManifoldType.tiny.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // Honest size readout — only renders when the runtime
                    // actually walked this source (v21 size cache). Silent
                    // when absent; we never fabricate "0 files" for a
                    // source we haven't scanned yet.
                    if let summary = SourceSizeFormatter.summary(for: source) {
                        Text("·")
                            .font(ManifoldType.tiny)
                            .foregroundStyle(.tertiary)
                        Text(summary)
                            .font(ManifoldType.tiny.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            if isSessionAdd {
                Image(systemName: "clock.badge.checkmark")
                    .font(.caption2)
                    .foregroundStyle(ManifoldPalette.active)
                    .help("Added by the live session — not in the agent's default scope.")
            }
            if !source.isAccessible {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(ManifoldPalette.attention)
                    .help("Source is offline or unavailable")
            }
        }
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .fill(isSelected ? accent.opacity(0.12) : ManifoldPalette.surface3.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .strokeBorder(isSelected ? accent.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Sources dock

/// Horizontal strip of sources not currently in any agent's scope.
/// Drops from a column land here to revoke all access.
private struct SourcesDock<Actions: View>: View {
    let sources: [SourceRecord]
    @Binding var selection: String?
    let onDrop: (String) -> Void
    @ViewBuilder let contextActions: (String) -> Actions

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.s2) {
                Text("UNSHARED")
                    .font(ManifoldType.tiny.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                if !sources.isEmpty {
                    Text("\(sources.count)")
                        .font(ManifoldType.tiny.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("Drag into a column to share  ·  drop here to revoke")
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.top, Spacing.s2)
            .padding(.bottom, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s2) {
                    if sources.isEmpty {
                        Text("Every source is in an agent's scope.")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, Spacing.s2)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(sources) { source in
                            SourceChip(
                                source: source,
                                accent: ManifoldPalette.text2,
                                isSelected: selection == source.sourceID
                            )
                            .frame(width: 220)
                            .onTapGesture { selection = source.sourceID }
                            .draggable(source.sourceID) {
                                SourceChip(
                                    source: source,
                                    accent: ManifoldPalette.text2,
                                    isSelected: true
                                )
                                .frame(width: 220)
                            }
                            .contextMenu {
                                contextActions(source.sourceID)
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.bottom, Spacing.s2)
            }
        }
        .frame(minHeight: 84, maxHeight: 110)
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .fill(isTargeted ? ManifoldPalette.attention.opacity(0.08) : Color.clear)
                .allowsHitTesting(false)
        )
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            onDrop(id)
            return true
        } isTargeted: { targeted in
            withAnimation(ManifoldMotion.micro) { isTargeted = targeted }
        }
    }
}

// MARK: - Session banner
//
// Renders only when a session is live. Communicates (a) the session is
// live and for which agent, (b) how many sources the session has added
// or removed relative to default scope, (c) a toggle that dims default
// sources so session adds read louder. Replaces the old "Session"
// sub-tab; the session is now a temporal axis on the Scope view itself
// (plan §6.5).

private struct SessionBanner: View {
    let session: SessionRecord
    let additionCount: Int
    let removalCount: Int
    @Binding var filter: ScopeColumnsView.SessionFilter

    private var agentName: String {
        guard let agent = session.agents.first else { return "Agent" }
        return agent == .codex ? "Codex" : "Claude"
    }

    private var agentAccent: Color {
        guard let agent = session.agents.first else { return ManifoldPalette.text2 }
        return agent == .codex ? ManifoldPalette.codex : ManifoldPalette.claude
    }

    private var deltaSentence: String {
        switch (additionCount, removalCount) {
        case (0, 0): return "No changes relative to default scope."
        case (let a, 0): return "Session adds \(a) source\(a == 1 ? "" : "s") beyond default."
        case (0, let r): return "Session removes \(r) source\(r == 1 ? "" : "s") from default."
        case (let a, let r): return "Session adds \(a), removes \(r)."
        }
    }

    var body: some View {
        HStack(spacing: Spacing.s3) {
            HStack(spacing: Spacing.s2) {
                Circle()
                    .fill(agentAccent)
                    .frame(width: 8, height: 8)
                Text("\(agentName) session · live")
                    .font(ManifoldType.captionMedium)
                    .foregroundStyle(.primary)
                if let duration = session.displayDuration {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(duration)
                        .font(ManifoldType.tiny.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(deltaSentence)
                .font(ManifoldType.tiny)
                .foregroundStyle(.secondary)

            Spacer()

            if additionCount > 0 {
                Picker("Show", selection: $filter) {
                    Text("All scope").tag(ScopeColumnsView.SessionFilter.all)
                    Text("Session adds").tag(ScopeColumnsView.SessionFilter.sessionOnly)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.regularMaterial)
    }
}
