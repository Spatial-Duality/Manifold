import Foundation
import ManifoldKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "email-accounts")

@Observable
@MainActor
final class EmailAccountModel {
    var accounts: [EmailAccountRecord] = []
    var syncStates: [String: [SyncStateRecord]] = [:]
    var totalMessageCount: Int = 0
    var mailboxRefreshToken: Int = 0

    /// Whether any account is currently syncing.
    var isSyncing: Bool {
        syncStates.values.contains { states in states.contains { $0.syncStatus == .syncing } }
    }

    private var client: AppRuntimeClient?
    private var backupInfo: EmailBackupInfo?

    init() {}

    func configure(client: AppRuntimeClient) {
        self.client = client
        Task { await loadAccounts() }
    }

    func loadAccounts() async {
        guard let client else { return }
        do {
            let fetchedAccounts = try await client.listEmailAccounts()
            let fetchedMessageCount = try await client.emailMessageCount()
            let fetchedBackupInfo = try? await client.emailBackupInfo()
            var nextStates: [String: [SyncStateRecord]] = [:]
            for account in fetchedAccounts {
                nextStates[account.accountID] = try await client.syncStates(accountID: account.accountID)
            }
            accounts = fetchedAccounts
            totalMessageCount = fetchedMessageCount
            backupInfo = fetchedBackupInfo
            syncStates = nextStates
            mailboxRefreshToken &+= 1
        } catch {
            logger.error("Failed to load email accounts: \(error.localizedDescription)")
        }
    }

    func addIMAPAccount(
        displayName: String,
        provider: EmailProvider,
        server: String,
        port: Int,
        username: String,
        password: String
    ) async -> String? {
        guard let client else { return "Runtime unavailable" }
        do {
            _ = try await client.addIMAPAccount(
                displayName: displayName,
                provider: provider,
                server: server,
                port: port,
                username: username,
                password: password
            )
            await loadAccounts()
            return nil
        } catch {
            logger.error("Failed to add email account: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    func removeAccount(id: String) async {
        guard let client else { return }
        do {
            try await client.removeEmailAccount(id: id)
        } catch {
            logger.error("Failed to remove account: \(error.localizedDescription)")
        }
        await loadAccounts()
    }

    func toggleSync(accountID: String, enabled: Bool) async {
        guard let client else { return }
        do {
            try await client.toggleEmailSync(accountID: accountID, enabled: enabled)
            await loadAccounts()
        } catch {
            logger.error("Failed to toggle sync: \(error.localizedDescription)")
        }
    }

    func syncNow(accountID: String) async {
        guard let client else { return }
        do {
            let result = try await client.syncEmailNow(accountID: accountID)
            if !result.isSuccess {
                logger.warning("Sync errors: \(result.errors.joined(separator: ", "))")
            }
        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
        }
        await loadAccounts()
    }

    func messages(accountID: String, limit: Int = 200) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        return (try? await client.emailMessages(accountID: accountID, limit: limit)) ?? []
    }

    func allMessages(limit: Int = 500) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        return (try? await client.emailMessages(limit: limit)) ?? []
    }

