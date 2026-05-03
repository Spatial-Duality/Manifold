// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
import CryptoKit
@testable import ManifoldKit

@Suite("EmailStore")
struct EmailStoreTests {
    /// The default test account ID, set by makeStore().
    static let testAccountID = "email-testacct"

    func makeStore() async throws -> (EmailStore, DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-email-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        let store = EmailStore(db: db)
        // Create the default test account (FK requires email_accounts row)
        // Use raw SQL to control the account_id for test stability
        let now = ISO8601DateFormatter().string(from: Date())
        try db.execute("""
            INSERT INTO email_accounts (account_id, display_name, provider_type, server, port, username, auth_type, sync_enabled, sync_interval_seconds, created_at, updated_at)
            VALUES (?, 'Test', 'other', 'imap.test.com', '993', 'test@test.com', 'password', 1, 300, ?, ?)
        """, params: [Self.testAccountID, now, now])
        return (store, db, tempDir)
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    func mailboxRecord(
        accountID: String = EmailStoreTests.testAccountID,
        mailboxName: String,
        flags: [String] = [],
        isSelectable: Bool = true,
        sortOrder: Int = 0
    ) -> IMAPMailboxRecord {
        IMAPMailboxRecord(row: [
            "account_id": accountID,
            "mailbox_name": mailboxName,
            "flags": (try? String(
                data: JSONSerialization.data(withJSONObject: flags),
                encoding: .utf8
            )) ?? "[]",
            "is_selectable": isSelectable ? "1" : "0",
            "sort_order": "\(sortOrder)",
        ])!
    }

    /// Insert a test message and return its ID.
    func insertTestMessage(
        store: EmailStore,
        emailID: String = "msg-\(UUID().uuidString.prefix(8))",
        accountID: String = EmailStoreTests.testAccountID,
        mailbox: String = "INBOX",
        sender: String = "Test User <test@example.com>",
        senderEmail: String = "test@example.com",
        senderDomain: String = "example.com",
        subject: String = "Test Subject",
        isRead: Bool = false,
        isFlagged: Bool = false,
        attachmentCount: Int = 0
    ) async throws -> String {
        try store.upsertEmailMessage(
            emailID: emailID,
            accountID: accountID,
            mailbox: mailbox,
            sender: sender,
            senderEmail: senderEmail,
            senderDomain: senderDomain,
            recipients: "recipient@test.com",
            subject: subject,
            receivedAt: ISO8601DateFormatter().string(from: Date()),
            emlPath: nil,
            sizeBytes: 1024,
            preview: "This is a test preview",
            isRead: isRead,
            isFlagged: isFlagged,
            attachmentCount: attachmentCount
        )
        return emailID
    }

    // MARK: - Migration v10

    @Test("Migration v10 creates new columns and FTS5 table")
    func migrationV10() async throws {
        let (_, db, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        // Verify new columns exist by querying them
        let rows = try db.queryAll("SELECT local_is_viewed, is_junk, deleted_on_server_at, body_text FROM email_messages LIMIT 1")
        // Just need no error — the columns exist

        // Verify FTS5 table
        let fts = try db.queryAll("SELECT * FROM email_fts LIMIT 1")
        // No error means it exists

        // Verify membership missing_from column
        let mem = try db.queryAll("SELECT missing_from FROM email_mailbox_membership LIMIT 1")
        _ = (rows, fts, mem) // suppress unused
    }

    @Test("Migration v10 creates preset smart mailbox")
    func presetSmartMailbox() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let mailboxes = try store.allSmartMailboxes()
        let preset = mailboxes.first { $0.displayName == "Shared with Cowork" }
        #expect(preset != nil)
        #expect(preset?.iconName == "person.2.fill")
    }

    @Test("Migration v38 creates production mail foundation tables")
    func migrationV38ProductionMailFoundations() async throws {
        let (_, db, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try db.queryAll("SELECT credential_kind, credential_keychain_service, credential_keychain_account, auth_state, index_privacy_mode FROM email_accounts LIMIT 1")
        _ = try db.queryAll("SELECT canonical_blob_cid, header_blob_cid, rfc_message_id_hmac FROM email_messages LIMIT 1")
        _ = try db.queryAll("SELECT attachment_blob_cid FROM email_attachments LIMIT 1")
        _ = try db.queryAll("SELECT content_id, kind, manifest_id FROM mail_blobs LIMIT 1")
        _ = try db.queryAll("SELECT term_hmac, field_mask, term_count FROM mail_private_terms LIMIT 1")
        _ = try db.queryAll("SELECT job_type, state, cursor_json_ciphertext FROM mail_sync_jobs LIMIT 1")
        _ = try db.queryAll("SELECT access_kind, details_redacted FROM mail_access_audit_events LIMIT 1")
    }

    @Test("New email accounts store v2 credential references")
    func addEmailAccountStoresV2CredentialReference() async throws {
        let (store, db, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let account = try store.addEmailAccount(
            displayName: "Fastmail",
            providerType: EmailProvider.fastmail.rawValue,
            server: "imap.fastmail.com",
            port: 993,
            username: "user@example.com",
            authType: "app_password"
        )

        let row = try #require(try db.queryAll(
            """
            SELECT credential_kind, credential_keychain_service, credential_keychain_account
            FROM email_accounts
            WHERE account_id = ?
            """,
            params: [account.accountID]
        ).first)
        #expect(row["credential_kind"] == MailCredentialKind.appPassword.rawValue)
        #expect(row["credential_keychain_service"] == KeychainMailSecretStore.credentialService)
        #expect(row["credential_keychain_account"] == "mail-account:\(account.accountID):app-password")
        #expect(account.mailCredentialReference?.keychainAccount == "mail-account:\(account.accountID):app-password")
    }

    @Test("Email accounts persist selected index privacy mode")
    func addEmailAccountPersistsIndexPrivacyMode() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let account = try store.addEmailAccount(
            displayName: "Fastmail FTS",
            providerType: EmailProvider.fastmail.rawValue,
            server: "imap.fastmail.com",
            port: 993,
            username: "user@example.com",
            authType: "app_password",
            indexPrivacyMode: .plaintextFTSWithDisclosure
        )

        let stored = try #require(try store.emailAccount(id: account.accountID))
        #expect(stored.indexPrivacyMode == MailIndexPrivacyMode.plaintextFTSWithDisclosure.rawValue)
    }

