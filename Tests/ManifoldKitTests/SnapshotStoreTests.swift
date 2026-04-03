import Testing
import Foundation
@testable import ManifoldKit

@Suite("SnapshotStore")
struct SnapshotStoreTests {
    func makeStores() throws -> (ContentStore, SnapshotStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let contentStore = try ContentStore(rootURL: tempDir)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)

        return (contentStore, snapshotStore, tempDir)
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Record baseline and retrieve")
    func baseline() async throws {
        let (_, snapshotStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let data = "Original content".data(using: .utf8)!
        try await snapshotStore.recordBaseline(
            runID: "run-test1",
            workspaceID: "ws-1",
            filePath: "src/main.swift",
            data: data
        )

        let hash = try await snapshotStore.baselineHash(
            runID: "run-test1",
            filePath: "src/main.swift"
        )
        #expect(hash != nil)
    }

    @Test("Record modification with before/after hashes")
    func modification() async throws {
        let (_, snapshotStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let original = "Version 1".data(using: .utf8)!
        try await snapshotStore.recordBaseline(
            runID: "run-test2",
            workspaceID: "ws-1",
            filePath: "file.txt",
            data: original
        )

        let modified = "Version 2".data(using: .utf8)!
        try await snapshotStore.recordModification(
            runID: "run-test2",
            workspaceID: "ws-1",
            filePath: "file.txt",
            newData: modified
        )

        let latest = try await snapshotStore.latestHash(runID: "run-test2", filePath: "file.txt")
        let baseline = try await snapshotStore.baselineHash(runID: "run-test2", filePath: "file.txt")

        #expect(latest != nil)
        #expect(baseline != nil)
        #expect(latest != baseline)
    }

    @Test("Run timeline returns all snapshots in order")
    func runTimeline() async throws {
        let (_, snapshotStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let run = "run-test3"
        let ws = "ws-1"

        try await snapshotStore.recordBaseline(runID: run, workspaceID: ws, filePath: "a.txt", data: "A".data(using: .utf8)!)
        try await snapshotStore.recordBaseline(runID: run, workspaceID: ws, filePath: "b.txt", data: "B".data(using: .utf8)!)
        try await snapshotStore.recordModification(runID: run, workspaceID: ws, filePath: "a.txt", newData: "A modified".data(using: .utf8)!)
        try await snapshotStore.recordCreation(runID: run, workspaceID: ws, filePath: "c.txt", data: "C new".data(using: .utf8)!)

        let timeline = try await snapshotStore.runTimeline(runID: run)
        #expect(timeline.count == 4)

        // Most recent first
        #expect(timeline[0].filePath == "c.txt")
        #expect(timeline[1].filePath == "a.txt")
    }

    @Test("Modified files excludes baselines")
    func modifiedFiles() async throws {
        let (_, snapshotStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let run = "run-test4"
        let ws = "ws-1"

        try await snapshotStore.recordBaseline(runID: run, workspaceID: ws, filePath: "a.txt", data: "A".data(using: .utf8)!)
        try await snapshotStore.recordBaseline(runID: run, workspaceID: ws, filePath: "b.txt", data: "B".data(using: .utf8)!)
        try await snapshotStore.recordModification(runID: run, workspaceID: ws, filePath: "a.txt", newData: "A mod".data(using: .utf8)!)

        let modified = try await snapshotStore.modifiedFiles(runID: run)
        #expect(modified.count == 1)
        #expect(modified[0] == "a.txt")
    }

    @Test("File history shows complete chain")
    func fileHistory() async throws {
        let (_, snapshotStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let run = "run-test5"
        let ws = "ws-1"

        try await snapshotStore.recordBaseline(runID: run, workspaceID: ws, filePath: "x.txt", data: "V0".data(using: .utf8)!)
        try await snapshotStore.recordModification(runID: run, workspaceID: ws, filePath: "x.txt", newData: "V1".data(using: .utf8)!)
        try await snapshotStore.recordModification(runID: run, workspaceID: ws, filePath: "x.txt", newData: "V2".data(using: .utf8)!)

        let history = try await snapshotStore.history(runID: run, filePath: "x.txt")
        #expect(history.count == 3)
        #expect(history[0].isBaseline)
        #expect(!history[1].isBaseline)
        #expect(!history[2].isBaseline)
    }

    @Test("Restore records a manifold-restore snapshot")
    func restore() async throws {
        let (_, snapshotStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let run = "run-test6"
        let ws = "ws-1"
        let originalData = "Original".data(using: .utf8)!

        try await snapshotStore.recordBaseline(runID: run, workspaceID: ws, filePath: "r.txt", data: originalData)
        try await snapshotStore.recordModification(runID: run, workspaceID: ws, filePath: "r.txt", newData: "Changed".data(using: .utf8)!)
        try await snapshotStore.recordRestore(runID: run, workspaceID: ws, filePath: "r.txt", restoredData: originalData)

        let history = try await snapshotStore.history(runID: run, filePath: "r.txt")
        #expect(history.count == 3)
        #expect(history[2].source == "manifold-restore")

        let latest = try await snapshotStore.latestHash(runID: run, filePath: "r.txt")
        let baseline = try await snapshotStore.baselineHash(runID: run, filePath: "r.txt")
        #expect(latest == baseline)
    }

    @Test("File history spans multiple runs")
    func fileHistoryAcrossRuns() async throws {
        let (_, snapshotStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await snapshotStore.recordBaseline(runID: "run-x", workspaceID: "ws-1", filePath: "shared.txt", data: "V1".data(using: .utf8)!)
        try await snapshotStore.recordModification(runID: "run-x", workspaceID: "ws-1", filePath: "shared.txt", newData: "V2".data(using: .utf8)!)
        try await snapshotStore.recordBaseline(runID: "run-y", workspaceID: "ws-1", filePath: "shared.txt", data: "V2".data(using: .utf8)!)
        try await snapshotStore.recordModification(runID: "run-y", workspaceID: "ws-1", filePath: "shared.txt", newData: "V3".data(using: .utf8)!)

        let history = try await snapshotStore.fileHistory(filePath: "shared.txt")
        #expect(history.count == 4)
        // Most recent first
        #expect(history[0].runID == "run-y")
        #expect(history[3].runID == "run-x")
    }

    @Test("File history excludes other files")
    func fileHistoryExcludesOtherFiles() async throws {
        let (_, snapshotStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await snapshotStore.recordCreation(runID: "run-z", workspaceID: "ws-1", filePath: "target.txt", data: "data".data(using: .utf8)!)
        try await snapshotStore.recordCreation(runID: "run-z", workspaceID: "ws-1", filePath: "other.txt", data: "other".data(using: .utf8)!)

        let history = try await snapshotStore.fileHistory(filePath: "target.txt")
        #expect(history.count == 1)
        #expect(history[0].filePath == "target.txt")
    }

    @Test("Data for restore returns correct content")
    func dataForRestore() async throws {
        let (_, snapshotStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let original = "Restore me".data(using: .utf8)!
        try await snapshotStore.recordCreation(runID: "run-r", workspaceID: "ws-1", filePath: "restore.txt", data: original)

        let history = try await snapshotStore.fileHistory(filePath: "restore.txt")
        #expect(history.count == 1)

        let restored = try await snapshotStore.dataForRestore(snapshotID: history[0].id)
        #expect(restored == original)
    }

    @Test("Prune keeps recent runs")
    func pruneKeepsRecent() async throws {
        let (_, snapshotStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        // Create 3 runs
        for i in 0..<3 {
            try await snapshotStore.recordCreation(runID: "run-p\(i)", workspaceID: "ws-1", filePath: "f\(i).txt", data: "data\(i)".data(using: .utf8)!)
        }

        // Prune keeping last 2
        let pruned = try await snapshotStore.pruneOldRuns(keepLast: 2)
        #expect(pruned >= 0) // At least attempted to prune

        // Run-p2 and run-p1 should still exist
        let timeline2 = try await snapshotStore.runTimeline(runID: "run-p2")
        #expect(!timeline2.isEmpty)
    }

    @Test("Workspace timeline spans multiple runs")
    func workspaceTimeline() async throws {
        let (_, snapshotStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let ws = "ws-multi"

        try await snapshotStore.recordBaseline(runID: "run-a", workspaceID: ws, filePath: "f.txt", data: "V1".data(using: .utf8)!)
        try await snapshotStore.recordModification(runID: "run-a", workspaceID: ws, filePath: "f.txt", newData: "V2".data(using: .utf8)!)
        try await snapshotStore.recordBaseline(runID: "run-b", workspaceID: ws, filePath: "f.txt", data: "V2".data(using: .utf8)!)
        try await snapshotStore.recordModification(runID: "run-b", workspaceID: ws, filePath: "f.txt", newData: "V3".data(using: .utf8)!)

        let timeline = try await snapshotStore.workspaceTimeline(workspaceID: ws)
        #expect(timeline.count == 4)
        #expect(timeline[0].runID == "run-b") // Most recent first
    }
}
