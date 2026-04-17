// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RequestsView — the approval queue surface.
//
// Replaces the old modal approval sheet (Stage 2 §2, Principle 2).
// Requests accumulate here silently; the user answers when they return.
// "Not this time" is the focused default (Principle 3).
//
// Layout rules:
//   - Empty queue  → EmptyRequestsView takes the full pane.
//   - Active queue → a single dense queue surface. We avoid dedicating
//     permanent primary space to placeholder analytics or activity panes.

import SwiftUI
import ManifoldKit

struct RequestsView: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        if store.pendingRequests.isEmpty {
            EmptyRequestsView()
                .accessibilityIdentifier("ledger.surface.requests")
        } else {
            activeLayout
                .accessibilityIdentifier("ledger.surface.requests")
        }
    }

    private var activeLayout: some View {
        VStack(spacing: 0) {
            RequestsQueueView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            RequestsKeyboardHint()
        }
    }
}

private struct RequestsKeyboardHint: View {
    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: "keyboard")
                .foregroundStyle(ManifoldPalette.selection)
            Text("Answer requests with Return, Option-Return, or Command-Return.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .background(.regularMaterial)
    }
}
