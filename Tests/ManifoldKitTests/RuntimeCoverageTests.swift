// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import Testing
@testable import ManifoldKit
@testable import ManifoldRuntime

@Suite("RuntimeCoverage")
struct RuntimeCoverageTests {
    func makeRuntime() throws -> (ManifoldRuntime, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-runtime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return (try ManifoldRuntime(storeURL: tempDir), tempDir)
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Coverage events are deduped by key")
    func coverageEventsAreDeduped() async throws {
        let (runtime, tempDir) = try makeRuntime()
        defer { cleanup(tempDir) }

        await runtime.recordCoverageEvent(
            agent: .codex,
            coverageState: .outsideCoverage,
            eventType: "drift",
            message: "changed outside coverage",
            resourcePath: "shared/worklog.md",
            dedupeKey: "drift-1"
        )
        await runtime.recordCoverageEvent(
            agent: .codex,
            coverageState: .outsideCoverage,
            eventType: "drift",
            message: "changed outside coverage",
            resourcePath: "shared/worklog.md",
            dedupeKey: "drift-1"
        )

        let events = await runtime.coverageEvents(limit: 10)
        #expect(events.count == 1)
        #expect(events[0].coverageState == .outsideCoverage)
    }

    @Test("Connected snapshot reports manifold routed for a normal session gateway")
    func connectedSnapshotReportsNormalSessionGateway() async throws {
        let (runtime, tempDir) = try makeRuntime()
        defer { cleanup(tempDir) }

        let sourceRoot = tempDir.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let sourceID = try await runtime.grantStore.addSource(displayName: "Shared", rootPath: sourceRoot.path)
        let grant = try await runtime.grantStore.startGrant(
            targetApp: .codex,
            profileID: "profile-test",
            sourceIDs: [sourceID],
            materializationRoot: tempDir.appendingPathComponent("workspace").path
        )
        _ = try await runtime.workBlockStore.startBlock(agent: .codex, grantID: grant.grantID, sourceIDs: [sourceID])
        let bridge = await runtime.bridge(for: "coverage-test", targetApp: .codex, version: "test")
        await bridge.registerVerifiedClientIdentity(
            VerifiedClientIdentity(
                requestedTargetApp: TargetApp.codex.rawValue,
                effectiveTargetApp: TargetApp.codex.rawValue,
                clientProcessID: 123,
                clientExecutablePath: nil,
                hostProcessID: 456,
                hostBundleIdentifier: "com.openai.codex",
                hostExecutablePath: nil,
                status: .verified,
                reason: "test"
            )
        )

        let snapshots = await runtime.connectedClientSnapshots()
        let codex = try #require(snapshots.first(where: { $0.agent == TargetApp.codex.rawValue }))
        #expect(codex.coverageState == .manifoldRouted)
    }

    @Test("Connected snapshot reports tracked workspace for a draft workspace block")
    func connectedSnapshotReportsDraftWorkspace() async throws {
        let (runtime, tempDir) = try makeRuntime()
        defer { cleanup(tempDir) }

        let sourceRoot = tempDir.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let sourceID = try await runtime.grantStore.addSource(displayName: "Shared", rootPath: sourceRoot.path)
        let grant = try await runtime.grantStore.startGrant(
            targetApp: .codex,
            profileID: "profile-test",
            sourceIDs: [sourceID],
            materializationRoot: tempDir.appendingPathComponent("workspace").path,
            summaryFraming: "Manifold draft workspace for governed AI file writes."
        )
        _ = try await runtime.workBlockStore.startBlock(agent: .codex, grantID: grant.grantID, sourceIDs: [sourceID])

        let snapshots = await runtime.connectedClientSnapshots()
        let codex = try #require(snapshots.first(where: { $0.agent == TargetApp.codex.rawValue }))
        #expect(codex.coverageState == .trackedWorkspace)
    }

    @Test("Drift scan emits a drift coverage event for changed originals")
    func driftScanEmitsCoverageEvent() async throws {
        let (runtime, tempDir) = try makeRuntime()
        defer { cleanup(tempDir) }

        let sourceRoot = tempDir.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let originalFile = sourceRoot.appendingPathComponent("worklog.md")
        try Data("before".utf8).write(to: originalFile)

        let sourceID = try await runtime.grantStore.addSource(displayName: "Shared", rootPath: sourceRoot.path)
        let workspaceRoot = tempDir.appendingPathComponent("workspace")
        let grant = try await runtime.grantStore.startGrant(
            targetApp: .codex,
            profileID: "profile-test",
            sourceIDs: [sourceID],
            materializationRoot: workspaceRoot.path
        )
        _ = try await runtime.workBlockStore.startBlock(agent: .codex, grantID: grant.grantID, sourceIDs: [sourceID])

        let mountName = try #require(try await runtime.grantStore.grantSources(grantID: grant.grantID).first?.mountName)
        let baselineDirectory = workspaceRoot.appendingPathComponent(mountName)
        try FileManager.default.createDirectory(at: baselineDirectory, withIntermediateDirectories: true)
        let baselineHash = SHA256.hash(data: Data("before".utf8)).map { String(format: "%02x", $0) }.joined()
        let baseline = ["worklog.md": baselineHash]
        let baselineData = try JSONSerialization.data(withJSONObject: baseline)
        try baselineData.write(to: baselineDirectory.appendingPathComponent(".manifold-baseline.json"))

        try Data("after".utf8).write(to: originalFile)
        await runtime.scanForActiveWorkBlockDrift()

        let events = await runtime.coverageEvents(limit: 10)
        #expect(events.contains(where: { $0.eventType == "drift" && $0.resourcePath == "\(mountName)/worklog.md" }))
    }
}
