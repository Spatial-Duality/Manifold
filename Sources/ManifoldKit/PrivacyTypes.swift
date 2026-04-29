// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum PrivacyRuntimeDefaults {
    public static let mlxRuntimeID = "openai-privacy-filter-mlx-mxfp8"
}

public enum PrivacyBackendKind: String, Sendable, Codable, CaseIterable {
    case rulesOnly = "rules_only"
    case mlx

    public var displayName: String {
        switch self {
        case .rulesOnly: return "Rules only"
        case .mlx: return "Fast Local Scanner"
        }
    }

    public static func fromStoredRawValue(_ rawValue: String) -> PrivacyBackendKind? {
        switch rawValue {
        case Self.rulesOnly.rawValue:
            return .rulesOnly
        case Self.mlx.rawValue, "core_ml", "official_cli":
            return .mlx
        default:
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let value = Self.fromStoredRawValue(rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid privacy backend kind: \(rawValue)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum PrivacyInstallState: String, Sendable, Codable, CaseIterable {
    case notInstalled = "not_installed"
    case installed
    case downloadRequired = "download_required"
    case downloading
    case verifying
    case unavailable

    public var displayName: String {
        switch self {
        case .notInstalled: return "Not installed"
        case .installed: return "Installed"
        case .downloadRequired: return "Download required"
        case .downloading: return "Downloading"
        case .verifying: return "Verifying"
        case .unavailable: return "Unavailable"
        }
    }
}

public enum PrivacyRuntimeVerificationState: String, Sendable, Codable, CaseIterable {
    case notInstalled = "not_installed"
    case unverified
    case checksumVerified = "checksum_verified"
    case signatureVerified = "signature_verified"
    case failed

    public var displayName: String {
        switch self {
        case .notInstalled: return "Not installed"
        case .unverified: return "Unverified"
        case .checksumVerified: return "Checksum verified"
        case .signatureVerified: return "Signature verified"
        case .failed: return "Verification failed"
        }
    }
}

public struct PrivacyRuntimeDescriptor: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public var displayName: String
    public var publisher: String
    public var installedVersion: String?
    public var availableVersion: String?
    public var sizeBytes: Int64?
    public var installState: PrivacyInstallState
    public var verificationState: PrivacyRuntimeVerificationState
    public var downloadedBytes: Int64?
    public var totalBytes: Int64?
    public var downloadProgress: Double?
    public var sourceRepository: String?
    public var note: String?

    public init(
        id: String,
        displayName: String,
        publisher: String,
        installedVersion: String? = nil,
        availableVersion: String? = nil,
        sizeBytes: Int64? = nil,
        installState: PrivacyInstallState = .notInstalled,
        verificationState: PrivacyRuntimeVerificationState = .notInstalled,
        downloadedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        downloadProgress: Double? = nil,
        sourceRepository: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.publisher = publisher
        self.installedVersion = installedVersion
        self.availableVersion = availableVersion
        self.sizeBytes = sizeBytes
        self.installState = installState
        self.verificationState = verificationState
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.downloadProgress = downloadProgress
        self.sourceRepository = sourceRepository
        self.note = note
    }
}

public enum PrivacyHandlingMode: String, Sendable, Codable, CaseIterable {
    case off
    case warn
    case redact
    case ask

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .warn: return "Warn"
        case .redact: return "Redact"
        case .ask: return "Ask"
        }
    }
}

public enum PrivacySecretHandling: String, Sendable, Codable, CaseIterable {
    case warn
    case ask
    case block

    public var displayName: String {
        switch self {
        case .warn: return "Warn"
        case .ask: return "Ask"
        case .block: return "Block"
        }
    }
}

public enum PrivacyContentKind: String, Sendable, Codable, CaseIterable {
    case sourceCode = "source_code"
    case diff
    case email
    case document
    case log
    case snippet
    case archiveEntry = "archive_entry"
    case structuredResult = "structured_result"
    case unknown

