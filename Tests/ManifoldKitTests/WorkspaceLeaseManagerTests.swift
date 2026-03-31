import Testing
import Foundation
@testable import ManifoldKit

@Suite("WorkspaceLeaseManager")
struct WorkspaceLeaseManagerTests {
    func makeManager() throws -> (WorkspaceLeaseManager, ContentStore, SnapshotStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let contentStore = try ContentStore(rootURL: tempDir)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)
        let manager = try WorkspaceLeaseManager(db: db, snapshotStore: snapshotStore)

        return (manager, contentStore, snapshotStore, tempDir)
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Register workspace and retrieve by profile")
    func registerAndRetrieve() async throws {
        let (manager, _, _, tempDir) = try makeManager()
        defer { cleanup(tempDir) }

        let ws = ManagedWorkspace(profileID: "profile-1", agent: "cowork", baseURL: tempDir)
        try await manager.registerWorkspace(ws)

        let record = try await manager.workspace(forProfile: "profile-1")
        #expect(record != nil)
        #expect(record?.profileID == "profile-1")
        #expect(record?.agent == "cowork")
        #expect(record?.status == "idle")
    }

    @Test("Start run returns unique ID and sets workspace active")
    func startRun() async throws {
        let (manager, _, _, tempDir) = try makeManager()
        defer { cleanup(tempDir) }

        let ws = ManagedWorkspace(profileID: "profile-2", agent: "cowork", baseURL: tempDir)
        try await manager.registerWorkspace(ws)

        let runID = try await manager.startRun(
            workspaceID: ws.workspaceID,
            agent: "cowork",
            trigger: .userGrant
        )

        #expect(runID.hasPrefix("run-"))

        let active = try await manager.activeRun(workspaceID: ws.workspaceID)
        #expect(active != nil)
        #expect(active?.runID == runID)
        #expect(active?.status == "active")
        #expect(active?.trigger == "user_grant")
    }

    @Test("End run sets status to closed and workspace to idle")
    func endRun() async throws {
        let (manager, _, _, tempDir) = try makeManager()
        defer { cleanup(tempDir) }

        let ws = ManagedWorkspace(profileID: "profile-3", agent: "cowork", baseURL: tempDir)
        try await manager.registerWorkspace(ws)

        let runID = try await manager.startRun(
            workspaceID: ws.workspaceID,
            agent: "cowork",
            trigger: .userGrant
        )

        try await manager.endRun(runID: runID)

        let active = try await manager.activeRun(workspaceID: ws.workspaceID)
        #expect(active == nil)

        let wsRecord = try await manager.workspace(forProfile: "profile-3")
        #expect(wsRecord?.status == "idle")
    }

    @Test("Starting a new run ends the previous one")
    func startRunEndsPrevious() async throws {
        let (manager, _, _, tempDir) = try makeManager()
        defer { cleanup(tempDir) }

        let ws = ManagedWorkspace(profileID: "profile-4", agent: "cowork", baseURL: tempDir)
        try await manager.registerWorkspace(ws)

        let run1 = try await manager.startRun(
            workspaceID: ws.workspaceID,
            agent: "cowork",
            trigger: .userGrant
        )

        let run2 = try await manager.startRun(
            workspaceID: ws.workspaceID,
            agent: "cowork",
            trigger: .userRefresh
        )

        #expect(run1 != run2)

        let allRuns = try await manager.runs(workspaceID: ws.workspaceID)
        #expect(allRuns.count == 2)

        // run2 is active, run1 is closed
        let activeRun = allRuns.first(where: { $0.isActive })
        #expect(activeRun?.runID == run2)

        let closedRun = allRuns.first(where: { !$0.isActive })
        #expect(closedRun?.runID == run1)
    }

    @Test("Mark baseline complete records timestamp")
    func markBaseline() async throws {
        let (manager, _, _, tempDir) = try makeManager()
        defer { cleanup(tempDir) }

        let ws = ManagedWorkspace(profileID: "profile-5", agent: "cowork", baseURL: tempDir)
        try await manager.registerWorkspace(ws)

        let runID = try await manager.startRun(
            workspaceID: ws.workspaceID,
            agent: "cowork",
            trigger: .userGrant
        )

        try await manager.markBaselineComplete(runID: runID)

        let active = try await manager.activeRun(workspaceID: ws.workspaceID)
        #expect(active?.baselineCompletedAt != nil)
    }

    @Test("Runs list returns all runs for workspace, most recent first")
    func runsList() async throws {
        let (manager, _, _, tempDir) = try makeManager()
        defer { cleanup(tempDir) }

        let ws = ManagedWorkspace(profileID: "profile-6", agent: "cowork", baseURL: tempDir)
        try await manager.registerWorkspace(ws)

        let run1 = try await manager.startRun(workspaceID: ws.workspaceID, agent: "cowork", trigger: .userGrant)
        try await manager.endRun(runID: run1)

        let run2 = try await manager.startRun(workspaceID: ws.workspaceID, agent: "cowork", trigger: .userRefresh)
        try await manager.endRun(runID: run2)

        let run3 = try await manager.startRun(workspaceID: ws.workspaceID, agent: "cowork", trigger: .userGrant)

        let allRuns = try await manager.runs(workspaceID: ws.workspaceID)
        #expect(allRuns.count == 3)
        #expect(allRuns[0].runID == run3) // Most recent first
    }

    @Test("No active run returns nil")
    func noActiveRun() async throws {
        let (manager, _, _, tempDir) = try makeManager()
        defer { cleanup(tempDir) }

        let ws = ManagedWorkspace(profileID: "profile-7", agent: "cowork", baseURL: tempDir)
        try await manager.registerWorkspace(ws)

        let active = try await manager.activeRun(workspaceID: ws.workspaceID)
        #expect(active == nil)
    }
}
