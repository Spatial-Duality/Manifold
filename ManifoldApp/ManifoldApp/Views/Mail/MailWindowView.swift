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

    enum Tab: String, Hashable, CaseIterable {
        case mailboxes, threads, session, history

        var label: String {
            switch self {
            case .mailboxes: return "Mailboxes"
            case .threads:   return "Threads"
            case .session:   return "Session"
            case .history:   return "History"
            }
        }

        var systemImage: String {
            switch self {
            case .mailboxes: return "tray.2"
            case .threads:   return "text.bubble"
            case .session:   return "play.fill"
            case .history:   return "clock.arrow.circlepath"
            }
        }
    }

    @State private var tab: Tab = .mailboxes

    var body: some View {
        VStack(spacing: 0) {
            MailTabBar(selection: $tab, hasSession: store.activeSession != nil)
            Divider()

            if store.emailAccounts.accounts.isEmpty {
                EmptyMailView()
            } else {
                switch tab {
                case .mailboxes: MailboxesMatrixView()
                case .threads:   ThreadsView()
                case .session:   MailSessionView()
                case .history:   MailHistoryView()
                }
            }
        }
        .task { await store.emailAccounts.loadAccounts() }
    }
}

private struct MailTabBar: View {
    @Binding var selection: MailWindowView.Tab
    let hasSession: Bool

    var body: some View {
        HStack(spacing: Spacing.s2) {
            ForEach(MailWindowView.Tab.allCases, id: \.self) { tab in
                let enabled = (tab != .session || hasSession)
                Button {
                    if enabled { selection = tab }
                } label: {
                    HStack(spacing: Spacing.s1) {
                        Image(systemName: tab.systemImage)
                            .font(.caption.weight(.medium))
                        Text(tab.label)
                            .font(ManifoldType.body)
                    }
                    .padding(.horizontal, Spacing.s3)
                    .padding(.vertical, Spacing.s1)
                    .background(Capsule().fill(selection == tab ? ManifoldPalette.claudeSoft : .clear))
                    .foregroundStyle(selection == tab ? ManifoldPalette.claude : ManifoldPalette.text2)
                    .opacity(enabled ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
    }
}
