// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import Testing
@testable import ManifoldKit

@Suite("Mail exporter")
struct MailExporterTests {
    private static let accountID = "mail-export-account"

    private func makeContext() throws -> (EmailStore, MailArchiveStore, DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-mail-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        try DatabaseMigrator(db: db).migrate()
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute("""
            INSERT INTO email_accounts (
                account_id, display_name, provider_type, server, port, username,
                auth_type, sync_enabled, sync_interval_seconds, created_at, updated_at
            )
            VALUES (?, 'Export', 'other', 'imap.example.com', '993', 'user@example.com',
                    'app_password', 1, 300, ?, ?)
        """, params: [Self.accountID, now, now])
        let archive = try MailArchiveStore(rootURL: tempDir.appendingPathComponent("MailArchive"))
        return (EmailStore(db: db), archive, db, tempDir)
    }

    @Test("Explicit export decrypts archive v2 messages and attachment blobs")
    func exportsArchiveV2MessageAndAttachments() throws {
        let (store, archive, _, tempDir) = try makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let messageData = Data("Subject: Export\r\n\r\nEncrypted canonical message".utf8)
        let messageObject = try archive.storeMessage(accountID: Self.accountID, plaintext: messageData)
        let attachmentData = Data("Attachment payload".utf8)
        let attachmentObject = try archive.store(
            accountID: Self.accountID,
            kind: .attachment,
            plaintext: attachmentData
        )
        try store.recordMailBlob(messageObject)
        try store.recordMailBlob(attachmentObject)
        try store.upsertEmailMessage(
            emailID: "export-message-1",
            accountID: Self.accountID,
            mailbox: "INBOX",
            sender: "Export <export@example.com>",
            senderEmail: "export@example.com",
            senderDomain: "example.com",
            recipients: "user@example.com",
            subject: "Export / path:test",
            receivedAt: "2026-05-01T10:00:00Z",
            emlPath: messageObject.manifestURL.path,
            sizeBytes: messageData.count,
            preview: nil,
            canonicalBlobCID: messageObject.contentID
        )
        try store.upsertEmailAttachment(
            attachmentID: "export-attachment-1",
            emailID: "export-message-1",
            filename: "../secret.txt",
            mimeType: "text/plain",
            sizeBytes: attachmentData.count,
            contentHash: SHA256.hash(data: attachmentData).map { String(format: "%02x", $0) }.joined(),
            attachmentBlobCID: attachmentObject.contentID
        )

        let destination = tempDir.appendingPathComponent("Exported", isDirectory: true)
        let exporter = MailExporter(emailStore: store, archiveStore: archive)
        let result = try exporter.export(MailExportRequest(
            scope: .messages(["export-message-1"]),
            destinationPath: destination.path,
            includeAttachments: true,
            includeOriginalEML: true,
            createFolderPerMessage: false
        ))

        #expect(result.messageCount == 1)
        #expect(result.attachmentCount == 1)
        #expect(result.writtenPaths.count == 3)
        #expect(result.writtenPaths.allSatisfy {
            URL(fileURLWithPath: $0).standardizedFileURL.path.hasPrefix(destination.standardizedFileURL.path)
        })

        let emlPath = try #require(result.writtenPaths.first { $0.hasSuffix(".eml") })
        #expect(try Data(contentsOf: URL(fileURLWithPath: emlPath)) == messageData)

        let attachmentPath = try #require(result.writtenPaths.first { $0.hasSuffix(".txt") })
        #expect(URL(fileURLWithPath: attachmentPath).lastPathComponent == "secret.txt")
        #expect(try Data(contentsOf: URL(fileURLWithPath: attachmentPath)) == attachmentData)
    }

    @Test("Safe filenames remove traversal and duplicate exported names are uniqued")
    func safeFilenameAndDuplicateHandling() throws {
        #expect(MailExporter.safeFilename("../../a:b?.eml") == "a_b_.eml")

        let (store, archive, _, tempDir) = try makeContext()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let messageData = Data("Subject: Duplicate\r\n\r\nBody".utf8)
        let messageObject = try archive.storeMessage(accountID: Self.accountID, plaintext: messageData)
        try store.recordMailBlob(messageObject)
        for index in 1...2 {
            try store.upsertEmailMessage(
                emailID: "duplicate-\(index)",
                accountID: Self.accountID,
                mailbox: "INBOX",
                sender: "Export <export@example.com>",
                senderEmail: "export@example.com",
                senderDomain: "example.com",
                recipients: "user@example.com",
                subject: "Same",
                receivedAt: "2026-05-01T10:00:00Z",
                emlPath: messageObject.manifestURL.path,
                sizeBytes: messageData.count,
                preview: nil,
                canonicalBlobCID: messageObject.contentID
            )
        }

        let destination = tempDir.appendingPathComponent("Exported", isDirectory: true)
        let result = try MailExporter(emailStore: store, archiveStore: archive).export(MailExportRequest(
            scope: .messages(["duplicate-1", "duplicate-2"]),
            destinationPath: destination.path,
            includeAttachments: false,
            includeOriginalEML: true
        ))

        let filenames = result.writtenPaths.map { URL(fileURLWithPath: $0).lastPathComponent }
        #expect(Set(filenames).count == 2)
        #expect(filenames.allSatisfy { $0.hasSuffix(".eml") })
    }
}
