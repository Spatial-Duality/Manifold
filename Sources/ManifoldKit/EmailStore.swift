// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CryptoKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "email-store")

/// Dedicated store for all email backup operations.
/// Extracted from GrantStore to keep email CRUD, search, rule engine, and smart mailbox
/// queries in a focused module. Shares the same DatabaseConnection.
public struct EmailStore: Sendable {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    // MARK: - Email Messages (metadata index for .eml files)

    public func upsertEmailMessage(
        emailID: String,
        accountID: String,
        mailbox: String,
        sender: String,
        senderEmail: String? = nil,
        senderDomain: String? = nil,
        recipients: String,
        cc: String = "",
        subject: String,
        receivedAt: String,
        emlPath: String?,
        sizeBytes: Int,
        preview: String?,
        contentType: String? = nil,
        isRead: Bool = false,
        isFlagged: Bool = false,
        inReplyTo: String? = nil,
        referencesHeader: String? = nil,
        messageIDHeader: String? = nil,
        attachmentCount: Int = 0
    ) throws {
        try db.execute("""
            INSERT INTO email_messages (
                email_id, account, account_id, mailbox, sender, sender_email, sender_domain,
                recipients, cc, subject, received_at, eml_path, size_bytes, preview,
                content_type, is_read, is_flagged, in_reply_to, references_header,
                message_id_header, attachment_count
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(email_id) DO UPDATE SET
                account_id = excluded.account_id,
                mailbox = excluded.mailbox,
                sender = excluded.sender,
                sender_email = COALESCE(excluded.sender_email, email_messages.sender_email),
                sender_domain = COALESCE(excluded.sender_domain, email_messages.sender_domain),
                recipients = excluded.recipients,
                cc = excluded.cc,
                subject = excluded.subject,
                received_at = excluded.received_at,
                eml_path = COALESCE(excluded.eml_path, email_messages.eml_path),
                size_bytes = excluded.size_bytes,
                preview = COALESCE(excluded.preview, email_messages.preview),
                content_type = COALESCE(excluded.content_type, email_messages.content_type),
                is_read = excluded.is_read,
                is_flagged = excluded.is_flagged,
                in_reply_to = COALESCE(excluded.in_reply_to, email_messages.in_reply_to),
                references_header = COALESCE(excluded.references_header, email_messages.references_header),
                message_id_header = COALESCE(excluded.message_id_header, email_messages.message_id_header),
                attachment_count = excluded.attachment_count
        """, params: [
            emailID, accountID, accountID, mailbox, sender, senderEmail, senderDomain,
            recipients, cc, subject, receivedAt, emlPath, "\(sizeBytes)", preview,
            contentType, isRead ? "1" : "0", isFlagged ? "1" : "0",
            inReplyTo, referencesHeader, messageIDHeader, "\(attachmentCount)",
        ])
    }

    public func emailMessages(accountID: String, limit: Int = 500) throws -> [EmailMessageRecord] {
        let rows = try db.queryAll(
            "SELECT * FROM email_messages WHERE account_id = ? ORDER BY received_at DESC LIMIT ?",
            params: [accountID, "\(limit)"]
        )
        return rows.compactMap { EmailMessageRecord(row: $0) }
    }

    public func emailMessages(accountID: String, mailbox: String, limit: Int = 500) throws -> [EmailMessageRecord] {
        let membershipCount = try db.queryScalar(
            "SELECT COUNT(*) FROM email_mailbox_membership WHERE account_id = ? AND mailbox = ?",
            params: [accountID, mailbox]
        ).flatMap(Int.init) ?? 0

        let rows: [[String: String]]
        if membershipCount > 0 {
            rows = try db.queryAll("""
                SELECT DISTINCT em.* FROM email_messages em
                JOIN email_mailbox_membership emm ON em.email_id = emm.email_id
                WHERE emm.account_id = ? AND emm.mailbox = ?
                ORDER BY em.received_at DESC
                LIMIT ?
            """, params: [accountID, mailbox, "\(limit)"])
        } else {
            rows = try db.queryAll(
                "SELECT * FROM email_messages WHERE account_id = ? AND mailbox = ? ORDER BY received_at DESC LIMIT ?",
                params: [accountID, mailbox, "\(limit)"]
            )
        }
        return rows.compactMap { EmailMessageRecord(row: $0) }
    }

    public func mailboxes(accountID: String) throws -> [(name: String, count: Int)] {
        let membershipCount = try db.queryScalar(
            "SELECT COUNT(*) FROM email_mailbox_membership WHERE account_id = ?",
            params: [accountID]
        ).flatMap(Int.init) ?? 0

        let rows: [[String: String]]
        if membershipCount > 0 {
            rows = try db.queryAll("""
                SELECT mailbox, COUNT(DISTINCT email_id) as cnt
                FROM email_mailbox_membership
                WHERE account_id = ?
                GROUP BY mailbox
                ORDER BY mailbox ASC
            """, params: [accountID])
        } else {
            rows = try db.queryAll(
                "SELECT mailbox, COUNT(*) as cnt FROM email_messages WHERE account_id = ? GROUP BY mailbox ORDER BY mailbox ASC",
                params: [accountID]
            )
        }
        return rows.compactMap { row in
            guard let name = row["mailbox"], let countStr = row["cnt"], let count = Int(countStr) else { return nil }
            return (name, count)
        }
    }

    /// Aggregate email counts by sender domain using SQL GROUP BY.
    /// Returns (domain, count) pairs sorted by count descending.
    /// This is O(1) in Swift vs O(N) for loading all messages and counting in memory.
    public func domainCounts() throws -> [(domain: String, count: Int)] {
        let rows = try db.queryAll("""
            SELECT COALESCE(sender_domain, 'unknown') as domain, COUNT(*) as cnt
            FROM email_messages
            GROUP BY domain
            ORDER BY cnt DESC
        """)
        return rows.compactMap { row in
            guard let domain = row["domain"], let cntStr = row["cnt"], let cnt = Int(cntStr) else { return nil }
            return (domain, cnt)
        }
    }

