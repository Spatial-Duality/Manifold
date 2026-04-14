// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RequestsWindowView — the approval queue surface.
//
// Replaces the old modal approval sheet (Stage 2 §2, Principle 2).
// Requests accumulate here silently; the user answers when they return.
// "Not this time" is the focused default (Principle 3).

import SwiftUI
import ManifoldKit

struct RequestsWindowView: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if store.pendingRequests.isEmpty {
                    EmptyRequestsView()
                } else {
                    PendingQueueView()
                }

                if !store.pendingRequests.isEmpty {
                    Divider()
                    RecentAnswersView()
                        .frame(maxHeight: 260)
                }
            }

            Divider()

            PatternDetectionInspector()
                .frame(width: 320)
                .background(ManifoldPalette.surface2)
        }
    }
}
