// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "grant-types")

// MARK: - Source (persistent pointer to user-approved original folder)

public struct SourceRecord: Sendable, Hashable, Identifiable, Codable {
    enum CodingKeys: String, CodingKey {
        case sourceID
        case displayName
        case originalRootPath
        case bookmarkDataBase64
        case resolvedRootPath
        case sourceHealth
        case sourceHealthDetail
        case rootFileIdentity
        case lastResolvedAt
        case sourceKind
        case status
        case createdAt
        case updatedAt
    }

    public var id: String { sourceID }
    public let sourceID: String
    public let displayName: String
    public let originalRootPath: String
    public let bookmarkDataBase64: String?
    public let resolvedRootPath: String?
    public let sourceHealth: SourceHealthStatus
    public let sourceHealthDetail: String?
    public let rootFileIdentity: String?
    public let lastResolvedAt: String?
    public let sourceKind: SourceKind
    public let status: String  // idle, active, paused, removed
    public let createdAt: String
    public let updatedAt: String

    public var isAccessible: Bool { status == "idle" || status == "active" }
    public var isPaused: Bool { status == "paused" }
    public var isRemoved: Bool { status == "removed" }
    public var isSourceHealthy: Bool { sourceHealth.isUsable }
    public var isResolvedForAccess: Bool { isAccessible && isSourceHealthy }
    public var effectiveRootPath: String { resolvedRootPath ?? originalRootPath }
    public var hasMoved: Bool {
        guard let resolvedRootPath else { return false }
        return resolvedRootPath != originalRootPath
    }
    public var canonicalMountName: String {
        let base = URL(fileURLWithPath: originalRootPath).lastPathComponent
        let sanitized = base
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? sourceID : sanitized
    }

