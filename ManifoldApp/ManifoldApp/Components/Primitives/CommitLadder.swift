// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// CommitLadder — the 4-button approval row used on approval cards.
//
// Deny-focused by default (Principle 3). "Not this time" is prominent
// and carries `.defaultAction`; the other three are borderless bordered.
// The session button is hidden when no session is live, per Cooper —
// no dead affordances.
//
// Keyboard layout:
//   ↩    → Not this time
//   ⇧↩   → Once
//   ⌥↩   → For this session
//   ⌘↩   → Add to default

import SwiftUI
import ManifoldKit

struct CommitLadder: View {
    let agent: TargetApp
    let sessionIsLive: Bool

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

            Button("Once", action: onOnce)
                .keyboardShortcut(.return, modifiers: .shift)
                .buttonStyle(.bordered)
                .controlSize(.small)

            if sessionIsLive {
                Button("For this session", action: onSession)
                    .keyboardShortcut(.return, modifiers: .option)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(ManifoldPalette.active)
            }

            Button("Add to default", action: onDefault)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(ManifoldPalette.agent(agent))
        }
    }
}

#Preview("Commit ladder — session live") {
    CommitLadder(agent: .cowork, sessionIsLive: true)
        .padding(Spacing.s6)
        .background(ManifoldPalette.bg)
}

#Preview("Commit ladder — no session") {
    CommitLadder(agent: .codex, sessionIsLive: false)
        .padding(Spacing.s6)
        .background(ManifoldPalette.bg)
}
