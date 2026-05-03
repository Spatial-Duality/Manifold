// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import Security

public enum MailArchiveStoreError: LocalizedError, Sendable {
    case invalidPath
    case invalidBlob
    case invalidManifest
    case missingArchiveKey
    case keychainFailure(OSStatus)
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidPath:
            "The mail archive path is not a valid archive v2 path."
        case .invalidBlob:
            "The mail archive blob is invalid or incomplete."
        case .invalidManifest:
            "The mail archive manifest is invalid or cannot be authenticated."
        case .missingArchiveKey:
            "The mail archive encryption key is missing."
        case .keychainFailure(let status):
            "Mail archive keychain operation failed with status \(status)."
        case .verificationFailed:
            "The encrypted mail archive object could not be verified after writing."
        }
    }
}

public struct MailArchiveStoredObject: Sendable, Equatable {
    public let accountID: String
    public let kind: MailArchiveObjectKind
    public let contentID: String
    public let manifestID: String
    public let manifestURL: URL
    public let objectURL: URL
    public let byteCountPlaintext: Int64
    public let byteCountCiphertext: Int64
    public let createdAt: String
}

private struct MailBlobChunkManifest: Codable, Sendable, Equatable {
    var index: Int
    var plaintextByteCount: Int
    var sealedByteCount: Int
}

private struct MailBlobManifest: Codable, Sendable, Equatable {
    var version: Int
    var kind: MailArchiveObjectKind
    var accountID: String
    var contentID: String
    var manifestID: String
    var chunkSize: Int
    var chunks: [MailBlobChunkManifest]
    var byteCountPlaintext: Int64
    var byteCountCiphertext: Int64
    var createdAt: String
}

private final class MailArchiveRootKeyCache: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    func get() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func set(_ data: Data?) {
        lock.lock()
        self.data = data
        lock.unlock()
    }
}

/// Archive v2 stores canonical mail objects as account-local, keyed-content
/// addressed, authenticated encrypted blobs. Readable `.eml` files are only
/// produced by explicit export code; sync writes `.mblob` plus `.mmanifest`.
public struct MailArchiveStore {
    public static let chunkSize = 1_048_576

    private static let archiveVersion = 2
    private static let blobMagic = Data([0x4D, 0x42, 0x4C, 0x32]) // "MBL2"
    private static let manifestMagic = Data([0x4D, 0x4D, 0x46, 0x32]) // "MMF2"
    private static let rootKeyLength = 32
    private static let keychainService = "com.manifold.mail.archive-key"
    private static let keychainAccount = "archive-root:local-v2"
    private static let rootKeyCache = MailArchiveRootKeyCache()

