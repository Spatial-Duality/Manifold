// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("DiagnosticsRecorder")
struct DiagnosticsRecorderTests {

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-diagnostics-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Recorder writes per-launch JSONL files isolated by process and launch UUID")
    func perLaunchFileIsolation() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let appLaunch = "11111111-1111-1111-1111-111111111111"
        let agentLaunch = "22222222-2222-2222-2222-222222222222"

        let app = DiagnosticsRecorder(process: .app, directory: dir, launchUUID: appLaunch)
        let agent = DiagnosticsRecorder(process: .agent, directory: dir, launchUUID: agentLaunch)

        app.record(.appLaunch)
        agent.record(.runtimeRegistrationAttempted)

        // Allow the internal queue to drain.
        try await Task.sleep(for: .milliseconds(150))

        let appFile = dir.appendingPathComponent("app-\(appLaunch).jsonl")
        let agentFile = dir.appendingPathComponent("agent-\(agentLaunch).jsonl")

        #expect(FileManager.default.fileExists(atPath: appFile.path))
        #expect(FileManager.default.fileExists(atPath: agentFile.path))

        let appText = try String(contentsOf: appFile, encoding: .utf8)
        let agentText = try String(contentsOf: agentFile, encoding: .utf8)
        #expect(appText.contains("\"appLaunch\""))
        #expect(agentText.contains("\"runtimeRegistrationAttempted\""))
        // Cross-process isolation: agent file must not carry app events.
        #expect(!agentText.contains("\"appLaunch\""))
        #expect(!appText.contains("\"runtimeRegistrationAttempted\""))
    }

    @Test("Records are line-delimited and round-trip through readAllRecords")
    func readAllRecordsRoundTrip() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let recorder = DiagnosticsRecorder(process: .app, directory: dir, launchUUID: "abc")

        recorder.record(.appLaunch)
        recorder.record(.runtimeRegistrationFailedLaunchctlBootstrap(code: 5))
        recorder.record(.versionMismatchRestart(appVersion: "0.4.0", runtimeVersion: "0.3.9"))

        try await Task.sleep(for: .milliseconds(150))

        let records = recorder.readAllRecords()
        #expect(records.count == 3)

        let bootstrap = records.first { $0.name == "runtimeRegistrationFailedLaunchctlBootstrap" }
        #expect(bootstrap?.payload.bootstrapCode == 5)
        let mismatch = records.first { $0.name == "versionMismatchRestart" }
        #expect(mismatch?.payload.appVersion == "0.4.0")
        #expect(mismatch?.payload.runtimeVersion == "0.3.9")
    }

    @Test("Agent state marker round-trips and survives recorder recreation")
    func agentStateMarkerRoundTrip() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let agent = DiagnosticsRecorder(process: .agent, directory: dir, launchUUID: "boot-1")
        agent.recordAgentBoot()
        // A fresh app-side recorder should be able to read the marker.
        let app = DiagnosticsRecorder(process: .app, directory: dir, launchUUID: "app-1")
        let marker = app.readAgentState()
        #expect(marker?.state == .running)
        #expect(marker?.launchUUID == "boot-1")

        agent.recordAgentCleanShutdown()
        let marker2 = app.readAgentState()
        #expect(marker2?.state == .cleanShutdown)
    }

    @Test("deleteAll wipes the directory but leaves the recorder usable")
    func deleteAllResets() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let recorder = DiagnosticsRecorder(process: .app, directory: dir, launchUUID: "one")
        recorder.record(.appLaunch)
        try await Task.sleep(for: .milliseconds(100))

        try recorder.deleteAll()
        let firstReadAfterDelete = recorder.readAllRecords()
        #expect(firstReadAfterDelete.isEmpty)

        recorder.record(.runtimeRegistrationSucceeded)
        try await Task.sleep(for: .milliseconds(100))
        let secondRead = recorder.readAllRecords()
        #expect(secondRead.count == 1)
        #expect(secondRead.first?.name == "runtimeRegistrationSucceeded")
    }

    @Test("Limits drop oldest files when count exceeds maxFiles")
    func limitsEnforceFileCount() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        // Write 5 jsonl files manually then trigger enforcement via a write.
        for i in 0..<5 {
            let url = dir.appendingPathComponent("app-old-\(i).jsonl")
            try "{}".write(to: url, atomically: true, encoding: .utf8)
            // Stagger mtimes so "oldest" is deterministic.
            let date = Date().addingTimeInterval(TimeInterval(i))
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }

        let recorder = DiagnosticsRecorder(
            process: .app, directory: dir, launchUUID: "current",
            limits: .init(maxFiles: 3, maxBytesPerFile: 256_000)
        )
        recorder.record(.appLaunch)
        try await Task.sleep(for: .milliseconds(150))

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
        #expect(files.count <= 3)
    }
}