    public var displayName: String {
        switch self {
        case .sourceCode: return "Source code"
        case .diff: return "Diff"
        case .email: return "Email"
        case .document: return "Document"
        case .log: return "Log"
        case .snippet: return "Snippet"
        case .archiveEntry: return "Archive entry"
        case .structuredResult: return "Structured result"
        case .unknown: return "Unknown"
        }
    }

    public var isCodeLike: Bool {
        switch self {
        case .sourceCode, .diff:
            return true
        default:
            return false
        }
    }
}

public enum PrivacyCategory: String, Sendable, Codable, CaseIterable, Hashable {
    case privatePerson = "private_person"
    case email
    case phone
    case address
    case url
    case date
    case accountNumber = "account_number"
    case secret

    public var displayName: String {
        switch self {
        case .privatePerson: return "Private people"
        case .email: return "Emails"
        case .phone: return "Phone numbers"
        case .address: return "Addresses"
        case .url: return "URLs"
        case .date: return "Dates"
        case .accountNumber: return "Account numbers"
        case .secret: return "Secrets"
        }
    }

    public var replacementToken: String {
        switch self {
        case .privatePerson: return "[PERSON REDACTED]"
        case .email: return "[EMAIL REDACTED]"
        case .phone: return "[PHONE REDACTED]"
        case .address: return "[ADDRESS REDACTED]"
        case .url: return "[URL REDACTED]"
        case .date: return "[DATE REDACTED]"
        case .accountNumber: return "[ACCOUNT REDACTED]"
        case .secret: return "[SECRET REDACTED]"
        }
    }
}

public enum PrivacyOutcome: String, Sendable, Codable, CaseIterable {
    case clean
    case warning
    case filtered
    case blocked
    case approvalRequired = "approval_required"

    public var displayName: String {
        switch self {
        case .clean: return "Clean"
        case .warning: return "Needs review"
        case .filtered: return "Filtered"
        case .blocked: return "Secret blocked"
        case .approvalRequired: return "Needs review"
        }
    }
}

public enum PrivacyApprovalDecision: String, Sendable, Codable, CaseIterable {
    case shareRedacted = "share_redacted"
    case shareOriginalOnce = "share_original_once"

    public var displayName: String {
        switch self {
        case .shareRedacted: return "Share redacted"
        case .shareOriginalOnce: return "Share original once"
        }
    }
}

public enum PrivacyIndexedContentKind: String, Sendable, Codable, CaseIterable {
    case sourceFile = "source_file"
    case emailBody = "email_body"
    case emailAttachment = "email_attachment"

    public var displayName: String {
        switch self {
        case .sourceFile: return "Source file"
        case .emailBody: return "Email body"
        case .emailAttachment: return "Email attachment"
        }
    }
}

public enum PrivacyExtractStatus: String, Sendable, Codable, CaseIterable {
    case pending
    case ready
    case partial
    case unsupported
    case failed
}

public enum PrivacyIndexStatus: String, Sendable, Codable, CaseIterable {
    case queued
    case running
    case scanned
    case failed
    case stale
}

public enum PrivacySeverity: String, Sendable, Codable, CaseIterable, Comparable {
    case none
    case low
    case medium
    case high
    case critical