    @Test("Email messages can reference archive v2 canonical blobs")
    func upsertMessageWithCanonicalBlobReference() async throws {
        let (store, db, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let archiveRoot = tempDir.appendingPathComponent("MailArchive")
        let archive = try MailArchiveStore(rootURL: archiveRoot)
        let stored = try archive.storeMessage(
            accountID: Self.testAccountID,
            plaintext: Data("Subject: Stored\r\n\r\nArchived body".utf8)
        )

        try store.upsertEmailMessage(
            emailID: "msg-archive-v2",
            accountID: Self.testAccountID,
            mailbox: "INBOX",
            sender: "Test User <test@example.com>",
            senderEmail: "test@example.com",
            senderDomain: "example.com",
            recipients: "recipient@test.com",
            subject: "Stored",
            receivedAt: ISO8601DateFormatter.shared.string(from: Date()),
            emlPath: stored.manifestURL.path,
            sizeBytes: Int(stored.byteCountPlaintext),
            preview: nil,
            canonicalBlobCID: stored.contentID
        )
        try store.recordMailBlob(stored)

        let message = try #require(try store.emailMessage(id: "msg-archive-v2"))
        #expect(message.canonicalBlobCID == stored.contentID)
        #expect(EmailSyncEngine.readStoredMessage(at: stored.manifestURL.path) == Data("Subject: Stored\r\n\r\nArchived body".utf8))

        let blobRefCount = try db.queryScalar(
            "SELECT ref_count FROM mail_blobs WHERE content_id = ?",
            params: [stored.contentID]
        )
        #expect(blobRefCount == "1")
    }

    @Test("Email attachments can reference archive v2 attachment blobs")
    func upsertAttachmentWithArchiveBlobReference() async throws {
        let (store, db, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let emailID = try await insertTestMessage(
            store: store,
            emailID: "msg-attachment-archive-v2",
            attachmentCount: 1
        )
        let archive = try MailArchiveStore(rootURL: tempDir.appendingPathComponent("MailArchive"))
        let attachmentData = Data("attachment secret payload".utf8)
        let stored = try archive.store(
            accountID: Self.testAccountID,
            kind: .attachment,
            plaintext: attachmentData
        )

        try store.recordMailBlob(stored)
        try store.upsertEmailAttachment(
            attachmentID: "att-archive-v2",
            emailID: emailID,
            filename: "secret.txt",
            mimeType: "text/plain",
            sizeBytes: attachmentData.count,
            contentHash: SHA256.hash(data: attachmentData).hexString,
            contentID: "<mime-content-id>",
            attachmentBlobCID: stored.contentID
        )

        let attachment = try #require(try store.emailAttachment(id: "att-archive-v2"))
        #expect(attachment.contentID == "<mime-content-id>")
        #expect(attachment.attachmentBlobCID == stored.contentID)
        #expect(try archive.readObject(contentID: stored.contentID, accountID: Self.testAccountID) == attachmentData)

        let row = try #require(try db.queryAll(
            "SELECT kind, ref_count FROM mail_blobs WHERE content_id = ?",
            params: [stored.contentID]
        ).first)
        #expect(row["kind"] == MailArchiveObjectKind.attachment.rawValue)
        #expect(row["ref_count"] == "1")
    }

    @Test("Paged message query returns stable windows and total count")
    func pagedMessageQueryWindows() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let baseDate = try #require(ISO8601DateFormatter.shared.date(from: "2026-05-01T00:00:00Z"))
        for index in 0..<80 {
            let receivedAt = ISO8601DateFormatter.shared.string(
                from: baseDate.addingTimeInterval(TimeInterval(index * 60))
            )
            try store.upsertEmailMessage(
                emailID: String(format: "paged-%03d", index),
                accountID: Self.testAccountID,
                mailbox: "INBOX",
                sender: "Sender \(index) <sender\(index)@example.com>",
                senderEmail: "sender\(index)@example.com",
                senderDomain: "example.com",
                recipients: "recipient@test.com",
                subject: "Paged \(index)",
                receivedAt: receivedAt,
                emlPath: nil,
                sizeBytes: 100 + index,
                preview: "Paged test \(index)"
            )
        }

        let firstPage = try store.emailMessagePage(
            accountID: Self.testAccountID,
            mailbox: "INBOX",
            sortKey: .date,
            limit: 25,
            offset: 0
        )
        #expect(firstPage.totalCount == 80)
        #expect(firstPage.messages.count == 25)
        #expect(firstPage.messages.first?.emailID == "paged-079")
        #expect(firstPage.messages.last?.emailID == "paged-055")

        let secondPage = try store.emailMessagePage(
            accountID: Self.testAccountID,
            mailbox: "INBOX",
            sortKey: .date,
            limit: 25,
            offset: 25
        )
        #expect(secondPage.totalCount == 80)
        #expect(Array(secondPage.messages.map(\.emailID).prefix(3)) == ["paged-054", "paged-053", "paged-052"])

