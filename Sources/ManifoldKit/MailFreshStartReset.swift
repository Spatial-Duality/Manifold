// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import Security

private let mailResetLogger = Logger(subsystem: "com.spatialduality.manifold", category: "mail-reset")

public enum MailFreshStartReset {
    public static let appliedKey = "mail_fresh_start_v39_applied_at"
    public static let legacyAccountIDsKey = "mail_fresh_start_v39_legacy_account_ids_json"
    public static let cleanupKey = "mail_fresh_start_v39_runtime_cleanup_at"

    public static func cleanupIfNeeded(
        db: DatabaseConnection,
        backupRoot: URL,
        archiveRoot: URL,
        fileManager: FileManager = .default
    ) throws {
        guard try db.queryScalar(
            "SELECT value FROM runtime_settings WHERE key = ? LIMIT 1",
            params: [cleanupKey]
        ) == nil else {
            return
        }

        for accountID in try legacyAccountIDsMarkedForCleanup(db: db) {
            deleteLegacyCredential(accountID: accountID)
            let secretStore = KeychainMailSecretStore()
            for reference in knownCredentialReferences(accountID: accountID) {
                secretStore.delete(reference: reference)
            }
        }

        try removeDirectoryIfPresent(backupRoot, fileManager: fileManager)
        try removeDirectoryIfPresent(archiveRoot, fileManager: fileManager)

        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            """
            INSERT INTO runtime_settings (key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """,
            params: [cleanupKey, now, now]
        )
        mailResetLogger.info("Mail fresh-start runtime cleanup complete")
    }

    public static func legacyAccountIDsMarkedForCleanup(db: DatabaseConnection) throws -> [String] {
        guard let json = try db.queryScalar(
            "SELECT value FROM runtime_settings WHERE key = ? LIMIT 1",
            params: [legacyAccountIDsKey]
        ), let data = json.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    public static func knownCredentialReferences(accountID: String) -> [MailCredentialReference] {
        [
            KeychainMailSecretStore.appPasswordReference(accountID: accountID),
            KeychainMailSecretStore.manualPasswordReference(accountID: accountID),
            KeychainMailSecretStore.microsoftTokenReference(accountID: accountID),
        ]
    }

    private static func removeDirectoryIfPresent(_ url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    @discardableResult
    private static func deleteLegacyCredential(accountID: String) -> Bool {
        let service = "com.spatialduality.manifold.email.\(accountID)"
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
        ]

        var dataProtectionQuery = baseQuery
        dataProtectionQuery[kSecUseDataProtectionKeychain as String] = true
        SecItemDelete(dataProtectionQuery as CFDictionary)

        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
