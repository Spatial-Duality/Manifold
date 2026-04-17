// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AccessHistoryView — past sessions grouped by day with a reload-preview
// action per row. The row opens a read-only drift preview sheet.

import SwiftUI
import ManifoldKit

struct AccessHistoryView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var previewEntry: SessionHistoryEntry?

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
                        subtitle: "When you finish a session it lands here with the scope it used and the evidence it produced. Reload previews will appear here as that flow hardens."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.s8)
                } else {
                    ForEach(entries) { entry in
                        SessionHistoryRow(entry: entry) {
                            previewEntry = entry
                        }
                    }
                }
            }
            .padding(Spacing.s4)
        }
        .sheet(item: $previewEntry) { entry in
            ReloadDriftSheet(historyEntry: entry)
        }
    }
}

private struct SessionHistoryRow: View {
    let entry: SessionHistoryEntry
    let onPreview: () -> Void

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
            Button("Reload Preview") {
                onPreview()
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