    private var rank: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .critical: return 4
        }
    }

    public static func < (lhs: PrivacySeverity, rhs: PrivacySeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

public enum PrivacyIdentityKind: String, Sendable, Codable, CaseIterable {
    case personName = "person_name"
    case email
    case phone
    case address
    case accountNumber = "account_number"
    case url
    case secret
}

public enum PrivacyMatchMode: String, Sendable, Codable, CaseIterable {
    case exact
    case contains
    case domainSuffix = "domain_suffix"
}

public enum PrivacySuggestionSourceKind: String, Sendable, Codable, CaseIterable {
    case emailAccount = "email_account"
    case emailHeader = "email_header"
    case emailSignature = "email_signature"
    case sourceRoot = "source_root"
    case manual
}

public enum PrivacySuggestionStatus: String, Sendable, Codable, CaseIterable {
    case pending
    case accepted
    case rejected
}

public enum PrivacyOrgAllowKind: String, Sendable, Codable, CaseIterable {
    case senderDomain = "sender_domain"
    case organizationName = "organization_name"
    case emailAddress = "email_address"
    case url
}

public enum PrivacySpanSource: String, Sendable, Codable, CaseIterable {
    case model
    case identity
    case allowlist
}

public enum PrivacyIndexJobStatus: String, Sendable, Codable, CaseIterable {
    case queued
    case running
    case completed
    case failed
}

public struct PrivacyIdentityRecord: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let kind: PrivacyIdentityKind
    public var displayName: String
    public var value: String
    public var normalizedHash: String?
    public var matchingMode: PrivacyMatchMode
    public var isEnabled: Bool
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String = "privacy-identity-\(UUID().uuidString.prefix(8).lowercased())",
        kind: PrivacyIdentityKind,
        displayName: String,
        value: String,
        normalizedHash: String? = nil,
        matchingMode: PrivacyMatchMode = .exact,
        isEnabled: Bool = true,
        createdAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        updatedAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.value = value
        self.normalizedHash = normalizedHash
        self.matchingMode = matchingMode
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PrivacyIdentitySuggestion: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let kind: PrivacyIdentityKind
    public var displayName: String
    public var value: String
    public var normalizedHash: String?
    public var sourceKind: PrivacySuggestionSourceKind
    public var sourceRef: String?
    public var confidence: Double
    public var status: PrivacySuggestionStatus
    public var createdAt: String
    public var reviewedAt: String?

    public init(
        id: String = "privacy-suggestion-\(UUID().uuidString.prefix(8).lowercased())",
        kind: PrivacyIdentityKind,
        displayName: String,
        value: String,
        normalizedHash: String? = nil,
        sourceKind: PrivacySuggestionSourceKind,
        sourceRef: String? = nil,
        confidence: Double,
        status: PrivacySuggestionStatus = .pending,
        createdAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        reviewedAt: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.value = value
        self.normalizedHash = normalizedHash
        self.sourceKind = sourceKind
        self.sourceRef = sourceRef
        self.confidence = confidence
        self.status = status
        self.createdAt = createdAt
        self.reviewedAt = reviewedAt
    }
}

