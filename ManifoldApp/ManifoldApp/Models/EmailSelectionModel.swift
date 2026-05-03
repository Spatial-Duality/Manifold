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
    var pageSize: Int = 25
    var pageIndex: Int = 0
    var totalMessageCount: Int = 0
    var sharedEmailIDsByAgent: [TargetApp: Set<String>] = [:]
    var connectedAgents: [TargetApp] = []
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

    var pageOffset: Int { pageIndex * pageSize }

    var maxPageIndex: Int {
        guard pageSize > 0, totalMessageCount > 0 else { return 0 }
        return max(0, (totalMessageCount - 1) / pageSize)
    }

    var canPageBackward: Bool { pageIndex > 0 }
    var canPageForward: Bool { pageIndex < maxPageIndex }

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
        let nextAccountID = resolvedAccountID(from: accounts)
        if selectedAccountID != nextAccountID {
            pageIndex = 0
        }
        selectedAccountID = nextAccountID

        if let accountID = selectedAccountID {
            let defaultCandidates: [IMAPMailboxRecord]
            if let selectedAccount = accounts.first(where: { $0.accountID == accountID }) {
                defaultCandidates = sidebarMailboxes(for: selectedAccount).map(\.mailbox)
            } else {
                defaultCandidates = selectableMailboxes(for: accountID)
            }
            if force || selectedMailboxName == nil || !defaultCandidates.contains(where: { $0.mailboxName == selectedMailboxName }) {
                let nextMailbox = defaultMailboxName(from: defaultCandidates)
                if selectedMailboxName != nextMailbox {
                    pageIndex = 0
                }
                selectedMailboxName = nextMailbox
            }
        }

        await refreshSharedState()
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

    func applyStoredPaging(pageSize storedPageSize: Int, pageIndex storedPageIndex: Int) async {
        let normalizedSize = Self.normalizedPageSize(storedPageSize)
        let normalizedIndex = max(0, storedPageIndex)
        guard pageSize != normalizedSize || pageIndex != normalizedIndex else { return }
        pageSize = normalizedSize
        pageIndex = normalizedIndex
        await reloadVisibleMessages()
    }

    func setPageSize(_ size: Int) async {
        let normalized = Self.normalizedPageSize(size)
        guard pageSize != normalized else { return }
        pageSize = normalized
        pageIndex = 0
        await reloadVisibleMessages()
    }

    func setPageIndex(_ index: Int) async {
        let clamped = min(max(0, index), maxPageIndex)
        guard pageIndex != clamped else { return }
        pageIndex = clamped
        await reloadVisibleMessages()
    }

    func previousPage() async {
        await setPageIndex(pageIndex - 1)
    }

    func nextPage() async {
        await setPageIndex(pageIndex + 1)
    }

    func resetPageAndReload() async {
        pageIndex = 0
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
        pageIndex = 0
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
        pageIndex = 0
        await ensureMailboxesLoaded(for: [accountID], force: false)
        if let account = mailAccounts?.accounts.first(where: { $0.accountID == accountID }) {
            selectedMailboxName = defaultMailboxName(from: sidebarMailboxes(for: account).map(\.mailbox))
        } else {
            selectedMailboxName = defaultMailboxName(from: selectableMailboxes(for: accountID))
        }
        await reloadVisibleMessages()
    }

    func selectMailbox(_ mailboxName: String) async {
        guard selectedMailboxName != mailboxName else { return }
        selectedMailboxName = mailboxName
        pageIndex = 0
        selectedThreadKey = nil
        selectedMessageID = nil
        await reloadVisibleMessages()
    }

    /// Pushed in by the view when the activated-AI list changes; refreshes
    /// the per-agent shared sets so chips line up.
    func setConnectedAgents(_ agents: [TargetApp]) async {
        guard connectedAgents != agents else { return }
        connectedAgents = agents
        await refreshSharedState()
    }

    func setQuickFilter(_ filter: QuickFilter?) async {
        let nextFilter = activeQuickFilter == filter ? nil : filter
        guard activeQuickFilter != nextFilter else { return }
        activeQuickFilter = nextFilter
        pageIndex = 0
        selectedThreadKey = nil
        selectedMessageID = nil
        await reloadVisibleMessages()
    }

    func updateSearchText(_ text: String) {
        searchText = text
        pageIndex = 0
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

    func setThreadShared(_ thread: MailThreadRow, agent: TargetApp, isShared: Bool) async {
        guard let mailAccounts else { return }
        let ids = thread.messages.map(\.emailID)
        if isShared {
            await mailAccounts.shareEmails(emailIDs: ids, for: agent)
        } else {
            await mailAccounts.unshareEmails(emailIDs: ids, for: agent)
        }
        await refreshSharedState()
    }

    func setMessageShared(_ emailID: String, agent: TargetApp, isShared: Bool) async {
        guard let mailAccounts else { return }
        if isShared {
            await mailAccounts.shareEmails(emailIDs: [emailID], for: agent)
        } else {
            await mailAccounts.unshareEmails(emailIDs: [emailID], for: agent)
        }
        await refreshSharedState()
    }

    func setMessageSharedForAllAgents(_ emailID: String, isShared: Bool) async {
        for agent in connectedAgents {
            await setMessageShared(emailID, agent: agent, isShared: isShared)
        }
    }

    func isShared(_ emailID: String, agent: TargetApp) -> Bool {
        sharedEmailIDsByAgent[agent, default: []].contains(emailID)
    }

    func sharedAgents(for emailID: String) -> Set<TargetApp> {
        var result: Set<TargetApp> = []
        for agent in connectedAgents {
            if isShared(emailID, agent: agent) { result.insert(agent) }
        }
        return result
    }

    /// Count of messages in `messages` shared with at least one connected
    /// AI. Cached because the toolbar summary line reads it on every body
    /// pass — recomputing the Set each time was N-message + N-agent work
    /// per render.
    private(set) var sharedAnyAgentCount: Int = 0

    private func recomputeSharedAnyAgentCount() {
        let known = Set(messages.map(\.emailID))
        var union: Set<String> = []
        for agent in connectedAgents {
            union.formUnion(sharedEmailIDsByAgent[agent, default: []].intersection(known))
        }
        let next = union.count
        if next != sharedAnyAgentCount { sharedAnyAgentCount = next }
    }

    func mailboxes(for accountID: String) -> [IMAPMailboxRecord] {
        (mailboxesByAccountID[accountID] ?? []).sorted(by: mailboxComparator)
    }

    func sidebarMailboxes(for account: EmailAccountRecord) -> [MailSidebarMailbox] {
        MailboxSidebarPresentation.present(
            mailboxes: (mailboxesByAccountID[account.accountID] ?? [])
                .sorted(by: mailboxComparator)
                .filter(\.isSelectable),
            provider: account.provider
        )
    }

    func shareState(for thread: MailThreadRow, agent: TargetApp) -> MailThreadShareState {
        thread.shareState(sharedEmailIDs: sharedEmailIDsByAgent[agent, default: []])
    }

    func shareState(for emailID: String, agent: TargetApp) -> MailThreadShareState {
        isShared(emailID, agent: agent) ? .on : .off
    }

    private func reloadVisibleMessages() async {
        guard let mailAccounts, let accountID = selectedAccountID else {
            messages = []
            totalMessageCount = 0
            errorMessage = nil
            return
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isRawSearch = !trimmedSearch.isEmpty

        let scopedMailbox: String?
        if isRawSearch {
            scopedMailbox = nil
        } else if let mailbox = selectedMailboxName {
            scopedMailbox = mailbox
        } else {
            messages = []
            totalMessageCount = 0
            errorMessage = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        var page = await mailAccounts.messagePage(
            freeText: trimmedSearch,
            accountID: isRawSearch ? nil : accountID,
            mailbox: scopedMailbox,
            filter: isRawSearch ? nil : activeQuickFilter,
            sortKey: .date,
            limit: pageSize,
            offset: pageOffset
        )
        if page.messages.isEmpty, page.totalCount > 0, pageIndex > 0 {
            pageIndex = max(0, (page.totalCount - 1) / max(pageSize, 1))
            page = await mailAccounts.messagePage(
                freeText: trimmedSearch,
                accountID: isRawSearch ? nil : accountID,
                mailbox: scopedMailbox,
                filter: isRawSearch ? nil : activeQuickFilter,
                sortKey: .date,
                limit: pageSize,
                offset: pageOffset
            )
        }

        messages = page.messages
        totalMessageCount = page.totalCount
        errorMessage = mailAccounts.lastQueryError
        await refreshSharedState()
        reconcileSelection()
    }

    private func refreshSharedState() async {
        guard let mailAccounts else { return }
        // mailAccounts is @MainActor, so a TaskGroup wouldn't actually
        // parallelize — every await would hop back to the main actor and
        // serialize. Keep the loop and just add a same-value short-circuit
        // so @Observable doesn't fire when the result hasn't changed.
        var next: [TargetApp: Set<String>] = [:]
        for agent in connectedAgents {
            next[agent] = await mailAccounts.sharedEmailIDs(agent: agent)
        }
        if next != sharedEmailIDsByAgent { sharedEmailIDsByAgent = next }
        recomputeSharedAnyAgentCount()
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
        pageIndex = 0
        totalMessageCount = 0
        sharedEmailIDsByAgent = [:]
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

    private static func normalizedPageSize(_ value: Int) -> Int {
        [25, 50, 75].contains(value) ? value : 25
    }
}

struct MailSidebarMailbox: Identifiable, Hashable {
    let mailbox: IMAPMailboxRecord
    let displayName: String

    var id: String { mailbox.id }
    var mailboxName: String { mailbox.mailboxName }
    var folderType: IMAPMailboxRecord.FolderType { mailbox.folderType }
    var systemImage: String { folderType.systemImage }
    var helpText: String? {
        mailbox.mailboxName == displayName ? nil : "IMAP mailbox: \(mailbox.mailboxName)"
    }
}

private enum MailboxSidebarPresentation {
    private static let systemOrder: [IMAPMailboxRecord.FolderType] = [
        .inbox,
        .sent,
        .drafts,
        .flagged,
        .archive,
        .junk,
        .trash,
    ]

    static func present(
        mailboxes: [IMAPMailboxRecord],
        provider: EmailProvider
    ) -> [MailSidebarMailbox] {
        let candidates = mailboxes.filter { !isHiddenSystemView($0, provider: provider) }
        var rows: [MailSidebarMailbox] = []
        var representedIDs = Set<String>()

        for folderType in systemOrder {
            let typed = candidates.filter { $0.folderType == folderType }
            guard let mailbox = typed.min(by: { lhs, rhs in
                isPreferred(lhs, over: rhs, folderType: folderType, provider: provider)
            }) else {
                continue
            }
            rows.append(MailSidebarMailbox(mailbox: mailbox, displayName: displayName(for: folderType)))
            representedIDs.insert(mailbox.id)
        }

        let customRows = candidates
            .filter { $0.folderType == .other && !representedIDs.contains($0.id) }
            .sorted(by: rawMailboxComparator)
            .map { mailbox in
                MailSidebarMailbox(mailbox: mailbox, displayName: cleanedDisplayName(for: mailbox))
            }

        return rows + customRows
    }

    private static func isHiddenSystemView(_ mailbox: IMAPMailboxRecord, provider: EmailProvider) -> Bool {
        guard provider == .gmail else { return false }
        let flags = normalizedFlags(mailbox)
        if flags.contains("\\all") || flags.contains("\\important") || flags.contains("\\flagged") {
            return true
        }

        let normalizedName = normalizedMailboxName(mailbox.mailboxName)
            .replacingOccurrences(of: "[google mail]/", with: "[gmail]/")
        return normalizedName == "[gmail]/all mail"
            || normalizedName == "[gmail]/important"
            || normalizedName == "[gmail]/starred"
    }

    private static func isPreferred(
        _ lhs: IMAPMailboxRecord,
        over rhs: IMAPMailboxRecord,
        folderType: IMAPMailboxRecord.FolderType,
        provider: EmailProvider
    ) -> Bool {
        let lhsScore = preferenceScore(lhs, folderType: folderType, provider: provider)
        let rhsScore = preferenceScore(rhs, folderType: folderType, provider: provider)
        if lhsScore != rhsScore {
            return lhsScore < rhsScore
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.mailboxName.count != rhs.mailboxName.count {
            return lhs.mailboxName.count < rhs.mailboxName.count
        }
        return lhs.mailboxName.localizedCaseInsensitiveCompare(rhs.mailboxName) == .orderedAscending
    }

    private static func preferenceScore(
        _ mailbox: IMAPMailboxRecord,
        folderType: IMAPMailboxRecord.FolderType,
        provider: EmailProvider
    ) -> Int {
        var score = 1_000
        if hasSpecialUseFlag(mailbox, folderType: folderType) {
            score -= 500
        }
        if provider == .gmail, isUnderGmailSystemRoot(mailbox.mailboxName) {
            score -= 100
        }
        if canonicalAliases(for: folderType).contains(mailboxLeaf(mailbox.mailboxName)) {
            score -= 50
        }
        return score
    }

    private static func hasSpecialUseFlag(
        _ mailbox: IMAPMailboxRecord,
        folderType: IMAPMailboxRecord.FolderType
    ) -> Bool {
        let flags = normalizedFlags(mailbox)
        switch folderType {
        case .inbox:
            return flags.contains("\\inbox") || normalizedMailboxName(mailbox.mailboxName) == "inbox"
        case .sent:
            return flags.contains("\\sent")
        case .drafts:
            return flags.contains("\\drafts")
        case .trash:
            return flags.contains("\\trash")
        case .junk:
            return flags.contains("\\junk")
        case .archive:
            return flags.contains("\\archive") || flags.contains("\\all")
        case .flagged:
            return flags.contains("\\flagged")
        case .other:
            return false
        }
    }

    private static func displayName(for folderType: IMAPMailboxRecord.FolderType) -> String {
        switch folderType {
        case .inbox: "Inbox"
        case .sent: "Sent"
        case .drafts: "Drafts"
        case .trash: "Trash"
        case .junk: "Junk"
        case .archive: "Archive"
        case .flagged: "Flagged"
        case .other: "Mailbox"
        }
    }

    private static func canonicalAliases(for folderType: IMAPMailboxRecord.FolderType) -> Set<String> {
        switch folderType {
        case .inbox:
            return ["inbox"]
        case .sent:
            return ["sent", "sent mail", "sent messages", "sent items"]
        case .drafts:
            return ["drafts", "draft messages", "draft items"]
        case .trash:
            return ["trash", "deleted messages", "deleted items", "bin"]
        case .junk:
            return ["junk", "spam"]
        case .archive:
            return ["archive", "all mail", "all messages"]
        case .flagged:
            return ["flagged", "starred"]
        case .other:
            return []
        }
    }

    private static func cleanedDisplayName(for mailbox: IMAPMailboxRecord) -> String {
        let name = mailbox.mailboxName.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["[Gmail]/", "[Google Mail]/"] {
            if name.lowercased().hasPrefix(prefix.lowercased()) {
                let stripped = String(name.dropFirst(prefix.count))
                return stripped.isEmpty ? name : stripped
            }
        }
        return name.isEmpty ? mailbox.mailboxName : name
    }

    private static func normalizedFlags(_ mailbox: IMAPMailboxRecord) -> Set<String> {
        Set(mailbox.flags.map { flag in
            flag.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\\\", with: "\\")
                .lowercased()
        })
    }

    private static func normalizedMailboxName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func mailboxLeaf(_ name: String) -> String {
        normalizedMailboxName(name)
            .split(separator: "/")
            .last
            .map(String.init) ?? normalizedMailboxName(name)
    }

    private static func isUnderGmailSystemRoot(_ name: String) -> Bool {
        let normalized = normalizedMailboxName(name)
        return normalized.hasPrefix("[gmail]/") || normalized.hasPrefix("[google mail]/")
    }

    private static func rawMailboxComparator(lhs: IMAPMailboxRecord, rhs: IMAPMailboxRecord) -> Bool {
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
        MailDateNormalizer.parse(rawValue) ?? .distantPast
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
