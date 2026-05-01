// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

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
                let now = ISO8601DateFormatter.shared.string(from: Date())
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
        try Self.repairCurrentSchema(db)
        return applied
    }

    /// Current schema version (highest applied migration).
    public func currentVersion() throws -> Int {
        let result = try db.queryScalar("SELECT MAX(version) FROM schema_migrations")
        return result.flatMap(Int.init) ?? 0
    }

    private static func repairCurrentSchema(_ db: DatabaseConnection) throws {
        try repairApprovalRequests(db)
        try repairFileVisibilityOverrides(db)
        try repairRuleRecords(db)
        try repairStandingWriteGrants(db)
        try repairRuntimeSettings(db)
        try repairGrants(db)
        try MemoryStore.ensureSchema(db)
    }

    private static func tableExists(_ db: DatabaseConnection, named table: String) throws -> Bool {
        precondition(isValidSQLIdentifier(table), "Invalid SQL table identifier: \(table)")
        return try !db.queryAll(
            "SELECT name FROM sqlite_master WHERE type='table' AND name = ? LIMIT 1",
            params: [table]
        ).isEmpty
    }

    private static func deleteRowsIfTableExists(
        _ db: DatabaseConnection,
        table: String,
        where whereClause: String? = nil,
        params: [String?] = []
    ) throws {
        precondition(isValidSQLIdentifier(table), "Invalid SQL table identifier: \(table)")
        guard try tableExists(db, named: table) else { return }
        if let whereClause {
            try db.execute("DELETE FROM \(table) WHERE \(whereClause)", params: params)
        } else {
            try db.execute("DELETE FROM \(table)")
        }
    }

    private static func upsertRuntimeSetting(_ db: DatabaseConnection, key: String, value: String) throws {
        try repairRuntimeSettings(db)
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            """
            INSERT INTO runtime_settings (key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """,
            params: [key, value, now]
        )
    }

    private static func repairGrants(_ db: DatabaseConnection) throws {
        let tables = try db.queryAll(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='grants'"
        )
        guard !tables.isEmpty else { return }
        let columns = try db.queryAll("PRAGMA table_info(grants)")
        let columnNames = Set(columns.compactMap { $0["name"] })
        if !columnNames.contains("request_detail_level") {
            try db.execute("ALTER TABLE grants ADD COLUMN request_detail_level TEXT")
        }
        if !columnNames.contains("memory_access_enabled") {
            try db.execute("ALTER TABLE grants ADD COLUMN memory_access_enabled INTEGER NOT NULL DEFAULT 0")
        }
    }

    private static func repairApprovalRequests(_ db: DatabaseConnection) throws {
        let tables = try db.queryAll(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='approval_requests'"
        )
        guard !tables.isEmpty else { return }

        let columns = try db.queryAll("PRAGMA table_info(approval_requests)")
        let columnNames = Set(columns.compactMap { $0["name"] })
        if !columnNames.contains("request_kind") {
            try db.execute("ALTER TABLE approval_requests ADD COLUMN request_kind TEXT NOT NULL DEFAULT 'standing_write'")
        }
        if !columnNames.contains("source_id") {
            try db.execute("ALTER TABLE approval_requests ADD COLUMN source_id TEXT")
        }
        if !columnNames.contains("mount_name") {
            try db.execute("ALTER TABLE approval_requests ADD COLUMN mount_name TEXT")
        }
        if !columnNames.contains("relative_path") {
            try db.execute("ALTER TABLE approval_requests ADD COLUMN relative_path TEXT")
        }
        if !columnNames.contains("context_json") {
            try db.execute("ALTER TABLE approval_requests ADD COLUMN context_json TEXT")
        }
        if !columnNames.contains("resolution_action") {
            try db.execute("ALTER TABLE approval_requests ADD COLUMN resolution_action TEXT")
        }
        try db.execute("CREATE INDEX IF NOT EXISTS idx_approval_requests_status ON approval_requests(status)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_approval_requests_source ON approval_requests(source_id)")
    }

    private static func repairRuntimeSettings(_ db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS runtime_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
    }

    private static func repairFileVisibilityOverrides(_ db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS file_visibility_overrides (
                agent TEXT NOT NULL,
                source_id TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                is_directory INTEGER NOT NULL DEFAULT 0,
                decision TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY(agent, source_id, relative_path, is_directory)
            )
        """)
        try db.execute(
            "CREATE INDEX IF NOT EXISTS idx_file_visibility_overrides_source ON file_visibility_overrides(source_id)"
        )
        try db.execute(
            "CREATE INDEX IF NOT EXISTS idx_file_visibility_overrides_agent ON file_visibility_overrides(agent)"
        )
    }

    /// Some users hit "no such table: standing_write_default_grants" when
    /// flipping the share checkbox: migration 21 was either skipped on
    /// their install or the table was dropped manually. Re-creating
    /// idempotently on every startup means setSourceScope no longer
    /// rolls back its optimistic mutation, so the checkbox actually
    /// stays unchecked.
    private static func repairStandingWriteGrants(_ db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS standing_write_default_grants (
                agent TEXT NOT NULL,
                source_id TEXT NOT NULL,
                created_at REAL NOT NULL,
                PRIMARY KEY(agent, source_id)
            )
        """)
        try db.execute(
            "CREATE INDEX IF NOT EXISTS idx_standing_write_default_grants_source ON standing_write_default_grants(source_id)"
        )
        try db.execute("""
            CREATE TABLE IF NOT EXISTS standing_write_once_grants (
                agent TEXT NOT NULL,
                source_id TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                created_at REAL NOT NULL,
                PRIMARY KEY(agent, source_id, relative_path)
            )
        """)
        try db.execute(
            "CREATE INDEX IF NOT EXISTS idx_standing_write_once_grants_source ON standing_write_once_grants(source_id)"
        )
    }

    private static func repairRuleRecords(_ db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS rule_records (
                rule_id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                explanation TEXT NOT NULL DEFAULT '',
                scope TEXT NOT NULL,
                action TEXT NOT NULL,
                matcher_json TEXT NOT NULL,
                agents_json TEXT NOT NULL DEFAULT '[]',
                window_json TEXT NOT NULL DEFAULT '{"kind":"always"}',
                source TEXT NOT NULL DEFAULT 'user',
                enabled INTEGER NOT NULL DEFAULT 1,
                order_index INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                last_matched_at TEXT,
                match_count INTEGER NOT NULL DEFAULT 0
            )
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_rule_records_scope ON rule_records(scope)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_rule_records_source ON rule_records(source)")
        try db.execute(
            "CREATE INDEX IF NOT EXISTS idx_rule_records_scope_enabled_order ON rule_records(scope, enabled, order_index)"
        )
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

        // v5: Add grant_id column to audit_log for direct grant filtering.
        // Previously grant_id was buried in freeform metadata JSON, requiring string-contains matching.
        Migration(version: 5, name: "audit_log_grant_id") { db in
            let tables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='audit_log'"
            )
            guard !tables.isEmpty else { return }
            let columns = try db.queryAll("PRAGMA table_info(audit_log)")
            let hasGrantID = columns.contains { $0["name"] == "grant_id" }
            if !hasGrantID {
                try db.execute("ALTER TABLE audit_log ADD COLUMN grant_id TEXT")
            }
            try db.execute("CREATE INDEX IF NOT EXISTS idx_audit_grant ON audit_log(grant_id)")
        },

        // v6: Email backup system — accounts, sync state, and extended email_messages columns.
        // Adds IMAP account management and incremental sync tracking.
        Migration(version: 6, name: "email_backup_system") { db in
            try db.execute("""
                CREATE TABLE IF NOT EXISTS email_accounts (
                    account_id TEXT PRIMARY KEY,
                    display_name TEXT NOT NULL,
                    provider_type TEXT NOT NULL,
                    server TEXT,
                    port INTEGER,
                    username TEXT,
                    auth_type TEXT NOT NULL DEFAULT 'password',
                    keychain_ref TEXT,
                    sync_enabled INTEGER DEFAULT 1,
                    sync_interval_seconds INTEGER DEFAULT 300,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)

            try db.execute("""
                CREATE TABLE IF NOT EXISTS email_sync_state (
                    account_id TEXT NOT NULL,
                    mailbox_name TEXT NOT NULL,
                    uid_validity INTEGER,
                    last_sync_uid INTEGER DEFAULT 0,
                    last_sync_at TEXT,
                    message_count INTEGER DEFAULT 0,
                    sync_status TEXT DEFAULT 'idle',
                    error_message TEXT,
                    PRIMARY KEY(account_id, mailbox_name),
                    FOREIGN KEY(account_id) REFERENCES email_accounts(account_id)
                )
            """)

            // Extend email_messages with account linkage and IMAP UID tracking.
            let columns = try db.queryAll("PRAGMA table_info(email_messages)")
            let columnNames = Set(columns.compactMap { $0["name"] })

            if !columnNames.contains("account_id") {
                try db.execute("ALTER TABLE email_messages ADD COLUMN account_id TEXT REFERENCES email_accounts(account_id)")
            }
            if !columnNames.contains("imap_uid") {
                try db.execute("ALTER TABLE email_messages ADD COLUMN imap_uid INTEGER")
            }
            if !columnNames.contains("synced_at") {
                try db.execute("ALTER TABLE email_messages ADD COLUMN synced_at TEXT")
            }

            try db.execute("CREATE INDEX IF NOT EXISTS idx_email_messages_account ON email_messages(account_id)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_email_messages_uid ON email_messages(account_id, imap_uid)")
        },

        // v7: Email attachments — extracted MIME parts stored in EmailBackupStore.
        Migration(version: 7, name: "email_attachments") { db in
            try db.execute("""
                CREATE TABLE IF NOT EXISTS email_attachments (
                    attachment_id TEXT PRIMARY KEY,
                    email_id TEXT NOT NULL,
                    filename TEXT NOT NULL,
                    mime_type TEXT NOT NULL,
                    size_bytes INTEGER NOT NULL DEFAULT 0,
                    content_hash TEXT NOT NULL,
                    content_id TEXT,
                    FOREIGN KEY(email_id) REFERENCES email_messages(email_id)
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_attachments_email ON email_attachments(email_id)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_attachments_hash ON email_attachments(content_hash)")

            // Add attachment_count to email_messages for fast display
            let columns = try db.queryAll("PRAGMA table_info(email_messages)")
            let columnNames = Set(columns.compactMap { $0["name"] })
            if !columnNames.contains("attachment_count") {
                try db.execute("ALTER TABLE email_messages ADD COLUMN attachment_count INTEGER DEFAULT 0")
            }
        },

        // v8: .eml file storage — add eml_path, size_bytes, and account_id to email_messages.
        // Replaces content_hash-based storage with direct .eml file references.
        // account_id mirrors the old `account` column with a FK to email_accounts.
        Migration(version: 8, name: "eml_file_storage") { db in
            let columns = try db.queryAll("PRAGMA table_info(email_messages)")
            let columnNames = Set(columns.compactMap { $0["name"] })

            if !columnNames.contains("eml_path") {
                try db.execute("ALTER TABLE email_messages ADD COLUMN eml_path TEXT")
            }
            if !columnNames.contains("size_bytes") {
                try db.execute("ALTER TABLE email_messages ADD COLUMN size_bytes INTEGER DEFAULT 0")
            }
            if !columnNames.contains("account_id") {
                try db.execute("ALTER TABLE email_messages ADD COLUMN account_id TEXT")
                // Backfill account_id from the legacy account column
                try db.execute("UPDATE email_messages SET account_id = account WHERE account_id IS NULL")
            }
        },

        // v9: Email UI rewrite — rich metadata, mailbox membership, persistent sharing,
        // IMAP folder tree, and smart mailboxes.
        Migration(version: 9, name: "email_ui_rewrite") { db in
            let columns = try db.queryAll("PRAGMA table_info(email_messages)")
            let columnNames = Set(columns.compactMap { $0["name"] })

            // New metadata columns on email_messages
            let newColumns: [(String, String)] = [
                ("sender_email", "TEXT"),
                ("sender_domain", "TEXT"),
                ("is_read", "INTEGER DEFAULT 0"),
                ("is_flagged", "INTEGER DEFAULT 0"),
                ("flag_color", "TEXT"),
                ("in_reply_to", "TEXT"),
                ("references_header", "TEXT"),
                ("content_type", "TEXT"),
                ("cc", "TEXT DEFAULT ''"),
                ("message_id_header", "TEXT"),
            ]
            // The migration array above is hardcoded by the migration author.
            // `name` must be a SQL identifier (validated); `type` is a SQL type
            // fragment that may include DEFAULT clauses, trusted because it
            // ships with the binary and is not user-controllable.
            for (name, type) in newColumns where !columnNames.contains(name) {
                precondition(isValidSQLIdentifier(name), "Migration v8 column name is not a valid SQL identifier: \(name)")
                try db.execute("ALTER TABLE email_messages ADD COLUMN \(name) \(type)")
            }

            // Backfill sender_email from sender column ("Name <email>" → "email")
            try db.execute("""
                UPDATE email_messages SET sender_email =
                    CASE
                        WHEN INSTR(sender, '<') > 0
                        THEN LOWER(TRIM(SUBSTR(sender, INSTR(sender, '<') + 1,
                             INSTR(sender, '>') - INSTR(sender, '<') - 1)))
                        ELSE LOWER(TRIM(sender))
                    END
                WHERE sender_email IS NULL AND sender IS NOT NULL AND sender != ''
            """)

            // Backfill sender_domain from sender_email
            try db.execute("""
                UPDATE email_messages SET sender_domain =
                    LOWER(SUBSTR(sender_email, INSTR(sender_email, '@') + 1))
                WHERE sender_domain IS NULL
                    AND sender_email IS NOT NULL
                    AND INSTR(sender_email, '@') > 0
            """)

            // Mailbox membership junction table (one message can appear in multiple folders)
            try db.execute("""
                CREATE TABLE IF NOT EXISTS email_mailbox_membership (
                    account_id TEXT NOT NULL,
                    mailbox TEXT NOT NULL,
                    imap_uid INTEGER NOT NULL,
                    email_id TEXT NOT NULL REFERENCES email_messages(email_id),
                    PRIMARY KEY(account_id, mailbox, imap_uid)
                )
            """)

            // Backfill membership from existing email_messages
            try db.execute("""
                INSERT OR IGNORE INTO email_mailbox_membership (account_id, mailbox, imap_uid, email_id)
                SELECT account_id, mailbox, imap_uid, email_id
                FROM email_messages
                WHERE account_id IS NOT NULL AND mailbox IS NOT NULL AND imap_uid IS NOT NULL
            """)

            // IMAP mailbox metadata (persisted folder tree from LIST command)
            try db.execute("""
                CREATE TABLE IF NOT EXISTS imap_mailboxes (
                    account_id TEXT NOT NULL,
                    mailbox_name TEXT NOT NULL,
                    delimiter TEXT,
                    flags TEXT,
                    is_selectable INTEGER DEFAULT 1,
                    parent_path TEXT,
                    sort_order INTEGER DEFAULT 0,
                    PRIMARY KEY(account_id, mailbox_name)
                )
            """)

            // Persistent email sharing (independent of grant lifecycle)
            try db.execute("""
                CREATE TABLE IF NOT EXISTS shared_emails (
                    share_id TEXT PRIMARY KEY,
                    email_id TEXT NOT NULL REFERENCES email_messages(email_id),
                    shared_at TEXT NOT NULL,
                    label TEXT,
                    UNIQUE(email_id)
                )
            """)

            // Smart mailboxes (virtual folders with rule-based filtering)
            try db.execute("""
                CREATE TABLE IF NOT EXISTS smart_mailboxes (
                    mailbox_id TEXT PRIMARY KEY,
                    display_name TEXT NOT NULL,
                    icon_name TEXT DEFAULT 'tray',
                    rules_json TEXT NOT NULL DEFAULT '[]',
                    sort_order INTEGER DEFAULT 0
                )
            """)

            // Indexes for common query patterns
            try db.execute("CREATE INDEX IF NOT EXISTS idx_email_messages_read ON email_messages(is_read)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_email_messages_flagged ON email_messages(is_flagged)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_email_messages_in_reply_to ON email_messages(in_reply_to)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_email_messages_received ON email_messages(received_at)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_email_messages_sender_domain ON email_messages(sender_domain)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_email_messages_sender_email ON email_messages(sender_email)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_membership_email ON email_mailbox_membership(email_id)")
        },

        // v10: Email backup state — viewed tracking, junk tagging, server deletion, FTS5 body search
        Migration(version: 10, name: "email_backup_state_and_fts5") { db in
            // New columns on email_messages
            try db.execute("ALTER TABLE email_messages ADD COLUMN local_is_viewed INTEGER DEFAULT 0")
            try db.execute("ALTER TABLE email_messages ADD COLUMN is_junk INTEGER DEFAULT 0")
            try db.execute("ALTER TABLE email_messages ADD COLUMN deleted_on_server_at TEXT")
            try db.execute("ALTER TABLE email_messages ADD COLUMN body_text TEXT")

            // EXPUNGE detection: per-membership missing tracking
            try db.execute("ALTER TABLE email_mailbox_membership ADD COLUMN missing_from TEXT")

            // FTS5 virtual table for body text search
            try db.execute("""
                CREATE VIRTUAL TABLE IF NOT EXISTS email_fts USING fts5(
                    email_id,
                    body_text,
                    content='email_messages',
                    content_rowid='rowid'
                )
            """)

            // Indexes for new query patterns
            try db.execute("CREATE INDEX IF NOT EXISTS idx_email_messages_junk ON email_messages(is_junk)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_email_messages_deleted ON email_messages(deleted_on_server_at)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_email_messages_viewed ON email_messages(local_is_viewed)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_membership_missing ON email_mailbox_membership(missing_from)")

            // Backfill is_junk from existing mailbox membership + folder type detection
            try db.execute("""
                UPDATE email_messages SET is_junk = 1
                WHERE email_id IN (
                    SELECT emm.email_id FROM email_mailbox_membership emm
                    JOIN imap_mailboxes im ON emm.account_id = im.account_id AND emm.mailbox = im.mailbox_name
                    WHERE im.flags LIKE '%Junk%' OR im.flags LIKE '%Spam%'
                       OR UPPER(im.mailbox_name) LIKE '%JUNK%' OR UPPER(im.mailbox_name) LIKE '%SPAM%'
                )
            """)

            // Auto-create preset "Shared with Cowork" smart mailbox
            try db.execute("""
                INSERT OR IGNORE INTO smart_mailboxes (mailbox_id, display_name, icon_name, rules_json, sort_order)
                VALUES ('preset-shared-cowork', 'Shared with Cowork', 'person.2.fill',
                        '{"match":"all","conditions":[{"field":"shared","op":"equals","value":"true"}]}', 0)
            """)

            logger.info("Migration 10: email backup state columns, FTS5 table, junk backfill, preset smart mailbox")
        },

        // v11: Domain preset wiring — store email sensitivity and summary framing on grants
        Migration(version: 11, name: "grant_domain_preset") { db in
            let columns = try db.queryAll("PRAGMA table_info(grants)")
            let columnNames = Set(columns.compactMap { $0["name"] })
            if !columnNames.contains("email_sensitivity") {
                try db.execute("ALTER TABLE grants ADD COLUMN email_sensitivity TEXT NOT NULL DEFAULT 'moderate'")
            }
            if !columnNames.contains("summary_framing") {
                try db.execute("ALTER TABLE grants ADD COLUMN summary_framing TEXT")
            }
            logger.info("Migration 11: grant email_sensitivity and summary_framing columns")
        },

        // v12: Explicit access selection — scoped files, selected emails, and reusable presets.
        Migration(version: 12, name: "explicit_access_selection") { db in
            let grantColumns = try db.queryAll("PRAGMA table_info(grants)")
            let grantColumnNames = Set(grantColumns.compactMap { $0["name"] })
            if !grantColumnNames.contains("explicit_selection") {
                try db.execute("ALTER TABLE grants ADD COLUMN explicit_selection INTEGER NOT NULL DEFAULT 0")
            }

            try db.execute("""
                CREATE TABLE IF NOT EXISTS grant_file_scopes (
                    grant_id TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    relative_path TEXT NOT NULL,
                    is_directory INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY(grant_id, source_id, relative_path),
                    FOREIGN KEY(grant_id) REFERENCES grants(grant_id),
                    FOREIGN KEY(source_id) REFERENCES sources(source_id)
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_grant_file_scopes_grant ON grant_file_scopes(grant_id)")

            try db.execute("""
                CREATE TABLE IF NOT EXISTS access_presets (
                    preset_id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)

            try db.execute("""
                CREATE TABLE IF NOT EXISTS access_preset_file_scopes (
                    preset_id TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    relative_path TEXT NOT NULL,
                    is_directory INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY(preset_id, source_id, relative_path),
                    FOREIGN KEY(preset_id) REFERENCES access_presets(preset_id),
                    FOREIGN KEY(source_id) REFERENCES sources(source_id)
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_preset_file_scopes_preset ON access_preset_file_scopes(preset_id)")

            try db.execute("""
                CREATE TABLE IF NOT EXISTS access_preset_emails (
                    preset_id TEXT NOT NULL,
                    email_id TEXT NOT NULL,
                    PRIMARY KEY(preset_id, email_id),
                    FOREIGN KEY(preset_id) REFERENCES access_presets(preset_id),
                    FOREIGN KEY(email_id) REFERENCES email_messages(email_id)
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_preset_emails_preset ON access_preset_emails(preset_id)")
            logger.info("Migration 12: explicit selection and access preset tables")
        },

        // v13: Session note policy and typed session note entries.
        Migration(version: 13, name: "session_note_policy") { db in
            let grantColumns = try db.queryAll("PRAGMA table_info(grants)")
            let grantColumnNames = Set(grantColumns.compactMap { $0["name"] })
            if !grantColumnNames.contains("note_capture_mode") {
                try db.execute("ALTER TABLE grants ADD COLUMN note_capture_mode TEXT NOT NULL DEFAULT 'off'")
            }

            let summaryColumns = try db.queryAll("PRAGMA table_info(session_summaries)")
            let summaryColumnNames = Set(summaryColumns.compactMap { $0["name"] })
            if !summaryColumnNames.contains("summary_kind") {
                try db.execute("ALTER TABLE session_summaries ADD COLUMN summary_kind TEXT NOT NULL DEFAULT 'summary'")
            }
            if !summaryColumnNames.contains("summary_origin") {
                try db.execute("ALTER TABLE session_summaries ADD COLUMN summary_origin TEXT NOT NULL DEFAULT 'system'")
            }

            try db.execute("CREATE INDEX IF NOT EXISTS idx_grants_note_capture_mode ON grants(note_capture_mode)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_session_summaries_kind ON session_summaries(grant_id, summary_kind, ended_at)")
            logger.info("Migration 13: session note policy and typed note metadata")
        },

        // v14: Standing access — agent access policies, temporary reveals, work block records.
        // Supports persistent per-agent access without session ceremony.
        Migration(version: 14, name: "standing_access") { db in
            try db.execute("""
                CREATE TABLE IF NOT EXISTS agent_access_policies (
                    policy_id TEXT PRIMARY KEY,
                    agent TEXT NOT NULL UNIQUE,
                    allowed_source_ids TEXT NOT NULL DEFAULT '[]',
                    allowed_email_domains TEXT NOT NULL DEFAULT '[]',
                    email_sensitivity TEXT NOT NULL DEFAULT 'moderate',
                    is_paused INTEGER NOT NULL DEFAULT 0,
                    has_completed_first_grant INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)
            try db.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_policies_agent ON agent_access_policies(agent)"
            )

            try db.execute("""
                CREATE TABLE IF NOT EXISTS temporary_reveals (
                    reveal_id TEXT PRIMARY KEY,
                    agent TEXT NOT NULL,
                    email_id TEXT NOT NULL,
                    work_block_id TEXT,
                    created_at TEXT NOT NULL
                )
            """)
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_reveals_agent ON temporary_reveals(agent)"
            )
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_reveals_workblock ON temporary_reveals(work_block_id)"
            )

            try db.execute("""
                CREATE TABLE IF NOT EXISTS work_block_records (
                    work_block_id TEXT PRIMARY KEY,
                    agent TEXT NOT NULL,
                    grant_id TEXT NOT NULL,
                    source_ids TEXT NOT NULL DEFAULT '[]',
                    started_at TEXT NOT NULL,
                    ended_at TEXT,
                    status TEXT NOT NULL DEFAULT 'active',
                    modified_file_count INTEGER NOT NULL DEFAULT 0,
                    new_file_count INTEGER NOT NULL DEFAULT 0,
                    FOREIGN KEY(grant_id) REFERENCES grants(grant_id)
                )
            """)
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_workblocks_agent ON work_block_records(agent)"
            )
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_workblocks_status ON work_block_records(status)"
            )

            logger.info("Migration 14: standing access policies, temporary reveals, work block records")
        },

        // v15: Access request queue — agent-initiated access requests displayed in menu bar.
        Migration(version: 15, name: "access_request_queue") { db in
            try db.execute("""
                CREATE TABLE IF NOT EXISTS access_requests (
                    request_id TEXT PRIMARY KEY,
                    agent TEXT NOT NULL,
                    resource_path TEXT NOT NULL,
                    resource_name TEXT NOT NULL,
                    requested_at TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'pending'
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_requests_agent ON access_requests(agent)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_requests_status ON access_requests(status)")
            logger.info("Migration 15: access request queue")
        },

        // v16: Approval queue for tracked-write escalation from standing access.
        Migration(version: 16, name: "approval_requests") { db in
            try db.execute("""
                CREATE TABLE IF NOT EXISTS approval_requests (
                    id TEXT PRIMARY KEY,
                    connection_id TEXT NOT NULL,
                    agent TEXT NOT NULL,
                    path TEXT NOT NULL,
                    action TEXT NOT NULL,
                    request_kind TEXT NOT NULL DEFAULT 'standing_write',
                    source_id TEXT,
                    mount_name TEXT,
                    relative_path TEXT,
                    requested_at REAL NOT NULL,
                    status TEXT NOT NULL DEFAULT 'pending',
                    resolved_at REAL
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_approval_requests_status ON approval_requests(status)")
            logger.info("Migration 16: approval request queue")
        },

        // v17: Access decisions and exposure tracking for provenance.
        Migration(version: 17, name: "access_decisions_and_exposures") { db in
            try db.execute("""
                CREATE TABLE IF NOT EXISTS access_decisions (
                    id TEXT PRIMARY KEY,
                    connection_id TEXT NOT NULL,
                    agent TEXT NOT NULL,
                    tool_name TEXT NOT NULL,
                    resource_path TEXT,
                    action TEXT NOT NULL,
                    allowed INTEGER NOT NULL,
                    reason TEXT NOT NULL,
                    access_mode TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    policy_snapshot TEXT
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_ad_connection ON access_decisions(connection_id)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_ad_path ON access_decisions(resource_path)")

            try db.execute("""
                CREATE TABLE IF NOT EXISTS exposure_records (
                    id TEXT PRIMARY KEY,
                    connection_id TEXT NOT NULL,
                    agent TEXT NOT NULL,
                    tool_name TEXT NOT NULL,
                    resource_path TEXT,
                    byte_count INTEGER NOT NULL,
                    content_hash TEXT NOT NULL,
                    exposure_type TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    access_decision_id TEXT NOT NULL
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_er_connection ON exposure_records(connection_id)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_er_decision ON exposure_records(access_decision_id)")
            logger.info("Migration 17: access decisions and exposure records")
        },

        Migration(version: 18, name: "governance_identity_and_exposure_previews") { db in
            try db.execute("ALTER TABLE access_decisions ADD COLUMN client_identity TEXT")
            try db.execute("ALTER TABLE exposure_records ADD COLUMN payload_preview TEXT")
            try db.execute("ALTER TABLE exposure_records ADD COLUMN payload_preview_truncated INTEGER NOT NULL DEFAULT 0")
            try db.execute("ALTER TABLE exposure_records ADD COLUMN client_identity TEXT")
            logger.info("Migration 18: verification metadata and exposure previews")
        },

        Migration(version: 19, name: "access_recording_levels_and_intents") { db in
            let policyColumns = try db.queryAll("PRAGMA table_info(agent_access_policies)")
            let policyColumnNames = Set(policyColumns.compactMap { $0["name"] })
            if !policyColumnNames.contains("access_recording_level") {
                try db.execute("ALTER TABLE agent_access_policies ADD COLUMN access_recording_level TEXT NOT NULL DEFAULT 'lightweight'")
            }

            let accessDecisionColumns = try db.queryAll("PRAGMA table_info(access_decisions)")
            let accessDecisionColumnNames = Set(accessDecisionColumns.compactMap { $0["name"] })
            if !accessDecisionColumnNames.contains("intent_summary") {
                try db.execute("ALTER TABLE access_decisions ADD COLUMN intent_summary TEXT")
            }
            if !accessDecisionColumnNames.contains("intent_details") {
                try db.execute("ALTER TABLE access_decisions ADD COLUMN intent_details TEXT")
            }

            let exposureColumns = try db.queryAll("PRAGMA table_info(exposure_records)")
            let exposureColumnNames = Set(exposureColumns.compactMap { $0["name"] })
            if !exposureColumnNames.contains("intent_summary") {
                try db.execute("ALTER TABLE exposure_records ADD COLUMN intent_summary TEXT")
            }
            if !exposureColumnNames.contains("intent_details") {
                try db.execute("ALTER TABLE exposure_records ADD COLUMN intent_details TEXT")
            }

            logger.info("Migration 19: access recording levels and intent metadata")
        },

        Migration(version: 20, name: "email_rules_runtimeization") { db in
            let policyColumns = try db.queryAll("PRAGMA table_info(agent_access_policies)")
            let policyColumnNames = Set(policyColumns.compactMap { $0["name"] })
            if !policyColumnNames.contains("default_email_policy") {
                try db.execute("ALTER TABLE agent_access_policies ADD COLUMN default_email_policy TEXT NOT NULL DEFAULT 'allow_unless_blocked'")
                try db.execute(
                    """
                    UPDATE agent_access_policies
                    SET default_email_policy = CASE
                        WHEN agent = 'codex' THEN 'block_unless_allowed'
                        ELSE 'allow_unless_blocked'
                    END
                    """
                )
            }

            try db.execute("""
                CREATE TABLE IF NOT EXISTS email_shield_states (
                    agent TEXT NOT NULL,
                    shield_id TEXT NOT NULL,
                    is_enabled INTEGER NOT NULL DEFAULT 1,
                    updated_at TEXT NOT NULL,
                    PRIMARY KEY(agent, shield_id)
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_email_shield_states_agent ON email_shield_states(agent)")

            try db.execute("""
                CREATE TABLE IF NOT EXISTS email_domain_rules (
                    rule_id TEXT PRIMARY KEY,
                    agent TEXT NOT NULL,
                    domain TEXT NOT NULL,
                    action TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)
            try db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_email_domain_rules_agent_domain ON email_domain_rules(agent, domain)")

            try db.execute("""
                CREATE TABLE IF NOT EXISTS email_contact_rules (
                    rule_id TEXT PRIMARY KEY,
                    agent TEXT NOT NULL,
                    display_name TEXT NOT NULL DEFAULT '',
                    email TEXT NOT NULL,
                    action TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)
            try db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_email_contact_rules_agent_email ON email_contact_rules(agent, email)")

            try db.execute("""
                CREATE TABLE IF NOT EXISTS email_keyword_rules (
                    rule_id TEXT PRIMARY KEY,
                    agent TEXT NOT NULL,
                    pattern TEXT NOT NULL,
                    match_location TEXT NOT NULL,
                    action TEXT NOT NULL,
                    is_regex INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)
            try db.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_email_keyword_rules_unique ON email_keyword_rules(agent, pattern, match_location, is_regex)"
            )

            let now = ISO8601DateFormatter.shared.string(from: Date())
            let policies = try db.queryAll("SELECT agent, allowed_email_domains FROM agent_access_policies")
            for row in policies {
                guard let agent = row["agent"],
                      let domainsJSON = row["allowed_email_domains"],
                      let data = domainsJSON.data(using: .utf8),
                      let domains = try? JSONDecoder().decode([String].self, from: data) else {
                    continue
                }
                for domain in Set(domains.map { $0.lowercased() }) where !domain.isEmpty {
                    let ruleID = "email-domain-migrated-\(agent)-\(domain.replacingOccurrences(of: ".", with: "-"))"
                    try db.execute(
                        """
                        INSERT OR IGNORE INTO email_domain_rules (
                            rule_id, agent, domain, action, created_at, updated_at
                        ) VALUES (?, ?, ?, 'allow', ?, ?)
                        """,
                        params: [ruleID, agent, domain, now, now]
                    )
                }
            }

            for agent in ["cowork", "codex"] {
                for shield in EmailShieldCatalog.defaults(enabledByDefault: true) {
                    try db.execute(
                        """
                        INSERT OR IGNORE INTO email_shield_states (agent, shield_id, is_enabled, updated_at)
                        VALUES (?, ?, ?, ?)
                        """,
                        params: [agent, shield.shieldID, shield.isEnabled ? "1" : "0", now]
                    )
                }
            }

            logger.info("Migration 20: runtime-owned email rule tables and defaults")
        },

        Migration(version: 21, name: "standing_write_approval_runtimeization") { db in
            let approvalTables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='approval_requests'"
            )
            if !approvalTables.isEmpty {
                let approvalColumns = try db.queryAll("PRAGMA table_info(approval_requests)")
                let approvalColumnNames = Set(approvalColumns.compactMap { $0["name"] })
                if !approvalColumnNames.contains("request_kind") {
                    try db.execute("ALTER TABLE approval_requests ADD COLUMN request_kind TEXT NOT NULL DEFAULT 'standing_write'")
                }
                if !approvalColumnNames.contains("source_id") {
                    try db.execute("ALTER TABLE approval_requests ADD COLUMN source_id TEXT")
                }
                if !approvalColumnNames.contains("mount_name") {
                    try db.execute("ALTER TABLE approval_requests ADD COLUMN mount_name TEXT")
                }
                if !approvalColumnNames.contains("relative_path") {
                    try db.execute("ALTER TABLE approval_requests ADD COLUMN relative_path TEXT")
                }
            }

            try db.execute("""
                CREATE TABLE IF NOT EXISTS standing_write_default_grants (
                    agent TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    PRIMARY KEY(agent, source_id)
                )
            """)
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_standing_write_default_grants_source ON standing_write_default_grants(source_id)"
            )

            try db.execute("""
                CREATE TABLE IF NOT EXISTS standing_write_once_grants (
                    agent TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    relative_path TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    PRIMARY KEY(agent, source_id, relative_path)
                )
            """)
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_standing_write_once_grants_source ON standing_write_once_grants(source_id)"
            )

            logger.info("Migration 21: standing write approval grants and richer request context")
        },

        Migration(version: 22, name: "file_visibility_overrides") { db in
            try db.execute("""
                CREATE TABLE IF NOT EXISTS file_visibility_overrides (
                    agent TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    relative_path TEXT NOT NULL,
                    is_directory INTEGER NOT NULL DEFAULT 0,
                    decision TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    PRIMARY KEY(agent, source_id, relative_path, is_directory)
                )
            """)
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_file_visibility_overrides_source ON file_visibility_overrides(source_id)"
            )
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_file_visibility_overrides_agent ON file_visibility_overrides(agent)"
            )

            logger.info("Migration 22: persisted file visibility overrides")
        },

        // v23: Unified rule_records table — foundation for the cross-scope rules engine
        // (files, emails, agent behavior). Coexists with the existing v1 email rule tables
        // while the EmailPolicyEngine migration lands in a follow-up pass.
        Migration(version: 23, name: "unified_rule_records") { db in
            try db.execute("""
                CREATE TABLE IF NOT EXISTS rule_records (
                    rule_id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    explanation TEXT NOT NULL DEFAULT '',
                    scope TEXT NOT NULL,
                    action TEXT NOT NULL,
                    matcher_json TEXT NOT NULL,
                    agents_json TEXT NOT NULL DEFAULT '[]',
                    window_json TEXT NOT NULL DEFAULT '{"kind":"always"}',
                    source TEXT NOT NULL DEFAULT 'user',
                    enabled INTEGER NOT NULL DEFAULT 1,
                    order_index INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    last_matched_at TEXT,
                    match_count INTEGER NOT NULL DEFAULT 0
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_rule_records_scope ON rule_records(scope)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_rule_records_source ON rule_records(source)")
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_rule_records_scope_enabled_order ON rule_records(scope, enabled, order_index)"
            )
            logger.info("Migration 23: unified rule_records table")
        },

        Migration(version: 24, name: "privacy_preflight_foundation") { db in
            let approvalTables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='approval_requests'"
            )
            if !approvalTables.isEmpty {
                let approvalColumns = try db.queryAll("PRAGMA table_info(approval_requests)")
                let approvalColumnNames = Set(approvalColumns.compactMap { $0["name"] })
                if !approvalColumnNames.contains("context_json") {
                    try db.execute("ALTER TABLE approval_requests ADD COLUMN context_json TEXT")
                }
                if !approvalColumnNames.contains("resolution_action") {
                    try db.execute("ALTER TABLE approval_requests ADD COLUMN resolution_action TEXT")
                }
            }

            try db.execute("""
                CREATE TABLE IF NOT EXISTS privacy_preflight_settings (
                    id TEXT PRIMARY KEY,
                    is_enabled INTEGER NOT NULL DEFAULT 0,
                    selected_backend TEXT NOT NULL DEFAULT 'rules_only',
                    install_state TEXT NOT NULL DEFAULT 'not_installed',
                    model_version TEXT,
                    storage_path TEXT,
                    installed_at TEXT,
                    cache_enabled INTEGER NOT NULL DEFAULT 1,
                    unload_on_memory_pressure INTEGER NOT NULL DEFAULT 1,
                    updated_at TEXT NOT NULL
                )
            """)

            try db.execute("""
                CREATE TABLE IF NOT EXISTS agent_privacy_policies (
                    policy_id TEXT PRIMARY KEY,
                    agent TEXT NOT NULL UNIQUE,
                    text_handling TEXT NOT NULL DEFAULT 'redact',
                    code_handling TEXT NOT NULL DEFAULT 'ask',
                    secret_handling TEXT NOT NULL DEFAULT 'block',
                    enabled_categories_json TEXT NOT NULL DEFAULT '[]',
                    updated_at TEXT NOT NULL
                )
            """)
            try db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_privacy_policies_agent ON agent_privacy_policies(agent)")

            try db.execute("""
                CREATE TABLE IF NOT EXISTS privacy_scan_cache (
                    input_hash TEXT NOT NULL,
                    backend TEXT NOT NULL,
                    model_version TEXT NOT NULL,
                    operating_point TEXT NOT NULL,
                    category_set_json TEXT NOT NULL,
                    content_kind TEXT NOT NULL,
                    spans_json TEXT NOT NULL,
                    redacted_text TEXT NOT NULL,
                    findings_summary TEXT NOT NULL,
                    elapsed_ms INTEGER NOT NULL DEFAULT 0,
                    cached_at TEXT NOT NULL,
                    PRIMARY KEY(input_hash, backend, model_version, operating_point, category_set_json, content_kind)
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_privacy_scan_cache_cached_at ON privacy_scan_cache(cached_at)")

            try db.execute("""
                CREATE TABLE IF NOT EXISTS privacy_scan_events (
                    id TEXT PRIMARY KEY,
                    access_decision_id TEXT NOT NULL,
                    agent TEXT NOT NULL,
                    tool_name TEXT NOT NULL,
                    resource_path TEXT,
                    backend TEXT NOT NULL,
                    model_version TEXT NOT NULL,
                    content_kind TEXT NOT NULL,
                    input_hash TEXT NOT NULL,
                    delivered_hash TEXT,
                    outcome TEXT NOT NULL,
                    findings_summary TEXT NOT NULL,
                    findings_count INTEGER NOT NULL DEFAULT 0,
                    matched_categories_json TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_privacy_scan_events_decision ON privacy_scan_events(access_decision_id)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_privacy_scan_events_path ON privacy_scan_events(resource_path)")

            try db.execute("""
                CREATE TABLE IF NOT EXISTS privacy_approval_overrides (
                    id TEXT PRIMARY KEY,
                    agent TEXT NOT NULL,
                    resource_key TEXT NOT NULL,
                    input_hash TEXT NOT NULL,
                    content_kind TEXT NOT NULL,
                    decision TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
            """)
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_privacy_approval_overrides_lookup ON privacy_approval_overrides(agent, resource_key, input_hash, content_kind)"
            )

            logger.info("Migration 24: privacy preflight settings, cache, and approval state")
        },

        Migration(version: 25, name: "privacy_index_foundation") { db in
            try db.execute("""
                CREATE TABLE IF NOT EXISTS privacy_identity_registry (
                    identity_id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    value_ciphertext TEXT NOT NULL,
                    normalized_hash TEXT NOT NULL,
                    matching_mode TEXT NOT NULL DEFAULT 'exact',
                    is_enabled INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)
            try db.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_privacy_identity_registry_kind_hash ON privacy_identity_registry(kind, normalized_hash)"
            )

            try db.execute("""
                CREATE TABLE IF NOT EXISTS privacy_identity_suggestions (
                    suggestion_id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    value_ciphertext TEXT NOT NULL,
                    normalized_hash TEXT NOT NULL,
                    source_kind TEXT NOT NULL,
                    source_ref TEXT,
                    confidence REAL NOT NULL,
                    status TEXT NOT NULL DEFAULT 'pending',
                    created_at TEXT NOT NULL,
                    reviewed_at TEXT
                )
            """)
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_privacy_identity_suggestions_status_kind ON privacy_identity_suggestions(status, kind)"
            )

            try db.execute("""
                CREATE TABLE IF NOT EXISTS privacy_org_allowlist (
                    allow_id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    pattern TEXT NOT NULL,
                    match_mode TEXT NOT NULL DEFAULT 'exact',
                    source TEXT NOT NULL DEFAULT 'user',
                    is_enabled INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)
            try db.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_privacy_org_allowlist_kind_pattern ON privacy_org_allowlist(kind, pattern)"
            )

            try db.execute("""
                CREATE TABLE IF NOT EXISTS privacy_content_index (
                    content_id TEXT PRIMARY KEY,
                    subject_kind TEXT NOT NULL,
                    source_id TEXT,
                    relative_path TEXT,
                    email_id TEXT,
                    attachment_id TEXT,
                    parent_content_id TEXT,
                    display_name TEXT NOT NULL,
                    mime_type TEXT,
                    extractor TEXT,
                    extract_status TEXT NOT NULL,
                    scan_status TEXT NOT NULL,
                    content_hash TEXT,
                    backend TEXT,
                    model_version TEXT,
                    contains_sensitive INTEGER NOT NULL DEFAULT 0,
                    contains_my_info INTEGER NOT NULL DEFAULT 0,
                    contains_third_party_private INTEGER NOT NULL DEFAULT 0,
                    contains_secret INTEGER NOT NULL DEFAULT 0,
                    contains_org_only INTEGER NOT NULL DEFAULT 0,
                    severity TEXT NOT NULL DEFAULT 'none',
                    matched_categories_json TEXT NOT NULL DEFAULT '[]',
                    matched_identity_ids_json TEXT NOT NULL DEFAULT '[]',
                    matched_allow_ids_json TEXT NOT NULL DEFAULT '[]',
                    redacted_preview TEXT,
                    findings_summary TEXT NOT NULL DEFAULT '',
                    span_count INTEGER NOT NULL DEFAULT 0,
                    last_scanned_at TEXT,
                    updated_at TEXT NOT NULL,
                    last_error TEXT
                )
            """)
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_privacy_content_index_subject_source_path ON privacy_content_index(subject_kind, source_id, relative_path)"
            )
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_privacy_content_index_subject_email ON privacy_content_index(subject_kind, email_id)"
            )
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_privacy_content_index_flags ON privacy_content_index(contains_my_info, contains_secret, severity)"
            )

            try db.execute("""
                CREATE TABLE IF NOT EXISTS privacy_detected_spans (
                    span_id TEXT PRIMARY KEY,
                    content_id TEXT NOT NULL,
                    category TEXT NOT NULL,
                    start_utf16 INTEGER NOT NULL,
                    end_utf16 INTEGER NOT NULL,
                    confidence REAL,
                    source TEXT NOT NULL,
                    placeholder TEXT,
                    text_hash TEXT,
                    created_at TEXT NOT NULL
                )
            """)
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_privacy_detected_spans_content_category ON privacy_detected_spans(content_id, category)"
            )

            try db.execute("""
                CREATE TABLE IF NOT EXISTS privacy_index_jobs (
                    job_id TEXT PRIMARY KEY,
                    content_id TEXT NOT NULL,
                    reason TEXT NOT NULL,
                    priority INTEGER NOT NULL,
                    status TEXT NOT NULL,
                    attempt_count INTEGER NOT NULL DEFAULT 0,
                    scheduled_at TEXT NOT NULL,
                    started_at TEXT,
                    finished_at TEXT,
                    last_error TEXT
                )
            """)
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_privacy_index_jobs_status_priority_scheduled ON privacy_index_jobs(status, priority, scheduled_at)"
            )

            logger.info("Migration 25: privacy indexing tables")
        },

        Migration(version: 26, name: "per_agent_shared_emails") { db in
            let hasSharedEmails = try !db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='shared_emails'"
            ).isEmpty

            try db.execute("""
                CREATE TABLE IF NOT EXISTS shared_emails_v26 (
                    share_id TEXT PRIMARY KEY,
                    agent TEXT NOT NULL DEFAULT 'cowork',
                    email_id TEXT NOT NULL REFERENCES email_messages(email_id),
                    shared_at TEXT NOT NULL,
                    label TEXT,
                    UNIQUE(agent, email_id)
                )
            """)

            if hasSharedEmails {
                try db.execute("""
                    INSERT OR IGNORE INTO shared_emails_v26 (share_id, agent, email_id, shared_at, label)
                    SELECT share_id, 'cowork', email_id, shared_at, label
                    FROM shared_emails
                """)
            }

            try db.execute("DROP TABLE IF EXISTS shared_emails")
            try db.execute("ALTER TABLE shared_emails_v26 RENAME TO shared_emails")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_shared_emails_agent ON shared_emails(agent)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_shared_emails_email ON shared_emails(email_id)")

            logger.info("Migration 26: shared emails are scoped per agent")
        },

        Migration(version: 27, name: "repair_rules_and_file_visibility_tables") { db in
            try Self.repairCurrentSchema(db)
            logger.info("Migration 27: repaired rules and file visibility tables")
        },

        Migration(version: 28, name: "personal_data_os_foundation") { db in
            try LedgerStore.ensureSchema(db)
            try ToolMetricsStore.ensureSchema(db)
            try MemoryStore.ensureSchema(db)
            try SkillStore.ensureSchema(db)
            try CapabilityHandleStore.ensureSchema(db)
            try ExecRunStore.ensureSchema(db)
            try KnowledgeGraphStore.ensureSchema(db)
            try FabricationFindingStore.ensureSchema(db)

            try db.execute("""
                CREATE TABLE IF NOT EXISTS value_handles (
                    handle_id TEXT PRIMARY KEY,
                    origin TEXT NOT NULL,
                    sensitivity TEXT NOT NULL,
                    trust_level TEXT NOT NULL,
                    allowed_sinks_json TEXT NOT NULL,
                    grant_id TEXT,
                    lineage_json TEXT NOT NULL,
                    created_at REAL NOT NULL
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_value_handles_grant ON value_handles(grant_id)")

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

            try db.execute("""
                CREATE TABLE IF NOT EXISTS knowledge_graph_nodes (
                    node_id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    label TEXT NOT NULL,
                    lineage_json TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_graph_nodes_kind ON knowledge_graph_nodes(kind)")

            try db.execute("""
                CREATE TABLE IF NOT EXISTS knowledge_graph_edges (
                    edge_id TEXT PRIMARY KEY,
                    from_node_id TEXT NOT NULL,
                    to_node_id TEXT NOT NULL,
                    relation TEXT NOT NULL,
                    lineage_json TEXT NOT NULL,
                    created_at REAL NOT NULL
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_graph_edges_from ON knowledge_graph_edges(from_node_id)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_graph_edges_to ON knowledge_graph_edges(to_node_id)")

            try db.execute("""
                CREATE TABLE IF NOT EXISTS fabrication_findings (
                    finding_id TEXT PRIMARY KEY,
                    session_id TEXT,
                    claim_text TEXT NOT NULL,
                    status TEXT NOT NULL,
                    evidence_json TEXT NOT NULL,
                    created_at REAL NOT NULL
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_fabrication_session ON fabrication_findings(session_id)")

            logger.info("Migration 28: personal data OS foundation")
        },

        Migration(version: 29, name: "contextual_retrieval_chunks") { db in
            try ArtifactIndex.ensureRetrievalSchema(db)
            logger.info("Migration 29: contextual retrieval chunks")
        },

        Migration(version: 30, name: "memory_settings_and_retention") { db in
            try MemoryStore.ensureSchema(db)
            logger.info("Migration 30: memory settings and derived-memory retention")
        },

        // v31: Named session templates. Adds optional target_app column to
        // access_presets so saved presets can be scoped to one agent and
        // reused as named-session starting points. NULL target_app means
        // the preset applies to any agent (legacy behavior preserved).
        //
        // Defensive against broken upgrade paths: if access_presets is
        // missing entirely (e.g., a database where v12's CREATE TABLE was
        // skipped), this migration is a no-op. A future repair migration
        // is responsible for rebuilding the table; this one only adapts
        // an already-present table.
        Migration(version: 31, name: "session_templates_target_app") { db in
            let tableExists = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='access_presets'"
            )
            guard !tableExists.isEmpty else {
                logger.info("Migration 31: access_presets table missing, skipping (no-op)")
                return
            }

            let columns = try db.queryAll("PRAGMA table_info(access_presets)")
            let columnNames = Set(columns.compactMap { $0["name"] })
            if !columnNames.contains("target_app") {
                try db.execute("ALTER TABLE access_presets ADD COLUMN target_app TEXT")
            }
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_presets_target_app ON access_presets(target_app)"
            )
            logger.info("Migration 31: named session templates (target_app on access_presets)")
        },

        // v32: Filter mode plumbing. Adds a per-agent settings row plus a
        // per-(grant, source, path) override table for "override and share"
        // approvals. Default mode is 'off' so existing flows are unaffected
        // until the UI surfaces a mode change.
        //
        // The runtime enforcement integration in ManifoldBridge.enforceFileReadRules
        // is intentionally deferred — it depends on a findings provider that
        // isn't yet wired in this lane. The data layer ships standalone so
        // the UI can read/write user preferences and the enforcement can
        // hook in as a separate compositing layer later.
        Migration(version: 32, name: "filter_mode_plumbing") { db in
            try db.execute("""
                CREATE TABLE IF NOT EXISTS filter_mode_settings (
                    -- 'agent' is either a TargetApp.rawValue ('cowork', 'codex') or
                    -- the literal '_global' for the default that applies when an
                    -- agent has no explicit override.
                    agent TEXT PRIMARY KEY,
                    mode TEXT NOT NULL DEFAULT 'off',
                    updated_at TEXT NOT NULL
                )
            """)

            try db.execute("""
                CREATE TABLE IF NOT EXISTS filter_mode_overrides (
                    grant_id TEXT NOT NULL,
                    agent TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    relative_path TEXT NOT NULL,
                    approved_at TEXT NOT NULL,
                    PRIMARY KEY(grant_id, agent, source_id, relative_path)
                )
            """)
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_filter_mode_overrides_grant ON filter_mode_overrides(grant_id)"
            )
            try db.execute(
                "CREATE INDEX IF NOT EXISTS idx_filter_mode_overrides_agent ON filter_mode_overrides(agent)"
            )
            logger.info("Migration 32: filter mode settings and override tables")
        },

        Migration(version: 33, name: "managed_privacy_runtime") { db in
            let settingsTables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='privacy_preflight_settings'"
            )
            if !settingsTables.isEmpty {
                try db.execute("""
                    UPDATE privacy_preflight_settings
                    SET selected_backend = 'mlx',
                        install_state = CASE
                            WHEN selected_backend IN ('official_cli', 'mlx') THEN 'download_required'
                            ELSE install_state
                        END,
                        model_version = CASE
                            WHEN selected_backend IN ('official_cli', 'mlx') THEN NULL
                            ELSE model_version
                        END,
                        installed_at = CASE
                            WHEN selected_backend IN ('official_cli', 'mlx') THEN NULL
                            ELSE installed_at
                        END
                    WHERE selected_backend IN ('official_cli', 'mlx')
                """)
            }

            let cacheTables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='privacy_scan_cache'"
            )
            if !cacheTables.isEmpty {
                try db.execute("DELETE FROM privacy_scan_cache WHERE backend IN ('official_cli', 'mlx')")
            }

            logger.info("Migration 33: migrated legacy privacy backends to managed privacy scanner")
        },

        Migration(version: 34, name: "mlx_mxfp8_privacy_runtime") { db in
            let settingsTables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='privacy_preflight_settings'"
            )
            if !settingsTables.isEmpty {
                try db.execute("""
                    UPDATE privacy_preflight_settings
                    SET selected_backend = 'mlx',
                        install_state = 'download_required',
                        model_version = NULL,
                        installed_at = NULL
                    WHERE selected_backend IN ('core_ml', 'official_cli')
                """)
            }

            let cacheTables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='privacy_scan_cache'"
            )
            if !cacheTables.isEmpty {
                try db.execute("DELETE FROM privacy_scan_cache WHERE backend IN ('core_ml', 'official_cli', 'mlx')")
            }

            let eventTables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='privacy_scan_events'"
            )
            if !eventTables.isEmpty {
                try db.execute("UPDATE privacy_scan_events SET backend = 'mlx' WHERE backend IN ('core_ml', 'official_cli')")
            }

            logger.info("Migration 34: migrated managed privacy scanner to MLX MXFP8")
        },

        // v35: Scrub orphan access records left behind by older builds where
        // `removeSource` only flipped status to 'removed' without cascading
        // into file_visibility_overrides or agent_access_policies. The
        // runtime's resolveAccess re-filters via activeSources() so orphans
        // were never an enforcement leak, but they polluted the matrix dot
        // indicator (which lights up for any source with overrides) and
        // would fire if a code path ever read policies without the status
        // filter.
        Migration(version: 35, name: "scrub_orphan_access_records") { db in
            // The migration requires both `sources` (created in v3) and
            // either `file_visibility_overrides` or `agent_access_policies`
            // to do anything useful. If the underlying tables are absent —
            // typically because an older migrator test seeded the
            // schema_migrations row without running the real migration —
            // there's nothing to scrub. Bail before issuing any DELETE.
            let sourceTables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='sources'"
            )
            guard !sourceTables.isEmpty else {
                logger.info("Migration 35: no sources table, skipping access scrub")
                return
            }

            // 1. Drop file visibility overrides that reference a source
            //    that's missing from `sources` or marked removed.
            let overridesTables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='file_visibility_overrides'"
            )
            if !overridesTables.isEmpty {
                try db.execute("""
                    DELETE FROM file_visibility_overrides
                    WHERE source_id NOT IN (
                        SELECT source_id FROM sources WHERE status IN ('idle', 'active', 'paused')
                    )
                """)
            }

            // 2. Walk every agent_access_policies row and prune its
            //    allowed_source_ids JSON of any entry that points at a
            //    missing or removed source.
            let policyTables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='agent_access_policies'"
            )
            guard !policyTables.isEmpty else {
                logger.info("Migration 35: no agent_access_policies table, skipping policy scrub")
                return
            }
            let liveSourceRows = try db.queryAll(
                "SELECT source_id FROM sources WHERE status IN ('idle', 'active', 'paused')"
            )
            let liveSourceIDs = Set(liveSourceRows.compactMap { $0["source_id"] })
            let policyRows = try db.queryAll(
                "SELECT policy_id, allowed_source_ids FROM agent_access_policies"
            )
            let now = ISO8601DateFormatter.shared.string(from: Date())
            var scrubbedRows = 0
            for row in policyRows {
                guard let policyID = row["policy_id"],
                      let allowedJSON = row["allowed_source_ids"],
                      let data = allowedJSON.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                    continue
                }
                let kept = decoded.filter { liveSourceIDs.contains($0) }
                guard kept.count != decoded.count else { continue }
                let encoded = (try? JSONEncoder().encode(kept.sorted())).flatMap {
                    String(data: $0, encoding: .utf8)
                } ?? "[]"
                try db.execute(
                    "UPDATE agent_access_policies SET allowed_source_ids = ?, updated_at = ? WHERE policy_id = ?",
                    params: [encoded, now, policyID]
                )
                scrubbedRows += 1
            }
            logger.info("Migration 35: scrubbed orphan access records (\(scrubbedRows) policy rows updated)")
        },

        // v36: Session-scoped request detail. This keeps MCP intent
        // requirements on the active grant instead of mutating the
        // persistent per-agent policy while a session is live.
        Migration(version: 36, name: "grant_request_detail_level") { db in
            try repairGrants(db)
            logger.info("Migration 36: grant request detail override")
        },

        // v37: Session-scoped file memory access. Memory is always saved,
        // but active grants must opt in before agents can query prior
        // memory for the selected files.
        Migration(version: 37, name: "grant_memory_access") { db in
            try repairGrants(db)
            logger.info("Migration 37: grant file memory access")
        },

        // v38: Production mail subsystem foundations. This keeps the
        // existing email_* surface intact while adding the credential,
        // archive-v2, private-index, sync-job, and audit tables needed by
        // the redesigned read-only mail pipeline.
        Migration(version: 38, name: "production_mail_foundations") { db in
            let accountTables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='email_accounts'"
            )
            guard !accountTables.isEmpty else {
                logger.info("Migration 38: no email_accounts table, skipping mail foundations")
                return
            }

            let accountColumns = try db.queryAll("PRAGMA table_info(email_accounts)")
            let accountColumnNames = Set(accountColumns.compactMap { $0["name"] })
            let accountAdditions: [(String, String)] = [
                ("credential_kind", "TEXT"),
                ("credential_keychain_service", "TEXT"),
                ("credential_keychain_account", "TEXT"),
                ("last_successful_sync_at", "TEXT"),
                ("auth_state", "TEXT NOT NULL DEFAULT 'valid'"),
                ("index_privacy_mode", "TEXT NOT NULL DEFAULT 'privateTokenIndex'"),
            ]
            for (name, type) in accountAdditions where !accountColumnNames.contains(name) {
                precondition(isValidSQLIdentifier(name), "Migration v38 column name is not valid: \(name)")
                try db.execute("ALTER TABLE email_accounts ADD COLUMN \(name) \(type)")
            }
            try db.execute("""
                UPDATE email_accounts
                SET credential_kind = CASE
                        WHEN auth_type = 'oauth2' THEN 'oauthTokenSet'
                        WHEN auth_type = 'app_password' THEN 'appPassword'
                        ELSE 'manualPassword'
                    END,
                    credential_keychain_service = COALESCE(credential_keychain_service, 'com.spatialduality.manifold.email'),
                    credential_keychain_account = COALESCE(credential_keychain_account, account_id),
                    index_privacy_mode = COALESCE(index_privacy_mode, 'privateTokenIndex')
                WHERE credential_kind IS NULL
                   OR credential_keychain_service IS NULL
                   OR credential_keychain_account IS NULL
                   OR index_privacy_mode IS NULL
            """)

            let messageTables = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='email_messages'"
            )
            if !messageTables.isEmpty {
                let messageColumns = try db.queryAll("PRAGMA table_info(email_messages)")
                let messageColumnNames = Set(messageColumns.compactMap { $0["name"] })
                let messageAdditions: [(String, String)] = [
                    ("canonical_blob_cid", "TEXT"),
                    ("header_blob_cid", "TEXT"),
                    ("rfc_message_id_hmac", "TEXT"),
                ]
                for (name, type) in messageAdditions where !messageColumnNames.contains(name) {
                    precondition(isValidSQLIdentifier(name), "Migration v38 column name is not valid: \(name)")
                    try db.execute("ALTER TABLE email_messages ADD COLUMN \(name) \(type)")
                }
            }

            try db.execute("""
                CREATE TABLE IF NOT EXISTS mail_blobs (
                    content_id TEXT PRIMARY KEY,
                    account_id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    manifest_id TEXT NOT NULL,
                    byte_count_plaintext INTEGER NOT NULL,
                    byte_count_ciphertext INTEGER NOT NULL,
                    created_at TEXT NOT NULL,
                    last_verified_at TEXT,
                    ref_count INTEGER NOT NULL DEFAULT 1,
                    FOREIGN KEY(account_id) REFERENCES email_accounts(account_id)
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_mail_blobs_account ON mail_blobs(account_id)")

            try db.execute("""
                CREATE TABLE IF NOT EXISTS mail_private_terms (
                    account_id TEXT NOT NULL,
                    term_hmac TEXT NOT NULL,
                    email_id TEXT NOT NULL,
                    field_mask INTEGER NOT NULL,
                    term_count INTEGER NOT NULL,
                    first_seen_position INTEGER,
                    PRIMARY KEY(account_id, term_hmac, email_id),
                    FOREIGN KEY(account_id) REFERENCES email_accounts(account_id),
                    FOREIGN KEY(email_id) REFERENCES email_messages(email_id)
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_mail_private_terms_lookup ON mail_private_terms(account_id, term_hmac)")

            try db.execute("""
                CREATE TABLE IF NOT EXISTS mail_sync_jobs (
                    id TEXT PRIMARY KEY,
                    account_id TEXT NOT NULL,
                    mailbox_name TEXT,
                    job_type TEXT NOT NULL,
                    state TEXT NOT NULL,
                    priority INTEGER NOT NULL,
                    cursor_json_ciphertext TEXT,
                    error_code TEXT,
                    error_redacted TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    FOREIGN KEY(account_id) REFERENCES email_accounts(account_id)
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_mail_sync_jobs_account_state ON mail_sync_jobs(account_id, state)")

            try db.execute("""
                CREATE TABLE IF NOT EXISTS mail_access_audit_events (
                    id TEXT PRIMARY KEY,
                    account_id TEXT,
                    email_id TEXT,
                    agent_id TEXT NOT NULL,
                    session_id TEXT NOT NULL,
                    access_kind TEXT NOT NULL,
                    policy_grant_id TEXT,
                    created_at TEXT NOT NULL,
                    details_redacted TEXT
                )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_mail_access_audit_agent ON mail_access_audit_events(agent_id, created_at)")

            logger.info("Migration 38: production mail subsystem foundations")
        },

        // v39: Fresh-start mail reset. The production mail subsystem now
        // treats archive-v2 as the only canonical storage path for newly
        // synced mail. This migration clears legacy mail rows, plaintext
        // search/index state, sync cursors, and archive bookkeeping so setup
        // starts from a clean baseline. Filesystem and Keychain cleanup is
        // performed by MailFreshStartReset at runtime using the account IDs
        // recorded here.
        Migration(version: 39, name: "mail_fresh_start_reset") { db in
            try repairRuntimeSettings(db)

            let emailAccountsExist = try tableExists(db, named: "email_accounts")
            let legacyAccountIDs: [String]
            if emailAccountsExist {
                legacyAccountIDs = try db.queryAll(
                    """
                    SELECT account_id FROM email_accounts
                    WHERE credential_kind IS NULL
                       OR credential_keychain_service IS NULL
                       OR credential_keychain_account IS NULL
                       OR NOT (
                            (
                                credential_kind IN ('appPassword', 'manualPassword')
                                AND credential_keychain_service = ?
                                AND credential_keychain_account LIKE 'mail-account:%'
                            )
                            OR (
                                credential_kind = 'oauthTokenSet'
                                AND credential_keychain_service = ?
                                AND credential_keychain_account LIKE 'mail-account:%'
                            )
                       )
                    """,
                    params: [
                        KeychainMailSecretStore.credentialService,
                        KeychainMailSecretStore.oauthService,
                    ]
                ).compactMap { $0["account_id"] }

                if !legacyAccountIDs.isEmpty,
                   let data = try? JSONEncoder().encode(legacyAccountIDs.sorted()),
                   let json = String(data: data, encoding: .utf8) {
                    try upsertRuntimeSetting(
                        db,
                        key: MailFreshStartReset.legacyAccountIDsKey,
                        value: json
                    )
                }
            } else {
                legacyAccountIDs = []
            }

            if try tableExists(db, named: "privacy_content_index") {
                let mailContentWhere = """
                    content_id IN (
                        SELECT content_id FROM privacy_content_index
                        WHERE email_id IS NOT NULL
                           OR attachment_id IS NOT NULL
                           OR subject_kind IN ('email_body', 'email_attachment')
                    )
                """
                try deleteRowsIfTableExists(db, table: "privacy_detected_spans", where: mailContentWhere)
                try deleteRowsIfTableExists(db, table: "privacy_index_jobs", where: mailContentWhere)
                try db.execute("""
                    DELETE FROM privacy_content_index
                    WHERE email_id IS NOT NULL
                       OR attachment_id IS NOT NULL
                       OR subject_kind IN ('email_body', 'email_attachment')
                """)
            }

            let emailMessagesExist = try tableExists(db, named: "email_messages")

            if try tableExists(db, named: "email_fts"), emailMessagesExist {
                do {
                    try db.execute("""
                        INSERT INTO email_fts(email_fts, rowid, email_id, body_text)
                        SELECT 'delete', rowid, email_id, COALESCE(body_text, '')
                        FROM email_messages
                        WHERE body_text IS NOT NULL
                    """)
                } catch {
                    logger.warning("Migration 39: email_fts delete sweep failed before reset: \(error.localizedDescription)")
                }
            }

            if emailMessagesExist {
                try deleteRowsIfTableExists(db, table: "email_attachments")
                try deleteRowsIfTableExists(db, table: "email_mailbox_membership")
                try deleteRowsIfTableExists(db, table: "grant_emails")
                try deleteRowsIfTableExists(db, table: "shared_emails")
                try deleteRowsIfTableExists(db, table: "temporary_reveals", where: "email_id IS NOT NULL")
                try deleteRowsIfTableExists(db, table: "access_preset_emails")
                try deleteRowsIfTableExists(db, table: "mail_private_terms")
            }
            try deleteRowsIfTableExists(db, table: "mail_sync_jobs")
            try deleteRowsIfTableExists(db, table: "mail_access_audit_events")
            try deleteRowsIfTableExists(db, table: "mail_blobs")
            try deleteRowsIfTableExists(db, table: "email_sync_state")
            try deleteRowsIfTableExists(db, table: "imap_mailboxes")
            if emailMessagesExist {
                try deleteRowsIfTableExists(db, table: "email_messages")
            }

            if try tableExists(db, named: "email_fts") {
                do {
                    try db.execute("INSERT INTO email_fts(email_fts) VALUES('rebuild')")
                } catch {
                    logger.warning("Migration 39: email_fts rebuild failed after reset: \(error.localizedDescription)")
                }
            }

            if emailAccountsExist {
                try db.execute(
                    """
                    DELETE FROM email_accounts
                    WHERE credential_kind IS NULL
                       OR credential_keychain_service IS NULL
                       OR credential_keychain_account IS NULL
                       OR NOT (
                            (
                                credential_kind IN ('appPassword', 'manualPassword')
                                AND credential_keychain_service = ?
                                AND credential_keychain_account LIKE 'mail-account:%'
                            )
                            OR (
                                credential_kind = 'oauthTokenSet'
                                AND credential_keychain_service = ?
                                AND credential_keychain_account LIKE 'mail-account:%'
                            )
                       )
                    """,
                    params: [
                        KeychainMailSecretStore.credentialService,
                        KeychainMailSecretStore.oauthService,
                    ]
                )

                let now = ISO8601DateFormatter.shared.string(from: Date())
                try db.execute("""
                    UPDATE email_accounts
                    SET last_successful_sync_at = NULL,
                        auth_state = 'valid',
                        updated_at = ?
                """, params: [now])
            }

            try upsertRuntimeSetting(
                db,
                key: MailFreshStartReset.appliedKey,
                value: ISO8601DateFormatter.shared.string(from: Date())
            )
            logger.info("Migration 39: mail fresh-start reset; legacy accounts recorded \(legacyAccountIDs.count)")
        },

        // v40: Extracted MIME attachments now have their own archive-v2 blob
        // reference. Keep MIME Content-ID separate from the encrypted blob CID
        // so agent/export paths can address the stored attachment object
        // without overloading message-internal MIME metadata.
        Migration(version: 40, name: "mail_attachment_archive_blob_reference") { db in
            guard try tableExists(db, named: "email_attachments") else { return }
            try addColumnIfMissing(
                db,
                table: "email_attachments",
                column: "attachment_blob_cid",
                sql: "ALTER TABLE email_attachments ADD COLUMN attachment_blob_cid TEXT"
            )
            try db.execute("""
                CREATE INDEX IF NOT EXISTS idx_attachments_blob_cid
                ON email_attachments(attachment_blob_cid)
            """)
        },
    ]
}