public struct PrivacyOrgAllowEntry: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let kind: PrivacyOrgAllowKind
    public var pattern: String
    public var matchMode: PrivacyMatchMode
    public var source: String
    public var isEnabled: Bool
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String = "privacy-allow-\(UUID().uuidString.prefix(8).lowercased())",
        kind: PrivacyOrgAllowKind,
        pattern: String,
        matchMode: PrivacyMatchMode = .exact,
        source: String = "user",
        isEnabled: Bool = true,
        createdAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        updatedAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.id = id
        self.kind = kind
        self.pattern = pattern
        self.matchMode = matchMode
        self.source = source
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PrivacyIndexRecord: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let subjectKind: PrivacyIndexedContentKind
    public var sourceID: String?
    public var relativePath: String?
    public var emailID: String?
    public var attachmentID: String?
    public var parentContentID: String?
    public var displayName: String
    public var mimeType: String?
    public var extractor: String?
    public var extractStatus: PrivacyExtractStatus
    public var scanStatus: PrivacyIndexStatus
    public var contentHash: String?
    public var backend: PrivacyBackendKind?
    public var modelVersion: String?
    public var containsSensitive: Bool
    public var containsMyInfo: Bool
    public var containsThirdPartyPrivate: Bool
    public var containsSecret: Bool
    public var containsOrgOnly: Bool
    public var severity: PrivacySeverity
    public var matchedCategories: [PrivacyCategory]
    public var matchedIdentityIDs: [String]
    public var matchedAllowIDs: [String]
    public var redactedPreview: String?
    public var findingsSummary: String
    public var spanCount: Int
    public var lastScannedAt: String?
    public var updatedAt: String
    public var lastError: String?

    public init(
        id: String,
        subjectKind: PrivacyIndexedContentKind,
        sourceID: String? = nil,
        relativePath: String? = nil,
        emailID: String? = nil,
        attachmentID: String? = nil,
        parentContentID: String? = nil,
        displayName: String,
        mimeType: String? = nil,
        extractor: String? = nil,
        extractStatus: PrivacyExtractStatus = .pending,
        scanStatus: PrivacyIndexStatus = .queued,
        contentHash: String? = nil,
        backend: PrivacyBackendKind? = nil,
        modelVersion: String? = nil,
        containsSensitive: Bool = false,
        containsMyInfo: Bool = false,
        containsThirdPartyPrivate: Bool = false,
        containsSecret: Bool = false,
        containsOrgOnly: Bool = false,
        severity: PrivacySeverity = .none,
        matchedCategories: [PrivacyCategory] = [],
        matchedIdentityIDs: [String] = [],
        matchedAllowIDs: [String] = [],
        redactedPreview: String? = nil,
        findingsSummary: String = "",
        spanCount: Int = 0,
        lastScannedAt: String? = nil,
        updatedAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        lastError: String? = nil
    ) {
        self.id = id
        self.subjectKind = subjectKind
        self.sourceID = sourceID
        self.relativePath = relativePath
        self.emailID = emailID
        self.attachmentID = attachmentID
        self.parentContentID = parentContentID
        self.displayName = displayName
        self.mimeType = mimeType
        self.extractor = extractor
        self.extractStatus = extractStatus
        self.scanStatus = scanStatus
        self.contentHash = contentHash
        self.backend = backend
        self.modelVersion = modelVersion
        self.containsSensitive = containsSensitive
        self.containsMyInfo = containsMyInfo
        self.containsThirdPartyPrivate = containsThirdPartyPrivate
        self.containsSecret = containsSecret
        self.containsOrgOnly = containsOrgOnly
        self.severity = severity
        self.matchedCategories = matchedCategories
        self.matchedIdentityIDs = matchedIdentityIDs
        self.matchedAllowIDs = matchedAllowIDs
        self.redactedPreview = redactedPreview
        self.findingsSummary = findingsSummary
        self.spanCount = spanCount
        self.lastScannedAt = lastScannedAt
        self.updatedAt = updatedAt
        self.lastError = lastError
    }
}

public struct PrivacySpanRecord: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let contentID: String
    public let category: PrivacyCategory
    public let startUTF16: Int
    public let endUTF16: Int
    public let confidence: Double?
    public let source: PrivacySpanSource
    public let placeholder: String?
    public let textHash: String?
    public let createdAt: String

    public init(
        id: String = "privacy-span-\(UUID().uuidString.prefix(8).lowercased())",
        contentID: String,
        category: PrivacyCategory,
        startUTF16: Int,
        endUTF16: Int,
        confidence: Double? = nil,
        source: PrivacySpanSource,
        placeholder: String? = nil,
        textHash: String? = nil,
        createdAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.id = id
        self.contentID = contentID
        self.category = category
        self.startUTF16 = startUTF16
        self.endUTF16 = endUTF16
        self.confidence = confidence
        self.source = source
        self.placeholder = placeholder
        self.textHash = textHash
        self.createdAt = createdAt
    }
}

public struct PrivacyIndexJobRecord: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let contentID: String
    public var reason: String
    public var priority: Int
    public var status: PrivacyIndexJobStatus
    public var attemptCount: Int
    public var scheduledAt: String
    public var startedAt: String?
    public var finishedAt: String?
    public var lastError: String?

    public init(
        id: String = "privacy-job-\(UUID().uuidString.prefix(8).lowercased())",
        contentID: String,
        reason: String,
        priority: Int,
        status: PrivacyIndexJobStatus = .queued,
        attemptCount: Int = 0,
        scheduledAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        startedAt: String? = nil,
        finishedAt: String? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.contentID = contentID
        self.reason = reason
        self.priority = priority
        self.status = status
        self.attemptCount = attemptCount
        self.scheduledAt = scheduledAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.lastError = lastError
    }
}

public struct PrivacyIndexScope: Sendable, Codable, Hashable {
    public var subjectKinds: [PrivacyIndexedContentKind]?
    public var sourceID: String?
    public var emailID: String?
    public var attachmentID: String?

