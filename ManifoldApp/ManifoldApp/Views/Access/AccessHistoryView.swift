// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AccessHistoryView — past sessions grouped by day with a Resume button
// per row. Resume computes drift and presents the drift preview sheet
// (Phase 7 wires the sheet itself; Phase 3 renders the list).

import SwiftUI
import ManifoldKit

struct AccessHistoryView: View {
    @Environment(ManifoldStore.self) private var store

    private var entries: [SessionHistoryEntry] {
        store.recentSessionEntries
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.s2) {
                if entries.isEmpty {
                    EmptyStateIllustration(
                        systemImage: "clock.arrow.circlepath",
                        title: "No past sessions yet",
                        subtitle: "When you finish a session it lands here with the scope it used and the evidence it produced. You can resume any of them."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.s8)
                } else {
                    ForEach(entries) { entry in
                        SessionHistoryRow(entry: entry)
                    }
                }
            }
            .padding(Spacing.s4)
        }
    }
}

private struct SessionHistoryRow: View {
    @Environment(ManifoldStore.self) private var store
    let entry: SessionHistoryEntry

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.title3)
                .foregroundStyle(ManifoldPalette.active)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(ManifoldType.bodyMedium)
                Text("\(entry.displayLastRun) · \(entry.displayDuration) · \(entry.eventCount) events")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Resume") {
                Task { try? await store.reloadSession(historyID: entry.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(Spacing.s3)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }
}
