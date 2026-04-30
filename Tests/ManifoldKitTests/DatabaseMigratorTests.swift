// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

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

    @Test("Migration v27 repairs missing rules table on upgraded databases")
    func repairsMissingRulesTableOnUpgradedDatabase() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        let now = ISO8601DateFormatter.shared.string(from: Date())
        for version in 1...26 {
            try db.execute(
                "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                params: ["\(version)", now]
            )
        }

        #expect(try db.queryAll("SELECT name FROM sqlite_master WHERE type='table' AND name='rule_records'").isEmpty)
        #expect(try db.queryAll("SELECT name FROM sqlite_master WHERE type='table' AND name='file_visibility_overrides'").isEmpty)

        let applied = try migrator.migrate()

        #expect(applied == 11)
        #expect(try migrator.currentVersion() == 37)
        #expect(!((try db.queryAll("SELECT name FROM sqlite_master WHERE type='table' AND name='rule_records'")).isEmpty))
        #expect(!((try db.queryAll("SELECT name FROM sqlite_master WHERE type='table' AND name='file_visibility_overrides'")).isEmpty))
    }

    @Test("Schema repair runs even when database is already current")
    func repairsMissingRulesTableOnCurrentDatabase() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        let now = ISO8601DateFormatter.shared.string(from: Date())
        for version in 1...37 {
            try db.execute(
                "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                params: ["\(version)", now]
            )
        }

        #expect(try migrator.currentVersion() == 37)
        #expect(try db.queryAll("SELECT name FROM sqlite_master WHERE type='table' AND name='rule_records'").isEmpty)
        #expect(try db.queryAll("SELECT name FROM sqlite_master WHERE type='table' AND name='file_visibility_overrides'").isEmpty)
        try db.execute("""
            CREATE TABLE approval_requests (
                id TEXT PRIMARY KEY,
                connection_id TEXT NOT NULL,
                agent TEXT NOT NULL,
                path TEXT NOT NULL,
                action TEXT NOT NULL,
                requested_at REAL NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                resolved_at REAL
            )
        """)

        let applied = try migrator.migrate()

        #expect(applied == 0)
        #expect(!((try db.queryAll("SELECT name FROM sqlite_master WHERE type='table' AND name='rule_records'")).isEmpty))
        #expect(!((try db.queryAll("SELECT name FROM sqlite_master WHERE type='table' AND name='file_visibility_overrides'")).isEmpty))
        let approvalColumns = Set(try db.queryAll("PRAGMA table_info(approval_requests)").compactMap { $0["name"] })
        #expect(approvalColumns.contains("source_id"))
        #expect(approvalColumns.contains("request_kind"))
        #expect(approvalColumns.contains("context_json"))
        #expect(!((try db.queryAll("SELECT name FROM sqlite_master WHERE type='table' AND name='runtime_settings'")).isEmpty))
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
        #expect(grantNames.contains("request_detail_level"))
        #expect(grantNames.contains("memory_access_enabled"))

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

    @Test("Migration v24 creates privacy preflight schema")
    func privacyPreflightSchema() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let approvalColumns = try db.queryAll("PRAGMA table_info(approval_requests)")
        let approvalNames = Set(approvalColumns.compactMap { $0["name"] })
        #expect(approvalNames.contains("context_json"))
        #expect(approvalNames.contains("resolution_action"))

        for table in [
            "privacy_preflight_settings",
            "agent_privacy_policies",
            "privacy_scan_cache",
            "privacy_scan_events",
            "privacy_approval_overrides",
        ] {
            let rows = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='\(table)'"
            )
            #expect(!rows.isEmpty, "Table '\(table)' should exist after migration v24")
        }
    }

    @Test("Migration v25 creates privacy index schema")
    func privacyIndexSchema() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        for table in [
            "privacy_identity_registry",
            "privacy_identity_suggestions",
            "privacy_org_allowlist",
            "privacy_content_index",
            "privacy_detected_spans",
            "privacy_index_jobs",
        ] {
            let rows = try db.queryAll(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='\(table)'"
            )
            #expect(!rows.isEmpty, "Table '\(table)' should exist after migration v25")
        }

        let contentIndexColumns = Set(
            try db.queryAll("PRAGMA table_info(privacy_content_index)").compactMap { $0["name"] }
        )
        #expect(contentIndexColumns.contains("contains_my_info"))
        #expect(contentIndexColumns.contains("contains_secret"))
        #expect(contentIndexColumns.contains("matched_categories_json"))
    }

    @Test("Migration v26 makes shared emails per-agent")
    func perAgentSharedEmailSchema() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let columns = Set(
            try db.queryAll("PRAGMA table_info(shared_emails)").compactMap { $0["name"] }
        )
        #expect(columns.contains("agent"))

        let uniqueIndexes = try db.queryAll("PRAGMA index_list(shared_emails)").filter { row in
            row["unique"] == "1"
        }
        let hasAgentEmailUniqueIndex = try uniqueIndexes.contains { row in
            guard let name = row["name"] else { return false }
            let indexedColumns = try db.queryAll("PRAGMA index_info(\(name))").compactMap { $0["name"] }
            return indexedColumns == ["agent", "email_id"]
        }
        #expect(hasAgentEmailUniqueIndex)
    }

    @Test("Migration v29 adds contextual retrieval chunk schema")
    func contextualRetrievalChunkSchema() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let chunkTable = try db.queryAll(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='artifact_chunks'"
        )
        let chunkSearchTable = try db.queryAll(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='artifact_chunk_search'"
        )
        let columns = Set(
            try db.queryAll("PRAGMA table_info(artifact_chunks)")
                .compactMap { $0["name"] }
        )

        #expect(!chunkTable.isEmpty)
        #expect(!chunkSearchTable.isEmpty)
        #expect(columns.contains("content_hash"))
        #expect(columns.contains("context"))
        #expect(columns.contains("line_start"))
        #expect(columns.contains("line_end"))
    }

    @Test("Migration v30 adds memory settings and retention columns")
    func memorySettingsAndRetentionSchema() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let settingsTable = try db.queryAll(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='memory_settings'"
        )
        let memoryColumns = Set(
            try db.queryAll("PRAGMA table_info(memory_items)")
                .compactMap { $0["name"] }
        )

        #expect(!settingsTable.isEmpty)
        #expect(memoryColumns.contains("origin"))
        #expect(memoryColumns.contains("expires_at"))
    }

    @Test("Migration v31 adds target_app column to access_presets")
    func sessionTemplatesTargetAppColumn() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let columns = Set(
            try db.queryAll("PRAGMA table_info(access_presets)")
                .compactMap { $0["name"] }
        )
        #expect(columns.contains("target_app"))

        let indexes = try db.queryAll(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_presets_target_app'"
        )
        #expect(!indexes.isEmpty)
    }

    @Test("Migration v31 is idempotent — re-running does not fail")
    func sessionTemplatesIdempotent() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let firstMigrator = try DatabaseMigrator(db: db)
        try firstMigrator.migrate()
        let secondMigrator = try DatabaseMigrator(db: db)
        try secondMigrator.migrate()

        let columns = Set(
            try db.queryAll("PRAGMA table_info(access_presets)")
                .compactMap { $0["name"] }
        )
        #expect(columns.contains("target_app"))
    }

    @Test("Migration v32 creates filter mode tables")
    func filterModePlumbing() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let settingsTable = try db.queryAll(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='filter_mode_settings'"
        )
        let overridesTable = try db.queryAll(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='filter_mode_overrides'"
        )
        #expect(!settingsTable.isEmpty)
        #expect(!overridesTable.isEmpty)

        let overrideIndexGrant = try db.queryAll(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_filter_mode_overrides_grant'"
        )
        let overrideIndexAgent = try db.queryAll(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_filter_mode_overrides_agent'"
        )
        #expect(!overrideIndexGrant.isEmpty)
        #expect(!overrideIndexAgent.isEmpty)
    }

    @Test("Migration v32 is idempotent — re-running does not fail")
    func filterModeIdempotent() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let firstMigrator = try DatabaseMigrator(db: db)
        try firstMigrator.migrate()
        let secondMigrator = try DatabaseMigrator(db: db)
        try secondMigrator.migrate()

        let settingsTable = try db.queryAll(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='filter_mode_settings'"
        )
        #expect(!settingsTable.isEmpty)
    }

    @Test("Migration v34 migrates legacy privacy backends to MLX MXFP8")
    func mlxMXFP8RuntimeMigration() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        let now = ISO8601DateFormatter.shared.string(from: Date())
        for version in 1...33 {
            try db.execute(
                "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                params: ["\(version)", now]
            )
        }

        try db.execute("""
            CREATE TABLE privacy_preflight_settings (
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
            CREATE TABLE privacy_scan_cache (
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
        try db.execute(
            """
            INSERT INTO privacy_preflight_settings
            (id, selected_backend, install_state, model_version, storage_path, installed_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            params: ["default", "official_cli", "installed", "openai/privacy-filter", "/tmp/official-cli", now, now]
        )
        try db.execute(
            """
            INSERT INTO privacy_scan_cache
            (input_hash, backend, model_version, operating_point, category_set_json, content_kind, spans_json, redacted_text, findings_summary, elapsed_ms, cached_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            params: ["hash-1", "official_cli", "legacy", "balanced", "[]", "text", "[]", "redacted", "summary", "1", now]
        )
        try db.execute(
            """
            INSERT INTO privacy_scan_cache
            (input_hash, backend, model_version, operating_point, category_set_json, content_kind, spans_json, redacted_text, findings_summary, elapsed_ms, cached_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            params: ["hash-2", "rules_only", "rules", "balanced", "[]", "text", "[]", "plain", "summary", "1", now]
        )

        let applied = try migrator.migrate()

        #expect(applied == 4)
        #expect(try migrator.currentVersion() == 37)
        let settings = try #require(try db.queryAll("SELECT selected_backend, install_state, model_version, installed_at FROM privacy_preflight_settings").first)
        #expect(settings["selected_backend"] == "mlx")
        #expect(settings["install_state"] == "download_required")
        #expect(settings["model_version"] == nil)
        #expect(settings["installed_at"] == nil)
        #expect(try db.queryScalar("SELECT COUNT(*) FROM privacy_scan_cache WHERE backend = 'official_cli'") == "0")
        #expect(try db.queryScalar("SELECT COUNT(*) FROM privacy_scan_cache WHERE backend = 'rules_only'") == "1")
    }

    @Test("Migration v31 preserves legacy presets created without target_app")
    func sessionTemplatesPreservesLegacyPresets() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        // Insert a preset by directly avoiding target_app — simulates a row
        // created by code running on a pre-v31 schema and persisted across
        // the migration boundary.
        let now = ISO8601DateFormatter().string(from: Date())
        try db.execute(
            """
            INSERT INTO access_presets (preset_id, name, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            """,
            params: ["legacy-1", "Legacy preset", now, now]
        )

        let rows = try db.queryAll(
            "SELECT preset_id, name, target_app FROM access_presets WHERE preset_id = ?",
            params: ["legacy-1"]
        )
        #expect(rows.count == 1)
        // SQLite returns NULL columns as nil/missing in our query interface; this
        // legacy row should have target_app absent or empty, never crashing readers.
        let targetApp = rows.first?["target_app"]?.trimmingCharacters(in: .whitespaces) ?? ""
        #expect(targetApp.isEmpty)
    }

    /// v35 scrubs orphan rows in `file_visibility_overrides` that point at a
    /// missing or removed source, and prunes dead source IDs out of every
    /// `agent_access_policies.allowed_source_ids` JSON list. Without the
    /// migration, the Folders matrix dot indicator lit up for removed rows
    /// because those overrides lingered indefinitely.
    @Test("Migration v35 scrubs orphan access records")
    func migrationScrubsOrphanAccessRecords() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        // Run every migration honestly so the real `sources` and
        // `agent_access_policies` tables exist before we stage stale data.
        _ = try migrator.migrate()

        let now = ISO8601DateFormatter.shared.string(from: Date())

        try db.execute("""
            INSERT INTO sources (source_id, display_name, original_root_path, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, params: ["src-live", "Live", "/tmp/live", "idle", now, now])
        try db.execute("""
            INSERT INTO sources (source_id, display_name, original_root_path, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, params: ["src-removed", "Gone", "/tmp/gone", "removed", now, now])

        try db.execute("""
            INSERT INTO file_visibility_overrides (agent, source_id, relative_path, is_directory, decision, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, params: ["cowork", "src-live", "keep.txt", "0", "allow", now])
        try db.execute("""
            INSERT INTO file_visibility_overrides (agent, source_id, relative_path, is_directory, decision, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, params: ["cowork", "src-removed", "stale.txt", "0", "allow", now])
        try db.execute("""
            INSERT INTO file_visibility_overrides (agent, source_id, relative_path, is_directory, decision, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, params: ["cowork", "src-gone-entirely", "ghost.txt", "0", "deny", now])

        try db.execute("""
            INSERT INTO agent_access_policies
            (policy_id, agent, allowed_source_ids, allowed_email_domains, email_sensitivity, default_email_policy, access_recording_level, is_paused, has_completed_first_grant, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, params: [
            "p-cowork", "cowork",
            #"["src-live","src-removed","src-gone-entirely"]"#,
            "[]", "moderate", "allow_unless_blocked", "lightweight", "0", "1", now, now,
        ])

        // Re-arm v35 so migrate() runs it again over the seeded stale data.
        // Later migrations also need to be removed because the migrator advances from the
        // maximum recorded version.
        try db.execute("DELETE FROM schema_migrations WHERE version = ?", params: ["35"])
        try db.execute("DELETE FROM schema_migrations WHERE version = ?", params: ["36"])
        try db.execute("DELETE FROM schema_migrations WHERE version = ?", params: ["37"])
        let applied = try migrator.migrate()

        #expect(applied == 3)
        #expect(try migrator.currentVersion() == 37)

        let liveOverride = try db.queryAll(
            "SELECT relative_path FROM file_visibility_overrides WHERE source_id = ?",
            params: ["src-live"]
        )
        #expect(liveOverride.count == 1)
        #expect(liveOverride.first?["relative_path"] == "keep.txt")

        let removedOverride = try db.queryAll(
            "SELECT relative_path FROM file_visibility_overrides WHERE source_id = ?",
            params: ["src-removed"]
        )
        #expect(removedOverride.isEmpty)

        let ghostOverride = try db.queryAll(
            "SELECT relative_path FROM file_visibility_overrides WHERE source_id = ?",
            params: ["src-gone-entirely"]
        )
        #expect(ghostOverride.isEmpty)

        let policy = try #require(try db.queryAll(
            "SELECT allowed_source_ids FROM agent_access_policies WHERE policy_id = ?",
            params: ["p-cowork"]
        ).first)
        #expect(policy["allowed_source_ids"] == #"["src-live"]"#)
    }
}
