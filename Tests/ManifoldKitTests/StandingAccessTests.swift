import Testing
import Foundation
@testable import ManifoldKit
@testable import ManifoldMCP

/// Integration tests for standing access via PolicyStore + ManifoldBridge.
/// Validates that the bridge resolves access through policies (not grants)
/// when PolicyStore is injected.
@Suite("Standing Access")
struct StandingAccessTests {
    struct Harness {
        let db: DatabaseConnection
        let contentStore: ContentStore
        let snapshotStore: SnapshotStore
        let auditStore: AuditStore
        let grantStore: GrantStore
        let emailStore: EmailStore
        let artifactIndex: ArtifactIndex
        let policyStore: PolicyStore
        let workBlockStore: WorkBlockStore
        let bridge: ManifoldBridge
        let tempDir: URL
    }

    func makeHarness() throws -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-standing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let contentStore = try ContentStore(rootURL: tempDir)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)
        let auditStore = try AuditStore(db: db)
        let grantStore = GrantStore(db: db)
        let emailStore = EmailStore(db: db)
        let artifactIndex = try ArtifactIndex(db: db)
        let policyStore = PolicyStore(db: db)
        let workBlockStore = WorkBlockStore(db: db)

        let bridge = ManifoldBridge(
            db: db,
            auditStore: auditStore,
            contentStore: contentStore,
            grantStore: grantStore,
            emailStore: emailStore,
            snapshotStore: snapshotStore,
            artifactIndex: artifactIndex,
            policyStore: policyStore,
            workBlockStore: workBlockStore
        )

        return Harness(
            db: db, contentStore: contentStore, snapshotStore: snapshotStore,
            auditStore: auditStore, grantStore: grantStore, emailStore: emailStore,
            artifactIndex: artifactIndex, policyStore: policyStore,
            workBlockStore: workBlockStore, bridge: bridge, tempDir: tempDir
        )
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    /// Create a source directory with test files and register it.
    func createAndRegisterSource(harness: Harness, name: String) async throws -> String {
        let sourceDir = harness.tempDir.appendingPathComponent("sources/\(name)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("hello world".utf8).write(to: sourceDir.appendingPathComponent("README.md"))
        try FileManager.default.createDirectory(at: sourceDir.appendingPathComponent("src"), withIntermediateDirectories: true)
        try Data("func main() {}".utf8).write(to: sourceDir.appendingPathComponent("src/main.swift"))
        return try await harness.grantStore.addSource(displayName: name, rootPath: sourceDir.path)
    }

    // MARK: - Status Tests

    @Test("Status shows no access when policy is empty")
    func emptyPolicyStatus() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let status = await h.bridge.getStatus()
        #expect(status.active == false)
        #expect(status.message.contains("No access configured"))
    }

    @Test("Status shows standing access when policy has sources")
    func standingAccessStatus() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)

        let status = await h.bridge.getStatus()
        #expect(status.active)
        #expect(status.message.contains("standing access"))
        #expect(status.message.contains("MyApp"))
        #expect(status.fileCount > 0)
    }

    @Test("Status shows paused when agent is paused")
    func pausedStatus() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)
        try await h.policyStore.pauseAgent(.cowork)

        let status = await h.bridge.getStatus()
        #expect(status.active == false)
        #expect(status.message.contains("paused"))
    }

    @Test("Paused agent denies file access")
    func pausedDeniesAccess() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)
        try await h.policyStore.pauseAgent(.cowork)

        do {
            _ = try await h.bridge.listFiles()
            Issue.record("Expected access denied error")
        } catch let error as ManifoldMCPError {
            if case .accessPaused = error {
                // Expected
            } else {
                Issue.record("Expected accessPaused, got \(error)")
            }
        }
    }

    @Test("Resumed agent restores access")
    func resumeRestoresAccess() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)
        try await h.policyStore.pauseAgent(.cowork)
        try await h.policyStore.resumeAgent(.cowork)

        let status = await h.bridge.getStatus()
        #expect(status.active)
    }
}
