// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
@testable import ManifoldKit

/// Integration tests for the grant-based access model.
/// Tests the full lifecycle: source → grant → materialize → promote.
@Suite("Grant Access")
struct GrantAccessTests {
    func makeStores() throws -> (GrantStore, DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-access-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        let store = GrantStore(db: db)
        return (store, db, tempDir)
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    /// Create a source directory with test files.
    func createSourceDir(in tempDir: URL, name: String) throws -> URL {
        let dir = tempDir.appendingPathComponent("sources/\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("hello world".utf8).write(to: dir.appendingPathComponent("README.md"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("src"), withIntermediateDirectories: true)
        try Data("func main() {}".utf8).write(to: dir.appendingPathComponent("src/main.swift"))
        return dir
    }

    // MARK: - Full Lifecycle

    @Test("Full grant lifecycle: create → materialize → modify → promote")
    func fullLifecycle() async throws {
        let (store, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        // 1. Create source
        let sourceDir = try createSourceDir(in: tempDir, name: "MyApp")
        let sourceID = try await store.addSource(displayName: "MyApp", rootPath: sourceDir.path)

        // 2. Start grant with materialization
        let matRoot = tempDir.appendingPathComponent("materializations/grant-test")
        let grant = try await store.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [sourceID],
            materializationRoot: matRoot.path
        )

        // 3. Materialize
        let source = try await store.source(id: sourceID)!
        let grantSources = try await store.grantSources(grantID: grant.grantID)
        let results = try MaterializationEngine.materialize(
            grantID: grant.grantID,
            sources: [(source: source, mountName: grantSources[0].mountName)],
            materializationRoot: grant.materializationRoot
        )

        #expect(results.count == 1)
        #expect(results[0].fileCount == 2)

        // Store baseline hash
        try await store.setBaselineHash(
            grantID: grant.grantID,
            sourceID: sourceID,
            hash: results[0].manifestHash
        )

        // 4. Verify materialized files exist
        let mountPath = matRoot.appendingPathComponent(grantSources[0].mountName)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: mountPath.appendingPathComponent("README.md").path))
        #expect(fm.fileExists(atPath: mountPath.appendingPathComponent("src/main.swift").path))

        // 5. Agent modifies a file in the workspace
        try Data("func main() { print(\"hello\") }".utf8)
            .write(to: mountPath.appendingPathComponent("src/main.swift"))

        // 6. Promote changes back
        let summary = try PromoteEngine.promote(
            sourceID: sourceID,
            mountName: grantSources[0].mountName,
            mountURL: mountPath,
            originalURL: URL(fileURLWithPath: sourceDir.path)
        )

        #expect(summary.applied.count == 1)
        #expect(summary.applied[0].relativePath == "src/main.swift")
        #expect(summary.skipped == 1) // README.md unchanged

        // 7. Verify original was updated
        let promoted = try String(contentsOf: sourceDir.appendingPathComponent("src/main.swift"), encoding: .utf8)
        #expect(promoted.contains("hello"))

        // 8. Record promotions
        for file in summary.applied + summary.conflicts + summary.newFiles {
            try await store.recordPromotion(
                grantID: grant.grantID,
                sourceID: sourceID,
                relativePath: file.relativePath,
                result: file.result,
                originalBeforeHash: file.originalBeforeHash,
                promotedHash: file.promotedHash,
                conflictReason: file.conflictReason
            )
        }

        let promos = try await store.promotions(grantID: grant.grantID)
        #expect(promos.count == 1)

        // 9. End grant
        try await store.endGrant(grantID: grant.grantID)
        let ended = try await store.grant(id: grant.grantID)
        #expect(ended?.isActive == false)
    }

