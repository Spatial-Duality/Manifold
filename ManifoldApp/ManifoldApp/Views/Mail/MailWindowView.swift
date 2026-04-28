// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// MailView — the mail surface.
//
// Active-Backup, not a Mail client. No reading pane, no compose, no reply.
// One surface: the dense review browser (account/mailbox rail + sortable
// message table + narrow metadata inspector with atomic allow / hide).
//
// History: prior versions split this into Review / Session / History tabs.
// The Session and History tabs were stubs that pointed at functionality
// living elsewhere (Activity tab handles cross-cutting history). Removing
// them per the redesign plan ships the Synology-style read-only archive
// view as the only surface and drops the dead tab bar that competed with
// the main app sidebar.
//
// MailSessionView.swift and MailHistoryView.swift remain in the tree as
// unreachable placeholders — the redesign plan's named-session lifecycle
// (Lane B-rest) will replace them with grant-scoped overlays that compose
// on top of this Review surface, not a separate tab.

import SwiftUI
import ManifoldKit

struct MailView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var hasLoadedMailAccounts = false

    var body: some View {
        VStack(spacing: 0) {
            if !hasLoadedMailAccounts {
                ProgressView("Loading mail backup…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ManifoldPalette.surface)
            } else if store.mailAccounts.accounts.isEmpty {
                EmptyMailView()
            } else {
                MailReviewView()
            }
        }
        .accessibilityElement(children: .contain)
        .environment(store.mailAccounts)
        .environment(store.mailReview)
        .task {
            await store.mailAccounts.loadAccounts()
            await store.mailReview.prepare(force: true)
            hasLoadedMailAccounts = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ledger.surface.mail")
    }
}
