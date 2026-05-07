// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "workblock")

/// Manages optional tracked work blocks with snapshot/promote lifecycle.
/// Explicit work blocks freeze their selected scope at start. Default work
/// blocks are launched from standing access; the runtime bridge re-resolves the
/// current Access matrix so sharing toggles are visible on the next tool call.
public actor WorkBlockStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    // MARK: - Work Block Lifecycle

    /// Start a new work block for an agent. Only one active block per agent.
    public func startBlock(
        agent: TargetApp,
        grantID: String,
        sourceIDs: [String]
    ) throws -> WorkBlockRecord {
        // End any existing active block for this agent
        if let existing = try activeBlock(for: agent) {
            try endBlock(id: existing.id, status: .discarded)
        }

        let block = WorkBlockRecord(
            agent: agent,
            grantID: grantID,
            sourceIDs: sourceIDs
        )

        try db.execute("""
            INSERT INTO work_block_records (work_block_id, agent, grant_id, source_ids,
                started_at, status, modified_file_count, new_file_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, params: [
            block.id,
            agent.rawValue,
            grantID,
            block.encodeSourceIDs(),
            block.startedAt,
            block.status.rawValue,
            "\(block.modifiedFileCount)",
            "\(block.newFileCount)",
        ])

        logger.info("Started work block \(block.id) for \(agent.rawValue)")
        return block
    }

    /// Get the active work block for an agent, if any.
    public func activeBlock(for agent: TargetApp) throws -> WorkBlockRecord? {
        let rows = try db.queryAll("""
            SELECT * FROM work_block_records
            WHERE agent = ? AND status IN ('active', 'paused')
            ORDER BY started_at DESC LIMIT 1
        """, params: [agent.rawValue])
        return rows.first.flatMap { WorkBlockRecord(row: $0) }
    }

    /// Get a specific work block by ID.
    public func block(id: String) throws -> WorkBlockRecord? {
        let rows = try db.queryAll(
            "SELECT * FROM work_block_records WHERE work_block_id = ? LIMIT 1",
            params: [id]
        )
        return rows.first.flatMap { WorkBlockRecord(row: $0) }
    }

    /// End a work block with a specific status.
    public func endBlock(id: String, status: WorkBlockStatus) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute("""
            UPDATE work_block_records
            SET status = ?, ended_at = ?
            WHERE work_block_id = ? AND status IN ('active', 'paused', 'reviewing')
        """, params: [status.rawValue, now, id])
        logger.info("Ended work block \(id) with status \(status.rawValue)")
    }

    /// Pause an active work block.
    public func pauseBlock(id: String) throws {
        try db.execute("""
            UPDATE work_block_records SET status = 'paused'
            WHERE work_block_id = ? AND status = 'active'
        """, params: [id])
        logger.info("Paused work block \(id)")
    }

    /// Resume a paused work block.
    public func resumeBlock(id: String) throws {
        try db.execute("""
            UPDATE work_block_records SET status = 'active'
            WHERE work_block_id = ? AND status = 'paused'
        """, params: [id])
        logger.info("Resumed work block \(id)")
    }

    /// Mark a work block as reviewing (Finish & Review clicked).
    public func markReviewing(id: String) throws {
        try db.execute("""
            UPDATE work_block_records SET status = 'reviewing'
            WHERE work_block_id = ? AND status = 'active'
        """, params: [id])
    }

    /// Update file counts on an active work block.
    public func updateCounts(id: String, modifiedFiles: Int, newFiles: Int) throws {
        try db.execute("""
            UPDATE work_block_records
            SET modified_file_count = ?, new_file_count = ?
            WHERE work_block_id = ?
        """, params: ["\(modifiedFiles)", "\(newFiles)", id])
    }

    /// Get all work blocks for an agent, most recent first.
    public func allBlocks(for agent: TargetApp, limit: Int = 50) throws -> [WorkBlockRecord] {
        let rows = try db.queryAll("""
            SELECT * FROM work_block_records
            WHERE agent = ?
            ORDER BY started_at DESC
            LIMIT ?
        """, params: [agent.rawValue, "\(limit)"])
        return rows.compactMap { WorkBlockRecord(row: $0) }
    }

    /// Check if any agent has an active work block.
    public func anyActiveBlock() throws -> WorkBlockRecord? {
        let rows = try db.queryAll("""
            SELECT * FROM work_block_records
            WHERE status IN ('active', 'paused')
            ORDER BY started_at DESC LIMIT 1
        """)
        return rows.first.flatMap { WorkBlockRecord(row: $0) }
    }
}
