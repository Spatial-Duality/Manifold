import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "grant-types")

// MARK: - Source (persistent pointer to user-approved original folder)

public struct SourceRecord: Sendable, Hashable, Identifiable {
    public var id: String { sourceID }
    public let sourceID: String
    public let displayName: String
    public let originalRootPath: String
    public let status: String  // idle, active, paused, removed
    public let createdAt: String
    public let updatedAt: String

    public var isAccessible: Bool { status == "idle" || status == "active" }
    public var isPaused: Bool { status == "paused" }
    public var isRemoved: Bool { status == "removed" }

    init?(row: [String: String]) {
        guard let sourceID = row["source_id"],
              let displayName = row["display_name"],
              let originalRootPath = row["original_root_path"],
              let status = row["status"],
              let createdAt = row["created_at"],
              let updatedAt = row["updated_at"] else {
            logger.warning("Failed to parse SourceRecord: missing field(s) in \(row.keys.sorted())")
            return nil
        }
        self.sourceID = sourceID
        self.displayName = displayName
        self.originalRootPath = originalRootPath
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Grant (time-bounded share session for one agent target)

public enum GrantStatus: String, Sendable {
    case active
    case ended
    case timedOut = "timed_out"
}

public enum TargetApp: String, Sendable {
    case cowork
    case codex
}

public struct GrantRecord: Sendable, Identifiable {
    public var id: String { grantID }
    public let grantID: String
    public let targetApp: String
    public let profileID: String
    public let status: String  // active, ended, timed_out
    public let startedAt: String
    public let endedAt: String?
    public let materializationRoot: String
    public let inactivityDeadline: String?
    public let refreshOfGrantID: String?

    public var isActive: Bool { status == GrantStatus.active.rawValue }

    init?(row: [String: String]) {
        guard let grantID = row["grant_id"],
              let targetApp = row["target_app"],
              let profileID = row["profile_id"],
              let status = row["status"],
              let startedAt = row["started_at"],
              let materializationRoot = row["materialization_root"] else {
            logger.warning("Failed to parse GrantRecord: missing field(s) in \(row.keys.sorted())")
            return nil
        }
        self.grantID = grantID
        self.targetApp = targetApp
        self.profileID = profileID
        self.status = status
        self.startedAt = startedAt
        self.endedAt = row["ended_at"]
        self.materializationRoot = materializationRoot
        self.inactivityDeadline = row["inactivity_deadline"]
        self.refreshOfGrantID = row["refresh_of_grant_id"]
    }
}

// MARK: - Grant ↔ Source (many-to-many)

public struct GrantSourceRecord: Sendable {
    public let grantID: String
    public let sourceID: String
    public let mountName: String
    public let baselineManifestHash: String?

    init?(row: [String: String]) {
        guard let grantID = row["grant_id"],
              let sourceID = row["source_id"],
              let mountName = row["mount_name"] else {
            logger.warning("Failed to parse GrantSourceRecord: missing field(s) in \(row.keys.sorted())")
            return nil
        }
        self.grantID = grantID
        self.sourceID = sourceID
        self.mountName = mountName
        self.baselineManifestHash = row["baseline_manifest_hash"]
    }
}

public struct GrantMount: Sendable, Hashable {
    public let sourceID: String
    public let mountName: String
    public let mountPath: String

    public init(sourceID: String, mountName: String, mountPath: String) {
        self.sourceID = sourceID
        self.mountName = mountName
        self.mountPath = mountPath
    }
}

// MARK: - Email (normalized, first-class content)

public struct EmailMessageRecord: Sendable, Identifiable {
    public var id: String { emailID }
    public let emailID: String
    public let account: String
    public let mailbox: String
    public let sender: String
    public let recipients: String
    public let subject: String
    public let receivedAt: String
    public let contentHash: String?
    public let preview: String?
    public let classificationStatus: String  // pending, shared, auto_hidden, user_hidden
    public let hiddenReason: String?

    public var isShared: Bool { classificationStatus == "shared" }

    init?(row: [String: String]) {
        guard let emailID = row["email_id"],
              let account = row["account"],
              let mailbox = row["mailbox"],
              let sender = row["sender"],
              let subject = row["subject"],
              let receivedAt = row["received_at"],
              let classificationStatus = row["classification_status"] else {
            logger.warning("Failed to parse EmailMessageRecord: missing field(s) in \(row.keys.sorted())")
            return nil
        }
        self.emailID = emailID
        self.account = account
        self.mailbox = mailbox
        self.sender = sender
        self.recipients = row["recipients"] ?? ""
        self.subject = subject
        self.receivedAt = receivedAt
        self.contentHash = row["content_hash"]
        self.preview = row["preview"]
        self.classificationStatus = classificationStatus
        self.hiddenReason = row["hidden_reason"]
    }
}

// MARK: - Grant ↔ Email (emails selected for a grant)

public struct GrantEmailRecord: Sendable {
    public let grantID: String
    public let emailID: String
    public let materializedPath: String

    init?(row: [String: String]) {
        guard let grantID = row["grant_id"],
              let emailID = row["email_id"],
              let materializedPath = row["materialized_path"] else {
            logger.warning("Failed to parse GrantEmailRecord: missing field(s) in \(row.keys.sorted())")
            return nil
        }
        self.grantID = grantID
        self.emailID = emailID
        self.materializedPath = materializedPath
    }
}

public struct GrantEmailMessageRecord: Sendable, Identifiable {
    public var id: String { emailID }
    public let grantID: String
    public let emailID: String
    public let materializedPath: String
    public let account: String
    public let mailbox: String
    public let sender: String
    public let recipients: String
    public let subject: String
    public let receivedAt: String
    public let contentHash: String?
    public let preview: String?
    public let classificationStatus: String
    public let hiddenReason: String?

    init?(row: [String: String]) {
        guard let grantID = row["grant_id"],
              let emailID = row["email_id"],
              let materializedPath = row["materialized_path"],
              let account = row["account"],
              let mailbox = row["mailbox"],
              let sender = row["sender"],
              let subject = row["subject"],
              let receivedAt = row["received_at"],
              let classificationStatus = row["classification_status"] else {
            logger.warning("Failed to parse GrantEmailMessageRecord: missing field(s) in \(row.keys.sorted())")
            return nil
        }
        self.grantID = grantID
        self.emailID = emailID
        self.materializedPath = materializedPath
        self.account = account
        self.mailbox = mailbox
        self.sender = sender
        self.recipients = row["recipients"] ?? ""
        self.subject = subject
        self.receivedAt = receivedAt
        self.contentHash = row["content_hash"]
        self.preview = row["preview"]
        self.classificationStatus = classificationStatus
        self.hiddenReason = row["hidden_reason"]
    }
}

// MARK: - Promotion (result of writing grant changes back to originals)

public enum PromotionResult: String, Sendable {
    case applied
    case conflict
    case skipped
    case newFile = "new_file"
}

public struct PromotionRecord: Sendable, Identifiable {
    public var id: String { promotionID }
    public let promotionID: String
    public let grantID: String
    public let sourceID: String
    public let relativePath: String
    public let result: String  // applied, conflict, skipped
    public let originalBeforeHash: String?
    public let promotedHash: String?
    public let conflictReason: String?
    public let createdAt: String

    public var isConflict: Bool { result == PromotionResult.conflict.rawValue }

    init?(row: [String: String]) {
        guard let promotionID = row["promotion_id"],
              let grantID = row["grant_id"],
              let sourceID = row["source_id"],
              let relativePath = row["relative_path"],
              let result = row["result"],
              let createdAt = row["created_at"] else {
            logger.warning("Failed to parse PromotionRecord: missing field(s) in \(row.keys.sorted())")
            return nil
        }
        self.promotionID = promotionID
        self.grantID = grantID
        self.sourceID = sourceID
        self.relativePath = relativePath
        self.result = result
        self.originalBeforeHash = row["original_before_hash"]
        self.promotedHash = row["promoted_hash"]
        self.conflictReason = row["conflict_reason"]
        self.createdAt = createdAt
    }
}

// MARK: - Session Summary (structured history for future agents)

public struct SessionSummaryRecord: Sendable, Identifiable {
    public var id: String { summaryID }
    public let summaryID: String
    public let grantID: String
    public let targetApp: String
    public let startedAt: String
    public let endedAt: String
    public let summaryMarkdown: String
    public let summaryJSONHash: String?

    init?(row: [String: String]) {
        guard let summaryID = row["summary_id"],
              let grantID = row["grant_id"],
              let targetApp = row["target_app"],
              let startedAt = row["started_at"],
              let endedAt = row["ended_at"],
              let summaryMarkdown = row["summary_markdown"] else {
            logger.warning("Failed to parse SessionSummaryRecord: missing field(s) in \(row.keys.sorted())")
            return nil
        }
        self.summaryID = summaryID
        self.grantID = grantID
        self.targetApp = targetApp
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.summaryMarkdown = summaryMarkdown
        self.summaryJSONHash = row["summary_json_hash"]
    }
}