    private let rootURL: URL
    private let fileManager: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL
        self.fileManager = fileManager
        try ensureRoot()
        try reconcileStaging()
    }

    public func storeMessage(accountID: String, plaintext: Data) throws -> MailArchiveStoredObject {
        try store(accountID: accountID, kind: .messageRFC822, plaintext: plaintext)
    }

    public func storeMessage(accountID: String, plaintextFileURL: URL) throws -> MailArchiveStoredObject {
        try store(accountID: accountID, kind: .messageRFC822, plaintextFileURL: plaintextFileURL)
    }

    public func store(accountID: String, kind: MailArchiveObjectKind, plaintext: Data) throws -> MailArchiveStoredObject {
        let rootKey = try Self.archiveRootKey()
        let encryptionKey = Self.deriveKey(rootKey: rootKey, accountID: accountID, purpose: "mail-blob-encryption")
        let contentIDKey = Self.deriveKey(rootKey: rootKey, accountID: accountID, purpose: "mail-content-id")
        let contentID = Self.contentID(for: plaintext, key: contentIDKey)
        let manifestID = try Self.randomHex(byteCount: 32)
        let objectURL = objectURL(accountID: accountID, contentID: contentID)
        let manifestURL = manifestURL(accountID: accountID, manifestID: manifestID)
        let createdAt = ISO8601DateFormatter.shared.string(from: Date())

        let stagingURL = stagingDirectory(accountID: accountID, jobID: UUID().uuidString)
        try LocalFileProtection.ensureDirectory(at: stagingURL)
        defer { try? fileManager.removeItem(at: stagingURL) }

        let objectAlreadyExists = fileManager.fileExists(atPath: objectURL.path)
        var chunkManifests: [MailBlobChunkManifest] = []
        var ciphertextBytes: Int64

        if objectAlreadyExists {
            ciphertextBytes = try fileSize(objectURL)
            chunkManifests = try readManifestForExistingObject(
                accountID: accountID,
                contentID: contentID,
                plaintextByteCount: Int64(plaintext.count)
            )
        } else {
            let stagedObjectURL = stagingURL.appendingPathComponent("\(contentID).mblob")
            let encrypted = try Self.encryptBlob(
                plaintext: plaintext,
                accountID: accountID,
                kind: kind,
                contentID: contentID,
                key: encryptionKey
            )
            chunkManifests = encrypted.chunks
            ciphertextBytes = Int64(encrypted.payload.count)
            try LocalFileProtection.writeOwnerOnly(encrypted.payload, to: stagedObjectURL)
            try promote(stagedObjectURL, to: objectURL)
        }

        let manifest = MailBlobManifest(
            version: Self.archiveVersion,
            kind: kind,
            accountID: accountID,
            contentID: contentID,
            manifestID: manifestID,
            chunkSize: Self.chunkSize,
            chunks: chunkManifests,
            byteCountPlaintext: Int64(plaintext.count),
            byteCountCiphertext: ciphertextBytes,
            createdAt: createdAt
        )
        let stagedManifestURL = stagingURL.appendingPathComponent("\(manifestID).mmanifest")
        let manifestPayload = try Self.encryptManifest(manifest, accountID: accountID, manifestID: manifestID, key: encryptionKey)
        try LocalFileProtection.writeOwnerOnly(manifestPayload, to: stagedManifestURL)
        try promote(stagedManifestURL, to: manifestURL)

        let stored = MailArchiveStoredObject(
            accountID: accountID,
            kind: kind,
            contentID: contentID,
            manifestID: manifestID,
            manifestURL: manifestURL,
            objectURL: objectURL,
            byteCountPlaintext: Int64(plaintext.count),
            byteCountCiphertext: ciphertextBytes,
            createdAt: createdAt
        )

        let verified = try readObject(atManifestURL: manifestURL)
        guard verified == plaintext else {
            throw MailArchiveStoreError.verificationFailed
        }
        return stored
    }

    public func store(
        accountID: String,
        kind: MailArchiveObjectKind,
        plaintextFileURL: URL
    ) throws -> MailArchiveStoredObject {
        let rootKey = try Self.archiveRootKey()
        let encryptionKey = Self.deriveKey(rootKey: rootKey, accountID: accountID, purpose: "mail-blob-encryption")
        let contentIDKey = Self.deriveKey(rootKey: rootKey, accountID: accountID, purpose: "mail-content-id")
        let source = try Self.contentID(forFileAt: plaintextFileURL, key: contentIDKey)
        let contentID = source.contentID
        let manifestID = try Self.randomHex(byteCount: 32)
        let objectURL = objectURL(accountID: accountID, contentID: contentID)
        let manifestURL = manifestURL(accountID: accountID, manifestID: manifestID)
        let createdAt = ISO8601DateFormatter.shared.string(from: Date())

        let stagingURL = stagingDirectory(accountID: accountID, jobID: UUID().uuidString)
        try LocalFileProtection.ensureDirectory(at: stagingURL)
        defer { try? fileManager.removeItem(at: stagingURL) }

        let objectAlreadyExists = fileManager.fileExists(atPath: objectURL.path)
        let chunkManifests: [MailBlobChunkManifest]
        let ciphertextBytes: Int64

        if objectAlreadyExists {
            ciphertextBytes = try fileSize(objectURL)
            chunkManifests = try readManifestForExistingObject(
                accountID: accountID,
                contentID: contentID,
                plaintextByteCount: source.byteCount
            )
        } else {
            let stagedObjectURL = stagingURL.appendingPathComponent("\(contentID).mblob")
            let encrypted = try Self.encryptBlob(
                plaintextFileURL: plaintextFileURL,
                stagedObjectURL: stagedObjectURL,
                plaintextByteCount: source.byteCount,
                accountID: accountID,
                kind: kind,
                contentID: contentID,
                key: encryptionKey
            )
            chunkManifests = encrypted.chunks
            ciphertextBytes = encrypted.byteCountCiphertext
            try promote(stagedObjectURL, to: objectURL)
        }

        let manifest = MailBlobManifest(
            version: Self.archiveVersion,
            kind: kind,
            accountID: accountID,
            contentID: contentID,
            manifestID: manifestID,
            chunkSize: Self.chunkSize,
            chunks: chunkManifests,
            byteCountPlaintext: source.byteCount,
            byteCountCiphertext: ciphertextBytes,
            createdAt: createdAt
        )
        let stagedManifestURL = stagingURL.appendingPathComponent("\(manifestID).mmanifest")
        let manifestPayload = try Self.encryptManifest(manifest, accountID: accountID, manifestID: manifestID, key: encryptionKey)
        try LocalFileProtection.writeOwnerOnly(manifestPayload, to: stagedManifestURL)
        try promote(stagedManifestURL, to: manifestURL)

        let stored = MailArchiveStoredObject(
            accountID: accountID,
            kind: kind,
            contentID: contentID,
            manifestID: manifestID,
            manifestURL: manifestURL,
            objectURL: objectURL,
            byteCountPlaintext: source.byteCount,
            byteCountCiphertext: ciphertextBytes,
            createdAt: createdAt
        )

        guard try verifyObject(atManifestURL: manifestURL, equalsPlaintextAt: plaintextFileURL) else {
            throw MailArchiveStoreError.verificationFailed
        }
        return stored
    }

    public func readObject(contentID: String, accountID: String) throws -> Data {
        let objectURL = objectURL(accountID: accountID, contentID: contentID)
        guard fileManager.fileExists(atPath: objectURL.path) else {
            throw MailArchiveStoreError.invalidBlob
        }
        let manifests = try manifestURLs(accountID: accountID)
        for manifestURL in manifests {
            let manifest = try readManifest(at: manifestURL)
            if manifest.contentID == contentID {
                return try readObject(atManifestURL: manifestURL)
            }
        }
        throw MailArchiveStoreError.invalidManifest
    }

    public func readObject(atManifestURL manifestURL: URL) throws -> Data {
        let accountID = try Self.accountID(fromManifestURL: manifestURL)
        let manifest = try readManifest(at: manifestURL)
        guard manifest.accountID == accountID else {
            throw MailArchiveStoreError.invalidManifest
        }

        let objectURL = objectURL(accountID: accountID, contentID: manifest.contentID)
        let payload = try Data(contentsOf: objectURL, options: [.mappedIfSafe])
        return try Self.decryptBlob(payload, manifest: manifest, key: encryptionKey(accountID: accountID))
    }

    @discardableResult
    public func removeAccountArchive(accountID: String) throws -> Bool {
        let accountURL = try accountRootURL(accountID: accountID)
        guard fileManager.fileExists(atPath: accountURL.path) else {
            return false
        }
        try fileManager.removeItem(at: accountURL)
        return true
    }

    public static func isArchiveV2Path(_ url: URL) -> Bool {
        url.pathExtension == "mmanifest" && url.pathComponents.contains("MailArchive")
    }

    public static func readArchivedObject(atManifestURL manifestURL: URL) throws -> Data {
        let rootURL = try rootURL(fromManifestURL: manifestURL)
        let store = try MailArchiveStore(rootURL: rootURL)
        return try store.readObject(atManifestURL: manifestURL)
    }

    // MARK: - Paths

    private func ensureRoot() throws {
        try LocalFileProtection.ensureDirectory(at: rootURL)
        try LocalFileProtection.ensureDirectory(at: rootURL.appendingPathComponent("v2/accounts"))
    }

    private func reconcileStaging() throws {
        let accountsURL = rootURL.appendingPathComponent("v2/accounts")
        guard let accounts = try? fileManager.contentsOfDirectory(at: accountsURL, includingPropertiesForKeys: nil) else {
            return
        }
        for accountURL in accounts {
            let stagingURL = accountURL.appendingPathComponent("staging")
            guard fileManager.fileExists(atPath: stagingURL.path) else { continue }
            let jobs = (try? fileManager.contentsOfDirectory(at: stagingURL, includingPropertiesForKeys: nil)) ?? []
            for job in jobs {
                try? fileManager.removeItem(at: job)
            }
        }
    }

    private func objectURL(accountID: String, contentID: String) -> URL {
        rootURL
            .appendingPathComponent("v2/accounts")
            .appendingPathComponent(accountID)
            .appendingPathComponent("objects")
            .appendingPathComponent(String(contentID.prefix(2)))
            .appendingPathComponent("\(contentID).mblob")
    }

    private func manifestURL(accountID: String, manifestID: String) -> URL {
        rootURL
            .appendingPathComponent("v2/accounts")
            .appendingPathComponent(accountID)
            .appendingPathComponent("manifests")
            .appendingPathComponent(String(manifestID.prefix(2)))
            .appendingPathComponent("\(manifestID).mmanifest")
    }

    private func stagingDirectory(accountID: String, jobID: String) -> URL {
        rootURL
            .appendingPathComponent("v2/accounts")
            .appendingPathComponent(accountID)
            .appendingPathComponent("staging")
            .appendingPathComponent(jobID)
    }

    private func accountRootURL(accountID: String) throws -> URL {
        guard !accountID.isEmpty,
              !accountID.contains("/"),
              !accountID.contains("\\"),
              accountID != ".",
              accountID != ".." else {
            throw MailArchiveStoreError.invalidPath
        }

        let accountsRoot = rootURL.appendingPathComponent("v2/accounts").standardizedFileURL
        let accountURL = accountsRoot.appendingPathComponent(accountID, isDirectory: true).standardizedFileURL
        guard accountURL.path.hasPrefix(accountsRoot.path + "/") else {
            throw MailArchiveStoreError.invalidPath
        }
        return accountURL
    }

    private func promote(_ stagedURL: URL, to finalURL: URL) throws {
        try LocalFileProtection.ensureDirectory(at: finalURL.deletingLastPathComponent())
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: stagedURL)
            return
        }
        try fileManager.moveItem(at: stagedURL, to: finalURL)
        try LocalFileProtection.secureFile(at: finalURL)
    }

    private func manifestURLs(accountID: String) throws -> [URL] {
        let manifestsRoot = rootURL
            .appendingPathComponent("v2/accounts")
            .appendingPathComponent(accountID)
            .appendingPathComponent("manifests")
        guard fileManager.fileExists(atPath: manifestsRoot.path) else { return [] }
        let shardURLs = try fileManager.contentsOfDirectory(at: manifestsRoot, includingPropertiesForKeys: nil)
        return try shardURLs.flatMap { shard in
            try fileManager.contentsOfDirectory(at: shard, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "mmanifest" }
        }
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - Manifest

    private func readManifest(at manifestURL: URL) throws -> MailBlobManifest {
        let accountID = try Self.accountID(fromManifestURL: manifestURL)
        let manifestID = manifestURL.deletingPathExtension().lastPathComponent
        let payload = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        guard payload.starts(with: Self.manifestMagic) else {
            throw MailArchiveStoreError.invalidManifest
        }
        let sealed = try AES.GCM.SealedBox(combined: payload.dropFirst(Self.manifestMagic.count))
        let opened = try AES.GCM.open(
            sealed,
            using: encryptionKey(accountID: accountID),
            authenticating: Self.manifestAAD(accountID: accountID, manifestID: manifestID)
        )
        return try JSONDecoder().decode(MailBlobManifest.self, from: opened)
    }

    private static func encryptManifest(
        _ manifest: MailBlobManifest,
        accountID: String,
        manifestID: String,
        key: SymmetricKey
    ) throws -> Data {
        let data = try JSONEncoder().encode(manifest)
        let sealed = try AES.GCM.seal(data, using: key, authenticating: manifestAAD(accountID: accountID, manifestID: manifestID))
        guard let combined = sealed.combined else {
            throw MailArchiveStoreError.invalidManifest
        }
        return manifestMagic + combined
    }

    private func readManifestForExistingObject(
        accountID: String,
        contentID: String,
        plaintextByteCount: Int64
    ) throws -> [MailBlobChunkManifest] {
        let manifests = try manifestURLs(accountID: accountID)
        for manifestURL in manifests {
            let manifest = try readManifest(at: manifestURL)
            if manifest.contentID == contentID {
                return manifest.chunks
            }
        }

        let objectSize = try fileSize(objectURL(accountID: accountID, contentID: contentID))
        return [
            MailBlobChunkManifest(
                index: 0,
                plaintextByteCount: Int(min(plaintextByteCount, Int64(Int.max))),
                sealedByteCount: max(Int(objectSize) - Self.blobMagic.count - 4, 0)
            ),
        ]
    }

    // MARK: - Blob encryption

    private static func encryptBlob(
        plaintext: Data,
        accountID: String,
        kind: MailArchiveObjectKind,
        contentID: String,
        key: SymmetricKey
    ) throws -> (payload: Data, chunks: [MailBlobChunkManifest]) {
        let totalChunks = max(1, Int(ceil(Double(plaintext.count) / Double(chunkSize))))
        var output = blobMagic
        var chunks: [MailBlobChunkManifest] = []

        if plaintext.isEmpty {
            let sealed = try AES.GCM.seal(Data(), using: key, authenticating: chunkAAD(
                accountID: accountID,
                kind: kind,
                contentID: contentID,
                index: 0,
                totalChunks: 1
            ))
            guard let combined = sealed.combined else {
                throw MailArchiveStoreError.invalidBlob
            }
            appendLengthPrefixed(combined, to: &output)
            chunks.append(MailBlobChunkManifest(index: 0, plaintextByteCount: 0, sealedByteCount: combined.count))
            return (output, chunks)
        }

        var offset = 0
        var index = 0
        while offset < plaintext.count {
            let end = min(offset + chunkSize, plaintext.count)
            let chunk = plaintext[offset..<end]
            let sealed = try AES.GCM.seal(Data(chunk), using: key, authenticating: chunkAAD(
                accountID: accountID,
                kind: kind,
                contentID: contentID,
                index: index,
                totalChunks: totalChunks
            ))
            guard let combined = sealed.combined else {
                throw MailArchiveStoreError.invalidBlob
            }
            appendLengthPrefixed(combined, to: &output)
            chunks.append(MailBlobChunkManifest(
                index: index,
                plaintextByteCount: chunk.count,
                sealedByteCount: combined.count
            ))
            offset = end
            index += 1
        }
        return (output, chunks)
    }

    private static func encryptBlob(
        plaintextFileURL: URL,
        stagedObjectURL: URL,
        plaintextByteCount: Int64,
        accountID: String,
        kind: MailArchiveObjectKind,
        contentID: String,
        key: SymmetricKey
    ) throws -> (byteCountCiphertext: Int64, chunks: [MailBlobChunkManifest]) {
        try LocalFileProtection.writeOwnerOnly(Data(), to: stagedObjectURL, options: [])

        let input = try FileHandle(forReadingFrom: plaintextFileURL)
        defer { try? input.close() }

        let output = try FileHandle(forWritingTo: stagedObjectURL)
        defer { try? output.close() }

        try output.write(contentsOf: blobMagic)
        var ciphertextBytes = Int64(blobMagic.count)
        var chunks: [MailBlobChunkManifest] = []
        let totalChunks = max(1, Int(ceil(Double(plaintextByteCount) / Double(chunkSize))))

        if plaintextByteCount == 0 {
            let sealed = try AES.GCM.seal(
                Data(),
                using: key,
                authenticating: chunkAAD(
                    accountID: accountID,
                    kind: kind,
                    contentID: contentID,
                    index: 0,
                    totalChunks: 1
                )
            )
            guard let combined = sealed.combined else {
                throw MailArchiveStoreError.invalidBlob
            }
            try writeLengthPrefixed(combined, to: output)
            ciphertextBytes += Int64(4 + combined.count)
            chunks.append(MailBlobChunkManifest(index: 0, plaintextByteCount: 0, sealedByteCount: combined.count))
            try LocalFileProtection.secureFile(at: stagedObjectURL)
            return (ciphertextBytes, chunks)
        }

        var index = 0
        while true {
            let chunk = try input.read(upToCount: chunkSize) ?? Data()
            guard !chunk.isEmpty else { break }
            let sealed = try AES.GCM.seal(
                chunk,
                using: key,
                authenticating: chunkAAD(
                    accountID: accountID,
                    kind: kind,
                    contentID: contentID,
                    index: index,
                    totalChunks: totalChunks
                )
            )
            guard let combined = sealed.combined else {
                throw MailArchiveStoreError.invalidBlob
            }
            try writeLengthPrefixed(combined, to: output)
            ciphertextBytes += Int64(4 + combined.count)
            chunks.append(MailBlobChunkManifest(
                index: index,
                plaintextByteCount: chunk.count,
                sealedByteCount: combined.count
            ))
            index += 1
        }

        guard index == totalChunks else {
            throw MailArchiveStoreError.invalidBlob
        }
        try LocalFileProtection.secureFile(at: stagedObjectURL)
        return (ciphertextBytes, chunks)
    }

    private static func decryptBlob(_ payload: Data, manifest: MailBlobManifest, key: SymmetricKey) throws -> Data {
        guard payload.starts(with: blobMagic) else {
            throw MailArchiveStoreError.invalidBlob
        }
        var offset = blobMagic.count
        var plaintext = Data()
        plaintext.reserveCapacity(Int(manifest.byteCountPlaintext))

        for chunk in manifest.chunks.sorted(by: { $0.index < $1.index }) {
            let sealedData = try readLengthPrefixed(payload, offset: &offset)
            guard sealedData.count == chunk.sealedByteCount else {
                throw MailArchiveStoreError.invalidBlob
            }
            let sealed = try AES.GCM.SealedBox(combined: sealedData)
            let opened = try AES.GCM.open(
                sealed,
                using: key,
                authenticating: chunkAAD(
                    accountID: manifest.accountID,
                    kind: manifest.kind,
                    contentID: manifest.contentID,
                    index: chunk.index,
                    totalChunks: manifest.chunks.count
                )
            )
            guard opened.count == chunk.plaintextByteCount else {
                throw MailArchiveStoreError.invalidBlob
            }
            plaintext.append(opened)
        }

        guard Int64(plaintext.count) == manifest.byteCountPlaintext else {
            throw MailArchiveStoreError.invalidBlob
        }
        return plaintext
    }

    private static func appendLengthPrefixed(_ data: Data, to output: inout Data) {
        var length = UInt32(data.count).bigEndian
        withUnsafeBytes(of: &length) { output.append(contentsOf: $0) }
        output.append(data)
    }

    private static func writeLengthPrefixed(_ data: Data, to output: FileHandle) throws {
        var length = UInt32(data.count).bigEndian
        let lengthBytes = withUnsafeBytes(of: &length) { Data($0) }
        try output.write(contentsOf: lengthBytes)
        try output.write(contentsOf: data)
    }

    private static func readLengthPrefixed(_ data: Data, offset: inout Int) throws -> Data {
        guard offset + 4 <= data.count else {
            throw MailArchiveStoreError.invalidBlob
        }
        let length = data[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        offset += 4
        let end = offset + Int(length)
        guard end <= data.count else {
            throw MailArchiveStoreError.invalidBlob
        }
        defer { offset = end }
        return Data(data[offset..<end])
    }

    private static func readLengthPrefixed(from input: FileHandle) throws -> Data {
        let lengthBytes = try input.read(upToCount: 4) ?? Data()
        guard lengthBytes.count == 4 else {
            throw MailArchiveStoreError.invalidBlob
        }
        let length = lengthBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let payload = try input.read(upToCount: Int(length)) ?? Data()
        guard payload.count == Int(length) else {
            throw MailArchiveStoreError.invalidBlob
        }
        return payload
    }

    private static func chunkAAD(
        accountID: String,
        kind: MailArchiveObjectKind,
        contentID: String,
        index: Int,
        totalChunks: Int
    ) -> Data {
        Data("mail-archive-v2:chunk:\(accountID):\(kind.rawValue):\(contentID):\(index):\(totalChunks)".utf8)
    }

    private static func manifestAAD(accountID: String, manifestID: String) -> Data {
        Data("mail-archive-v2:manifest:\(accountID):\(manifestID)".utf8)
    }

    // MARK: - Keys

    private func encryptionKey(accountID: String) throws -> SymmetricKey {
        try Self.accountDerivedKey(accountID: accountID, purpose: "mail-blob-encryption")
    }

    static func accountDerivedKey(accountID: String, purpose: String) throws -> SymmetricKey {
        try deriveKey(rootKey: archiveRootKey(), accountID: accountID, purpose: purpose)
    }

    private static func contentID(for data: Data, key: SymmetricKey) -> String {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key)).mailArchiveHexString
    }

    private static func contentID(
        forFileAt fileURL: URL,
        key: SymmetricKey
    ) throws -> (contentID: String, byteCount: Int64) {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hmac = HMAC<SHA256>(key: key)
        var byteCount: Int64 = 0
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            guard !chunk.isEmpty else { break }
            hmac.update(data: chunk)
            byteCount += Int64(chunk.count)
        }
        return (Data(hmac.finalize()).mailArchiveHexString, byteCount)
    }

    private func verifyObject(atManifestURL manifestURL: URL, equalsPlaintextAt plaintextURL: URL) throws -> Bool {
        let accountID = try Self.accountID(fromManifestURL: manifestURL)
        let manifest = try readManifest(at: manifestURL)
        guard manifest.accountID == accountID else {
            throw MailArchiveStoreError.invalidManifest
        }

        let objectInput = try FileHandle(forReadingFrom: objectURL(accountID: accountID, contentID: manifest.contentID))
        defer { try? objectInput.close() }
        let plaintextInput = try FileHandle(forReadingFrom: plaintextURL)
        defer { try? plaintextInput.close() }

        let magic = try objectInput.read(upToCount: Self.blobMagic.count) ?? Data()
        guard magic == Self.blobMagic else {
            throw MailArchiveStoreError.invalidBlob
        }

        for chunk in manifest.chunks.sorted(by: { $0.index < $1.index }) {
            let sealedData = try Self.readLengthPrefixed(from: objectInput)
            guard sealedData.count == chunk.sealedByteCount else {
                throw MailArchiveStoreError.invalidBlob
            }
            let sealed = try AES.GCM.SealedBox(combined: sealedData)
            let opened = try AES.GCM.open(
                sealed,
                using: encryptionKey(accountID: accountID),
                authenticating: Self.chunkAAD(
                    accountID: manifest.accountID,
                    kind: manifest.kind,
                    contentID: manifest.contentID,
                    index: chunk.index,
                    totalChunks: manifest.chunks.count
                )
            )
            guard opened.count == chunk.plaintextByteCount else {
                throw MailArchiveStoreError.invalidBlob
            }
            let expected = try plaintextInput.read(upToCount: chunk.plaintextByteCount) ?? Data()
            guard expected == opened else {
                return false
            }
        }

        let trailingPlaintext = try plaintextInput.read(upToCount: 1) ?? Data()
        let trailingCiphertext = try objectInput.read(upToCount: 1) ?? Data()
        return trailingPlaintext.isEmpty && trailingCiphertext.isEmpty
    }

    private static func deriveKey(rootKey: SymmetricKey, accountID: String, purpose: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: rootKey,
            salt: Data(accountID.utf8),
            info: Data(purpose.utf8),
            outputByteCount: rootKeyLength
        )
    }

    private static func archiveRootKey() throws -> SymmetricKey {
        if let cached = rootKeyCache.get(), cached.count == rootKeyLength {
            return SymmetricKey(data: cached)
        }

        if let existing = retrieveRootKeyData() {
            if existing.count == rootKeyLength {
                rootKeyCache.set(existing)
                return SymmetricKey(data: existing)
            }
            deleteRootKeyData()
        }

        var bytes = [UInt8](repeating: 0, count: rootKeyLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw MailArchiveStoreError.keychainFailure(status)
        }
        let data = Data(bytes)
        try storeRootKeyData(data)
        if let stored = retrieveRootKeyData(), stored.count == rootKeyLength {
            rootKeyCache.set(stored)
            return SymmetricKey(data: stored)
        }
        rootKeyCache.set(data)
        return SymmetricKey(data: data)
    }

    private static func retrieveRootKeyData() -> Data? {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var dpQuery = baseQuery
        dpQuery[kSecUseDataProtectionKeychain as String] = true
        var result: AnyObject?
        var status = SecItemCopyMatching(dpQuery as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return data
        }

        result = nil
        status = SecItemCopyMatching(baseQuery as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func storeRootKeyData(_ data: Data) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
        ]

        var dpQuery = baseQuery
        dpQuery[kSecUseDataProtectionKeychain as String] = true
        dpQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let dpStatus = SecItemAdd(dpQuery as CFDictionary, nil)
        if dpStatus == errSecSuccess {
            return
        }
        if dpStatus == errSecDuplicateItem, retrieveRootKeyData()?.count == rootKeyLength {
            return
        }

        let status = SecItemAdd(baseQuery as CFDictionary, nil)
        if status == errSecDuplicateItem, retrieveRootKeyData()?.count == rootKeyLength {
            return
        }
        guard status == errSecSuccess else {
            throw MailArchiveStoreError.keychainFailure(status)
        }
    }

    private static func deleteRootKeyData() {
        rootKeyCache.set(nil)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        var dpQuery = baseQuery
        dpQuery[kSecUseDataProtectionKeychain as String] = true
        SecItemDelete(dpQuery as CFDictionary)
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static func randomHex(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw MailArchiveStoreError.keychainFailure(status)
        }
        return Data(bytes).mailArchiveHexString
    }

    // MARK: - Static path helpers

    private static func accountID(fromManifestURL manifestURL: URL) throws -> String {
        let manifestsURL = manifestURL.deletingLastPathComponent().deletingLastPathComponent()
        guard manifestsURL.lastPathComponent == "manifests" else {
            throw MailArchiveStoreError.invalidPath
        }
        let accountURL = manifestsURL.deletingLastPathComponent()
        guard accountURL.deletingLastPathComponent().lastPathComponent == "accounts" else {
            throw MailArchiveStoreError.invalidPath
        }
        return accountURL.lastPathComponent
    }

    private static func rootURL(fromManifestURL manifestURL: URL) throws -> URL {
        let rootURL = manifestURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard rootURL.lastPathComponent == "MailArchive" else {
            throw MailArchiveStoreError.invalidPath
        }
        return rootURL
    }
}

private extension Data {
    var mailArchiveHexString: String {
        let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)
        var chars = [UInt8](repeating: 0, count: count * 2)
        for (index, byte) in enumerated() {
            chars[index * 2] = hexDigits[Int(byte >> 4)]
            chars[index * 2 + 1] = hexDigits[Int(byte & 0x0F)]
        }
        return String(bytes: chars, encoding: .ascii) ?? ""
    }
}
