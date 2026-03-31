import Foundation

/// Records every file version in every managed workspace.
/// Each snapshot references a blob in ContentStore by hash (deduped).
/// Snapshots are grouped by run_id (user-initiated access windows) and workspace_id.
public actor SnapshotStore {
    private let db: DatabaseConnection
    private let contentStore: ContentStore

    public init(db: DatabaseConnection, contentStore: ContentStore) throws {
        self.db = db
        self.contentStore = contentStore

        try db.execute("""
            CREATE TABLE IF NOT EXISTS snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                run_id TEXT NOT NULL,
                workspace_id TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                file_path TEXT NOT NULL,
                after_hash TEXT,
                before_hash TEXT,
                is_baseline INTEGER DEFAULT 0,
                is_delete INTEGER DEFAULT 0,
                source TEXT DEFAULT 'agent'
            )
        """)

        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_snapshots_run ON snapshots(run_id)
        """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_snapshots_workspace ON snapshots(workspace_id)
        """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_snapshots_path ON snapshots(file_path)
        """)
    }

    /// Record a baseline snapshot (the "before AI touched anything" state).
    public func recordBaseline(runID: String, workspaceID: String, filePath: String, data: Data) async throws {
        let hash = try await contentStore.ingest(data: data)
        let timestamp = ISO8601DateFormatter().string(from: Date())

        try db.transaction {
            try db.execute("""
                INSERT INTO snapshots (run_id, workspace_id, timestamp, file_path, after_hash, before_hash, is_baseline, source)
                VALUES (?, ?, ?, ?, ?, NULL, 1, 'manifold')
            """, params: [runID, workspaceID, timestamp, filePath, hash])

            try db.execute("UPDATE content_meta SET ref_count = ref_count + 1 WHERE hash = ?", params: [hash])
        }
    }

    /// Record a file modification (agent wrote to a file).
    public func recordModification(runID: String, workspaceID: String, filePath: String, newData: Data, source: String = "agent") async throws {
        let afterHash = try await contentStore.ingest(data: newData)
        let beforeHash = try latestHash(runID: runID, filePath: filePath)
        let timestamp = ISO8601DateFormatter().string(from: Date())

        try db.transaction {
            try db.execute("""
                INSERT INTO snapshots (run_id, workspace_id, timestamp, file_path, after_hash, before_hash, is_baseline, source)
                VALUES (?, ?, ?, ?, ?, ?, 0, ?)
            """, params: [runID, workspaceID, timestamp, filePath, afterHash, beforeHash ?? "", source])

            try db.execute("UPDATE content_meta SET ref_count = ref_count + 1 WHERE hash = ?", params: [afterHash])
        }
    }

    /// Record a file creation (agent created a new file).
    public func recordCreation(runID: String, workspaceID: String, filePath: String, data: Data) async throws {
        let hash = try await contentStore.ingest(data: data)
        let timestamp = ISO8601DateFormatter().string(from: Date())

        try db.transaction {
            try db.execute("""
                INSERT INTO snapshots (run_id, workspace_id, timestamp, file_path, after_hash, before_hash, is_baseline, source)
                VALUES (?, ?, ?, ?, ?, NULL, 0, 'agent')
            """, params: [runID, workspaceID, timestamp, filePath, hash])

            try db.execute("UPDATE content_meta SET ref_count = ref_count + 1 WHERE hash = ?", params: [hash])
        }
    }

    /// Record a file deletion.
    public func recordDeletion(runID: String, workspaceID: String, filePath: String) throws {
        let beforeHash = try latestHash(runID: runID, filePath: filePath)
        let timestamp = ISO8601DateFormatter().string(from: Date())

        try db.execute("""
            INSERT INTO snapshots (run_id, workspace_id, timestamp, file_path, after_hash, before_hash, is_delete, source)
            VALUES (?, ?, ?, ?, NULL, ?, 1, 'agent')
        """, params: [runID, workspaceID, timestamp, filePath, beforeHash ?? ""])
    }

    /// Record a restore action.
    public func recordRestore(runID: String, workspaceID: String, filePath: String, restoredData: Data) async throws {
        try await recordModification(runID: runID, workspaceID: workspaceID, filePath: filePath, newData: restoredData, source: "manifold-restore")
    }

    /// Get the latest hash for a file in a run.
    public func latestHash(runID: String, filePath: String) throws -> String? {
        try db.queryScalar("""
            SELECT after_hash FROM snapshots
            WHERE run_id = ? AND file_path = ? AND is_delete = 0
            ORDER BY id DESC LIMIT 1
        """, params: [runID, filePath])
    }

    /// Get the baseline hash for a file in a run.
    public func baselineHash(runID: String, filePath: String) throws -> String? {
        try db.queryScalar("""
            SELECT after_hash FROM snapshots
            WHERE run_id = ? AND file_path = ? AND is_baseline = 1
            ORDER BY id ASC LIMIT 1
        """, params: [runID, filePath])
    }

    /// Get all snapshots for a file in a run, ordered by time.
    public func history(runID: String, filePath: String) throws -> [SnapshotRecord] {
        let rows = try db.queryAll("""
            SELECT id, run_id, workspace_id, timestamp, file_path, after_hash, before_hash, is_baseline, is_delete, source
            FROM snapshots
            WHERE run_id = ? AND file_path = ?
            ORDER BY id ASC
        """, params: [runID, filePath])

        return rows.compactMap { SnapshotRecord(row: $0) }
    }

    /// Get all snapshots for a run, ordered by time (most recent first).
    public func runTimeline(runID: String) throws -> [SnapshotRecord] {
        let rows = try db.queryAll("""
            SELECT id, run_id, workspace_id, timestamp, file_path, after_hash, before_hash, is_baseline, is_delete, source
            FROM snapshots
            WHERE run_id = ?
            ORDER BY id DESC
        """, params: [runID])

        return rows.compactMap { SnapshotRecord(row: $0) }
    }

    /// Get all snapshots for a workspace across all runs (most recent first).
    public func workspaceTimeline(workspaceID: String) throws -> [SnapshotRecord] {
        let rows = try db.queryAll("""
            SELECT id, run_id, workspace_id, timestamp, file_path, after_hash, before_hash, is_baseline, is_delete, source
            FROM snapshots
            WHERE workspace_id = ?
            ORDER BY id DESC
        """, params: [workspaceID])

        return rows.compactMap { SnapshotRecord(row: $0) }
    }

    /// Get all modified files in a run (excludes baselines).
    public func modifiedFiles(runID: String) throws -> [String] {
        let rows = try db.queryAll("""
            SELECT DISTINCT file_path FROM snapshots
            WHERE run_id = ? AND is_baseline = 0
        """, params: [runID])

        return rows.compactMap { $0["file_path"] }
    }

    /// Restore a file to its state at a given snapshot ID. Returns the data.
    public func dataForRestore(snapshotID: Int) async throws -> Data? {
        guard let hash = try db.queryScalar(
            "SELECT after_hash FROM snapshots WHERE id = ?",
            params: ["\(snapshotID)"]
        ) else {
            return nil
        }
        return try await contentStore.retrieve(hash: hash)
    }

    /// Prune snapshots from old runs, keeping the last N per workspace.
    @discardableResult
    public func pruneOldRuns(keepLast: Int = 10) throws -> Int {
        let runs = try db.queryAll("""
            SELECT run_id, MAX(id) as max_id FROM snapshots
            GROUP BY run_id ORDER BY max_id DESC
        """)

        guard runs.count > keepLast else { return 0 }

        let toPrune = runs.dropFirst(keepLast)
        var pruned = 0

        for run in toPrune {
            guard let runID = run["run_id"] else { continue }

            let hashes = try db.queryAll(
                "SELECT after_hash FROM snapshots WHERE run_id = ? AND after_hash IS NOT NULL",
                params: [runID]
            )

            try db.transaction {
                try db.execute("DELETE FROM snapshots WHERE run_id = ?", params: [runID])

                for row in hashes {
                    if let hash = row["after_hash"], !hash.isEmpty {
                        try db.execute(
                            "UPDATE content_meta SET ref_count = ref_count - 1 WHERE hash = ?",
                            params: [hash]
                        )
                    }
                }
            }

            pruned += hashes.count
        }

        return pruned
    }
}

// MARK: - SnapshotRecord

public struct SnapshotRecord: Sendable {
    public let id: Int
    public let runID: String
    public let workspaceID: String
    public let timestamp: String
    public let filePath: String
    public let afterHash: String?
    public let beforeHash: String?
    public let isBaseline: Bool
    public let isDelete: Bool
    public let source: String

    init?(row: [String: String]) {
        guard let idStr = row["id"], let id = Int(idStr),
              let runID = row["run_id"],
              let workspaceID = row["workspace_id"],
              let timestamp = row["timestamp"],
              let filePath = row["file_path"] else {
            return nil
        }
        self.id = id
        self.runID = runID
        self.workspaceID = workspaceID
        self.timestamp = timestamp
        self.filePath = filePath
        self.afterHash = row["after_hash"]
        self.beforeHash = row["before_hash"]
        self.isBaseline = row["is_baseline"] == "1"
        self.isDelete = row["is_delete"] == "1"
        self.source = row["source"] ?? "agent"
    }
}
