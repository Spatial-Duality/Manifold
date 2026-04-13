import Foundation

// MARK: - Agent Access Policy

/// Persistent standing access policy per agent.
/// File access lives here directly. Email policy fields are compatibility storage
/// mirrored from the runtime-owned email rule set.
public struct AgentAccessPolicy: Sendable, Identifiable, Codable {
    public let id: String
    public let agent: TargetApp
    public var allowedSourceIDs: Set<String>
    public var allowedEmailDomains: Set<String>
    public var emailSensitivity: EmailSensitivityLevel
    public var defaultEmailPolicy: EmailDefaultPolicy
    public var accessRecordingLevel: AccessRecordingLevel
    public var isPaused: Bool
    public var hasCompletedFirstGrant: Bool
    public let createdAt: String
    public var updatedAt: String

    public init(
        id: String = "policy-\(UUID().uuidString.prefix(8).lowercased())",
        agent: TargetApp,
        allowedSourceIDs: Set<String> = [],
        allowedEmailDomains: Set<String> = [],
        emailSensitivity: EmailSensitivityLevel = .moderate,
        defaultEmailPolicy: EmailDefaultPolicy? = nil,
        accessRecordingLevel: AccessRecordingLevel = .lightweight,
        isPaused: Bool = false,
        hasCompletedFirstGrant: Bool = false,
        createdAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        updatedAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.id = id
        self.agent = agent
        self.allowedSourceIDs = allowedSourceIDs
        self.allowedEmailDomains = allowedEmailDomains
        self.emailSensitivity = emailSensitivity
        self.defaultEmailPolicy = defaultEmailPolicy ?? .defaultValue(for: agent)
        self.accessRecordingLevel = accessRecordingLevel
        self.isPaused = isPaused
        self.hasCompletedFirstGrant = hasCompletedFirstGrant
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init?(row: [String: String]) {
        guard let id = row["policy_id"],
              let agentRaw = row["agent"],
              let agent = TargetApp(rawValue: agentRaw),
              let createdAt = row["created_at"],
              let updatedAt = row["updated_at"] else {
            return nil
        }
        self.id = id
        self.agent = agent
        self.allowedSourceIDs = Self.decodeSet(row["allowed_source_ids"])
        self.allowedEmailDomains = Self.decodeSet(row["allowed_email_domains"])
        self.emailSensitivity = EmailSensitivityLevel(rawValue: row["email_sensitivity"] ?? "moderate") ?? .moderate
        self.defaultEmailPolicy = EmailDefaultPolicy(rawValue: row["default_email_policy"] ?? "") ?? .defaultValue(for: agent)
        self.accessRecordingLevel = AccessRecordingLevel(rawValue: row["access_recording_level"] ?? "lightweight") ?? .lightweight
        self.isPaused = row["is_paused"] == "1"
        self.hasCompletedFirstGrant = row["has_completed_first_grant"] == "1"
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private static func decodeSet(_ json: String?) -> Set<String> {
        guard let json, !json.isEmpty,
              let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(array)
    }

    func encodeSourceIDs() -> String {
        let sorted = allowedSourceIDs.sorted()
        guard let data = try? JSONEncoder().encode(sorted) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    func encodeDomains() -> String {
        let sorted = allowedEmailDomains.sorted()
        guard let data = try? JSONEncoder().encode(sorted) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

// MARK: - Email Sensitivity Level

public enum EmailSensitivityLevel: String, Sendable, CaseIterable, Codable {
    case strict
    case moderate
    case open

    /// Ordering: strict < moderate < open.
    private var rank: Int {
        switch self {
        case .strict: 0
        case .moderate: 1
        case .open: 2
        }
    }

    /// True if self allows more data visibility than `other`.
    public func isLooserThan(_ other: EmailSensitivityLevel) -> Bool {
        rank > other.rank
    }

    public var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Temporary Reveal

/// Single-email temporary visibility override.
/// Expires when the current run or work block ends.
public struct TemporaryReveal: Sendable, Identifiable, Codable {
    public let id: String
    public let agent: TargetApp
    public let emailID: String
    public let workBlockID: String?
    public let createdAt: String

    public init(
        id: String = "reveal-\(UUID().uuidString.prefix(8).lowercased())",
        agent: TargetApp,
        emailID: String,
        workBlockID: String? = nil,
        createdAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.id = id
        self.agent = agent
        self.emailID = emailID
        self.workBlockID = workBlockID
        self.createdAt = createdAt
    }

    init?(row: [String: String]) {
        guard let id = row["reveal_id"],
              let agentRaw = row["agent"],
              let agent = TargetApp(rawValue: agentRaw),
              let emailID = row["email_id"],
              let createdAt = row["created_at"] else {
            return nil
        }
        self.id = id
        self.agent = agent
        self.emailID = emailID
        self.workBlockID = row["work_block_id"]?.nilIfEmpty
        self.createdAt = createdAt
    }
}

// MARK: - Work Block Record

/// Optional tracked work block with snapshot/promote lifecycle.
/// Work blocks freeze the access scope at start and use MaterializationEngine
/// for workspace isolation.
public struct WorkBlockRecord: Sendable, Identifiable, Codable {
    public let id: String
    public let agent: TargetApp
    public let grantID: String
    public let sourceIDs: [String]
    public let startedAt: String
    public var endedAt: String?
    public var status: WorkBlockStatus
    public var modifiedFileCount: Int
    public var newFileCount: Int

    public init(
        id: String = "wb-\(UUID().uuidString.prefix(8).lowercased())",
        agent: TargetApp,
        grantID: String,
        sourceIDs: [String] = [],
        startedAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        endedAt: String? = nil,
        status: WorkBlockStatus = .active,
        modifiedFileCount: Int = 0,
        newFileCount: Int = 0
    ) {
        self.id = id
        self.agent = agent
        self.grantID = grantID
        self.sourceIDs = sourceIDs
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.modifiedFileCount = modifiedFileCount
        self.newFileCount = newFileCount
    }

    init?(row: [String: String]) {
        guard let id = row["work_block_id"],
              let agentRaw = row["agent"],
              let agent = TargetApp(rawValue: agentRaw),
              let grantID = row["grant_id"],
              let startedAt = row["started_at"],
              let statusRaw = row["status"],
              let status = WorkBlockStatus(rawValue: statusRaw) else {
            return nil
        }
        self.id = id
        self.agent = agent
        self.grantID = grantID
        self.sourceIDs = Self.decodeArray(row["source_ids"])
        self.startedAt = startedAt
        self.endedAt = row["ended_at"]?.nilIfEmpty
        self.status = status
        self.modifiedFileCount = Int(row["modified_file_count"] ?? "0") ?? 0
        self.newFileCount = Int(row["new_file_count"] ?? "0") ?? 0
    }

    private static func decodeArray(_ json: String?) -> [String] {
        guard let json, !json.isEmpty,
              let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return array
    }

    func encodeSourceIDs() -> String {
        guard let data = try? JSONEncoder().encode(sourceIDs) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    public var isActive: Bool { status == .active }
    public var isPaused: Bool { status == .paused }
}

// MARK: - Work Block Status

public enum WorkBlockStatus: String, Sendable, Codable {
    case active
    case paused
    case reviewing
    case promoted
    case discarded
}
