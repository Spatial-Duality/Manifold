// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// CommitLadder — the approval row used on queue cards.
//
// Deny-focused by default (Principle 3). "Not this time" is prominent
// and carries `.defaultAction`; the other actions are borderless bordered.
// The session button only appears for request kinds that truly support it.
//
// Keyboard layout:
//   ↩    → Not this time
//   ⇧↩   → Once
//   ⌥↩   → For this session (when supported)
//   ⌘↩   → Add to default

import SwiftUI
import ManifoldKit

struct CommitLadder: View {
    let agent: TargetApp
    let showsSessionScope: Bool

    var onNotThisTime: () -> Void = {}
    var onOnce:        () -> Void = {}
    var onSession:     () -> Void = {}
    var onDefault:     () -> Void = {}

    var body: some View {
        HStack(spacing: Spacing.s1) {
            Button("Not this time", action: onNotThisTime)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(ManifoldPalette.attention)
                .accessibilityIdentifier("requests.action.notThisTime")

            Button("Once", action: onOnce)
                .keyboardShortcut(.return, modifiers: .shift)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("requests.action.once")

            if showsSessionScope {
                Button("For this session", action: onSession)
                    .keyboardShortcut(.return, modifiers: .option)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(ManifoldPalette.active)
                    .accessibilityIdentifier("requests.action.session")
            }

            Button("Add to default", action: onDefault)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(ManifoldPalette.agent(agent))
                .accessibilityIdentifier("requests.action.default")
        }
    }
}

#Preview("Commit ladder — session live") {
    CommitLadder(agent: .cowork, showsSessionScope: true)
        .padding(Spacing.s6)
        .background(ManifoldPalette.bg)
}

#Preview("Commit ladder — no session") {
    CommitLadder(agent: .codex, showsSessionScope: false)
        .padding(Spacing.s6)
        .background(ManifoldPalette.bg)
}
