// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

// MARK: - Email Messages View (Synology Active Backup–style governance browser)
// NOT a mail client. Two-pane: sidebar + full-width table with inline preview.

struct EmailView: View {
    @Environment(ManifoldStore.self) var store
    @Bindable var selection: EmailSelectionModel
    @State private var search = EmailSearchModel()
    @State private var messages: [EmailMessageRecord] = []
    @State private var showAddAccount = false
    @State private var loadTask: Task<Void, Never>?
    @State private var sidebarFilter: MessagesSidebarFilter = .allMail

    var body: some View {
        mainContent
            .sheet(isPresented: $showAddAccount) { EmailAccountSetupView() }
            .onChange(of: sidebarFilter) { _, _ in reloadMessages() }
            .onChange(of: selection.selectedAccountID) { _, _ in reloadMessages() }
            .onChange(of: search.freeText) { _, _ in reloadMessages() }
            .onChange(of: store.emailAccounts.mailboxRefreshToken) { _, _ in reloadMessages() }
            .onChange(of: store.isRuntimeConnected) { _, connected in
                guard connected else { return }
                reloadMessages()
            }
    }

    private func reloadMessages() {
        loadTask?.cancel()
        loadTask = Task { await loadMessages() }
    }

    @ViewBuilder
    private var mainContent: some View {
        if store.emailAccounts.accounts.isEmpty, !store.isRuntimeConnected {
            EmailRuntimeUnavailableState()
                .task { await store.emailAccounts.loadAccounts() }
        } else if store.emailAccounts.accounts.isEmpty {
            EmailEmptyState(showAddAccount: $showAddAccount)
                .task { await store.emailAccounts.loadAccounts() }
        } else {
            // Two-pane: sidebar + full-width table (NO reading pane column)
            NavigationSplitView {
                EmailSidebar(
                    sidebarFilter: $sidebarFilter,
                    showAddAccount: $showAddAccount
                )
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
            } detail: {
                // Full-width governance table with inline preview
                EmailMessageList(
                    selection: selection,
                    search: search,
                    messages: messages
                )
            }
            .navigationSplitViewStyle(.balanced)
            .task { await initialLoad() }
        }
    }

    // MARK: - Data Loading

    private func initialLoad() async {
        await store.emailAccounts.loadAccounts()
        if selection.selectedAccountID == nil, let first = store.emailAccounts.accounts.first {
            selection.selectedAccountID = first.accountID
        }
        await loadMessages()
    }

    private func loadMessages() async {
        // Filter based on sidebar selection
        switch sidebarFilter {
        case .sharedWithClaude, .sharedWithCodex:
            messages = await store.emailAccounts.sharedEmails()
        case .notShared:
            let allMsgs = await store.emailAccounts.allMessages()
            let sharedIDs = await store.emailAccounts.sharedEmailIDs()
            messages = allMsgs.filter { !sharedIDs.contains($0.emailID) }
        case .inbox:
            if let accountID = selection.selectedAccountID {
                messages = await store.emailAccounts.messagesInMailbox(accountID: accountID, mailbox: "INBOX")
            } else {
                messages = await store.emailAccounts.allMessages()
            }
        case .folder(let folder):
            if let accountID = selection.selectedAccountID {
                messages = await store.emailAccounts.messagesInMailbox(accountID: accountID, mailbox: folder)
            }
        case .allMail:
            if let accountID = selection.selectedAccountID {
                messages = await store.emailAccounts.messages(accountID: accountID)
            } else {
                messages = await store.emailAccounts.allMessages()
            }
        }
    }
}

// MARK: - Empty State

private struct EmailEmptyState: View {
    @Binding var showAddAccount: Bool

    var body: some View {
        ContentUnavailableView {
            Label("Email Backup", systemImage: "envelope.badge.shield.half.filled")
        } description: {
            Text("Back up and govern your emails. Connect an account to get started.")
        } actions: {
            Button("Add Email Account", systemImage: "person.badge.plus") {
                showAddAccount = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct EmailRuntimeUnavailableState: View {
    var body: some View {
        ContentUnavailableView {
            Label("Runtime Disconnected", systemImage: "bolt.horizontal.circle")
        } description: {
            Text("Manifold can’t reach its runtime, so email accounts and messages can’t load yet.")
        }
    }
}
