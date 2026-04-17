// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

/// Persists standing write approvals granted from the ledger queue.
/// `once` grants are exact-path and consumed on first successful write.
/// `default` grants allow reversible writes anywhere inside one shared source.
public actor StandingWriteApprovalStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    public func grantOnce(agent: TargetApp, sourceID: String, relativePath: String) throws {
        try db.execute(
            """
            INSERT OR REPLACE INTO standing_write_once_grants (
                agent, source_id, relative_path, created_at
            ) VALUES (?, ?, ?, ?)
            """,
            params: [
                agent.rawValue,
                sourceID,
                relativePath,
                String(Date().timeIntervalSince1970),
            ]
        )
    }

    public func consumeOnce(agent: TargetApp, sourceID: String, relativePath: String) throws -> Bool {
        let existing = try db.queryScalar(
            """
            SELECT COUNT(*) FROM standing_write_once_grants
            WHERE agent = ? AND source_id = ? AND relative_path = ?
            """,
            params: [agent.rawValue, sourceID, relativePath]
        )
        guard (Int(existing ?? "0") ?? 0) > 0 else {
            return false
        }

        try db.execute(
            """
            DELETE FROM standing_write_once_grants
            WHERE agent = ? AND source_id = ? AND relative_path = ?
            """,
            params: [agent.rawValue, sourceID, relativePath]
        )
        return true
    }

    public func grantDefault(agent: TargetApp, sourceID: String) throws {
        try db.execute(
            """
            INSERT OR REPLACE INTO standing_write_default_grants (
                agent, source_id, created_at
            ) VALUES (?, ?, ?)
            """,
            params: [
                agent.rawValue,
                sourceID,
                String(Date().timeIntervalSince1970),
            ]
        )
    }

    public func hasDefaultGrant(agent: TargetApp, sourceID: String) throws -> Bool {
        let count = try db.queryScalar(
            """
            SELECT COUNT(*) FROM standing_write_default_grants
            WHERE agent = ? AND source_id = ?
            """,
            params: [agent.rawValue, sourceID]
        )
        return (Int(count ?? "0") ?? 0) > 0
    }

    public func removeGrants(agent: TargetApp, sourceID: String) throws {
        try db.execute(
            "DELETE FROM standing_write_default_grants WHERE agent = ? AND source_id = ?",
            params: [agent.rawValue, sourceID]
        )
        try db.execute(
            "DELETE FROM standing_write_once_grants WHERE agent = ? AND source_id = ?",
            params: [agent.rawValue, sourceID]
        )
    }

    public func removeGrants(sourceID: String) throws {
        try db.execute(
            "DELETE FROM standing_write_default_grants WHERE source_id = ?",
            params: [sourceID]
        )
        try db.execute(
            "DELETE FROM standing_write_once_grants WHERE source_id = ?",
            params: [sourceID]
        )
    }
}
