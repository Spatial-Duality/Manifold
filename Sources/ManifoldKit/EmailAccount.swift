// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - EmailProvider

public enum EmailProvider: String, Sendable, CaseIterable, Codable {
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
public struct EmailAccountRecord: Sendable, Identifiable, Codable {
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
    public let credentialKind: String?
    public let credentialKeychainService: String?
    public let credentialKeychainAccount: String?
    public let authState: String?
    public let indexPrivacyMode: String

    public var provider: EmailProvider {
        EmailProvider(rawValue: providerType) ?? .other
    }

    public var mailCredentialReference: MailCredentialReference? {
        guard let credentialKind,
              let kind = MailCredentialKind(rawValue: credentialKind),
              let credentialKeychainService,
              let credentialKeychainAccount else {
            return nil
        }
        return MailCredentialReference(
            kind: kind,
            keychainService: credentialKeychainService,
            keychainAccount: credentialKeychainAccount,
            createdAt: ISO8601DateFormatter.shared.date(from: createdAt) ?? Date()
        )
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
        updatedAt: String = "",
        credentialKind: String? = nil,
        credentialKeychainService: String? = nil,
        credentialKeychainAccount: String? = nil,
        authState: String? = nil,
        indexPrivacyMode: String = MailIndexPrivacyMode.privateTokenIndex.rawValue
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
        self.credentialKind = credentialKind
        self.credentialKeychainService = credentialKeychainService
        self.credentialKeychainAccount = credentialKeychainAccount
        self.authState = authState
        self.indexPrivacyMode = indexPrivacyMode
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
        self.credentialKind = row["credential_kind"]
        self.credentialKeychainService = row["credential_keychain_service"]
        self.credentialKeychainAccount = row["credential_keychain_account"]
        self.authState = row["auth_state"]
        self.indexPrivacyMode = row["index_privacy_mode"] ?? MailIndexPrivacyMode.privateTokenIndex.rawValue
    }
}
