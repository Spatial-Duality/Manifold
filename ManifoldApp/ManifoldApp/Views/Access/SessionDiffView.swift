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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                if let session = store.activeSession {
                    SessionHeader(session: session)

                    DiffSection(
                        label: "Added in this session",
                        count: session.additions.count,
                        color: ManifoldPalette.active,
                        items: session.additions
                    )

                    DiffSection(
                        label: "Removed in this session",
                        count: session.removals.count,
                        color: ManifoldPalette.attention,
                        items: session.removals
                    )

                    InheritedSection(store: store, session: session)
                } else {
                    EmptyStateIllustration(
                        systemImage: "play.circle",
                        title: "No session running",
                        subtitle: "Start a session to layer scope changes on top of defaults — the diff shows up here, live."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.s8)
                }
            }
            .padding(Spacing.s4)
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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Circle().fill(ManifoldPalette.claude).frame(width: 8, height: 8)
                Text("Inherited from default").font(ManifoldType.bodyMedium)
                Text("\(store.sources.count)")
                    .font(ManifoldType.numericCaption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if store.sources.isEmpty {
                Text("No default sources.").font(ManifoldType.caption).foregroundStyle(.tertiary).padding(.leading, 18)
            } else {
                ForEach(store.sources) { source in
                    HStack(spacing: Spacing.s2) {
                        FileTypeIcon(filename: source.displayName, isFolder: true, size: 12)
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