        let widePage = try store.emailMessagePage(
            accountID: Self.testAccountID,
            mailbox: "INBOX",
            sortKey: .date,
            limit: 75,
            offset: 75
        )
        #expect(widePage.messages.count == 5)
        #expect(widePage.messages.last?.emailID == "paged-000")
    }

    @Test("Paged mail search tolerates punctuation and matches sender fields")
    func pagedMailSearchToleratesPunctuation() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(
            store: store,
            emailID: "punctuated-search",
            sender: "Mindbody <alerts@mindbody.com>",
            senderEmail: "alerts@mindbody.com",
            senderDomain: "mindbody.com",
            subject: "Finish creating your Cambridge Country Club account"
        )

        let page = try store.emailMessagePage(
            freeText: "alerts@mindbody.com",
            accountID: Self.testAccountID,
            mailbox: "INBOX",
            sortKey: .date,
            limit: 10,
            offset: 0
        )

        #expect(page.totalCount == 1)
        #expect(page.messages.map(\.emailID) == ["punctuated-search"])
    }

    @Test("Authoritative mailbox counts ignore stale sync state counts")
    func authoritativeMailboxCountsIgnoreStaleSyncState() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        for index in 0..<3 {
            let id = "counted-\(index)"
            _ = try await insertTestMessage(store: store, emailID: id, mailbox: "INBOX")
            try store.upsertMailboxMembership(
                accountID: Self.testAccountID,
                mailbox: "INBOX",
                imapUID: UInt32(index + 1),
                emailID: id
            )
        }
        try store.updateSyncState(
            accountID: Self.testAccountID,
            mailbox: "INBOX",
            uidValidity: 1,
            lastSyncUID: 3,
            messageCount: 1,
            syncStatus: .idle
        )

        let account = try #require(try store.emailAccount(id: Self.testAccountID))
        let progress = MailSyncProgressSnapshot.derive(
            account: account,
            states: try store.syncStates(accountID: Self.testAccountID),
            jobs: [],
            syncedMessageCount: try store.emailMessageCount(accountID: Self.testAccountID),
            authoritativeMailboxCounts: try store.authoritativeMailboxCounts(accountID: Self.testAccountID)
        )

        #expect(progress.mailboxSyncedCounts["INBOX"] == 3)
    }

    @Test("Sync state update preserves completed backfill unless explicitly changed")
    func syncStateUpdatePreservesCompletedBackfill() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        try store.updateSyncState(
            accountID: Self.testAccountID,
            mailbox: "INBOX",
            uidValidity: 1,
            lastSyncUID: 10,
            messageCount: 10,
            syncStatus: .idle,
            backfillCompleted: true
        )
        try store.updateSyncState(
            accountID: Self.testAccountID,
            mailbox: "INBOX",
            uidValidity: 1,
            lastSyncUID: 11,
            messageCount: 11,
            syncStatus: .idle
        )

        let state = try #require(try store.syncState(accountID: Self.testAccountID, mailbox: "INBOX"))
        #expect(state.backfillCompleted)
    }

    @Test("Mail metadata repair normalizes dates and decodes encoded headers")
    func mailMetadataRepairNormalizesDatesAndHeaders() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        try store.upsertEmailMessage(
            emailID: "encoded-date",
            accountID: Self.testAccountID,
            mailbox: "INBOX",
            sender: "=?UTF-8?Q?Jos=C3=A9_Test?= <jose@example.com>",
            senderEmail: "jose@example.com",
            senderDomain: "example.com",
            recipients: "recipient@test.com",
            subject: "=?UTF-8?Q?Quarterly_Update?=",
            receivedAt: "Fri, 05 Jan 2024 12:13:14 +0000",
            emlPath: nil,
            sizeBytes: 100,
            preview: nil
        )

        let repairs = try store.repairStoredMailMetadata(accountID: Self.testAccountID)
        let repaired = try #require(try store.emailMessage(id: "encoded-date"))

        #expect(repairs.dateRepairs == 1)
        #expect(repairs.headerRepairs == 1)
        #expect(repaired.receivedAt == "2024-01-05T12:13:14Z")
        #expect(repaired.receivedAtIsTrusted)
        #expect(repaired.sender == "José Test <jose@example.com>")
        #expect(repaired.subject == "Quarterly Update")
    }

    @Test("Untrusted dates sort after trusted dates")
    func untrustedDatesSortAfterTrustedDates() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        try store.upsertEmailMessage(
            emailID: "unknown-date",
            accountID: Self.testAccountID,
            mailbox: "INBOX",
            sender: "Unknown <unknown@example.com>",
            recipients: "recipient@test.com",
            subject: "Unknown",
            receivedAt: "not a date",
            emlPath: nil,
            sizeBytes: 100,
            preview: nil
        )
        try store.upsertEmailMessage(
            emailID: "trusted-date",
            accountID: Self.testAccountID,
            mailbox: "INBOX",
            sender: "Trusted <trusted@example.com>",
            recipients: "recipient@test.com",
            subject: "Trusted",
            receivedAt: "2026-05-01T10:00:00Z",
            emlPath: nil,
            sizeBytes: 100,
            preview: nil
        )

        _ = try store.repairStoredMailMetadata(accountID: Self.testAccountID)
        let page = try store.emailMessagePage(
            accountID: Self.testAccountID,
            mailbox: "INBOX",
            sortKey: .date,
            limit: 10,
            offset: 0
        )

        #expect(page.messages.map(\.emailID) == ["trusted-date", "unknown-date"])
        #expect(page.messages.last?.receivedAtIsTrusted == false)
    }

    @Test("Attachment share records are per-agent and independent from parent email choice")
    func attachmentShareRecordsArePerAgent() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let emailID = try await insertTestMessage(store: store, emailID: "message-with-attachment", attachmentCount: 1)
        try store.upsertEmailAttachment(
            attachmentID: "attachment-per-agent",
            emailID: emailID,
            filename: "agent-plan.txt",
            mimeType: "text/plain",
            sizeBytes: 32,
            contentHash: "hash-agent-plan"
        )

        #expect(try store.sharedEmailAttachmentIDs(emailID: emailID, agent: .codex).isEmpty)
        try store.shareEmailAttachments(attachmentIDs: ["attachment-per-agent"], for: .codex)
        #expect(try store.sharedEmailAttachmentIDs(emailID: emailID, agent: .codex) == Set(["attachment-per-agent"]))
        #expect(try store.sharedEmailAttachmentIDs(emailID: emailID, agent: .cowork).isEmpty)
        #expect(try store.isEmailAttachmentShared(attachmentID: "attachment-per-agent", agent: .codex))
        #expect(try !store.isEmailShared(emailID: emailID, agent: .codex))

        try store.shareEmails(emailIDs: [emailID], for: .codex)
        try store.unshareEmails(emailIDs: [emailID], for: .codex)
        #expect(try store.sharedEmailAttachmentIDs(emailID: emailID, agent: .codex) == Set(["attachment-per-agent"]))

        try store.unshareEmailAttachments(attachmentIDs: ["attachment-per-agent"], for: .codex)
        #expect(try store.sharedEmailAttachmentIDs(emailID: emailID, agent: .codex).isEmpty)
    }

    @Test("Private index mode does not enqueue plaintext body backfill")
    func privateModeSkipsPlaintextBodyBackfill() async throws {
        let (store, db, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        try store.upsertEmailMessage(
            emailID: "msg-private-index",
            accountID: Self.testAccountID,
            mailbox: "INBOX",
            sender: "Test User <test@example.com>",
            senderEmail: "test@example.com",
            senderDomain: "example.com",
            recipients: "recipient@test.com",
            subject: "Private",
            receivedAt: ISO8601DateFormatter.shared.string(from: Date()),
            emlPath: tempDir.appendingPathComponent("legacy.eml").path,
            sizeBytes: 123,
            preview: nil
        )

        #expect(try store.emailsNeedingBodyBackfill(limit: 10).isEmpty)

        try db.execute(
            "UPDATE email_accounts SET index_privacy_mode = 'plaintextFTSWithDisclosure' WHERE account_id = ?",
            params: [Self.testAccountID]
        )
        let queued = try store.emailsNeedingBodyBackfill(limit: 10)
        #expect(queued.map { $0.emailID } == ["msg-private-index"])
    }

    // MARK: - CRUD

    @Test("Upsert and retrieve email message")
    func upsertAndRetrieve() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let emailID = try await insertTestMessage(store: store, subject: "Hello World")
        let messages = try store.emailMessages(accountID: Self.testAccountID)
        #expect(messages.count == 1)
        #expect(messages[0].emailID == emailID)
        #expect(messages[0].subject == "Hello World")
    }

    @Test("updateLocalViewedState sets column correctly")
    func localViewedState() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let emailID = try await insertTestMessage(store: store)
        let before = try store.emailMessages(accountID: Self.testAccountID)
        #expect(before[0].localIsViewed == false)

        try store.updateLocalViewedState(emailID: emailID, viewed: true)
        let after = try store.emailMessages(accountID: Self.testAccountID)
        #expect(after[0].localIsViewed == true)
    }

    @Test("markDeletedOnServer sets timestamp")
    func markDeletedOnServer() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let emailID = try await insertTestMessage(store: store)
        try store.markDeletedOnServer(emailID: emailID)
        let messages = try store.emailMessages(accountID: Self.testAccountID)
        #expect(messages[0].isDeletedOnServer == true)
        #expect(messages[0].deletedOnServerAt != nil)
    }

    @Test("Unviewed count uses local_is_viewed, not is_read")
    func unviewedCount() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        // Message: is_read=true but local_is_viewed=false (server marked read, user hasn't opened in Manifold)
        _ = try await insertTestMessage(store: store, emailID: "msg-1", isRead: true)
        _ = try await insertTestMessage(store: store, emailID: "msg-2", isRead: false)
        // Mark msg-2 as viewed
        try store.updateLocalViewedState(emailID: "msg-2", viewed: true)

        let count = try store.unviewedCount()
        #expect(count == 1) // msg-1 is unviewed (never opened), msg-2 is viewed
    }

    // MARK: - Quick Filters

    @Test("Quick filter .junk returns is_junk=1 messages")
    func quickFilterJunk() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let junkID = try await insertTestMessage(store: store, emailID: "junk-1", subject: "Spam")
        _ = try await insertTestMessage(store: store, emailID: "normal-1", subject: "Normal")
        try store.updateJunkState(emailID: junkID, isJunk: true)

        let results = try store.searchEmailMessages(filter: .junk)
        #expect(results.count == 1)
        #expect(results[0].emailID == "junk-1")
    }

    @Test("Quick filter .deletedOnServer returns deleted messages")
    func quickFilterDeleted() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let deletedID = try await insertTestMessage(store: store, emailID: "del-1")
        _ = try await insertTestMessage(store: store, emailID: "normal-1")
        try store.markDeletedOnServer(emailID: deletedID)

        let results = try store.searchEmailMessages(filter: .deletedOnServer)
        #expect(results.count == 1)
        #expect(results[0].emailID == "del-1")
    }

    // MARK: - FTS5 Body Search

    @Test("Body text search returns correct results")
    func bodyTextSearch() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let id1 = try await insertTestMessage(store: store, emailID: "msg-1", subject: "Invoice")
        let id2 = try await insertTestMessage(store: store, emailID: "msg-2", subject: "Meeting")
        try store.updateBodyText(emailID: id1, bodyText: "Please find attached the quarterly invoice for services rendered.")
        try store.updateBodyText(emailID: id2, bodyText: "Let's schedule a meeting to discuss the project timeline.")

        let results = try store.searchEmailMessages(tokens: [SearchToken(type: .body, value: "invoice")])
        #expect(results.count == 1)
        #expect(results[0].emailID == "msg-1")
    }

    @Test("Body text indexed count tracks progress")
    func bodyTextIndexedCount() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-1")
        _ = try await insertTestMessage(store: store, emailID: "msg-2")
        #expect(try store.bodyTextIndexedCount() == 0)

        try store.updateBodyText(emailID: "msg-1", bodyText: "Hello world")
        #expect(try store.bodyTextIndexedCount() == 1)
    }

    // MARK: - Rule Engine

    @Test("Single condition equals operator")
    func ruleEngineEquals() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-1", senderDomain: "work.com")
        _ = try await insertTestMessage(store: store, emailID: "msg-2", senderDomain: "personal.com")

        let rules = SmartMailboxRules(
            match: .all,
            conditions: [RuleCondition(field: "sender_domain", op: .equals, value: "work.com")]
        )
        let results = try store.smartMailboxMessages(rules: rules)
        #expect(results.count == 1)
        #expect(results[0].emailID == "msg-1")
    }

    @Test("Single condition contains operator")
    func ruleEngineContains() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-1", subject: "Q4 Invoice Report")
        _ = try await insertTestMessage(store: store, emailID: "msg-2", subject: "Team Lunch Plans")

        let rules = SmartMailboxRules(
            match: .all,
            conditions: [RuleCondition(field: "subject", op: .contains, value: "Invoice")]
        )
        let results = try store.smartMailboxMessages(rules: rules)
        #expect(results.count == 1)
        #expect(results[0].emailID == "msg-1")
    }

    @Test("AND matching requires all conditions")
    func ruleEngineAllMatch() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-1", senderDomain: "work.com", subject: "Invoice")
        _ = try await insertTestMessage(store: store, emailID: "msg-2", senderDomain: "work.com", subject: "Meeting")
        _ = try await insertTestMessage(store: store, emailID: "msg-3", senderDomain: "personal.com", subject: "Invoice")

        let rules = SmartMailboxRules(
            match: .all,
            conditions: [
                RuleCondition(field: "sender_domain", op: .equals, value: "work.com"),
                RuleCondition(field: "subject", op: .contains, value: "Invoice"),
            ]
        )
        let results = try store.smartMailboxMessages(rules: rules)
        #expect(results.count == 1)
        #expect(results[0].emailID == "msg-1")
    }

    @Test("OR matching requires any condition")
    func ruleEngineAnyMatch() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-1", senderDomain: "work.com", subject: "Hello")
        _ = try await insertTestMessage(store: store, emailID: "msg-2", senderDomain: "other.com", subject: "Invoice")
        _ = try await insertTestMessage(store: store, emailID: "msg-3", senderDomain: "other.com", subject: "Hello")

        let rules = SmartMailboxRules(
            match: .any,
            conditions: [
                RuleCondition(field: "sender_domain", op: .equals, value: "work.com"),
                RuleCondition(field: "subject", op: .contains, value: "Invoice"),
            ]
        )
        let results = try store.smartMailboxMessages(rules: rules)
        #expect(results.count == 2) // msg-1 (domain match) + msg-2 (subject match)
    }

    @Test("Privacy virtual fields join against privacy content index")
    func ruleEnginePrivacyVirtualFields() async throws {
        let (store, db, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-secret", subject: "Prod secret")
        _ = try await insertTestMessage(store: store, emailID: "msg-clean", subject: "General update")

        let privacyStore = PrivacyStore(db: db)
        try await privacyStore.upsertContentIndexRecord(
            PrivacyIndexRecord(
                id: "email:msg-secret:body",
                subjectKind: .emailBody,
                emailID: "msg-secret",
                displayName: "Prod secret",
                extractStatus: .ready,
                scanStatus: .scanned,
                containsSensitive: true,
                containsSecret: true,
                severity: .critical,
                matchedCategories: [.secret],
                findingsSummary: "contains secret"
            )
        )

        let rules = SmartMailboxRules(
            match: .all,
            conditions: [RuleCondition(field: "privacy_contains_secret", op: .equals, value: "true")]
        )
        let results = try store.smartMailboxMessages(rules: rules)
        #expect(results.count == 1)
        #expect(results[0].emailID == "msg-secret")
    }

    @Test("SQL injection attempt in field name rejected by whitelist")
    func ruleEngineSQLInjection() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store)

        let rules = SmartMailboxRules(
            match: .all,
            conditions: [RuleCondition(field: "sender; DROP TABLE email_messages;--", op: .equals, value: "hack")]
        )
        // Invalid field should be skipped, returning empty results (no crash)
        let results = try store.smartMailboxMessages(rules: rules)
        // Should not crash and should not have dropped the table
        let count = try store.emailMessageCount()
        #expect(count == 1) // Table still intact
        _ = results
    }

    @Test("Empty conditions array returns all messages")
    func ruleEngineEmptyConditions() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-1")
        _ = try await insertTestMessage(store: store, emailID: "msg-2")

        let rules = SmartMailboxRules(match: .all, conditions: [])
        let results = try store.smartMailboxMessages(rules: rules)
        #expect(results.count == 2)
    }

    @Test("Smart mailbox count matches results")
    func smartMailboxCount() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-1", isFlagged: true)
        _ = try await insertTestMessage(store: store, emailID: "msg-2", isFlagged: false)

        let rules = SmartMailboxRules(
            match: .all,
            conditions: [RuleCondition(field: "is_flagged", op: .equals, value: "1")]
        )
        let count = try store.smartMailboxCount(rules: rules)
        #expect(count == 1)
    }

    // MARK: - EXPUNGE Detection

    @Test("storedUIDs returns UIDs for a mailbox")
    func storedUIDs() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        // Insert messages first (FK constraint)
        _ = try await insertTestMessage(store: store, emailID: "msg-1")
        _ = try await insertTestMessage(store: store, emailID: "msg-2")
        _ = try await insertTestMessage(store: store, emailID: "msg-3")

        try store.upsertMailboxMembership(accountID: Self.testAccountID, mailbox: "INBOX", imapUID: 100, emailID: "msg-1")
        try store.upsertMailboxMembership(accountID: Self.testAccountID, mailbox: "INBOX", imapUID: 200, emailID: "msg-2")
        try store.upsertMailboxMembership(accountID: Self.testAccountID, mailbox: "Sent", imapUID: 50, emailID: "msg-3")

        let uids = try store.storedUIDs(accountID: Self.testAccountID, mailbox: "INBOX")
        #expect(uids == [100, 200])
    }

    @Test("Mailbox queries use membership when messages appear in multiple folders")
    func mailboxQueriesUseMembership() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-1", mailbox: "INBOX")
        _ = try await insertTestMessage(store: store, emailID: "msg-2", mailbox: "Sent")

        try store.upsertMailboxMembership(accountID: Self.testAccountID, mailbox: "INBOX", imapUID: 100, emailID: "msg-1")
        try store.upsertMailboxMembership(accountID: Self.testAccountID, mailbox: "Archive", imapUID: 200, emailID: "msg-1")
        try store.upsertMailboxMembership(accountID: Self.testAccountID, mailbox: "Sent", imapUID: 300, emailID: "msg-2")

        let mailboxes = try store.mailboxes(accountID: Self.testAccountID)
        #expect(mailboxes.count == 3)
        #expect(mailboxes.first(where: { $0.name == "Archive" })?.count == 1)
        #expect(mailboxes.first(where: { $0.name == "INBOX" })?.count == 1)
        #expect(mailboxes.first(where: { $0.name == "Sent" })?.count == 1)

        let archiveMessages = try store.emailMessages(accountID: Self.testAccountID, mailbox: "Archive")
        #expect(archiveMessages.count == 1)
        #expect(archiveMessages[0].emailID == "msg-1")
    }

    @Test("Mailbox queries fall back to email_messages mailbox when membership rows are missing")
    func mailboxQueriesFallbackWithoutMembership() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-1", mailbox: "Sent Messages")
        _ = try await insertTestMessage(store: store, emailID: "msg-2", mailbox: "INBOX")

        let sentMessages = try store.messagesInMailbox(accountID: Self.testAccountID, mailbox: "Sent Messages")
        #expect(sentMessages.count == 1)
        #expect(sentMessages[0].emailID == "msg-1")
    }

    @Test("Mailbox resolver maps iCloud-style aliases to typed mailboxes")
    func mailboxResolverMapsICLoudAliases() {
        let mailboxes = [
            mailboxRecord(mailboxName: "INBOX", flags: ["\\\\Inbox"], sortOrder: 0),
            mailboxRecord(mailboxName: "Sent Messages", flags: ["\\\\Sent"], sortOrder: 1),
            mailboxRecord(mailboxName: "Deleted Messages", flags: ["\\\\Trash"], sortOrder: 2),
            mailboxRecord(mailboxName: "Archive", flags: ["\\\\Archive"], sortOrder: 3),
        ]

        #expect(MailboxResolver.resolve(requestedName: "INBOX", imapMailboxes: mailboxes) == "INBOX")
        #expect(MailboxResolver.resolve(requestedName: "Sent", imapMailboxes: mailboxes) == "Sent Messages")
        #expect(MailboxResolver.resolve(requestedName: "Trash", imapMailboxes: mailboxes) == "Deleted Messages")
        #expect(MailboxResolver.resolve(requestedName: "Archive", imapMailboxes: mailboxes) == "Archive")
    }

    @Test("markMissingFromMailbox sets missing_from timestamp")
    func markMissing() async throws {
        let (store, db, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-1")
        try store.upsertMailboxMembership(accountID: Self.testAccountID, mailbox: "INBOX", imapUID: 100, emailID: "msg-1")
        try store.markMissingFromMailbox(accountID: Self.testAccountID, mailbox: "INBOX", missingUIDs: [100])

        let rows = try db.queryAll("SELECT missing_from FROM email_mailbox_membership WHERE imap_uid = '100'")
        #expect(rows.first?["missing_from"] != nil)
    }

    @Test("clearMissingFrom resets timestamp for reappeared UIDs")
    func clearMissing() async throws {
        let (store, db, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-1")
        try store.upsertMailboxMembership(accountID: Self.testAccountID, mailbox: "INBOX", imapUID: 100, emailID: "msg-1")
        try store.markMissingFromMailbox(accountID: Self.testAccountID, mailbox: "INBOX", missingUIDs: [100])
        try store.clearMissingFrom(accountID: Self.testAccountID, mailbox: "INBOX", reappearedUIDs: [100])

        let rows = try db.queryAll("SELECT missing_from FROM email_mailbox_membership WHERE imap_uid = '100'")
        #expect(rows.first?["missing_from"] == nil)
    }

    @Test("confirmServerDeletions marks messages missing from ALL mailboxes")
    func confirmDeletions() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        // Create message first, then add memberships in two mailboxes
        _ = try await insertTestMessage(store: store, emailID: "msg-1")
        try store.upsertMailboxMembership(accountID: Self.testAccountID, mailbox: "INBOX", imapUID: 100, emailID: "msg-1")
        try store.upsertMailboxMembership(accountID: Self.testAccountID, mailbox: "Archive", imapUID: 50, emailID: "msg-1")

        // Mark missing from INBOX only
        try store.markMissingFromMailbox(accountID: Self.testAccountID, mailbox: "INBOX", missingUIDs: [100])

        // Should NOT confirm deletion (still in Archive)
        let confirmed1 = try store.confirmServerDeletions()
        #expect(confirmed1 == 0)

        // Now mark missing from Archive too
        try store.markMissingFromMailbox(accountID: Self.testAccountID, mailbox: "Archive", missingUIDs: [50])

        // Should confirm deletion (missing from ALL mailboxes)
        let confirmed2 = try store.confirmServerDeletions()
        #expect(confirmed2 == 1)

        let messages = try store.emailMessages(accountID: Self.testAccountID)
        #expect(messages[0].isDeletedOnServer == true)
    }

    // MARK: - Email Sync Engine Helpers

    @Test("HTML stripping removes tags and decodes entities")
    func stripHTML() {
        let html = "<html><body><h1>Hello</h1><p>World &amp; <b>friends</b></p></body></html>"
        let stripped = EmailSyncEngine.stripHTML(html)
        #expect(stripped.contains("Hello"))
        #expect(stripped.contains("World & friends"))
        #expect(!stripped.contains("<"))
    }

    @Test("Date normalization converts RFC 2822 to ISO 8601")
    func normalizeDate() {
        let rfc = "Mon, 05 Jan 2013 12:00:00 +0000"
        let iso = EmailSyncEngine.normalizeDate(rfc)
        #expect(iso.contains("2013-01-05"))
        #expect(iso.contains("T"))
    }

    @Test("Email address extraction from display name format")
    func extractEmail() {
        let result = EmailSyncEngine.extractEmail(from: "John Doe <john@example.com>")
        #expect(result == "john@example.com")

        let bare = EmailSyncEngine.extractEmail(from: "john@example.com")
        #expect(bare == "john@example.com")

        let empty = EmailSyncEngine.extractEmail(from: "")
        #expect(empty == nil)
    }

    @Test("Domain extraction from email address")
    func extractDomain() {
        let domain = EmailSyncEngine.extractDomain(from: "john@example.com")
        #expect(domain == "example.com")

        let none = EmailSyncEngine.extractDomain(from: "noemail")
        #expect(none == nil)
    }

    // MARK: - sqlForCondition: notEquals operator

    @Test("Rule engine notEquals operator excludes matching rows")
    func ruleEngineNotEquals() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-1", senderDomain: "work.com")
        _ = try await insertTestMessage(store: store, emailID: "msg-2", senderDomain: "spam.com")
        _ = try await insertTestMessage(store: store, emailID: "msg-3", senderDomain: "work.com")

        let rules = SmartMailboxRules(
            match: .all,
            conditions: [RuleCondition(field: "sender_domain", op: .notEquals, value: "work.com")]
        )
        let results = try store.smartMailboxMessages(rules: rules)
        #expect(results.count == 1)
        #expect(results[0].emailID == "msg-2")
    }

    // MARK: - sqlForCondition: before / after operators

    @Test("Rule engine after operator filters by date")
    func ruleEngineAfter() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let fmt = ISO8601DateFormatter()
        let old = fmt.string(from: Date(timeIntervalSince1970: 1_000_000))
        let recent = fmt.string(from: Date(timeIntervalSince1970: 2_000_000))

        try store.upsertEmailMessage(
            emailID: "old-msg", accountID: Self.testAccountID, mailbox: "INBOX",
            sender: "a@test.com", recipients: "b@test.com", subject: "Old",
            receivedAt: old, emlPath: nil, sizeBytes: 100, preview: nil
        )
        try store.upsertEmailMessage(
            emailID: "recent-msg", accountID: Self.testAccountID, mailbox: "INBOX",
            sender: "a@test.com", recipients: "b@test.com", subject: "Recent",
            receivedAt: recent, emlPath: nil, sizeBytes: 100, preview: nil
        )

        let cutoff = fmt.string(from: Date(timeIntervalSince1970: 1_500_000))
        let rules = SmartMailboxRules(
            match: .all,
            conditions: [RuleCondition(field: "received_at", op: .after, value: cutoff)]
        )
        let results = try store.smartMailboxMessages(rules: rules)
        #expect(results.count == 1)
        #expect(results[0].emailID == "recent-msg")
    }

    @Test("Rule engine before operator filters by date")
    func ruleEngineBefore() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let fmt = ISO8601DateFormatter()
        let old = fmt.string(from: Date(timeIntervalSince1970: 1_000_000))
        let recent = fmt.string(from: Date(timeIntervalSince1970: 2_000_000))

        try store.upsertEmailMessage(
            emailID: "old-msg", accountID: Self.testAccountID, mailbox: "INBOX",
            sender: "a@test.com", recipients: "b@test.com", subject: "Old",
            receivedAt: old, emlPath: nil, sizeBytes: 100, preview: nil
        )
        try store.upsertEmailMessage(
            emailID: "recent-msg", accountID: Self.testAccountID, mailbox: "INBOX",
            sender: "a@test.com", recipients: "b@test.com", subject: "Recent",
            receivedAt: recent, emlPath: nil, sizeBytes: 100, preview: nil
        )

        let cutoff = fmt.string(from: Date(timeIntervalSince1970: 1_500_000))
        let rules = SmartMailboxRules(
            match: .all,
            conditions: [RuleCondition(field: "received_at", op: .before, value: cutoff)]
        )
        let results = try store.smartMailboxMessages(rules: rules)
        #expect(results.count == 1)
        #expect(results[0].emailID == "old-msg")
    }

    // MARK: - sqlForCondition: between operator

    @Test("Rule engine between operator filters date range")
    func ruleEngineBetween() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let fmt = ISO8601DateFormatter()
        let early = fmt.string(from: Date(timeIntervalSince1970: 1_000_000))
        let mid = fmt.string(from: Date(timeIntervalSince1970: 1_500_000))
        let late = fmt.string(from: Date(timeIntervalSince1970: 2_000_000))

        try store.upsertEmailMessage(
            emailID: "early-msg", accountID: Self.testAccountID, mailbox: "INBOX",
            sender: "a@test.com", recipients: "b@test.com", subject: "Early",
            receivedAt: early, emlPath: nil, sizeBytes: 100, preview: nil
        )
        try store.upsertEmailMessage(
            emailID: "mid-msg", accountID: Self.testAccountID, mailbox: "INBOX",
            sender: "a@test.com", recipients: "b@test.com", subject: "Mid",
            receivedAt: mid, emlPath: nil, sizeBytes: 100, preview: nil
        )
        try store.upsertEmailMessage(
            emailID: "late-msg", accountID: Self.testAccountID, mailbox: "INBOX",
            sender: "a@test.com", recipients: "b@test.com", subject: "Late",
            receivedAt: late, emlPath: nil, sizeBytes: 100, preview: nil
        )

        let lo = fmt.string(from: Date(timeIntervalSince1970: 1_200_000))
        let hi = fmt.string(from: Date(timeIntervalSince1970: 1_800_000))
        let rules = SmartMailboxRules(
            match: .all,
            conditions: [RuleCondition(field: "received_at", op: .between, value: "\(lo),\(hi)")]
        )
        let results = try store.smartMailboxMessages(rules: rules)
        #expect(results.count == 1)
        #expect(results[0].emailID == "mid-msg")
    }

    // MARK: - Shared Emails

    @Test("shareEmails is per-agent while legacy counts remain aggregate")
    func sharedEmailsLifecycle() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let id1 = try await insertTestMessage(store: store, emailID: "msg-1", senderDomain: "work.com")
        let id2 = try await insertTestMessage(store: store, emailID: "msg-2", senderDomain: "hidden.com")
        _ = try await insertTestMessage(store: store, emailID: "msg-3", senderDomain: "work.com")

        // Initially nothing is shared
        #expect(try store.isEmailShared(emailID: id1) == false)
        #expect(try store.sharedEmailCount() == 0)
        #expect(try store.sharedEmailCount(agent: .cowork) == 0)
        #expect(try store.sharedEmailCount(agent: .codex) == 0)

        // Share two emails with Claude only.
        let shareCount = try store.shareEmails(emailIDs: [id1, id2], label: "test")
        #expect(shareCount == 2)
        #expect(try store.isEmailShared(emailID: id1, agent: .cowork) == true)
        #expect(try store.isEmailShared(emailID: id1, agent: .codex) == false)
        #expect(try store.isEmailShared(emailID: id2, agent: .cowork) == true)
        #expect(try store.sharedEmailCount() == 2)
        #expect(try store.sharedEmailCount(agent: .cowork) == 2)
        #expect(try store.sharedEmailCount(agent: .codex) == 0)

        // Sharing the same message with Codex creates a separate per-agent grant.
        try store.shareEmails(emailIDs: [id1], for: .codex)
        #expect(try store.sharedEmailCount() == 3)
        #expect(try store.sharedEmailCount(agent: .cowork) == 2)
        #expect(try store.sharedEmailCount(agent: .codex) == 1)
        #expect(try store.sharedEmailIDs(agent: .codex) == Set([id1]))
        #expect(try store.sharedEmails(agent: .codex).map(\.emailID) == [id1])

        try store.unshareEmails(emailIDs: [id1], for: .cowork)
        #expect(try store.isEmailShared(emailID: id1, agent: .cowork) == false)
        #expect(try store.isEmailShared(emailID: id1, agent: .codex) == true)
        #expect(try store.isEmailShared(emailID: id1) == true)

        // visibleEmailCount excludes hidden domains
        let totalCount = try store.emailMessageCount()
        #expect(totalCount == 3)
        let visibleCount = try store.visibleEmailCount(hiddenDomains: ["hidden.com"])
        #expect(visibleCount == 2)

        // visibleEmailCount with empty set returns total
        let allVisible = try store.visibleEmailCount(hiddenDomains: [])
        #expect(allVisible == 3)
    }

    // MARK: - searchEmailMessages with freeText

    @Test("searchEmailMessages with freeText matches sender, subject, preview")
    func searchFreeText() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-1", sender: "Alice <alice@example.com>", subject: "Quarterly Report")
        _ = try await insertTestMessage(store: store, emailID: "msg-2", sender: "Bob <bob@example.com>", subject: "Lunch Plans")
        _ = try await insertTestMessage(store: store, emailID: "msg-3", sender: "Charlie <charlie@example.com>", subject: "Alice Review")

        // freeText "Alice" should match msg-1 (sender) and msg-3 (subject)
        let results = try store.searchEmailMessages(freeText: "Alice")
        let ids = Set(results.map(\.emailID))
        #expect(ids.contains("msg-1"))
        #expect(ids.contains("msg-3"))
        #expect(!ids.contains("msg-2"))
    }

    // MARK: - conditionsFromQuickFilter: .unread and .flagged

    @Test("Quick filter .unread returns only unread messages")
    func quickFilterUnread() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-read", isRead: true)
        _ = try await insertTestMessage(store: store, emailID: "msg-unread", isRead: false)

        let results = try store.searchEmailMessages(filter: .unread)
        #expect(results.count == 1)
        #expect(results[0].emailID == "msg-unread")
    }

    @Test("Quick filter .flagged returns only flagged messages")
    func quickFilterFlagged() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        _ = try await insertTestMessage(store: store, emailID: "msg-flagged", isFlagged: true)
        _ = try await insertTestMessage(store: store, emailID: "msg-normal", isFlagged: false)

        let results = try store.searchEmailMessages(filter: .flagged)
        #expect(results.count == 1)
        #expect(results[0].emailID == "msg-flagged")
    }

    /// Removing an email account drops every row that references one of
    /// its messages — `shared_emails`, `temporary_reveals`, `grant_emails`,
    /// `email_attachments`, and the messages themselves. Without this, an
    /// account removal leaves orphan share + reveal rows pointing at
    /// emails that no longer exist.
    @Test("Removing an email account cascades shared_emails and temporary_reveals")
    func removeAccountCascadesShareAndReveal() async throws {
        let (store, db, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let emailID = try await insertTestMessage(store: store, emailID: "msg-cascade")
        try store.shareEmails(emailIDs: [emailID], for: .cowork)
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute("""
            INSERT INTO temporary_reveals (reveal_id, agent, email_id, work_block_id, created_at)
            VALUES (?, ?, ?, ?, ?)
        """, params: ["rev-1", "cowork", emailID, "wb-test", now])

        let beforeShare = try store.sharedEmailIDs(agent: .cowork)
        #expect(beforeShare.contains(emailID))
        let beforeReveal = try db.queryScalar(
            "SELECT COUNT(*) FROM temporary_reveals WHERE email_id = ?",
            params: [emailID]
        )
        #expect(beforeReveal == "1")

        try store.removeEmailAccount(id: Self.testAccountID)

        let afterShare = try store.sharedEmailIDs(agent: .cowork)
        #expect(!afterShare.contains(emailID))
        let afterReveal = try db.queryScalar(
            "SELECT COUNT(*) FROM temporary_reveals WHERE email_id = ?",
            params: [emailID]
        )
        #expect(afterReveal == "0")
    }

    @Test("Removal history writes plain-text agent context before account reset")
    func removalHistoryWritesPlainTextAgentContext() async throws {
        let (store, _, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let emailID = try await insertTestMessage(
            store: store,
            emailID: "msg-history",
            subject: "Private mailbox subject"
        )
        try store.recordMailAccessAuditEvent(
            accountID: nil,
            emailID: emailID,
            agentID: TargetApp.codex.rawValue,
            sessionID: "session-1",
            accessKind: "bodyRead",
            policyGrantID: "grant-1",
            detailsRedacted: "opened message body"
        )
        try store.shareEmails(emailIDs: [emailID], for: .codex)

        let result = try store.writeAccountRemovalHistory(
            accountID: Self.testAccountID,
            destinationRoot: tempDir.appendingPathComponent("history", isDirectory: true)
        )

        let history = try String(contentsOfFile: result.contextArchivePath, encoding: .utf8)
        #expect(result.accessAuditEventCount == 1)
        #expect(result.sharedReferenceCount == 1)
        #expect(history.contains("Manifold Mail Account Removal History"))
        #expect(history.contains("access_kind=bodyRead"))
        #expect(history.contains("agent=codex"))
        #expect(history.contains("details_redacted=opened message body"))
        #expect(!history.contains("Private mailbox subject"))
    }

    @Test("Removing an email account deletes derived indexes and saved email references")
    func removeAccountDeletesDerivedIndexesAndSavedReferences() async throws {
        let (store, db, tempDir) = try await makeStore()
        defer { cleanup(tempDir) }

        let emailID = try await insertTestMessage(store: store, emailID: "msg-derived")
        try store.upsertEmailAttachment(
            attachmentID: "att-derived",
            emailID: emailID,
            filename: "secret.txt",
            mimeType: "text/plain",
            sizeBytes: 42,
            contentHash: "hash-derived",
            attachmentBlobCID: "blob-att-derived"
        )
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute("""
            INSERT INTO access_presets (preset_id, name, created_at, updated_at, target_app)
            VALUES (?, ?, ?, ?, ?)
        """, params: ["preset-mail", "Mail preset", now, now, TargetApp.codex.rawValue])
        try db.execute("""
            INSERT INTO access_preset_emails (preset_id, email_id)
            VALUES (?, ?)
        """, params: ["preset-mail", emailID])
        try db.execute("""
            INSERT INTO privacy_content_index (
                content_id, subject_kind, email_id, attachment_id, display_name,
                extract_status, scan_status, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, params: [
            "privacy-email",
            PrivacyIndexedContentKind.emailBody.rawValue,
            emailID,
            nil,
            "message",
            PrivacyExtractStatus.ready.rawValue,
            PrivacyIndexStatus.scanned.rawValue,
            now,
        ])
        try db.execute("""
            INSERT INTO privacy_content_index (
                content_id, subject_kind, email_id, attachment_id, display_name,
                extract_status, scan_status, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, params: [
            "privacy-attachment",
            PrivacyIndexedContentKind.emailAttachment.rawValue,
            emailID,
            "att-derived",
            "secret.txt",
            PrivacyExtractStatus.ready.rawValue,
            PrivacyIndexStatus.scanned.rawValue,
            now,
        ])
        try db.execute("""
            INSERT INTO privacy_detected_spans (
                span_id, content_id, category, start_utf16, end_utf16, source, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """, params: ["span-1", "privacy-email", "secret", "0", "6", "test", now])
        try db.execute("""
            INSERT INTO privacy_index_jobs (
                job_id, content_id, reason, priority, status, scheduled_at
            ) VALUES (?, ?, ?, ?, ?, ?)
        """, params: ["job-1", "privacy-attachment", "test", "1", "pending", now])
        try store.recordMailAccessAuditEvent(
            accountID: nil,
            emailID: emailID,
            agentID: TargetApp.codex.rawValue,
            sessionID: "session-1",
            accessKind: "search",
            policyGrantID: nil,
            detailsRedacted: "query"
        )

        try store.removeEmailAccount(id: Self.testAccountID)

        for table in [
            "access_preset_emails",
            "privacy_content_index",
            "privacy_detected_spans",
            "privacy_index_jobs",
            "mail_access_audit_events",
            "email_attachments",
            "email_messages",
        ] {
            let count = try db.queryScalar("SELECT COUNT(*) FROM \(table)")
            #expect(count == "0", "\(table) should be empty after account removal")
        }
    }
}
