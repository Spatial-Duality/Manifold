// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// KbdLabel — keyboard hint pill ("⌘K", "↩", etc.).
//
// Used in footer rows and inline next to menu items. Reads as a
// typographic affordance, not a button.

import SwiftUI

struct KbdLabel: View {
    let keys: String

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(ManifoldPalette.text3)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(ManifoldPalette.surface3.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
            )
            .accessibilityLabel("Keyboard shortcut: \(keys)")
    }
}

#Preview("Keyboard labels") {
    HStack(spacing: Spacing.s3) {
        KbdLabel("⌘O")
        KbdLabel("⌘,")
        KbdLabel("⌘N")
        KbdLabel("⌘⇧F")
        KbdLabel("↩")
        KbdLabel("⌥↩")
        KbdLabel("⌘↩")
    }
    .padding(Spacing.s6)
    .background(ManifoldPalette.bg)
}
