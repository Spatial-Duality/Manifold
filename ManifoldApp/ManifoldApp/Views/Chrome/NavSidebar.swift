// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// LedgerSidebar — the Ledger sidebar.
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
//   - `.badge(Text?)` for pending counts — the system handles position,
//     type scaling, and accessibility ("N unread"-style reads). We use
//     Text? instead of Int so we can render "99+" cleanly.
//   - Selection foreground styling handled by the system; we don't
//     override it with per-row tints.
//   - `.navigationSplitViewColumnWidth` applied here so the sidebar
//     carries its own width contract and can't be squeezed to nothing.
//   - Live `SessionChip` intentionally lives only in `StatusBar` —
//     one ambient home for runtime state (plan §6.3).

import SwiftUI
import ManifoldKit

struct LedgerSidebar: View {
    @Binding var selection: LedgerDestination
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(LedgerDestination.allCases) { destination in
                    NavRow(destination: destination, pendingCount: badgeText(for: destination))
                        .tag(destination)
                }
            }
            .listStyle(.sidebar)
            // NO .navigationTitle here — detail owns the window title. See the
            // title-ownership note above before changing this.
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)

            Divider()
            SidebarFooterStatus()
        }
        .accessibilityIdentifier("ledger.sidebar")
    }

    private func badgeText(for destination: LedgerDestination) -> Text? {
        guard destination == .requests, store.pendingRequests.count > 0 else { return nil }
        return Text(store.pendingRequests.count > 99 ? "99+" : "\(store.pendingRequests.count)")
    }
}

/// A single destination row. Rendered as a system `Label` with a native
/// `.badge()` count — the system picks the right foreground color for
/// selection, Dynamic Type, and high-contrast modes.
private struct NavRow: View {
    let destination: LedgerDestination
    let pendingCount: Text?

    var body: some View {
        Label(destination.title, systemImage: destination.systemImage)
            .badge(pendingCount)
            .accessibilityLabel(destination.title)
            .accessibilityHint(destination.emptySubtitle)
            .accessibilityIdentifier("ledger.sidebar.\(destination.id)")
    }
}

private struct SidebarFooterStatus: View {
    @Environment(ManifoldStore.self) private var store

    private var status: (AgentStatusDot.Status, String) {
        if let error = store.runtimeLaunchError ?? store.lastError {
            return (.denied, error)
        }
        if !store.isRuntimeConnected {
            return (.offline, "Runtime offline")
        }
        if let session = store.activeSession {
            return (.active, session.isTrackedEdit ? "Tracked session live" : "Session live")
        }
        let agents = [store.isClaudeConnected ? "Claude" : nil, store.isCodexConnected ? "Codex" : nil]
            .compactMap { $0 }
        if agents.isEmpty {
            return (.paused, "No agents connected")
        }
        return (.active, agents.joined(separator: " · "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            HStack(spacing: Spacing.s2) {
                AgentStatusDot(status: status.0, size: 7)
                Text(status.1)
                    .font(ManifoldType.captionMedium)
                    .foregroundStyle(ManifoldPalette.text2)
                    .lineLimit(1)
                Spacer()
            }

            if !store.isRuntimeConnected {
                Button("Reconnect") {
                    Task {
                        store.registerAgent()
                        await store.refreshAll(force: true)
                    }
                }
                .buttonStyle(.borderless)
                .font(ManifoldType.caption)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Runtime status. \(status.1)")
        .accessibilityIdentifier("ledger.sidebar.status")
    }
}
