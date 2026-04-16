// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RequestsWindowView — the approval queue surface.
//
// Replaces the old modal approval sheet (Stage 2 §2, Principle 2).
// Requests accumulate here silently; the user answers when they return.
// "Not this time" is the focused default (Principle 3).
//
// Layout rules:
//   - Top bar     → header strip with status sentence + pending count.
//     Gives the destination visual chrome consistent with Access, Rules
//     and Activity so the user always has a "you are here" anchor when
//     the canvas happens to be empty (prevents the "blank navbar" feeling
//     reported in testing).
//   - Empty queue  → EmptyRequestsView takes the full pane below the bar.
//   - Active queue → two columns: pending + recent answers on the left,
//     pattern-detection inspector on the right (320w).

import SwiftUI
import ManifoldKit

struct RequestsWindowView: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if store.pendingRequests.isEmpty {
                EmptyRequestsView()
            } else {
                activeLayout
            }
        }
    }

    /// Top bar mirrors `ModeBar` / `RulesWindowView.toolbar` — a short
    /// `.regularMaterial` strip so every destination's detail pane opens
    /// with a consistent visual header instead of a full-frame illustration.
    private var topBar: some View {
        let count = store.pendingRequests.count
        let isEmpty = count == 0
        return HStack(spacing: Spacing.s2) {
            Image(systemName: isEmpty ? "checkmark.seal" : "hand.raised.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isEmpty ? ManifoldPalette.active : ManifoldPalette.attention)
            Text(isEmpty ? "All caught up" : "\(count) waiting on you")
                .font(ManifoldType.bodyMedium)
            Text(isEmpty
                 ? "Agents will land here when they ask for access."
                 : "Answer in a ladder — deny, once, session, default.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.regularMaterial)
    }

    private var activeLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                PendingQueueView()
                    .frame(maxHeight: .infinity)
                Divider()
                RecentAnswersView()
                    .frame(maxHeight: 260)
            }
            .frame(maxWidth: .infinity)

            Divider()

            PatternDetectionInspector()
                .frame(width: 320)
                .background(ManifoldPalette.surface2)
        }
    }
}
