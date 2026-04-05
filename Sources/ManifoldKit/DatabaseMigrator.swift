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

        // v3: Content boundary tables — sources, grants, grant_sources, email_messages,
        // grant_emails, promotions, session_summaries. These run alongside existing
        // workspaces/runs tables (old UI keeps working).
        Migration(version: 3, name: "content_boundary_tables") { db in
            try db.execute("""
                CREATE TABLE IF NOT EXISTS sources (
                    source_id TEXT PRIMARY KEY,
                    display_name TEXT NOT NULL,
                    original_root_path TEXT NOT NULL UNIQUE,
                    status TEXT NOT NULL DEFAULT 'idle',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)

            try db.execute("""
                CREATE TABLE IF NOT EXISTS grants (
                    grant_id TEXT PRIMARY KEY,
                    target_app TEXT NOT NULL,
                    profile_id TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'active',
                    started_at TEXT NOT NULL,
                    ended_at TEXT,
                    materialization_root TEXT NOT NULL,
                    inactivity_deadline TEXT,
                    refresh_of_grant_id TEXT,
                    FOREIGN KEY(refresh_of_grant_id) REFERENCES grants(grant_id)
                )
            """)
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_grants_status ON grants(status)"
            )
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_grants_target_profile ON grants(target_app, profile_id)"
            )

            try db.execute("""
                CREATE TABLE IF NOT EXISTS grant_sources (
                    grant_id TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    mount_name TEXT NOT NULL,
                    baseline_manifest_hash TEXT,
                    PRIMARY KEY(grant_id, source_id),
                    FOREIGN KEY(grant_id) REFERENCES grants(grant_id),
                    FOREIGN KEY(source_id) REFERENCES sources(source_id)
                )
            """)

            try db.execute("""
                CREATE TABLE IF NOT EXISTS email_messages (
                    email_id TEXT PRIMARY KEY,
                    account TEXT NOT NULL,
                    mailbox TEXT NOT NULL,
                    sender TEXT NOT NULL,
                    recipients TEXT NOT NULL DEFAULT '',
                    subject TEXT NOT NULL,
                    received_at TEXT NOT NULL,
                    content_hash TEXT,
                    preview TEXT,
                    classification_status TEXT NOT NULL DEFAULT 'pending',
                    hidden_reason TEXT
                )
            """)
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_emails_classification ON email_messages(classification_status)"
            )

            try db.execute("""
                CREATE TABLE IF NOT EXISTS grant_emails (
                    grant_id TEXT NOT NULL,
                    email_id TEXT NOT NULL,
                    materialized_path TEXT NOT NULL,
                    PRIMARY KEY(grant_id, email_id),
                    FOREIGN KEY(grant_id) REFERENCES grants(grant_id),
                    FOREIGN KEY(email_id) REFERENCES email_messages(email_id)
                )
            """)

            try db.execute("""
                CREATE TABLE IF NOT EXISTS promotions (
                    promotion_id TEXT PRIMARY KEY,
                    grant_id TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    relative_path TEXT NOT NULL,
                    result TEXT NOT NULL,
                    original_before_hash TEXT,
                    promoted_hash TEXT,
                    conflict_reason TEXT,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY(grant_id) REFERENCES grants(grant_id),
                    FOREIGN KEY(source_id) REFERENCES sources(source_id)
                )
            """)
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_promotions_grant ON promotions(grant_id)"
            )

            try db.execute("""
                CREATE TABLE IF NOT EXISTS session_summaries (
                    summary_id TEXT PRIMARY KEY,
                    grant_id TEXT NOT NULL,
                    target_app TEXT NOT NULL,
                    started_at TEXT NOT NULL,
                    ended_at TEXT NOT NULL,
                    summary_markdown TEXT NOT NULL,
                    summary_json_hash TEXT,
                    FOREIGN KEY(grant_id) REFERENCES grants(grant_id)
                )
            """)
        },

        // v4: Migrate existing workspaces into sources.
        // Each workspace becomes a source. The workspace_id maps to source_id,
        // root_path to original_root_path. Workspace status maps directly (idle, active, paused, removed).
        // Skips if sources table already has rows (idempotent).
        Migration(version: 4, name: "migrate_workspaces_to_sources") { db in
            let tables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='workspaces'"
            )
            guard !tables.isEmpty else { return }

            let existing = try db.queryScalar(
                "SELECT COUNT(*) FROM sources"
            )
            guard existing == "0" || existing == nil else { return }

            let workspaces = try db.queryAll(
                "SELECT * FROM workspaces ORDER BY created_at ASC"
            )
            for ws in workspaces {
                guard let wsID = ws["workspace_id"],
                      let rootPath = ws["root_path"],
                      let status = ws["status"],
                      let createdAt = ws["created_at"],
                      let updatedAt = ws["updated_at"] else { continue }
                let displayName = URL(fileURLWithPath: rootPath).lastPathComponent
                try db.execute("""
                    INSERT OR IGNORE INTO sources (source_id, display_name, original_root_path, status, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, params: [wsID, displayName, rootPath, status, createdAt, updatedAt])
            }
            if !workspaces.isEmpty {
                logger.info("Migrated \(workspaces.count) workspaces to sources")
            }
        },
    ]
}
