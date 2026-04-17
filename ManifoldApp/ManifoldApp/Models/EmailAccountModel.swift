// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "email-accounts")

@Observable
@MainActor
final class MailAccountsModel {
    var accounts: [EmailAccountRecord] = []
    var syncStates: [String: [SyncStateRecord]] = [:]
    var totalMessageCount: Int = 0
    var mailboxRefreshToken: Int = 0
    var lastQueryError: String?

    /// Whether any account is currently syncing.
    var isSyncing: Bool {
        syncStates.values.contains { states in states.contains { $0.syncStatus == .syncing } }
    }

    private var client: (any RuntimeClientProtocol)?
    private var backupInfo: EmailBackupInfo?

    init() {}

    func configure(client: any RuntimeClientProtocol) {
        self.client = client
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
                lastQueryError = result.errors.joined(separator: ", ")
            } else {
                lastQueryError = nil
            }
        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
            lastQueryError = error.localizedDescription
        }
        await loadAccounts()
    }

    func messages(accountID: String, limit: Int = 200) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        do {
            let result = try await client.emailMessages(
                accountID: accountID,
                mailbox: nil,
                ids: nil,
                limit: limit
            )
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func allMessages(limit: Int = 500) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        do {
            let result = try await client.emailMessages(
                accountID: nil,
                mailbox: nil,
                ids: nil,
                limit: limit
            )
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func messages(ids: [String]) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        do {
            let result = try await client.emailMessages(
                accountID: nil,
                mailbox: nil,
                ids: ids,
                limit: max(ids.count, 500)
            )
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func domainCounts() async -> [String: Int] {
        guard let client else { return [:] }
        return (try? await client.domainCounts()) ?? [:]
    }

    func readEmail(emlPath: String?) -> MIMEParser.ParsedEmail? {
        guard let path = emlPath, !path.isEmpty else { return nil }
        guard let data = EmailSyncEngine.readStoredMessage(at: path) else { return nil }
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
        do {
            let result = try await client.imapMailboxes(accountID: accountID)
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func messagesInMailbox(accountID: String, mailbox: String, limit: Int = 500) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        let resolvedMailbox = await resolvedMailboxName(accountID: accountID, requestedName: mailbox)
        do {
            let result = try await client.emailMessages(
                accountID: accountID,
                mailbox: resolvedMailbox,
                ids: nil,
                limit: limit
            )
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
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
        do {
            let result = try await client.sharedEmailIDs()
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func sharedEmails(limit: Int = 500) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        do {
            let result = try await client.sharedEmails(limit: limit)
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func shareEmails(emailIDs: [String]) async {
        guard let client else { return }
        do {
            try await client.shareEmails(emailIDs: emailIDs)
            lastQueryError = nil
        } catch {
            lastQueryError = error.localizedDescription
        }
    }

    func unshareEmails(emailIDs: [String]) async {
        guard let client else { return }
        do {
            try await client.unshareEmails(emailIDs: emailIDs)
            lastQueryError = nil
        } catch {
            lastQueryError = error.localizedDescription
        }
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
        do {
            let result = try await client.searchEmailMessages(
                tokens: tokens,
                freeText: freeText,
                accountID: accountID,
                mailbox: mailbox,
                filter: filter,
                sortKey: sortKey,
                limit: limit
            )
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
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
