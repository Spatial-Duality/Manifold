// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Manages workspace lifecycles and access runs.
/// A run is a user-initiated access window — starts on "Grant to Claude",
/// ends on "End Access" or idle timeout.
public actor WorkspaceLeaseManager {
    private let db: DatabaseConnection
    private let snapshotStore: SnapshotStore

    public init(db: DatabaseConnection, snapshotStore: SnapshotStore) throws {
        self.db = db

        try db.execute("""
            CREATE TABLE IF NOT EXISTS workspaces (
                workspace_id TEXT PRIMARY KEY,
                profile_id TEXT NOT NULL,
                root_path TEXT NOT NULL,
                agent TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'idle',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS runs (
                run_id TEXT PRIMARY KEY,
                workspace_id TEXT NOT NULL,
                agent TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'active',
                trigger TEXT NOT NULL,
                started_at TEXT NOT NULL,
                ended_at TEXT,
                baseline_completed_at TEXT,
                FOREIGN KEY(workspace_id) REFERENCES workspaces(workspace_id)
            )
        """)

        self.snapshotStore = snapshotStore
    }

    // MARK: - Workspace Management

    /// Register a workspace in the database.
    public func registerWorkspace(id: String, profileID: String, rootPath: String, agent: String) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute("""
            INSERT OR REPLACE INTO workspaces (workspace_id, profile_id, root_path, agent, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, 'idle', ?, ?)
        """, params: [id, profileID, rootPath, agent, now, now])
    }

    /// Get all workspaces, most recently updated first.
    public func allWorkspaces() throws -> [WorkspaceRecord] {
        let rows = try db.queryAll("SELECT * FROM workspaces ORDER BY updated_at DESC")
        return rows.compactMap { WorkspaceRecord(row: $0) }
    }

    /// Get the workspace for a profile, if one exists.
    public func workspace(forProfile profileID: String) throws -> WorkspaceRecord? {
        let rows = try db.queryAll(
            "SELECT * FROM workspaces WHERE profile_id = ? LIMIT 1",
            params: [profileID]
        )
        return rows.first.flatMap { WorkspaceRecord(row: $0) }
    }

    /// Update workspace status. Values: "active", "idle", "archived"
    public func updateWorkspaceStatus(workspaceID: String, status: String) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            "UPDATE workspaces SET status = ?, updated_at = ? WHERE workspace_id = ?",
            params: [status, now, workspaceID]
        )
    }

    // MARK: - Access Runs

    /// Start a new access run. Called when user clicks "Grant to Claude" or "Refresh and Continue".
    /// Returns the new run ID.
    @discardableResult
    public func startRun(
        workspaceID: String,
        agent: String,
        trigger: RunTrigger
    ) throws -> String {
        // End any existing active run for this workspace
        try endActiveRuns(workspaceID: workspaceID)

        let runID = "run-\(UUID().uuidString.prefix(8).lowercased())"
        let now = ISO8601DateFormatter.shared.string(from: Date())

        try db.execute("""
            INSERT INTO runs (run_id, workspace_id, agent, status, trigger, started_at)
            VALUES (?, ?, ?, 'active', ?, ?)
        """, params: [runID, workspaceID, agent, trigger.rawValue, now])

        try updateWorkspaceStatus(workspaceID: workspaceID, status: "active")

        return runID
    }

    /// Mark baseline as completed for a run.
    public func markBaselineComplete(runID: String) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            "UPDATE runs SET baseline_completed_at = ? WHERE run_id = ?",
            params: [now, runID]
        )
    }

    /// End a specific run. Called when user clicks "End Access".
    public func endRun(runID: String) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            "UPDATE runs SET status = 'closed', ended_at = ? WHERE run_id = ?",
            params: [now, runID]
        )

        // Get workspace ID to update status
        if let wsID = try db.queryScalar(
            "SELECT workspace_id FROM runs WHERE run_id = ?",
            params: [runID]
        ) {
            // Check if any other runs are still active
            let activeCount = try db.queryScalar(
                "SELECT COUNT(*) FROM runs WHERE workspace_id = ? AND status = 'active'",
                params: [wsID]
            )
            if activeCount == "0" || activeCount == nil {
                try updateWorkspaceStatus(workspaceID: wsID, status: "idle")
            }
        }
    }

    /// End all active runs for a workspace.
    public func endActiveRuns(workspaceID: String) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            "UPDATE runs SET status = 'closed', ended_at = ? WHERE workspace_id = ? AND status = 'active'",
            params: [now, workspaceID]
        )
    }

    /// Get the current active run for a workspace, if any.
    public func activeRun(workspaceID: String) throws -> RunRecord? {
        let rows = try db.queryAll(
            "SELECT * FROM runs WHERE workspace_id = ? AND status = 'active' ORDER BY started_at DESC LIMIT 1",
            params: [workspaceID]
        )
        return rows.first.flatMap { RunRecord(row: $0) }
    }

    /// Get all runs for a workspace, most recent first.
    public func runs(workspaceID: String) throws -> [RunRecord] {
        let rows = try db.queryAll(
            "SELECT * FROM runs WHERE workspace_id = ? ORDER BY rowid DESC",
            params: [workspaceID]
        )
        return rows.compactMap { RunRecord(row: $0) }
    }

    /// Mark idle runs as closed after timeout.
    public func closeIdleRuns(idleTimeout: TimeInterval = 3600) throws {
        let cutoff = Date().addingTimeInterval(-idleTimeout)
        let cutoffStr = ISO8601DateFormatter.shared.string(from: cutoff)
        let now = ISO8601DateFormatter.shared.string(from: Date())

        // Find runs where no snapshot has been recorded since cutoff
        let idleRuns = try db.queryAll("""
            SELECT r.run_id, r.workspace_id FROM runs r
            WHERE r.status = 'active'
            AND NOT EXISTS (
                SELECT 1 FROM snapshots s
                WHERE s.run_id = r.run_id AND s.timestamp > ?
            )
            AND r.started_at < ?
        """, params: [cutoffStr, cutoffStr])

        for run in idleRuns {
            guard let runID = run["run_id"], let wsID = run["workspace_id"] else { continue }
            try db.execute(
                "UPDATE runs SET status = 'idle', ended_at = ? WHERE run_id = ?",
                params: [now, runID]
            )
            try updateWorkspaceStatus(workspaceID: wsID, status: "idle")
        }
    }
}