    public init(
        sourceID: String,
        displayName: String,
        originalRootPath: String,
        bookmarkDataBase64: String? = nil,
        resolvedRootPath: String? = nil,
        sourceHealth: SourceHealthStatus = .unknown,
        sourceHealthDetail: String? = nil,
        rootFileIdentity: String? = nil,
        lastResolvedAt: String? = nil,
        sourceKind: SourceKind = .folder,
        status: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.sourceID = sourceID
        self.displayName = displayName
        self.originalRootPath = originalRootPath
        self.bookmarkDataBase64 = bookmarkDataBase64
        self.resolvedRootPath = resolvedRootPath
        self.sourceHealth = sourceHealth
        self.sourceHealthDetail = sourceHealthDetail
        self.rootFileIdentity = rootFileIdentity
        self.lastResolvedAt = lastResolvedAt
        self.sourceKind = sourceKind
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceID = try container.decode(String.self, forKey: .sourceID)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.originalRootPath = try container.decode(String.self, forKey: .originalRootPath)
        self.bookmarkDataBase64 = try container.decodeIfPresent(String.self, forKey: .bookmarkDataBase64)
        self.resolvedRootPath = try container.decodeIfPresent(String.self, forKey: .resolvedRootPath)
        self.sourceHealth = try container.decodeIfPresent(SourceHealthStatus.self, forKey: .sourceHealth) ?? .unknown
        self.sourceHealthDetail = try container.decodeIfPresent(String.self, forKey: .sourceHealthDetail)
        self.rootFileIdentity = try container.decodeIfPresent(String.self, forKey: .rootFileIdentity)
        self.lastResolvedAt = try container.decodeIfPresent(String.self, forKey: .lastResolvedAt)
        self.sourceKind = try container.decodeIfPresent(SourceKind.self, forKey: .sourceKind) ?? .folder
        self.status = try container.decode(String.self, forKey: .status)
        self.createdAt = try container.decode(String.self, forKey: .createdAt)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceID, forKey: .sourceID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(originalRootPath, forKey: .originalRootPath)
        try container.encodeIfPresent(bookmarkDataBase64, forKey: .bookmarkDataBase64)
        try container.encodeIfPresent(resolvedRootPath, forKey: .resolvedRootPath)
        try container.encode(sourceHealth, forKey: .sourceHealth)
        try container.encodeIfPresent(sourceHealthDetail, forKey: .sourceHealthDetail)
        try container.encodeIfPresent(rootFileIdentity, forKey: .rootFileIdentity)
        try container.encodeIfPresent(lastResolvedAt, forKey: .lastResolvedAt)
        try container.encode(sourceKind, forKey: .sourceKind)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

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
        self.bookmarkDataBase64 = row["bookmark_data_base64"]
        self.resolvedRootPath = row["resolved_root_path"]
        self.sourceHealth = SourceHealthStatus(rawValue: row["source_health"] ?? "") ?? .unknown
        self.sourceHealthDetail = row["source_health_detail"]
        self.rootFileIdentity = row["root_file_identity"]
        self.lastResolvedAt = row["last_resolved_at"]
        self.sourceKind = SourceKind(rawValue: row["source_kind"] ?? "") ?? .folder
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum SourceKind: String, Sendable, Codable, CaseIterable {
    case folder
    case file
}

public enum SourceHealthStatus: String, Sendable, Codable, CaseIterable {
    case unknown
    case available
    case moved
    case missing
    case needsPermission = "needs_permission"
    case staleBookmark = "stale_bookmark"
    case replaced
    case invalid

    public var isUsable: Bool {
        switch self {
        case .available, .moved, .staleBookmark:
            return true
        case .unknown, .missing, .needsPermission, .replaced, .invalid:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .unknown: return "Needs check"
        case .available: return "Available"
        case .moved: return "Moved"
        case .missing: return "Missing"
        case .needsPermission: return "Needs permission"
        case .staleBookmark: return "Bookmark stale"
        case .replaced: return "Replaced"
        case .invalid: return "Invalid"
        }
    }
}

// MARK: - Grant (time-bounded share session for one agent target)

public enum GrantStatus: String, Sendable, Codable {
    case active
    case ended
    case timedOut = "timed_out"
}

public enum TargetApp: String, Sendable, CaseIterable, Codable {
    case cowork
    case codex
}

public enum SessionNoteCaptureMode: String, Sendable, CaseIterable, Codable {
    case off
    case basic
    case verbose

    public var automaticNoteKinds: [SessionSummaryKind] {
        switch self {
        case .off:
            return []
        case .basic:
            return [.startNote, .endNote]
        case .verbose:
            return [.startNote, .checkpointNote, .endNote]
        }
    }

    public var statusLabel: String {
        rawValue.uppercased()
    }
}

public enum SessionSummaryKind: String, Sendable, CaseIterable, Codable {
    case summary
    case startNote = "start_note"
    case checkpointNote = "checkpoint_note"
    case endNote = "end_note"

    public var displayName: String {
        switch self {
        case .summary:
            return "Summary"
        case .startNote:
            return "Start Note"
        case .checkpointNote:
            return "Checkpoint Note"
        case .endNote:
            return "End Note"
        }
    }
}

public enum SessionSummaryOrigin: String, Sendable, CaseIterable, Codable {
    case system
    case agent
}

public struct GrantRecord: Sendable, Identifiable, Codable {
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
    public let explicitSelection: Bool
    public let noteCaptureMode: String
    public let requestDetailLevel: String?
    public let memoryAccessEnabled: Bool

    public var isActive: Bool { status == GrantStatus.active.rawValue }
    public var sessionNoteCaptureMode: SessionNoteCaptureMode {
        SessionNoteCaptureMode(rawValue: noteCaptureMode) ?? .off
    }
    public var sessionRequestDetailLevel: AccessRecordingLevel? {
        requestDetailLevel.flatMap(AccessRecordingLevel.init(rawValue:))
    }

    enum CodingKeys: String, CodingKey {
        case grantID
        case targetApp
        case profileID
        case status
        case startedAt
        case endedAt
        case materializationRoot
        case inactivityDeadline
        case refreshOfGrantID
        case emailSensitivity
        case summaryFraming
        case explicitSelection
        case noteCaptureMode
        case requestDetailLevel
        case memoryAccessEnabled
    }

    public init(
        grantID: String,
        targetApp: String,
        profileID: String,
        status: String,
        startedAt: String,
        endedAt: String? = nil,
        materializationRoot: String,
        inactivityDeadline: String? = nil,
        refreshOfGrantID: String? = nil,
        emailSensitivity: String = "moderate",
        summaryFraming: String? = nil,
        explicitSelection: Bool = false,
        noteCaptureMode: String = SessionNoteCaptureMode.off.rawValue,
        requestDetailLevel: String? = nil,
        memoryAccessEnabled: Bool = false
    ) {
        self.grantID = grantID
        self.targetApp = targetApp
        self.profileID = profileID
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.materializationRoot = materializationRoot
        self.inactivityDeadline = inactivityDeadline
        self.refreshOfGrantID = refreshOfGrantID
        self.emailSensitivity = emailSensitivity
        self.summaryFraming = summaryFraming
        self.explicitSelection = explicitSelection
        self.noteCaptureMode = noteCaptureMode
        self.requestDetailLevel = requestDetailLevel
        self.memoryAccessEnabled = memoryAccessEnabled
    }

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
        self.explicitSelection = row["explicit_selection"] == "1"
        self.noteCaptureMode = row["note_capture_mode"] ?? SessionNoteCaptureMode.off.rawValue
        self.requestDetailLevel = row["request_detail_level"]
        self.memoryAccessEnabled = row["memory_access_enabled"] == "1"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.grantID = try container.decode(String.self, forKey: .grantID)
        self.targetApp = try container.decode(String.self, forKey: .targetApp)
        self.profileID = try container.decode(String.self, forKey: .profileID)
        self.status = try container.decode(String.self, forKey: .status)
        self.startedAt = try container.decode(String.self, forKey: .startedAt)
        self.endedAt = try container.decodeIfPresent(String.self, forKey: .endedAt)
        self.materializationRoot = try container.decode(String.self, forKey: .materializationRoot)
        self.inactivityDeadline = try container.decodeIfPresent(String.self, forKey: .inactivityDeadline)
        self.refreshOfGrantID = try container.decodeIfPresent(String.self, forKey: .refreshOfGrantID)
        self.emailSensitivity = try container.decodeIfPresent(String.self, forKey: .emailSensitivity) ?? "moderate"
        self.summaryFraming = try container.decodeIfPresent(String.self, forKey: .summaryFraming)
        self.explicitSelection = try container.decodeIfPresent(Bool.self, forKey: .explicitSelection) ?? false
        self.noteCaptureMode = try container.decodeIfPresent(String.self, forKey: .noteCaptureMode) ?? SessionNoteCaptureMode.off.rawValue
        self.requestDetailLevel = try container.decodeIfPresent(String.self, forKey: .requestDetailLevel)
        self.memoryAccessEnabled = try container.decodeIfPresent(Bool.self, forKey: .memoryAccessEnabled) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(grantID, forKey: .grantID)
        try container.encode(targetApp, forKey: .targetApp)
        try container.encode(profileID, forKey: .profileID)
        try container.encode(status, forKey: .status)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encode(materializationRoot, forKey: .materializationRoot)
        try container.encodeIfPresent(inactivityDeadline, forKey: .inactivityDeadline)
        try container.encodeIfPresent(refreshOfGrantID, forKey: .refreshOfGrantID)
        try container.encode(emailSensitivity, forKey: .emailSensitivity)
        try container.encodeIfPresent(summaryFraming, forKey: .summaryFraming)
        try container.encode(explicitSelection, forKey: .explicitSelection)
        try container.encode(noteCaptureMode, forKey: .noteCaptureMode)
        try container.encodeIfPresent(requestDetailLevel, forKey: .requestDetailLevel)
        try container.encode(memoryAccessEnabled, forKey: .memoryAccessEnabled)
    }
}

// MARK: - Grant ↔ Source (many-to-many)

public struct GrantSourceRecord: Sendable, Codable {
    public let grantID: String
    public let sourceID: String
    public let mountName: String
    public let baselineManifestHash: String?

