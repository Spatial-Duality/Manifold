// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// LedgerSidebar — the Ledger sidebar.
//
// Four destinations: Work, Access, Mail, Rules. Pending approvals badge
// on Work; a single "+ New Session" button at the bottom that drops the
// user into Work with a fresh prepared session.
//
// Title ownership note (kept from the previous version because it bit
// us twice): the sidebar sets NO navigationTitle. The detail column
// owns `.navigationTitle(destination.title)`. If both set titles, the
// sidebar `List` starts drawing from Y=0 and rows land behind the
// traffic lights.

import SwiftUI
import ManifoldKit

struct LedgerSidebar: View {
    @Binding var selection: LedgerDestination
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        List(selection: $selection) {
            ForEach(LedgerDestination.allCases) { destination in
                NavRow(destination: destination, pendingCount: badgeText(for: destination))
                    .tag(destination)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("ledger.sidebar.\(destination.id)")
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SessionFooter(selection: $selection)
        }
        .accessibilityIdentifier("ledger.sidebar")
    }

    /// Pending approvals are now a Work concern. Other destinations carry
    /// no badge.
    private func badgeText(for destination: LedgerDestination) -> Text? {
        guard destination == .work, store.pendingRequests.count > 0 else { return nil }
        return Text(store.pendingRequests.count > 99 ? "99+" : "\(store.pendingRequests.count)")
    }
}

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

// MARK: - SessionFooter
//
// One row, ~28pt, single primary action: + New Session. Tapping it
// opens the Work surface and starts a fresh prepared session built on
// the user's default scope.
//
// Pattern: Mail's "+ New Mailbox", Notes' "+ New Folder". Pure macOS
// 26 (Tahoe). No surface tint, no glass plate, no "more" menu.

private struct SessionFooter: View {
    @Binding var selection: LedgerDestination
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            Button {
                selection = .work
                if store.sessionWorkbench.preload == nil {
                    store.beginSessionPreload(
                        agent: store.defaultSessionAgent,
                        baseMode: .buildOnDefault
                    )
                }
            } label: {
                Label("New Session", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
            }
            .glassProminentButton()
            .controlSize(.regular)
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("New Session (⌘⇧N)")
            .accessibilityIdentifier("ledger.sidebar.newSession")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityIdentifier("ledger.sidebar.footer")
    }
}
