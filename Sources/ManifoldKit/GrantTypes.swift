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
    public let emailSensitivity: String  // strict, moderate, open
    public let summaryFraming: String?

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
        self.emailSensitivity = row["email_sensitivity"] ?? "moderate"
        self.summaryFraming = row["summary_framing"]
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

// MARK: - Email Message (metadata index for .eml files)

public struct EmailMessageRecord: Sendable, Identifiable, Hashable {
    public var id: String { emailID }
    public let emailID: String
    public let accountID: String
    public let mailbox: String          // primary/denormalized mailbox
    public let sender: String           // display: "John Doe <john@example.com>"
    public let senderEmail: String?     // normalized: "john@example.com"
    public let senderDomain: String?    // normalized: "example.com"
    public let recipients: String
    public let cc: String
    public let subject: String
    public let receivedAt: String
    public let emlPath: String?         // path to .eml file on disk
    public let sizeBytes: Int
    public let preview: String?
    public let contentType: String?     // "text/plain" or "text/html"
    public let isRead: Bool
    public let isFlagged: Bool
    public let flagColor: String?
    public let inReplyTo: String?
    public let referencesHeader: String?
    public let messageIDHeader: String? // RFC Message-ID header
    public let attachmentCount: Int
    public let localIsViewed: Bool       // v10: opened in Manifold (not IMAP \Seen)
    public let isJunk: Bool              // v10: in a junk/spam IMAP folder
    public let deletedOnServerAt: String? // v10: ISO8601 timestamp when server UID disappeared
    public let bodyText: String?         // v10: plaintext extracted from .eml for FTS5

    init?(row: [String: String]) {
        // account_id was added in v8; fall back to legacy "account" column
        guard let emailID = row["email_id"],
              let accountID = row["account_id"] ?? row["account"],
              let mailbox = row["mailbox"],
              let sender = row["sender"],
              let subject = row["subject"],
              let receivedAt = row["received_at"] else {
            logger.warning("Failed to parse EmailMessageRecord: missing field(s) in \(row.keys.sorted())")
            return nil
        }
        self.emailID = emailID
        self.accountID = accountID
        self.mailbox = mailbox
        self.sender = sender
        self.senderEmail = row["sender_email"]
        self.senderDomain = row["sender_domain"]
        self.recipients = row["recipients"] ?? ""
        self.cc = row["cc"] ?? ""
        self.subject = subject
        self.receivedAt = receivedAt
        self.emlPath = row["eml_path"]
        self.sizeBytes = row["size_bytes"].flatMap { Int($0) } ?? 0
        self.preview = row["preview"]
        self.contentType = row["content_type"]
        self.isRead = row["is_read"] == "1"
        self.isFlagged = row["is_flagged"] == "1"
        self.flagColor = row["flag_color"]
        self.inReplyTo = row["in_reply_to"]
        self.referencesHeader = row["references_header"]
        self.messageIDHeader = row["message_id_header"]
        self.attachmentCount = row["attachment_count"].flatMap { Int($0) } ?? 0
        self.localIsViewed = row["local_is_viewed"] == "1"
        self.isJunk = row["is_junk"] == "1"
        self.deletedOnServerAt = row["deleted_on_server_at"]
        self.bodyText = row["body_text"]
    }

    public var isDeletedOnServer: Bool { deletedOnServerAt != nil }
}

public struct EmailAttachmentRecord: Sendable, Identifiable, Hashable {
    public var id: String { attachmentID }
    public let attachmentID: String
    public let emailID: String
    public let filename: String
    public let mimeType: String
    public let sizeBytes: Int
    public let contentHash: String
    public let contentID: String?

    init?(row: [String: String]) {
        guard let attachmentID = row["attachment_id"],
              let emailID = row["email_id"],
              let filename = row["filename"],
              let mimeType = row["mime_type"],
              let contentHash = row["content_hash"] else {
            logger.warning("Failed to parse EmailAttachmentRecord: missing field(s) in \(row.keys.sorted())")
            return nil
        }
        self.attachmentID = attachmentID
        self.emailID = emailID
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = row["size_bytes"].flatMap { Int($0) } ?? 0
        self.contentHash = contentHash
        self.contentID = row["content_id"]
    }
}

// MARK: - IMAP Mailbox (persisted folder tree from IMAP LIST)

