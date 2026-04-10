import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "audit")

/// Records all user and system actions for accountability.
/// Every grant, end-access, restore, promote, and source change is logged.
///
/// Session grouping: entries are grouped into sessions by agent + 5-min time gap.
/// A `session_id` column is assigned at write time. Historical entries without
/// session_id get backfilled on first launch.
public actor AuditStore {
    private let db: DatabaseConnection
    private static let sessionGapSeconds: TimeInterval = 300 // 5 minutes

    public init(db: DatabaseConnection) throws {
        self.db = db

        try db.execute("""
            CREATE TABLE IF NOT EXISTS audit_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                run_id TEXT,
                workspace_id TEXT,
                agent TEXT,
                action TEXT NOT NULL,
                file_path TEXT,
                before_hash TEXT,
                after_hash TEXT,
                metadata TEXT,
                session_id TEXT,
                grant_id TEXT
            )
        """)

        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_audit_workspace ON audit_log(workspace_id)
        """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_audit_run ON audit_log(run_id)
        """)

        // session_id column and index are added by DatabaseMigrator v2.
        // CREATE INDEX IF NOT EXISTS is safe to run as a no-op guard.
        try db.execute("CREATE INDEX IF NOT EXISTS idx_audit_session ON audit_log(session_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_audit_grant ON audit_log(grant_id)")

        // Backfill session_ids for existing entries
        try backfillSessionIDs()
    }

    // MARK: - Session Assignment

    /// Determine the session_id for a new entry. Reuses the most recent session
    /// for the same agent if within 5 minutes, otherwise generates a new one.
    private func resolveSessionID(agent: String?, timestamp: Date) throws -> String {
        let agentValue = agent ?? ""
        let isoFormatter = ISO8601DateFormatter.shared

        if let lastRow = try db.queryAll("""
            SELECT session_id, timestamp FROM audit_log
            WHERE agent = ? AND session_id IS NOT NULL AND session_id != ''
            ORDER BY id DESC LIMIT 1
        """, params: [agentValue]).first,
           let lastSessionID = lastRow["session_id"]?.nilIfEmpty,
           let lastTimestamp = lastRow["timestamp"],
           let lastDate = isoFormatter.date(from: lastTimestamp) {
            if timestamp.timeIntervalSince(lastDate) <= Self.sessionGapSeconds {
                return lastSessionID
            }
        }

        return "session-\(UUID().uuidString.prefix(12).lowercased())"
    }

    /// One-time migration: assign session_ids to historical entries that lack them.
    private nonisolated func backfillSessionIDs() throws {
        let needsBackfill = try db.queryScalar("""
            SELECT COUNT(*) FROM audit_log WHERE session_id IS NULL OR session_id = ''
        """)
        guard let countStr = needsBackfill, let count = Int(countStr), count > 0 else { return }

        let rows = try db.queryAll("""
            SELECT id, timestamp, agent FROM audit_log
            WHERE session_id IS NULL OR session_id = ''
            ORDER BY id ASC
        """)

        let isoFormatter = ISO8601DateFormatter.shared
        var currentSessionID: String?
        var currentAgent: String?
        var lastDate: Date?

        for row in rows {
            guard let idStr = row["id"], let ts = row["timestamp"] else { continue }
            let agent = row["agent"]?.nilIfEmpty ?? ""
            let date = isoFormatter.date(from: ts) ?? Date.distantPast

            let needsNewSession = currentSessionID == nil
                || agent != currentAgent
                || lastDate.map({ date.timeIntervalSince($0) > Self.sessionGapSeconds }) ?? true

            if needsNewSession {
                currentSessionID = "session-\(UUID().uuidString.prefix(12).lowercased())"
                currentAgent = agent
            }
            lastDate = date

            try db.execute(
                "UPDATE audit_log SET session_id = ? WHERE id = ?",
                params: [currentSessionID!, idStr]
            )
        }
    }

    // MARK: - Logging

    /// Log an action.
    public func log(
        action: AuditAction,
        runID: String? = nil,
        workspaceID: String? = nil,
        agent: String? = nil,
        filePath: String? = nil,
        beforeHash: String? = nil,
        afterHash: String? = nil,
        metadata: [String: String]? = nil,
        grantID: String? = nil
    ) throws {
        let now = Date()
        let timestamp = ISO8601DateFormatter.shared.string(from: now)
        let sessionID = try resolveSessionID(agent: agent, timestamp: now)
        let metadataJSON: String? = metadata.flatMap { dict in
            do {
                let data = try JSONSerialization.data(withJSONObject: dict)
                return String(data: data, encoding: .utf8)
            } catch {
                logger.warning("Failed to serialize audit metadata: \(error.localizedDescription)")
                return nil
            }
        }

        try db.execute("""
            INSERT INTO audit_log (timestamp, run_id, workspace_id, agent, action, file_path, before_hash, after_hash, metadata, session_id, grant_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, params: [
            timestamp,
            runID ?? "",
            workspaceID ?? "",
            agent ?? "",
            action.rawValue,
            filePath ?? "",
            beforeHash ?? "",
            afterHash ?? "",
            metadataJSON ?? "",
            sessionID,
            grantID ?? ""
        ])
    }

    // MARK: - Entry Queries

    /// Query audit entries for a workspace.
    public func entries(workspaceID: String, limit: Int = 100) throws -> [AuditEntry] {
        let rows = try db.queryAll("""
            SELECT id, timestamp, run_id, workspace_id, agent, action, file_path, before_hash, after_hash, metadata, session_id
            FROM audit_log
            WHERE workspace_id = ?
            ORDER BY id DESC
            LIMIT ?
        """, params: [workspaceID, "\(limit)"])

        return rows.compactMap { AuditEntry(row: $0) }
    }

    /// Query all audit entries across workspaces.
    public func recentEntries(limit: Int = 50) throws -> [AuditEntry] {
        let rows = try db.queryAll("""
            SELECT id, timestamp, run_id, workspace_id, agent, action, file_path, before_hash, after_hash, metadata, session_id, grant_id
            FROM audit_log
            ORDER BY id DESC
            LIMIT ?
        """, params: ["\(limit)"])

        return rows.compactMap { AuditEntry(row: $0) }
    }

    /// Query audit entries by grant ID (uses indexed column from migration v5).
    public func entriesByGrant(grantID: String, limit: Int = 50) throws -> [AuditEntry] {
        let rows = try db.queryAll("""
            SELECT id, timestamp, run_id, workspace_id, agent, action, file_path, before_hash, after_hash, metadata, session_id, grant_id
            FROM audit_log
            WHERE grant_id = ?
            ORDER BY id DESC
            LIMIT ?
        """, params: [grantID, "\(limit)"])

        return rows.compactMap { AuditEntry(row: $0) }
    }

    // MARK: - Session Queries

    /// List recent sessions, newest first.
    public func recentSessions(limit: Int = 20) throws -> [Session] {
        let rows = try db.queryAll("""
            SELECT session_id,
                   COALESCE(NULLIF(agent, ''), 'Unknown Agent') as agent,
                   MIN(timestamp) as start_time,
                   MAX(timestamp) as end_time,
                   COUNT(*) as action_count,
                   SUM(CASE WHEN action = 'file_read' THEN 1 ELSE 0 END) as read_count,
                   SUM(CASE WHEN action IN ('file_modified', 'file_created') THEN 1 ELSE 0 END) as write_count,
                   SUM(CASE WHEN action = 'tool_call' AND metadata LIKE '%search%' THEN 1 ELSE 0 END) as search_count
            FROM audit_log
            WHERE session_id IS NOT NULL AND session_id != ''
            GROUP BY session_id
            ORDER BY end_time DESC
            LIMIT ?
        """, params: ["\(limit)"])

        return rows.compactMap { Session(row: $0) }
    }

    /// Get all events for a session.
    /// Write events rely on hashes captured in audit_log at write time plus an optional
    /// `snapshot_id` stored in metadata, so history does not need a lossy timestamp join.
    public func sessionEvents(sessionID: String) throws -> [SessionEvent] {
        let rows = try db.queryAll("""
            SELECT id, timestamp, action, agent, file_path, metadata, before_hash, after_hash
            FROM audit_log
            WHERE session_id = ?
            ORDER BY id ASC
        """, params: [sessionID])
        return rows.compactMap { SessionEvent(row: $0) }
    }
}

// MARK: - Types

public enum AuditAction: String, Sendable {
    case sourceAdded = "source_added"
    case sourceRemoved = "source_removed"
    case profileChanged = "profile_changed"
    case runStart = "run_start"
    case runEnd = "run_end"
    case fileModified = "file_modified"
    case fileCreated = "file_created"
    case fileDeleted = "file_deleted"
    case restore = "restore"
    case promote = "promote"
    case sensitivityWarning = "sensitivity_warning"
    case fileRead = "file_read"
    case mcpConnection = "mcp_connection"
    case toolCall = "tool_call"
}

public struct AuditEntry: Sendable, Identifiable {
    public let id: Int
    public let timestamp: String
    public let runID: String?
    public let workspaceID: String?
    public let agent: String?
    public let action: String
    public let filePath: String?
    public let beforeHash: String?
    public let afterHash: String?
    public let metadata: String?
    public let sessionID: String?
    public let grantID: String?

    init?(row: [String: String]) {
        guard let idStr = row["id"], let id = Int(idStr),
              let timestamp = row["timestamp"],
              let action = row["action"] else {
            return nil
        }
        self.id = id
        self.timestamp = timestamp
        self.runID = row["run_id"]?.nilIfEmpty
        self.workspaceID = row["workspace_id"]?.nilIfEmpty
        self.agent = row["agent"]?.nilIfEmpty
        self.action = action
        self.filePath = row["file_path"]?.nilIfEmpty
        self.beforeHash = row["before_hash"]?.nilIfEmpty
        self.afterHash = row["after_hash"]?.nilIfEmpty
        self.metadata = row["metadata"]?.nilIfEmpty
        self.sessionID = row["session_id"]?.nilIfEmpty
        self.grantID = row["grant_id"]?.nilIfEmpty
    }
}

// MARK: - Session Types

public struct Session: Sendable, Identifiable, Hashable {
    public let id: String
    public let agent: String
    public let startTime: String
    public let endTime: String
    public let actionCount: Int
    public let readCount: Int
    public let writeCount: Int
    public let searchCount: Int

    init?(row: [String: String]) {
        guard let sessionID = row["session_id"]?.nilIfEmpty,
              let agent = row["agent"],
              let startTime = row["start_time"],
              let endTime = row["end_time"] else {
            return nil
        }
        self.id = sessionID
        self.agent = agent
        self.startTime = startTime
        self.endTime = endTime
        self.actionCount = Int(row["action_count"] ?? "0") ?? 0
        self.readCount = Int(row["read_count"] ?? "0") ?? 0
        self.writeCount = Int(row["write_count"] ?? "0") ?? 0
        self.searchCount = Int(row["search_count"] ?? "0") ?? 0
    }
}

public struct SessionEvent: Sendable, Identifiable {
    public let id: Int
    public let timestamp: String
    public let action: String
    public let agent: String?
    public let filePath: String?
    public let metadata: String?
    public let snapshotID: Int?
    public let beforeHash: String?
    public let afterHash: String?

    init?(row: [String: String]) {
        guard let idStr = row["id"], let id = Int(idStr),
              let timestamp = row["timestamp"],
              let action = row["action"] else {
            return nil
        }
        let metadata = row["metadata"]?.nilIfEmpty
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.agent = row["agent"]?.nilIfEmpty
        self.filePath = row["file_path"]?.nilIfEmpty
        self.metadata = metadata
        self.snapshotID = row["snapshot_id"].flatMap { Int($0) } ?? Self.snapshotID(from: metadata)
        self.beforeHash = row["before_hash"]?.nilIfEmpty
        self.afterHash = row["after_hash"]?.nilIfEmpty
    }

    public var isWriteEvent: Bool {
        action == "file_modified" || action == "file_created"
    }

    private static func snapshotID(from metadata: String?) -> Int? {
        guard let metadata,
              let data = metadata.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let snapshotID = json["snapshot_id"].flatMap(Int.init) else {
            return nil
        }
        return snapshotID
    }
}