    @Test("Grant-mode file resolution uses materialized paths, not originals")
    func grantPathResolution() async throws {
        let (store, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let sourceDir = try createSourceDir(in: tempDir, name: "Project")
        let sourceID = try await store.addSource(displayName: "Project", rootPath: sourceDir.path)

        let matRoot = tempDir.appendingPathComponent("materializations/test")
        let grant = try await store.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [sourceID],
            materializationRoot: matRoot.path
        )

        let source = try await store.source(id: sourceID)!
        let grantSources = try await store.grantSources(grantID: grant.grantID)
        _ = try MaterializationEngine.materialize(
            grantID: grant.grantID,
            sources: [(source: source, mountName: grantSources[0].mountName)],
            materializationRoot: grant.materializationRoot
        )

        // Write to materialized copy (what agent does)
        let mountPath = matRoot.appendingPathComponent(grantSources[0].mountName)
        try Data("agent wrote this".utf8)
            .write(to: mountPath.appendingPathComponent("agent_file.txt"))

        // Materialized copy has the new file
        #expect(FileManager.default.fileExists(
            atPath: mountPath.appendingPathComponent("agent_file.txt").path
        ))

        // Original does NOT have the new file (isolation)
        #expect(!FileManager.default.fileExists(
            atPath: sourceDir.appendingPathComponent("agent_file.txt").path
        ))
    }

    @Test("Conflict detection when original changes during grant")
    func conflictDuringGrant() async throws {
        let (store, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let sourceDir = try createSourceDir(in: tempDir, name: "Conflicting")
        let sourceID = try await store.addSource(displayName: "Conflicting", rootPath: sourceDir.path)

        let matRoot = tempDir.appendingPathComponent("materializations/conflict-test")
        let grant = try await store.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [sourceID],
            materializationRoot: matRoot.path
        )

        let source = try await store.source(id: sourceID)!
        let grantSources = try await store.grantSources(grantID: grant.grantID)
        _ = try MaterializationEngine.materialize(
            grantID: grant.grantID,
            sources: [(source: source, mountName: grantSources[0].mountName)],
            materializationRoot: grant.materializationRoot
        )

        let mountPath = matRoot.appendingPathComponent(grantSources[0].mountName)

        // Agent modifies README.md in workspace
        try Data("agent version".utf8).write(to: mountPath.appendingPathComponent("README.md"))

        // Meanwhile, user modifies README.md in the original
        try Data("user version".utf8).write(to: sourceDir.appendingPathComponent("README.md"))

        // Promote detects the conflict
        let summary = try PromoteEngine.promote(
            sourceID: sourceID,
            mountName: grantSources[0].mountName,
            mountURL: mountPath,
            originalURL: URL(fileURLWithPath: sourceDir.path)
        )

        #expect(summary.conflicts.count == 1)
        #expect(summary.conflicts[0].relativePath == "README.md")
        #expect(summary.applied.isEmpty)

        // Original keeps the user's version
        let original = try String(contentsOf: sourceDir.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(original == "user version")
    }

    @Test("Explicit file scopes block promotion outside approved paths")
    func explicitScopesBlockOutOfScopePromotion() async throws {
        let (store, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let sourceDir = try createSourceDir(in: tempDir, name: "Scoped")
        let sourceID = try await store.addSource(displayName: "Scoped", rootPath: sourceDir.path)

        let matRoot = tempDir.appendingPathComponent("materializations/scoped-test")
        let grant = try await store.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [sourceID],
            materializationRoot: matRoot.path,
            explicitSelection: true
        )

        try await store.replaceGrantFileScopes(
            grantID: grant.grantID,
            scopes: [
                FileSelectionScope(sourceID: sourceID, relativePath: "README.md", isDirectory: false),
            ]
        )

        let source = try await store.source(id: sourceID)!
        let grantSources = try await store.grantSources(grantID: grant.grantID)
        _ = try MaterializationEngine.materialize(
            grantID: grant.grantID,
            sources: [(source: source, mountName: grantSources[0].mountName)],
            materializationRoot: grant.materializationRoot
        )

        let mountPath = matRoot.appendingPathComponent(grantSources[0].mountName)
        try Data("out of scope".utf8).write(to: mountPath.appendingPathComponent("notes.txt"))

        let summary = try PromoteEngine.promote(
            sourceID: sourceID,
            mountName: grantSources[0].mountName,
            mountURL: mountPath,
            originalURL: URL(fileURLWithPath: sourceDir.path),
            allowedScopes: [
                FileSelectionScope(sourceID: sourceID, relativePath: "README.md", isDirectory: false),
            ]
        )

        #expect(summary.newFiles.isEmpty)
        #expect(summary.conflicts.count == 1)
        #expect(summary.conflicts[0].relativePath == "notes.txt")
        #expect(summary.conflicts[0].conflictReason == "Path is outside the approved grant scope")
        #expect(!FileManager.default.fileExists(atPath: sourceDir.appendingPathComponent("notes.txt").path))
    }

    @Test("No grant returns nil from activeGrant")
    func noGrantFallback() async throws {
        let (store, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        // No grant created — GrantStore returns nil
        let grant = try await store.activeGrant(targetApp: .cowork, profileID: "default")
        #expect(grant == nil, "No grant should exist")

        // Sources still queryable (empty is fine)
        let sources = try await store.activeSources()
        #expect(sources.isEmpty)
    }

    @Test("Grant inactivity timeout expires grant")
    func inactivityTimeout() async throws {
        let (store, db, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let sourceDir = try createSourceDir(in: tempDir, name: "Timeout")
        let sourceID = try await store.addSource(displayName: "Timeout", rootPath: sourceDir.path)

        let matRoot = tempDir.appendingPathComponent("materializations/timeout-test")
        let grant = try await store.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [sourceID],
            materializationRoot: matRoot.path,
            inactivityTimeout: 60
        )

        // Force deadline into the past
        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-120))
        try db.execute(
            "UPDATE grants SET inactivity_deadline = ? WHERE grant_id = ?",
            params: [past, grant.grantID]
        )

        // Expire stale grants
        let expired = try await store.expireStaleGrants()
        #expect(expired == 1)

        // Grant should no longer be active
        let active = try await store.activeGrant(targetApp: .cowork, profileID: "default")
        #expect(active == nil)
    }
}
