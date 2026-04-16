// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// IntegratedToolbar — the Ledger window's native macOS toolbar.
//
// The live `SessionChip` now lives only in `StatusBar` (Principle 10 —
// one ambient home for runtime state). The toolbar keeps "Start
// session" as the primary action when no session is live, and drops
// the Refresh button entirely: the runtime pushes state, so a Refresh
// affordance was an admission that live state wasn't trusted.

import SwiftUI
import ManifoldKit

struct IntegratedToolbar: ToolbarContent {
    @Environment(ManifoldStore.self) private var store
    let destination: LedgerDestination

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if store.activeSession == nil {
                Button {
                    Task { try? await store.startSession(SessionDraft()) }
                } label: {
                    Label("Start session", systemImage: "play.fill")
                }
                .help("Start a new session (⌘N)")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
