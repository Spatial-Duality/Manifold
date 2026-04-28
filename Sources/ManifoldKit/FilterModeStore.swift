// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// User preferences + grant-scoped overrides for filter mode.
///
/// Two responsibilities:
///   1. Mode preferences — global default + optional per-agent override.
///      Reads via `mode(for:)` walk per-agent first, fall back to global.
///   2. Override-and-share approvals — recorded when the user explicitly
///      approves sharing a file flagged in Block mode. Scoped to a single
///      grant; the row stays after the grant ends for audit but no longer
///      affects future grants.
///
/// The actual enforcement (turning these settings into allow/deny at file
/// read time) lives in `ManifoldBridge`. This store is the persistence
/// + UI-readable layer.
public actor FilterModeStore {
    public static let globalSentinel: String = "_global"

    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    // MARK: - Mode preferences

    /// Returns the effective filter mode for an agent: per-agent override
    /// if set, otherwise the global default, otherwise `.off`.
    public func mode(for agent: TargetApp) throws -> FilterMode {
        if let perAgent = try readMode(key: agent.rawValue) {
            return perAgent
        }
        return try readMode(key: Self.globalSentinel) ?? .off
    }

    /// Returns the global default filter mode (the one applied when an
    /// agent has no explicit override). Defaults to `.off`.
    public func globalMode() throws -> FilterMode {
        try readMode(key: Self.globalSentinel) ?? .off
    }

    /// Sets the global default filter mode.
    public func setGlobalMode(_ mode: FilterMode) throws {
        try writeMode(key: Self.globalSentinel, mode: mode)
    }

    /// Sets the per-agent filter mode. Pass `nil` to clear the override and
    /// fall back to the global default.
    public func setMode(_ mode: FilterMode?, for agent: TargetApp) throws {
        if let mode {
            try writeMode(key: agent.rawValue, mode: mode)
        } else {
            try db.execute(
                "DELETE FROM filter_mode_settings WHERE agent = ?",
                params: [agent.rawValue]
            )
        }
    }

    // MARK: - Override-and-share

    /// Records an explicit user approval to share a flagged file with an
    /// agent for the duration of a single grant. Idempotent: re-approving
    /// the same (grant, agent, source, path) updates the timestamp.
    public func addOverride(_ override: FilterModeOverrideRecord) throws {
        try db.execute(
            """
            INSERT OR REPLACE INTO filter_mode_overrides (
                grant_id, agent, source_id, relative_path, approved_at
            ) VALUES (?, ?, ?, ?, ?)
            """,
            params: [
                override.grantID,
                override.agent.rawValue,
                override.sourceID,
                override.relativePath,
                override.approvedAt,
            ]
        )
    }

    /// Records overrides for many files in one transaction. Used by the
    /// bulk override-and-share sheet.
    public func addOverrides(_ overrides: [FilterModeOverrideRecord]) throws {
        guard !overrides.isEmpty else { return }
        try db.transaction {
            for override in overrides {
                try db.execute(
                    """
                    INSERT OR REPLACE INTO filter_mode_overrides (
                        grant_id, agent, source_id, relative_path, approved_at
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    params: [
                        override.grantID,
                        override.agent.rawValue,
                        override.sourceID,
                        override.relativePath,
                        override.approvedAt,
                    ]
                )
            }
        }
    }

    /// True iff the user has approved sharing this file in this grant.
    public func hasOverride(
        grantID: String,
        agent: TargetApp,
        sourceID: String,
        relativePath: String
    ) throws -> Bool {
        let rows = try db.queryAll(
            """
            SELECT 1 FROM filter_mode_overrides
            WHERE grant_id = ? AND agent = ? AND source_id = ? AND relative_path = ?
            LIMIT 1
            """,
            params: [grantID, agent.rawValue, sourceID, relativePath]
        )
        return !rows.isEmpty
    }

    /// All overrides recorded for a grant. Used by the audit / inspector
    /// surfaces to render "you overrode N flagged files in this session".
    public func overrides(grantID: String) throws -> [FilterModeOverrideRecord] {
        let rows = try db.queryAll(
            """
            SELECT grant_id, agent, source_id, relative_path, approved_at
            FROM filter_mode_overrides
            WHERE grant_id = ?
            ORDER BY approved_at DESC
            """,
            params: [grantID]
        )
        return rows.compactMap { row in
            guard let grantID = row["grant_id"],
                  let agentRaw = row["agent"],
                  let agent = TargetApp(rawValue: agentRaw),
                  let sourceID = row["source_id"],
                  let relativePath = row["relative_path"],
                  let approvedAt = row["approved_at"] else {
                return nil
            }
            return FilterModeOverrideRecord(
                grantID: grantID,
                agent: agent,
                sourceID: sourceID,
                relativePath: relativePath,
                approvedAt: approvedAt
            )
        }
    }

    // MARK: - Internal

    private func readMode(key: String) throws -> FilterMode? {
        let rows = try db.queryAll(
            "SELECT mode FROM filter_mode_settings WHERE agent = ? LIMIT 1",
            params: [key]
        )
        guard let raw = rows.first?["mode"] else { return nil }
        return FilterMode(rawValue: raw)
    }

    private func writeMode(key: String, mode: FilterMode) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            """
            INSERT OR REPLACE INTO filter_mode_settings (agent, mode, updated_at)
            VALUES (?, ?, ?)
            """,
            params: [key, mode.rawValue, now]
        )
    }
}
