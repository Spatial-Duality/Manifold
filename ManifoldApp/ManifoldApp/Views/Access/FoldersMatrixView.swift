// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FoldersMatrixView — sources × agents coverage matrix.
//
// Columns are driven by `store.connectedAgents` so the matrix scales
// from one agent to four. Beyond four, the per-agent columns collapse
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
                }
            }
        }
    }

    private func agentColumn(for agent: TargetApp) -> TableColumn<SourceRecord, Never, some View, Text> {
        TableColumn(LocalizedStringKey(AgentMeta.label(agent))) { (source: SourceRecord) in
            CoverageDotButton(
                on: scopeByAgent[agent]?.contains(source.sourceID) == true,
                tint: AgentMeta.color(agent)
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
            let visible = Set(connectedAgents.filter { scopeByAgent[$0]?.contains(source.sourceID) == true })
            AccessChipStack(
                agents: connectedAgents,
                visibleAgents: visible,
                onToggle: { agent, wasVisible in
                    Task {
                        await store.setSourceScope(sourceID: source.sourceID, agent: agent, inScope: !wasVisible)
                    }
                }
            )
        }
    }

    private var statusColumn: TableColumn<SourceRecord, Never, some View, Text> {
        TableColumn("Status") { (source: SourceRecord) in
            if source.isRemoved {
                Pill(text: "removed", variant: .attention)
            } else if !source.isAccessible {
                Pill(text: "offline", variant: .attention)
            } else {
                Pill(text: "active", variant: .defaultScope)
            }
        }
        .width(100)
    }

    // MARK: - Bulk bar

    private var bulkBar: some View {
        HStack(spacing: Spacing.s2) {
            Text("\(selectedIDs.count) selected")
                .font(ManifoldType.captionMedium)

            Spacer()

            if !connectedAgents.isEmpty {
                Menu {
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

    private var selectedSource: SourceRecord? {
        guard let id = selectedIDs.first else { return nil }
        return store.sources.first(where: { $0.sourceID == id })
    }
}

// MARK: - CoverageDotButton

private struct CoverageDotButton: View {
    let on: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(on ? tint : ManifoldPalette.surface3)
                .overlay(Circle().strokeBorder(on ? tint.opacity(0.4) : ManifoldPalette.border, lineWidth: 0.8))
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .help(on ? "In scope — click to unshare" : "Not in scope — click to share")
        .accessibilityLabel(on ? "In scope" : "Not in scope")
    }
}
