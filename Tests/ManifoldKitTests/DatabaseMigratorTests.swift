import Testing
import Foundation
@testable import ManifoldKit

@Suite("Database Migrator")
struct DatabaseMigratorTests {
    func makeDB() throws -> (DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-migrator-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        return (db, tempDir)
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    @Test("Fresh database starts at version 0")
    func freshVersion() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        #expect(try migrator.currentVersion() == 0)
    }

    @Test("Migrate applies all migrations")
    func migrateAll() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        let applied = try migrator.migrate()
        #expect(applied >= 2, "At least baseline + session_id migrations")
        #expect(try migrator.currentVersion() >= 2)
    }

    @Test("Running migrate twice is idempotent")
    func idempotent() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        let first = try migrator.migrate()
        let second = try migrator.migrate()
        #expect(first >= 2)
        #expect(second == 0, "No migrations applied on second run")
    }

    @Test("Migration v2 adds session_id to existing audit_log")
    func upgradeExistingDB() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        // Create old-style audit_log without session_id
        try db.execute("""
            CREATE TABLE audit_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                run_id TEXT, workspace_id TEXT, agent TEXT,
                action TEXT NOT NULL, file_path TEXT,
                before_hash TEXT, after_hash TEXT, metadata TEXT
            )
        """)

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        // Verify session_id column exists
        let columns = try db.queryAll("PRAGMA table_info(audit_log)")
        let hasSessionID = columns.contains { $0["name"] == "session_id" }
        #expect(hasSessionID, "session_id column should be added by migration v2")
    }

    @Test("Migration tracking persists across instances")
    func persistent() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator1 = try DatabaseMigrator(db: db)
        try migrator1.migrate()
        let version1 = try migrator1.currentVersion()

        // New migrator instance on same DB
        let migrator2 = try DatabaseMigrator(db: db)
        #expect(try migrator2.currentVersion() == version1)
        #expect(try migrator2.migrate() == 0)
    }

    @Test("Migration v3 creates all content boundary tables")
    func contentBoundaryTables() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let expectedTables = ["sources", "grants", "grant_sources",
                              "email_messages", "grant_emails", "promotions",
                              "session_summaries"]
        for table in expectedTables {
            let rows = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='\(table)'"
            )
            #expect(!rows.isEmpty, "Table '\(table)' should exist after migration v3")
        }
    }

    @Test("Migration v3 tables have correct columns")
    func contentBoundaryColumns() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        // Spot-check key columns on each table
        let sourceCols = try db.queryAll("PRAGMA table_info(sources)")
        let sourceNames = Set(sourceCols.compactMap { $0["name"] })
        #expect(sourceNames.contains("source_id"))
        #expect(sourceNames.contains("original_root_path"))
        #expect(sourceNames.contains("status"))

        let grantCols = try db.queryAll("PRAGMA table_info(grants)")
        let grantNames = Set(grantCols.compactMap { $0["name"] })
        #expect(grantNames.contains("grant_id"))
        #expect(grantNames.contains("target_app"))
        #expect(grantNames.contains("materialization_root"))
        #expect(grantNames.contains("inactivity_deadline"))

        let promoCols = try db.queryAll("PRAGMA table_info(promotions)")
        let promoNames = Set(promoCols.compactMap { $0["name"] })
        #expect(promoNames.contains("promotion_id"))
        #expect(promoNames.contains("result"))
        #expect(promoNames.contains("conflict_reason"))
    }

    @Test("Migration v4 migrates workspaces to sources")
    func workspacesToSources() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        // Create old-style workspaces table with data
        try db.execute("""
            CREATE TABLE workspaces (
                workspace_id TEXT PRIMARY KEY,
                profile_id TEXT NOT NULL,
                root_path TEXT NOT NULL,
                agent TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'idle',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
        let now = ISO8601DateFormatter().string(from: Date())
        try db.execute("""
            INSERT INTO workspaces (workspace_id, profile_id, root_path, agent, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, params: ["ws-1", "profile-1", "/Users/test/Projects/MyApp", "cowork", "active", now, now])
        try db.execute("""
            INSERT INTO workspaces (workspace_id, profile_id, root_path, agent, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, params: ["ws-2", "profile-1", "/Users/test/Documents", "codex", "paused", now, now])

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        // Sources should contain migrated workspaces
        let sources = try db.queryAll("SELECT * FROM sources ORDER BY source_id")
        #expect(sources.count == 2)
        #expect(sources[0]["source_id"] == "ws-1")
        #expect(sources[0]["original_root_path"] == "/Users/test/Projects/MyApp")
        #expect(sources[0]["display_name"] == "MyApp")
        #expect(sources[0]["status"] == "active")
        #expect(sources[1]["source_id"] == "ws-2")
        #expect(sources[1]["display_name"] == "Documents")
        #expect(sources[1]["status"] == "paused")
    }

    @Test("Migration v4 is idempotent with existing sources")
    func workspacesMigrationIdempotent() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        // Pre-create sources table with existing data
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let now = ISO8601DateFormatter().string(from: Date())
        try db.execute("""
            INSERT INTO sources (source_id, display_name, original_root_path, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, params: ["src-existing", "Existing", "/existing/path", "idle", now, now])

        // Create workspaces table after initial migration (simulates edge case)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS workspaces (
                workspace_id TEXT PRIMARY KEY,
                profile_id TEXT NOT NULL,
                root_path TEXT NOT NULL,
                agent TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'idle',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
        try db.execute("""
            INSERT INTO workspaces (workspace_id, profile_id, root_path, agent, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, params: ["ws-new", "profile-1", "/new/path", "cowork", "idle", now, now])

        // Re-running migrate should skip v4 since sources already has rows
        let applied = try migrator.migrate()
        #expect(applied == 0)

        let sources = try db.queryAll("SELECT * FROM sources")
        #expect(sources.count == 1, "Should only have the pre-existing source, not the workspace")
    }

    @Test("Migration v12 creates explicit access selection schema")
    func explicitAccessSelectionSchema() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let grantColumns = try db.queryAll("PRAGMA table_info(grants)")
        let grantColumnNames = Set(grantColumns.compactMap { $0["name"] })
        #expect(grantColumnNames.contains("explicit_selection"))

        for table in [
            "grant_file_scopes",
            "access_presets",
            "access_preset_file_scopes",
            "access_preset_emails",
        ] {
            let rows = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='\(table)'"
            )
            #expect(!rows.isEmpty, "Table '\(table)' should exist after migration v12")
        }
    }

    @Test("Migration v13 adds session note policy columns")
    func sessionNotePolicySchema() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let grantColumns = try db.queryAll("PRAGMA table_info(grants)")
        let grantColumnNames = Set(grantColumns.compactMap { $0["name"] })
        #expect(grantColumnNames.contains("note_capture_mode"))

        let summaryColumns = try db.queryAll("PRAGMA table_info(session_summaries)")
        let summaryColumnNames = Set(summaryColumns.compactMap { $0["name"] })
        #expect(summaryColumnNames.contains("summary_kind"))
        #expect(summaryColumnNames.contains("summary_origin"))
    }

    @Test("Migration v18 adds exposure previews and client identity columns")
    func governanceSchema() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let decisionColumns = try db.queryAll("PRAGMA table_info(access_decisions)")
        let decisionColumnNames = Set(decisionColumns.compactMap { $0["name"] })
        #expect(decisionColumnNames.contains("client_identity"))

        let exposureColumns = try db.queryAll("PRAGMA table_info(exposure_records)")
        let exposureColumnNames = Set(exposureColumns.compactMap { $0["name"] })
        #expect(exposureColumnNames.contains("payload_preview"))
        #expect(exposureColumnNames.contains("payload_preview_truncated"))
        #expect(exposureColumnNames.contains("client_identity"))
    }

    @Test("Migration v19 adds access recording and intent columns")
    func accessRecordingSchema() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let policyColumns = try db.queryAll("PRAGMA table_info(agent_access_policies)")
        let policyColumnNames = Set(policyColumns.compactMap { $0["name"] })
        #expect(policyColumnNames.contains("access_recording_level"))

        let decisionColumns = try db.queryAll("PRAGMA table_info(access_decisions)")
        let decisionColumnNames = Set(decisionColumns.compactMap { $0["name"] })
        #expect(decisionColumnNames.contains("intent_summary"))
        #expect(decisionColumnNames.contains("intent_details"))

        let exposureColumns = try db.queryAll("PRAGMA table_info(exposure_records)")
        let exposureColumnNames = Set(exposureColumns.compactMap { $0["name"] })
        #expect(exposureColumnNames.contains("intent_summary"))
        #expect(exposureColumnNames.contains("intent_details"))
    }

    @Test("Migration v20 backfills runtime email rules from legacy allowed domains")
    func emailRulesRuntimeizationMigration() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        try db.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL
            )
        """)
        for version in 1 ... 19 {
            try db.execute(
                "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                params: ["\(version)", ISO8601DateFormatter.shared.string(from: Date())]
            )
        }

        try db.execute("""
            CREATE TABLE agent_access_policies (
                policy_id TEXT PRIMARY KEY,
                agent TEXT NOT NULL UNIQUE,
                allowed_source_ids TEXT NOT NULL DEFAULT '[]',
                allowed_email_domains TEXT NOT NULL DEFAULT '[]',
                email_sensitivity TEXT NOT NULL DEFAULT 'moderate',
                is_paused INTEGER NOT NULL DEFAULT 0,
                has_completed_first_grant INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                access_recording_level TEXT NOT NULL DEFAULT 'lightweight'
            )
        """)
        try db.execute("""
            CREATE TABLE access_decisions (
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
                policy_snapshot TEXT,
                client_identity TEXT,
                intent_summary TEXT,
                intent_details TEXT
            )
        """)
        try db.execute("""
            CREATE TABLE exposure_records (
                id TEXT PRIMARY KEY,
                connection_id TEXT NOT NULL,
                agent TEXT NOT NULL,
                tool_name TEXT NOT NULL,
                resource_path TEXT,
                byte_count INTEGER NOT NULL,
                content_hash TEXT NOT NULL,
                exposure_type TEXT NOT NULL,
                timestamp REAL NOT NULL,
                access_decision_id TEXT NOT NULL,
                payload_preview TEXT,
                payload_preview_truncated INTEGER NOT NULL DEFAULT 0,
                client_identity TEXT,
                intent_summary TEXT,
                intent_details TEXT
            )
        """)

        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            """
            INSERT INTO agent_access_policies
                (policy_id, agent, allowed_source_ids, allowed_email_domains, email_sensitivity, is_paused, has_completed_first_grant, created_at, updated_at, access_recording_level)
            VALUES
                (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            params: ["policy-cowork", "cowork", "[]", "[\"example.com\",\"alerts.example.com\"]", "moderate", "0", "0", now, now, "lightweight"]
        )

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let policyColumns = try db.queryAll("PRAGMA table_info(agent_access_policies)")
        let policyColumnNames = Set(policyColumns.compactMap { $0["name"] })
        #expect(policyColumnNames.contains("default_email_policy"))

        let rules = try db.queryAll("SELECT agent, domain, action FROM email_domain_rules ORDER BY domain ASC")
        #expect(rules.count == 2)
        #expect(rules.allSatisfy { $0["agent"] == "cowork" && $0["action"] == "allow" })
        #expect(rules.map { $0["domain"] ?? "" } == ["alerts.example.com", "example.com"])
    }
}