public struct IMAPMailboxRecord: Sendable, Identifiable, Hashable {
    public var id: String { "\(accountID)/\(mailboxName)" }
    public let accountID: String
    public let mailboxName: String
    public let delimiter: String?
    public let flags: [String]          // e.g. ["\\Sent", "\\Trash"]
    public let isSelectable: Bool
    public let parentPath: String?
    public let sortOrder: Int

    public init?(row: [String: String]) {
        guard let accountID = row["account_id"],
              let mailboxName = row["mailbox_name"] else { return nil }
        self.accountID = accountID
        self.mailboxName = mailboxName
        self.delimiter = row["delimiter"]
        // flags stored as JSON array string
        if let flagsJSON = row["flags"],
           let data = flagsJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String] {
            self.flags = parsed
        } else {
            self.flags = []
        }
        self.isSelectable = row["is_selectable"] != "0"
        self.parentPath = row["parent_path"]
        self.sortOrder = row["sort_order"].flatMap { Int($0) } ?? 0
    }

    /// Canonical folder type derived from IMAP flags.
    public var folderType: FolderType {
        let upper = flags.map { $0.lowercased() }
        if upper.contains("\\inbox") || mailboxName.uppercased() == "INBOX" { return .inbox }
        if upper.contains("\\sent") { return .sent }
        if upper.contains("\\drafts") { return .drafts }
        if upper.contains("\\trash") { return .trash }
        if upper.contains("\\junk") { return .junk }
        if upper.contains("\\archive") || upper.contains("\\all") { return .archive }
        if upper.contains("\\flagged") { return .flagged }
        // Heuristic fallback by name
        let name = mailboxName.uppercased()
        if name == "INBOX" { return .inbox }
        if name.contains("SENT") { return .sent }
        if name.contains("DRAFT") { return .drafts }
        if name.contains("TRASH") || name.contains("DELETED") { return .trash }
        if name.contains("JUNK") || name.contains("SPAM") { return .junk }
        if name.contains("ARCHIVE") || name.contains("ALL MAIL") { return .archive }
        return .other
    }

    public enum FolderType: String, Sendable {
        case inbox, sent, drafts, trash, junk, archive, flagged, other

        public var systemImage: String {
            switch self {
            case .inbox: "tray.fill"
            case .sent: "paperplane.fill"
            case .drafts: "pencil.line"
            case .trash: "trash.fill"
            case .junk: "xmark.bin.fill"
            case .archive: "archivebox.fill"
            case .flagged: "flag.fill"
            case .other: "folder.fill"
            }
        }

        /// Sort priority (lower = higher in sidebar).
        public var sortPriority: Int {
            switch self {
            case .inbox: 0
            case .sent: 1
            case .drafts: 2
            case .flagged: 3
            case .archive: 4
            case .junk: 5
            case .trash: 6
            case .other: 10
            }
        }
    }
}

// MARK: - Shared Email (persistent sharing, independent of grants)

public struct SharedEmailRecord: Sendable, Identifiable {
    public var id: String { shareID }
    public let shareID: String
    public let emailID: String
    public let sharedAt: String
    public let label: String?

    public init?(row: [String: String]) {
        guard let shareID = row["share_id"],
              let emailID = row["email_id"],
              let sharedAt = row["shared_at"] else { return nil }
        self.shareID = shareID
        self.emailID = emailID
        self.sharedAt = sharedAt
        self.label = row["label"]
    }
}

// MARK: - Smart Mailbox (virtual folder with rule-based filtering)

public struct SmartMailboxRecord: Sendable, Identifiable {
    public var id: String { mailboxID }
    public let mailboxID: String
    public let displayName: String
    public let iconName: String
    public let rulesJSON: String
    public let sortOrder: Int

    public init?(row: [String: String]) {
        guard let mailboxID = row["mailbox_id"],
              let displayName = row["display_name"] else { return nil }
        self.mailboxID = mailboxID
        self.displayName = displayName
        self.iconName = row["icon_name"] ?? "tray"
        self.rulesJSON = row["rules_json"] ?? "[]"
        self.sortOrder = row["sort_order"].flatMap { Int($0) } ?? 0
    }

    /// Parsed rules from rulesJSON
    public var rules: SmartMailboxRules? {
        guard let data = rulesJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SmartMailboxRules.self, from: data)
    }
}

// MARK: - Rule Condition (unified condition model for search, filters, smart mailboxes)

public struct RuleCondition: Codable, Sendable, Hashable {
    public let field: String
    public let op: RuleOperator
    public let value: String

