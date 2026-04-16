// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RootWindowContent — wrapper that presents either the FirstRunFlow or
// the LedgerWindowView, plus sheet presentations for session start and
// reload drift.
//
// Keeping this separate from ManifoldApp lets the @State sheet flags
// live inside the window (SwiftUI-idiomatic) instead of polluting the
// App type with view state.

import SwiftUI
import ManifoldKit

extension Notification.Name {
    static let manifoldShowSessionStartSheet = Notification.Name("manifold.showSessionStartSheet")
    /// Posted by the menu bar panel when the user taps "Answer in Ledger".
    /// LedgerWindowView listens and routes to the Requests destination.
    static let manifoldOpenRequests = Notification.Name("manifold.openRequests")
    /// Posted by the menu bar panel when the user taps an agent row.
    /// Today the receiver only switches the Ledger destination to `.access`;
    /// the `object` payload (`TargetApp`) is reserved for the Priority-2
    /// agent-centric Scope canvas, which will consume it to pre-focus the
    /// matching agent column. Posting it now keeps the call sites
    /// forward-compatible; a receiver-side TODO marks the gap.
    static let manifoldOpenScope = Notification.Name("manifold.openScope")
}

struct RootWindowContent: View {
    @Environment(ManifoldStore.self) private var store
    @State private var showStartSession = false
    @State private var reloadEntry: SessionHistoryEntry?

    private var showFirstRun: Bool {
        !store.hasCompletedOnboarding && store.sources.isEmpty
    }

    var body: some View {
        Group {
            if showFirstRun {
                FirstRunFlow()
            } else {
                LedgerWindowView()
            }
        }
        .sheet(isPresented: $showStartSession) {
            SessionStartSheet()
        }
        .sheet(item: $reloadEntry) { entry in
            ReloadDriftSheet(historyEntry: entry)
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldShowSessionStartSheet)) { _ in
            showStartSession = true
        }
    }
}
