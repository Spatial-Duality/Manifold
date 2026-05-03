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

        let query = Self.dataProtectionStoreQuery(secret, reference: reference)
        let dpStatus = SecItemAdd(query as CFDictionary, nil)
        if dpStatus == errSecSuccess { return true }

        let status = SecItemAdd(Self.loginStoreQuery(secret, reference: reference) as CFDictionary, nil)
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

    /// Stores a pending credential for app-to-agent handoff in the
    /// login keychain. Pending handoffs intentionally avoid the data
    /// protection keychain because the app and LaunchAgent can have
    /// different entitlement contexts during local development.
    @discardableResult
    public func storePendingHandoff(
        _ secret: Data,
        reference: MailCredentialReference,
        trustedApplicationPaths _: [String]
    ) -> Bool {
        delete(reference: reference)

        // Keep the pending handoff in the login keychain so the app and
        // LaunchAgent share the same lookup scope. The trusted-application
        // ACL APIs were legacy SecKeychain APIs and are deprecated on macOS.
        let status = SecItemAdd(Self.loginStoreQuery(secret, reference: reference) as CFDictionary, nil)
        if status != errSecSuccess {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown"
            mailSecretLogger.error("Pending mail credential store failed (\(status)): \(message)")
        }
        return status == errSecSuccess
    }

    static func dataProtectionStoreQuery(
        _ secret: Data,
        reference: MailCredentialReference
    ) -> [String: Any] {
        var query = baseStoreQuery(secret, reference: reference)
        query[kSecUseDataProtectionKeychain as String] = true
        return query
    }

    static func loginStoreQuery(
        _ secret: Data,
        reference: MailCredentialReference
    ) -> [String: Any] {
        baseStoreQuery(secret, reference: reference)
    }

    private static func baseStoreQuery(
        _ secret: Data,
        reference: MailCredentialReference
    ) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.keychainService,
            kSecAttrAccount as String: reference.keychainAccount,
            kSecValueData as String: secret,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
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

    // MARK: - Pending credential handoff (R5)

    /// Account-name prefix the app uses when staging a credential in
    /// Keychain before the agent has accepted it. The agent reads from
    /// this slot, validates, then renames to the canonical
    /// `mail-account:{accountID}:{kind}` location on success or deletes
    /// on failure.
    ///
    /// Closes the IMAP-password-as-XPC-string smell: cleartext never
    /// crosses the XPC boundary as a String inside a `[String: Any]`
    /// payload. The app writes to Keychain; the agent reads from
    /// Keychain. Apple security guidance: write credentials in the
    /// least-privileged process, pass references over IPC.
    /// https://developer.apple.com/documentation/security/adding-a-password-to-the-keychain
    public static let pendingAccountPrefix = "mail-account:pending-"

    /// Reference for a staged credential awaiting agent validation.
    /// `pendingID` is a UUID generated by the app; the agent receives
    /// it over XPC as the only credential identifier.
    public static func pendingReference(
        pendingID: String,
        kind: MailCredentialKind
    ) -> MailCredentialReference {
        let suffix: String
        switch kind {
        case .appPassword:    suffix = "app-password"
        case .manualPassword: suffix = "manual-password"
        case .oauthTokenSet:  suffix = "microsoft-token-set"
        }
        let service: String = (kind == .oauthTokenSet) ? oauthService : credentialService
        return MailCredentialReference(
            kind: kind,
            keychainService: service,
            keychainAccount: "\(pendingAccountPrefix)\(pendingID):\(suffix)"
        )
    }

    /// Sweeps Keychain for pending credential entries older than `ttl`
    /// and deletes them. Call on app launch to clean entries left
    /// behind by app crashes mid-handoff. Idempotent and silent when
    /// no stale entries exist.
    public func sweepStalePendingCredentials(
        ttl: TimeInterval = 3600,
        now: Date = Date()
    ) {
        let services = [Self.credentialService, Self.oauthService]
        for service in services {
            sweepPending(in: service, olderThan: now.addingTimeInterval(-ttl))
        }
    }

    private func sweepPending(in service: String, olderThan cutoff: Date) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return }

        var swept = 0
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix(Self.pendingAccountPrefix) else { continue }
            let creationDate = item[kSecAttrCreationDate as String] as? Date ?? .distantPast
            guard creationDate < cutoff else { continue }
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            if SecItemDelete(deleteQuery as CFDictionary) == errSecSuccess {
                swept += 1
            }
        }
        if swept > 0 {
            mailSecretLogger.info("Swept \(swept) stale pending credential(s) from \(service)")
        }
    }
}
