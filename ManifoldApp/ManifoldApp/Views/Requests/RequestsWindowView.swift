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
//   - Empty queue  → EmptyRequestsView takes the full pane. No inspector,
//     because there's nothing to pattern-match on yet.
//   - Active queue → two columns: pending + recent answers on the left,
//     pattern-detection inspector on the right (320w).

import SwiftUI
import ManifoldKit

struct RequestsWindowView: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        if store.pendingRequests.isEmpty {
            EmptyRequestsView()
        } else {
            activeLayout
        }
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
