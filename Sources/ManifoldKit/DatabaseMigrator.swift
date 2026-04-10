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
            for (name, type) in newColumns where !columnNames.contains(name) {
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
    ]
}
