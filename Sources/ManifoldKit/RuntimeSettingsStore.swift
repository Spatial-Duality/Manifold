// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum SessionAccessMode: String, CaseIterable, Codable, Sendable {
    /// Standing policy remains available when no named session is active.
    case defaultSession = "default_session"
    /// Governed MCP file/email access requires an active session gateway.
    case manualRequiresSession = "manual_requires_session"
}

public actor RuntimeSettingsStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    public func sessionAccessMode() throws -> SessionAccessMode {
        guard let raw = try db.queryScalar(
            "SELECT value FROM runtime_settings WHERE key = ? LIMIT 1",
            params: ["session_access_mode"]
        ) else {
            return .defaultSession
        }
        return SessionAccessMode(rawValue: raw) ?? .defaultSession
    }

    public func setSessionAccessMode(_ mode: SessionAccessMode) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            """
            INSERT INTO runtime_settings (key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """,
            params: ["session_access_mode", mode.rawValue, now]
        )
    }

    /// Read a generic boolean flag from `runtime_settings`. Returns `nil`
    /// when the key has never been set, so callers can distinguish
    /// "never seeded" from "explicitly false." Used by one-shot
    /// migration / seeding gates.
    public func flag(forKey key: String) throws -> Bool? {
        guard let raw = try db.queryScalar(
            "SELECT value FROM runtime_settings WHERE key = ? LIMIT 1",
            params: [key]
        ) else { return nil }
        return raw == "1" || raw.lowercased() == "true"
    }

    /// Persist a generic boolean flag in `runtime_settings`.
    public func setFlag(forKey key: String, value: Bool) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            """
            INSERT INTO runtime_settings (key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """,
            params: [key, value ? "1" : "0", now]
        )
    }
}
