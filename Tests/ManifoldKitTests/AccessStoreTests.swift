// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("AccessStore")
struct AccessStoreTests {
    func makeStore() throws -> (AccessStore, DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-access-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        return (AccessStore(db: db), db, tempDir)
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Save, update, load, and delete access presets")
    func presetLifecycle() async throws {
        let (store, db, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let now = ISO8601DateFormatter().string(from: Date())
        try db.execute(
            """
            INSERT INTO sources (source_id, display_name, original_root_path, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            params: ["src-1", "Project", "/tmp/project", "idle", now, now]
        )
        try db.execute(
            """
            INSERT INTO email_messages (
                email_id, account, mailbox, sender, recipients, subject, received_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            params: ["email-1", "account-1", "Inbox", "Sender One", "", "Subject One", now]
        )
        try db.execute(
            """
            INSERT INTO email_messages (
                email_id, account, mailbox, sender, recipients, subject, received_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            params: ["email-2", "account-1", "Inbox", "Sender Two", "", "Subject Two", now]
        )
        try db.execute(
            """
            INSERT INTO email_messages (
                email_id, account, mailbox, sender, recipients, subject, received_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            params: ["email-3", "account-1", "Archive", "Sender Three", "", "Subject Three", now]
        )

        let created = try await store.savePreset(
            name: "Core Access",
            fileScopes: [
                FileSelectionScope(sourceID: "src-1", relativePath: "Sources/App", isDirectory: true),
                FileSelectionScope(sourceID: "src-1", relativePath: "README.md", isDirectory: false),
            ],
            emailIDs: ["email-2", "email-1", "email-2"]
        )

        let presets = try await store.allPresets()
        #expect(presets.count == 1)
        #expect(presets.first?.presetID == created.presetID)

        let loaded = try await store.loadPreset(id: created.presetID)
        #expect(loaded?.preset.name == "Core Access")
        #expect(loaded?.fileScopes.count == 2)
        #expect(loaded?.emailIDs == ["email-1", "email-2"])

        let updated = try await store.savePreset(
            id: created.presetID,
            name: "Focused Access",
            fileScopes: [
                FileSelectionScope(sourceID: "src-1", relativePath: "Sources/App/Main.swift", isDirectory: false),
            ],
            emailIDs: ["email-3"]
        )

        #expect(updated.presetID == created.presetID)

        let reloaded = try await store.loadPreset(id: created.presetID)
        #expect(reloaded?.preset.name == "Focused Access")
        #expect(reloaded?.fileScopes == [
            FileSelectionScope(sourceID: "src-1", relativePath: "Sources/App/Main.swift", isDirectory: false)
        ])
        #expect(reloaded?.emailIDs == ["email-3"])

        try await store.deletePreset(id: created.presetID)
        #expect(try await store.allPresets().isEmpty)
        #expect(try await store.loadPreset(id: created.presetID) == nil)
    }

    @Test("savePreset persists targetApp and loadPreset reads it back")
    func savePresetWithTargetApp() async throws {
        let (store, db, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let now = ISO8601DateFormatter().string(from: Date())
        try db.execute(
            """
            INSERT INTO sources (source_id, display_name, original_root_path, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            params: ["src-1", "Project", "/tmp/project", "idle", now, now]
        )

        let saved = try await store.savePreset(
            name: "Q4 Reporting",
            targetApp: .cowork,
            fileScopes: [
                FileSelectionScope(sourceID: "src-1", relativePath: "Q4", isDirectory: true)
            ],
            emailIDs: []
        )
        #expect(saved.targetApp == .cowork)

        let loaded = try await store.loadPreset(id: saved.presetID)
        #expect(loaded?.preset.targetApp == .cowork)
        #expect(loaded?.preset.name == "Q4 Reporting")
    }

    @Test("savePreset with nil targetApp produces unscoped preset")
    func savePresetUnscoped() async throws {
        let (store, db, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let now = ISO8601DateFormatter().string(from: Date())
        try db.execute(
            """
            INSERT INTO sources (source_id, display_name, original_root_path, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            params: ["src-1", "Project", "/tmp/project", "idle", now, now]
        )

        let saved = try await store.savePreset(
            name: "Default",
            targetApp: nil,
            fileScopes: [],
            emailIDs: []
        )
        #expect(saved.targetApp == nil)
    }

    @Test("templatesForAgent returns scoped templates plus unscoped legacy presets")
    func templatesForAgentFilter() async throws {
        let (store, db, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let now = ISO8601DateFormatter().string(from: Date())
        try db.execute(
            """
            INSERT INTO sources (source_id, display_name, original_root_path, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            params: ["src-1", "Project", "/tmp/project", "idle", now, now]
        )

        // Templates scoped to Claude (cowork).
        _ = try await store.savePreset(
            name: "Q4 (Claude)", targetApp: .cowork, fileScopes: [], emailIDs: []
        )
        _ = try await store.savePreset(
            name: "Code review (Claude)", targetApp: .cowork, fileScopes: [], emailIDs: []
        )
        // Template scoped to Codex.
        _ = try await store.savePreset(
            name: "Tax filing (Codex)", targetApp: .codex, fileScopes: [], emailIDs: []
        )
        // Unscoped (legacy / default) preset.
        _ = try await store.savePreset(
            name: "Default", targetApp: nil, fileScopes: [], emailIDs: []
        )

        let claudeTemplates = try await store.templatesForAgent(.cowork)
        let claudeNames = Set(claudeTemplates.map(\.name))
        #expect(claudeNames.contains("Q4 (Claude)"))
        #expect(claudeNames.contains("Code review (Claude)"))
        #expect(claudeNames.contains("Default"))            // unscoped is visible to any agent
        #expect(!claudeNames.contains("Tax filing (Codex)")) // codex-scoped is hidden from claude

        let codexTemplates = try await store.templatesForAgent(.codex)
        let codexNames = Set(codexTemplates.map(\.name))
        #expect(codexNames.contains("Tax filing (Codex)"))
        #expect(codexNames.contains("Default"))
        #expect(!codexNames.contains("Q4 (Claude)"))
    }

    @Test("templatesForAgent returns empty array when no templates exist")
    func templatesForAgentEmpty() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }
        let templates = try await store.templatesForAgent(.cowork)
        #expect(templates.isEmpty)
    }

    @Test("templatesForAgent surfaces legacy presets persisted with NULL target_app")
    func templatesForAgentLegacyNullCompat() async throws {
        let (store, db, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let now = ISO8601DateFormatter().string(from: Date())
        // Direct insert without target_app — simulates a row created by pre-v31 code.
        try db.execute(
            """
            INSERT INTO access_presets (preset_id, name, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            """,
            params: ["legacy-1", "Legacy preset", now, now]
        )

        let templates = try await store.templatesForAgent(.cowork)
        #expect(templates.contains(where: { $0.presetID == "legacy-1" }))
        #expect(templates.first(where: { $0.presetID == "legacy-1" })?.targetApp == nil)
    }
}