    public func allEmailMessages(limit: Int = 1000) throws -> [EmailMessageRecord] {
        let rows = try db.queryAll(
            "SELECT * FROM email_messages ORDER BY received_at DESC LIMIT ?",
            params: ["\(limit)"]
        )
        return rows.compactMap { EmailMessageRecord(row: $0) }
    }

    public func emailMessages(ids: [String]) throws -> [EmailMessageRecord] {
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let rows = try db.queryAll(
            "SELECT * FROM email_messages WHERE email_id IN (\(placeholders)) ORDER BY received_at DESC",
            params: ids
        )
        return rows.compactMap { EmailMessageRecord(row: $0) }
    }

    public func emailAttachments(emailIDs: [String]? = nil) throws -> [EmailAttachmentRecord] {
        if let emailIDs, emailIDs.isEmpty {
            return []
        }

        let query: String
        let params: [String]
        if let emailIDs {
            let placeholders = emailIDs.map { _ in "?" }.joined(separator: ",")
            query = """
                SELECT * FROM email_attachments
                WHERE email_id IN (\(placeholders))
                ORDER BY filename ASC
            """
            params = emailIDs
        } else {
            query = "SELECT * FROM email_attachments ORDER BY filename ASC"
            params = []
        }

        let rows = try db.queryAll(query, params: params)
        return rows.compactMap { EmailAttachmentRecord(row: $0) }
    }

    public func emailAttachment(id: String) throws -> EmailAttachmentRecord? {
        let rows = try db.queryAll(
            "SELECT * FROM email_attachments WHERE attachment_id = ? LIMIT 1",
            params: [id]
        )
        return rows.first.flatMap { EmailAttachmentRecord(row: $0) }
    }

    public func upsertEmailAttachment(
        attachmentID: String,
        emailID: String,
        filename: String,
        mimeType: String,
        sizeBytes: Int,
        contentHash: String,
        contentID: String? = nil
    ) throws {
        try db.execute(
            """
            INSERT INTO email_attachments (
                attachment_id, email_id, filename, mime_type, size_bytes, content_hash, content_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(attachment_id) DO UPDATE SET
                email_id = excluded.email_id,
                filename = excluded.filename,
                mime_type = excluded.mime_type,
                size_bytes = excluded.size_bytes,
                content_hash = excluded.content_hash,
                content_id = excluded.content_id
            """,
            params: [
                attachmentID,
                emailID,
                filename,
                mimeType,
                "\(sizeBytes)",
                contentHash,
                contentID,
            ]
        )
    }

    public func deleteEmailAttachments(emailID: String) throws {
        try db.execute("DELETE FROM email_attachments WHERE email_id = ?", params: [emailID])
    }

    public func emailMessage(id: String) throws -> EmailMessageRecord? {
        let rows = try db.queryAll(
            "SELECT * FROM email_messages WHERE email_id = ? LIMIT 1",
            params: [id]
        )
        return rows.first.flatMap { EmailMessageRecord(row: $0) }
    }

    public func emailMessageCount() throws -> Int {
        let result = try db.queryScalar("SELECT COUNT(*) FROM email_messages")
        return result.flatMap { Int($0) } ?? 0
    }

    // MARK: - Email Account Management

    @discardableResult
    public func addEmailAccount(
        displayName: String,
        providerType: String,
        server: String?,
        port: Int?,
        username: String?,
        authType: String = "password",
        keychainRef: String? = nil,
        syncIntervalSeconds: Int = 300
    ) throws -> EmailAccountRecord {
        let accountID = "email-\(UUID().uuidString.prefix(8).lowercased())"
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute("""
            INSERT INTO email_accounts (
                account_id, display_name, provider_type, server, port, username,
                auth_type, keychain_ref, sync_enabled, sync_interval_seconds,
                created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
        """, params: [
            accountID, displayName, providerType, server,
            port.map { "\($0)" }, username, authType, keychainRef,
            "\(syncIntervalSeconds)", now, now,
        ])
        guard let created = try emailAccount(id: accountID) else {
            throw ManifoldError.database("Email account \(accountID) not found after insert")
        }
        return created
    }

    public func emailAccount(id: String) throws -> EmailAccountRecord? {
        let rows = try db.queryAll(
            "SELECT * FROM email_accounts WHERE account_id = ? LIMIT 1",
            params: [id]
        )
        return rows.first.flatMap { EmailAccountRecord(row: $0) }
    }

    public func allEmailAccounts() throws -> [EmailAccountRecord] {
        let rows = try db.queryAll("SELECT * FROM email_accounts ORDER BY display_name ASC")
        return rows.compactMap { EmailAccountRecord(row: $0) }
    }

