// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

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
        let timestamp = ISO8601DateFormatter.shared.string(from: Date())

        try db.transaction {
            try db.execute("""
                INSERT INTO snapshots (run_id, workspace_id, timestamp, file_path, after_hash, before_hash, is_baseline, source)
                VALUES (?, ?, ?, ?, ?, NULL, 1, 'manifold')
            """, params: [runID, workspaceID, timestamp, filePath, hash])

            try db.execute("UPDATE content_meta SET ref_count = ref_count + 1 WHERE hash = ?", params: [hash])
        }
    }

    /// Record a file modification (agent wrote to a file).
    @discardableResult
    public func recordModification(runID: String, workspaceID: String, filePath: String, newData: Data, source: String = "agent") async throws -> SnapshotWriteResult {
        let afterHash = try await contentStore.ingest(data: newData)
        let beforeHash = try latestHash(runID: runID, filePath: filePath)
        let timestamp = ISO8601DateFormatter.shared.string(from: Date())
        var snapshotID: Int?

        try db.transaction {
            try db.execute("""
                INSERT INTO snapshots (run_id, workspace_id, timestamp, file_path, after_hash, before_hash, is_baseline, source)
                VALUES (?, ?, ?, ?, ?, ?, 0, ?)
            """, params: [runID, workspaceID, timestamp, filePath, afterHash, beforeHash, source])

            snapshotID = try db.queryScalar("SELECT last_insert_rowid()").flatMap(Int.init)

            try db.execute("UPDATE content_meta SET ref_count = ref_count + 1 WHERE hash = ?", params: [afterHash])
        }

        guard let snapshotID else {
            throw ManifoldError.snapshotFailed("Failed to record snapshot id for \(filePath)")
        }

        return SnapshotWriteResult(
            id: snapshotID,
            beforeHash: beforeHash,
            afterHash: afterHash
        )
    }

    /// Record a file creation (agent created a new file).
    public func recordCreation(runID: String, workspaceID: String, filePath: String, data: Data) async throws {
        let hash = try await contentStore.ingest(data: data)
        let timestamp = ISO8601DateFormatter.shared.string(from: Date())

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
        let timestamp = ISO8601DateFormatter.shared.string(from: Date())

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

    /// Get all snapshots for a file across ALL runs, most recent first.
    public func fileHistory(filePath: String) throws -> [SnapshotRecord] {
        let rows = try db.queryAll("""
            SELECT id, run_id, workspace_id, timestamp, file_path, after_hash, before_hash, is_baseline, is_delete, source
            FROM snapshots
            WHERE file_path = ?
            ORDER BY id DESC
        """, params: [filePath])

        return rows.compactMap { SnapshotRecord(row: $0) }
    }

    /// Get one snapshot by id.
    public func snapshot(id: Int) throws -> SnapshotRecord? {
        let rows = try db.queryAll("""
            SELECT id, run_id, workspace_id, timestamp, file_path, after_hash, before_hash, is_baseline, is_delete, source
            FROM snapshots
            WHERE id = ?
            LIMIT 1
        """, params: ["\(id)"])

        return rows.first.flatMap { SnapshotRecord(row: $0) }
    }

    /// Get the latest known non-delete hash for a canonical file path across all runs.
    public func latestHash(filePath: String) throws -> String? {
        try db.queryScalar("""
            SELECT after_hash FROM snapshots
            WHERE file_path = ? AND is_delete = 0 AND after_hash IS NOT NULL
            ORDER BY id DESC LIMIT 1
        """, params: [filePath])
    }

    /// Get all distinct file paths that have at least one snapshot.
    public func allTrackedFiles() throws -> [String] {
        let rows = try db.queryAll("SELECT DISTINCT file_path FROM snapshots ORDER BY file_path")
        return rows.compactMap { $0["file_path"] }
    }

    /// Count snapshots by canonical file path. Used by the app's Files
    /// table so version badges line up with the same canonical paths that
    /// MCP tools and the snapshot store use.
    public func snapshotCountsByPath() throws -> [String: Int] {
        let rows = try db.queryAll("""
            SELECT file_path, COUNT(*) AS snapshot_count
            FROM snapshots
            GROUP BY file_path
            ORDER BY file_path
        """)
        var result: [String: Int] = [:]
        for row in rows {
            guard let path = row["file_path"] else { continue }
            result[path] = Int(row["snapshot_count"] ?? "0") ?? 0
        }
        return result
    }

    /// File paths that have at least one non-baseline snapshot whose
    /// `source` indicates an AI tool wrote the bytes. Used by the
    /// Files table to render the sparkle (✦) at a glance across the
    /// whole listing — Goal 6 from the redesign brief.
    ///
    /// The schema's source field is free-form ("agent", "mcp",
    /// "mcp_draft_workspace", "standing_write_auto", "manifold-restore",
    /// etc.); keep this broad enough to catch current governed AI write
    /// paths without marking restore/baseline rows.
    public func aiTouchedFilePaths() throws -> Set<String> {
        let rows = try db.queryAll(
            """
            SELECT DISTINCT file_path FROM snapshots
            WHERE is_baseline = 0
              AND (
                LOWER(source) LIKE '%agent%'
                OR LOWER(source) LIKE '%mcp%'
                OR LOWER(source) LIKE 'standing_write_%'
              )
            """
        )
        return Set(rows.compactMap { $0["file_path"] })
    }

    /// Count of distinct files under `rootPath` with non-baseline snapshots
    /// recorded after `sinceTimestamp`. Used by the per-source drift
    /// indicator on FoldersMatrixView — "12 files modified since Claude's
    /// last session ended."
    ///
    /// `rootPath` is matched as a prefix; passing the source's
    /// originalRootPath catches every file under it. `sinceTimestamp` is
    /// an ISO 8601 string (the snapshots table stores timestamps as text
    /// and ISO 8601 sorts correctly as text). Pass an empty string to get
    /// total non-baseline write count for the source.
    public func driftCount(rootPath: String, sinceTimestamp: String) throws -> Int {
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let result = try db.queryScalar(
            """
            SELECT COUNT(DISTINCT file_path) FROM snapshots
            WHERE is_baseline = 0
              AND file_path LIKE ?
              AND timestamp > ?
            """,
            params: [prefix + "%", sinceTimestamp]
        )
        return Int(result ?? "0") ?? 0
    }

    /// Count distinct files in one source/workspace with non-baseline snapshots
    /// after `sinceTimestamp`. Direct original writes store `workspace_id` as
    /// the source ID, while `file_path` remains canonical (`mount/file`).
    public func driftCount(workspaceID: String, sinceTimestamp: String) throws -> Int {
        let result = try db.queryScalar(
            """
            SELECT COUNT(DISTINCT file_path) FROM snapshots
            WHERE is_baseline = 0
              AND workspace_id = ?
              AND timestamp > ?
            """,
            params: [workspaceID, sinceTimestamp]
        )
        return Int(result ?? "0") ?? 0
    }

    /// Count snapshots for a file path.
    public func snapshotCount(filePath: String) throws -> Int {
        let result = try db.queryScalar(
            "SELECT COUNT(*) FROM snapshots WHERE file_path = ?",
            params: [filePath]
        )
        return Int(result ?? "0") ?? 0
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

    /// Prune snapshots older than a number of days.
    /// Uses CTE instead of correlated subquery (O(n) vs O(n²)).
    /// Batches all deletes into a single transaction (1 fsync vs N fsyncs).
    @discardableResult
    public func pruneByAge(days: Int = 30) throws -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let cutoffStr = ISO8601DateFormatter.shared.string(from: cutoff)

        // CTE pre-computes file counts once, then JOINs — O(n) not O(n²)
        let toDelete = try db.queryAll("""
            WITH file_counts AS (
                SELECT file_path, COUNT(*) as cnt FROM snapshots GROUP BY file_path
            )
            SELECT s.id, s.after_hash
            FROM snapshots s
            JOIN file_counts fc ON s.file_path = fc.file_path
            WHERE s.timestamp < ? AND fc.cnt > 1
        """, params: [cutoffStr])

        guard !toDelete.isEmpty else { return 0 }

        // Single transaction for all deletes — 1 fsync instead of N
        var pruned = 0
        try db.transaction {
            for row in toDelete {
                guard let idStr = row["id"] else { continue }
                try db.execute("DELETE FROM snapshots WHERE id = ?", params: [idStr])
                if let hash = row["after_hash"], !hash.isEmpty {
                    try db.execute(
                        "UPDATE content_meta SET ref_count = ref_count - 1 WHERE hash = ?",
                        params: [hash]
                    )
                }
                pruned += 1
            }
        }
        return pruned
    }

    /// Prune excess versions per file, keeping the most recent N.
    /// Batches all deletes into a single transaction.
    @discardableResult
    public func pruneByFileCount(maxPerFile: Int = 50) throws -> Int {
        let files = try db.queryAll("SELECT DISTINCT file_path FROM snapshots")
        var pruned = 0

        try db.transaction {
            for file in files {
                guard let filePath = file["file_path"] else { continue }
                let excess = try db.queryAll("""
                    SELECT id, after_hash FROM snapshots
                    WHERE file_path = ?
                    ORDER BY id DESC
                    LIMIT -1 OFFSET ?
                """, params: [filePath, "\(maxPerFile)"])

                for row in excess {
                    guard let idStr = row["id"] else { continue }
                    try db.execute("DELETE FROM snapshots WHERE id = ?", params: [idStr])
                    if let hash = row["after_hash"], !hash.isEmpty {
                        try db.execute(
                            "UPDATE content_meta SET ref_count = ref_count - 1 WHERE hash = ?",
                            params: [hash]
                        )
                    }
                    pruned += 1
                }
            }
        }
        return pruned
    }
}

public struct SnapshotWriteResult: Sendable, Hashable {
    public let id: Int
    public let beforeHash: String?
    public let afterHash: String

    public init(id: Int, beforeHash: String?, afterHash: String) {
        self.id = id
        self.beforeHash = beforeHash
        self.afterHash = afterHash
    }
}

// MARK: - SnapshotRecord

public struct SnapshotRecord: Sendable, Hashable, Identifiable, Codable {
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
