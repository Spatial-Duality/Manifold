// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
@testable import ManifoldKit
@testable import ManifoldRuntime

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
        let emailRuleStore: EmailRuleStore
        let workBlockStore: WorkBlockStore
        let fileVisibilityOverrideStore: FileVisibilityOverrideStore
        let approvalQueue: ApprovalQueue
        let standingWriteApprovalStore: StandingWriteApprovalStore
        let runtimeSettingsStore: RuntimeSettingsStore
        let exposureStore: ExposureStore
        let capabilityHandleStore: CapabilityHandleStore
        let ruleStore: RuleStore
        let bridge: ManifoldBridge
        let tempDir: URL
        let connectionID: String
    }

    func makeHarness(targetApp: TargetApp = .cowork) throws -> Harness {
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
        let emailRuleStore = EmailRuleStore(db: db, policyStore: policyStore)
        let workBlockStore = WorkBlockStore(db: db)
        let fileVisibilityOverrideStore = FileVisibilityOverrideStore(db: db)
        let approvalQueue = ApprovalQueue(db: db)
        let standingWriteApprovalStore = StandingWriteApprovalStore(db: db)
        let runtimeSettingsStore = RuntimeSettingsStore(db: db)
        let exposureStore = ExposureStore(db: db)
        let capabilityHandleStore = try CapabilityHandleStore(db: db)
        let ruleStore = RuleStore(db: db)
        let connectionID = "standing-test-\(UUID().uuidString)"

        let bridge = ManifoldBridge(
            db: db,
            auditStore: auditStore,
            contentStore: contentStore,
            grantStore: grantStore,
            emailStore: emailStore,
            snapshotStore: snapshotStore,
            artifactIndex: artifactIndex,
            policyStore: policyStore,
            runtimeSettingsStore: runtimeSettingsStore,
            emailRuleStore: emailRuleStore,
            workBlockStore: workBlockStore,
            fileVisibilityOverrideStore: fileVisibilityOverrideStore,
            approvalQueue: approvalQueue,
            standingWriteApprovalStore: standingWriteApprovalStore,
            exposureStore: exposureStore,
            capabilityHandleStore: capabilityHandleStore,
            ruleStore: ruleStore,
            targetApp: targetApp,
            connectionID: connectionID
        )

        return Harness(
            db: db, contentStore: contentStore, snapshotStore: snapshotStore,
            auditStore: auditStore, grantStore: grantStore, emailStore: emailStore,
            artifactIndex: artifactIndex, policyStore: policyStore, emailRuleStore: emailRuleStore,
            workBlockStore: workBlockStore, fileVisibilityOverrideStore: fileVisibilityOverrideStore,
            approvalQueue: approvalQueue,
            standingWriteApprovalStore: standingWriteApprovalStore,
            runtimeSettingsStore: runtimeSettingsStore,
            exposureStore: exposureStore, capabilityHandleStore: capabilityHandleStore,
            ruleStore: ruleStore,
            bridge: bridge, tempDir: tempDir,
            connectionID: connectionID
        )
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    func metadataJSON(_ metadata: String?) -> [String: String] {
        guard let metadata,
              let data = metadata.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return json
    }

    /// Create a source directory with test files and register it.
    func createAndRegisterSource(harness: Harness, name: String) async throws -> String {
        let sourceDir = harness.tempDir.appendingPathComponent("sources/\(name)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("hello world".utf8).write(to: sourceDir.appendingPathComponent("README.md"))
        try FileManager.default.createDirectory(at: sourceDir.appendingPathComponent("src"), withIntermediateDirectories: true)
        try Data("func main() {}".utf8).write(to: sourceDir.appendingPathComponent("src/main.swift"))
        return try await harness.grantStore.addSource(displayName: name, rootPath: sourceDir.path)
    }

    func createEmail(
        harness: Harness,
        id: String,
        sender: String,
        senderEmail: String,
        senderDomain: String,
        subject: String,
        body: String
    ) throws {
        let emlURL = harness.tempDir.appendingPathComponent("emails/\(id).eml")
        try FileManager.default.createDirectory(at: emlURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(body.utf8).write(to: emlURL)
        let account = try harness.emailStore.addEmailAccount(
            displayName: "Test Account \(id)",
            providerType: "other",
            server: nil,
            port: nil,
            username: "user@example.com"
        )
        try harness.emailStore.upsertEmailMessage(
            emailID: id,
            accountID: account.accountID,
            mailbox: "Inbox",
            sender: sender,
            senderEmail: senderEmail,
            senderDomain: senderDomain,
            recipients: "user@example.com",
            subject: subject,
            receivedAt: ISO8601DateFormatter.shared.string(from: Date()),
            emlPath: emlURL.path,
            sizeBytes: body.utf8.count,
            preview: body
        )
    }

    func materializeGrant(harness: Harness, grant: GrantRecord) async throws {
        let grantSources = try await harness.grantStore.grantSources(grantID: grant.grantID)
        var inputs: [MaterializationEngine.MaterializationSource] = []
        for grantSource in grantSources {
            guard let source = try await harness.grantStore.source(id: grantSource.sourceID) else { continue }
            inputs.append(MaterializationEngine.MaterializationSource(
                source: source,
                mountName: grantSource.mountName
            ))
        }
        let results = try MaterializationEngine.materialize(
            grantID: grant.grantID,
            sources: inputs,
            materializationRoot: grant.materializationRoot
        )
        for result in results {
            try await harness.grantStore.setBaselineHash(
                grantID: grant.grantID,
                sourceID: result.sourceID,
                hash: result.manifestHash
            )
        }
    }

    // MARK: - Status Tests

    @Test("Status shows no access when a block-by-default agent has no standing grants")
    func emptyPolicyStatus() async throws {
        let h = try makeHarness(targetApp: .codex)
        defer { cleanup(h.tempDir) }

        let status = await h.bridge.getStatus()
        #expect(status.active == false)
        #expect(status.message.contains("No access configured"))
    }

    @Test("Denied status does not reveal configured source names")
    func deniedStatusDoesNotRevealSourceNames() async throws {
        let h = try makeHarness(targetApp: .codex)
        defer { cleanup(h.tempDir) }

        _ = try await createAndRegisterSource(harness: h, name: "SecretDocs")

        let status = await h.bridge.getStatus()
        #expect(status.active == false)
        #expect(status.sources.isEmpty)
        #expect(status.pausedSources.isEmpty)
        #expect(status.message.contains("SecretDocs") == false)
    }

    @Test("Claude default email policy counts as standing access even before explicit rules")
    func defaultAllowEmailStatus() async throws {
        let h = try makeHarness(targetApp: .cowork)
        defer { cleanup(h.tempDir) }

        let status = await h.bridge.getStatus()
        #expect(status.active)
        #expect(status.message.contains("standing access"))
        #expect(status.message.contains("0 emails"))
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

    @Test("Standing capability handles are scoped by source lineage")
    func standingCapabilityHandleScope() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let allowedSourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        let blockedSourceID = try await createAndRegisterSource(harness: h, name: "OtherApp")
        try await h.policyStore.addSource(allowedSourceID, to: .cowork)

        let allowedHandle = try await h.capabilityHandleStore.save(ValueHandle(
            origin: "standing:myapp",
            sensitivity: "internal",
            trustLevel: "trusted",
            allowedSinks: ["model_context"],
            grantID: nil,
            lineage: [LineageRef(kind: "source", id: allowedSourceID)]
        ))
        let blockedHandle = try await h.capabilityHandleStore.save(ValueHandle(
            origin: "standing:otherapp",
            sensitivity: "internal",
            trustLevel: "trusted",
            allowedSinks: ["model_context"],
            grantID: nil,
            lineage: [LineageRef(kind: "source", id: blockedSourceID)]
        ))

        let allowed = try await h.bridge.checkCapabilityFlow(handleID: allowedHandle.handleID, sink: "model_context")
        let denied = try await h.bridge.checkCapabilityFlow(handleID: blockedHandle.handleID, sink: "model_context")

        #expect(allowed.contains(#""allowed":true"#))
        #expect(denied.contains(#""allowed":false"#))
        #expect(denied.contains("Capability handle is unavailable in the current session scope."))
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

    @Test("Manual session mode denies standing access without active gateway")
    func manualSessionModeRequiresActiveGateway() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)
        try await h.runtimeSettingsStore.setSessionAccessMode(.manualRequiresSession)

        do {
            _ = try await h.bridge.listFiles()
            Issue.record("Expected manual session mode to deny standing file access")
        } catch let error as ManifoldMCPError {
            if case .noAccessConfigured = error {
                // Expected
            } else {
                Issue.record("Expected noAccessConfigured, got \(error)")
            }
        }
    }

    @Test("Standing access writes shared files directly with reversible snapshots")
    func standingWriteDirectlyVersionsOriginal() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)

        let result = try await h.bridge.writeFile(path: "myapp/README.md", content: "updated")
        switch result {
        case .written(let message, let path):
            #expect(path == "myapp/README.md")
            #expect(message.contains("original folder"))
        case .escalationRequired:
            Issue.record("Standing access should write visible shared files directly")
        }

        let fileURL = h.tempDir.appendingPathComponent("sources/MyApp/README.md")
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "updated")

        let snapshots = try await h.snapshotStore.fileHistory(filePath: "myapp/README.md")
        #expect(snapshots.contains { $0.isBaseline && $0.source == "manifold" })
        #expect(snapshots.contains { !$0.isBaseline && $0.source == "standing_write_auto" })

        let pending = try await h.approvalQueue.pending()
        #expect(pending.isEmpty)
    }

    @Test("Explicit file deny hides a file inside an otherwise shared source")
    func explicitFileDenyHidesSharedFile() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)
        try await h.fileVisibilityOverrideStore.setOverride(
            agent: .cowork,
            sourceID: sourceID,
            relativePath: "README.md",
            isDirectory: false,
            decision: .deny
        )

        let files = try await h.bridge.listFiles()
        #expect(!files.contains(where: { $0.path == "myapp/README.md" }))

        do {
            _ = try await h.bridge.readFile(path: "myapp/README.md")
            Issue.record("Expected explicitly denied file to be hidden")
        } catch let error as ManifoldMCPError {
            if case .fileNotFound(let hiddenPath) = error {
                #expect(hiddenPath.contains("myapp/README.md"))
            } else {
                Issue.record("Expected fileNotFound for hidden file, got \(error)")
            }
        }
    }

    @Test("Explicit file allow exposes one file from a source that is not in default scope")
    func explicitFileAllowExposesUnsharedFile() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "PrivateDocs")
        try await h.fileVisibilityOverrideStore.setOverride(
            agent: .cowork,
            sourceID: sourceID,
            relativePath: "README.md",
            isDirectory: false,
            decision: .allow
        )

        let files = try await h.bridge.listFiles()
        #expect(files.contains(where: { $0.path == "privatedocs/README.md" }))
        #expect(!files.contains(where: { $0.path == "privatedocs/src/main.swift" }))

        let content = try await h.bridge.readFile(path: "privatedocs/README.md")
        #expect(content == "hello world")

        do {
            _ = try await h.bridge.readFile(path: "privatedocs/src/main.swift")
            Issue.record("Expected only the explicitly allowed file to be visible")
        } catch let error as ManifoldMCPError {
            if case .fileNotFound(let hiddenPath) = error {
                #expect(hiddenPath.contains("privatedocs/src/main.swift"))
            } else {
                Issue.record("Expected fileNotFound for non-allowed file, got \(error)")
            }
        }

        do {
            _ = try await h.bridge.fileInfo(path: "privatedocs/src/main.swift")
            Issue.record("Expected file_info to hide non-allowed file metadata")
        } catch let error as ManifoldMCPError {
            if case .fileNotFound(let hiddenPath) = error {
                #expect(hiddenPath.contains("privatedocs/src/main.swift"))
            } else {
                Issue.record("Expected fileNotFound for non-allowed file_info, got \(error)")
            }
        }
    }

    @Test("Removed source with stale allow override is never exposed")
    func removedSourceAllowOverrideIsHidden() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "RemovedDocs")
        try await h.fileVisibilityOverrideStore.setOverride(
            agent: .cowork,
            sourceID: sourceID,
            relativePath: "README.md",
            isDirectory: false,
            decision: .allow
        )
        try await h.grantStore.removeSource(sourceID: sourceID)

        let files = try await h.bridge.listFiles()
        #expect(!files.contains(where: { $0.path == "removeddocs/README.md" }))

        do {
            _ = try await h.bridge.readFile(path: "removeddocs/README.md")
            Issue.record("Expected removed source to be hidden even with a stale allow override")
        } catch let error as ManifoldMCPError {
            if case .fileNotFound(let hiddenPath) = error {
                #expect(hiddenPath.contains("removeddocs/README.md"))
            } else {
                Issue.record("Expected fileNotFound for removed source, got \(error)")
            }
        }
    }

    @Test("Runtime revocation clears stale access before the next MCP call")
    func runtimeRevocationClearsOverridesImmediately() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-runtime-revoke-\(UUID().uuidString)")
        defer { cleanup(tempDir) }

        let sourceDir = tempDir.appendingPathComponent("sources/Realtime")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("hello world".utf8).write(to: sourceDir.appendingPathComponent("README.md"))
        try FileManager.default.createDirectory(at: sourceDir.appendingPathComponent("src"), withIntermediateDirectories: true)
        try Data("func main() {}".utf8).write(to: sourceDir.appendingPathComponent("src/main.swift"))

        let runtime = try ManifoldRuntime(storeURL: tempDir.appendingPathComponent("store"))
        let sourceID = try await runtime.grantStore.addSource(
            displayName: "Realtime",
            rootPath: sourceDir.path
        )
        try await runtime.setSourceScope(sourceID: sourceID, agent: .cowork, inScope: true)
        try await runtime.fileVisibilityOverrideStore.setOverride(
            agent: .cowork,
            sourceID: sourceID,
            relativePath: "README.md",
            isDirectory: false,
            decision: .allow
        )
        try await runtime.standingWriteApprovalStore.grantDefault(agent: .cowork, sourceID: sourceID)

        let bridge = await runtime.bridge(
            for: "runtime-revoke-\(UUID().uuidString)",
            targetApp: .cowork,
            version: "test"
        )
        let before = try await bridge.listFiles()
        #expect(before.contains(where: { $0.path == "realtime/README.md" }))

        _ = try await runtime.approvalQueue.submit(
            connectionID: "runtime-revoke-test",
            agent: TargetApp.cowork.rawValue,
            path: "realtime/README.md",
            action: "write",
            kind: .standingWrite,
            sourceID: sourceID,
            mountName: "realtime",
            relativePath: "README.md"
        )
        #expect(try await runtime.approvalQueue.pending().count == 1)

        try await runtime.setSourceScope(sourceID: sourceID, agent: .cowork, inScope: false)

        let policy = try await runtime.policyStore.policy(for: .cowork)
        #expect(!policy.allowedSourceIDs.contains(sourceID))
        #expect(try await runtime.fileVisibilityOverrideStore.overrides(agent: .cowork).isEmpty)
        #expect(try await runtime.standingWriteApprovalStore.hasDefaultGrant(agent: .cowork, sourceID: sourceID) == false)
        #expect(try await runtime.approvalQueue.pending().isEmpty)

        let after = try await bridge.listFiles()
        #expect(!after.contains(where: { $0.path == "realtime/README.md" }))
        #expect(!after.contains(where: { $0.path == "realtime/src/main.swift" }))
    }

    /// Symlink containment: a source folder may contain a symlink that
    /// points outside the source root. The AI must NOT see those files —
    /// the runtime resolves each entry's standardized URL and only
    /// admits paths that hasPrefix the source's basePath. Verifies that
    /// guard end-to-end for both list_files and read_file.
    @Test("Symlinks pointing outside the source root are filtered out")
    func symlinksOutsideSourceAreHidden() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        // Build a target file *outside* any source folder. This is the
        // file the symlink would expose if containment was broken.
        let secretRoot = h.tempDir.appendingPathComponent("outside-secret")
        try FileManager.default.createDirectory(at: secretRoot, withIntermediateDirectories: true)
        let secretFile = secretRoot.appendingPathComponent("secret.txt")
        try Data("classified".utf8).write(to: secretFile)

        // Build the source folder and drop a symlink inside it pointing
        // at the outside-secret file.
        let sourceID = try await createAndRegisterSource(harness: h, name: "Sneaky")
        let sourceDir = h.tempDir.appendingPathComponent("sources/Sneaky")
        let symlinkURL = sourceDir.appendingPathComponent("escape-hatch.txt")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: secretFile)

        try await h.policyStore.addSource(sourceID, to: .cowork)

        // list_files must NOT include the symlinked-outside file. Inner
        // README/main.swift remain visible — they live inside the source.
        let files = try await h.bridge.listFiles()
        #expect(files.contains(where: { $0.path == "sneaky/README.md" }))
        #expect(!files.contains(where: { $0.path == "sneaky/escape-hatch.txt" }))
        #expect(!files.contains(where: { $0.path.contains("outside-secret") }))

        // read_file via the symlink path must also fail. Either
        // .invalidPath ("symlinks not allowed in governed paths" — the
        // upstream guard) or .fileNotFound (the path-prefix containment
        // check downstream) is acceptable; both are "denied".
        do {
            _ = try await h.bridge.readFile(path: "sneaky/escape-hatch.txt")
            Issue.record("Expected escape-hatch.txt to be unreadable")
        } catch let error as ManifoldMCPError {
            switch error {
            case .fileNotFound, .invalidPath:
                break // expected — containment held
            default:
                Issue.record("Expected fileNotFound or invalidPath for symlink escape, got \(error)")
            }
        }
    }

    /// Regression for the instant-propagation contract surfaced 2026-04-29.
    /// When the user toggles a sharing checkbox the AI's NEXT MCP call
    /// must reflect the new state — no waiting on the 10-second list cache
    /// or any other staleness window. listFilesFromOriginals keys its
    /// cache on (mountPaths, allowedSourceIDs, override signatures), so
    /// a policy mutation flips the key and forces a fresh enumeration.
    @Test("Toggling source scope is reflected on the very next list_files call")
    func scopeToggleReflectsImmediately() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "Realtime")

        // Cowork has default standing email access, so listFiles always
        // returns; empty mounts == empty list. Asserting on file count
        // exercises the cache-key invalidation path instead of the
        // throw-noAccessConfigured path.
        let cold = try await h.bridge.listFiles()
        #expect(cold.isEmpty)

        // User toggles scope on. NEXT call must see the source.
        try await h.policyStore.addSource(sourceID, to: .cowork)
        let afterAdd = try await h.bridge.listFiles()
        #expect(afterAdd.contains(where: { $0.path == "realtime/README.md" }))
        #expect(afterAdd.contains(where: { $0.path == "realtime/src/main.swift" }))

        // User toggles scope off. NEXT call must drop the files.
        try await h.policyStore.removeSource(sourceID, from: .cowork)
        let afterRemove = try await h.bridge.listFiles()
        #expect(afterRemove.isEmpty)

        // Per-file allow override on the unscoped source. NEXT call must
        // surface only that one file — the cache key picks up the new
        // override signature and re-enumerates.
        try await h.fileVisibilityOverrideStore.setOverride(
            agent: .cowork,
            sourceID: sourceID,
            relativePath: "README.md",
            isDirectory: false,
            decision: .allow
        )
        let afterOverride = try await h.bridge.listFiles()
        #expect(afterOverride.contains(where: { $0.path == "realtime/README.md" }))
        #expect(!afterOverride.contains(where: { $0.path == "realtime/src/main.swift" }))

        // Clear the override. NEXT call must drop everything again.
        try await h.fileVisibilityOverrideStore.clearOverrides(
            agent: .cowork,
            sourceID: sourceID
        )
        let afterClear = try await h.bridge.listFiles()
        #expect(afterClear.isEmpty)
    }

    @Test("Standing writes no longer require one-shot approval")
    func standingWriteOnceApprovalIsNotRequired() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)

        let write = try await h.bridge.writeFile(path: "myapp/README.md", content: "approved once")
        switch write {
        case .written(_, let path):
            #expect(path == "myapp/README.md")
        case .escalationRequired:
            Issue.record("Expected shared-source write to succeed without one-shot approval")
        }

        let fileURL = h.tempDir.appendingPathComponent("sources/MyApp/README.md")
        let updated = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(updated == "approved once")

        let snapshots = try await h.snapshotStore.fileHistory(filePath: "myapp/README.md")
        #expect(snapshots.count == 2)
        #expect(snapshots.contains { $0.isBaseline && $0.source == "manifold" })
        #expect(snapshots.contains { !$0.isBaseline && $0.source == "standing_write_auto" })

        let auditEntries = try await h.auditStore.recentEntries(limit: 10)
        let writeEntry = try #require(auditEntries.first(where: { $0.filePath == "myapp/README.md" }))
        let metadata = metadataJSON(writeEntry.metadata)
        #expect(metadata["access_mode"] == "standing_write_auto")

        let secondAttempt = try await h.bridge.writeFile(path: "myapp/README.md", content: "needs approval again")
        switch secondAttempt {
        case .written(_, let path):
            #expect(path == "myapp/README.md")
        case .escalationRequired:
            Issue.record("Expected subsequent shared-source write to succeed without approval")
        }
    }

    @Test("Standing writes are allowed for all visible shared sources")
    func standingWriteDefaultApprovalIsNotRequired() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sharedSourceID = try await createAndRegisterSource(harness: h, name: "Shared")
        let secondSourceID = try await createAndRegisterSource(harness: h, name: "Other")
        try await h.policyStore.addSource(sharedSourceID, to: .cowork)
        try await h.policyStore.addSource(secondSourceID, to: .cowork)

        let writeInShared = try await h.bridge.writeFile(path: "shared/src/main.swift", content: "func main() { print(\"hi\") }")
        switch writeInShared {
        case .written(_, let path):
            #expect(path == "shared/src/main.swift")
        case .escalationRequired:
            Issue.record("Expected shared source write to succeed")
        }

        let writeInOther = try await h.bridge.writeFile(path: "other/README.md", content: "other source change")
        switch writeInOther {
        case .written(_, let path):
            #expect(path == "other/README.md")
        case .escalationRequired:
            Issue.record("Expected second shared source write to succeed")
        }

        let reloadedStore = StandingWriteApprovalStore(db: h.db)
        #expect(try await reloadedStore.hasDefaultGrant(agent: .cowork, sourceID: sharedSourceID) == false)

        try await h.policyStore.removeSource(sharedSourceID, from: .cowork)
        try await h.standingWriteApprovalStore.removeGrants(agent: .cowork, sourceID: sharedSourceID)
        #expect((try await h.standingWriteApprovalStore.hasDefaultGrant(agent: .cowork, sourceID: sharedSourceID)) == false)
    }

    @Test("Binary writes default to original shared folders with snapshots")
    func binaryWriteDefaultsToOriginalFolder() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)

        let bytes = Data([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34])
        let result = try await h.bridge.writeBinaryFile(
            path: "myapp/report.pdf",
            contentBase64: bytes.base64EncodedString(),
            mimeType: "application/pdf",
            intent: AccessIntent(summary: "Create a governed test PDF.", details: nil)
        )

        switch result {
        case .written(let message, let path):
            #expect(path == "myapp/report.pdf")
            #expect(message.contains("original folder"))
        case .escalationRequired:
            Issue.record("Binary write should succeed against the original shared folder")
        }

        let originalURL = h.tempDir.appendingPathComponent("sources/MyApp/report.pdf")
        #expect(try Data(contentsOf: originalURL) == bytes)

        let snapshots = try await h.snapshotStore.fileHistory(filePath: "myapp/report.pdf")
        #expect(snapshots.contains { $0.source == "standing_write_auto" })
        #expect(try await h.workBlockStore.activeBlock(for: .cowork) == nil)
    }

    @Test("File write rules block governed standing writes")
    func fileWriteRuleBlocksStandingWrite() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)
        try await h.ruleStore.upsert(RuleRecord(
            name: "Block README writes",
            explanation: "README files are read-only for AI writes.",
            scope: .file,
            matcher: .pathGlob("myapp/README.md"),
            action: .deny,
            agents: [.cowork]
        ))

        do {
            _ = try await h.bridge.writeFile(path: "myapp/README.md", content: "blocked")
            Issue.record("Expected file write rule to block the write")
        } catch let error as ManifoldMCPError {
            if case .ruleDenied(let ruleName, _) = error {
                #expect(ruleName == "Block README writes")
            } else {
                Issue.record("Expected ruleDenied, got \(error)")
            }
        }

        let fileURL = h.tempDir.appendingPathComponent("sources/MyApp/README.md")
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "hello world")
    }

    @Test("Standing writes reject unknown mount prefixes")
    func standingWriteRejectsUnknownMountPrefix() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "HR")
        try await h.policyStore.addSource(sourceID, to: .cowork)

        do {
            _ = try await h.bridge.writeFile(path: "sort/foo.txt", content: "misplaced")
            Issue.record("Expected unknown mount prefix to be rejected")
        } catch let error as ManifoldMCPError {
            if case .invalidPath(let message) = error {
                #expect(message.contains("mount-prefixed path"))
            } else {
                Issue.record("Expected invalidPath, got \(error)")
            }
        }

        let misplaced = h.tempDir.appendingPathComponent("sources/HR/sort/foo.txt")
        #expect(!FileManager.default.fileExists(atPath: misplaced.path))
    }

    @Test("annotate_pdf rejects non-PDF paths before parsing")
    func annotatePDFRejectsNonPDFExtension() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)
        let sourceDir = h.tempDir.appendingPathComponent("sources/MyApp")
        try Data("%PDF-1.4\n".utf8).write(to: sourceDir.appendingPathComponent("not-a-pdf.txt"))

        do {
            _ = try await h.bridge.annotatePDF(path: "myapp/not-a-pdf.txt")
            Issue.record("Expected annotate_pdf to reject non-PDF extension")
        } catch let error as ManifoldMCPError {
            if case .invalidPath(let message) = error {
                #expect(message.contains(".pdf"))
            } else {
                Issue.record("Expected invalidPath, got \(error)")
            }
        }
    }

    @Test("Default writes prefer originals even when an old draft work block is active")
    func defaultWritesBypassActiveDraftWorkspace() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)

        let draftBytes = Data([0x25, 0x50, 0x44, 0x46])
        _ = try await h.bridge.writeBinaryFile(
            path: "myapp/draft.pdf",
            contentBase64: draftBytes.base64EncodedString(),
            mimeType: "application/pdf",
            intent: AccessIntent(summary: "Create a draft file.", details: nil),
            writeMode: "draft_workspace"
        )
        let block = try #require(try await h.workBlockStore.activeBlock(for: .cowork))
        let grant = try #require(try await h.grantStore.grant(id: block.grantID))

        let write = try await h.bridge.writeFile(path: "myapp/README.md", content: "direct update")
        switch write {
        case .written(let message, let path):
            #expect(path == "myapp/README.md")
            #expect(message.contains("original folder"))
        case .escalationRequired:
            Issue.record("Default write should bypass the active draft workspace")
        }

        let originalURL = h.tempDir.appendingPathComponent("sources/MyApp/README.md")
        #expect(try String(contentsOf: originalURL, encoding: .utf8) == "direct update")

        let draftURL = URL(fileURLWithPath: grant.materializationRoot)
            .appendingPathComponent("myapp/README.md")
        #expect(try String(contentsOf: draftURL, encoding: .utf8) == "hello world")

        let snapshots = try await h.snapshotStore.fileHistory(filePath: "myapp/README.md")
        #expect(snapshots.contains { $0.source == "standing_write_auto" })
    }

    @Test("Text write tool refuses binary-looking file extensions")
    func textWriteRefusesBinaryExtensions() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)
        try await h.standingWriteApprovalStore.grantDefault(agent: .cowork, sourceID: sourceID)

        do {
            _ = try await h.bridge.writeFile(path: "myapp/report.pdf", content: "JVBERi0xLjQ=")
            Issue.record("Expected write_file to reject PDF paths")
        } catch let error as ManifoldMCPError {
            if case .invalidPath(let message) = error {
                #expect(message.contains("write_file is UTF-8 text only"))
                #expect(message.contains("annotate_pdf"))
                #expect(message.contains("write_binary_file"))
            } else {
                Issue.record("Expected invalidPath for binary extension, got \(error)")
            }
        }

        let originalURL = h.tempDir.appendingPathComponent("sources/MyApp/report.pdf")
        #expect(!FileManager.default.fileExists(atPath: originalURL.path))
    }

    @Test("Expected before hash mismatch blocks direct standing writes")
    func expectedBeforeHashMismatchBlocksDirectWrite() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)
        try await h.standingWriteApprovalStore.grantDefault(agent: .cowork, sourceID: sourceID)

        do {
            _ = try await h.bridge.writeFile(
                path: "myapp/README.md",
                content: "should not land",
                expectedBeforeHash: String(repeating: "0", count: 64)
            )
            Issue.record("Expected a hash mismatch to reject the write")
        } catch let error as ManifoldMCPError {
            if case .invalidPath(let message) = error {
                #expect(message.contains("Hash mismatch"))
            } else {
                Issue.record("Expected invalidPath hash mismatch, got \(error)")
            }
        }

        let fileURL = h.tempDir.appendingPathComponent("sources/MyApp/README.md")
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "hello world")
    }

    @Test("Read file records access decision and exposure")
    func readFileRecordsDecisionAndExposure() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)

        let content = try await h.bridge.readFile(path: "myapp/README.md")
        #expect(content == "hello world")

        let decisions = try await h.exposureStore.decisions(connectionID: h.connectionID, limit: 10)
        #expect(decisions.contains {
            $0.toolName == "read_file" &&
            $0.allowed &&
            $0.reason == "standing_access"
        })

        let exposures = try await h.exposureStore.exposures(connectionID: h.connectionID, limit: 10)
        #expect(exposures.contains {
            $0.toolName == "read_file" &&
            $0.exposureType == "full_file" &&
            $0.byteCount == "hello world".utf8.count &&
            $0.payloadPreview == "[redacted full_file, 11 bytes]" &&
            $0.payloadPreviewTruncated == false
        })
    }

    @Test("Standing access rejects symlinked files inside a shared source")
    func standingAccessRejectsSymlinkedFiles() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceDir = h.tempDir.appendingPathComponent("sources/MyApp")
        let outsideURL = h.tempDir.appendingPathComponent("outside/secret.txt")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("top secret".utf8).write(to: outsideURL)
        try FileManager.default.createSymbolicLink(
            at: sourceDir.appendingPathComponent("linked.txt"),
            withDestinationURL: outsideURL
        )

        let sourceID = try await h.grantStore.addSource(displayName: "MyApp", rootPath: sourceDir.path)
        try await h.policyStore.addSource(sourceID, to: .cowork)

        do {
            _ = try await h.bridge.readFile(path: "myapp/linked.txt")
            Issue.record("Expected symlinked path to be rejected")
        } catch let error as ManifoldMCPError {
            if case .invalidPath(let message) = error {
                #expect(message.contains("Symlinks are not allowed"))
            } else {
                Issue.record("Expected invalidPath, got \(error)")
            }
        }
    }

    @Test("Summary access recording requires intent summary")
    func summaryAccessRecordingRequiresIntent() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)
        try await h.policyStore.updateAccessRecordingLevel(.summary, for: .cowork)

        do {
            _ = try await h.bridge.readFile(path: "myapp/README.md")
            Issue.record("Expected intent requirement error")
        } catch let error as ManifoldMCPError {
            if case .intentRequired = error {
                // Expected
            } else {
                Issue.record("Expected intentRequired, got \(error)")
            }
        }

        let content = try await h.bridge.readFile(
            path: "myapp/README.md",
            intent: AccessIntent(summary: "Checking the README before editing", details: nil)
        )
        #expect(content == "hello world")

        let decisions = try await h.exposureStore.decisions(connectionID: h.connectionID, limit: 10)
        #expect(decisions.contains { $0.intentSummary == "Checking the README before editing" })
    }

    @Test("Standing email access uses allowed domains without a tracked work block")
    func standingEmailAccess() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        try createEmail(
            harness: h,
            id: "email-1",
            sender: "Docs Team <updates@example.com>",
            senderEmail: "updates@example.com",
            senderDomain: "example.com",
            subject: "Weekly project update",
            body: "Project update for the governed workspace."
        )

        let emails = try await h.bridge.listEmails()
        #expect(emails.count == 1)
        #expect(emails.first?.id == "email-1")

        let content = try await h.bridge.readEmail(id: "email-1")
        #expect(content.contains("Project update"))
    }

    @Test("Standing email search is filtered by runtime email rules")
    func standingEmailSearch() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        var ruleSet = try await h.emailRuleStore.ruleSet(for: .cowork)
        ruleSet.defaultPolicy = .blockUnlessAllowed
        ruleSet.domainRules = [
            EmailDomainRule(agent: .cowork, domain: "example.com", action: .allow),
        ]
        try await h.emailRuleStore.updateRuleSet(ruleSet)

        try createEmail(
            harness: h,
            id: "email-1",
            sender: "Docs Team <updates@example.com>",
            senderEmail: "updates@example.com",
            senderDomain: "example.com",
            subject: "Roadmap notes",
            body: "Roadmap notes and shipping milestones."
        )
        try createEmail(
            harness: h,
            id: "email-2",
            sender: "Alerts <alerts@bank.com>",
            senderEmail: "alerts@bank.com",
            senderDomain: "bank.com",
            subject: "Statement ready",
            body: "Sensitive financial email."
        )

        let results = try await h.bridge.searchEmails(query: "Roadmap")
        #expect(results.count == 1)
        #expect(results.first?.emailID == "email-1")
    }

    @Test("Standing email access works when default policy allows mail without explicit allow rules")
    func standingEmailAccessUsesDefaultAllowPolicy() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        var ruleSet = try await h.emailRuleStore.ruleSet(for: .cowork)
        ruleSet.defaultPolicy = .allowUnlessBlocked
        ruleSet.domainRules = []
        ruleSet.contactRules = []
        ruleSet.keywordRules = []
        try await h.emailRuleStore.updateRuleSet(ruleSet)

        try createEmail(
            harness: h,
            id: "email-default-allow",
            sender: "Project Team <updates@docs.dev>",
            senderEmail: "updates@docs.dev",
            senderDomain: "docs.dev",
            subject: "Project notes",
            body: "Notes visible through standing access."
        )

        let emails = try await h.bridge.listEmails()
        #expect(emails.contains { $0.id == "email-default-allow" })

        let content = try await h.bridge.readEmail(id: "email-default-allow")
        #expect(content.contains("Notes visible through standing access."))
    }

    @Test("Structured standing search returns scoped files and governed emails")
    func standingStructuredSearchIncludesScopedFilesAndEmails() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)
        let source = try #require(try await h.grantStore.source(id: sourceID))
        let readmeURL = URL(fileURLWithPath: source.originalRootPath).appendingPathComponent("README.md")
        try "Roadmap notes in the shared file.".write(to: readmeURL, atomically: true, encoding: .utf8)

        try createEmail(
            harness: h,
            id: "email-roadmap",
            sender: "Docs Team <updates@example.com>",
            senderEmail: "updates@example.com",
            senderDomain: "example.com",
            subject: "Roadmap email",
            body: "Roadmap notes in governed email."
        )

        let json = try await h.bridge.searchStructured(query: "Roadmap", limit: 10)
        #expect(json.contains(#""path" : "myapp\/README.md""#))
        #expect(json.contains("email-roadmap"))
        #expect(json.contains("standing_email_search"))
    }

    @Test("Explicit file work block still exposes emails shared with the agent")
    func explicitFileWorkBlockKeepsSharedEmailAccess() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)
        try createEmail(
            harness: h,
            id: "email-shared",
            sender: "Docs Team <updates@example.com>",
            senderEmail: "updates@example.com",
            senderDomain: "example.com",
            subject: "Shared note",
            body: "Email shared alongside a file-only work block."
        )
        try h.emailStore.shareEmails(emailIDs: ["email-shared"], for: .cowork)

        let grant = try await h.grantStore.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [sourceID],
            materializationRoot: h.tempDir.appendingPathComponent("explicit-grant").path,
            emailSensitivity: EmailSensitivityLevel.strict.rawValue,
            explicitSelection: true
        )
        try await h.grantStore.replaceGrantFileScopes(
            grantID: grant.grantID,
            scopes: [FileSelectionScope(sourceID: sourceID, relativePath: "README.md", isDirectory: false)]
        )
        _ = try await h.workBlockStore.startBlock(agent: .cowork, grantID: grant.grantID, sourceIDs: [sourceID])

        let emails = try await h.bridge.listEmails()
        #expect(emails.contains { $0.id == "email-shared" })
    }

    @Test("Active default work block drops sources removed from the current agent policy")
    func activeWorkBlockDropsUnsharedSources() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sharedSourceID = try await createAndRegisterSource(harness: h, name: "Shared")
        let unsharedSourceID = try await createAndRegisterSource(harness: h, name: "Unshared")
        try await h.policyStore.addSource(sharedSourceID, to: .cowork)
        try await h.policyStore.addSource(unsharedSourceID, to: .cowork)

        let grant = try await h.grantStore.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [sharedSourceID, unsharedSourceID],
            materializationRoot: h.tempDir.appendingPathComponent("default-grant").path,
            explicitSelection: false
        )
        try await materializeGrant(harness: h, grant: grant)
        _ = try await h.workBlockStore.startBlock(
            agent: .cowork,
            grantID: grant.grantID,
            sourceIDs: [sharedSourceID, unsharedSourceID]
        )
        try await h.policyStore.removeSource(unsharedSourceID, from: .cowork)

        let files = try await h.bridge.listFiles()
        #expect(files.contains { $0.path == "shared/README.md" && $0.sourceName == "shared" })
        #expect(files.contains { $0.sourceName == "unshared" } == false)
    }

    @Test("Active default work block respects current file visibility overrides")
    func activeWorkBlockRespectsFileVisibilityOverrides() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)
        let grant = try await h.grantStore.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [sourceID],
            materializationRoot: h.tempDir.appendingPathComponent("default-grant").path,
            explicitSelection: false
        )
        _ = try await h.workBlockStore.startBlock(
            agent: .cowork,
            grantID: grant.grantID,
            sourceIDs: [sourceID]
        )
        try await h.fileVisibilityOverrideStore.setOverride(
            agent: .cowork,
            sourceID: sourceID,
            relativePath: "README.md",
            isDirectory: false,
            decision: .deny
        )

        let files = try await h.bridge.listFiles()
        #expect(files.contains { $0.path == "myapp/src/main.swift" })
        #expect(files.contains { $0.path == "myapp/README.md" } == false)

        do {
            _ = try await h.bridge.readFile(path: "myapp/README.md")
            Issue.record("Expected active session read to honor the current file deny")
        } catch let error as ManifoldMCPError {
            guard case .fileNotFound = error else {
                Issue.record("Expected fileNotFound for hidden session file, got \(error)")
                return
            }
        }

        do {
            _ = try await h.bridge.writeFile(
                path: "myapp/README.md",
                content: "blocked",
                intent: AccessIntent(summary: "try writing hidden file", details: nil)
            )
            Issue.record("Expected active session write to honor the current file deny")
        } catch let error as ManifoldMCPError {
            guard case .fileNotFound = error else {
                Issue.record("Expected fileNotFound for hidden session write, got \(error)")
                return
            }
        }
    }

    @Test("Session gateway writes land in original source and are visible to later access")
    func sessionGatewayWritesOriginalSource() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        let source = try #require(try await h.grantStore.source(id: sourceID))
        let grant = try await h.grantStore.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [sourceID],
            materializationRoot: h.tempDir.appendingPathComponent("session-gateway").path,
            explicitSelection: true
        )
        try await h.grantStore.replaceGrantFileScopes(
            grantID: grant.grantID,
            scopes: [FileSelectionScope(sourceID: sourceID, relativePath: "", isDirectory: true)]
        )
        let block = try await h.workBlockStore.startBlock(agent: .cowork, grantID: grant.grantID, sourceIDs: [sourceID])

        let result = try await h.bridge.writeFile(
            path: "myapp/session-note.txt",
            content: "created in session one",
            intent: AccessIntent(summary: "test session gateway write", details: nil)
        )
        #expect(result.path == "myapp/session-note.txt")

        let originalURL = URL(fileURLWithPath: source.originalRootPath).appendingPathComponent("session-note.txt")
        #expect((try? String(contentsOf: originalURL, encoding: .utf8)) == "created in session one")
        #expect(try await h.snapshotStore.latestHash(runID: grant.grantID, filePath: "myapp/session-note.txt") != nil)

        try await h.workBlockStore.endBlock(id: block.id, status: .discarded)
        try await h.grantStore.endGrant(grantID: grant.grantID)
        try await h.policyStore.addSource(sourceID, to: .cowork)

        let files = try await h.bridge.listFiles()
        #expect(files.contains { $0.path == "myapp/session-note.txt" })
    }

    @Test("Session context redacts emails hidden by current policy")
    func sessionContextRedactsBlockedEmails() async throws {
        let h = try makeHarness(targetApp: .codex)
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "History")
        try await h.policyStore.addSource(sourceID, to: .codex)

        try createEmail(
            harness: h,
            id: "email-hidden",
            sender: "Payroll <payroll@work.com>",
            senderEmail: "payroll@work.com",
            senderDomain: "work.com",
            subject: "Comp update",
            body: "Confidential comp notes"
        )

        try await h.auditStore.log(
            action: .fileRead,
            agent: TargetApp.cowork.rawValue,
            metadata: ["messageID": "email-hidden", "type": "email"]
        )
        let sessionID = try #require(try await h.auditStore.recentEntries(limit: 1).first?.sessionID)

        let context = try await h.bridge.sessionContext(sessionID: sessionID)
        let email = try #require(context.emails.first)
        #expect(email.isRedacted)
        #expect(email.from == "Redacted")
    }
}
