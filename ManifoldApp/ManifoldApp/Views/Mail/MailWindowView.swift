// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// MailWindowView — the mail surface.
//
// Per Stage 8: this is Active-Backup, not a Mail client. No reading pane,
// no compose, no reply. The surface answers: which mailboxes does an
// agent see, at what sensitivity, and which threads were touched in
// which session.

import SwiftUI
import ManifoldKit

struct MailWindowView: View {
    @Environment(ManifoldStore.self) private var store

    /// Three modes. `.session` (disabled-when-no-session) was a posture
    /// leak per plan §2.5.1 — dropped; session activity is visible via
    /// the Activity ledger filtered on the live session.
    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case mailboxes, threads, history

        var id: String { rawValue }

        var label: String {
            switch self {
            case .mailboxes: return "Mailboxes"
            case .threads:   return "Threads"
            case .history:   return "History"
            }
        }
    }

    @State private var tab: Tab = .mailboxes

    var body: some View {
        VStack(spacing: 0) {
            MailTabBar(selection: $tab)
            Divider()

            if store.emailAccounts.accounts.isEmpty {
                EmptyMailView()
            } else {
                switch tab {
                case .mailboxes: MailboxesMatrixView()
                case .threads:   ThreadsView()
                case .history:   MailHistoryView()
                }
            }
        }
        .task { await store.emailAccounts.loadAccounts() }
    }
}

/// Native segmented picker, replaces the previous custom capsule bar
/// per APPLE-DESIGN-EXCELLENCE-GUIDE §3.
private struct MailTabBar: View {
    @Binding var selection: MailWindowView.Tab

    var body: some View {
        HStack {
            Picker("View", selection: $selection) {
                ForEach(MailWindowView.Tab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.regularMaterial)
    }
}
