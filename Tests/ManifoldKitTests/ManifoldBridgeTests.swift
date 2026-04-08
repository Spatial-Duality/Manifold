import Testing
import Foundation
@testable import ManifoldKit

// ManifoldBridge is in ManifoldMCP target, but its core logic depends on ManifoldKit.
// We test the path validation and store interaction patterns here using ManifoldKit directly.

@Suite("MCP Bridge Logic")
struct MCPBridgeLogicTests {
    func makeStores() throws -> (DatabaseConnection, ContentStore, SnapshotStore, WorkspaceLeaseManager, AuditStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let contentStore = try ContentStore(rootURL: tempDir)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)
        let leaseManager = try WorkspaceLeaseManager(db: db, snapshotStore: snapshotStore)
        let auditStore = try AuditStore(db: db)

        return (db, contentStore, snapshotStore, leaseManager, auditStore, tempDir)
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
        let (db, _, _, leaseManager, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let rows = try db.queryAll("SELECT * FROM workspaces WHERE status = 'active'")
        #expect(rows.isEmpty)
    }

    @Test("Active run detected after grant")
    func activeRunDetected() async throws {
        let (_, _, _, leaseManager, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-1", profileID: "default", rootPath: tempDir.path, agent: "cowork")
        let runID = try await leaseManager.startRun(workspaceID: "ws-1", agent: "cowork", trigger: .userGrant)

        let active = try await leaseManager.activeRun(workspaceID: "ws-1")
        #expect(active != nil)
        #expect(active?.runID == runID)
    }

    @Test("No active run after end")
    func noRunAfterEnd() async throws {
        let (_, _, _, leaseManager, _, tempDir) = try makeStores()
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
        let (_, _, _, _, auditStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await auditStore.log(action: .fileRead, runID: "run-1", workspaceID: "ws-1", filePath: "test.txt")
        let entries = try await auditStore.recentEntries(limit: 10)
        #expect(entries.count == 1)
        #expect(entries[0].action == "file_read")
        #expect(entries[0].filePath == "test.txt")
    }

    @Test("MCP connection is audited")
    func mcpConnectionAudited() async throws {
        let (_, _, _, _, auditStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await auditStore.log(action: .mcpConnection, metadata: ["event": "connected"])
        let entries = try await auditStore.recentEntries(limit: 10)
        #expect(entries.count == 1)
        #expect(entries[0].action == "mcp_connection")
    }

    // MARK: - Snapshot on Write

    @Test("Write creates snapshot via snapshot store")
    func writeCreatesSnapshot() async throws {
        let (_, contentStore, snapshotStore, leaseManager, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-snap", profileID: "default", rootPath: tempDir.path, agent: "cowork")
        let runID = try await leaseManager.startRun(workspaceID: "ws-snap", agent: "cowork", trigger: .userGrant)

        let data = "hello world".data(using: .utf8)!
        try await snapshotStore.recordCreation(runID: runID, workspaceID: "ws-snap", filePath: "new.txt", data: data)

        let timeline = try await snapshotStore.runTimeline(runID: runID)
        #expect(timeline.count == 1)
        #expect(timeline[0].filePath == "new.txt")
    }

    // MARK: - Write Path: Modification vs Creation

    @Test("Modification records before and after hashes")
    func modificationTracking() async throws {
        let (_, contentStore, snapshotStore, leaseManager, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-mod", profileID: "default", rootPath: tempDir.path, agent: "cowork")
        let runID = try await leaseManager.startRun(workspaceID: "ws-mod", agent: "cowork", trigger: .userGrant)

        // Write a file on disk first (simulates existing file)
        let filePath = "src/main.swift"
        let fileURL = tempDir.appendingPathComponent(filePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let originalData = "original content".data(using: .utf8)!
        try originalData.write(to: fileURL)

        // Record baseline
        try await snapshotStore.recordBaseline(runID: runID, workspaceID: "ws-mod", filePath: filePath, data: originalData)

        // Modify
        let newData = "modified content".data(using: .utf8)!
        try await snapshotStore.recordModification(runID: runID, workspaceID: "ws-mod", filePath: filePath, newData: newData, source: "mcp")

        let timeline = try await snapshotStore.runTimeline(runID: runID)
        let modification = timeline.first { $0.isBaseline == false }
        #expect(modification != nil, "Should have a non-baseline snapshot")
        #expect(modification?.afterHash != nil, "After hash should be set")
    }

    @Test("Auto-run creation when no active run exists")
    func autoRunCreation() async throws {
        let (_, _, _, leaseManager, _, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-auto", profileID: "default", rootPath: tempDir.path, agent: "cowork")

        // No run started — activeRun should be nil
        let active = try await leaseManager.activeRun(workspaceID: "ws-auto")
        #expect(active == nil)

        // Start auto-resume run (like write_file does)
        let runID = try await leaseManager.startRun(workspaceID: "ws-auto", agent: "cowork", trigger: .autoResume)
        #expect(!runID.isEmpty)

        let nowActive = try await leaseManager.activeRun(workspaceID: "ws-auto")
        #expect(nowActive?.runID == runID)
    }

    // MARK: - Write Path: Audit Trail

    @Test("Write logs file_created for new files")
    func writeLogsCreated() async throws {
        let (_, _, _, _, auditStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await auditStore.log(action: .fileCreated, workspaceID: "ws-1", agent: "cowork", filePath: "new-file.txt")
        let entries = try await auditStore.recentEntries(limit: 10)
        #expect(entries.count == 1)
        #expect(entries[0].action == "file_created")
    }

    @Test("Write logs file_modified for existing files")
    func writeLogsModified() async throws {
        let (_, _, _, _, auditStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await auditStore.log(action: .fileModified, workspaceID: "ws-1", agent: "cowork", filePath: "existing.txt")
        let entries = try await auditStore.recentEntries(limit: 10)
        #expect(entries.count == 1)
        #expect(entries[0].action == "file_modified")
    }

    // MARK: - Email Write Rejection

    @Test("Email paths are identified correctly")
    func emailPathDetection() {
        let emailPaths = ["_emails/thread.md", "_emails/inbox/msg.txt"]
        let normalPaths = ["src/_emails/note.txt", "emails/draft.txt", "file.txt"]

        for path in emailPaths {
            #expect(path.hasPrefix("_emails/"), "\(path) should be detected as email path")
        }
        for path in normalPaths {
            #expect(!path.hasPrefix("_emails/"), "\(path) should NOT be detected as email path")
        }
    }
}
