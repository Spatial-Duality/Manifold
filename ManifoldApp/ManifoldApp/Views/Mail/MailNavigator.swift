// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

private enum MailNavigatorSelection: Hashable {
    case section(MailSection)
    case account(String)
    case mailbox(accountID: String, name: String)
}

struct MailNavigator: View {
    @Environment(ManifoldStore.self) private var store
    @Binding var section: MailSection

    var body: some View {
        List(selection: selection) {
            sectionsSection
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
                if section == .history {
                    return .section(.history)
                }
                if let accountID = store.mailReview.selectedAccountID,
                   let mailbox = store.mailReview.selectedMailboxName {
                    return .mailbox(accountID: accountID, name: mailbox)
                }
                if let accountID = store.mailReview.selectedAccountID {
                    return .account(accountID)
                }
                return .section(.review)
            },
            set: { newSelection in
                guard let newSelection else { return }
                switch newSelection {
                case .section(let newSection):
                    section = newSection
                case .account(let accountID):
                    section = .review
                    Task { await store.mailReview.selectAccount(accountID) }
                case .mailbox(_, let name):
                    section = .review
                    Task { await store.mailReview.selectMailbox(name) }
                }
            }
        )
    }

    private var sectionsSection: some View {
        Section("Mail") {
            ForEach(MailSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    MailSidebarLabel(
                        title: item.title,
                        subtitle: item.subtitle,
                        systemImage: item.systemImage
                    )
                }
                .buttonStyle(.plain)
                .tag(MailNavigatorSelection.section(item))
                .accessibilityIdentifier("mail.section.\(item.rawValue)")
            }
        }
    }

    @ViewBuilder
    private var accountsSection: some View {
        Section("Accounts") {
            if store.mailAccounts.accounts.isEmpty {
                Text("No accounts")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.mailAccounts.accounts) { account in
                    let progress = store.mailAccounts.progress(for: account)
                    MailSidebarLabel(
                        title: account.displayName,
                        subtitle: MailSyncProgressPresentation.accountSubtitle(
                            progress: progress,
                            account: account
                        ),
                        systemImage: account.provider.systemImage,
                        isActive: progress?.stage.isActive ?? false,
                        statusSystemImage: progress.map {
                            MailSyncProgressPresentation.stageSymbol($0.stage)
                        }
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
            if let accountID = store.mailReview.selectedAccountID,
               let account = store.mailAccounts.accounts.first(where: { $0.accountID == accountID }) {
                let mailboxes = store.mailReview.sidebarMailboxes(for: account)
                let progress = store.mailAccounts.progress(for: accountID)
                if mailboxes.isEmpty {
                    Text("No synced mailboxes")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(mailboxes) { mailbox in
                        let syncState = store.mailAccounts.syncStates[accountID]?.first {
                            $0.mailboxName == mailbox.mailboxName
                        }
                        MailSidebarLabel(
                            title: mailbox.displayName,
                            subtitle: MailSyncProgressPresentation.mailboxSubtitle(
                                progress: progress,
                                mailboxName: mailbox.mailboxName,
                                syncState: syncState
                            ),
                            systemImage: mailbox.systemImage,
                            trailingText: MailSyncProgressPresentation.mailboxCount(
                                progress: progress,
                                mailboxName: mailbox.mailboxName
                            ),
                            isActive: progress?.currentMailboxName == mailbox.mailboxName
                                && (progress?.stage.isActive ?? false),
                            statusSystemImage: syncState?.syncStatus == .error
                                ? "exclamationmark.triangle"
                                : nil
                        )
                        .help(mailbox.helpText ?? mailbox.displayName)
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
    let subtitle: String?
    let systemImage: String
    var trailingText: String?
    var isActive = false
    var statusSystemImage: String?

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.s2)
            if isActive {
                ProgressView()
                    .controlSize(.mini)
            } else if let statusSystemImage {
                Image(systemName: statusSystemImage)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            if let trailingText, !trailingText.isEmpty {
                Text(trailingText)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
