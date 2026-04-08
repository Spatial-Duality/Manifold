import Foundation
import ManifoldKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "email-accounts")

@Observable
@MainActor
final class EmailAccountModel {
    var accounts: [EmailAccountRecord] = []
    var syncStates: [String: [SyncStateRecord]] = [:]  // accountID -> states
    var isAddingAccount = false
    var selectedAccountID: String?  // for detail popover
    var totalMessageCount: Int = 0

    private var emailStore: EmailStore?
    private var syncEngine: EmailSyncEngine?

    init() {}

    func configure(
        emailStore: EmailStore,
        syncEngine: EmailSyncEngine
    ) {
        self.emailStore = emailStore
        self.syncEngine = syncEngine

        Task { await loadAccounts() }
    }

    // MARK: - Account CRUD

    func loadAccounts() async {
        guard let emailStore else { return }
        do {
            accounts = try await emailStore.allEmailAccounts()
            for account in accounts {
                syncStates[account.accountID] = try await emailStore.syncStates(accountID: account.accountID)
            }
            totalMessageCount = try await emailStore.emailMessageCount()
        } catch {
            logger.error("Failed to load email accounts: \(error.localizedDescription)")
            accounts = []
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
        guard let emailStore, let syncEngine else { return "Stores not initialized" }

        do {
            // Phase 1: Validate connection BEFORE persisting anything.
            let conn = IMAPConnection(host: server, port: UInt16(port))
            try await conn.connect()
            try await conn.login(username: username, password: password)
            await conn.disconnect()

            // Phase 2: Connection validated — now persist the account.
            let account = try await emailStore.addEmailAccount(
                displayName: displayName,
                providerType: provider.rawValue,
                server: server,
                port: port,
                username: username,
                authType: "password",
                keychainRef: nil,
                syncIntervalSeconds: 300
            )

            // Phase 3: Store credential in Keychain.
            guard KeychainHelper.store(accountID: account.accountID, credential: password) else {
                try? await emailStore.removeEmailAccount(id: account.accountID)
                return "Failed to store credentials securely"
            }

            // Phase 4: Register for background sync.
            await syncEngine.register(accountID: account.accountID)

            await loadAccounts()
            logger.info("Added email account: \(displayName)")
            return nil
        } catch {
            logger.error("Failed to add email account: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    func removeAccount(id: String) async {
        guard let emailStore, let syncEngine else { return }
        await syncEngine.unregister(accountID: id)
        KeychainHelper.delete(accountID: id)
        do {
            try await emailStore.removeEmailAccount(id: id)
        } catch {
            logger.error("Failed to remove account: \(error.localizedDescription)")
        }
        await loadAccounts()
    }

    func toggleSync(accountID: String, enabled: Bool) async {
        guard let emailStore, let syncEngine else { return }
        do {
            try await emailStore.setEmailAccountSyncEnabled(accountID: accountID, enabled: enabled)
            if enabled {
                await syncEngine.register(accountID: accountID)
            } else {
                await syncEngine.unregister(accountID: accountID)
            }
            await loadAccounts()
        } catch {
            logger.error("Failed to toggle sync: \(error.localizedDescription)")
        }
    }

    func syncNow(accountID: String) async {
        guard let syncEngine else { return }
        do {
            let result = try await syncEngine.syncNow(accountID: accountID)
            if !result.isSuccess {
                logger.warning("Sync errors: \(result.errors.joined(separator: ", "))")
            }
        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
        }
        await loadAccounts()
    }

    // MARK: - Messages

    func messages(accountID: String, limit: Int = 200) async -> [EmailMessageRecord] {
        guard let emailStore else { return [] }
        do {
            return try await emailStore.emailMessages(accountID: accountID, limit: limit)
        } catch {
            logger.error("Failed to load messages: \(error.localizedDescription)")
            return []
        }
    }

    func allMessages(limit: Int = 500) async -> [EmailMessageRecord] {
        guard let emailStore else { return [] }
        do {
            return try await emailStore.allEmailMessages(limit: limit)
        } catch {
            logger.error("Failed to load all messages: \(error.localizedDescription)")
            return []
        }
    }

    func messages(accountID: String, mailbox: String, limit: Int = 500) async -> [EmailMessageRecord] {
        guard let emailStore else { return [] }
        do {
            return try await emailStore.emailMessages(accountID: accountID, mailbox: mailbox, limit: limit)
        } catch {
            logger.error("Failed to load mailbox messages: \(error.localizedDescription)")
            return []
        }
    }

    func mailboxes(accountID: String) async -> [(name: String, count: Int)] {
        guard let emailStore else { return [] }
        do {
            return try await emailStore.mailboxes(accountID: accountID)
        } catch {
            logger.error("Failed to load mailboxes: \(error.localizedDescription)")
            return []
        }
    }

    /// Read and parse a .eml file from disk.
    func readEmail(emlPath: String?) -> MIMEParser.ParsedEmail? {
        guard let path = emlPath, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return MIMEParser.parse(data: data)
    }

    // MARK: - Unread Counts

    func unreadCountAll() async -> Int {
        guard let emailStore else { return 0 }
        return (try? await emailStore.unreadCountAll()) ?? 0
    }

    func unreadCount(accountID: String) async -> Int {
        guard let emailStore else { return 0 }
        return (try? await emailStore.unreadCount(accountID: accountID)) ?? 0
    }

    func unreadCount(accountID: String, mailbox: String) async -> Int {
        guard let emailStore else { return 0 }
        return (try? await emailStore.unreadCount(accountID: accountID, mailbox: mailbox)) ?? 0
    }

    // MARK: - IMAP Mailboxes

    func imapMailboxes(accountID: String) async -> [IMAPMailboxRecord] {
        guard let emailStore else { return [] }
        return (try? await emailStore.imapMailboxes(accountID: accountID)) ?? []
    }

    // MARK: - Messages (via membership)

    func messagesInMailbox(accountID: String, mailbox: String, limit: Int = 500) async -> [EmailMessageRecord] {
        guard let emailStore else { return [] }
        return (try? await emailStore.messagesInMailbox(accountID: accountID, mailbox: mailbox, limit: limit)) ?? []
    }

    // MARK: - Shared Emails

    func sharedEmailCount() async -> Int {
        guard let emailStore else { return 0 }
        return (try? await emailStore.sharedEmailCount()) ?? 0
    }

    func sharedEmailIDs() async -> Set<String> {
        guard let emailStore else { return [] }
        return (try? await emailStore.sharedEmailIDs()) ?? []
    }

    func sharedEmails(limit: Int = 500) async -> [EmailMessageRecord] {
        guard let emailStore else { return [] }
        return (try? await emailStore.sharedEmails(limit: limit)) ?? []
    }

    func shareEmails(emailIDs: [String]) async {
        guard let emailStore else { return }
        try? await emailStore.shareEmails(emailIDs: emailIDs)
    }

    func unshareEmails(emailIDs: [String]) async {
        guard let emailStore else { return }
        try? await emailStore.unshareEmails(emailIDs: emailIDs)
    }

    func unshareAllEmails() async {
        guard let emailStore else { return }
        try? await emailStore.unshareAllEmails()
    }

    // MARK: - Read/Flag State

    func updateReadState(emailID: String, isRead: Bool) async {
        guard let emailStore else { return }
        try? await emailStore.updateEmailReadState(emailID: emailID, isRead: isRead)
    }

    func updateFlagState(emailID: String, isFlagged: Bool, flagColor: String? = nil) async {
        guard let emailStore else { return }
        try? await emailStore.updateEmailFlagState(emailID: emailID, isFlagged: isFlagged, flagColor: flagColor)
    }

    func batchUpdateReadState(emailIDs: [String], isRead: Bool) async {
        guard let emailStore else { return }
        try? await emailStore.batchUpdateReadState(emailIDs: emailIDs, isRead: isRead)
    }

    func batchUpdateFlagState(emailIDs: [String], isFlagged: Bool, flagColor: String? = nil) async {
        guard let emailStore else { return }
        try? await emailStore.batchUpdateFlagState(emailIDs: emailIDs, isFlagged: isFlagged, flagColor: flagColor)
    }

    // MARK: - Search

    func searchMessages(
        tokens: [SearchToken] = [],
        freeText: String = "",
        accountID: String? = nil,
        mailbox: String? = nil,
        filter: QuickFilter? = nil,
        sortKey: EmailSortKey = .date,
        limit: Int = 500
    ) async -> [EmailMessageRecord] {
        guard let emailStore else { return [] }
        return (try? await emailStore.searchEmailMessages(
            tokens: tokens, freeText: freeText,
            accountID: accountID, mailbox: mailbox,
            filter: filter, sortKey: sortKey, limit: limit
        )) ?? []
    }

    // MARK: - Smart Mailboxes

    func createSmartMailbox(displayName: String, iconName: String = "tray", rulesJSON: String = "[]") async throws {
        guard let emailStore else { return }
        try await emailStore.createSmartMailbox(displayName: displayName, iconName: iconName, rulesJSON: rulesJSON)
    }

    func allSmartMailboxes() async throws -> [SmartMailboxRecord] {
        guard let emailStore else { return [] }
        return try await emailStore.allSmartMailboxes()
    }

    func updateSmartMailbox(mailboxID: String, displayName: String, iconName: String, rulesJSON: String) async throws {
        guard let emailStore else { return }
        try await emailStore.updateSmartMailbox(mailboxID: mailboxID, displayName: displayName, iconName: iconName, rulesJSON: rulesJSON)
    }

    func deleteSmartMailbox(mailboxID: String) async throws {
        guard let emailStore else { return }
        try await emailStore.deleteSmartMailbox(mailboxID: mailboxID)
    }

    // MARK: - Backup Info

    var backupRootPath: String {
        EmailSyncEngine.backupRoot.path
    }

    var backupDiskUsage: Int64 {
        let root = EmailSyncEngine.backupRoot
        guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }

    // MARK: - Startup Registration

    /// Re-register all sync-enabled accounts with the sync engine on app launch.
    /// Also starts FTS5 body text backfill for existing emails.
    func registerAllAccounts() async {
        guard let emailStore, let syncEngine else { return }
        do {
            let allAccounts = try await emailStore.allEmailAccounts()
            for account in allAccounts where account.syncEnabled {
                await syncEngine.register(accountID: account.accountID)
            }
            // Start background FTS5 body text backfill for pre-existing emails
            await syncEngine.startBackfill()
        } catch {
            logger.error("Failed to register accounts on startup: \(error.localizedDescription)")
        }
    }
}
