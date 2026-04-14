// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// EmptyRequestsView — the happy path. Calm, not celebratory.

import SwiftUI

struct EmptyRequestsView: View {
    var body: some View {
        VStack(spacing: Spacing.s6) {
            EmptyStateIllustration(
                systemImage: "checkmark.seal",
                title: "Nothing is waiting on you",
                subtitle: "When an agent asks for access it will land here. You answer in a ladder — deny, once, for this session, or add to default. No modals.",
                tint: ManifoldPalette.active
            )

            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack(spacing: Spacing.s2) {
                    KbdLabel("↩")
                    Text("Not this time (focused default)").font(ManifoldType.caption)
                }
                HStack(spacing: Spacing.s2) {
                    KbdLabel("⇧↩")
                    Text("Allow once").font(ManifoldType.caption)
                }
                HStack(spacing: Spacing.s2) {
                    KbdLabel("⌥↩")
                    Text("Allow for this session").font(ManifoldType.caption)
                }
                HStack(spacing: Spacing.s2) {
                    KbdLabel("⌘↩")
                    Text("Add to default scope").font(ManifoldType.caption)
                }
            }
            .padding(Spacing.s4)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r4)
                    .fill(ManifoldPalette.surface3.opacity(0.5))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.s8)
        .background(ManifoldPalette.bg)
    }
}