    public init(
        subjectKinds: [PrivacyIndexedContentKind]? = nil,
        sourceID: String? = nil,
        emailID: String? = nil,
        attachmentID: String? = nil
    ) {
        self.subjectKinds = subjectKinds
        self.sourceID = sourceID
        self.emailID = emailID
        self.attachmentID = attachmentID
    }
}

public struct PrivacyIndexFilter: Sendable, Codable, Hashable {
    public var containsSensitive: Bool?
    public var containsMyInfo: Bool?
    public var containsSecret: Bool?
    public var containsThirdPartyPrivate: Bool?
    public var containsOrgOnly: Bool?
    public var severity: PrivacySeverity?
    public var categories: [PrivacyCategory]?

    public init(
        containsSensitive: Bool? = nil,
        containsMyInfo: Bool? = nil,
        containsSecret: Bool? = nil,
        containsThirdPartyPrivate: Bool? = nil,
        containsOrgOnly: Bool? = nil,
        severity: PrivacySeverity? = nil,
        categories: [PrivacyCategory]? = nil
    ) {
        self.containsSensitive = containsSensitive
        self.containsMyInfo = containsMyInfo
        self.containsSecret = containsSecret
        self.containsThirdPartyPrivate = containsThirdPartyPrivate
        self.containsOrgOnly = containsOrgOnly
        self.severity = severity
        self.categories = categories
    }
}

public struct PrivacyIndexRuntimeStatus: Sendable, Codable, Hashable {
    public let enabled: Bool
    public let queuedJobs: Int
    public let runningJobs: Int
    public let failedJobs: Int
    public let indexedItems: Int
    public let staleItems: Int
    public let watchedSources: [String]
    public let lastError: String?

    public init(
        enabled: Bool,
        queuedJobs: Int,
        runningJobs: Int,
        failedJobs: Int,
        indexedItems: Int,
        staleItems: Int,
        watchedSources: [String],
        lastError: String?
    ) {
        self.enabled = enabled
        self.queuedJobs = queuedJobs
        self.runningJobs = runningJobs
        self.failedJobs = failedJobs
        self.indexedItems = indexedItems
        self.staleItems = staleItems
        self.watchedSources = watchedSources
        self.lastError = lastError
    }
}

public struct PrivacyPreflightSettings: Sendable, Codable {
    public let id: String
    public var isEnabled: Bool
    public var selectedBackend: PrivacyBackendKind
    public var installState: PrivacyInstallState
    public var modelVersion: String?
    public var storagePath: String?
    public var installedAt: String?
    public var cacheEnabled: Bool
    public var unloadOnMemoryPressure: Bool
    public var updatedAt: String

    public init(
        id: String = "privacy-preflight",
        isEnabled: Bool = false,
        selectedBackend: PrivacyBackendKind = .rulesOnly,
        installState: PrivacyInstallState = .notInstalled,
        modelVersion: String? = nil,
        storagePath: String? = nil,
        installedAt: String? = nil,
        cacheEnabled: Bool = true,
        unloadOnMemoryPressure: Bool = true,
        updatedAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.selectedBackend = selectedBackend
        self.installState = installState
        self.modelVersion = modelVersion
        self.storagePath = storagePath
        self.installedAt = installedAt
        self.cacheEnabled = cacheEnabled
        self.unloadOnMemoryPressure = unloadOnMemoryPressure
        self.updatedAt = updatedAt
    }
}

public struct AgentPrivacyPolicy: Sendable, Codable, Identifiable {
    public let id: String
    public let agent: TargetApp
    public var textHandling: PrivacyHandlingMode
    public var codeHandling: PrivacyHandlingMode
    public var secretHandling: PrivacySecretHandling
    public var enabledCategories: Set<PrivacyCategory>
    public var updatedAt: String

