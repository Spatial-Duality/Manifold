// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum MailAccountSetupState: String, Codable, Sendable {
    case started
    case providerDetected
    case trustExplained
    case waitingForCredential
    case waitingForOAuth
    case validatingCredential
    case discoveringCapabilities
    case choosingMailboxes
    case creatingAccount
    case enrolledForSync
    case failed
}

public enum MailSetupFailureReason: String, Codable, Sendable {
    case invalidEmail
    case providerUnsupported
    case missingOAuthConfig
    case authenticationFailed
    case adminConsentRequired
    case imapDisabled
    case tlsFailed
    case providerThrottled
    case networkUnavailable
    case unexpectedResponse
}

public struct MailAccountSetupSession: Codable, Sendable, Identifiable {
    public let id: UUID
    public var emailAddress: String?
    public var selectedProviderID: MailProviderID?
    public var providerCandidates: [MailProviderID]
    public var state: MailAccountSetupState
    public var authMethod: MailAuthMethod?
    public var progressMessage: String?
    public var failureReason: MailSetupFailureReason?

    public init(
        id: UUID = UUID(),
        emailAddress: String? = nil,
        selectedProviderID: MailProviderID? = nil,
        providerCandidates: [MailProviderID] = [],
        state: MailAccountSetupState = .started,
        authMethod: MailAuthMethod? = nil,
        progressMessage: String? = nil,
        failureReason: MailSetupFailureReason? = nil
    ) {
        self.id = id
        self.emailAddress = emailAddress
        self.selectedProviderID = selectedProviderID
        self.providerCandidates = providerCandidates
        self.state = state
        self.authMethod = authMethod
        self.progressMessage = progressMessage
        self.failureReason = failureReason
    }
}

public enum MailCredentialKind: String, Codable, Sendable {
    case appPassword
    case oauthTokenSet
    case manualPassword
}

public enum MailAccountAuthState: String, Codable, Sendable {
    case valid
    case needsReauthentication
}

public struct MailCredentialReference: Codable, Sendable, Equatable {
    public let kind: MailCredentialKind
    public let keychainService: String
    public let keychainAccount: String
    public let createdAt: Date
    public let lastValidatedAt: Date?

    public init(
        kind: MailCredentialKind,
        keychainService: String,
        keychainAccount: String,
        createdAt: Date = Date(),
        lastValidatedAt: Date? = nil
    ) {
        self.kind = kind
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
        self.createdAt = createdAt
        self.lastValidatedAt = lastValidatedAt
    }
}

public struct MailSyncPlan: Codable, Sendable {
    public let accountID: String
    public let priorityMailboxIDs: [String]
    public let selectedMailboxIDs: [String]
    public let firstPassMessageLimitPerMailbox: Int
    public let historicalBackfillEnabled: Bool
    public let incrementalEnabled: Bool

    public init(
        accountID: String,
        priorityMailboxIDs: [String] = [],
        selectedMailboxIDs: [String] = [],
        firstPassMessageLimitPerMailbox: Int = 1_000,
        historicalBackfillEnabled: Bool = true,
        incrementalEnabled: Bool = true
    ) {
        self.accountID = accountID
        self.priorityMailboxIDs = priorityMailboxIDs
        self.selectedMailboxIDs = selectedMailboxIDs
        self.firstPassMessageLimitPerMailbox = firstPassMessageLimitPerMailbox
        self.historicalBackfillEnabled = historicalBackfillEnabled
        self.incrementalEnabled = incrementalEnabled
    }
}

public enum MailSyncProgressState: String, Codable, Sendable {
    case idle
    case connecting
    case authenticating
    case discoveringMailboxes
    case recentPass
    case historicalBackfill
    case incremental
    case idleWaiting
    case paused
    case failed
}

public struct MailSyncProgress: Codable, Sendable {
    public let accountID: String
    public let state: MailSyncProgressState
    public let mailboxNameRedacted: String?
    public let messagesFetched: Int
    public let messagesIndexed: Int
    public let bytesFetched: Int64
    public let error: String?

