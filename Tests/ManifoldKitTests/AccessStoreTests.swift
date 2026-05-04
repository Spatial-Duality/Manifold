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

    // MARK: - v43: settings + per-preset overrides + default-at-launch

    @Test("savePreset round-trips Focus settings through loadPreset")
    func savePresetCarriesSettings() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let saved = try await store.savePreset(
            id: nil,
            name: "Q4 reports",
            targetApp: .cowork,
            fileScopes: [],
            emailIDs: [],
            requestDetailLevel: .summary,
            noteCaptureMode: .verbose,
            allowFileMemory: true,
            summaryFraming: "Q4 financial review",
            emailSensitivity: .strict
        )

        let snapshot = try await store.loadPreset(id: saved.presetID)
        #expect(snapshot != nil)
        #expect(snapshot?.preset.requestDetailLevel == .summary)
        #expect(snapshot?.preset.noteCaptureMode == .verbose)
        #expect(snapshot?.preset.allowFileMemory == true)
        #expect(snapshot?.preset.summaryFraming == "Q4 financial review")
        #expect(snapshot?.preset.emailSensitivity == .strict)
        #expect(snapshot?.preset.isDefaultAtLaunch == false)
    }

    @Test("updatePresetSettings patches settings without touching scope")
    func updateSettingsLeavesScopeAlone() async throws {
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
        let scopes = [FileSelectionScope(sourceID: "src-1", relativePath: "", isDirectory: true)]
        let saved = try await store.savePreset(
            id: nil, name: "Test", targetApp: .cowork,
            fileScopes: scopes, emailIDs: []
        )
        try await store.updatePresetSettings(
            presetID: saved.presetID,
            requestDetailLevel: .detailed,
            noteCaptureMode: nil,
            allowFileMemory: true,
            summaryFraming: nil,
            emailSensitivity: nil
        )
        let snap = try await store.loadPreset(id: saved.presetID)
        #expect(snap?.preset.requestDetailLevel == .detailed)
        #expect(snap?.preset.allowFileMemory == true)
        #expect(snap?.fileScopes.count == 1)
    }

    @Test("Per-preset overrides round-trip and clear correctly")
    func presetOverrideLifecycle() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let saved = try await store.savePreset(
            id: nil, name: "Test", targetApp: .cowork,
            fileScopes: [], emailIDs: []
        )
        try await store.setPresetOverride(
            presetID: saved.presetID, sourceID: "src-1",
            relativePath: "Secrets/.env", isDirectory: false, decision: .deny
        )
        try await store.setPresetOverride(
            presetID: saved.presetID, sourceID: "src-1",
            relativePath: "Specs/API.md", isDirectory: false, decision: .allow
        )

        let read = try await store.presetOverrides(presetID: saved.presetID, agent: .cowork)
        #expect(read.count == 2)
        #expect(read.contains { $0.relativePath == "Secrets/.env" && $0.decision == .deny })
        #expect(read.contains { $0.relativePath == "Specs/API.md" && $0.decision == .allow })

        try await store.clearPresetOverride(
            presetID: saved.presetID, sourceID: "src-1",
            relativePath: "Specs/API.md", isDirectory: false
        )
        let after = try await store.presetOverrides(presetID: saved.presetID, agent: .cowork)
        #expect(after.count == 1)
        #expect(after.first?.relativePath == "Secrets/.env")
    }

    @Test("savePresetOverrides full-replaces the saved set in one transaction")
    func savePresetOverridesReplaces() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let saved = try await store.savePreset(
            id: nil, name: "Test", targetApp: .cowork,
            fileScopes: [], emailIDs: []
        )
        // Seed
        try await store.savePresetOverrides(presetID: saved.presetID, overrides: [
            FileVisibilityOverrideRecord(agent: .cowork, sourceID: "s", relativePath: "a", isDirectory: false, decision: .allow),
            FileVisibilityOverrideRecord(agent: .cowork, sourceID: "s", relativePath: "b", isDirectory: false, decision: .deny),
        ])
        // Replace
        try await store.savePresetOverrides(presetID: saved.presetID, overrides: [
            FileVisibilityOverrideRecord(agent: .cowork, sourceID: "s", relativePath: "c", isDirectory: false, decision: .allow),
        ])
        let read = try await store.presetOverrides(presetID: saved.presetID, agent: .cowork)
        #expect(read.count == 1)
        #expect(read.first?.relativePath == "c")
    }

    @Test("setDefaultAtLaunch enforces ≤1 row per target_app")
    func defaultAtLaunchExclusivity() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let a = try await store.savePreset(id: nil, name: "A", targetApp: .cowork, fileScopes: [], emailIDs: [])
        let b = try await store.savePreset(id: nil, name: "B", targetApp: .cowork, fileScopes: [], emailIDs: [])
        let c = try await store.savePreset(id: nil, name: "C", targetApp: .codex, fileScopes: [], emailIDs: [])

        try await store.setDefaultAtLaunch(presetID: a.presetID, for: .cowork)
        var current = try await store.defaultPresetForLaunch(agent: .cowork)
        #expect(current?.presetID == a.presetID)

        // Switching default should clear A, set B.
        try await store.setDefaultAtLaunch(presetID: b.presetID, for: .cowork)
        current = try await store.defaultPresetForLaunch(agent: .cowork)
        #expect(current?.presetID == b.presetID)

        // Setting Codex's default doesn't touch Claude's.
        try await store.setDefaultAtLaunch(presetID: c.presetID, for: .codex)
        let coworkCurrent = try await store.defaultPresetForLaunch(agent: .cowork)
        let codexCurrent = try await store.defaultPresetForLaunch(agent: .codex)
        #expect(coworkCurrent?.presetID == b.presetID)
        #expect(codexCurrent?.presetID == c.presetID)

        // Clearing.
        try await store.setDefaultAtLaunch(presetID: nil, for: .cowork)
        let cleared = try await store.defaultPresetForLaunch(agent: .cowork)
        #expect(cleared == nil)
    }

    @Test("savePreset with overrides persists them in one call")
    func savePresetWithOverrides() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let saved = try await store.savePreset(
            id: nil,
            name: "With overrides",
            targetApp: .cowork,
            fileScopes: [],
            emailIDs: [],
            overrides: [
                FileVisibilityOverrideRecord(agent: .cowork, sourceID: "s", relativePath: "x", isDirectory: false, decision: .deny)
            ]
        )
        let snap = try await store.loadPreset(id: saved.presetID)
        #expect(snap?.overrides.count == 1)
        #expect(snap?.overrides.first?.decision == .deny)
    }

    @Test("Deleting a preset cascades to its overrides")
    func deletePresetCascades() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let saved = try await store.savePreset(
            id: nil, name: "Test", targetApp: .cowork, fileScopes: [], emailIDs: []
        )
        try await store.setPresetOverride(
            presetID: saved.presetID, sourceID: "s", relativePath: "x", isDirectory: false, decision: .deny
        )
        try await store.deletePreset(id: saved.presetID)
        let read = try await store.presetOverrides(presetID: saved.presetID, agent: .cowork)
        #expect(read.isEmpty)
    }

    // MARK: - v44: per-agent scope, mirror_to_both, is_built_in

    @Test("savePreset round-trips mirrorToBoth and isBuiltIn flags")
    func savePresetMirrorAndBuiltInFlags() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let mirrored = try await store.savePreset(
            id: nil, name: "Q4 reports", targetApp: nil,
            fileScopes: [], emailIDs: [],
            mirrorToBoth: true, isBuiltIn: false
        )
        #expect(mirrored.mirrorToBoth == true)
        #expect(mirrored.isBuiltIn == false)

        let independent = try await store.savePreset(
            id: nil, name: "Default", targetApp: nil,
            fileScopes: [], emailIDs: [],
            mirrorToBoth: false, isBuiltIn: true
        )
        #expect(independent.mirrorToBoth == false)
        #expect(independent.isBuiltIn == true)
    }

    @Test("Built-in Focuses cannot be deleted")
    func builtInFocusUndeletable() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let saved = try await store.savePreset(
            id: nil, name: "Default", targetApp: nil,
            fileScopes: [], emailIDs: [],
            isBuiltIn: true
        )
        do {
            try await store.deletePreset(id: saved.presetID)
            Issue.record("Expected delete of built-in to throw")
        } catch ManifoldError.invalidState {
            // expected
        }
        let stillThere = try await store.allPresets().contains { $0.presetID == saved.presetID }
        #expect(stillThere)
    }

    @Test("Per-agent fileScopes accessor filters correctly")
    func perAgentFileScopes() async throws {
        let (store, db, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let now = ISO8601DateFormatter().string(from: Date())
        for sourceID in ["shared", "claude-only", "codex-only"] {
            try db.execute(
                """
                INSERT INTO sources (source_id, display_name, original_root_path, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                params: [sourceID, sourceID, "/tmp/\(sourceID)", "idle", now, now]
            )
        }

        let preset = try await store.savePreset(
            id: nil, name: "Mixed", targetApp: nil,
            fileScopes: [], emailIDs: []
        )
        // Write rows directly with explicit agents (bypassing the
        // mirror-mode write path) to verify the per-agent filter.
        try db.execute(
            """
            INSERT INTO access_preset_file_scopes (preset_id, source_id, relative_path, is_directory, agent)
            VALUES (?, ?, '', 1, '')
            """,
            params: [preset.presetID, "shared"]
        )
        try db.execute(
            """
            INSERT INTO access_preset_file_scopes (preset_id, source_id, relative_path, is_directory, agent)
            VALUES (?, ?, '', 1, ?)
            """,
            params: [preset.presetID, "claude-only", "cowork"]
        )
        try db.execute(
            """
            INSERT INTO access_preset_file_scopes (preset_id, source_id, relative_path, is_directory, agent)
            VALUES (?, ?, '', 1, ?)
            """,
            params: [preset.presetID, "codex-only", "codex"]
        )

        let claudeScopes = try await store.fileScopes(presetID: preset.presetID, agent: .cowork)
        #expect(Set(claudeScopes.map(\.sourceID)) == ["shared", "claude-only"])
        let codexScopes = try await store.fileScopes(presetID: preset.presetID, agent: .codex)
        #expect(Set(codexScopes.map(\.sourceID)) == ["shared", "codex-only"])
    }

    @Test("updatePresetFileScopes per-agent replaces only that agent's rows")
    func perAgentFileScopesIsolatedReplace() async throws {
        let (store, db, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let now = ISO8601DateFormatter().string(from: Date())
        for sourceID in ["a", "b", "c"] {
            try db.execute(
                """
                INSERT INTO sources (source_id, display_name, original_root_path, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                params: [sourceID, sourceID, "/tmp/\(sourceID)", "idle", now, now]
            )
        }

        let preset = try await store.savePreset(
            id: nil, name: "Per-agent", targetApp: nil,
            fileScopes: [], emailIDs: []
        )
        // Seed Claude with a; Codex with b; both with c (mirror).
        try await store.updatePresetFileScopes(
            presetID: preset.presetID,
            fileScopes: [FileSelectionScope(sourceID: "a", relativePath: "", isDirectory: true)],
            agent: .cowork
        )
        try await store.updatePresetFileScopes(
            presetID: preset.presetID,
            fileScopes: [FileSelectionScope(sourceID: "b", relativePath: "", isDirectory: true)],
            agent: .codex
        )
        try await store.updatePresetFileScopes(
            presetID: preset.presetID,
            fileScopes: [FileSelectionScope(sourceID: "c", relativePath: "", isDirectory: true)],
            agent: nil  // mirror row
        )

        let claudeScopes = try await store.fileScopes(presetID: preset.presetID, agent: .cowork)
        #expect(Set(claudeScopes.map(\.sourceID)) == ["a", "c"])
        let codexScopes = try await store.fileScopes(presetID: preset.presetID, agent: .codex)
        #expect(Set(codexScopes.map(\.sourceID)) == ["b", "c"])

        // Replace Claude's set — Codex and mirror rows must not change.
        try await store.updatePresetFileScopes(
            presetID: preset.presetID,
            fileScopes: [FileSelectionScope(sourceID: "a", relativePath: "Sub", isDirectory: true)],
            agent: .cowork
        )
        let claudeAfter = try await store.fileScopes(presetID: preset.presetID, agent: .cowork)
        #expect(claudeAfter.contains { $0.relativePath == "Sub" })
        let codexAfter = try await store.fileScopes(presetID: preset.presetID, agent: .codex)
        #expect(Set(codexAfter.map(\.sourceID)) == ["b", "c"])
    }
}