    public init(
        id: String = "privacy-policy-\(UUID().uuidString.prefix(8).lowercased())",
        agent: TargetApp,
        textHandling: PrivacyHandlingMode = .redact,
        codeHandling: PrivacyHandlingMode = .ask,
        secretHandling: PrivacySecretHandling = .block,
        enabledCategories: Set<PrivacyCategory> = Set(PrivacyCategory.allCases),
        updatedAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.id = id
        self.agent = agent
        self.textHandling = textHandling
        self.codeHandling = codeHandling
        self.secretHandling = secretHandling
        self.enabledCategories = enabledCategories
        self.updatedAt = updatedAt
    }
}

public struct DetectedSpan: Sendable, Codable, Hashable {
    public let startUTF16: Int
    public let endUTF16: Int
    public let category: PrivacyCategory
    public let confidence: Double
    public let textPreview: String
    public let replacement: String

    public init(
        startUTF16: Int,
        endUTF16: Int,
        category: PrivacyCategory,
        confidence: Double,
        textPreview: String,
        replacement: String
    ) {
        self.startUTF16 = startUTF16
        self.endUTF16 = endUTF16
        self.category = category
        self.confidence = confidence
        self.textPreview = textPreview
        self.replacement = replacement
    }
}

public struct PrivacyScanRequest: Sendable, Codable {
    public let inputHash: String
    public let text: String
    public let categories: [PrivacyCategory]
    public let operatingPoint: String
    public let contentKind: PrivacyContentKind
    public let backend: PrivacyBackendKind
    public let agent: TargetApp
    public let resourcePath: String?
    public let toolName: String

    public init(
        inputHash: String,
        text: String,
        categories: [PrivacyCategory],
        operatingPoint: String,
        contentKind: PrivacyContentKind,
        backend: PrivacyBackendKind,
        agent: TargetApp,
        resourcePath: String?,
        toolName: String
    ) {
        self.inputHash = inputHash
        self.text = text
        self.categories = categories
        self.operatingPoint = operatingPoint
        self.contentKind = contentKind
        self.backend = backend
        self.agent = agent
        self.resourcePath = resourcePath
        self.toolName = toolName
    }
}

public struct PrivacyScanResult: Sendable, Codable {
    public let spans: [DetectedSpan]
    public let redactedText: String
    public let findingsSummary: String
    public let backend: PrivacyBackendKind
    public let modelVersion: String
    public let elapsedMs: Int
    public let cacheHit: Bool

    public init(
        spans: [DetectedSpan],
        redactedText: String,
        findingsSummary: String,
        backend: PrivacyBackendKind,
        modelVersion: String,
        elapsedMs: Int,
        cacheHit: Bool
    ) {
        self.spans = spans
        self.redactedText = redactedText
        self.findingsSummary = findingsSummary
        self.backend = backend
        self.modelVersion = modelVersion
        self.elapsedMs = elapsedMs
        self.cacheHit = cacheHit
    }
}

public struct PrivacyScanEventRecord: Sendable, Codable, Identifiable {
    public let id: String
    public let accessDecisionID: String
    public let agent: TargetApp
    public let toolName: String
    public let resourcePath: String?
    public let backend: PrivacyBackendKind
    public let modelVersion: String
    public let contentKind: PrivacyContentKind
    public let inputHash: String
    public let deliveredHash: String?
    public let outcome: PrivacyOutcome
    public let findingsSummary: String
    public let findingsCount: Int
    public let matchedCategories: [PrivacyCategory]
    public let createdAt: String

    public init(
        id: String = UUID().uuidString,
        accessDecisionID: String,
        agent: TargetApp,
        toolName: String,
        resourcePath: String?,
        backend: PrivacyBackendKind,
        modelVersion: String,
        contentKind: PrivacyContentKind,
        inputHash: String,
        deliveredHash: String?,
        outcome: PrivacyOutcome,
        findingsSummary: String,
        findingsCount: Int,
        matchedCategories: [PrivacyCategory],
        createdAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.id = id
        self.accessDecisionID = accessDecisionID
        self.agent = agent
        self.toolName = toolName
        self.resourcePath = resourcePath
        self.backend = backend
        self.modelVersion = modelVersion
        self.contentKind = contentKind
        self.inputHash = inputHash
        self.deliveredHash = deliveredHash
        self.outcome = outcome
        self.findingsSummary = findingsSummary
        self.findingsCount = findingsCount
        self.matchedCategories = matchedCategories
        self.createdAt = createdAt
    }
}

