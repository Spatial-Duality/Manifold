import Foundation
import Security
import os

private let keychainLogger = Logger(subsystem: "com.spatialduality.manifold", category: "keychain")

// MARK: - EmailProvider

public enum EmailProvider: String, Sendable, CaseIterable {
    case gmail, outlook, icloud, yahoo, fastmail, other

    public var displayName: String {
        switch self {
        case .gmail: "Gmail"
        case .outlook: "Outlook"
        case .icloud: "iCloud Mail"
        case .yahoo: "Yahoo Mail"
        case .fastmail: "Fastmail"
        case .other: "IMAP"
        }
    }

    public var systemImage: String {
        switch self {
        case .gmail: "envelope.fill"
        case .outlook: "envelope.fill"
        case .icloud: "icloud.fill"
        case .yahoo: "envelope.fill"
        case .fastmail: "envelope.fill"
        case .other: "envelope.fill"
        }
    }
}

// MARK: - EmailAccountRecord

/// Persistent record for a configured email account.
public struct EmailAccountRecord: Sendable, Identifiable {
    public var id: String { accountID }
    public let accountID: String
    public let displayName: String
    public let providerType: String      // "imap", "apple_mail"
    public let server: String?
    public let port: Int?
    public let username: String?
    public let authType: String          // "password", "oauth2", "app_password"
    public let keychainRef: String?
    public let syncEnabled: Bool
    public let syncIntervalSeconds: Int
    public let createdAt: String
    public let updatedAt: String

    public var provider: EmailProvider {
        EmailProvider(rawValue: providerType) ?? .other
    }

    public init(
        accountID: String,
        displayName: String,
        providerType: String,
        server: String? = nil,
        port: Int? = nil,
        username: String? = nil,
        authType: String = "password",
        keychainRef: String? = nil,
        syncEnabled: Bool = true,
        syncIntervalSeconds: Int = 300,
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.accountID = accountID
        self.displayName = displayName
        self.providerType = providerType
        self.server = server
        self.port = port
        self.username = username
        self.authType = authType
        self.keychainRef = keychainRef
        self.syncEnabled = syncEnabled
        self.syncIntervalSeconds = syncIntervalSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init?(row: [String: String]) {
        guard let accountID = row["account_id"],
              let displayName = row["display_name"],
              let providerType = row["provider_type"],
              let authType = row["auth_type"],
              let createdAt = row["created_at"],
              let updatedAt = row["updated_at"] else { return nil }
        self.accountID = accountID
        self.displayName = displayName
        self.providerType = providerType
        self.server = row["server"]
        self.port = row["port"].flatMap { Int($0) }
        self.username = row["username"]
        self.authType = authType
        self.keychainRef = row["keychain_ref"]
        self.syncEnabled = row["sync_enabled"] != "0"
        self.syncIntervalSeconds = row["sync_interval_seconds"].flatMap { Int($0) } ?? 300
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - KeychainHelper

/// Stores and retrieves email credentials in the macOS Keychain.
/// Each account gets a unique service key: "com.spatialduality.manifold.email.<accountID>"
///
/// Security model:
/// - Tries the Data Protection keychain first (silent, no prompts, requires
///   a development signing identity + keychain-access-groups entitlement).
/// - Falls back to the login keychain for ad-hoc / "Sign to Run Locally" builds.
///   The login keychain may show a one-time authorization prompt per rebuild;
///   clicking "Always Allow" persists the authorization.
/// - Credentials are never logged. Error codes are logged via os.Logger (not print).
public enum KeychainHelper: Sendable {
    private static let servicePrefix = "com.spatialduality.manifold.email"

    /// Store a credential (password or OAuth token) for an account.
    @discardableResult
    public static func store(accountID: String, credential: String) -> Bool {
        let service = "\(servicePrefix).\(accountID)"
        let cleaned = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else { return false }

        // Delete existing entry first (both keychains)
        delete(accountID: accountID)

        // Try Data Protection keychain first (silent, no prompts).
        let dpQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecValueData as String: data,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let dpStatus = SecItemAdd(dpQuery as CFDictionary, nil)
        if dpStatus == errSecSuccess { return true }

        // Fallback: login keychain (works with ad-hoc signing).
        let loginQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecAttrLabel as String: "Manifold Email (\(accountID.prefix(8)))",
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(loginQuery as CFDictionary, nil)
        if status != errSecSuccess {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown"
            keychainLogger.error("Keychain store error (\(status)): \(message)")
        }
        return status == errSecSuccess
    }

    /// Retrieve a stored credential for an account.
    public static func retrieve(accountID: String) -> String? {
        let service = "\(servicePrefix).\(accountID)"

        // Try Data Protection keychain first.
        let dpQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var result: AnyObject?
        var status = SecItemCopyMatching(dpQuery as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Fallback: login keychain.
        let loginQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        result = nil
        status = SecItemCopyMatching(loginQuery as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Delete a stored credential for an account.
    @discardableResult
    public static func delete(accountID: String) -> Bool {
        let service = "\(servicePrefix).\(accountID)"
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
        ]

        // Delete from both keychains.
        var dpQuery = baseQuery
        dpQuery[kSecUseDataProtectionKeychain as String] = true
        SecItemDelete(dpQuery as CFDictionary)

        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// The keychain reference string for a given account ID.
    public static func keychainRef(for accountID: String) -> String {
        "\(servicePrefix).\(accountID)"
    }
}
