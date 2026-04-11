import SwiftUI
import ManifoldKit

struct EmailMessageList: View {
    @Environment(ManifoldStore.self) var store
    @Bindable var selection: EmailSelectionModel
    @Bindable var search: EmailSearchModel
    let messages: [EmailMessageRecord]
    @State private var sharedEmailIDs: Set<String> = []

    /// Per-account sync state, not global. Prevents wrong-mailbox spinner.
    private var isSyncingSelectedAccount: Bool {
        guard let accountID = selection.selectedAccountID,
              let states = store.emailAccounts.syncStates[accountID] else { return false }
        return states.contains { $0.syncStatus == .syncing }
    }

    var body: some View {
        VStack(spacing: 0) {
            MessageFilterBar(selection: selection, search: search)

            if !selection.selectedMessageIDs.isEmpty && selection.isMultiSelecting {
                SelectionActionBar(
                    selectedCount: selection.selectedMessageIDs.count,
                    selection: selection
                )
            }

            List(messages, selection: $selection.selectedMessageIDs) { msg in
                EmailMessageRow(
                    message: msg,
                    isSelected: selection.focusedMessageID == msg.emailID,
                    isShared: sharedEmailIDs.contains(msg.emailID)
                )
                .tag(msg.emailID)
            }
            .listStyle(.inset)
            .overlay {
                if messages.isEmpty {
                    MessageListEmpty(
                        hasAccount: selection.selectedAccountID != nil,
                        isSyncing: isSyncingSelectedAccount
                    )
                }
            }
        }
        .focusable()
        .onKeyPress(.downArrow) { navigateMessage(direction: 1); return .handled }
        .onKeyPress(.upArrow) { navigateMessage(direction: -1); return .handled }
        .onKeyPress(characters: .init(charactersIn: "j")) { _ in navigateMessage(direction: 1); return .handled }
        .onKeyPress(characters: .init(charactersIn: "k")) { _ in navigateMessage(direction: -1); return .handled }
        .navigationTitle(listTitle)
        .navigationSubtitle("\(messages.count) messages")
        .onChange(of: selection.selectedMessageIDs) { _, newIDs in
            // When single selection changes, update the focused message
            if newIDs.count == 1, let id = newIDs.first {
                selection.focusedMessageID = id
                selection.focusedMessage = messages.first { $0.emailID == id }
            }
        }
        .task {
            sharedEmailIDs = await store.emailAccounts.sharedEmailIDs()
        }
    }

    // MARK: - Keyboard Navigation

    private func navigateMessage(direction: Int) {
        guard !messages.isEmpty else { return }
        if let currentID = selection.focusedMessageID,
           let idx = messages.firstIndex(where: { $0.emailID == currentID }) {
            let newIdx = max(0, min(messages.count - 1, idx + direction))
            selection.selectSingle(messages[newIdx])
        } else {
            let msg = direction > 0 ? messages[0] : messages[messages.count - 1]
            selection.selectSingle(msg)
        }
    }

    private var listTitle: String {
        if selection.showingSharedEmails { return "Shared with Claude" }
        if selection.selectedSmartMailboxID != nil { return "Smart Mailbox" }
        if let filter = selection.activeFilter { return filter.displayName }
        if let mb = selection.selectedMailbox { return mb }
        if let id = selection.selectedAccountID,
           let acct = store.emailAccounts.accounts.first(where: { $0.accountID == id }) {
            return acct.displayName
        }
        return "All Inboxes"
    }
}
