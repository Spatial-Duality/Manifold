// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// SessionDiffView — live overlay showing Added / Removed / Inherited
// scope for the running session. Runs over the Folders matrix as a
// context layer per design/html/access.html view 3.

import SwiftUI
import ManifoldKit

struct SessionDiffView: View {
    @Environment(ManifoldStore.self) private var store
    @Binding private var searchText: String

    init(searchText: Binding<String> = .constant("")) {
        _searchText = searchText
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                if let session = store.activeSession {
                    SessionHeader(session: session)

                    DiffSection(
                        label: "Added in this session",
                        count: filtered(session.additions).count,
                        color: ManifoldPalette.active,
                        items: filtered(session.additions)
                    )

                    DiffSection(
                        label: "Removed in this session",
                        count: filtered(session.removals).count,
                        color: ManifoldPalette.attention,
                        items: filtered(session.removals)
                    )

                    InheritedSection(store: store, session: session, searchText: searchText)
                } else {
                    EmptyStateIllustration(
                        systemImage: "play.circle",
                        title: "No session running",
                        subtitle: "Start a session to layer scope changes on top of defaults — the diff shows up here, live.",
                        tint: ManifoldPalette.active,
                        style: .manifoldMark
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.s8)
                }
            }
            .padding(Spacing.s4)
        }
    }

    private func filtered(_ changes: [SessionScopeChange]) -> [SessionScopeChange] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return changes }
        return changes.filter { change in
            "\(change.displayName)\n\(change.path)"
                .localizedCaseInsensitiveContains(trimmed)
        }
    }
}

private struct SessionHeader: View {
    let session: SessionRecord
    var body: some View {
        HStack(spacing: Spacing.s2) {
            SessionChip(name: session.name,
                        remainingSeconds: session.remainingSeconds,
                        isTrackedEdit: session.isTrackedEdit)
            Spacer()
        }
    }
}

private struct DiffSection: View {
    let label: String
    let count: Int
    let color: Color
    let items: [SessionScopeChange]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label)
                    .font(ManifoldType.bodyMedium)
                Text("\(count)")
                    .font(ManifoldType.numericCaption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if items.isEmpty {
                Text("Nothing.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 18)
            } else {
                ForEach(items) { item in
                    HStack(spacing: Spacing.s2) {
                        FileTypeIcon(filename: item.displayName, isFolder: item.kind == .folder, size: 12)
                        Text(item.displayName).font(ManifoldType.body)
                        Spacer()
                        Text(item.path.shortenedPath)
                            .font(ManifoldType.mono)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.leading, 18)
                }
            }
        }
    }
}

private struct InheritedSection: View {
    let store: ManifoldStore
    let session: SessionRecord
    let searchText: String

    private var visibleSources: [SourceRecord] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.sources }
        return store.sources.filter { source in
            "\(source.displayName)\n\(source.originalRootPath)"
                .localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Circle().fill(ManifoldPalette.claude).frame(width: 8, height: 8)
                Text("Inherited from default").font(ManifoldType.bodyMedium)
                Text("\(visibleSources.count)")
                    .font(ManifoldType.numericCaption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if visibleSources.isEmpty {
                Text("No default sources.").font(ManifoldType.caption).foregroundStyle(.tertiary).padding(.leading, 18)
            } else {
                ForEach(visibleSources) { source in
                    let cowork = store.governance.policy(for: .cowork)?.allowedSourceIDs.contains(source.sourceID) ?? false
                    let codex = store.governance.policy(for: .codex)?.allowedSourceIDs.contains(source.sourceID) ?? false
                    HStack(spacing: Spacing.s2) {
                        FileTypeIcon(
                            filename: source.displayName,
                            isFolder: true,
                            size: 12,
                            tint: ManifoldPalette.sharingTint(coworkShared: cowork, codexShared: codex)
                        )
                        Text(source.displayName).font(ManifoldType.body)
                        Spacer()
                        Text(source.originalRootPath.shortenedPath)
                            .font(ManifoldType.mono)
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .padding(.leading, 18)
                    .opacity(0.85)
                }
            }
        }
    }
}