    public init(field: String, op: RuleOperator, value: String) {
        self.field = field
        self.op = op
        self.value = value
    }

    public enum RuleOperator: String, Codable, Sendable, Hashable {
        case equals
        case notEquals
        case contains
        case notContains
        case greaterThan
        case lessThan
        case after
        case before
        case between
        case isNotNull
    }

    /// Whitelist of allowed field names for SQL injection safety
    public static let allowedFields: Set<String> = [
        "sender", "sender_email", "sender_domain", "recipients", "cc",
        "subject", "body_text", "received_at", "is_read", "local_is_viewed",
        "is_flagged", "is_junk", "deleted_on_server_at", "attachment_count",
        "size_bytes", "mailbox", "shared"
    ]

    public var isValid: Bool { Self.allowedFields.contains(field) }

    /// Field type classification for UI input control selection
    public enum FieldType: Sendable {
        case string, date, boolean, numeric, enumeration
    }

    public static func fieldType(for field: String) -> FieldType {
        switch field {
        case "received_at", "deleted_on_server_at": return .date
        case "is_read", "is_flagged", "is_junk", "local_is_viewed", "shared": return .boolean
        case "attachment_count", "size_bytes": return .numeric
        case "mailbox": return .enumeration
        default: return .string
        }
    }

    /// Valid operators for a given field type
    public static func operators(for field: String) -> [RuleOperator] {
        switch fieldType(for: field) {
        case .string: return [.contains, .notContains, .equals, .notEquals]
        case .date: return [.after, .before, .between]
        case .boolean: return [.equals]
        case .numeric: return [.equals, .greaterThan, .lessThan]
        case .enumeration: return [.equals, .notEquals]
        }
    }
}

public struct SmartMailboxRules: Codable, Sendable, Hashable {
    public let match: MatchType
    public let conditions: [RuleCondition]

    public init(match: MatchType, conditions: [RuleCondition]) {
        self.match = match
        self.conditions = conditions
    }

    public enum MatchType: String, Codable, Sendable, Hashable {
        case all
        case any
    }

    public func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Search Token (for email search UI)

public enum SearchTokenType: String, Sendable, CaseIterable {
    case from           // matches sender_email LIKE
    case domain         // matches sender_domain exact or LIKE
    case subject        // matches subject LIKE
    case to             // matches recipients LIKE
    case hasAttachments // matches attachment_count > 0
    case body           // matches body_text via FTS5 MATCH
    case dateAfter      // matches received_at > value
    case dateBefore     // matches received_at < value
    case isJunk         // matches is_junk = 1
    case isDeleted      // matches deleted_on_server_at IS NOT NULL
}

public struct SearchToken: Sendable, Identifiable, Hashable {
    public var id: String { "\(type.rawValue):\(value)" }
    public let type: SearchTokenType
    public let value: String

    public init(type: SearchTokenType, value: String) {
        self.type = type
        self.value = value
    }
}

// MARK: - Quick Filter (sidebar filter presets)

public enum QuickFilter: String, Sendable, CaseIterable, Identifiable {
    case unread
    case flagged
    case attachments
    case today
    case unviewed
    case deletedOnServer
    case junk
    case thisWeek

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unread: "Unread"
        case .flagged: "Flagged"
        case .attachments: "Attachments"
        case .today: "Today"
        case .unviewed: "Unviewed"
        case .deletedOnServer: "Deleted on Server"
        case .junk: "Junk"
        case .thisWeek: "This Week"
        }
    }

    public var systemImage: String {
        switch self {
        case .unread: "envelope.badge"
        case .flagged: "flag.fill"
        case .attachments: "paperclip"
        case .today: "calendar"
        case .unviewed: "eye.slash"
        case .deletedOnServer: "cloud.slash"
        case .junk: "xmark.bin"
        case .thisWeek: "calendar.badge.clock"
        }
    }

    /// Default visible filters (configurable by user)
    public static let defaultVisible: [QuickFilter] = [.unviewed, .flagged, .attachments, .deletedOnServer]

    /// Overflow filters shown in "More Filters..." disclosure
    public static let overflow: [QuickFilter] = [.junk, .today, .thisWeek, .unread]
}

// MARK: - Sort Key (for message list ordering)

public enum EmailSortKey: String, Sendable, CaseIterable {
    case date
    case sender
    case subject
    case size
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
