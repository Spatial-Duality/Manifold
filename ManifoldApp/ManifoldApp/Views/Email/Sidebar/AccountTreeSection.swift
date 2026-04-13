// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct AccountTreeSection: View {
    @Environment(ManifoldStore.self) var store
    let account: EmailAccountRecord
    let syncStates: [SyncStateRecord]
    @Bindable var selection: EmailSelectionModel
    let onDetail: () -> Void

    @State private var imapMailboxes: [IMAPMailboxRecord] = []
    @State private var isExpanded = true

    private var isSyncing: Bool { syncStates.contains { $0.syncStatus == .syncing } }
    private var hasError: Bool { syncStates.contains { $0.syncStatus == .error } }

    var body: some View {
        Section(isExpanded: $isExpanded) {
            // All mail for this account
            Button {
                selection.navigate(accountID: account.accountID)
            } label: {
                Label {
                    HStack {
                        Text("All Mail")
                        Spacer()
                        Text("\(store.emailAccounts.syncStates[account.accountID]?.reduce(0) { $0 + $1.messageCount } ?? 0)")
                            .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                    }
                } icon: {
                    Image(systemName: "tray.2")
                }
            }
            .buttonStyle(.plain)
            .fontWeight(selection.selectedAccountID == account.accountID && selection.selectedMailbox == nil ? .medium : .regular)

            // IMAP mailboxes sorted by folder type priority
            let sorted = imapMailboxes
                .filter { $0.isSelectable }
                .sorted { $0.folderType.sortPriority < $1.folderType.sortPriority }

            ForEach(sorted, id: \.mailboxName) { mailbox in
                Button {
                    selection.navigate(accountID: account.accountID, mailbox: mailbox.mailboxName)
                } label: {
                    Label {
                        HStack {
                            Text(mailbox.mailboxName)
                            Spacer()
                        }
                    } icon: {
                        Image(systemName: mailbox.folderType.systemImage)
                    }
                }
                .buttonStyle(.plain)
                .fontWeight(selection.selectedMailbox == mailbox.mailboxName && selection.selectedAccountID == account.accountID ? .medium : .regular)
            }
        } header: {
            HStack(spacing: Spacing.standard) {
                Image(systemName: account.provider.systemImage)
                    .foregroundStyle(providerColor)
                    .frame(width: 16)
                Text(account.displayName)
                    .font(.callout.weight(.medium))
                Spacer()
                Group {
                    if isSyncing {
                        ProgressView().controlSize(.mini)
                    } else if hasError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).imageScale(.small)
                    }
                }
            }
            .contextMenu {
                Button("Sync Now") {
                    Task { await store.emailAccounts.syncNow(accountID: account.accountID) }
                }
                Button("Account Details...") { onDetail() }
                Divider()
                Toggle("Sync Enabled", isOn: Binding(
                    get: { account.syncEnabled },
                    set: { enabled in
                        Task { await store.emailAccounts.toggleSync(accountID: account.accountID, enabled: enabled) }
                    }
                ))
                Divider()
                Button("Remove Account", role: .destructive) {
                    Task { await store.emailAccounts.removeAccount(id: account.accountID) }
                }
            }
        }
        .task(id: store.emailAccounts.mailboxRefreshToken) {
            imapMailboxes = await store.emailAccounts.imapMailboxes(accountID: account.accountID)
        }
    }

    private var providerColor: Color {
        switch account.provider {
        case .gmail:    .red
        case .outlook:  .blue
        case .icloud:   .cyan
        case .yahoo:    .purple
        case .fastmail: .indigo
        case .other:    .secondary
        }
    }
}