    public init(
        accountID: String,
        state: MailSyncProgressState,
        mailboxNameRedacted: String? = nil,
        messagesFetched: Int = 0,
        messagesIndexed: Int = 0,
        bytesFetched: Int64 = 0,
        error: String? = nil
    ) {
        self.accountID = accountID
        self.state = state
        self.mailboxNameRedacted = mailboxNameRedacted
        self.messagesFetched = messagesFetched
        self.messagesIndexed = messagesIndexed
        self.bytesFetched = bytesFetched
        self.error = error
    }
}

public enum MailIndexPrivacyMode: String, Codable, Sendable {
    case privateTokenIndex
    case plaintextFTSWithDisclosure
    case metadataOnly
}

public enum MailArchiveObjectKind: String, Codable, Sendable {
    case messageRFC822
    case attachment
    case extractedText
    case legacyEncryptedEML
}

public struct MailArchiveObject: Codable, Sendable {
    public let version: Int
    public let kind: MailArchiveObjectKind
    public let contentID: Data
    public let accountID: String
    public let byteCountPlaintext: Int64
    public let byteCountCiphertext: Int64
    public let manifestCID: Data
    public let createdAt: Date

    public init(
        version: Int,
        kind: MailArchiveObjectKind,
        contentID: Data,
        accountID: String,
        byteCountPlaintext: Int64,
        byteCountCiphertext: Int64,
        manifestCID: Data,
        createdAt: Date = Date()
    ) {
        self.version = version
        self.kind = kind
        self.contentID = contentID
        self.accountID = accountID
        self.byteCountPlaintext = byteCountPlaintext
        self.byteCountCiphertext = byteCountCiphertext
        self.manifestCID = manifestCID
        self.createdAt = createdAt
    }
}

public enum MailExportScope: Codable, Sendable, Equatable {
    case messages([String])
    case mailbox(String, dateRange: DateInterval?)
    case account(String, dateRange: DateInterval?)
}

public struct MailExportRequest: Codable, Sendable, Equatable {
    public let scope: MailExportScope
    public let destinationPath: String
    public let includeAttachments: Bool
    public let includeOriginalEML: Bool
    public let createFolderPerMessage: Bool
    public let temporary: Bool

    public init(
        scope: MailExportScope,
        destinationPath: String,
        includeAttachments: Bool = true,
        includeOriginalEML: Bool = true,
        createFolderPerMessage: Bool = false,
        temporary: Bool = false
    ) {
        self.scope = scope
        self.destinationPath = destinationPath
        self.includeAttachments = includeAttachments
        self.includeOriginalEML = includeOriginalEML
        self.createFolderPerMessage = createFolderPerMessage
        self.temporary = temporary
    }
}

public struct MailAccessGrant: Codable, Sendable, Identifiable {
    public let id: UUID
    public let agentID: String
    public let sessionID: String?
    public let accountIDs: [String]
    public let mailboxIDs: [String]
    public let messageIDs: [String]?
    public let allowSearch: Bool
    public let allowBodyRead: Bool
    public let allowAttachmentRead: Bool
    public let allowExport: Bool
    public let maxResults: Int
    public let expiresAt: Date?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        agentID: String,
        sessionID: String? = nil,
        accountIDs: [String] = [],
        mailboxIDs: [String] = [],
        messageIDs: [String]? = nil,
        allowSearch: Bool = false,
        allowBodyRead: Bool = false,
        allowAttachmentRead: Bool = false,
        allowExport: Bool = false,
        maxResults: Int = 50,
        expiresAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.agentID = agentID
        self.sessionID = sessionID
        self.accountIDs = accountIDs
        self.mailboxIDs = mailboxIDs
        self.messageIDs = messageIDs
        self.allowSearch = allowSearch
        self.allowBodyRead = allowBodyRead
        self.allowAttachmentRead = allowAttachmentRead
        self.allowExport = allowExport
        self.maxResults = maxResults
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }
}
