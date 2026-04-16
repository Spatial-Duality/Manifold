// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// IntegratedToolbar — the Ledger window's native macOS toolbar.
//
// The live `SessionChip` now lives only in `StatusBar` (Principle 10 —
// one ambient home for runtime state). The toolbar keeps "Start
// session" as the primary action when no session is live, and a
// "Finish session" action when one is. An always-populated toolbar
// keeps macOS from collapsing the title-bar area into an empty strip
// (which looks broken alongside a collapsed sidebar).

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
            } else {
                Button(role: .destructive) {
                    Task { await store.endSession() }
                } label: {
                    Label("Finish session", systemImage: "stop.fill")
                }
                .help("Finish the active session")
            }
        }
    }
}
