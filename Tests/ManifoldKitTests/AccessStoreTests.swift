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
}
