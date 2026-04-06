import SwiftUI

enum EmailListFilter: String, CaseIterable {
    case all, selected, shared, hidden
}

struct EmailView: View {
    @Environment(ManifoldStore.self) var store
    @State private var filter: EmailListFilter = .all
    @State private var searchText = ""
    @State private var selectedAccount = ""
    @State private var selectedMailbox = ""
    @State private var isFetching = false

    private var filteredEmails: [CachedEmail] {
        var emails = store.cachedEmails
        switch filter {
        case .selected:
            emails = emails.filter { store.selectedEmailIDsForNextSession.contains($0.messageID) }
        case .shared:
            emails = emails.filter(\.isShared)
        case .hidden:
            emails = emails.filter { $0.isUserHidden || $0.isAutoHidden }
        case .all:
            break
        }

        if !selectedAccount.isEmpty {
            emails = emails.filter { $0.account == selectedAccount }
        }
        if !searchText.isEmpty {
            emails = emails.filter {
                $0.sender.localizedStandardContains(searchText) ||
                $0.subject.localizedStandardContains(searchText)
            }
        }
        return emails
    }

    private var availableAccounts: [String] {
        Array(Set(store.mailboxes.map(\.account))).sorted()
    }

    private var availableMailboxes: [MailboxInfo] {
        guard !selectedAccount.isEmpty else { return store.mailboxes }
        return store.mailboxes.filter { $0.account == selectedAccount }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                VStack(spacing: Spacing.standard) {
                    Picker("Show", selection: $filter) {
                        Text("All").tag(EmailListFilter.all)
                        Text("Selected").tag(EmailListFilter.selected)
                        Text("Shared").tag(EmailListFilter.shared)
                        Text("Hidden").tag(EmailListFilter.hidden)
                    }
                    .pickerStyle(.segmented)

                    TextField("Search emails...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }
                .listRowSeparator(.hidden)

                if store.mailAccessStatus != .available {
                    MailSetupPrompt()
                } else {
                    MailboxImportSection(
                        selectedAccount: $selectedAccount,
                        selectedMailbox: $selectedMailbox,
                        isFetching: $isFetching,
                        availableAccounts: availableAccounts,
                        availableMailboxes: availableMailboxes
                    )

                    if filteredEmails.isEmpty {
                        EmailEmptyState(filter: filter)
                    } else {
                        EmailListContent(filteredEmails: filteredEmails)
                    }
                }

                if !store.emailRules.isEmpty {
                    EmailRulesSection()
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
        }
        .navigationTitle("Emails")
        .navigationSubtitle(emailSubtitle)
        .task {
            await store.checkMailAccess()
            await store.loadMailboxes()
            await store.loadCachedEmails()
            await store.loadEmailRules()
            initializeMailboxSelectionIfNeeded()
        }
        .onChange(of: store.mailboxes.count) { _, _ in
            initializeMailboxSelectionIfNeeded()
        }
        .onChange(of: selectedAccount) { _, newValue in
            if !availableMailboxes.contains(where: { $0.name == selectedMailbox && $0.account == newValue }) {
                selectedMailbox = availableMailboxes.first?.name ?? ""
            }
        }
    }

    private var emailSubtitle: String {
        let selectedCount = store.selectedEmailIDsForNextSession.count
        if let classification = store.emailClassification {
            return "\(selectedCount) selected, \(classification.shared) shared, \(classification.autoHidden) hidden"
        }
        return "\(selectedCount) selected"
    }

    private func initializeMailboxSelectionIfNeeded() {
        if selectedAccount.isEmpty {
            selectedAccount = availableAccounts.first ?? ""
        }
        if selectedMailbox.isEmpty {
            selectedMailbox = availableMailboxes.first?.name ?? ""
        }
    }
}

// MARK: - Mail Setup Prompt

private struct MailSetupPrompt: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        Section {
            VStack(spacing: Spacing.section) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Connect Apple Mail")
                    .font(.headline)
                Text("Import full messages, choose which ones are safe to share, and freeze a selected working set for the next session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                switch store.mailAccessStatus {
                case .mailNotRunning:
                    HStack(spacing: Spacing.standard) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow)
                        Text("Mail.app is not running").font(.callout)
                    }
                    Button("Check Again") { Task { await store.checkMailAccess() } }
                        .controlSize(.small)
                case .accessDenied:
                    HStack(spacing: Spacing.standard) {
                        Image(systemName: "xmark.circle").foregroundStyle(.red)
                        Text("Automation permission needed").font(.callout)
                    }
                    Text("System Settings → Privacy & Security → Automation → enable for Mail")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button("Check Again") { Task { await store.checkMailAccess() } }
                        .controlSize(.small)
                default:
                    Button("Connect Apple Mail") { Task { await store.checkMailAccess() } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.large)
        }
    }
}

// MARK: - Mailbox Import Section

private struct MailboxImportSection: View {
    @Environment(ManifoldStore.self) var store
    @Binding var selectedAccount: String
    @Binding var selectedMailbox: String
    @Binding var isFetching: Bool
    let availableAccounts: [String]
    let availableMailboxes: [MailboxInfo]

    var body: some View {
        Section("Mailbox Import") {
            VStack(alignment: .leading, spacing: Spacing.standard) {
                if store.mailboxes.isEmpty {
                    Text("No mailboxes loaded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: Spacing.section) {
                        Picker("Account", selection: $selectedAccount) {
                            ForEach(availableAccounts, id: \.self) { account in
                                Text(account).tag(account)
                            }
                        }
                        .frame(maxWidth: 220)

                        Picker("Mailbox", selection: $selectedMailbox) {
                            ForEach(availableMailboxes, id: \.name) { mailbox in
                                Text("\(mailbox.name) (\(mailbox.messageCount))").tag(mailbox.name)
                            }
                        }
                        .frame(maxWidth: 260)

                        Button(action: fetchMailbox) {
                            Label("Fetch", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedAccount.isEmpty || selectedMailbox.isEmpty || isFetching)

                        if isFetching {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                Text("Only emails marked as shared can be selected for the next session.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func fetchMailbox() {
        guard !selectedAccount.isEmpty, !selectedMailbox.isEmpty else { return }
        isFetching = true
        Task {
            await store.fetchAndCacheEmails(account: selectedAccount, mailbox: selectedMailbox)
            isFetching = false
        }
    }
}

// MARK: - Email Empty State

private struct EmailEmptyState: View {
    let filter: EmailListFilter

    var body: some View {
        ContentUnavailableView(
            "No Emails",
            systemImage: "envelope",
            description: Text(filter == .all
                ? "Fetch a mailbox, then choose which shared emails should go into the next session."
                : "No emails match this filter.")
        )
        .listRowSeparator(.hidden)
    }
}

// MARK: - Email List Content

private struct EmailListContent: View {
    @Environment(ManifoldStore.self) var store
    let filteredEmails: [CachedEmail]

    var body: some View {
        ForEach(filteredEmails, id: \.messageID) { email in
            EmailRow(
                email: email,
                isSelected: store.selectedEmailIDsForNextSession.contains(email.messageID)
            )
        }
    }
}

// MARK: - Rules Section

private struct EmailRulesSection: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        Section("Auto-Hide Rules") {
            ForEach(store.emailRules, id: \.id) { rule in
                HStack(spacing: Spacing.standard) {
                    Image(systemName: "shield")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(rule.pattern)
                        .font(.callout.monospaced())
                    Spacer()
                    Text(rule.category ?? "hidden")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await store.removeEmailRule(id: rule.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }
}
