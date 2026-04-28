// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("FilterModeStore")
struct FilterModeStoreTests {
    func makeStore() throws -> (FilterModeStore, DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-filter-mode-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        return (FilterModeStore(db: db), db, tempDir)
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    @Test("Default mode is .off when nothing has been written")
    func defaultsOff() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        #expect(try await store.globalMode() == .off)
        #expect(try await store.mode(for: .cowork) == .off)
        #expect(try await store.mode(for: .codex) == .off)
    }

    @Test("Setting global mode changes the default for all agents")
    func globalModeSet() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.setGlobalMode(.warn)
        #expect(try await store.globalMode() == .warn)
        #expect(try await store.mode(for: .cowork) == .warn)
        #expect(try await store.mode(for: .codex) == .warn)
    }

    @Test("Per-agent override takes precedence over the global default")
    func perAgentOverride() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.setGlobalMode(.warn)
        try await store.setMode(.block, for: .codex)

        #expect(try await store.mode(for: .cowork) == .warn) // inherits global
        #expect(try await store.mode(for: .codex) == .block) // explicit override
        #expect(try await store.globalMode() == .warn)
    }

    @Test("Clearing a per-agent override falls back to the global default")
    func clearAgentOverride() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.setGlobalMode(.warn)
        try await store.setMode(.block, for: .codex)
        #expect(try await store.mode(for: .codex) == .block)

        try await store.setMode(nil, for: .codex)
        #expect(try await store.mode(for: .codex) == .warn) // fell back to global
    }

    @Test("addOverride records grant-scoped approval and hasOverride sees it")
    func overrideRoundtrip() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let approval = FilterModeOverrideRecord(
            grantID: "grant-1",
            agent: .cowork,
            sourceID: "src-1",
            relativePath: "report.pdf"
        )
        try await store.addOverride(approval)

        #expect(try await store.hasOverride(
            grantID: "grant-1", agent: .cowork, sourceID: "src-1", relativePath: "report.pdf"
        ))
        // Different grant: not approved.
        #expect(try await store.hasOverride(
            grantID: "grant-2", agent: .cowork, sourceID: "src-1", relativePath: "report.pdf"
        ) == false)
        // Different agent on same path: not approved.
        #expect(try await store.hasOverride(
            grantID: "grant-1", agent: .codex, sourceID: "src-1", relativePath: "report.pdf"
        ) == false)
    }

    @Test("addOverrides applies a batch in one transaction")
    func batchOverrides() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let batch = (0..<5).map { i in
            FilterModeOverrideRecord(
                grantID: "grant-1",
                agent: .cowork,
                sourceID: "src-1",
                relativePath: "file-\(i).md"
            )
        }
        try await store.addOverrides(batch)

        let recorded = try await store.overrides(grantID: "grant-1")
        #expect(recorded.count == 5)
    }

    @Test("addOverrides empty input is a no-op")
    func emptyOverrides() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.addOverrides([])
        #expect(try await store.overrides(grantID: "grant-1").isEmpty)
    }

    @Test("addOverride is idempotent — re-approving same path updates timestamp only")
    func idempotentOverride() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.addOverride(FilterModeOverrideRecord(
            grantID: "grant-1", agent: .cowork, sourceID: "src-1", relativePath: "file.md",
            approvedAt: "2026-04-01T00:00:00Z"
        ))
        try await store.addOverride(FilterModeOverrideRecord(
            grantID: "grant-1", agent: .cowork, sourceID: "src-1", relativePath: "file.md",
            approvedAt: "2026-04-28T00:00:00Z"
        ))

        let overrides = try await store.overrides(grantID: "grant-1")
        #expect(overrides.count == 1)
        #expect(overrides.first?.approvedAt == "2026-04-28T00:00:00Z")
    }
}
