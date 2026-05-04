// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("FileVisibilityOverrideStore")
struct FileVisibilityOverrideStoreTests {
    func makeStore() throws -> (FileVisibilityOverrideStore, DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-file-visibility-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        return (FileVisibilityOverrideStore(db: db), db, tempDir)
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Overrides persist and resolve explicit allow / deny against inherited scope")
    func overrideLifecycle() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.setOverride(
            agent: .cowork,
            sourceID: "src-1",
            relativePath: "Specs/API.md",
            isDirectory: false,
            decision: .allow
        )
        try await store.setOverride(
            agent: .cowork,
            sourceID: "src-1",
            relativePath: "Secrets/.env",
            isDirectory: false,
            decision: .deny
        )

        let stored = try await store.overrides(agent: .cowork)
        #expect(stored.count == 2)

        let resolver = try await store.resolver(agent: .cowork)
        let allowed = resolver.evaluate(sourceID: "src-1", relativePath: "Specs/API.md", defaultVisible: false)
        #expect(allowed.isVisible)
        #expect(allowed.origin == .explicitAllow)

        let denied = resolver.evaluate(sourceID: "src-1", relativePath: "Secrets/.env", defaultVisible: true)
        #expect(!denied.isVisible)
        #expect(denied.origin == .explicitDeny)

        let inherited = resolver.evaluate(sourceID: "src-1", relativePath: "Sources/App.swift", defaultVisible: true)
        #expect(inherited.isVisible)
        #expect(inherited.origin == .inheritedAllow)

        try await store.clearOverride(
            agent: .cowork,
            sourceID: "src-1",
            relativePath: "Secrets/.env",
            isDirectory: false
        )
        let afterClear = try await store.resolver(agent: .cowork)
        let fallback = afterClear.evaluate(sourceID: "src-1", relativePath: "Secrets/.env", defaultVisible: true)
        #expect(fallback.isVisible)
        #expect(fallback.origin == .inheritedAllow)
    }

    @Test("Directory overrides apply to descendant files")
    func directoryOverridesCascadeToDescendants() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.setOverride(
            agent: .cowork,
            sourceID: "src-1",
            relativePath: "Specs",
            isDirectory: true,
            decision: .allow
        )
        try await store.setOverride(
            agent: .cowork,
            sourceID: "src-1",
            relativePath: "Secrets",
            isDirectory: true,
            decision: .deny
        )

        let resolver = try await store.resolver(agent: .cowork)

        let inheritedAllow = resolver.evaluate(
            sourceID: "src-1",
            relativePath: "Specs/API/contract.md",
            defaultVisible: false
        )
        #expect(inheritedAllow.isVisible)
        #expect(inheritedAllow.origin == .explicitAllow)

        let inheritedDeny = resolver.evaluate(
            sourceID: "src-1",
            relativePath: "Secrets/Prod/.env",
            defaultVisible: true
        )
        #expect(!inheritedDeny.isVisible)
        #expect(inheritedDeny.origin == .explicitDeny)
    }

    @Test("setManyOverrides empty input is a no-op")
    func setManyEmpty() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.setManyOverrides([])
        let overrides = try await store.overrides(agent: .cowork)
        #expect(overrides.isEmpty)
    }

    @Test("setManyOverrides applies all rows in a single transaction")
    func setManyApplies() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let batch: [FileVisibilityOverrideRecord] = (0..<10).map { i in
            FileVisibilityOverrideRecord(
                agent: .cowork,
                sourceID: "src-1",
                relativePath: "file-\(i).txt",
                isDirectory: false,
                decision: .deny
            )
        }
        try await store.setManyOverrides(batch)

        let overrides = try await store.overrides(agent: .cowork)
        #expect(overrides.count == 10)
        #expect(overrides.allSatisfy { $0.decision == .deny })
    }

    @Test("setManyOverrides supports mixed allow/deny in one batch")
    func setManyMixedDecisions() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.setManyOverrides([
            FileVisibilityOverrideRecord(
                agent: .cowork,
                sourceID: "src-1",
                relativePath: "allowed.md",
                isDirectory: false,
                decision: .allow
            ),
            FileVisibilityOverrideRecord(
                agent: .cowork,
                sourceID: "src-1",
                relativePath: "denied.md",
                isDirectory: false,
                decision: .deny
            ),
        ])

        let overrides = try await store.overrides(agent: .cowork)
        #expect(overrides.count == 2)
        let decisions = Set(overrides.map(\.decision))
        #expect(decisions == [.allow, .deny])
    }

    @Test("setManyOverrides INSERT OR REPLACE semantics on existing rows")
    func setManyReplacesExisting() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.setOverride(
            agent: .cowork,
            sourceID: "src-1",
            relativePath: "file.md",
            isDirectory: false,
            decision: .allow
        )
        // Replace via batch.
        try await store.setManyOverrides([
            FileVisibilityOverrideRecord(
                agent: .cowork,
                sourceID: "src-1",
                relativePath: "file.md",
                isDirectory: false,
                decision: .deny
            )
        ])
        let overrides = try await store.overrides(agent: .cowork)
        #expect(overrides.count == 1)
        #expect(overrides.first?.decision == .deny)
    }

    @Test("setManyOverrides supports per-agent scoping in one batch")
    func setManyMultipleAgents() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.setManyOverrides([
            FileVisibilityOverrideRecord(
                agent: .cowork,
                sourceID: "src-1",
                relativePath: "claude-only.md",
                isDirectory: false,
                decision: .allow
            ),
            FileVisibilityOverrideRecord(
                agent: .codex,
                sourceID: "src-1",
                relativePath: "codex-only.md",
                isDirectory: false,
                decision: .allow
            ),
        ])
        #expect(try await store.overrides(agent: .cowork).count == 1)
        #expect(try await store.overrides(agent: .codex).count == 1)
    }

    @Test("clearAllOverrides wipes one agent's set without touching the other")
    func clearAllOverridesScopedByAgent() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.setManyOverrides([
            FileVisibilityOverrideRecord(agent: .cowork, sourceID: "s", relativePath: "a", isDirectory: false, decision: .allow),
            FileVisibilityOverrideRecord(agent: .cowork, sourceID: "s", relativePath: "b", isDirectory: false, decision: .deny),
            FileVisibilityOverrideRecord(agent: .codex, sourceID: "s", relativePath: "c", isDirectory: false, decision: .allow),
        ])
        try await store.clearAllOverrides(agent: .cowork)
        #expect(try await store.overrides(agent: .cowork).isEmpty)
        #expect(try await store.overrides(agent: .codex).count == 1)
    }
}
