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

    @Test("Mail account reset exports context and removes archive storage")
    func mailAccountResetExportsContextAndRemovesArchiveStorage() async throws {
        let (runtime, tempDir) = try makeRuntime()
        defer { cleanup(tempDir) }

        let account = try runtime.emailStore.addEmailAccount(
            displayName: "Reset Mail",
            providerType: EmailProvider.icloud.rawValue,
            server: "imap.mail.me.com",
            port: 993,
            username: "person@icloud.com",
            authType: "app_password"
        )
        let archive = try MailArchiveStore(rootURL: runtime.mailArchiveRoot)
        let messageData = Data("Subject: Runtime Reset\r\n\r\nLocal mail body.".utf8)
        let archived = try archive.storeMessage(accountID: account.accountID, plaintext: messageData)
        try runtime.emailStore.recordMailBlob(archived)
        try runtime.emailStore.upsertEmailMessage(
            emailID: "runtime-reset-mail",
            accountID: account.accountID,
            mailbox: "INBOX",
            sender: "Sender <sender@example.com>",
            senderEmail: "sender@example.com",
            senderDomain: "example.com",
            recipients: "person@icloud.com",
            subject: "Runtime Reset",
            receivedAt: ISO8601DateFormatter.shared.string(from: Date()),
            emlPath: archived.manifestURL.path,
            sizeBytes: messageData.count,
            preview: "Local mail body.",
            canonicalBlobCID: archived.contentID
        )
        try runtime.emailStore.recordMailAccessAuditEvent(
            accountID: account.accountID,
            emailID: "runtime-reset-mail",
            agentID: TargetApp.codex.rawValue,
            sessionID: "session-runtime",
            accessKind: "search",
            policyGrantID: "grant-runtime",
            detailsRedacted: "query=reset"
        )
        let tempAccountRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManifoldMailSync", isDirectory: true)
            .appendingPathComponent(account.accountID, isDirectory: true)
        try FileManager.default.createDirectory(at: tempAccountRoot, withIntermediateDirectories: true)
        try Data("staged".utf8).write(to: tempAccountRoot.appendingPathComponent("message.rfc822"))

        let result = try await runtime.removeEmailAccountAndLocalData(accountID: account.accountID)

        let history = try String(contentsOfFile: result.contextArchivePath, encoding: .utf8)
        let accountArchiveRoot = runtime.mailArchiveRoot
            .appendingPathComponent("v2/accounts", isDirectory: true)
            .appendingPathComponent(account.accountID, isDirectory: true)
        #expect(history.contains("access_kind=search"))
        #expect(history.contains("details_redacted=query=reset"))
        #expect(!history.contains("Local mail body."))
        #expect(try runtime.emailStore.emailAccount(id: account.accountID)?.accountID == nil)
        #expect(!FileManager.default.fileExists(atPath: accountArchiveRoot.path))
        #expect(!FileManager.default.fileExists(atPath: tempAccountRoot.path))
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
