// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("Reliability Kernel")
struct ReliabilityKernelTests {
    func makeDB() throws -> (DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-reliability-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        return (db, tempDir)
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    @Test("Runtime environment defaults resolve production app-support paths")
    func runtimeEnvironmentDefaultsResolveProductionAppSupportPaths() throws {
        let env: [String: String] = [:]
        let appSupport = try #require(ManifoldRuntimeEnvironment.appSupportRootURL(env: env))
        let expectedAppSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        #expect(appSupport.standardizedFileURL.path == expectedAppSupport.standardizedFileURL.path)

        let runtimeStore = try #require(ManifoldRuntimeEnvironment.runtimeStoreURL(env: env))
        #expect(runtimeStore.standardizedFileURL.path == expectedAppSupport
            .appendingPathComponent("Manifold", isDirectory: true)
            .appendingPathComponent("store", isDirectory: true)
            .standardizedFileURL.path)

        let diagnostics = try #require(ManifoldRuntimeEnvironment.diagnosticsDirectoryURL(env: env))
        #expect(diagnostics.standardizedFileURL.path == expectedAppSupport
            .appendingPathComponent("Manifold", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .standardizedFileURL.path)
    }

    @Test("Runtime environment test home remains isolated")
    func runtimeEnvironmentTestHomeRemainsIsolated() throws {
        let testHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-runtime-env-\(UUID().uuidString)", isDirectory: true)
        let env = [ManifoldRuntimeEnvironment.testHomeKey: testHome.path]

        #expect(ManifoldRuntimeEnvironment.runtimeStoreURL(env: env)?.standardizedFileURL.path == testHome
            .appendingPathComponent("runtime-store", isDirectory: true)
            .standardizedFileURL.path)
        #expect(ManifoldRuntimeEnvironment.appSupportRootURL(env: env)?.standardizedFileURL.path == testHome
            .appendingPathComponent("app-support", isDirectory: true)
            .standardizedFileURL.path)
        #expect(ManifoldRuntimeEnvironment.diagnosticsDirectoryURL(env: env)?.standardizedFileURL.path == testHome
            .appendingPathComponent("diagnostics", isDirectory: true)
            .standardizedFileURL.path)
    }

    @Test("SingleShotThrowingContinuation ignores duplicate resumes")
    func singleShotContinuationIgnoresDuplicateResumes() async throws {
        let value: String = try await withCheckedThrowingContinuation { continuation in
            let singleShot = SingleShotThrowingContinuation<String>(continuation)
            #expect(singleShot.resume(returning: "first"))
            #expect(!singleShot.resume(throwing: NSError(domain: "test", code: 1)))
        }

        #expect(value == "first")
    }

    @Test("MCP failure store persists typed failures")
    func mcpFailureStorePersistsTypedFailures() async throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let store = try MCPFailureEventStore(db: db)
        let event = MCPFailureEvent(
            requestID: "req-test",
            agent: "codex",
            clientName: "manifold-mcp",
            toolName: "list_files",
            boundary: .xpcClient,
            phase: .reply,
            classification: .xpcConnectionInvalidated,
            isRetryable: true,
            redactedMessage: "Transport closed",
            connectionID: "conn-test",
            runtimeGeneration: 3,
            grantID: "grant-test",
            sourceIDs: ["src-1"],
            durationMS: 12
        )

        try await store.record(event)
        let recent = try await store.recent(limit: 10)
        let first = try #require(recent.first)

        #expect(first.requestID == "req-test")
        #expect(first.agent == "codex")
        #expect(first.classification == .xpcConnectionInvalidated)
        #expect(first.isRetryable)
        #expect(first.sourceIDs == ["src-1"])
    }

    @Test("RuntimeSupervisor allows one automatic restart per issue")
    func runtimeSupervisorAllowsOneAutomaticRestartPerIssue() {
        var supervisor = RuntimeSupervisor()

        #expect(supervisor.markStarting() == .starting(generation: 1))
        #expect(supervisor.markHealthy() == .healthy(generation: 1))
        #expect(supervisor.markDegraded(issue: "xpc_interrupted") == .degraded(generation: 1, issue: "xpc_interrupted"))
        let firstRestartSlot = supervisor.consumeAutomaticRestartSlot()
        let secondRestartSlot = supervisor.consumeAutomaticRestartSlot()
        #expect(firstRestartSlot)
        #expect(!secondRestartSlot)

        #expect(supervisor.markRestarting(reason: .xpcInterrupted) == .restarting(generation: 2, reason: .xpcInterrupted))
        #expect(supervisor.markFailed(issue: "health_timeout") == .failed(generation: 2, issue: "health_timeout"))
        #expect(supervisor.restartBackoffSeconds == 1)
    }
}