    public func removeEmailAccount(id: String) throws {
        try db.transaction {
            try db.execute("""
                DELETE FROM email_attachments WHERE email_id IN (
                    SELECT email_id FROM email_messages WHERE account_id = ?
                )
            """, params: [id])
            try db.execute("""
                DELETE FROM shared_emails WHERE email_id IN (
                    SELECT email_id FROM email_messages WHERE account_id = ?
                )
            """, params: [id])
            try db.execute("""
                DELETE FROM grant_emails WHERE email_id IN (
                    SELECT email_id FROM email_messages WHERE account_id = ?
                )
            """, params: [id])
            // temporary_reveals usually expire with their work block, but
            // removing an account is a permanent action and any reveals
            // for orphaned email IDs would never resolve to a real
            // message again. Drop them in the same transaction.
            try db.execute("""
                DELETE FROM temporary_reveals WHERE email_id IN (
                    SELECT email_id FROM email_messages WHERE account_id = ?
                )
            """, params: [id])
            // Clean FTS5 entries before deleting rows (content-synced table requires manual sync)
            try db.execute("""
                INSERT INTO email_fts(email_fts, rowid, email_id, body_text)
                SELECT 'delete', rowid, email_id, COALESCE(body_text, '')
                FROM email_messages WHERE account_id = ? AND body_text IS NOT NULL
            """, params: [id])
            try db.execute("DELETE FROM email_mailbox_membership WHERE account_id = ?", params: [id])
            try db.execute("DELETE FROM email_messages WHERE account_id = ?", params: [id])
            try db.execute("DELETE FROM email_messages WHERE account = ?", params: [id])
            try db.execute("DELETE FROM imap_mailboxes WHERE account_id = ?", params: [id])
            try db.execute("DELETE FROM email_sync_state WHERE account_id = ?", params: [id])
            try db.execute("DELETE FROM email_accounts WHERE account_id = ?", params: [id])
        }
        KeychainHelper.delete(accountID: id)
    }

