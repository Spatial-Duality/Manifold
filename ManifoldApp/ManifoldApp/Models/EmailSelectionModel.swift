// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftUI
import ManifoldKit

@Observable
@MainActor
final class MailReviewModel {
    var selectedAccountID: String?
    var selectedMailboxName: String?
    var activeQuickFilter: QuickFilter?
    var searchText: String = ""
    var messages: [EmailMessageRecord] = []
    var sharedEmailIDs: Set<String> = []
    var expandedThreadKeys: Set<String> = []
    var selectedThreadKey: String?
    var selectedMessageID: String?
    var isLoading = false
    var errorMessage: String?
    var mailboxesByAccountID: [String: [IMAPMailboxRecord]] = [:]

    private var mailAccounts: MailAccountsModel?
    private var reloadTask: Task<Void, Never>?

    var threadRows: [MailThreadRow] {
        MailThreadRow.group(messages: messages)
    }

    var selectedThread: MailThreadRow? {
        if let selectedThreadKey {
            return threadRows.first(where: { $0.threadKey == selectedThreadKey })
        }
        return threadRows.first
    }

    var selectedMessage: EmailMessageRecord? {
        guard let selectedThread else { return nil }
        if let selectedMessageID,
           let explicit = selectedThread.messages.first(where: { $0.emailID == selectedMessageID }) {
            return explicit
        }
        return selectedThread.latestMessage
    }

    func configure(mailAccounts: MailAccountsModel) {
        self.mailAccounts = mailAccounts
    }

    func prepare(force: Bool = false) async {
        guard let mailAccounts else { return }
        if force || mailAccounts.accounts.isEmpty {
            await mailAccounts.loadAccounts()
        }

        let accounts = mailAccounts.accounts
        guard !accounts.isEmpty else {
            resetBrowser()
            return
        }

        await ensureMailboxesLoaded(for: accounts.map(\.accountID), force: force)
        selectedAccountID = resolvedAccountID(from: accounts)

        if let accountID = selectedAccountID {
            let selectableMailboxes = selectableMailboxes(for: accountID)
            if force || selectedMailboxName == nil || !selectableMailboxes.contains(where: { $0.mailboxName == selectedMailboxName }) {
                selectedMailboxName = defaultMailboxName(from: selectableMailboxes)
            }
        }

        sharedEmailIDs = await mailAccounts.sharedEmailIDs()
        errorMessage = mailAccounts.lastQueryError

        guard selectedAccountID != nil else {
            messages = []
            return
        }

        guard selectedMailboxName != nil else {
            messages = []
            selectedThreadKey = nil
            selectedMessageID = nil
            return
        }

        await reloadVisibleMessages()
    }

    func browse(accountID: String, mailbox: String, clearQuery: Bool = true) async {
        guard selectedAccountID != accountID || selectedMailboxName != mailbox || clearQuery else {
            await reloadVisibleMessages()
            return
        }

        reloadTask?.cancel()
        selectedAccountID = accountID
        selectedMailboxName = mailbox
        if clearQuery {
            searchText = ""
            activeQuickFilter = nil
        }
        selectedThreadKey = nil
        selectedMessageID = nil
        await ensureMailboxesLoaded(for: [accountID], force: false)
        await reloadVisibleMessages()
    }

    func selectAccount(_ accountID: String) async {
        guard selectedAccountID != accountID else { return }
        selectedAccountID = accountID
        selectedThreadKey = nil
        selectedMessageID = nil
        searchText = ""
        activeQuickFilter = nil
        await ensureMailboxesLoaded(for: [accountID], force: false)
        selectedMailboxName = defaultMailboxName(from: selectableMailboxes(for: accountID))
        await reloadVisibleMessages()
    }

    func selectMailbox(_ mailboxName: String) async {
        guard selectedMailboxName != mailboxName else { return }
        selectedMailboxName = mailboxName
        selectedThreadKey = nil
        selectedMessageID = nil
        await reloadVisibleMessages()
    }

    func setQuickFilter(_ filter: QuickFilter?) async {
        let nextFilter = activeQuickFilter == filter ? nil : filter
        guard activeQuickFilter != nextFilter else { return }
        activeQuickFilter = nextFilter
        selectedThreadKey = nil
        selectedMessageID = nil
        await reloadVisibleMessages()
    }

