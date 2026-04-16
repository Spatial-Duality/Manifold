// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// NavSidebar — the 5-item Ledger sidebar.
//
// Uses system-native macOS sidebar patterns so the window chrome (traffic
// lights, sidebar toggle, window title) lays out correctly on every
// screen. Previous custom Section { ... } header: { ... } didn't reserve
// space for the title bar, which caused the top items to render behind
// the traffic lights.
//
// Conventions followed (per swiftui-pro references):
//   - Flat `List { ForEach … }` instead of a single-`Section` wrapper.
//     A one-section sidebar renders as a blank column on macOS 26 when
//     the detail also sets `.navigationTitle`, because the section
//     header and nav-title machinery can collide during relayout. A
//     flat list always renders.
//   - Label(title, systemImage:) for row content (references/design.md).
//   - .badge(Int) for pending counts — the system handles position, type
//     scaling, and accessibility ("N unread"-style reads).
//   - Selection foreground styling handled by the system; we don't
//     override it with per-row tints.
//   - .navigationSplitViewColumnWidth applied here, not at the split-view
//     level, so the sidebar carries its own width contract.

import SwiftUI
import ManifoldKit

struct NavSidebar: View {
    @Binding var selection: LedgerDestination
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        // Live `SessionChip` intentionally lives only in `StatusBar` —
        // one ambient home for runtime state (plan §6.3).
        List(selection: $selection) {
            ForEach(LedgerDestination.allCases) { destination in
                NavRow(destination: destination, pendingCount: badgeCount(for: destination))
                    .tag(destination)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Manifold")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
    }

    private func badgeCount(for destination: LedgerDestination) -> Int {
        destination == .requests ? store.pendingRequests.count : 0
    }
}

/// A single destination row. Rendered as a system `Label` with a native
/// `.badge()` count — the system picks the right foreground color for
/// selection, Dynamic Type, and high-contrast modes.
private struct NavRow: View {
    let destination: LedgerDestination
    let pendingCount: Int

    var body: some View {
        Label(destination.title, systemImage: destination.systemImage)
            .badge(pendingCount)
            .accessibilityLabel(destination.title)
            .accessibilityHint(destination.emptySubtitle)
    }
}
