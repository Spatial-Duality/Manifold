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
}
