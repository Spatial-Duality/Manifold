// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FoldersMatrixView — sources × agents coverage matrix.
//
// The main page of the Access surface. Each row is a folder the user
// has shared; each agent gets a column showing whether the folder is in
// that agent's default scope. Selecting a row reveals a file-tree
// inspector with tri-state checkboxes.

import SwiftUI
import ManifoldKit

struct FoldersMatrixView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var selectedIDs: Set<String> = []

    private var claudeSourceIDs: Set<String> {
        Set(store.policy.claudePolicy?.allowedSourceIDs ?? [])
    }
    private var codexSourceIDs: Set<String> {
        Set(store.policy.codexPolicy?.allowedSourceIDs ?? [])
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Table(of: SourceRecord.self, selection: $selectedIDs) {
                    TableColumn("Folder") { source in
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
                    TableColumn("Claude") { source in
                        CoverageDot(on: claudeSourceIDs.contains(source.sourceID),
                                    tint: ManifoldPalette.claude)
                    }
                    .width(80)
                    TableColumn("Codex") { source in
                        CoverageDot(on: codexSourceIDs.contains(source.sourceID),
                                    tint: ManifoldPalette.codex)
                    }
                    .width(80)
                    TableColumn("Status") { source in
                        if source.isRemoved {
                            Pill(text: "removed", variant: .attention)
                        } else if !source.isAccessible {
                            Pill(text: "offline", variant: .attention)
                        } else {
                            Pill(text: "active", variant: .defaultScope)
                        }
                    }
                    .width(100)
                } rows: {
                    ForEach(store.sources) { source in
                        TableRow(source)
                    }
                }
                .tableStyle(.inset)

                if !selectedIDs.isEmpty {
                    BulkActionBar(selectedCount: selectedIDs.count) {
                        let paths = store.sources
                            .filter { selectedIDs.contains($0.sourceID) }
                            .map(\.originalRootPath)
                        store.removeSources(paths: Set(paths))
                        selectedIDs.removeAll()
                    }
                }
            }
            Divider()
            FoldersInspector(selection: selectedIDs.first, store: store)
                .frame(width: 280)
                .background(ManifoldPalette.surface2)
        }
    }
}

private struct CoverageDot: View {
    let on: Bool
    let tint: Color

    var body: some View {
        Circle()
            .fill(on ? tint : ManifoldPalette.surface3)
            .overlay(Circle().strokeBorder(on ? tint.opacity(0.4) : ManifoldPalette.border, lineWidth: 0.8))
            .frame(width: 10, height: 10)
            .accessibilityLabel(on ? "In scope" : "Not in scope")
    }
}

private struct BulkActionBar: View {
    let selectedCount: Int
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Text("\(selectedCount) selected")
                .font(ManifoldType.captionMedium)
            Spacer()
            Button("Remove", role: .destructive, action: onRemove)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(ManifoldPalette.attention)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }
}

private struct FoldersInspector: View {
    let selection: String?
    let store: ManifoldStore

    private var source: SourceRecord? {
        guard let selection else { return nil }
        return store.sources.first(where: { $0.sourceID == selection })
    }

    var body: some View {
        ScrollView {
            if let source {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    Text(source.displayName)
                        .font(ManifoldType.heading)
                    Text(source.originalRootPath.shortenedPath)
                        .font(ManifoldType.mono)
                        .foregroundStyle(ManifoldPalette.text2)
                        .textSelection(.enabled)

                    Divider()

                    Text("Agents")
                        .font(ManifoldType.tiny.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)

                    AgentScopeRow(agent: .cowork,
                                  inScope: store.policy.claudePolicy?.allowedSourceIDs.contains(source.sourceID) == true)
                    AgentScopeRow(agent: .codex,
                                  inScope: store.policy.codexPolicy?.allowedSourceIDs.contains(source.sourceID) == true)
                }
                .padding(Spacing.s4)
            } else {
                VStack(spacing: Spacing.s2) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Select a folder to see its agent scope.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.s8)
            }
        }
    }
}

private struct AgentScopeRow: View {
    let agent: TargetApp
    let inScope: Bool

    var body: some View {
        HStack(spacing: Spacing.s2) {
            GradientAvatar(agent: agent, size: .small)
            Text(agent == .codex ? "Codex" : "Claude")
                .font(ManifoldType.body)
            Spacer()
            Pill(text: inScope ? "in scope" : "not shared",
                 variant: inScope ? .defaultScope : .neutral)
        }
    }
}