    func messages(ids: [String]) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        return (try? await client.emailMessages(ids: ids)) ?? []
    }

    func domainCounts() async -> [String: Int] {
        guard let client else { return [:] }
        return (try? await client.domainCounts()) ?? [:]
    }

    func readEmail(emlPath: String?) -> MIMEParser.ParsedEmail? {
        guard let path = emlPath, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return MIMEParser.parse(data: data)
    }

    func unreadCountAll() async -> Int {
        guard let client else { return 0 }
        return (try? await client.unreadCountAll()) ?? 0
    }

    func unreadCount(accountID: String) async -> Int {
        guard let client else { return 0 }
        return (try? await client.unreadCount(accountID: accountID)) ?? 0
    }

    func unreadCount(accountID: String, mailbox: String) async -> Int {
        guard let client else { return 0 }
        return (try? await client.unreadCount(accountID: accountID, mailbox: mailbox)) ?? 0
    }

    func imapMailboxes(accountID: String) async -> [IMAPMailboxRecord] {
        guard let client else { return [] }
        return (try? await client.imapMailboxes(accountID: accountID)) ?? []
    }

    func messagesInMailbox(accountID: String, mailbox: String, limit: Int = 500) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        let resolvedMailbox = await resolvedMailboxName(accountID: accountID, requestedName: mailbox)
        return (try? await client.emailMessages(accountID: accountID, mailbox: resolvedMailbox, limit: limit)) ?? []
    }

    func resolvedMailboxName(accountID: String, requestedName: String) async -> String {
        let mailboxes = await imapMailboxes(accountID: accountID)
        return MailboxResolver.resolve(requestedName: requestedName, imapMailboxes: mailboxes)
    }

    func sharedEmailCount() async -> Int {
        guard let client else { return 0 }
        return (try? await client.sharedEmailCount()) ?? 0
    }

    func sharedEmailIDs() async -> Set<String> {
        guard let client else { return [] }
        return (try? await client.sharedEmailIDs()) ?? []
    }

    func sharedEmails(limit: Int = 500) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        return (try? await client.sharedEmails(limit: limit)) ?? []
    }

    func shareEmails(emailIDs: [String]) async {
        guard let client else { return }
        try? await client.shareEmails(emailIDs: emailIDs)
    }

    func unshareEmails(emailIDs: [String]) async {
        guard let client else { return }
        try? await client.unshareEmails(emailIDs: emailIDs)
    }

    func unshareAllEmails() async {
        guard let client else { return }
        try? await client.unshareAllEmails()
    }

    func updateReadState(emailID: String, isRead: Bool) async {
        guard let client else { return }
        try? await client.updateEmailReadState(emailID: emailID, isRead: isRead)
    }

    func updateFlagState(emailID: String, isFlagged: Bool, flagColor: String? = nil) async {
        guard let client else { return }
        try? await client.updateEmailFlagState(emailID: emailID, isFlagged: isFlagged, flagColor: flagColor)
    }

    func batchUpdateReadState(emailIDs: [String], isRead: Bool) async {
        guard let client else { return }
        try? await client.batchUpdateReadState(emailIDs: emailIDs, isRead: isRead)
    }

    func batchUpdateFlagState(emailIDs: [String], isFlagged: Bool, flagColor: String? = nil) async {
        guard let client else { return }
        try? await client.batchUpdateFlagState(emailIDs: emailIDs, isFlagged: isFlagged, flagColor: flagColor)
    }

    func searchMessages(
        tokens: [SearchToken] = [],
        freeText: String = "",
        accountID: String? = nil,
        mailbox: String? = nil,
        filter: QuickFilter? = nil,
        sortKey: EmailSortKey = .date,
        limit: Int = 500
    ) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        return (try? await client.searchEmailMessages(
            tokens: tokens,
            freeText: freeText,
            accountID: accountID,
            mailbox: mailbox,
            filter: filter,
            sortKey: sortKey,
            limit: limit
        )) ?? []
    }

    func createSmartMailbox(displayName: String, iconName: String = "tray", rulesJSON: String = "[]") async throws {
        guard let client else { return }
        try await client.createSmartMailbox(displayName: displayName, iconName: iconName, rulesJSON: rulesJSON)
    }

    func allSmartMailboxes() async throws -> [SmartMailboxRecord] {
        guard let client else { return [] }
        return try await client.listSmartMailboxes()
    }

    func updateSmartMailbox(mailboxID: String, displayName: String, iconName: String, rulesJSON: String) async throws {
        guard let client else { return }
        try await client.updateSmartMailbox(
            mailboxID: mailboxID,
            displayName: displayName,
            iconName: iconName,
            rulesJSON: rulesJSON
        )
    }

    func deleteSmartMailbox(mailboxID: String) async throws {
        guard let client else { return }
        try await client.deleteSmartMailbox(mailboxID: mailboxID)
    }

    var backupRootPath: String {
        backupInfo?.path ?? EmailSyncEngine.backupRoot.path
    }
}
