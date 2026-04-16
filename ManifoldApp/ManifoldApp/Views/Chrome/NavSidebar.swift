// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// NavSidebar — the 5-item Ledger sidebar.
//
// Uses system-native macOS sidebar patterns so the window chrome (traffic
// lights, sidebar toggle, window title) lays out correctly on every
// destination.
//
// Title ownership (the thing that bit us twice):
//
//   The macOS `NavigationSplitView` title bar is owned by the DETAIL
//   column, not the sidebar. If the sidebar ALSO sets `.navigationTitle`,
//   the two fight and the sidebar's `List` starts drawing from Y=0 — the
//   first rows render behind the traffic lights. Symptom: "Activity,
//   Scope, Mail disappear; only Requests and Rules are visible."
//
//   Fix: the sidebar sets NO navigationTitle. The detail sets
//   `.navigationTitle(destination.title)` exclusively. The sidebar just
//   renders its rows.
//
// Conventions followed (per swiftui-pro references):
//   - Flat `List { ForEach … }` instead of a single-`Section` wrapper.
//     A one-section sidebar renders as a blank column on macOS 26.
//   - `Label(title, systemImage:)` for row content (references/design.md).
//   - `.badge(Int)` for pending counts — the system handles position,
//     type scaling, and accessibility ("N unread"-style reads).
//   - Selection foreground styling handled by the system; we don't
//     override it with per-row tints.
//   - `.navigationSplitViewColumnWidth` applied here so the sidebar
//     carries its own width contract and can't be squeezed to nothing.

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
        // NO .navigationTitle here — detail owns the window title. See the
        // title-ownership note above before changing this.
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
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