    public init(grantID: String, sourceID: String, mountName: String, baselineManifestHash: String? = nil) {
        self.grantID = grantID
        self.sourceID = sourceID
        self.mountName = mountName
        self.baselineManifestHash = baselineManifestHash
    }

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

public struct GrantMount: Sendable, Hashable, Codable {
    public let sourceID: String
    public let mountName: String
    public let mountPath: String

    public init(sourceID: String, mountName: String, mountPath: String) {
        self.sourceID = sourceID
        self.mountName = mountName
        self.mountPath = mountPath
    }
}

public struct FileSelectionScope: Sendable, Hashable, Identifiable, Codable {
    public var id: String { "\(sourceID):\(normalizedRelativePath):\(isDirectory ? "dir" : "file")" }
    public let sourceID: String
    public let relativePath: String
    public let isDirectory: Bool

    public var normalizedRelativePath: String {
        Self.normalize(relativePath)
    }

    public init(sourceID: String, relativePath: String, isDirectory: Bool) {
        self.sourceID = sourceID
        self.relativePath = Self.normalize(relativePath)
        self.isDirectory = isDirectory
    }

    public func contains(relativePath: String) -> Bool {
        let normalizedPath = Self.normalize(relativePath)
        if isDirectory {
            if normalizedRelativePath.isEmpty {
                return true
            }
            return normalizedPath == normalizedRelativePath
                || normalizedPath.hasPrefix(normalizedRelativePath + "/")
        }
        return normalizedPath == normalizedRelativePath
    }

