// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import AppKit
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
    @State private var removalCandidate: EmailAccountRecord?

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
        .sheet(item: $removalCandidate) { account in
            MailAccountRemovalSheet(account: account)
                .environment(store)
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
                    HStack(spacing: Spacing.s2) {
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
                        Menu {
                            Button("Mailbox Settings…", systemImage: "gearshape") {
                                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                            }
                            Button("Sync now", systemImage: "arrow.clockwise") {
                                Task { await store.mailAccounts.syncNow(accountID: account.accountID) }
                            }
                            Divider()
                            Button("Remove Account…", systemImage: "trash", role: .destructive) {
                                removalCandidate = account
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Mail account actions")
                        .accessibilityIdentifier("mail.account.\(account.accountID).menu")
                    }
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

private struct MailAccountRemovalSheet: View {
    @Environment(ManifoldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let account: EmailAccountRecord
    @State private var confirmed = false
    @State private var isRemoving = false
    @State private var result: MailAccountRemovalResult?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Remove \(account.displayName)") {
                Text("This permanently deletes this account’s local credentials, mailboxes, messages, search data, sync jobs, sync logs, archived mail storage, and temporary sync files from Manifold.")
                    .foregroundStyle(.secondary)
                Text("Contextual agent history is preserved only as the plain-file removal history that Manifold writes before deleting the account data.")
                    .foregroundStyle(.secondary)
            }

            Section("Confirm") {
                Toggle("I understand this deletes all local mail data for this account.", isOn: $confirmed)
                if let result {
                    LabeledContent("Removed messages", value: "\(result.messageCount)")
                    LabeledContent("History file", value: result.contextArchivePath)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(ManifoldPalette.danger)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isRemoving)
                Spacer()
                if isRemoving {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Remove Account", role: .destructive) {
                    Task { await removeAccount() }
                }
                .disabled(!confirmed || isRemoving || result != nil)
            }
            .padding()
            .background(.bar)
        }
        .accessibilityIdentifier("mail.account.remove.sheet")
    }

    private func removeAccount() async {
        isRemoving = true
        defer { isRemoving = false }
        let removalResult = await store.mailAccounts.removeAccount(id: account.accountID)
        result = removalResult
        errorMessage = store.mailAccounts.lastRemovalError
        if removalResult != nil {
            await store.mailReview.prepare(force: true)
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
