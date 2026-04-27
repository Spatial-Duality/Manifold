// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import os

private let skillLogger = Logger(subsystem: "com.spatialduality.manifold", category: "skills")

public actor SkillStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) throws {
        self.db = db
        try Self.ensureSchema(db)
    }

    public static func ensureSchema(_ db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS skill_records (
                skill_id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                manifest_hash TEXT NOT NULL,
                manifest_json TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
        """)
        try db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_skill_name ON skill_records(name)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_skill_manifest_hash ON skill_records(manifest_hash)")
    }

    @discardableResult
    public func save(name: String, manifestJSON: String) throws -> SkillRecord {
        let now = Date().timeIntervalSince1970
        let record = SkillRecord(
            name: name,
            manifestHash: Self.sha256(manifestJSON),
            manifestJSON: manifestJSON,
            createdAt: now,
            updatedAt: now
        )
        try db.execute("""
            INSERT INTO skill_records (skill_id, name, manifest_hash, manifest_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(name) DO UPDATE SET
                manifest_hash = excluded.manifest_hash,
                manifest_json = excluded.manifest_json,
                updated_at = excluded.updated_at
        """, params: [
            record.skillID,
            record.name,
            record.manifestHash,
            record.manifestJSON,
            "\(record.createdAt)",
            "\(record.updatedAt)",
        ])
        return try skill(named: name) ?? record
    }

    public func list(limit: Int = 50) throws -> [SkillRecord] {
        let rows = try db.queryAll(
            "SELECT * FROM skill_records ORDER BY updated_at DESC LIMIT ?",
            params: ["\(limit)"]
        )
        return rows.compactMap(Self.record(from:))
    }

    public func skill(named name: String) throws -> SkillRecord? {
        let rows = try db.queryAll(
            "SELECT * FROM skill_records WHERE name = ? LIMIT 1",
            params: [name]
        )
        return rows.first.flatMap(Self.record(from:))
    }

    private static func record(from row: [String: String]) -> SkillRecord? {
        guard let skillID = row["skill_id"],
              let name = row["name"],
              let manifestHash = row["manifest_hash"],
              let manifestJSON = row["manifest_json"],
              let createdRaw = row["created_at"],
              let createdAt = Double(createdRaw),
              let updatedRaw = row["updated_at"],
              let updatedAt = Double(updatedRaw) else {
            skillLogger.warning("Failed to decode skill record")
            return nil
        }
        return SkillRecord(
            skillID: skillID,
            name: name,
            manifestHash: manifestHash,
            manifestJSON: manifestJSON,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
