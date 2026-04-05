import Testing
import Foundation
@testable import ManifoldKit

@Suite("GrantStore")
struct GrantStoreTests {
    func makeStore() throws -> (GrantStore, DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-grant-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        let store = GrantStore(db: db)
        return (store, db, tempDir)
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    // MARK: - Sources

    @Test("Add source and retrieve it")
    func addSource() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let sourceID = try await store.addSource(displayName: "MyProject", rootPath: "/Users/test/MyProject")
        let source = try await store.source(id: sourceID)

        #expect(source != nil)
        #expect(source?.displayName == "MyProject")
        #expect(source?.originalRootPath == "/Users/test/MyProject")
        #expect(source?.status == "idle")
    }

    @Test("Active sources excludes removed")
    func activeSourcesFilter() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let id1 = try await store.addSource(displayName: "Active", rootPath: "/path/active")
        let id2 = try await store.addSource(displayName: "Removed", rootPath: "/path/removed")
        try await store.removeSource(sourceID: id2)

        let active = try await store.activeSources()
        #expect(active.count == 1)
        #expect(active[0].sourceID == id1)

        let all = try await store.allSources()
        #expect(all.count == 2)
    }

    @Test("Pause and resume source")
    func pauseResumeSource() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let id = try await store.addSource(displayName: "Test", rootPath: "/path/test")
        try await store.pauseSource(sourceID: id)

        var source = try await store.source(id: id)
        #expect(source?.isPaused == true)
        #expect(source?.isAccessible == false)

        try await store.resumeSource(sourceID: id)
        source = try await store.source(id: id)
        #expect(source?.isPaused == false)
        #expect(source?.isAccessible == true)
    }

    @Test("Find source by path")
    func sourceByPath() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.addSource(displayName: "Test", rootPath: "/unique/path/here")
        let found = try await store.source(byPath: "/unique/path/here")
        #expect(found != nil)
        #expect(found?.displayName == "Test")

        let notFound = try await store.source(byPath: "/nonexistent")
        #expect(notFound == nil)
    }

    // MARK: - Grants

    @Test("Start grant links sources and sets them active")
    func startGrant() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let srcID = try await store.addSource(displayName: "App", rootPath: "/path/app")
        let grant = try await store.startGrant(
            targetApp: .cowork,
            profileID: "profile-1",
            sourceIDs: [srcID],
            materializationRoot: "/tmp/mat/grant-test"
        )

        #expect(grant.isActive)
        #expect(grant.targetApp == "cowork")

        let sources = try await store.grantSources(grantID: grant.grantID)
        #expect(sources.count == 1)
        #expect(sources[0].sourceID == srcID)
        #expect(sources[0].mountName == "app")

        let source = try await store.source(id: srcID)
        #expect(source?.status == "active")
    }

    @Test("Only one active grant per target/profile")
    func singleActiveGrant() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let srcID = try await store.addSource(displayName: "Test", rootPath: "/path/test")

        let grant1 = try await store.startGrant(
            targetApp: .cowork, profileID: "p1",
            sourceIDs: [srcID], materializationRoot: "/tmp/mat/g1"
        )
        let grant2 = try await store.startGrant(
            targetApp: .cowork, profileID: "p1",
            sourceIDs: [srcID], materializationRoot: "/tmp/mat/g2"
        )

        // First grant should be ended
        let g1 = try await store.grant(id: grant1.grantID)
        #expect(g1?.isActive == false)

        // Second grant should be active
        let g2 = try await store.grant(id: grant2.grantID)
        #expect(g2?.isActive == true)
    }

    @Test("End grant resets sources to idle")
    func endGrantResetsSource() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let srcID = try await store.addSource(displayName: "Test", rootPath: "/path/test")
        let grant = try await store.startGrant(
            targetApp: .cowork, profileID: "p1",
            sourceIDs: [srcID], materializationRoot: "/tmp/mat/g"
        )

        try await store.endGrant(grantID: grant.grantID)

        let source = try await store.source(id: srcID)
        #expect(source?.status == "idle")

        let ended = try await store.grant(id: grant.grantID)
        #expect(ended?.isActive == false)
    }

    @Test("Source stays active when shared by multiple grants")
    func sharedSourceStaysActive() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let srcID = try await store.addSource(displayName: "Shared", rootPath: "/path/shared")

        let g1 = try await store.startGrant(
            targetApp: .cowork, profileID: "p1",
            sourceIDs: [srcID], materializationRoot: "/tmp/mat/g1"
        )
        // Different target app, so both can be active
        let g2 = try await store.startGrant(
            targetApp: .codex, profileID: "p1",
            sourceIDs: [srcID], materializationRoot: "/tmp/mat/g2"
        )

        // End first grant
        try await store.endGrant(grantID: g1.grantID)

        // Source should still be active (codex grant still using it)
        let source = try await store.source(id: srcID)
        #expect(source?.status == "active")

        // End second grant
        try await store.endGrant(grantID: g2.grantID)
        let sourceAfter = try await store.source(id: srcID)
        #expect(sourceAfter?.status == "idle")
    }

    @Test("Touch grant extends deadline")
    func touchGrant() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let srcID = try await store.addSource(displayName: "Test", rootPath: "/path/test")
        let grant = try await store.startGrant(
            targetApp: .cowork, profileID: "p1",
            sourceIDs: [srcID], materializationRoot: "/tmp/mat/g",
            inactivityTimeout: 60
        )

        let originalDeadline = grant.inactivityDeadline

        try await store.touchGrant(grantID: grant.grantID, timeout: 7200)
        let refreshed = try await store.grant(id: grant.grantID)

        #expect(refreshed?.inactivityDeadline != originalDeadline)
    }

    @Test("Expire stale grants")
    func expireStale() async throws {
        let (store, db, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let srcID = try await store.addSource(displayName: "Test", rootPath: "/path/test")
        let grant = try await store.startGrant(
            targetApp: .cowork, profileID: "p1",
            sourceIDs: [srcID], materializationRoot: "/tmp/mat/g",
            inactivityTimeout: 60
        )

        // Set deadline to the past
        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-120))
        try db.execute(
            "UPDATE grants SET inactivity_deadline = ? WHERE grant_id = ?",
            params: [past, grant.grantID]
        )

        let expired = try await store.expireStaleGrants()
        #expect(expired == 1)

        let g = try await store.grant(id: grant.grantID)
        #expect(g?.status == GrantStatus.timedOut.rawValue)
    }

    // MARK: - Promotions

    @Test("Record and retrieve promotions")
    func promotions() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let srcID = try await store.addSource(displayName: "Test", rootPath: "/path/test")
        let grant = try await store.startGrant(
            targetApp: .cowork, profileID: "p1",
            sourceIDs: [srcID], materializationRoot: "/tmp/mat/g"
        )

        try await store.recordPromotion(
            grantID: grant.grantID, sourceID: srcID,
            relativePath: "src/main.swift", result: .applied,
            originalBeforeHash: "abc123", promotedHash: "def456"
        )
        try await store.recordPromotion(
            grantID: grant.grantID, sourceID: srcID,
            relativePath: "README.md", result: .conflict,
            conflictReason: "Original changed since baseline"
        )

        let promos = try await store.promotions(grantID: grant.grantID)
        #expect(promos.count == 2)
        #expect(promos[0].result == PromotionResult.applied.rawValue)
        #expect(promos[1].isConflict)
        #expect(promos[1].conflictReason == "Original changed since baseline")
    }

    // MARK: - Session Summaries

    @Test("Save and retrieve session summaries")
    func sessionSummaries() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let srcID = try await store.addSource(displayName: "Test", rootPath: "/path/test")
        let grant = try await store.startGrant(
            targetApp: .cowork, profileID: "p1",
            sourceIDs: [srcID], materializationRoot: "/tmp/mat/g"
        )

        let now = ISO8601DateFormatter().string(from: Date())
        try await store.saveSummary(
            grantID: grant.grantID, targetApp: .cowork,
            startedAt: now, endedAt: now,
            markdown: "## Session\n\nRefactored auth module."
        )

        let summaries = try await store.allSummaries()
        #expect(summaries.count == 1)
        #expect(summaries[0].summaryMarkdown.contains("Refactored auth"))
        #expect(summaries[0].grantID == grant.grantID)

        let bySummary = try await store.summaries(grantID: grant.grantID)
        #expect(bySummary.count == 1)
    }

    // MARK: - Baseline Hash

    @Test("Set baseline manifest hash on grant-source link")
    func baselineHash() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let srcID = try await store.addSource(displayName: "Test", rootPath: "/path/test")
        let grant = try await store.startGrant(
            targetApp: .cowork, profileID: "p1",
            sourceIDs: [srcID], materializationRoot: "/tmp/mat/g"
        )

        try await store.setBaselineHash(grantID: grant.grantID, sourceID: srcID, hash: "sha256-abc123")

        let links = try await store.grantSources(grantID: grant.grantID)
        #expect(links[0].baselineManifestHash == "sha256-abc123")
    }

    // MARK: - Update Materialization Root

    @Test("Update materialization root after grant creation")
    func updateMaterializationRoot() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let srcID = try await store.addSource(displayName: "Test", rootPath: "/path/test")
        let grant = try await store.startGrant(
            targetApp: .cowork, profileID: "p1",
            sourceIDs: [srcID], materializationRoot: "/tmp/placeholder"
        )

        // Update to actual root
        try await store.updateMaterializationRoot(grantID: grant.grantID, root: "/real/path/workspace")

        let updated = try await store.grant(id: grant.grantID)
        #expect(updated?.materializationRoot == "/real/path/workspace")
    }

    // MARK: - Multiple Summaries Per Grant

    @Test("Multiple summaries accumulate for the same grant")
    func multipleSummaries() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let srcID = try await store.addSource(displayName: "Multi", rootPath: "/path/multi")
        let grant = try await store.startGrant(
            targetApp: .cowork, profileID: "p1",
            sourceIDs: [srcID], materializationRoot: "/tmp/mat/multi"
        )

        let now = ISO8601DateFormatter().string(from: Date())
        try await store.saveSummary(
            grantID: grant.grantID, targetApp: .cowork,
            startedAt: now, endedAt: now,
            markdown: "Auto-generated summary"
        )
        try await store.saveSummary(
            grantID: grant.grantID, targetApp: .cowork,
            startedAt: now, endedAt: now,
            markdown: "Agent note: completed auth refactor"
        )

        let summaries = try await store.summaries(grantID: grant.grantID)
        #expect(summaries.count == 2)

        let all = try await store.allSummaries()
        #expect(all.count == 2)
    }
}