    public static func allows(_ relativePath: String, in scopes: [FileSelectionScope]) -> Bool {
        let normalizedPath = Self.normalize(relativePath)
        return scopes.contains { $0.contains(relativePath: normalizedPath) }
    }

    private static func normalize(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\\\", with: "/")
            .replacingOccurrences(of: "//", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

public struct GrantFileScopeRecord: Sendable, Hashable, Identifiable, Codable {
    public var id: String { "\(grantID):\(sourceID):\(relativePath):\(isDirectory ? "dir" : "file")" }
    public let grantID: String
    public let sourceID: String
    public let relativePath: String
    public let isDirectory: Bool

    public init?(row: [String: String]) {
        guard let grantID = row["grant_id"],
              let sourceID = row["source_id"],
              let relativePath = row["relative_path"] else {
            return nil
        }
        self.grantID = grantID
        self.sourceID = sourceID
        self.relativePath = relativePath
        self.isDirectory = row["is_directory"] == "1"
    }
}

public struct AccessPresetRecord: Sendable, Hashable, Identifiable, Codable {
    public var id: String { presetID }
    public let presetID: String
    public let name: String
    /// Agent this preset is scoped to when used as a named-session template.
    /// `nil` means the preset is unscoped (legacy presets, or templates that
    /// apply to any agent).
    public let targetApp: TargetApp?
    /// Per-Focus session settings, persisted alongside scope. `nil` means
    /// "use the agent's default" (no override). When the preset is activated
    /// as a Focus, these flow into the new grant via startSessionFromTemplate.
    public let requestDetailLevel: AccessRecordingLevel?
    public let noteCaptureMode: SessionNoteCaptureMode?
    public let allowFileMemory: Bool
    public let summaryFraming: String?
    public let emailSensitivity: EmailSensitivityLevel?
    /// At most one preset per `targetApp` may have this true at a time —
    /// invariant enforced by AccessStore.setDefaultAtLaunch via a clear+set
    /// transaction.
    public let isDefaultAtLaunch: Bool
    /// Per-Focus editor UI mode. `true` = scope editor shows ONE combined
    /// column; ticking a folder applies to both agents (writes scope rows
    /// with agent=''). `false` = the editor exposes the per-agent
    /// matrix (writes scope rows with agent='cowork' or 'codex').
    /// Default Focus is seeded with `false` to preserve today's
    /// independent-per-agent Access matrix behavior; new user Focuses
    /// default to `true` so creating "Q4 reports" implicitly mirrors
    /// across both AIs.
    public let mirrorToBoth: Bool
    /// Built-in Focuses (Default, Locked Down) — user can rename but not
    /// delete. The delete UI checks this flag.
    public let isBuiltIn: Bool
    public let createdAt: String
    public let updatedAt: String

    public init(
        presetID: String,
        name: String,
        targetApp: TargetApp? = nil,
        requestDetailLevel: AccessRecordingLevel? = nil,
        noteCaptureMode: SessionNoteCaptureMode? = nil,
        allowFileMemory: Bool = false,
        summaryFraming: String? = nil,
        emailSensitivity: EmailSensitivityLevel? = nil,
        isDefaultAtLaunch: Bool = false,
        mirrorToBoth: Bool = true,
        isBuiltIn: Bool = false,
        createdAt: String,
        updatedAt: String
    ) {
        self.presetID = presetID
        self.name = name
        self.targetApp = targetApp
        self.requestDetailLevel = requestDetailLevel
        self.noteCaptureMode = noteCaptureMode
        self.allowFileMemory = allowFileMemory
        self.summaryFraming = summaryFraming
        self.emailSensitivity = emailSensitivity
        self.isDefaultAtLaunch = isDefaultAtLaunch
        self.mirrorToBoth = mirrorToBoth
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init?(row: [String: String]) {
        guard let presetID = row["preset_id"],
              let name = row["name"],
              let createdAt = row["created_at"],
              let updatedAt = row["updated_at"] else {
            return nil
        }
        let targetAppRaw = row["target_app"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetApp: TargetApp?
        if let raw = targetAppRaw, !raw.isEmpty {
            targetApp = TargetApp(rawValue: raw)
        } else {
            targetApp = nil
        }
        self.presetID = presetID
        self.name = name
        self.targetApp = targetApp
        // New v43 columns — nil-tolerant for rows written before the migration.
        self.requestDetailLevel = row["request_detail_level"]
            .flatMap { $0.isEmpty ? nil : AccessRecordingLevel(rawValue: $0) }
        self.noteCaptureMode = row["note_capture_mode"]
            .flatMap { $0.isEmpty ? nil : SessionNoteCaptureMode(rawValue: $0) }
        self.allowFileMemory = row["allow_file_memory"] == "1"
        self.summaryFraming = row["summary_framing"].flatMap { $0.isEmpty ? nil : $0 }
        self.emailSensitivity = row["email_sensitivity"]
            .flatMap { $0.isEmpty ? nil : EmailSensitivityLevel(rawValue: $0) }
        self.isDefaultAtLaunch = row["is_default_at_launch"] == "1"
        // v44 columns. Default for legacy rows that haven't been touched
        // since the migration: mirror_to_both=1 is the column default
        // (new behavior); is_built_in=0 is the column default. Reading
        // returns whatever the DB has, with `1`/`0` parsed.
        self.mirrorToBoth = (row["mirror_to_both"] ?? "1") == "1"
        self.isBuiltIn = row["is_built_in"] == "1"
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Custom Codable: keep round-trips backwards-compatible with payloads
    // serialized before v43/v44 added the new fields. Booleans default
    // to sensible values when absent; optional settings default to nil.
    // Encoding writes everything.
    private enum CodingKeys: String, CodingKey {
        case presetID, name, targetApp
        case requestDetailLevel, noteCaptureMode, allowFileMemory
        case summaryFraming, emailSensitivity, isDefaultAtLaunch
        case mirrorToBoth, isBuiltIn
        case createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.presetID = try c.decode(String.self, forKey: .presetID)
        self.name = try c.decode(String.self, forKey: .name)
        self.targetApp = try c.decodeIfPresent(TargetApp.self, forKey: .targetApp)
        self.requestDetailLevel = try c.decodeIfPresent(AccessRecordingLevel.self, forKey: .requestDetailLevel)
        self.noteCaptureMode = try c.decodeIfPresent(SessionNoteCaptureMode.self, forKey: .noteCaptureMode)
        self.allowFileMemory = try c.decodeIfPresent(Bool.self, forKey: .allowFileMemory) ?? false
        self.summaryFraming = try c.decodeIfPresent(String.self, forKey: .summaryFraming)
        self.emailSensitivity = try c.decodeIfPresent(EmailSensitivityLevel.self, forKey: .emailSensitivity)
        self.isDefaultAtLaunch = try c.decodeIfPresent(Bool.self, forKey: .isDefaultAtLaunch) ?? false
        // mirrorToBoth defaults to true (matches v44 column default for
        // new presets). isBuiltIn defaults to false (column default).
        self.mirrorToBoth = try c.decodeIfPresent(Bool.self, forKey: .mirrorToBoth) ?? true
        self.isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        self.createdAt = try c.decode(String.self, forKey: .createdAt)
        self.updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(presetID, forKey: .presetID)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(targetApp, forKey: .targetApp)
        try c.encodeIfPresent(requestDetailLevel, forKey: .requestDetailLevel)
        try c.encodeIfPresent(noteCaptureMode, forKey: .noteCaptureMode)
        try c.encode(allowFileMemory, forKey: .allowFileMemory)
        try c.encodeIfPresent(summaryFraming, forKey: .summaryFraming)
        try c.encodeIfPresent(emailSensitivity, forKey: .emailSensitivity)
        try c.encode(isDefaultAtLaunch, forKey: .isDefaultAtLaunch)
        try c.encode(mirrorToBoth, forKey: .mirrorToBoth)
        try c.encode(isBuiltIn, forKey: .isBuiltIn)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - Email Message (metadata index for local mail archive)

public struct EmailMessageRecord: Sendable, Identifiable, Hashable, Codable {
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
    public let receivedAtRaw: String?
    public let receivedAtIsTrusted: Bool
    public let emlPath: String?         // archive-v2 manifest path; legacy encrypted EML in tests/dev safety only
    public let canonicalBlobCID: String?
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
    public let bodyText: String?         // plaintext FTS body, present only for explicit plaintext index mode

    public init(
        emailID: String,
        accountID: String,
        mailbox: String,
        sender: String,
        senderEmail: String? = nil,
        senderDomain: String? = nil,
        recipients: String,
        cc: String = "",
        subject: String,
        receivedAt: String,
        receivedAtRaw: String? = nil,
        receivedAtIsTrusted: Bool = true,
        emlPath: String? = nil,
        canonicalBlobCID: String? = nil,
        sizeBytes: Int = 0,
        preview: String? = nil,
        contentType: String? = nil,
        isRead: Bool = false,
        isFlagged: Bool = false,
        flagColor: String? = nil,
        inReplyTo: String? = nil,
        referencesHeader: String? = nil,
        messageIDHeader: String? = nil,
        attachmentCount: Int = 0,
        localIsViewed: Bool = false,
        isJunk: Bool = false,
        deletedOnServerAt: String? = nil,
        bodyText: String? = nil
    ) {
        self.emailID = emailID
        self.accountID = accountID
        self.mailbox = mailbox
        self.sender = sender
        self.senderEmail = senderEmail
        self.senderDomain = senderDomain
        self.recipients = recipients
        self.cc = cc
        self.subject = subject
        self.receivedAt = receivedAt
        self.receivedAtRaw = receivedAtRaw
        self.receivedAtIsTrusted = receivedAtIsTrusted
        self.emlPath = emlPath
        self.canonicalBlobCID = canonicalBlobCID
        self.sizeBytes = sizeBytes
        self.preview = preview
        self.contentType = contentType
        self.isRead = isRead
        self.isFlagged = isFlagged
        self.flagColor = flagColor
        self.inReplyTo = inReplyTo
        self.referencesHeader = referencesHeader
        self.messageIDHeader = messageIDHeader
        self.attachmentCount = attachmentCount
        self.localIsViewed = localIsViewed
        self.isJunk = isJunk
        self.deletedOnServerAt = deletedOnServerAt
        self.bodyText = bodyText
    }

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
        self.receivedAtRaw = row["received_at_raw"]
        self.receivedAtIsTrusted = row["received_at_is_trusted"] != "0"
        self.emlPath = row["eml_path"]
        self.canonicalBlobCID = row["canonical_blob_cid"]
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

public struct EmailMessagePage: Sendable, Hashable, Codable {
    public let messages: [EmailMessageRecord]
    public let totalCount: Int
    public let limit: Int
    public let offset: Int

    public init(messages: [EmailMessageRecord], totalCount: Int, limit: Int, offset: Int) {
        self.messages = messages
        self.totalCount = totalCount
        self.limit = limit
        self.offset = offset
    }
}

public struct EmailAttachmentRecord: Sendable, Identifiable, Hashable, Codable {
    public var id: String { attachmentID }
    public let attachmentID: String
    public let emailID: String
    public let filename: String
    public let mimeType: String
    public let sizeBytes: Int
    public let contentHash: String
    public let contentID: String?
    public let attachmentBlobCID: String?

    public init(
        attachmentID: String,
        emailID: String,
        filename: String,
        mimeType: String,
        sizeBytes: Int,
        contentHash: String,
        contentID: String? = nil,
        attachmentBlobCID: String? = nil
    ) {
        self.attachmentID = attachmentID
        self.emailID = emailID
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.contentHash = contentHash
        self.contentID = contentID
        self.attachmentBlobCID = attachmentBlobCID
    }

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
        self.attachmentBlobCID = row["attachment_blob_cid"]
    }
}

// MARK: - IMAP Mailbox (persisted folder tree from IMAP LIST)

public struct IMAPMailboxRecord: Sendable, Identifiable, Hashable, Codable {
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

    public enum FolderType: String, Sendable, Codable {
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

public struct SharedEmailRecord: Sendable, Identifiable, Codable {
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

public struct SmartMailboxRecord: Sendable, Identifiable, Codable {
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
        "size_bytes", "mailbox", "shared",
        "privacy_contains_sensitive", "privacy_contains_my_info",
        "privacy_contains_secret", "privacy_contains_third_party_private",
        "privacy_contains_org_only", "privacy_severity", "privacy_categories"
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
        case "privacy_contains_sensitive", "privacy_contains_my_info",
             "privacy_contains_secret", "privacy_contains_third_party_private",
             "privacy_contains_org_only":
            return .boolean
        case "attachment_count", "size_bytes": return .numeric
        case "mailbox", "privacy_severity": return .enumeration
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

public enum SearchTokenType: String, Sendable, CaseIterable, Codable {
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

public struct SearchToken: Sendable, Identifiable, Hashable, Codable {
    public var id: String { "\(type.rawValue):\(value)" }
    public let type: SearchTokenType
    public let value: String

    public init(type: SearchTokenType, value: String) {
        self.type = type
        self.value = value
    }
}

// MARK: - Quick Filter (sidebar filter presets)

public enum QuickFilter: String, Sendable, CaseIterable, Identifiable, Codable {
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

public enum EmailSortKey: String, Sendable, CaseIterable, Codable {
    case date
    case sender
    case subject
    case size
}

// MARK: - Promotion (result of writing grant changes back to originals)

public enum PromotionResult: String, Sendable, Codable {
    case applied
    case conflict
    case skipped
    case newFile = "new_file"
}

public struct PromotionRecord: Sendable, Identifiable, Codable {
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

public struct SessionSummaryRecord: Sendable, Identifiable, Codable {
    public var id: String { summaryID }
    public let summaryID: String
    public let grantID: String
    public let targetApp: String
    public let startedAt: String
    public let endedAt: String
    public let summaryMarkdown: String
    public let summaryJSONHash: String?
    public let summaryKind: String
    public let summaryOrigin: String

    public var kind: SessionSummaryKind {
        SessionSummaryKind(rawValue: summaryKind) ?? .summary
    }

    public var origin: SessionSummaryOrigin {
        SessionSummaryOrigin(rawValue: summaryOrigin) ?? .system
    }

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
        self.summaryKind = row["summary_kind"] ?? SessionSummaryKind.summary.rawValue
        self.summaryOrigin = row["summary_origin"] ?? SessionSummaryOrigin.system.rawValue
    }
}