public struct PrivacyApprovalContext: Sendable, Codable {
    public let toolName: String
    public let contentKind: PrivacyContentKind
    public let inputHash: String
    public let findingsSummary: String
    public let matchedCategories: [PrivacyCategory]
    public let redactedPreview: String?
    public let recommendation: String

    public init(
        toolName: String,
        contentKind: PrivacyContentKind,
        inputHash: String,
        findingsSummary: String,
        matchedCategories: [PrivacyCategory],
        redactedPreview: String?,
        recommendation: String
    ) {
        self.toolName = toolName
        self.contentKind = contentKind
        self.inputHash = inputHash
        self.findingsSummary = findingsSummary
        self.matchedCategories = matchedCategories
        self.redactedPreview = redactedPreview
        self.recommendation = recommendation
    }
}

public struct PrivacyBackendStatus: Sendable, Codable {
    public let kind: PrivacyBackendKind
    public let available: Bool
    public let installed: Bool
    public let note: String?

    public init(kind: PrivacyBackendKind, available: Bool, installed: Bool, note: String?) {
        self.kind = kind
        self.available = available
        self.installed = installed
        self.note = note
    }
}

public struct PrivacyRuntimeStatus: Sendable, Codable {
    public let featureEnabled: Bool
    public let selectedBackend: PrivacyBackendKind
    public let effectiveBackend: PrivacyBackendKind
    public let installState: PrivacyInstallState
    public let modelLoaded: Bool
    public let cacheEntryCount: Int
    public let lastError: String?
    public let storagePath: String?
    public let backends: [PrivacyBackendStatus]
    public let runtimeID: String?
    public let runtimeDisplayName: String?
    public let installedVersion: String?
    public let availableVersion: String?
    public let verificationState: PrivacyRuntimeVerificationState?
    public let downloadedBytes: Int64?
    public let totalBytes: Int64?
    public let downloadProgress: Double?

    public init(
        featureEnabled: Bool,
        selectedBackend: PrivacyBackendKind,
        effectiveBackend: PrivacyBackendKind,
        installState: PrivacyInstallState,
        modelLoaded: Bool,
        cacheEntryCount: Int,
        lastError: String?,
        storagePath: String?,
        backends: [PrivacyBackendStatus],
        runtimeID: String? = nil,
        runtimeDisplayName: String? = nil,
        installedVersion: String? = nil,
        availableVersion: String? = nil,
        verificationState: PrivacyRuntimeVerificationState? = nil,
        downloadedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        downloadProgress: Double? = nil
    ) {
        self.featureEnabled = featureEnabled
        self.selectedBackend = selectedBackend
        self.effectiveBackend = effectiveBackend
        self.installState = installState
        self.modelLoaded = modelLoaded
        self.cacheEntryCount = cacheEntryCount
        self.lastError = lastError
        self.storagePath = storagePath
        self.backends = backends
        self.runtimeID = runtimeID
        self.runtimeDisplayName = runtimeDisplayName
        self.installedVersion = installedVersion
        self.availableVersion = availableVersion
        self.verificationState = verificationState
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.downloadProgress = downloadProgress
    }
}

public struct PrivacySettingsBundle: Sendable, Codable {
    public let settings: PrivacyPreflightSettings
    public let claudePolicy: AgentPrivacyPolicy
    public let codexPolicy: AgentPrivacyPolicy
    public let runtimes: [PrivacyRuntimeDescriptor]

    public init(
        settings: PrivacyPreflightSettings,
        claudePolicy: AgentPrivacyPolicy,
        codexPolicy: AgentPrivacyPolicy,
        runtimes: [PrivacyRuntimeDescriptor] = []
    ) {
        self.settings = settings
        self.claudePolicy = claudePolicy
        self.codexPolicy = codexPolicy
        self.runtimes = runtimes
    }
}