    public func setEmailAccountSyncEnabled(accountID: String, enabled: Bool) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            "UPDATE email_accounts SET sync_enabled = ?, updated_at = ? WHERE account_id = ?",
            params: [enabled ? "1" : "0", now, accountID]
        )
    }

    // MARK: - Email Sync State

    public func syncState(accountID: String, mailbox: String) throws -> SyncStateRecord? {
        let rows = try db.queryAll(
            "SELECT * FROM email_sync_state WHERE account_id = ? AND mailbox_name = ? LIMIT 1",
            params: [accountID, mailbox]
        )
        return rows.first.flatMap { SyncStateRecord(row: $0) }
    }

    public func syncStates(accountID: String) throws -> [SyncStateRecord] {
        let rows = try db.queryAll(
            "SELECT * FROM email_sync_state WHERE account_id = ? ORDER BY mailbox_name ASC",
            params: [accountID]
        )
        return rows.compactMap { SyncStateRecord(row: $0) }
    }

    public func updateSyncState(
        accountID: String,
        mailbox: String,
        uidValidity: UInt32?,
        lastSyncUID: UInt32,
        messageCount: Int,
        syncStatus: SyncStatus,
        errorMessage: String? = nil
    ) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute("""
            INSERT INTO email_sync_state (
                account_id, mailbox_name, uid_validity, last_sync_uid,
                last_sync_at, message_count, sync_status, error_message
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_id, mailbox_name) DO UPDATE SET
                uid_validity = excluded.uid_validity,
                last_sync_uid = excluded.last_sync_uid,
                last_sync_at = excluded.last_sync_at,
                message_count = excluded.message_count,
                sync_status = excluded.sync_status,
                error_message = excluded.error_message
        """, params: [
            accountID, mailbox,
            uidValidity.map { "\($0)" },
            "\(lastSyncUID)", now, "\(messageCount)",
            syncStatus.rawValue, errorMessage,
        ])
    }

    public func resetSyncState(accountID: String, mailbox: String) throws {
        try db.execute(
            "DELETE FROM email_sync_state WHERE account_id = ? AND mailbox_name = ?",
            params: [accountID, mailbox]
        )
    }

    // MARK: - Email Read/Flag/Viewed State

    public func updateEmailReadState(emailID: String, isRead: Bool) throws {
        try db.execute(
            "UPDATE email_messages SET is_read = ? WHERE email_id = ?",
            params: [isRead ? "1" : "0", emailID]
        )
    }

    public func updateEmailFlagState(emailID: String, isFlagged: Bool, flagColor: String? = nil) throws {
        try db.execute(
            "UPDATE email_messages SET is_flagged = ?, flag_color = ? WHERE email_id = ?",
            params: [isFlagged ? "1" : "0", flagColor, emailID]
        )
    }

    public func batchUpdateReadState(emailIDs: [String], isRead: Bool) throws {
        guard !emailIDs.isEmpty else { return }
        let placeholders = emailIDs.map { _ in "?" }.joined(separator: ",")
        let params = [isRead ? "1" : "0"] + emailIDs
        try db.execute(
            "UPDATE email_messages SET is_read = ? WHERE email_id IN (\(placeholders))",
            params: params
        )
    }

    public func batchUpdateFlagState(emailIDs: [String], isFlagged: Bool, flagColor: String? = nil) throws {
        guard !emailIDs.isEmpty else { return }
        let placeholders = emailIDs.map { _ in "?" }.joined(separator: ",")
        let params: [String?] = [isFlagged ? "1" : "0", flagColor] + emailIDs.map { Optional($0) }
        try db.execute(
            "UPDATE email_messages SET is_flagged = ?, flag_color = ? WHERE email_id IN (\(placeholders))",
            params: params
        )
    }

    /// Mark a message as locally viewed in Manifold (distinct from IMAP \Seen flag).
    public func updateLocalViewedState(emailID: String, viewed: Bool) throws {
        try db.execute(
            "UPDATE email_messages SET local_is_viewed = ? WHERE email_id = ?",
            params: [viewed ? "1" : "0", emailID]
        )
    }

    /// Batch mark messages as locally viewed.
    public func batchUpdateLocalViewedState(emailIDs: [String], viewed: Bool) throws {
        guard !emailIDs.isEmpty else { return }
        let placeholders = emailIDs.map { _ in "?" }.joined(separator: ",")
        let params = [viewed ? "1" : "0"] + emailIDs
        try db.execute(
            "UPDATE email_messages SET local_is_viewed = ? WHERE email_id IN (\(placeholders))",
            params: params
        )
    }

    // MARK: - Server Deletion Tracking

    /// Mark a message as deleted on the server.
    public func markDeletedOnServer(emailID: String) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            "UPDATE email_messages SET deleted_on_server_at = ? WHERE email_id = ?",
            params: [now, emailID]
        )
    }

    /// Mark a message's junk status.
    public func updateJunkState(emailID: String, isJunk: Bool) throws {
        try db.execute(
            "UPDATE email_messages SET is_junk = ? WHERE email_id = ?",
            params: [isJunk ? "1" : "0", emailID]
        )
    }

    // MARK: - Body Text (FTS5)

    /// Update body text for a message and sync to FTS5 index.
    public func updateBodyText(emailID: String, bodyText: String) throws {
        // Remove stale FTS entry if body_text was previously indexed (content-synced FTS5
        // requires old values for delete, so only delete when an entry exists)
        try db.execute("""
            INSERT INTO email_fts(email_fts, rowid, email_id, body_text)
            SELECT 'delete', rowid, email_id, body_text FROM email_messages
            WHERE email_id = ? AND body_text IS NOT NULL
        """, params: [emailID])
        try db.execute(
            "UPDATE email_messages SET body_text = ? WHERE email_id = ?",
            params: [bodyText, emailID]
        )
        // Insert new FTS entry with updated body text
        try db.execute("""
            INSERT INTO email_fts(rowid, email_id, body_text)
            SELECT rowid, email_id, body_text FROM email_messages WHERE email_id = ?
        """, params: [emailID])
    }

    /// Count of messages with body text indexed.
    public func bodyTextIndexedCount() throws -> Int {
        let result = try db.queryScalar("SELECT COUNT(*) FROM email_messages WHERE body_text IS NOT NULL")
        return result.flatMap { Int($0) } ?? 0
    }

    /// Get email IDs that need body text backfill, ordered by received_at DESC.
    public func emailsNeedingBodyBackfill(limit: Int = 100) throws -> [(emailID: String, emlPath: String)] {
        let rows = try db.queryAll("""
            SELECT email_id, eml_path FROM email_messages
            WHERE body_text IS NULL AND eml_path IS NOT NULL
            ORDER BY received_at DESC
            LIMIT ?
        """, params: ["\(limit)"])
        return rows.compactMap { row in
            guard let id = row["email_id"], let path = row["eml_path"] else { return nil }
            return (id, path)
        }
    }

    // MARK: - Unread / Unviewed Counts

    public func unreadCount(accountID: String, mailbox: String) throws -> Int {
        let result = try db.queryScalar("""
            SELECT COUNT(*) FROM email_messages em
            JOIN email_mailbox_membership emm ON em.email_id = emm.email_id
            WHERE emm.account_id = ? AND emm.mailbox = ? AND em.is_read = 0
        """, params: [accountID, mailbox])
        return result.flatMap { Int($0) } ?? 0
    }

    public func unreadCountAll() throws -> Int {
        let result = try db.queryScalar(
            "SELECT COUNT(*) FROM email_messages WHERE is_read = 0"
        )
        return result.flatMap { Int($0) } ?? 0
    }

    public func unreadCount(accountID: String) throws -> Int {
        let result = try db.queryScalar(
            "SELECT COUNT(*) FROM email_messages WHERE account_id = ? AND is_read = 0",
            params: [accountID]
        )
        return result.flatMap { Int($0) } ?? 0
    }

    public func unviewedCount() throws -> Int {
        let result = try db.queryScalar(
            "SELECT COUNT(*) FROM email_messages WHERE local_is_viewed = 0"
        )
        return result.flatMap { Int($0) } ?? 0
    }

    // MARK: - Mailbox Membership

    public func upsertMailboxMembership(accountID: String, mailbox: String, imapUID: UInt32, emailID: String) throws {
        try db.execute("""
            INSERT OR IGNORE INTO email_mailbox_membership (account_id, mailbox, imap_uid, email_id)
            VALUES (?, ?, ?, ?)
        """, params: [accountID, mailbox, "\(imapUID)", emailID])
    }

    public func messagesInMailbox(accountID: String, mailbox: String, limit: Int = 500) throws -> [EmailMessageRecord] {
        try emailMessages(accountID: accountID, mailbox: mailbox, limit: limit)
    }

    public func replaceGrantEmails(grantID: String, emailIDs: [String]) throws {
        try db.transaction {
            try db.execute("DELETE FROM grant_emails WHERE grant_id = ?", params: [grantID])
            for emailID in Set(emailIDs) {
                let materializedPath = try db.queryScalar(
                    "SELECT COALESCE(eml_path, 'selected://' || email_id) FROM email_messages WHERE email_id = ? LIMIT 1",
                    params: [emailID]
                )
                guard let materializedPath else { continue }
                try db.execute(
                    """
                    INSERT INTO grant_emails (grant_id, email_id, materialized_path)
                    VALUES (?, ?, ?)
                    """,
                    params: [grantID, emailID, materializedPath]
                )
            }
        }
    }

    public func grantEmails(grantID: String, limit: Int = 500) throws -> [EmailMessageRecord] {
        let rows = try db.queryAll(
            """
            SELECT em.* FROM email_messages em
            JOIN grant_emails ge ON em.email_id = ge.email_id
            WHERE ge.grant_id = ?
            ORDER BY em.received_at DESC
            LIMIT ?
            """,
            params: [grantID, "\(limit)"]
        )
        return rows.compactMap { EmailMessageRecord(row: $0) }
    }

    public func grantEmailIDs(grantID: String) throws -> Set<String> {
        let rows = try db.queryAll(
            "SELECT email_id FROM grant_emails WHERE grant_id = ?",
            params: [grantID]
        )
        return Set(rows.compactMap { $0["email_id"] })
    }

    public func isEmailInGrant(grantID: String, emailID: String) throws -> Bool {
        let result = try db.queryScalar(
            "SELECT COUNT(*) FROM grant_emails WHERE grant_id = ? AND email_id = ?",
            params: [grantID, emailID]
        )
        return result.flatMap(Int.init) ?? 0 > 0
    }

    public func messageCountInMailbox(accountID: String, mailbox: String) throws -> Int {
        let result = try db.queryScalar("""
            SELECT COUNT(*) FROM email_mailbox_membership
            WHERE account_id = ? AND mailbox = ?
        """, params: [accountID, mailbox])
        return result.flatMap { Int($0) } ?? 0
    }

    // MARK: - EXPUNGE Detection (SEARCH ALL reconciliation)

    /// Get stored UIDs for a mailbox from the membership table.
    public func storedUIDs(accountID: String, mailbox: String) throws -> Set<UInt32> {
        let rows = try db.queryAll(
            "SELECT imap_uid FROM email_mailbox_membership WHERE account_id = ? AND mailbox = ?",
            params: [accountID, mailbox]
        )
        return Set(rows.compactMap { $0["imap_uid"].flatMap { UInt32($0) } })
    }

    /// Mark UIDs as missing from a mailbox (first pass of EXPUNGE detection).
    public func markMissingFromMailbox(accountID: String, mailbox: String, missingUIDs: Set<UInt32>) throws {
        guard !missingUIDs.isEmpty else { return }
        let now = ISO8601DateFormatter.shared.string(from: Date())
        for uid in missingUIDs {
            try db.execute("""
                UPDATE email_mailbox_membership SET missing_from = ?
                WHERE account_id = ? AND mailbox = ? AND imap_uid = ? AND missing_from IS NULL
            """, params: [now, accountID, mailbox, "\(uid)"])
        }
    }

    /// Clear missing_from for UIDs that reappeared.
    public func clearMissingFrom(accountID: String, mailbox: String, reappearedUIDs: Set<UInt32>) throws {
        guard !reappearedUIDs.isEmpty else { return }
        for uid in reappearedUIDs {
            try db.execute("""
                UPDATE email_mailbox_membership SET missing_from = NULL
                WHERE account_id = ? AND mailbox = ? AND imap_uid = ?
            """, params: [accountID, mailbox, "\(uid)"])
        }
    }

    /// Confirm server deletions: find messages missing from ALL mailboxes (second pass).
    public func confirmServerDeletions() throws -> Int {
        // Find email_ids where ALL membership rows have non-null missing_from
        let rows = try db.queryAll("""
            SELECT emm.email_id FROM email_mailbox_membership emm
            WHERE emm.missing_from IS NOT NULL
            GROUP BY emm.email_id
            HAVING COUNT(*) = (
                SELECT COUNT(*) FROM email_mailbox_membership emm2
                WHERE emm2.email_id = emm.email_id
            )
            AND NOT EXISTS (
                SELECT 1 FROM email_messages em
                WHERE em.email_id = emm.email_id AND em.deleted_on_server_at IS NOT NULL
            )
        """)
        var count = 0
        for row in rows {
            if let emailID = row["email_id"] {
                try markDeletedOnServer(emailID: emailID)
                count += 1
            }
        }
        return count
    }

    // MARK: - IMAP Mailboxes (persisted folder tree)

    public func upsertIMAPMailbox(
        accountID: String,
        name: String,
        delimiter: String?,
        flags: [String],
        isSelectable: Bool = true,
        parentPath: String? = nil,
        sortOrder: Int = 0
    ) throws {
        let flagsJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: flags),
           let str = String(data: data, encoding: .utf8) {
            flagsJSON = str
        } else {
            flagsJSON = "[]"
        }
        try db.execute("""
            INSERT INTO imap_mailboxes (account_id, mailbox_name, delimiter, flags, is_selectable, parent_path, sort_order)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_id, mailbox_name) DO UPDATE SET
                delimiter = excluded.delimiter,
                flags = excluded.flags,
                is_selectable = excluded.is_selectable,
                parent_path = excluded.parent_path,
                sort_order = excluded.sort_order
        """, params: [
            accountID, name, delimiter, flagsJSON,
            isSelectable ? "1" : "0", parentPath, "\(sortOrder)",
        ])
    }

    public func imapMailboxes(accountID: String) throws -> [IMAPMailboxRecord] {
        let rows = try db.queryAll(
            "SELECT * FROM imap_mailboxes WHERE account_id = ? ORDER BY sort_order ASC, mailbox_name ASC",
            params: [accountID]
        )
        return rows.compactMap { IMAPMailboxRecord(row: $0) }
    }

    // MARK: - Shared Emails (persistent, per-agent, grant-independent)

    @discardableResult
    public func shareEmails(emailIDs: [String], for agent: TargetApp, label: String? = nil) throws -> Int {
        guard !emailIDs.isEmpty else { return 0 }
        let now = ISO8601DateFormatter.shared.string(from: Date())
        var count = 0
        for emailID in emailIDs {
            let shareID = "share-\(UUID().uuidString.prefix(8).lowercased())"
            try db.execute("""
                INSERT OR IGNORE INTO shared_emails (share_id, agent, email_id, shared_at, label)
                VALUES (?, ?, ?, ?, ?)
            """, params: [shareID, agent.rawValue, emailID, now, label])
            count += 1
        }
        return count
    }

    @discardableResult
    public func shareEmails(emailIDs: [String], label: String? = nil) throws -> Int {
        try shareEmails(emailIDs: emailIDs, for: .cowork, label: label)
    }

    public func unshareEmails(emailIDs: [String], for agent: TargetApp) throws {
        guard !emailIDs.isEmpty else { return }
        let placeholders = emailIDs.map { _ in "?" }.joined(separator: ",")
        try db.execute(
            "DELETE FROM shared_emails WHERE agent = ? AND email_id IN (\(placeholders))",
            params: [agent.rawValue] + emailIDs
        )
    }

    public func unshareEmails(emailIDs: [String]) throws {
        try unshareEmails(emailIDs: emailIDs, for: .cowork)
    }

    public func unshareAllEmails() throws {
        try db.execute("DELETE FROM shared_emails")
    }

    public func sharedEmails(agent: TargetApp, limit: Int = 500) throws -> [EmailMessageRecord] {
        let rows = try db.queryAll("""
            SELECT em.* FROM email_messages em
            JOIN shared_emails se ON em.email_id = se.email_id
            WHERE se.agent = ?
            ORDER BY se.shared_at DESC
            LIMIT ?
        """, params: [agent.rawValue, "\(limit)"])
        return rows.compactMap { EmailMessageRecord(row: $0) }
    }

    public func sharedEmails(limit: Int = 500) throws -> [EmailMessageRecord] {
        try sharedEmails(agent: .cowork, limit: limit)
    }

    public func sharedEmailCount(agent: TargetApp) throws -> Int {
        let result = try db.queryScalar(
            "SELECT COUNT(*) FROM shared_emails WHERE agent = ?",
            params: [agent.rawValue]
        )
        return result.flatMap { Int($0) } ?? 0
    }

    public func sharedEmailCount() throws -> Int {
        let result = try db.queryScalar("SELECT COUNT(*) FROM shared_emails")
        return result.flatMap { Int($0) } ?? 0
    }

    /// Count emails not in the given hidden domains set.
    public func visibleEmailCount(hiddenDomains: Set<String>) throws -> Int {
        if hiddenDomains.isEmpty {
            return try emailMessageCount()
        }
        let placeholders = hiddenDomains.map { _ in "?" }.joined(separator: ", ")
        let params = Array(hiddenDomains) as [String?]
        let result = try db.queryScalar(
            "SELECT COUNT(*) FROM email_messages WHERE sender_domain NOT IN (\(placeholders))",
            params: params
        )
        return result.flatMap { Int($0) } ?? 0
    }

    public func isEmailShared(emailID: String, agent: TargetApp) throws -> Bool {
        let result = try db.queryScalar(
            "SELECT COUNT(*) FROM shared_emails WHERE agent = ? AND email_id = ?",
            params: [agent.rawValue, emailID]
        )
        return (result.flatMap { Int($0) } ?? 0) > 0
    }

    public func isEmailShared(emailID: String) throws -> Bool {
        let result = try db.queryScalar(
            "SELECT COUNT(*) FROM shared_emails WHERE email_id = ?",
            params: [emailID]
        )
        return (result.flatMap { Int($0) } ?? 0) > 0
    }

    public func sharedEmailIDs(agent: TargetApp) throws -> Set<String> {
        let rows = try db.queryAll(
            "SELECT email_id FROM shared_emails WHERE agent = ?",
            params: [agent.rawValue]
        )
        return Set(rows.compactMap { $0["email_id"] })
    }

    public func sharedEmailIDs() throws -> Set<String> {
        let rows = try db.queryAll("SELECT email_id FROM shared_emails")
        return Set(rows.compactMap { $0["email_id"] })
    }

    // MARK: - Smart Mailboxes

    @discardableResult
    public func createSmartMailbox(displayName: String, iconName: String = "tray", rulesJSON: String = "[]") throws -> String {
        let mailboxID = "smart-\(UUID().uuidString.prefix(8).lowercased())"
        let nextOrder = try db.queryScalar("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM smart_mailboxes")
        try db.execute("""
            INSERT INTO smart_mailboxes (mailbox_id, display_name, icon_name, rules_json, sort_order)
            VALUES (?, ?, ?, ?, ?)
        """, params: [mailboxID, displayName, iconName, rulesJSON, nextOrder ?? "0"])
        return mailboxID
    }

    public func updateSmartMailbox(mailboxID: String, displayName: String, iconName: String, rulesJSON: String) throws {
        try db.execute("""
            UPDATE smart_mailboxes SET display_name = ?, icon_name = ?, rules_json = ?
            WHERE mailbox_id = ?
        """, params: [displayName, iconName, rulesJSON, mailboxID])
    }

    public func allSmartMailboxes() throws -> [SmartMailboxRecord] {
        let rows = try db.queryAll("SELECT * FROM smart_mailboxes ORDER BY sort_order ASC")
        return rows.compactMap { SmartMailboxRecord(row: $0) }
    }

    public func deleteSmartMailbox(mailboxID: String) throws {
        try db.execute("DELETE FROM smart_mailboxes WHERE mailbox_id = ?", params: [mailboxID])
    }

    /// Count messages matching a smart mailbox's rules.
    public func smartMailboxCount(rules: SmartMailboxRules) throws -> Int {
        let (whereClause, params) = buildConditionSQL(from: rules.conditions, match: rules.match)
        let result = try db.queryScalar("""
            SELECT COUNT(*) FROM email_messages em
            \(whereClause)
        """, params: params)
        return result.flatMap { Int($0) } ?? 0
    }

    /// Get messages matching a smart mailbox's rules.
    public func smartMailboxMessages(rules: SmartMailboxRules, sortKey: EmailSortKey = .date, limit: Int = 500) throws -> [EmailMessageRecord] {
        let (whereClause, params) = buildConditionSQL(from: rules.conditions, match: rules.match)
        var allParams = params
        allParams.append("\(limit)")

        let orderClause = orderSQL(for: sortKey)

        let rows = try db.queryAll("""
            SELECT em.* FROM email_messages em
            \(whereClause)
            ORDER BY \(orderClause)
            LIMIT ?
        """, params: allParams)
        return rows.compactMap { EmailMessageRecord(row: $0) }
    }

    // MARK: - Threading

    public func emailThread(messageIDHeader: String) throws -> [EmailMessageRecord] {
        let rows = try db.queryAll("""
            SELECT * FROM email_messages
            WHERE message_id_header = ? OR in_reply_to = ?
            ORDER BY received_at ASC
        """, params: [messageIDHeader, messageIDHeader])
        return rows.compactMap { EmailMessageRecord(row: $0) }
    }

    // MARK: - Unified Search (condition builder)

    /// Search emails using the unified condition builder. Handles structured tokens,
    /// quick filters, free text, and scope filters through a single SQL builder.
    public func searchEmailMessages(
        tokens: [SearchToken] = [],
        freeText: String = "",
        accountID: String? = nil,
        mailbox: String? = nil,
        filter: QuickFilter? = nil,
        sortKey: EmailSortKey = .date,
        limit: Int = 500
    ) throws -> [EmailMessageRecord] {
        // Convert all inputs to RuleConditions for unified handling
        var conditions = conditionsFromTokens(tokens)
        if let filterConditions = conditionsFromQuickFilter(filter) {
            conditions.append(contentsOf: filterConditions)
        }

        var extraSQL: [String] = []
        var extraParams: [String?] = []

        // Date-relative filters (not expressible as static RuleConditions)
        if filter == .today {
            extraSQL.append("em.received_at >= date('now', 'start of day')")
        } else if filter == .thisWeek {
            extraSQL.append("em.received_at >= date('now', '-6 days', 'start of day')")
        }

        // Scope filters (not expressible as RuleConditions)
        if let accountID {
            extraSQL.append("em.account_id = ?")
            extraParams.append(accountID)
        }
        if let mailbox {
            extraSQL.append("""
                em.email_id IN (
                    SELECT email_id FROM email_mailbox_membership
                    WHERE account_id = em.account_id AND mailbox = ?
                )
            """)
            extraParams.append(mailbox)
        }

        // Free text search across sender, subject, preview, and body
        if !freeText.isEmpty {
            extraSQL.append("""
                (em.sender LIKE ? OR em.subject LIKE ? OR em.preview LIKE ?
                 OR em.email_id IN (SELECT email_id FROM email_fts WHERE body_text MATCH ?))
            """)
            let pattern = "%\(freeText)%"
            extraParams.append(pattern)
            extraParams.append(pattern)
            extraParams.append(pattern)
            extraParams.append(freeText)
        }

        let (ruleWhere, ruleParams) = buildConditionSQL(from: conditions, match: .all)

        // Merge rule conditions with scope/freetext conditions
        var allConditionParts: [String] = []
        var allParams: [String?] = []

        if !ruleWhere.isEmpty {
            // Strip "WHERE " prefix from ruleWhere
            let stripped = ruleWhere.hasPrefix("WHERE ") ? String(ruleWhere.dropFirst(6)) : ruleWhere
            if !stripped.isEmpty {
                allConditionParts.append(stripped)
            }
            allParams.append(contentsOf: ruleParams)
        }
        allConditionParts.append(contentsOf: extraSQL)
        allParams.append(contentsOf: extraParams)

        let whereClause = allConditionParts.isEmpty ? "" : "WHERE " + allConditionParts.joined(separator: " AND ")
        let orderClause = orderSQL(for: sortKey)
        allParams.append("\(limit)")

        let rows = try db.queryAll("""
            SELECT em.* FROM email_messages em
            \(whereClause)
            ORDER BY \(orderClause)
            LIMIT ?
        """, params: allParams)
        return rows.compactMap { EmailMessageRecord(row: $0) }
    }

    // MARK: - Unified Condition Builder (private)

    /// Build WHERE clause from an array of RuleConditions.
    private func buildConditionSQL(
        from conditions: [RuleCondition],
        match: SmartMailboxRules.MatchType
    ) -> (whereClause: String, params: [String?]) {
        let validConditions = conditions.filter { $0.isValid }
        guard !validConditions.isEmpty else { return ("", []) }

        var sqlParts: [String] = []
        var params: [String?] = []

        for condition in validConditions {
            guard let (sql, condParams) = sqlForCondition(condition) else { continue }
            sqlParts.append(sql)
            params.append(contentsOf: condParams)
        }

        guard !sqlParts.isEmpty else { return ("", []) }

        let joiner = match == .all ? " AND " : " OR "
        let combined = sqlParts.count == 1 ? sqlParts[0] : "(" + sqlParts.joined(separator: joiner) + ")"
        return ("WHERE " + combined, params)
    }

    /// Generate SQL fragment for a single RuleCondition.
    private func sqlForCondition(_ condition: RuleCondition) -> (String, [String?])? {
        let field = condition.field

        // Special handling for "shared" virtual field
        if field == "shared" {
            if condition.op == .equals && condition.value == "true" {
                return ("em.email_id IN (SELECT email_id FROM shared_emails)", [])
            } else {
                return ("em.email_id NOT IN (SELECT email_id FROM shared_emails)", [])
            }
        }

        if let virtual = sqlForPrivacyCondition(condition) {
            return virtual
        }

        // Defense-in-depth: re-validate field even though buildConditionSQL pre-filters
        guard RuleCondition.allowedFields.contains(field) else { return nil }
        let column = "em.\(field)"

        switch condition.op {
        case .equals:
            return ("\(column) = ?", [condition.value])
        case .notEquals:
            return ("\(column) != ?", [condition.value])
        case .contains:
            if field == "body_text" {
                // Use FTS5 MATCH for body text
                return ("em.email_id IN (SELECT email_id FROM email_fts WHERE body_text MATCH ?)", [condition.value])
            }
            return ("\(column) LIKE ?", ["%\(condition.value)%"])
        case .notContains:
            if field == "body_text" {
                return ("em.email_id NOT IN (SELECT email_id FROM email_fts WHERE body_text MATCH ?)", [condition.value])
            }
            return ("\(column) NOT LIKE ?", ["%\(condition.value)%"])
        case .greaterThan:
            return ("\(column) > ?", [condition.value])
        case .lessThan:
            return ("\(column) < ?", [condition.value])
        case .after:
            return ("\(column) > ?", [condition.value])
        case .before:
            return ("\(column) < ?", [condition.value])
        case .between:
            let parts = condition.value.split(separator: ",").map(String.init)
            guard parts.count == 2 else { return nil }
            return ("\(column) BETWEEN ? AND ?", [parts[0], parts[1]])
        case .isNotNull:
            return ("\(column) IS NOT NULL", [])
        }
    }

    private func sqlForPrivacyCondition(_ condition: RuleCondition) -> (String, [String?])? {
        switch condition.field {
        case "privacy_contains_sensitive":
            return privacyBooleanCondition(column: "contains_sensitive", condition: condition)
        case "privacy_contains_my_info":
            return privacyBooleanCondition(column: "contains_my_info", condition: condition)
        case "privacy_contains_secret":
            return privacyBooleanCondition(column: "contains_secret", condition: condition)
        case "privacy_contains_third_party_private":
            return privacyBooleanCondition(column: "contains_third_party_private", condition: condition)
        case "privacy_contains_org_only":
            return privacyBooleanCondition(column: "contains_org_only", condition: condition)
        case "privacy_severity":
            guard condition.op == .equals || condition.op == .notEquals else { return nil }
            let comparator = condition.op == .equals ? "=" : "!="
            return (
                """
                em.email_id IN (
                    SELECT email_id FROM privacy_content_index
                    WHERE subject_kind = 'email_body' AND severity \(comparator) ?
                )
                """,
                [condition.value]
            )
        case "privacy_categories":
            switch condition.op {
            case .contains, .equals:
                return (
                    """
                    em.email_id IN (
                        SELECT email_id FROM privacy_content_index
                        WHERE subject_kind = 'email_body' AND matched_categories_json LIKE ?
                    )
                    """,
                    ["%\"\(condition.value)\"%"]
                )
            case .notContains, .notEquals:
                return (
                    """
                    em.email_id NOT IN (
                        SELECT email_id FROM privacy_content_index
                        WHERE subject_kind = 'email_body' AND matched_categories_json LIKE ?
                    )
                    """,
                    ["%\"\(condition.value)\"%"]
                )
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func privacyBooleanCondition(
        column: String,
        condition: RuleCondition
    ) -> (String, [String?])? {
        guard condition.op == .equals else { return nil }
        let normalized = condition.value.lowercased()
        let expected = normalized == "1" || normalized == "true" ? "1" : "0"
        let comparator = expected == "1" ? "IN" : "NOT IN"
        return (
            """
            em.email_id \(comparator) (
                SELECT email_id FROM privacy_content_index
                WHERE subject_kind = 'email_body' AND \(column) = 1
            )
            """,
            []
        )
    }

    /// Convert SearchTokens to RuleConditions.
    private func conditionsFromTokens(_ tokens: [SearchToken]) -> [RuleCondition] {
        tokens.compactMap { token -> RuleCondition? in
            switch token.type {
            case .from:
                return RuleCondition(field: "sender_email", op: .contains, value: token.value)
            case .domain:
                return RuleCondition(field: "sender_domain", op: .equals, value: token.value.lowercased())
            case .subject:
                return RuleCondition(field: "subject", op: .contains, value: token.value)
            case .to:
                return RuleCondition(field: "recipients", op: .contains, value: token.value)
            case .hasAttachments:
                return RuleCondition(field: "attachment_count", op: .greaterThan, value: "0")
            case .body:
                return RuleCondition(field: "body_text", op: .contains, value: token.value)
            case .dateAfter:
                return RuleCondition(field: "received_at", op: .after, value: token.value)
            case .dateBefore:
                return RuleCondition(field: "received_at", op: .before, value: token.value)
            case .isJunk:
                return RuleCondition(field: "is_junk", op: .equals, value: "1")
            case .isDeleted:
                return RuleCondition(field: "deleted_on_server_at", op: .isNotNull, value: "")
            }
        }
    }

    /// Convert a QuickFilter to RuleConditions.
    private func conditionsFromQuickFilter(_ filter: QuickFilter?) -> [RuleCondition]? {
        guard let filter else { return nil }
        switch filter {
        case .unread:
            return [RuleCondition(field: "is_read", op: .equals, value: "0")]
        case .flagged:
            return [RuleCondition(field: "is_flagged", op: .equals, value: "1")]
        case .attachments:
            return [RuleCondition(field: "attachment_count", op: .greaterThan, value: "0")]
        case .today:
            // Date-relative filters can't be expressed as simple RuleConditions,
            // so we handle them inline in the search method
            return nil
        case .unviewed:
            return [RuleCondition(field: "local_is_viewed", op: .equals, value: "0")]
        case .deletedOnServer:
            return [RuleCondition(field: "deleted_on_server_at", op: .isNotNull, value: "")]
        case .junk:
            return [RuleCondition(field: "is_junk", op: .equals, value: "1")]
        case .thisWeek:
            return nil
        }
    }

    /// Generate ORDER BY SQL for a sort key.
    private func orderSQL(for sortKey: EmailSortKey) -> String {
        switch sortKey {
        case .date: return "em.received_at DESC"
        case .sender: return "em.sender_email ASC, em.received_at DESC"
        case .subject: return "em.subject ASC, em.received_at DESC"
        case .size: return "em.size_bytes DESC, em.received_at DESC"
        }
    }
}
