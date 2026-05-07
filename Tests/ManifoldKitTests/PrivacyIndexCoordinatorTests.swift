// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import Testing
@testable import ManifoldKit
@testable import ManifoldRuntime

@Suite("Privacy Index Coordinator")
struct PrivacyIndexCoordinatorTests {
    private struct TestContext {
        let tempDir: URL
        let db: DatabaseConnection
        let grantStore: GrantStore
        let emailStore: EmailStore
        let privacyStore: PrivacyStore
        let coordinator: PrivacyIndexCoordinator
    }

    private func makeContext() throws -> TestContext {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-privacy-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        try DatabaseMigrator(db: db).migrate()

        let grantStore = GrantStore(db: db)
        let emailStore = EmailStore(db: db)
        let privacyStore = PrivacyStore(db: db)
        let runtimeSettingsStore = RuntimeSettingsStore(db: db)
        let finderTagLedgerStore = try FinderTagLedgerStore(db: db)
        let emailSyncEngine = EmailSyncEngine(emailStore: emailStore)
        let runtimeManager = PrivacyRuntimeManager(
            storageURL: tempDir.appendingPathComponent("privacy-models", isDirectory: true)
        )
        let mlxBackend = MLXPrivacyBackend(runtimeManager: runtimeManager)
        let coordinator = PrivacyIndexCoordinator(
            store: privacyStore,
            grantStore: grantStore,
            emailStore: emailStore,
            emailSyncEngine: emailSyncEngine,
            runtimeSettingsStore: runtimeSettingsStore,
            finderTagLedgerStore: finderTagLedgerStore,
            defaultStoragePath: tempDir.appendingPathComponent("privacy-models", isDirectory: true).path,
            rulesOnlyBackend: RulesOnlyPrivacyBackend(),
            mlxBackend: mlxBackend
        )
        return TestContext(
            tempDir: tempDir,
            db: db,
            grantStore: grantStore,
            emailStore: emailStore,
            privacyStore: privacyStore,
            coordinator: coordinator
        )
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func runtimeEML(subject: String, body: String, attachmentFilename: String, attachmentData: Data) -> String {
        let boundary = "MANIFOLD-TEST-BOUNDARY"
        let attachment = attachmentData.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return """
        From: Ops <ops@runtime.test>
        To: ada@example.com
        Subject: \(subject)
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="\(boundary)"

        --\(boundary)
        Content-Type: text/plain; charset="utf-8"

        \(body)
        --\(boundary)
        Content-Type: text/plain; name="\(attachmentFilename)"
        Content-Transfer-Encoding: base64
        Content-Disposition: attachment; filename="\(attachmentFilename)"

        \(attachment)
        --\(boundary)--
        """
    }

    @Test("Bootstrap seeds privacy smart mailboxes and indexes files, emails, and attachments")
    func bootstrapIndexesSeededCorpus() async throws {
        let context = try makeContext()
        defer { cleanup(context.tempDir) }

        let sourceRoot = context.tempDir.appendingPathComponent("Sources/Privacy", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let docsRoot = sourceRoot.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsRoot, withIntermediateDirectories: true)

        let sensitiveText = """
        Customer outreach draft
        Email: ada@example.com
        Address: 123 Market Street
        Secret: sk-test-1234567890abcdefghijklmnop
        """
        let notesText = "General release notes without personal information."
        let sensitiveURL = docsRoot.appendingPathComponent("CustomerDraft.txt")
        let notesURL = docsRoot.appendingPathComponent("ReleaseNotes.md")
        let unsupportedURL = docsRoot.appendingPathComponent("Archive.bin")
        try sensitiveText.write(to: sensitiveURL, atomically: true, encoding: .utf8)
        try notesText.write(to: notesURL, atomically: true, encoding: .utf8)
        try Data([0, 1, 2, 255]).write(to: unsupportedURL)

        let sourceID = try await context.grantStore.addSource(displayName: "Privacy", rootPath: sourceRoot.path)

        let account = try context.emailStore.addEmailAccount(
            displayName: "Runtime Inbox",
            providerType: EmailProvider.gmail.rawValue,
            server: "imap.runtime.test",
            port: 993,
            username: "runtime@manifold.test"
        )
        try context.emailStore.upsertIMAPMailbox(
            accountID: account.accountID,
            name: "INBOX",
            delimiter: "/",
            flags: ["\\\\Inbox"],
            isSelectable: true
        )

        let attachmentData = Data("Account number 1234-5678 and secret sk-abcdef1234567890abcdef12".utf8)
        let emlURL = context.tempDir.appendingPathComponent("runtime-message.eml")
        try runtimeEML(
            subject: "Privacy review needed",
            body: "Hi Ada Example, please review ada@example.com before sharing.",
            attachmentFilename: "customer-packet.txt",
            attachmentData: attachmentData
        ).write(to: emlURL, atomically: true, encoding: .utf8)

        try context.emailStore.upsertEmailMessage(
            emailID: "runtime-email-1",
            accountID: account.accountID,
            mailbox: "INBOX",
            sender: "Ops <ops@runtime.test>",
            senderEmail: "ops@runtime.test",
            senderDomain: "runtime.test",
            recipients: "ada@example.com",
            subject: "Privacy review needed",
            receivedAt: ISO8601DateFormatter.shared.string(from: Date()),
            emlPath: emlURL.path,
            sizeBytes: (try Data(contentsOf: emlURL)).count,
            preview: "Please review the attached customer packet before sharing.",
            contentType: "text/plain",
            isRead: false,
            isFlagged: true,
            messageIDHeader: "<runtime-email-1@runtime.test>",
            attachmentCount: 1
        )
        try context.emailStore.upsertEmailAttachment(
            attachmentID: "runtime-attachment-1",
            emailID: "runtime-email-1",
            filename: "customer-packet.txt",
            mimeType: "text/plain",
            sizeBytes: attachmentData.count,
            contentHash: sha256(attachmentData)
        )
        try context.emailStore.upsertMailboxMembership(
            accountID: account.accountID,
            mailbox: "INBOX",
            imapUID: 1,
            emailID: "runtime-email-1"
        )

        try await context.privacyStore.upsertSettings(
            PrivacyPreflightSettings(
                isEnabled: true,
                selectedBackend: .rulesOnly,
                installState: .installed,
                modelVersion: "rules-only-v1",
                storagePath: context.tempDir.appendingPathComponent("privacy-models", isDirectory: true).path
            )
        )

        await context.coordinator.bootstrap()

        var lastStatus: PrivacyIndexRuntimeStatus?
        for _ in 0..<40 {
            let status = try await context.coordinator.runtimeStatus()
            lastStatus = status
            if status.indexedItems >= 4, status.failedJobs >= 1, status.queuedJobs == 0, status.runningJobs == 0 {
                break
            }
            try await Task.sleep(for: .milliseconds(150))
        }

        let status = try #require(lastStatus)
        #expect(status.indexedItems >= 4)
        #expect(status.failedJobs >= 1)
        #expect(status.watchedSources.contains(sourceID))

        let records = try await context.coordinator.listIndex(
            scope: PrivacyIndexScope(),
            filter: PrivacyIndexFilter(),
            limit: 32
        )
        let unsupported = try #require(records.first(where: { $0.relativePath == "Docs/Archive.bin" }))
        #expect(unsupported.extractStatus == .unsupported)
        #expect(unsupported.scanStatus == .failed)

        let sourceRecord = try #require(records.first(where: { $0.relativePath == "Docs/CustomerDraft.txt" }))
        #expect(sourceRecord.containsSensitive)
        #expect(sourceRecord.containsSecret)

        let emailRecordCandidate = records.first {
            $0.subjectKind == .emailBody && $0.emailID == "runtime-email-1"
        }
        let emailRecord = try #require(emailRecordCandidate)
        #expect(emailRecord.scanStatus == .scanned)
        #expect(emailRecord.containsSensitive)

        let attachmentRecordCandidate = records.first {
            $0.subjectKind == .emailAttachment && $0.attachmentID == "runtime-attachment-1"
        }
        let attachmentRecord = try #require(attachmentRecordCandidate)
        #expect(attachmentRecord.scanStatus == .scanned)
        #expect(attachmentRecord.containsSecret)

        let mailboxNames = Set(try context.emailStore.allSmartMailboxes().map(\.displayName))
        #expect(mailboxNames.isSuperset(of: ["Has My Info", "Has Secret", "Third-Party Private", "Org Only", "Needs Review"]))
    }

    @Test("Extractor reads attachment text from stored eml payload")
    func extractorReadsAttachmentFromStoredEML() async throws {
        let context = try makeContext()
        defer { cleanup(context.tempDir) }

        let attachmentData = Data("Account number 1234-5678 and secret sk-abcdef1234567890abcdef12".utf8)
        let emlURL = context.tempDir.appendingPathComponent("attachment-message.eml")
        try runtimeEML(
            subject: "Attachment test",
            body: "See attachment.",
            attachmentFilename: "customer-packet.txt",
            attachmentData: attachmentData
        ).write(to: emlURL, atomically: true, encoding: .utf8)

        let account = try context.emailStore.addEmailAccount(
            displayName: "Runtime Inbox",
            providerType: EmailProvider.gmail.rawValue,
            server: "imap.runtime.test",
            port: 993,
            username: "runtime@manifold.test"
        )
        try context.emailStore.upsertEmailMessage(
            emailID: "runtime-email-2",
            accountID: account.accountID,
            mailbox: "INBOX",
            sender: "Ops <ops@runtime.test>",
            senderEmail: "ops@runtime.test",
            senderDomain: "runtime.test",
            recipients: "ada@example.com",
            subject: "Attachment test",
            receivedAt: ISO8601DateFormatter.shared.string(from: Date()),
            emlPath: emlURL.path,
            sizeBytes: (try Data(contentsOf: emlURL)).count,
            preview: "See attachment.",
            contentType: "text/plain"
        )
        try context.emailStore.upsertEmailAttachment(
            attachmentID: "runtime-attachment-2",
            emailID: "runtime-email-2",
            filename: "customer-packet.txt",
            mimeType: "text/plain",
            sizeBytes: attachmentData.count,
            contentHash: sha256(attachmentData)
        )

        let extractor = PrivacyContentExtractor()
        let attachmentCandidate = try context.emailStore.emailAttachment(id: "runtime-attachment-2")
        let emailCandidate = try context.emailStore.emailMessage(id: "runtime-email-2")
        let attachment = try #require(attachmentCandidate)
        let email = try #require(emailCandidate)

        let result = await extractor.extractEmailAttachment(attachment, email: email)

        #expect(result.extractStatus == .ready)
        #expect(result.extractor == "plain-text")
        #expect(result.text?.contains("Account number 1234-5678") == true)
        #expect(result.text?.contains("sk-abcdef1234567890abcdef12") == true)
    }

    @Test("Extractor reads attachment text from archive v2 attachment blob")
    func extractorReadsAttachmentFromArchiveBlob() async throws {
        let context = try makeContext()
        defer { cleanup(context.tempDir) }

        let account = try context.emailStore.addEmailAccount(
            displayName: "Runtime Inbox",
            providerType: EmailProvider.gmail.rawValue,
            server: "imap.runtime.test",
            port: 993,
            username: "runtime@manifold.test"
        )
        try context.emailStore.upsertEmailMessage(
            emailID: "runtime-email-archive-attachment",
            accountID: account.accountID,
            mailbox: "INBOX",
            sender: "Ops <ops@runtime.test>",
            senderEmail: "ops@runtime.test",
            senderDomain: "runtime.test",
            recipients: "ada@example.com",
            subject: "Attachment archive test",
            receivedAt: ISO8601DateFormatter.shared.string(from: Date()),
            emlPath: nil,
            sizeBytes: 0,
            preview: nil,
            contentType: "text/plain"
        )

        let archiveRoot = context.tempDir.appendingPathComponent("MailArchive")
        let archive = try MailArchiveStore(rootURL: archiveRoot)
        let attachmentData = Data("Token abc-123 and customer account 9876".utf8)
        let stored = try archive.store(
            accountID: account.accountID,
            kind: .attachment,
            plaintext: attachmentData
        )
        try context.emailStore.recordMailBlob(stored)
        try context.emailStore.upsertEmailAttachment(
            attachmentID: "runtime-attachment-archive-v2",
            emailID: "runtime-email-archive-attachment",
            filename: "archive-packet.txt",
            mimeType: "text/plain",
            sizeBytes: attachmentData.count,
            contentHash: sha256(attachmentData),
            attachmentBlobCID: stored.contentID
        )

        let extractor = PrivacyContentExtractor(mailArchiveRoot: archiveRoot)
        let attachment = try #require(try context.emailStore.emailAttachment(id: "runtime-attachment-archive-v2"))
        let email = try #require(try context.emailStore.emailMessage(id: "runtime-email-archive-attachment"))

        let result = await extractor.extractEmailAttachment(attachment, email: email)

        #expect(result.extractStatus == .ready)
        #expect(result.extractor == "plain-text")
        #expect(result.text?.contains("customer account 9876") == true)
    }
}
