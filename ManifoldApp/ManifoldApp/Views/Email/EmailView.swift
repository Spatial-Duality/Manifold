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
    @State private var showAccountDetail: EmailAccountRecord?
    @State private var loadTask: Task<Void, Never>?
    @State private var sidebarFilter: MessagesSidebarFilter = .allMail

    var body: some View {
        mainContent
            .sheet(isPresented: $showAddAccount) { EmailAccountSetupView() }
            .sheet(item: $showAccountDetail) { account in EmailAccountDetailSheet(account: account) }
            .onChange(of: sidebarFilter) { _, _ in reloadMessages() }
            .onChange(of: selection.selectedAccountID) { _, _ in reloadMessages() }
            .onChange(of: search.freeText) { _, _ in reloadMessages() }
    }

    private func reloadMessages() {
        loadTask?.cancel()
        loadTask = Task { await loadMessages() }
    }

    @ViewBuilder
    private var mainContent: some View {
        if store.emailAccounts.accounts.isEmpty {
            EmailEmptyState(showAddAccount: $showAddAccount)
                .task { await store.emailAccounts.loadAccounts() }
        } else {
            // Two-pane: sidebar + full-width table (NO reading pane column)
            NavigationSplitView {
                EmailSidebar(
                    selection: selection,
                    sidebarFilter: $sidebarFilter,
                    showAddAccount: $showAddAccount,
                    showAccountDetail: $showAccountDetail
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

// MARK: - Account Detail Sheet

private struct EmailAccountDetailSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    let account: EmailAccountRecord
    @State private var confirmDelete = false

    private var currentAccount: EmailAccountRecord {
        store.emailAccounts.accounts.first(where: { $0.accountID == account.accountID }) ?? account
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: currentAccount.provider.systemImage)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentAccount.displayName).font(.headline)
                    Text(currentAccount.username ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Spacing.edge)

            Divider()

            Form {
                Section("Connection") {
                    LabeledContent("Server") { Text(currentAccount.server ?? "Unknown").font(Typ.mono) }
                    LabeledContent("Port") { Text("\(currentAccount.port ?? 993)").font(Typ.mono) }
                }

                Section {
                    Button("Remove Account", role: .destructive) { confirmDelete = true }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 480, height: 400)
        .alert("Remove Account?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task {
                    await store.emailAccounts.removeAccount(id: currentAccount.accountID)
                    dismiss()
                }
            }
        } message: {
            Text("This will remove \(currentAccount.displayName) and stop syncing.")
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
