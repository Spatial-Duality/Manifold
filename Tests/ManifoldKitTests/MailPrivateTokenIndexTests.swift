// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("Mail private token index")
struct MailPrivateTokenIndexTests {
    private static let accountID = "email-private-index"

    private func makeStore() throws -> (EmailStore, DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-mail-private-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute("""
            INSERT INTO email_accounts (
                account_id, display_name, provider_type, server, port, username,
                auth_type, sync_enabled, sync_interval_seconds, created_at, updated_at
            )
            VALUES (?, 'Private Index', 'other', 'imap.example.com', '993', 'user@example.com',
                    'app_password', 1, 300, ?, ?)
        """, params: [Self.accountID, now, now])
        return (EmailStore(db: db), db, tempDir)
    }

    @Test("Token normalization folds case and derives useful email parts")
    func tokenNormalization() {
        let tokens = MailPrivateTokenIndex.normalizedTokens("Résumé LAUNCH-code user@example.com")
        #expect(tokens.contains("resume"))
        #expect(tokens.contains("launch-code"))
        #expect(tokens.contains("launch"))
        #expect(tokens.contains("code"))
        #expect(tokens.contains("user@example.com"))
        #expect(tokens.contains("example"))
    }

    @Test("Term HMAC is stable within an account and different across accounts")
    func accountLocalTermHMAC() throws {
        let first = try MailPrivateTokenIndex.termHMAC(accountID: "account-a", normalizedToken: "launch")
        let second = try MailPrivateTokenIndex.termHMAC(accountID: "account-a", normalizedToken: "launch")
        let other = try MailPrivateTokenIndex.termHMAC(accountID: "account-b", normalizedToken: "launch")

        #expect(first == second)
        #expect(first != other)
    }

    @Test("Term HMAC can reuse a derived account key")
    func reusableAccountTermKeyMatchesSingleTermDerivation() throws {
        let key = try MailArchiveStore.accountDerivedKey(accountID: "account-a", purpose: "mail-private-index")
        let direct = try MailPrivateTokenIndex.termHMAC(accountID: "account-a", normalizedToken: "launch")
        let reusedKey = MailPrivateTokenIndex.termHMAC(normalizedToken: "launch", key: key)

        #expect(reusedKey == direct)
    }

    @Test("Private index supports multi-term body search without plaintext terms")
    func privateIndexSearch() throws {
        let (store, db, tempDir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try store.upsertEmailMessage(
            emailID: "msg-private-hit",
            accountID: Self.accountID,
            mailbox: "INBOX",
            sender: "Research Lead <lead@example.com>",
            senderEmail: "lead@example.com",
            senderDomain: "example.com",
            recipients: "user@example.com",
            subject: "Quarterly plan",
            receivedAt: ISO8601DateFormatter.shared.string(from: Date()),
            emlPath: nil,
            sizeBytes: 100,
            preview: nil
        )
        try store.upsertEmailMessage(
            emailID: "msg-private-miss",
            accountID: Self.accountID,
            mailbox: "INBOX",
            sender: "Other <other@example.com>",
            senderEmail: "other@example.com",
            senderDomain: "example.com",
            recipients: "user@example.com",
            subject: "Unrelated",
            receivedAt: ISO8601DateFormatter.shared.string(from: Date()),
            emlPath: nil,
            sizeBytes: 100,
            preview: nil
        )

        try store.replacePrivateTokenIndex(
            accountID: Self.accountID,
            emailID: "msg-private-hit",
            fields: [.body: "The private launch calendar moved to Friday."]
        )
        try store.replacePrivateTokenIndex(
            accountID: Self.accountID,
            emailID: "msg-private-miss",
            fields: [.body: "The public lunch calendar moved to Friday."]
        )

        let privateIDs = try store.privateTokenSearchEmailIDs(query: "private launch", accountID: Self.accountID)
        let tokenIDs = try store.searchEmailMessages(tokens: [SearchToken(type: .body, value: "private launch")]).map(\.emailID)
        let freeTextIDs = try store.searchEmailMessages(freeText: "private launch").map(\.emailID)
        #expect(privateIDs == ["msg-private-hit"], "privateIDs=\(privateIDs)")
        #expect(tokenIDs == ["msg-private-hit"], "tokenIDs=\(tokenIDs)")
        #expect(freeTextIDs == ["msg-private-hit"], "freeTextIDs=\(freeTextIDs)")

        let rows = try db.queryAll("SELECT term_hmac FROM mail_private_terms")
        #expect(!rows.isEmpty)
        let storedTerms = rows.compactMap { $0["term_hmac"] }.joined(separator: " ")
        #expect(!storedTerms.contains("private"))
        #expect(!storedTerms.contains("launch"))
    }
}
