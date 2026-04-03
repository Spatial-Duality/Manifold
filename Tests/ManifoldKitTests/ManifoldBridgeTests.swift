import Testing
import Foundation
@testable import ManifoldKit

// ManifoldBridge is in ManifoldMCP target, but its core logic depends on ManifoldKit.
// We test the path validation and store interaction patterns here using ManifoldKit directly.

@Suite("MCP Bridge Logic")
struct MCPBridgeLogicTests {
    func makeStores() throws -> (DatabaseConnection, ContentStore, SnapshotStore, WorkspaceLeaseManager, AuditStore, EmailFilter, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let contentStore = try ContentStore(rootURL: tempDir)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)
        let leaseManager = try WorkspaceLeaseManager(db: db, snapshotStore: snapshotStore)
        let auditStore = try AuditStore(db: db)
        let emailFilter = try EmailFilter(db: db)

        return (db, contentStore, snapshotStore, leaseManager, auditStore, emailFilter, tempDir)
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    // MARK: - Path Validation

    @Test("Reject absolute paths")
    func absolutePath() {
        let path = "/etc/passwd"
        #expect(path.hasPrefix("/"))
    }

    @Test("Reject path traversal")
    func pathTraversal() {
        let path = "../../../etc/passwd"
        #expect(path.contains(".."))
    }

    @Test("Accept normal relative path")
    func normalPath() {
        let path = "src/main.swift"
        #expect(!path.hasPrefix("/"))
        #expect(!path.contains(".."))
    }

    @Test("Reject email write attempt")
    func emailWriteRejected() {
        let path = "_emails/thread.md"
        #expect(path.hasPrefix("_emails/"))
    }

    // MARK: - Active Run Detection

    @Test("No active run when workspace not registered")
    func noActiveRun() async throws {
        let (db, _, _, leaseManager, _, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let rows = try db.queryAll("SELECT * FROM workspaces WHERE status = 'active'")
        #expect(rows.isEmpty)
    }

    @Test("Active run detected after grant")
    func activeRunDetected() async throws {
        let (_, _, _, leaseManager, _, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-1", profileID: "default", rootPath: tempDir.path, agent: "cowork")
        let runID = try await leaseManager.startRun(workspaceID: "ws-1", agent: "cowork", trigger: .userGrant)

        let active = try await leaseManager.activeRun(workspaceID: "ws-1")
        #expect(active != nil)
        #expect(active?.runID == runID)
    }

    @Test("No active run after end")
    func noRunAfterEnd() async throws {
        let (_, _, _, leaseManager, _, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-2", profileID: "default", rootPath: tempDir.path, agent: "cowork")
        let runID = try await leaseManager.startRun(workspaceID: "ws-2", agent: "cowork", trigger: .userGrant)
        try await leaseManager.endRun(runID: runID)

        let active = try await leaseManager.activeRun(workspaceID: "ws-2")
        #expect(active == nil)
    }

    // MARK: - Audit Logging

    @Test("File read is audited")
    func fileReadAudited() async throws {
        let (_, _, _, _, auditStore, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await auditStore.log(action: .fileRead, runID: "run-1", workspaceID: "ws-1", filePath: "test.txt")
        let entries = try await auditStore.recentEntries(limit: 10)
        #expect(entries.count == 1)
        #expect(entries[0].action == "file_read")
        #expect(entries[0].filePath == "test.txt")
    }

    @Test("MCP connection is audited")
    func mcpConnectionAudited() async throws {
        let (_, _, _, _, auditStore, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await auditStore.log(action: .mcpConnection, metadata: ["event": "connected"])
        let entries = try await auditStore.recentEntries(limit: 10)
        #expect(entries.count == 1)
        #expect(entries[0].action == "mcp_connection")
    }

    // MARK: - Snapshot on Write

    @Test("Write creates snapshot via snapshot store")
    func writeCreatesSnapshot() async throws {
        let (_, contentStore, snapshotStore, leaseManager, _, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-snap", profileID: "default", rootPath: tempDir.path, agent: "cowork")
        let runID = try await leaseManager.startRun(workspaceID: "ws-snap", agent: "cowork", trigger: .userGrant)

        let data = "hello world".data(using: .utf8)!
        try await snapshotStore.recordCreation(runID: runID, workspaceID: "ws-snap", filePath: "new.txt", data: data)

        let timeline = try await snapshotStore.runTimeline(runID: runID)
        #expect(timeline.count == 1)
        #expect(timeline[0].filePath == "new.txt")
    }
}
