// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let execRunLogger = Logger(subsystem: "com.spatialduality.manifold", category: "exec")

public actor ExecRunStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) throws {
        self.db = db
        try Self.ensureSchema(db)
    }

    public static func ensureSchema(_ db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS exec_runs (
                run_id TEXT PRIMARY KEY,
                status TEXT NOT NULL,
                reason TEXT NOT NULL,
                suggested_alternative TEXT,
                output_preview TEXT,
                created_at REAL NOT NULL
            )
        """)
    }

    @discardableResult
    public func save(result: ExecRunResult) throws -> ExecRunRecord {
        let record = ExecRunRecord(
            status: result.status,
            reason: result.reason,
            suggestedAlternative: result.suggestedAlternative,
            outputPreview: result.output.map { String($0.prefix(4_000)) }
        )
        try db.execute("""
            INSERT INTO exec_runs (
                run_id, status, reason, suggested_alternative, output_preview, created_at
            ) VALUES (?, ?, ?, ?, ?, ?)
        """, params: [
            record.runID,
            record.status,
            record.reason,
            record.suggestedAlternative,
            record.outputPreview,
            "\(record.createdAt)",
        ])
        return record
    }

    public func recent(limit: Int = 50) throws -> [ExecRunRecord] {
        let rows = try db.queryAll(
            "SELECT * FROM exec_runs ORDER BY created_at DESC LIMIT ?",
            params: ["\(max(1, min(limit, 500)))"]
        )
        return rows.compactMap(Self.record(from:))
    }

    private static func record(from row: [String: String]) -> ExecRunRecord? {
        guard let runID = row["run_id"],
              let status = row["status"],
              let reason = row["reason"],
              let createdRaw = row["created_at"],
              let createdAt = Double(createdRaw) else {
            execRunLogger.warning("Failed to decode exec run row")
            return nil
        }
        return ExecRunRecord(
            runID: runID,
            status: status,
            reason: reason,
            suggestedAlternative: row["suggested_alternative"]?.nilIfEmpty,
            outputPreview: row["output_preview"]?.nilIfEmpty,
            createdAt: createdAt
        )
    }
}
