// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// LedgerToolbar — the Ledger window's native macOS toolbar.
//
// The live `SessionChip` now lives only in `StatusBar` (Principle 10 —
// one ambient home for runtime state). The toolbar keeps "Start
// session" as the primary action when no session is live, and a
// "Finish session" action when one is. An always-populated toolbar
// keeps macOS from collapsing the title-bar area into an empty strip
// (which looks broken alongside a collapsed sidebar).

import SwiftUI
import ManifoldKit

struct LedgerToolbar: ToolbarContent {
    @Environment(ManifoldStore.self) private var store
    @Environment(CommandPaletteModel.self) private var commandPalette
    let destination: LedgerDestination

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if store.activeSession != nil {
                Button(role: .destructive) {
                    Task { await store.endSession() }
                } label: {
                    Label("Finish session", systemImage: "stop.fill")
                }
                .help("Finish the active session")
            } else {
                if let command = commandPalette.command(.protectNextSession, for: store) {
                    Button {
                        Task { await command.action(store) }
                    } label: {
                        Label(command.title, systemImage: command.icon)
                    }
                    .help("\(command.title) (\(command.shortcutLabel ?? ""))")
                    .keyboardShortcut(command.shortcut!.key, modifiers: command.shortcut!.modifiers)
                }
            }
        }

        ToolbarItemGroup(placement: .automatic) {
            if let command = commandPalette.command(.refreshRuntime, for: store) {
                Button {
                    Task { await command.action(store) }
                } label: {
                    Label(command.title, systemImage: command.icon)
                }
                .help(command.title)
                .keyboardShortcut(command.shortcut!.key, modifiers: command.shortcut!.modifiers)
            }
        }
    }
}
