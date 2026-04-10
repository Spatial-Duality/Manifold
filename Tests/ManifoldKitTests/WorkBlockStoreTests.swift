import Testing
import Foundation
@testable import ManifoldKit

@Suite("WorkBlockStore")
struct WorkBlockStoreTests {
    func makeStores() throws -> (WorkBlockStore, GrantStore, DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-wb-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        let wbStore = WorkBlockStore(db: db)
        let grantStore = GrantStore(db: db)
        return (wbStore, grantStore, db, tempDir)
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    /// Helper: create a grant to link work blocks to.
    func createGrant(_ grantStore: GrantStore, tempDir: URL) async throws -> String {
        let sourceID = try await grantStore.addSource(
            displayName: "Test", rootPath: tempDir.appendingPathComponent("source").path
        )
        let grant = try await grantStore.startGrant(
            targetApp: .cowork, profileID: "default",
            sourceIDs: [sourceID], materializationRoot: tempDir.appendingPathComponent("mat").path
        )
        return grant.grantID
    }

    @Test("Start work block creates active record")
    func startBlock() async throws {
        let (store, grantStore, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let grantID = try await createGrant(grantStore, tempDir: tempDir)
        let block = try await store.startBlock(
            agent: .cowork, grantID: grantID, sourceIDs: ["src-1"]
        )

        #expect(block.isActive)
        #expect(block.agent == .cowork)
        #expect(block.grantID == grantID)
        #expect(block.modifiedFileCount == 0)
        #expect(block.newFileCount == 0)
    }

    @Test("Only one active block per agent")
    func singleActive() async throws {
        let (store, grantStore, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let grantID = try await createGrant(grantStore, tempDir: tempDir)
        let first = try await store.startBlock(agent: .cowork, grantID: grantID, sourceIDs: [])
        let second = try await store.startBlock(agent: .cowork, grantID: grantID, sourceIDs: [])

        let firstReloaded = try await store.block(id: first.id)
        #expect(firstReloaded?.status == .discarded, "First block should be discarded")

        let secondReloaded = try await store.block(id: second.id)
        #expect(secondReloaded?.isActive == true)
    }

    @Test("Pause and resume block")
    func pauseResume() async throws {
        let (store, grantStore, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let grantID = try await createGrant(grantStore, tempDir: tempDir)
        let block = try await store.startBlock(agent: .cowork, grantID: grantID, sourceIDs: [])

        try await store.pauseBlock(id: block.id)
        var reloaded = try await store.block(id: block.id)
        #expect(reloaded?.isPaused == true)

        try await store.resumeBlock(id: block.id)
        reloaded = try await store.block(id: block.id)
        #expect(reloaded?.isActive == true)
    }

    @Test("End block with promoted status")
    func endPromoted() async throws {
        let (store, grantStore, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let grantID = try await createGrant(grantStore, tempDir: tempDir)
        let block = try await store.startBlock(agent: .cowork, grantID: grantID, sourceIDs: [])

        try await store.endBlock(id: block.id, status: .promoted)
        let reloaded = try await store.block(id: block.id)
        #expect(reloaded?.status == .promoted)
        #expect(reloaded?.endedAt != nil)
    }

    @Test("End block with discarded status")
    func endDiscarded() async throws {
        let (store, grantStore, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let grantID = try await createGrant(grantStore, tempDir: tempDir)
        let block = try await store.startBlock(agent: .cowork, grantID: grantID, sourceIDs: [])

        try await store.endBlock(id: block.id, status: .discarded)
        let reloaded = try await store.block(id: block.id)
        #expect(reloaded?.status == .discarded)
    }

    @Test("Active block query returns nil when none active")
    func noActiveBlock() async throws {
        let (store, _, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let active = try await store.activeBlock(for: .cowork)
        #expect(active == nil)
    }

    @Test("Active block query returns paused blocks too")
    func pausedCountsAsActive() async throws {
        let (store, grantStore, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let grantID = try await createGrant(grantStore, tempDir: tempDir)
        let block = try await store.startBlock(agent: .cowork, grantID: grantID, sourceIDs: [])
        try await store.pauseBlock(id: block.id)

        let active = try await store.activeBlock(for: .cowork)
        #expect(active != nil, "Paused block should be returned by activeBlock")
        #expect(active?.isPaused == true)
    }

    @Test("Update file counts")
    func updateCounts() async throws {
        let (store, grantStore, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let grantID = try await createGrant(grantStore, tempDir: tempDir)
        let block = try await store.startBlock(agent: .cowork, grantID: grantID, sourceIDs: [])

        try await store.updateCounts(id: block.id, modifiedFiles: 12, newFiles: 3)
        let reloaded = try await store.block(id: block.id)
        #expect(reloaded?.modifiedFileCount == 12)
        #expect(reloaded?.newFileCount == 3)
    }

    @Test("Any active block returns across agents")
    func anyActiveBlock() async throws {
        let (store, grantStore, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        var any = try await store.anyActiveBlock()
        #expect(any == nil)

        let grantID = try await createGrant(grantStore, tempDir: tempDir)
        _ = try await store.startBlock(agent: .codex, grantID: grantID, sourceIDs: [])

        any = try await store.anyActiveBlock()
        #expect(any != nil)
        #expect(any?.agent == .codex)
    }

    @Test("All blocks returns history for agent")
    func allBlocks() async throws {
        let (store, grantStore, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let grantID = try await createGrant(grantStore, tempDir: tempDir)

        // First block: start and promote
        let b1 = try await store.startBlock(agent: .cowork, grantID: grantID, sourceIDs: [])
        try await store.endBlock(id: b1.id, status: .promoted)

        // Second block: start (first is already ended, so no auto-discard)
        _ = try await store.startBlock(agent: .cowork, grantID: grantID, sourceIDs: [])

        let all = try await store.allBlocks(for: .cowork)
        #expect(all.count == 2)

        let statuses = Set(all.map(\.status))
        #expect(statuses.contains(.active), "Should have one active block")
        #expect(statuses.contains(.promoted), "Should have one promoted block")
    }
}
