// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("MailArchiveStore")
struct MailArchiveStoreTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-mail-archive-\(UUID().uuidString)")
            .appendingPathComponent("MailArchive")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("Stores and reads encrypted archive v2 message objects")
    func storesAndReadsMessageObject() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let archive = try MailArchiveStore(rootURL: root)
        let message = Data("Subject: Quarterly Secret\r\n\r\nThe launch code is not plaintext on disk.".utf8)
        let stored = try archive.storeMessage(accountID: "account-a", plaintext: message)

        #expect(stored.manifestURL.pathExtension == "mmanifest")
        #expect(stored.objectURL.pathExtension == "mblob")
        #expect(FileManager.default.fileExists(atPath: stored.manifestURL.path))
        #expect(FileManager.default.fileExists(atPath: stored.objectURL.path))
        #expect(try archive.readObject(atManifestURL: stored.manifestURL) == message)
        #expect(EmailSyncEngine.readStoredMessage(at: stored.manifestURL.path) == message)

        let manifestBytes = try Data(contentsOf: stored.manifestURL)
        let objectBytes = try Data(contentsOf: stored.objectURL)
        #expect(!manifestBytes.containsSubsequence(Data("Quarterly Secret".utf8)))
        #expect(!objectBytes.containsSubsequence(Data("launch code".utf8)))
    }

    @Test("Content IDs dedupe within an account but not across accounts")
    func contentIDsAreAccountLocal() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let archive = try MailArchiveStore(rootURL: root)
        let message = Data("Subject: Same bytes\r\n\r\nSame canonical content.".utf8)

        let first = try archive.storeMessage(accountID: "account-a", plaintext: message)
        let second = try archive.storeMessage(accountID: "account-a", plaintext: message)
        let otherAccount = try archive.storeMessage(accountID: "account-b", plaintext: message)

        #expect(first.contentID == second.contentID)
        #expect(first.objectURL == second.objectURL)
        #expect(first.contentID != otherAccount.contentID)
    }

    @Test("Tampered encrypted blobs fail authentication")
    func tamperedBlobFailsAuthentication() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let archive = try MailArchiveStore(rootURL: root)
        let message = Data("Subject: Tamper\r\n\r\nThis must authenticate.".utf8)
        let stored = try archive.storeMessage(accountID: "account-a", plaintext: message)

        var objectBytes = try Data(contentsOf: stored.objectURL)
        objectBytes[objectBytes.count - 1] ^= 0x01
        try objectBytes.write(to: stored.objectURL, options: .atomic)

        do {
            _ = try archive.readObject(atManifestURL: stored.manifestURL)
            Issue.record("Expected tampered mail archive blob to fail authentication")
        } catch {
        }
    }

    @Test("Streams file-backed message objects into chunked archive blobs")
    func streamsFileBackedMessageObject() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let archive = try MailArchiveStore(rootURL: root)
        let plaintextURL = root.deletingLastPathComponent().appendingPathComponent("large-source.eml")
        let message = Data(
            ("Subject: Large Stream\r\n\r\n" + String(repeating: "streaming mail payload ", count: 120_000)).utf8
        )
        try message.write(to: plaintextURL)

        let stored = try archive.storeMessage(accountID: "account-a", plaintextFileURL: plaintextURL)

        #expect(stored.byteCountPlaintext == Int64(message.count))
        #expect(stored.manifestURL.pathExtension == "mmanifest")
        #expect(stored.objectURL.pathExtension == "mblob")
        #expect(try archive.readObject(atManifestURL: stored.manifestURL) == message)

        let objectBytes = try Data(contentsOf: stored.objectURL)
        #expect(!objectBytes.containsSubsequence(Data("Large Stream".utf8)))
        #expect(!objectBytes.containsSubsequence(Data("streaming mail payload".utf8)))
    }

    @Test("File-backed and data-backed content IDs match for the same account")
    func fileBackedContentIDMatchesDataContentID() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let archive = try MailArchiveStore(rootURL: root)
        let plaintextURL = root.deletingLastPathComponent().appendingPathComponent("same-source.eml")
        let message = Data("Subject: Same\r\n\r\nCanonical bytes.".utf8)
        try message.write(to: plaintextURL)

        let dataStored = try archive.storeMessage(accountID: "account-a", plaintext: message)
        let fileStored = try archive.storeMessage(accountID: "account-a", plaintextFileURL: plaintextURL)

        #expect(fileStored.contentID == dataStored.contentID)
        #expect(fileStored.objectURL == dataStored.objectURL)
    }

    @Test("Removing an account archive deletes only that account directory")
    func removeAccountArchiveDeletesOnlySelectedAccount() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let archive = try MailArchiveStore(rootURL: root)
        let removed = try archive.storeMessage(
            accountID: "account-remove",
            plaintext: Data("Subject: Remove\r\n\r\nDelete this account.".utf8)
        )
        let kept = try archive.storeMessage(
            accountID: "account-keep",
            plaintext: Data("Subject: Keep\r\n\r\nKeep this account.".utf8)
        )

        #expect(try archive.removeAccountArchive(accountID: "account-remove"))
        #expect(!FileManager.default.fileExists(atPath: removed.manifestURL.path))
        #expect(!FileManager.default.fileExists(atPath: removed.objectURL.path))
        #expect(FileManager.default.fileExists(atPath: kept.manifestURL.path))
        #expect(FileManager.default.fileExists(atPath: kept.objectURL.path))
        #expect(try archive.readObject(atManifestURL: kept.manifestURL) == Data("Subject: Keep\r\n\r\nKeep this account.".utf8))
    }
}

private extension Data {
    func containsSubsequence(_ needle: Data) -> Bool {
        guard !needle.isEmpty, needle.count <= count else { return false }
        return range(of: needle) != nil
    }
}
