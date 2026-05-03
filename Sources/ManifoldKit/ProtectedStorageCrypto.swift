// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import Security

enum ProtectedStorageError: LocalizedError {
    case missingKeyMaterial
    case invalidCiphertext
    case keyGenerationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingKeyMaterial:
            return "Missing encryption key material for the protected local store."
        case .invalidCiphertext:
            return "The protected local store contains invalid encrypted data."
        case .keyGenerationFailed(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown"
            return "Failed to generate a protected local store key (\(status)): \(message)"
        }
    }
}

private final class ProtectedStorageKeyCache: @unchecked Sendable {
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

/// Encrypts high-sensitivity local Manifold content at rest using a shared
/// symmetric key stored in the macOS Keychain when available.
public enum ProtectedStorageCrypto: Sendable {
    private static let service = "com.spatialduality.manifold.storage"
    private static let account = "local-store-key-v1"
    private static let magic = Data([0x4D, 0x4E, 0x46, 0x31]) // "MNF1"
    private static let keyLength = 32
    private static let keyCache = ProtectedStorageKeyCache()

    public static func encrypt(_ plaintext: Data) throws -> Data {
        let key = try storageKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw ProtectedStorageError.invalidCiphertext
        }
        return magic + combined
    }

    public static func decrypt(_ stored: Data) throws -> Data {
        guard stored.starts(with: magic) else {
            // Backward compatibility for older plaintext local content.
            return stored
        }

        let payload = stored.dropFirst(magic.count)
        let sealedBox = try AES.GCM.SealedBox(combined: payload)
        return try AES.GCM.open(sealedBox, using: storageKey())
    }

    public static func isEncryptedPayload(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    private static func storageKey() throws -> SymmetricKey {
        if let testKey = testStorageKey() {
            return testKey
        }

        if let cached = keyCache.get(), cached.count == keyLength {
            return SymmetricKey(data: cached)
        }

        if let existing = retrieveKeyData(), existing.count == keyLength {
            keyCache.set(existing)
            return SymmetricKey(data: existing)
        }

        var keyBytes = [UInt8](repeating: 0, count: keyLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        guard status == errSecSuccess else {
            throw ProtectedStorageError.keyGenerationFailed(status)
        }

        let keyData = Data(keyBytes)
        guard storeKeyData(keyData) else {
            throw ProtectedStorageError.missingKeyMaterial
        }
        keyCache.set(keyData)
        return SymmetricKey(data: keyData)
    }

    private static func testStorageKey() -> SymmetricKey? {
        let environment = ProcessInfo.processInfo.environment
        guard let seed = environment["MANIFOLD_TEST_PROTECTED_STORAGE_KEY"], !seed.isEmpty else {
            return nil
        }
        let digest = SHA256.hash(data: Data(seed.utf8))
        return SymmetricKey(data: Data(digest))
    }

    private static func retrieveKeyData() -> Data? {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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

    @discardableResult
    private static func storeKeyData(_ data: Data) -> Bool {
        _ = deleteKeyData()

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]

        var dpQuery = baseQuery
        dpQuery[kSecUseDataProtectionKeychain as String] = true
        dpQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let dpStatus = SecItemAdd(dpQuery as CFDictionary, nil)
        if dpStatus == errSecSuccess {
            return true
        }

        let status = SecItemAdd(baseQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    @discardableResult
    private static func deleteKeyData() -> Bool {
        keyCache.set(nil)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        var dpQuery = baseQuery
        dpQuery[kSecUseDataProtectionKeychain as String] = true
        SecItemDelete(dpQuery as CFDictionary)

        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
