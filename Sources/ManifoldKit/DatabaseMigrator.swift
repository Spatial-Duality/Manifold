import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "migration")

/// Versioned database migration system.
/// Migrations are numbered sequentially. Each runs exactly once, tracked in `schema_migrations`.
/// Run this BEFORE initializing stores — stores use CREATE TABLE IF NOT EXISTS and are safe
/// to run after migrations.
public struct DatabaseMigrator {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) throws {
        self.db = db
        try db.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL
            )
        """)
    }

    /// Run all pending migrations. Returns the number of migrations applied.
    @discardableResult
    public func migrate() throws -> Int {
        let current = try currentVersion()
        var applied = 0

        for migration in Self.migrations where migration.version > current {
            logger.info("Applying migration \(migration.version): \(migration.name)")
            try db.transaction {
                try migration.apply(db)
                let now = ISO8601DateFormatter().string(from: Date())
                try db.execute(
                    "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                    params: ["\(migration.version)", now]
                )
            }
            logger.info("Migration \(migration.version) applied")
            applied += 1
        }

        if applied > 0 {
            logger.info("Migrations complete. Schema at version \(Self.migrations.last?.version ?? 0)")
        }
        return applied
    }

    /// Current schema version (highest applied migration).
    public func currentVersion() throws -> Int {
        let result = try db.queryScalar("SELECT MAX(version) FROM schema_migrations")
        return result.flatMap(Int.init) ?? 0
    }

    // MARK: - Migration Definitions

    private struct Migration: Sendable {
        let version: Int
        let name: String
        let apply: @Sendable (DatabaseConnection) throws -> Void
    }

    private static let migrations: [Migration] = [
        // v1: Baseline schema. Tables already created by store init (CREATE TABLE IF NOT EXISTS).
        // This migration just marks the baseline as applied.
        Migration(version: 1, name: "baseline") { _ in
            // No-op. All tables are created by their respective store initializers.
        },

        // v2: Add session_id to audit_log for session replay grouping.
        // Previously an ad-hoc PRAGMA table_info check in AuditStore.init.
        // On fresh databases, audit_log may not exist yet (stores create tables after migration).
        // The column is now in AuditStore's CREATE TABLE, so this only matters for upgrades.
        Migration(version: 2, name: "audit_log_session_id") { db in
            let tables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='audit_log'"
            )
            guard !tables.isEmpty else { return }
            let columns = try db.queryAll("PRAGMA table_info(audit_log)")
            let hasSessionID = columns.contains { $0["name"] == "session_id" }
            if !hasSessionID {
                try db.execute("ALTER TABLE audit_log ADD COLUMN session_id TEXT")
            }
            try db.execute("CREATE INDEX IF NOT EXISTS idx_audit_session ON audit_log(session_id)")
        },
    ]
}
