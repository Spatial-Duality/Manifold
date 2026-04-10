import SwiftUI
import ManifoldKit

// MARK: - Main Email View (3-pane layout)

struct EmailView: View {
    @Environment(ManifoldStore.self) var store
    @State private var selection = EmailSelectionModel()
    @State private var search = EmailSearchModel()
    @State private var messages: [EmailMessageRecord] = []
    @State private var showAddAccount = false
    @State private var showAccountDetail: EmailAccountRecord?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        mainContent
            .sheet(isPresented: $showAddAccount) { EmailAccountSetupView() }
            .sheet(item: $showAccountDetail) { account in EmailAccountDetailSheet(account: account) }
            .onChange(of: selection.selectedAccountID) { _, _ in reloadMessages() }
            .onChange(of: selection.selectedMailbox) { _, _ in reloadMessages() }
            .onChange(of: selection.activeFilter) { _, _ in reloadMessages() }
            .onChange(of: selection.showingSharedEmails) { _, _ in reloadMessages() }
            .onChange(of: selection.selectedSmartMailboxID) { _, _ in reloadMessages() }
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
            NavigationSplitView {
                EmailSidebar(
                    selection: selection,
                    showAddAccount: $showAddAccount,
                    showAccountDetail: $showAccountDetail
                )
            } content: {
                EmailMessageList(
                    selection: selection,
                    search: search,
                    messages: messages
                )
                .searchable(text: $search.freeText, prompt: "Search emails")
            } detail: {
                EmailReadingPane(selection: selection)
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
    }

    private func loadMessages() async {
        if selection.showingSharedEmails {
            messages = await store.emailAccounts.sharedEmails()
            return
        }

        // Smart mailbox query
        if let rules = selection.selectedSmartMailboxRules, let emailStore = store.emailStore {
            messages = (try? await emailStore.smartMailboxMessages(rules: rules, sortKey: selection.sortKey)) ?? []
            return
        }

        // Use search if active
        if search.isActive || selection.activeFilter != nil {
            messages = await store.emailAccounts.searchMessages(
                tokens: search.tokens,
                freeText: search.freeText,
                accountID: selection.selectedAccountID,
                mailbox: selection.selectedMailbox,
                filter: selection.activeFilter,
                sortKey: selection.sortKey
            )
            return
        }

        guard let accountID = selection.selectedAccountID else {
            messages = await store.emailAccounts.allMessages()
            return
        }
        if let mailbox = selection.selectedMailbox {
            messages = await store.emailAccounts.messagesInMailbox(accountID: accountID, mailbox: mailbox)
        } else {
            messages = await store.emailAccounts.messages(accountID: accountID)
        }
    }
}

// MARK: - Account Detail Sheet

private struct EmailAccountDetailSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    let account: EmailAccountRecord
    @State private var syncStates: [SyncStateRecord] = []
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: account.provider.systemImage)
                    .font(.title2).foregroundStyle(providerColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName).font(.headline)
                    Text(account.username ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Spacing.edge)

            Divider()

            Form {
                Section("Connection") {
                    LabeledContent("Server") { Text(account.server ?? "Unknown").font(.caption.monospaced()) }
                    LabeledContent("Port") { Text("\(account.port ?? 993)").font(.caption.monospaced()) }
                    LabeledContent("Auth") { Text(account.authType).font(.caption) }
                    LabeledContent("Sync Interval") { Text("\(account.syncIntervalSeconds / 60) min") }
                }

                Section("Mailboxes") {
                    if syncStates.isEmpty {
                        Text("No mailboxes synced yet")
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(syncStates) { state in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(state.mailboxName)
                                        .font(.callout.weight(.medium))
                                    HStack(spacing: Spacing.standard) {
                                        Text("\(state.messageCount) messages")
                                        if let lastSync = state.lastSyncAt {
                                            Text("\u{2022}").foregroundStyle(.quaternary)
                                            Text("Last sync: \(lastSync)")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                syncStatusBadge(state.syncStatus)
                            }
                        }
                    }
                }

                Section("Sync") {
                    Toggle("Sync Enabled", isOn: Binding(
                        get: { account.syncEnabled },
                        set: { enabled in
                            Task { await store.emailAccounts.toggleSync(accountID: account.accountID, enabled: enabled) }
                        }
                    ))
                    Button("Sync Now") {
                        Task { await store.emailAccounts.syncNow(accountID: account.accountID) }
                    }
                }

                Section {
                    Button("Remove Account", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 480, height: 520)
        .task {
            syncStates = store.emailAccounts.syncStates[account.accountID] ?? []
        }
        .alert("Remove Account?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task {
                    await store.emailAccounts.removeAccount(id: account.accountID)
                    dismiss()
                }
            }
        } message: {
            Text("This will remove \(account.displayName) and stop syncing. Backed up .eml files on disk will not be deleted.")
        }
    }

    @ViewBuilder
    private func syncStatusBadge(_ status: SyncStatus) -> some View {
        switch status {
        case .syncing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Syncing").font(.caption2).foregroundStyle(.secondary)
            }
        case .error:
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2).foregroundStyle(.orange)
        case .idle:
            Label("OK", systemImage: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green)
        case .pausedNoDrive:
            Label("Paused", systemImage: "pause.circle")
                .font(.caption2).foregroundStyle(.secondary)
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

// MARK: - Empty State

private struct EmailEmptyState: View {
    @Binding var showAddAccount: Bool

    var body: some View {
        VStack(spacing: Spacing.large) {
            Spacer()
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 48)).foregroundStyle(.tertiary)

            VStack(spacing: Spacing.standard) {
                Text("Email Backup")
                    .font(.title2.weight(.semibold))
                Text("Back up all your emails as .eml files on your disk.\nConnect an account to get started.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showAddAccount = true
            } label: {
                Label("Add Email Account", systemImage: "person.badge.plus")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Supports Gmail, Outlook, iCloud, Yahoo, Fastmail, and any IMAP server.")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
