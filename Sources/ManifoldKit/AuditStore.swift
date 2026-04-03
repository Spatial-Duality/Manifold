import Foundation

/// Records all user and system actions for accountability.
/// Every grant, end-access, restore, promote, and source change is logged.
public actor AuditStore {
    private let db: DatabaseConnection

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
                metadata TEXT
            )
        """)

        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_audit_workspace ON audit_log(workspace_id)
        """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_audit_run ON audit_log(run_id)
        """)
    }

    /// Log an action.
    public func log(
        action: AuditAction,
        runID: String? = nil,
        workspaceID: String? = nil,
        agent: String? = nil,
        filePath: String? = nil,
        beforeHash: String? = nil,
        afterHash: String? = nil,
        metadata: [String: String]? = nil
    ) throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let metadataJSON: String? = metadata.flatMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let str = String(data: data, encoding: .utf8) else { return nil }
            return str
        }

        try db.execute("""
            INSERT INTO audit_log (timestamp, run_id, workspace_id, agent, action, file_path, before_hash, after_hash, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, params: [
            timestamp,
            runID ?? "",
            workspaceID ?? "",
            agent ?? "",
            action.rawValue,
            filePath ?? "",
            beforeHash ?? "",
            afterHash ?? "",
            metadataJSON ?? ""
        ])
    }

    /// Query audit entries for a workspace.
    public func entries(workspaceID: String, limit: Int = 100) throws -> [AuditEntry] {
        let rows = try db.queryAll("""
            SELECT id, timestamp, run_id, workspace_id, agent, action, file_path, before_hash, after_hash, metadata
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
            SELECT id, timestamp, run_id, workspace_id, agent, action, file_path, before_hash, after_hash, metadata
            FROM audit_log
            ORDER BY id DESC
            LIMIT ?
        """, params: ["\(limit)"])

        return rows.compactMap { AuditEntry(row: $0) }
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
}

public struct AuditEntry: Sendable {
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

    init?(row: [String: String]) {
        guard let idStr = row["id"], let id = Int(idStr),
              let timestamp = row["timestamp"],
              let action = row["action"] else {
            return nil
        }
        self.id = id
        self.timestamp = timestamp
        self.runID = row["run_id"].flatMap { $0.isEmpty ? nil : $0 }
        self.workspaceID = row["workspace_id"].flatMap { $0.isEmpty ? nil : $0 }
        self.agent = row["agent"].flatMap { $0.isEmpty ? nil : $0 }
        self.action = action
        self.filePath = row["file_path"].flatMap { $0.isEmpty ? nil : $0 }
        self.beforeHash = row["before_hash"].flatMap { $0.isEmpty ? nil : $0 }
        self.afterHash = row["after_hash"].flatMap { $0.isEmpty ? nil : $0 }
        self.metadata = row["metadata"].flatMap { $0.isEmpty ? nil : $0 }
    }
}
