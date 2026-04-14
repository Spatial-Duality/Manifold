// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// IntegratedToolbar — the Ledger window's native macOS toolbar.
//
// Matches design/html/chrome.css — a thin strip with filter chips where
// appropriate, a SessionChip in the trailing position when a session is
// live, and destination-specific actions. Phase 1 renders the shell; each
// phase's destination adds its own toolbar items.

import SwiftUI
import ManifoldKit

struct IntegratedToolbar: ToolbarContent {
    @Environment(ManifoldStore.self) private var store
    let destination: LedgerDestination

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let session = store.activeSession {
                SessionChip(
                    name: session.name,
                    remainingSeconds: session.remainingSeconds,
                    isTrackedEdit: session.isTrackedEdit
                )
                .accessibilityAddTraits(.isStaticText)
            } else {
                Button {
                    Task { try? await store.startSession(SessionDraft()) }
                } label: {
                    Label("Start session", systemImage: "play.fill")
                }
                .help("Start a new session (⌘N)")
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        ToolbarItemGroup(placement: .automatic) {
            Button {
                Task { await store.refreshAll(force: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh runtime state")
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}
