// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Security
import os

private let mailSecretLogger = Logger(subsystem: "com.spatialduality.manifold", category: "mail-keychain")

public struct KeychainMailSecretStore: Sendable {
    public static let credentialService = "com.manifold.mail.credential"
    public static let oauthService = "com.manifold.mail.oauth"
    public static let archiveKeyService = "com.manifold.mail.archive-key"

    public init() {}

    @discardableResult
    public func store(_ secret: Data, reference: MailCredentialReference) -> Bool {
        delete(reference: reference)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.keychainService,
            kSecAttrAccount as String: reference.keychainAccount,
            kSecValueData as String: secret,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let dpStatus = SecItemAdd(query as CFDictionary, nil)
        if dpStatus == errSecSuccess { return true }

        var loginQuery = query
        loginQuery.removeValue(forKey: kSecUseDataProtectionKeychain as String)
        let status = SecItemAdd(loginQuery as CFDictionary, nil)
        if status != errSecSuccess {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown"
            mailSecretLogger.error("Mail keychain store failed (\(status)): \(message)")
        }
        return status == errSecSuccess
    }

    public func retrieve(reference: MailCredentialReference) -> Data? {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.keychainService,
            kSecAttrAccount as String: reference.keychainAccount,
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
    public func delete(reference: MailCredentialReference) -> Bool {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.keychainService,
            kSecAttrAccount as String: reference.keychainAccount,
        ]

        var dpQuery = baseQuery
        dpQuery[kSecUseDataProtectionKeychain as String] = true
        SecItemDelete(dpQuery as CFDictionary)

        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public static func appPasswordReference(accountID: String) -> MailCredentialReference {
        MailCredentialReference(
            kind: .appPassword,
            keychainService: credentialService,
            keychainAccount: "mail-account:\(accountID):app-password"
        )
    }

    public static func manualPasswordReference(accountID: String) -> MailCredentialReference {
        MailCredentialReference(
            kind: .manualPassword,
            keychainService: credentialService,
            keychainAccount: "mail-account:\(accountID):manual-password"
        )
    }

    public static func microsoftTokenReference(accountID: String) -> MailCredentialReference {
        MailCredentialReference(
            kind: .oauthTokenSet,
            keychainService: oauthService,
            keychainAccount: "mail-account:\(accountID):microsoft-token-set"
        )
    }
}
