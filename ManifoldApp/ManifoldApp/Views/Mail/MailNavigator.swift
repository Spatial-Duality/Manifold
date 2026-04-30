// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

private enum MailNavigatorSelection: Hashable {
    case account(String)
    case mailbox(accountID: String, name: String)
}

struct MailNavigator: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        List(selection: selection) {
            accountsSection
            mailboxesSection
            quickFiltersSection
        }
        .listStyle(.sidebar)
        .task {
            if store.mailAccounts.accounts.isEmpty {
                await store.mailAccounts.loadAccounts()
                await store.mailReview.prepare(force: false)
            }
        }
        .accessibilityIdentifier("mail.sidebar")
    }

    private var selection: Binding<MailNavigatorSelection?> {
        Binding(
            get: {
                if let accountID = store.mailReview.selectedAccountID,
                   let mailbox = store.mailReview.selectedMailboxName {
                    return .mailbox(accountID: accountID, name: mailbox)
                }
                if let accountID = store.mailReview.selectedAccountID {
                    return .account(accountID)
                }
                return nil
            },
            set: { newSelection in
                guard let newSelection else { return }
                switch newSelection {
                case .account(let accountID):
                    Task { await store.mailReview.selectAccount(accountID) }
                case .mailbox(_, let name):
                    Task { await store.mailReview.selectMailbox(name) }
                }
            }
        )
    }

    @ViewBuilder
    private var accountsSection: some View {
        Section("Accounts") {
            if store.mailAccounts.accounts.isEmpty {
                Text("No accounts")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.mailAccounts.accounts) { account in
                    MailSidebarLabel(
                        title: account.displayName,
                        subtitle: account.username ?? account.provider.displayName,
                        systemImage: account.provider.systemImage
                    )
                    .tag(MailNavigatorSelection.account(account.accountID))
                    .accessibilityIdentifier("mail.account.\(account.accountID)")
                }
            }
        }
    }

    @ViewBuilder
    private var mailboxesSection: some View {
        Section("Mailboxes") {
            if let accountID = store.mailReview.selectedAccountID {
                let mailboxes = store.mailReview.mailboxes(for: accountID).filter(\.isSelectable)
                if mailboxes.isEmpty {
                    Text("No synced mailboxes")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(mailboxes) { mailbox in
                        MailSidebarLabel(
                            title: mailbox.mailboxName,
                            subtitle: mailbox.folderType.rawValue.capitalized,
                            systemImage: mailbox.folderType.systemImage
                        )
                        .tag(MailNavigatorSelection.mailbox(accountID: accountID, name: mailbox.mailboxName))
                        .accessibilityIdentifier("mail.mailbox.\(accountID).\(mailbox.mailboxName.replacingOccurrences(of: " ", with: "-"))")
                    }
                }
            } else {
                Text("Pick an account first")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickFiltersSection: some View {
        Section("Quick Filters") {
            ForEach(QuickFilter.defaultVisible) { filter in
                Button {
                    Task { await store.mailReview.setQuickFilter(filter) }
                } label: {
                    HStack(spacing: Spacing.s2) {
                        MailSidebarLabel(
                            title: filter.displayName,
                            subtitle: "Filter current mailbox",
                            systemImage: filter.systemImage
                        )
                        Spacer(minLength: 0)
                        if store.mailReview.activeQuickFilter == filter {
                            Image(systemName: "checkmark")
                                .font(ManifoldType.captionMedium)
                                .foregroundStyle(ManifoldPalette.selection)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mail.quickFilter.\(filter.rawValue)")
            }
        }
    }
}

private struct MailSidebarLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
