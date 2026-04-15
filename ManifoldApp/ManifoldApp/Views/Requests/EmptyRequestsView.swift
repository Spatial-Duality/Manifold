// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// EmptyRequestsView — the happy path.
//
// Uses ContentUnavailableView (references/design.md) for the illustration +
// title + description. A secondary shortcut reference card sits below it
// so the user can see the ladder's keyboard layout without waiting for a
// real request to arrive.

import SwiftUI

struct EmptyRequestsView: View {
    var body: some View {
        VStack(spacing: Spacing.s6) {
            ContentUnavailableView(
                "Nothing is waiting on you",
                systemImage: "checkmark.seal",
                description: Text("When an agent asks for access it will land here. You answer in a ladder — deny, once, for this session, or add to default. No modals.")
            )

            ShortcutsCard()
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.s8)
    }
}

/// Keyboard-shortcut reference for the commit ladder. Kept as a secondary
/// affordance so the empty state doubles as a quick lookup.
private struct ShortcutsCard: View {
    private struct Row: Identifiable {
        let id = UUID()
        let key: String
        let label: String
    }

    private let rows: [Row] = [
        .init(key: "↩",   label: "Not this time (focused default)"),
        .init(key: "⇧↩",  label: "Allow once"),
        .init(key: "⌥↩",  label: "Allow for this session"),
        .init(key: "⌘↩",  label: "Add to default scope"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("Commit ladder")
                .font(ManifoldType.tiny.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            ForEach(rows) { row in
                LabeledContent {
                    Text(row.label)
                        .font(ManifoldType.caption)
                        .foregroundStyle(ManifoldPalette.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    KbdLabel(row.key)
                        .frame(width: 36, alignment: .leading)
                }
            }
        }
        .padding(Spacing.s4)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
    }
}

#Preview("Empty Requests") {
    EmptyRequestsView()
        .frame(width: 720, height: 520)
}
