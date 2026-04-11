import SwiftUI
import ManifoldKit

struct EmailSidebar: View {
    @Environment(ManifoldStore.self) var store
    @Bindable var selection: EmailSelectionModel
    @Binding var showAddAccount: Bool
    @Binding var showAccountDetail: EmailAccountRecord?
    @State private var showSmartMailboxEditor = false

    var body: some View {
        List {
            UnifiedInboxRow(selection: selection)

            // 4.5: Collapsible sections with header prominence
            Section {
                QuickFilterSection(selection: selection)
            } header: {
                Text("Filters")
            }
            .headerProminence(.increased)

            SmartMailboxSection(
                selection: selection,
                onNewMailbox: { showSmartMailboxEditor = true }
            )

            SharedEmailsRow(selection: selection)

            ForEach(store.emailAccounts.accounts) { account in
                AccountTreeSection(
                    account: account,
                    syncStates: store.emailAccounts.syncStates[account.accountID] ?? [],
                    selection: selection,
                    onDetail: { showAccountDetail = account }
                )
            }

            Section {
                AddAccountButton(showAddAccount: $showAddAccount)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Email Backup")
        .sheet(isPresented: $showSmartMailboxEditor) {
            SmartMailboxEditor()
        }
    }
}

// MARK: - Smart Mailbox Sidebar Section

private struct SmartMailboxSection: View {
    @Environment(ManifoldStore.self) var store
    @Bindable var selection: EmailSelectionModel
    let onNewMailbox: () -> Void

    @State private var smartMailboxes: [SmartMailboxRecord] = []
    @State private var counts: [String: Int] = [:]

    var body: some View {
        Section {
            if smartMailboxes.isEmpty {
                ContentUnavailableView {
                    Label("No Smart Mailboxes", systemImage: "tray.2")
                        .font(.caption)
                } description: {
                    Text("Create rules to automatically filter your backed-up emails.")
                        .font(.caption)
                }
            } else {
                ForEach(smartMailboxes) { mailbox in
                    Button {
                        selection.selectSmartMailbox(mailbox)
                    } label: {
                        HStack {
                            Label(mailbox.displayName, systemImage: mailbox.iconName)
                            Spacer()
                            Text("\(counts[mailbox.mailboxID] ?? 0)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .fontWeight(selection.selectedSmartMailboxID == mailbox.mailboxID ? .medium : .regular)
                }
            }

            Button(action: onNewMailbox) {
                Label("New Smart Mailbox", systemImage: "plus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Smart Mailboxes")
        }
        .task { await loadSmartMailboxes() }
    }

    private func loadSmartMailboxes() async {
        do {
            smartMailboxes = try await store.emailAccounts.allSmartMailboxes()
            for mb in smartMailboxes {
                counts[mb.mailboxID] = await store.emailAccounts.smartMailboxCount(rulesJSON: mb.rulesJSON)
            }
        } catch {
            smartMailboxes = []
        }
    }
}