    func updateSearchText(_ text: String) {
        searchText = text
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            await self.reloadVisibleMessages()
        }
    }

    func retry() async {
        await reloadVisibleMessages()
    }

    func syncSelectedAccount() async {
        guard let mailAccounts, let accountID = selectedAccountID else { return }
        await mailAccounts.syncNow(accountID: accountID)
        await ensureMailboxesLoaded(for: [accountID], force: true)
        await reloadVisibleMessages()
    }

    func toggleExpanded(threadKey: String) {
        var nextExpandedThreadKeys = expandedThreadKeys
        if nextExpandedThreadKeys.contains(threadKey) {
            nextExpandedThreadKeys.remove(threadKey)
        } else {
            nextExpandedThreadKeys.insert(threadKey)
        }
        expandedThreadKeys = nextExpandedThreadKeys
    }

    func selectThread(_ threadKey: String) {
        selectedThreadKey = threadKey
        guard let thread = threadRows.first(where: { $0.threadKey == threadKey }) else { return }
        selectedMessageID = thread.latestMessage.emailID
    }

    func selectMessage(_ emailID: String, threadKey: String) {
        selectedThreadKey = threadKey
        selectedMessageID = emailID
        var nextExpandedThreadKeys = expandedThreadKeys
        nextExpandedThreadKeys.insert(threadKey)
        expandedThreadKeys = nextExpandedThreadKeys
    }

    func setThreadShared(_ thread: MailThreadRow, isShared: Bool) async {
        guard let mailAccounts else { return }
        let ids = thread.messages.map(\.emailID)
        if isShared {
            await mailAccounts.shareEmails(emailIDs: ids)
        } else {
            await mailAccounts.unshareEmails(emailIDs: ids)
        }
        await refreshSharedState()
    }

    func setMessageShared(_ emailID: String, isShared: Bool) async {
        guard let mailAccounts else { return }
        if isShared {
            await mailAccounts.shareEmails(emailIDs: [emailID])
        } else {
            await mailAccounts.unshareEmails(emailIDs: [emailID])
        }
        await refreshSharedState()
    }

    func mailboxes(for accountID: String) -> [IMAPMailboxRecord] {
        (mailboxesByAccountID[accountID] ?? []).sorted(by: mailboxComparator)
    }

    func shareState(for thread: MailThreadRow) -> MailThreadShareState {
        thread.shareState(sharedEmailIDs: sharedEmailIDs)
    }

    func shareState(for emailID: String) -> MailThreadShareState {
        sharedEmailIDs.contains(emailID) ? .on : .off
    }

    private func reloadVisibleMessages() async {
        guard let mailAccounts, let accountID = selectedAccountID else {
            messages = []
            errorMessage = nil
            return
        }

        guard let mailbox = selectedMailboxName else {
            messages = []
            errorMessage = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loadedMessages: [EmailMessageRecord]
        if trimmedSearch.isEmpty, activeQuickFilter == nil {
            loadedMessages = await mailboxScopedMessages(
                accountID: accountID,
                mailbox: mailbox,
                limit: 500
            )
        } else {
            let scopedMatches = await mailAccounts.searchMessages(
                freeText: trimmedSearch,
                accountID: accountID,
                mailbox: mailbox,
                filter: activeQuickFilter,
                sortKey: .date,
                limit: 500
            )
            if scopedMatches.isEmpty {
                let accountMatches = await mailAccounts.searchMessages(
                    freeText: trimmedSearch,
                    accountID: accountID,
                    mailbox: nil,
                    filter: activeQuickFilter,
                    sortKey: .date,
                    limit: 500
                )
                loadedMessages = locallyScopedMessages(
                    accountMatches,
                    accountID: accountID,
                    mailbox: mailbox
                )
            } else {
                loadedMessages = scopedMatches
            }
        }

        messages = loadedMessages.sorted(by: MailDate.comparatorDescending)
        errorMessage = mailAccounts.lastQueryError
        await refreshSharedState()
        reconcileSelection()
    }

    private func mailboxScopedMessages(accountID: String, mailbox: String, limit: Int) async -> [EmailMessageRecord] {
        guard let mailAccounts else { return [] }

        let scopedMessages = await mailAccounts.messagesInMailbox(
            accountID: accountID,
            mailbox: mailbox,
            limit: limit
        )
        if !scopedMessages.isEmpty {
            return scopedMessages
        }

        let accountMessages = await mailAccounts.messages(accountID: accountID, limit: limit)
        return locallyScopedMessages(accountMessages, accountID: accountID, mailbox: mailbox)
    }

    private func locallyScopedMessages(
        _ accountMessages: [EmailMessageRecord],
        accountID: String,
        mailbox: String
    ) -> [EmailMessageRecord] {
        let resolvedMailbox = MailboxResolver.resolve(
            requestedName: mailbox,
            imapMailboxes: mailboxes(for: accountID)
        )

        return accountMessages.filter { message in
            guard message.accountID == accountID else { return false }
            let resolvedMessageMailbox = MailboxResolver.resolve(
                requestedName: message.mailbox,
                imapMailboxes: mailboxes(for: accountID)
            )
            return resolvedMessageMailbox.caseInsensitiveCompare(resolvedMailbox) == .orderedSame
        }
    }

    private func refreshSharedState() async {
        guard let mailAccounts else { return }
        sharedEmailIDs = await mailAccounts.sharedEmailIDs()
        errorMessage = errorMessage ?? mailAccounts.lastQueryError
    }

    private func ensureMailboxesLoaded(for accountIDs: [String], force: Bool) async {
        guard let mailAccounts else { return }
        for accountID in accountIDs {
            if !force, mailboxesByAccountID[accountID] != nil {
                continue
            }
            mailboxesByAccountID[accountID] = await mailAccounts.imapMailboxes(accountID: accountID)
        }
        errorMessage = mailAccounts.lastQueryError
    }

    private func selectableMailboxes(for accountID: String) -> [IMAPMailboxRecord] {
        mailboxes(for: accountID).filter(\.isSelectable)
    }

    private func defaultMailboxName(from mailboxes: [IMAPMailboxRecord]) -> String? {
        if let inbox = mailboxes.first(where: { $0.folderType == .inbox }) {
            return inbox.mailboxName
        }
        return mailboxes.first?.mailboxName
    }

    private func resolvedAccountID(from accounts: [EmailAccountRecord]) -> String? {
        if let selectedAccountID, accounts.contains(where: { $0.accountID == selectedAccountID }) {
            return selectedAccountID
        }
        return accounts.first(where: \.syncEnabled)?.accountID ?? accounts.first?.accountID
    }

    private func reconcileSelection() {
        let rows = threadRows
        let validThreadKeys = Set(rows.map(\.threadKey))
        expandedThreadKeys = expandedThreadKeys.intersection(validThreadKeys)

        guard !rows.isEmpty else {
            selectedThreadKey = nil
            selectedMessageID = nil
            return
        }

        if selectedThreadKey == nil || !validThreadKeys.contains(selectedThreadKey ?? "") {
            selectedThreadKey = rows.first?.threadKey
        }

        guard let selectedThreadKey,
              let selectedThread = rows.first(where: { $0.threadKey == selectedThreadKey }) else {
            return
        }

        if let selectedMessageID,
           selectedThread.messages.contains(where: { $0.emailID == selectedMessageID }) {
            return
        }

        selectedMessageID = selectedThread.latestMessage.emailID
    }

    private func resetBrowser() {
        selectedAccountID = nil
        selectedMailboxName = nil
        activeQuickFilter = nil
        searchText = ""
        messages = []
        sharedEmailIDs = []
        expandedThreadKeys = []
        selectedThreadKey = nil
        selectedMessageID = nil
        errorMessage = nil
        mailboxesByAccountID = [:]
    }

    private func mailboxComparator(lhs: IMAPMailboxRecord, rhs: IMAPMailboxRecord) -> Bool {
        if lhs.folderType.sortPriority != rhs.folderType.sortPriority {
            return lhs.folderType.sortPriority < rhs.folderType.sortPriority
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.mailboxName.localizedCaseInsensitiveCompare(rhs.mailboxName) == .orderedAscending
    }
}

enum MailThreadShareState: Hashable {
    case off
    case mixed
    case on

    var accessibilityKey: String {
        switch self {
        case .off: return "off"
        case .mixed: return "mixed"
        case .on: return "on"
        }
    }

    var checkboxState: TriStateCheckbox.State {
        switch self {
        case .off: return .off
        case .mixed: return .mixed
        case .on: return .on
        }
    }

    var label: String {
        switch self {
        case .off: return "Not shared here"
        case .mixed: return "Partially shared here"
        case .on: return "Shared here"
        }
    }
}

struct MailThreadMessageRow: Identifiable, Hashable {
    let message: EmailMessageRecord

    var id: String { message.emailID }
    var emailID: String { message.emailID }
}

struct MailThreadRow: Identifiable, Hashable {
    let threadKey: String
    let messages: [EmailMessageRecord]

    var id: String { threadKey }
    var latestMessage: EmailMessageRecord { messages.last ?? messages[0] }
    var subject: String { latestMessage.subject.isEmpty ? "(No subject)" : latestMessage.subject }
    var previewText: String {
        latestMessage.preview?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ?? latestMessage.bodyText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ?? "No preview available"
    }
    var attachmentCount: Int { messages.reduce(0) { $0 + $1.attachmentCount } }
    var latestTimestamp: String { latestMessage.receivedAt }
    var accountID: String { latestMessage.accountID }
    var mailbox: String { latestMessage.mailbox }
    var messageRows: [MailThreadMessageRow] { messages.map(MailThreadMessageRow.init(message:)) }
    var senderLabel: String { messages.last.map { Self.shortSender(from: $0.sender) } ?? "Unknown sender" }
    var participantLabel: String { Self.participantsLabel(messages: messages) }
    var uniqueSenderCount: Int { Set(messages.map { Self.shortSender(from: $0.sender) }).count }

    func shareState(sharedEmailIDs: Set<String>) -> MailThreadShareState {
        let sharedCount = messages.reduce(into: 0) { total, message in
            if sharedEmailIDs.contains(message.emailID) {
                total += 1
            }
        }
        if sharedCount == 0 { return .off }
        if sharedCount == messages.count { return .on }
        return .mixed
    }

    static func group(messages: [EmailMessageRecord]) -> [MailThreadRow] {
        let grouped = Dictionary(grouping: messages) { message in
            threadKey(for: message)
        }

        return grouped.map { key, groupedMessages in
            let ordered = groupedMessages.sorted { lhs, rhs in
                MailDate.comparatorAscending(lhs: lhs, rhs: rhs)
            }
            return MailThreadRow(threadKey: key, messages: ordered)
        }
        .sorted { lhs, rhs in
            MailDate.comparatorDescending(lhs: lhs.latestMessage, rhs: rhs.latestMessage)
        }
    }

    static func threadKey(for message: EmailMessageRecord) -> String {
        if let reference = firstNormalizedReference(from: message.referencesHeader) {
            return reference
        }
        if let inReplyTo = normalizeMessageID(message.inReplyTo) {
            return inReplyTo
        }
        if let messageID = normalizeMessageID(message.messageIDHeader) {
            return messageID
        }
        return message.emailID
    }

    private static func firstNormalizedReference(from referencesHeader: String?) -> String? {
        guard let referencesHeader else { return nil }
        let parts = referencesHeader
            .components(separatedBy: .whitespacesAndNewlines)
            .flatMap { $0.split(separator: ",") }
            .map(String.init)
        return parts.compactMap(normalizeMessageID).first
    }

    private static func normalizeMessageID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    static func shortSender(from sender: String) -> String {
        let trimmed = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        if let angleRange = trimmed.range(of: "<") {
            let prefix = trimmed[..<angleRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            return prefix.isEmpty ? trimmed : prefix
        }
        return trimmed
    }

    private static func participantsLabel(messages: [EmailMessageRecord]) -> String {
        let uniqueSenders = Array(NSOrderedSet(array: messages.map { shortSender(from: $0.sender) })) as? [String] ?? []
        switch uniqueSenders.count {
        case 0:
            return "No senders"
        case 1:
            return uniqueSenders[0]
        case 2:
            return "\(uniqueSenders[0]), \(uniqueSenders[1])"
        default:
            let visible = uniqueSenders.prefix(2).joined(separator: ", ")
            return "\(visible) + \(uniqueSenders.count - 2) others"
        }
    }
}

private enum MailDate {
    static func parse(_ rawValue: String) -> Date {
        ISO8601DateFormatter.shared.date(from: rawValue) ?? .distantPast
    }

    static func comparatorDescending(lhs: EmailMessageRecord, rhs: EmailMessageRecord) -> Bool {
        parse(lhs.receivedAt) > parse(rhs.receivedAt)
    }

    static func comparatorAscending(lhs: EmailMessageRecord, rhs: EmailMessageRecord) -> Bool {
        parse(lhs.receivedAt) < parse(rhs.receivedAt)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