// MARK: - Types

public enum RunTrigger: String, Sendable {
    case userGrant = "user_grant"
    case userRefresh = "user_refresh"
    case autoResume = "auto_resume"
}

public struct WorkspaceRecord: Sendable, Hashable, Identifiable {
    public var id: String { workspaceID }
    public let workspaceID: String
    public let profileID: String
    public let rootPath: String
    public let agent: String
    public let status: String
    public let createdAt: String
    public let updatedAt: String

    init?(row: [String: String]) {
        guard let workspaceID = row["workspace_id"],
              let profileID = row["profile_id"],
              let rootPath = row["root_path"],
              let agent = row["agent"],
              let status = row["status"],
              let createdAt = row["created_at"],
              let updatedAt = row["updated_at"] else {
            return nil
        }
        self.workspaceID = workspaceID
        self.profileID = profileID
        self.rootPath = rootPath
        self.agent = agent
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RunRecord: Sendable, Identifiable {
    public var id: String { runID }
    public let runID: String
    public let workspaceID: String
    public let agent: String
    public let status: String
    public let trigger: String
    public let startedAt: String
    public let endedAt: String?
    public let baselineCompletedAt: String?

    public var isActive: Bool { status == "active" }

    init?(row: [String: String]) {
        guard let runID = row["run_id"],
              let workspaceID = row["workspace_id"],
              let agent = row["agent"],
              let status = row["status"],
              let trigger = row["trigger"],
              let startedAt = row["started_at"] else {
            return nil
        }
        self.runID = runID
        self.workspaceID = workspaceID
        self.agent = agent
        self.status = status
        self.trigger = trigger
        self.startedAt = startedAt
        self.endedAt = row["ended_at"]
        self.baselineCompletedAt = row["baseline_completed_at"]
    }
}
