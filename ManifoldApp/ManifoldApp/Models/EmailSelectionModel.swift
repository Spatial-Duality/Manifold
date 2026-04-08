import SwiftUI
import ManifoldKit

/// Coordination model for email navigation state across all three panes.
@Observable
@MainActor
final class EmailSelectionModel {
    /// Currently selected account ID (sidebar).
    var selectedAccountID: String?
    /// Currently selected mailbox within an account (sidebar).
    var selectedMailbox: String?
    /// Set of selected message IDs for multi-select (message list).
    var selectedMessageIDs: Set<String> = []
    /// Single focused message ID for reading pane.
    var focusedMessageID: String?
    /// Active quick filter (Unread/Flagged/Attachments/Today).
    var activeFilter: QuickFilter?
    /// Sort key for message list.
    var sortKey: EmailSortKey = .date
    /// Whether the sidebar "Shared with Cowork" section is selected.
    var showingSharedEmails: Bool = false
    /// Selected smart mailbox ID.
    var selectedSmartMailboxID: String?
    /// Selected smart mailbox rules for query.
    var selectedSmartMailboxRules: SmartMailboxRules?

    /// The single focused message for the reading pane.
    /// When multi-selecting, this is the last-clicked message.
    var focusedMessage: EmailMessageRecord?

    /// Convenience: is multi-select active?
    var isMultiSelecting: Bool { selectedMessageIDs.count > 1 }

    /// Select a single message (clears multi-select).
    func selectSingle(_ message: EmailMessageRecord) {
        selectedMessageIDs = [message.emailID]
        focusedMessageID = message.emailID
        focusedMessage = message
    }

    /// Clear all message selection.
    func clearMessageSelection() {
        selectedMessageIDs.removeAll()
        focusedMessageID = nil
        focusedMessage = nil
    }

    /// Navigate to a specific account/mailbox.
    func navigate(accountID: String?, mailbox: String? = nil) {
        selectedAccountID = accountID
        selectedMailbox = mailbox
        clearMessageSelection()
        activeFilter = nil
        showingSharedEmails = false
        selectedSmartMailboxID = nil
        selectedSmartMailboxRules = nil
    }

    /// Activate a quick filter (clears account/mailbox scope).
    func activateFilter(_ filter: QuickFilter) {
        activeFilter = filter
        selectedMailbox = nil
        showingSharedEmails = false
        selectedSmartMailboxID = nil
        selectedSmartMailboxRules = nil
        clearMessageSelection()
    }

    /// Show shared emails view.
    func showSharedEmails() {
        showingSharedEmails = true
        selectedMailbox = nil
        activeFilter = nil
        selectedSmartMailboxID = nil
        selectedSmartMailboxRules = nil
        clearMessageSelection()
    }

    /// Select a smart mailbox.
    func selectSmartMailbox(_ mailbox: SmartMailboxRecord) {
        selectedSmartMailboxID = mailbox.mailboxID
        selectedSmartMailboxRules = mailbox.rules
        selectedMailbox = nil
        activeFilter = nil
        showingSharedEmails = false
        clearMessageSelection()
    }
}
