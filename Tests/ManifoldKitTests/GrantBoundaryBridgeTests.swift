// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
@testable import ManifoldKit
@testable import ManifoldRuntime

@Suite("Grant Boundary Bridge")
struct GrantBoundaryBridgeTests {
    struct Harness {
        let db: DatabaseConnection
        let contentStore: ContentStore
        let snapshotStore: SnapshotStore
        let auditStore: AuditStore
        let grantStore: GrantStore
        let emailStore: EmailStore
        let artifactIndex: ArtifactIndex
        let exposureStore: ExposureStore
        let ledgerStore: LedgerStore
        let memoryStore: MemoryStore
        let skillStore: SkillStore
        let capabilityHandleStore: CapabilityHandleStore
        let execRunStore: ExecRunStore
        let knowledgeGraphStore: KnowledgeGraphStore
        let fabricationFindingStore: FabricationFindingStore
        let bridge: ManifoldBridge
        let tempDir: URL
        let targetApp: TargetApp
    }

    func makeHarness(targetApp: TargetApp = .cowork) throws -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-bridge-grant-\(UUID().uuidString)")
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
        let exposureStore = ExposureStore(db: db)
        let ledgerStore = try LedgerStore(db: db)
        let memoryStore = try MemoryStore(db: db)
        let skillStore = try SkillStore(db: db)
        let capabilityHandleStore = try CapabilityHandleStore(db: db)
        let execRunStore = try ExecRunStore(db: db)
        let knowledgeGraphStore = try KnowledgeGraphStore(db: db)
        let fabricationFindingStore = try FabricationFindingStore(db: db)
        let bridge = ManifoldBridge(
            db: db,
            auditStore: auditStore,
            contentStore: contentStore,
            grantStore: grantStore,
            emailStore: emailStore,
            snapshotStore: snapshotStore,
            artifactIndex: artifactIndex,
            exposureStore: exposureStore,
            ledgerStore: ledgerStore,
            memoryStore: memoryStore,
            skillStore: skillStore,
            capabilityHandleStore: capabilityHandleStore,
            execRunStore: execRunStore,
            knowledgeGraphStore: knowledgeGraphStore,
            fabricationFindingStore: fabricationFindingStore,
            targetApp: targetApp
        )
        return Harness(
            db: db,
            contentStore: contentStore,
            snapshotStore: snapshotStore,
            auditStore: auditStore,
            grantStore: grantStore,
            emailStore: emailStore,
            artifactIndex: artifactIndex,
            exposureStore: exposureStore,
            ledgerStore: ledgerStore,
            memoryStore: memoryStore,
            skillStore: skillStore,
            capabilityHandleStore: capabilityHandleStore,
            execRunStore: execRunStore,
            knowledgeGraphStore: knowledgeGraphStore,
            fabricationFindingStore: fabricationFindingStore,
            bridge: bridge,
            tempDir: tempDir,
            targetApp: targetApp
        )
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func metadataJSON(_ metadata: String?) -> [String: String] {
        guard let metadata,
              let data = metadata.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return json
    }

    func createSource(in root: URL, name: String, files: [String: String]) throws -> URL {
        let dir = root.appendingPathComponent("sources/\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (relativePath, contents) in files {
            let fileURL = dir.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: fileURL)
        }
        return dir
    }

    func startMaterializedGrant(
        harness: Harness,
        sources: [(id: String, record: SourceRecord)],
        targetApp: TargetApp? = nil,
        noteCaptureMode: SessionNoteCaptureMode = .off
    ) async throws -> GrantRecord {
        let materializationRoot = harness.tempDir.appendingPathComponent("materialized/\(UUID().uuidString)")
        let grant = try await harness.grantStore.startGrant(
            targetApp: targetApp ?? harness.targetApp,
            profileID: "default",
            sourceIDs: sources.map(\.id),
            materializationRoot: materializationRoot.path,
            noteCaptureMode: noteCaptureMode
        )
        let grantSources = try await harness.grantStore.grantSources(grantID: grant.grantID)
        let mountInputs = grantSources.compactMap { grantSource -> (source: SourceRecord, mountName: String)? in
            guard let match = sources.first(where: { $0.id == grantSource.sourceID }) else { return nil }
            return (match.record, grantSource.mountName)
        }

        let results = try MaterializationEngine.materialize(
            grantID: grant.grantID,
            sources: mountInputs,
            materializationRoot: grant.materializationRoot
        )
        for result in results {
            try await harness.grantStore.setBaselineHash(
                grantID: grant.grantID,
                sourceID: result.sourceID,
                hash: result.manifestHash
            )
            try await baselineSnapshotMount(
                snapshotStore: harness.snapshotStore,
                grantID: grant.grantID,
                sourceID: result.sourceID,
                mountName: result.mountName,
                mountPath: result.mountPath
            )
        }
        return grant
    }

    func baselineSnapshotMount(
        snapshotStore: SnapshotStore,
        grantID: String,
        sourceID: String,
        mountName: String,
        mountPath: String
    ) async throws {
        let root = URL(fileURLWithPath: mountPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
            guard !rel.hasPrefix("_emails/") else { continue }
            guard !rel.hasPrefix(".manifold-") else { continue }
            try await snapshotStore.recordBaseline(
                runID: grantID,
                workspaceID: sourceID,
                filePath: "\(mountName)/\(rel)",
                data: try Data(contentsOf: url)
            )
        }
    }

    @Test("Bridge ManifoldExec runs safe JSON plans and refuses dangerous ops")
    func bridgeManifoldExecPlan() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.tempDir) }

        let sourceURL = try createSource(
            in: harness.tempDir,
            name: "Alpha",
            files: ["notes.md": "invoice schema amount vendor date"]
        )
        let sourceID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceURL.path)
        let source = try #require(await harness.grantStore.source(id: sourceID))
        _ = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source)])
        _ = try await harness.memoryStore.save(
            kind: .sourceSchema,
            title: "Invoice schema",
            body: "amount, vendor, date",
            contributingSourceIDs: [sourceID]
        )

        let result = try await harness.bridge.runCode(
            code: #"{"steps":[{"op":"recall_memory","query":"schema","limit":5}]}"#,
            language: "json"
        )
        #expect(result.status == ExecRunStatus.completed.rawValue)
        #expect(result.output?.contains("Invoice schema") == true)

        let refused = try await harness.bridge.runCode(
            code: #"{"steps":[{"op":"shell","command":"cat secrets"}]}"#,
            language: "json"
        )
        #expect(refused.status == ExecRunStatus.refused.rawValue)
        #expect(refused.reason.contains("refused op shell"))
    }

    @Test("Bridge invokes executable skills and applies Rule of Two")
    func bridgeExecutableSkills() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.tempDir) }

        let sourceURL = try createSource(in: harness.tempDir, name: "Alpha", files: ["notes.md": "routine"])
        let sourceID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceURL.path)
        let source = try #require(await harness.grantStore.source(id: sourceID))
        _ = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source)])
        _ = try await harness.memoryStore.save(
            kind: .routine,
            title: "Weekly invoice routine",
            body: "search, summarize, cite",
            contributingSourceIDs: [sourceID]
        )

        _ = try await harness.bridge.saveSkill(
            name: "Recall routine",
            manifestJSON: #"{"steps":[{"op":"recall_memory","query":"routine","limit":5}]}"#
        )
        let completed = try await harness.bridge.invokeSkill(name: "Recall routine")
        #expect(completed.status == ExecRunStatus.completed.rawValue)
        #expect(completed.output?.contains("Weekly invoice routine") == true)

        _ = try await harness.bridge.saveSkill(
            name: "Unsafe send",
            manifestJSON: #"{"untrusted_input":true,"sensitive_data":true,"state_changing":true,"steps":[{"op":"recall_memory","query":"routine"}]}"#
        )
        let gated = try await harness.bridge.invokeSkill(name: "Unsafe send")
        #expect(gated.status == ExecRunStatus.needsApproval.rawValue)
    }

    @Test("Bridge verifies claimed actions against exposure ground truth")
    func bridgeClaimVerification() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.tempDir) }

        let sourceURL = try createSource(in: harness.tempDir, name: "Alpha", files: ["notes.md": "original"])
        let sourceID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceURL.path)
        let source = try #require(await harness.grantStore.source(id: sourceID))
        _ = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source)])

        _ = try await harness.bridge.readFile(path: "alpha/notes.md")
        let exposure = try #require(try await harness.exposureStore.latestExposure(resourcePath: "alpha/notes.md"))
        try await harness.exposureStore.recordExposure(
            ExposureRecord(
                connectionID: "other-connection",
                agent: "cowork",
                toolName: "read_file",
                resourcePath: "beta/secret.md",
                byteCount: 6,
                contentHash: "otherhash",
                exposureType: "full_file",
                accessDecisionID: "other-decision"
            )
        )

        let verification = try await harness.bridge.verifyClaimedActions(
            claimsJSON: """
            [
              {"tool_name":"read_file","resource_path":"alpha/notes.md","content_hash":"\(exposure.contentHash)"},
              {"tool_name":"read_file","resource_path":"missing.md"},
              {"tool_name":"read_file"},
              "I read alpha/notes.md",
              {"tool_name":"read_file","resource_path":"beta/secret.md","content_hash":"otherhash"}
            ]
            """
        )

        #expect(verification.contains("supported: tool=read_file resource=alpha/notes.md hash="))
        #expect(verification.contains("unverified: tool=read_file resource=missing.md"))
        #expect(verification.contains("ambiguous: tool=read_file"))
        #expect(verification.contains("ambiguous: I read alpha/notes.md"))
        #expect(verification.contains("unverified: tool=read_file resource=beta/secret.md hash=otherhash"))
    }

    @Test("Bridge forget_memory is scoped to current grant/source lineage")
    func bridgeForgetMemoryIsScoped() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.tempDir) }

        let sourceAURL = try createSource(in: harness.tempDir, name: "Alpha", files: ["notes.md": "alpha"])
        let sourceBURL = try createSource(in: harness.tempDir, name: "Beta", files: ["notes.md": "beta"])
        let sourceAID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceAURL.path)
        let sourceBID = try await harness.grantStore.addSource(displayName: "Beta", rootPath: sourceBURL.path)
        let sourceA = try #require(await harness.grantStore.source(id: sourceAID))
        _ = try await startMaterializedGrant(harness: harness, sources: [(sourceAID, sourceA)])

        let inScope = try await harness.memoryStore.save(
            kind: .note,
            title: "Alpha note",
            body: "alpha memory",
            contributingSourceIDs: [sourceAID]
        )
        let outOfScope = try await harness.memoryStore.save(
            kind: .note,
            title: "Beta note",
            body: "beta memory",
            contributingSourceIDs: [sourceBID]
        )
        let unscoped = try await harness.memoryStore.save(
            kind: .note,
            title: "Unscoped note",
            body: "no lineage"
        )

        let deniedOutOfScope = try await harness.bridge.forgetMemory(memoryID: outOfScope.memoryID)
        let deniedUnscoped = try await harness.bridge.forgetMemory(memoryID: unscoped.memoryID)
        let deniedMissing = try await harness.bridge.forgetMemory(memoryID: "mem-missing")
        let allowed = try await harness.bridge.forgetMemory(memoryID: inScope.memoryID)

        #expect(deniedOutOfScope == "Memory is unavailable in the current session scope.")
        #expect(deniedUnscoped == deniedOutOfScope)
        #expect(deniedMissing == deniedOutOfScope)
        #expect(allowed.contains("marked deleted"))
        #expect(try await harness.memoryStore.memory(id: outOfScope.memoryID)?.status == MemoryStatus.active.rawValue)
        #expect(try await harness.memoryStore.memory(id: unscoped.memoryID)?.status == MemoryStatus.active.rawValue)
        #expect(try await harness.memoryStore.memory(id: inScope.memoryID)?.status == MemoryStatus.deletedByUser.rawValue)
    }

    @Test("Bridge save_memory_note obeys amnesiac mode")
    func bridgeSaveMemoryNoteObeysAmnesiacMode() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.tempDir) }

        let sourceURL = try createSource(in: harness.tempDir, name: "Alpha", files: ["notes.md": "alpha"])
        let sourceID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceURL.path)
        let source = try #require(await harness.grantStore.source(id: sourceID))
        _ = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source)])

        try await harness.memoryStore.upsertSettings(MemorySettings(amnesiacMode: true, derivedRetentionDays: 90))
        let response = try await harness.bridge.saveMemoryNote(title: "Do not persist", body: "sensitive derived note")
        let memories = try await harness.memoryStore.list(limit: 10, includeDeleted: true)
        let ledgerEntries = try await harness.ledgerStore.recent(limit: 10)

        #expect(response == "Memory not saved because amnesiac mode is enabled.")
        #expect(memories.contains { $0.title == "Do not persist" } == false)
        #expect(ledgerEntries.contains { $0.subjectTable == "memory_settings" && $0.metadataJSON?.contains("amnesiac_mode") == true })
    }

    @Test("Bridge check_capability_flow is scoped before sink evaluation")
    func bridgeCapabilityHandlesAreScoped() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.tempDir) }

        let sourceAURL = try createSource(in: harness.tempDir, name: "Alpha", files: ["notes.md": "alpha"])
        let sourceBURL = try createSource(in: harness.tempDir, name: "Beta", files: ["notes.md": "beta"])
        let sourceAID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceAURL.path)
        let sourceBID = try await harness.grantStore.addSource(displayName: "Beta", rootPath: sourceBURL.path)
        let sourceA = try #require(await harness.grantStore.source(id: sourceAID))
        let grant = try await startMaterializedGrant(harness: harness, sources: [(sourceAID, sourceA)])

        let inScope = try await harness.capabilityHandleStore.save(ValueHandle(
            origin: "alpha",
            sensitivity: "sensitive",
            trustLevel: "untrusted",
            allowedSinks: ["model_context", "write_file"],
            grantID: grant.grantID,
            lineage: [LineageRef(kind: "source", id: sourceAID)]
        ))
        let outOfScope = try await harness.capabilityHandleStore.save(ValueHandle(
            origin: "beta",
            sensitivity: "sensitive",
            trustLevel: "untrusted",
            allowedSinks: ["model_context"],
            grantID: "grant-other",
            lineage: [LineageRef(kind: "source", id: sourceBID)]
        ))

        let denied = try await harness.bridge.checkCapabilityFlow(handleID: outOfScope.handleID, sink: "model_context")
        let allowed = try await harness.bridge.checkCapabilityFlow(handleID: inScope.handleID, sink: "model_context")
        let ruleOfTwo = try await harness.bridge.checkCapabilityFlow(
            handleID: inScope.handleID,
            sink: "write_file",
            untrustedInput: true,
            stateChangingAction: true
        )

        #expect(denied.contains(#""allowed":false"#))
        #expect(denied.contains("Capability handle is unavailable in the current session scope."))
        #expect(allowed.contains(#""allowed":true"#))
        #expect(ruleOfTwo.contains(#""allowed":false"#))
        #expect(ruleOfTwo.contains(#""ruleOfTwoTriggered":true"#))
    }

    @Test("Bridge write_file creates snapshots and canonical audit entries")
    func bridgeWriteCreatesSnapshots() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.tempDir) }

        let sourceURL = try createSource(
            in: harness.tempDir,
            name: "Alpha",
            files: ["notes.md": "original"]
        )
        let sourceID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceURL.path)
        let source = try #require(await harness.grantStore.source(id: sourceID))
        let grant = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source)])

        let result = try await harness.bridge.writeFile(path: "alpha/notes.md", content: "updated")
        #expect(result.message.contains("alpha/notes.md"))

        let history = try await harness.snapshotStore.history(runID: grant.grantID, filePath: "alpha/notes.md")
        let mcpSnapshots = history.filter { $0.source == "mcp" }
        #expect(mcpSnapshots.count == 1)
        #expect(mcpSnapshots.last?.afterHash != nil)

        let entries = try await harness.auditStore.recentEntries(limit: 10)
        let writeEntry = entries.first { $0.action == "file_modified" }
        #expect(writeEntry?.runID == grant.grantID)
        #expect(writeEntry?.workspaceID == sourceID)
        #expect(writeEntry?.filePath == "alpha/notes.md")
        #expect(writeEntry?.beforeHash == mcpSnapshots.last?.beforeHash?.nilIfEmpty)
        #expect(writeEntry?.afterHash == mcpSnapshots.last?.afterHash?.nilIfEmpty)
    }

    @Test("Bridge uses Codex target app for grant resolution and audit entries")
    func bridgeUsesCodexTargetApp() async throws {
        let harness = try makeHarness(targetApp: .codex)
        defer { cleanup(harness.tempDir) }

        let sourceURL = try createSource(
            in: harness.tempDir,
            name: "Alpha",
            files: ["notes.md": "original"]
        )
        let sourceID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceURL.path)
        let source = try #require(await harness.grantStore.source(id: sourceID))
        let grant = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source)])

        _ = try await harness.bridge.writeFile(path: "alpha/notes.md", content: "updated by codex")

        let status = await harness.bridge.getStatus()
        #expect(status.grantID == grant.grantID)

        let entries = try await harness.auditStore.recentEntries(limit: 20)
        let writeEntry = entries.first { $0.action == "file_modified" }
        #expect(writeEntry?.agent == "codex")
        #expect(writeEntry?.runID == grant.grantID)
    }

    @Test("Bridge records free connection context and carries it into later audit entries")
    func bridgeRecordsConnectionContext() async throws {
        let harness = try makeHarness(targetApp: .codex)
        defer { cleanup(harness.tempDir) }

        await harness.bridge.registerClientContext(initializeParams: [
            "protocolVersion": "2024-11-05",
            "clientInfo": [
                "name": "Codex Desktop",
                "version": "1.2.3",
            ] as [String: Any],
            "capabilities": [
                "roots": [:] as [String: Any],
                "sampling": [:] as [String: Any],
            ] as [String: Any],
            "metadata": [
                "provider": "openai",
                "model": "gpt-5.4",
            ] as [String: Any],
        ])

        let sourceURL = try createSource(
            in: harness.tempDir,
            name: "Alpha",
            files: ["notes.md": "original"]
        )
        let sourceID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceURL.path)
        let source = try #require(await harness.grantStore.source(id: sourceID))
        _ = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source)])

        _ = try await harness.bridge.writeFile(path: "alpha/notes.md", content: "updated with context")
        await harness.bridge.recordDisconnection()

        let entries = try await harness.auditStore.recentEntries(limit: 20)
        let connectionEntry = entries.first { $0.action == "mcp_connection" }
        let connectionMetadata = metadataJSON(connectionEntry?.metadata)
        #expect(connectionEntry?.agent == "codex")
        #expect(connectionMetadata["event"] == "disconnected")
        #expect(connectionMetadata["client_name"] == "Codex Desktop")
        #expect(connectionMetadata["client_version"] == "1.2.3")
        #expect(connectionMetadata["provider_hint"] == "openai")
        #expect(connectionMetadata["model_hint"] == "gpt-5.4")
        #expect(connectionMetadata["target_app"] == "codex")
        #expect(connectionMetadata["protocol_version"] == "2024-11-05")
        #expect(connectionMetadata["connection_id"] != nil)

        let writeEntry = entries.first { $0.action == "file_modified" }
        let writeMetadata = metadataJSON(writeEntry?.metadata)
        #expect(writeMetadata["connection_id"] == connectionMetadata["connection_id"])
        #expect(writeMetadata["client_name"] == "Codex Desktop")
        #expect(writeMetadata["provider_hint"] == "openai")
        #expect(writeMetadata["model_hint"] == "gpt-5.4")
    }

    @Test("Bridge records one automatic verbose checkpoint note on first write")
    func bridgeRecordsAutomaticVerboseCheckpointNote() async throws {
        let harness = try makeHarness(targetApp: .codex)
        defer { cleanup(harness.tempDir) }

        let sourceURL = try createSource(
            in: harness.tempDir,
            name: "Alpha",
            files: ["notes.md": "original"]
        )
        let sourceID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceURL.path)
        let source = try #require(await harness.grantStore.source(id: sourceID))
        let grant = try await startMaterializedGrant(
            harness: harness,
            sources: [(sourceID, source)],
            noteCaptureMode: .verbose
        )

        _ = try await harness.bridge.writeFile(path: "alpha/notes.md", content: "first change")
        _ = try await harness.bridge.writeFile(path: "alpha/notes.md", content: "second change")

        let notes = try await harness.grantStore.summaries(grantID: grant.grantID, kind: .checkpointNote)
        #expect(notes.count == 1)
        #expect(notes[0].origin == .system)
        #expect(notes[0].summaryMarkdown.contains("first material change"))

        let status = await harness.bridge.getStatus()
        #expect(status.noteCaptureMode == SessionNoteCaptureMode.verbose.rawValue)
        #expect(status.noteGuidance?.contains("VERBOSE") == true)
    }

    @Test("Bridge saves typed agent session notes")
    func bridgeSavesTypedAgentSessionNotes() async throws {
        let harness = try makeHarness(targetApp: .cowork)
        defer { cleanup(harness.tempDir) }

        let sourceURL = try createSource(
            in: harness.tempDir,
            name: "Alpha",
            files: ["notes.md": "original"]
        )
        let sourceID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceURL.path)
        let source = try #require(await harness.grantStore.source(id: sourceID))
        let grant = try await startMaterializedGrant(
            harness: harness,
            sources: [(sourceID, source)],
            noteCaptureMode: .basic
        )

        let response = try await harness.bridge.saveSessionNote(
            note: "Objective is to draft a concise board-ready summary.",
            noteType: .startNote
        )
        #expect(response.contains("start note"))

        let startNotes = try await harness.grantStore.summaries(grantID: grant.grantID, kind: .startNote)
        #expect(startNotes.count == 1)
        #expect(startNotes[0].origin == .agent)
    }

    @Test("Bridge rejects ambiguous bare paths across multiple mounts")
    func bridgeRejectsAmbiguousBarePath() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.tempDir) }

        let sourceAURL = try createSource(in: harness.tempDir, name: "Alpha", files: ["notes.md": "alpha"])
        let sourceBURL = try createSource(in: harness.tempDir, name: "Beta", files: ["notes.md": "beta"])
        let sourceAID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceAURL.path)
        let sourceBID = try await harness.grantStore.addSource(displayName: "Beta", rootPath: sourceBURL.path)
        let sourceA = try #require(await harness.grantStore.source(id: sourceAID))
        let sourceB = try #require(await harness.grantStore.source(id: sourceBID))
        _ = try await startMaterializedGrant(
            harness: harness,
            sources: [(sourceAID, sourceA), (sourceBID, sourceB)]
        )

        await #expect(throws: ManifoldMCPError.self) {
            _ = try await harness.bridge.readFile(path: "notes.md")
        }
    }

    @Test("Bridge write_file rejects paths outside explicit grant scope")
    func bridgeRejectsOutOfScopeWrite() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.tempDir) }

        let sourceURL = try createSource(
            in: harness.tempDir,
            name: "Alpha",
            files: ["notes.md": "original"]
        )
        let sourceID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceURL.path)
        let source = try #require(await harness.grantStore.source(id: sourceID))
        let grant = try await harness.grantStore.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [sourceID],
            materializationRoot: harness.tempDir.appendingPathComponent("scoped-write").path,
            explicitSelection: true
        )
        try await harness.grantStore.replaceGrantFileScopes(
            grantID: grant.grantID,
            scopes: [
                FileSelectionScope(sourceID: sourceID, relativePath: "notes.md", isDirectory: false),
            ]
        )
        let grantSources = try await harness.grantStore.grantSources(grantID: grant.grantID)
        _ = try MaterializationEngine.materialize(
            grantID: grant.grantID,
            sources: [(source: source, mountName: grantSources[0].mountName)],
            materializationRoot: grant.materializationRoot
        )

        await #expect(throws: ManifoldMCPError.self) {
            _ = try await harness.bridge.writeFile(path: "alpha/outside.md", content: "blocked")
        }
    }

    @Test("Bridge search reflects indexed content after writes")
    func bridgeSearchUpdatesAfterWrite() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.tempDir) }

        let sourceURL = try createSource(
            in: harness.tempDir,
            name: "Alpha",
            files: ["notes.md": "line one\nneedle before\nline three"]
        )
        let sourceID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceURL.path)
        let source = try #require(await harness.grantStore.source(id: sourceID))
        _ = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source)])

        let beforeHits = try await harness.bridge.searchFiles(query: "before")
        #expect(beforeHits.count == 1)
        #expect(beforeHits[0].path == "alpha/notes.md")
        #expect(beforeHits[0].matches.joined(separator: "\n").contains("needle before"))

        _ = try await harness.bridge.writeFile(path: "alpha/notes.md", content: "line one\nneedle after\nline three")

        let afterHits = try await harness.bridge.searchFiles(query: "after")
        #expect(afterHits.count == 1)
        #expect(afterHits[0].matches.joined(separator: "\n").contains("needle after"))

        let oldHits = try await harness.bridge.searchFiles(query: "before")
        #expect(oldHits.isEmpty)
    }

    @Test("Bridge read_range returns targeted lines")
    func bridgeReadRange() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.tempDir) }

        let sourceURL = try createSource(
            in: harness.tempDir,
            name: "Alpha",
            files: ["notes.md": "one\ntwo\nthree\nfour"]
        )
        let sourceID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceURL.path)
        let source = try #require(await harness.grantStore.source(id: sourceID))
        _ = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source)])

        let excerpt = try await harness.bridge.readRange(path: "alpha/notes.md", startLine: 2, endLine: 3)
        #expect(excerpt == "two\nthree")
    }

    @Test("Bridge diff_file compares current content to baseline snapshot")
    func bridgeDiffFile() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.tempDir) }

        let sourceURL = try createSource(
            in: harness.tempDir,
            name: "Alpha",
            files: ["notes.md": "original"]
        )
        let sourceID = try await harness.grantStore.addSource(displayName: "Alpha", rootPath: sourceURL.path)
        let source = try #require(await harness.grantStore.source(id: sourceID))
        _ = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source)])

        _ = try await harness.bridge.writeFile(path: "alpha/notes.md", content: "updated")
        let diff = try await harness.bridge.diffFile(path: "alpha/notes.md")

        #expect(diff.contains("-original"))
        #expect(diff.contains("+updated"))
    }

    @Test("Email-only grant exposes full selected email content")
    func emailOnlyGrantReadsFromEml() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.tempDir) }

        // Write a .eml file to disk
        let emlContent = """
        From: counsel@example.com
        To: team@example.com
        Date: 2026-04-05
        Subject: Draft redlines
        Message-ID: email-1

        Full legal email body.
        """
        let emlDir = harness.tempDir.appendingPathComponent("eml")
        try FileManager.default.createDirectory(at: emlDir, withIntermediateDirectories: true)
        let emlFile = emlDir.appendingPathComponent("1.eml")
        try emlContent.write(to: emlFile, atomically: true, encoding: .utf8)

        // Create the email account first (FK constraint)
        let emailAccount = try await harness.emailStore.addEmailAccount(
            displayName: "Test Account",
            providerType: "other",
            server: "imap.example.com",
            port: 993,
            username: "test@example.com",
            authType: "password"
        )

        try await harness.emailStore.upsertEmailMessage(
            emailID: "email-1",
            accountID: emailAccount.accountID,
            mailbox: "Inbox",
            sender: "counsel@example.com",
            recipients: "team@example.com",
            subject: "Draft redlines",
            receivedAt: "2026-04-05",
            emlPath: emlFile.path,
            sizeBytes: emlContent.utf8.count,
            preview: "Draft redlines"
        )

        let grant = try await harness.grantStore.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [],
            materializationRoot: harness.tempDir.appendingPathComponent("email-only").path
        )

        let emails = try await harness.bridge.listEmails()
        #expect(emails.count == 1)
        #expect(emails[0].id == "email-1")

        let content = try await harness.bridge.readEmail(id: "email-1")
        #expect(content.contains("Full legal email body."))

        let status = await harness.bridge.getStatus()
        #expect(status.active == true)
        #expect(status.grantID == grant.grantID)
        #expect(status.emailCount == 1)
    }

    @Test("Bridge search_structured includes email and session summary artifacts")
    func bridgeSearchStructuredIncludesNonFileArtifacts() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.tempDir) }

        let emailAccount = try await harness.emailStore.addEmailAccount(
            displayName: "Test Account",
            providerType: "other",
            server: "imap.example.com",
            port: 993,
            username: "test@example.com",
            authType: "password"
        )

        try await harness.emailStore.upsertEmailMessage(
            emailID: "email-needle",
            accountID: emailAccount.accountID,
            mailbox: "Inbox",
            sender: "needle@example.com",
            recipients: "team@example.com",
            subject: "Needle email",
            receivedAt: "2026-04-05",
            emlPath: nil,
            sizeBytes: 128,
            preview: "Needle email preview"
        )

        let grant = try await harness.grantStore.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [],
            materializationRoot: harness.tempDir.appendingPathComponent("structured-search").path
        )

        _ = try await harness.grantStore.saveSummary(
            grantID: grant.grantID,
            targetApp: .cowork,
            startedAt: grant.startedAt,
            endedAt: "2026-04-06",
            markdown: "# Session Summary\n\nNeedle summary marker"
        )

        let result = try await harness.bridge.searchStructured(query: "Needle", limit: 10)
        #expect(result.contains("\"kind\" : \"email\""))
        #expect(result.contains("email-needle"))
        #expect(result.contains("\"kind\" : \"session_summary\""))
        #expect(result.contains("_sessions"))
        #expect(result.contains("\"retrieval\""))
        #expect(result.contains("contextual_chunk"))
        #expect(result.contains("\"content_hash\""))
    }

    // MARK: - Cross-agent hero shot

    struct CrossAgentHarness {
        let db: DatabaseConnection
        let contentStore: ContentStore
        let snapshotStore: SnapshotStore
        let auditStore: AuditStore
        let grantStore: GrantStore
        let emailStore: EmailStore
        let artifactIndex: ArtifactIndex
        let exposureStore: ExposureStore
        let ledgerStore: LedgerStore
        let memoryStore: MemoryStore
        let skillStore: SkillStore
        let capabilityHandleStore: CapabilityHandleStore
        let execRunStore: ExecRunStore
        let knowledgeGraphStore: KnowledgeGraphStore
        let fabricationFindingStore: FabricationFindingStore
        let codexBridge: ManifoldBridge
        let coworkBridge: ManifoldBridge
        let tempDir: URL
    }

    func makeCrossAgentHarness() throws -> CrossAgentHarness {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-bridge-cross-agent-\(UUID().uuidString)")
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
        let exposureStore = ExposureStore(db: db)
        let ledgerStore = try LedgerStore(db: db)
        let memoryStore = try MemoryStore(db: db)
        let skillStore = try SkillStore(db: db)
        let capabilityHandleStore = try CapabilityHandleStore(db: db)
        let execRunStore = try ExecRunStore(db: db)
        let knowledgeGraphStore = try KnowledgeGraphStore(db: db)
        let fabricationFindingStore = try FabricationFindingStore(db: db)

        func makeBridge(targetApp: TargetApp) -> ManifoldBridge {
            ManifoldBridge(
                db: db,
                auditStore: auditStore,
                contentStore: contentStore,
                grantStore: grantStore,
                emailStore: emailStore,
                snapshotStore: snapshotStore,
                artifactIndex: artifactIndex,
                exposureStore: exposureStore,
                ledgerStore: ledgerStore,
                memoryStore: memoryStore,
                skillStore: skillStore,
                capabilityHandleStore: capabilityHandleStore,
                execRunStore: execRunStore,
                knowledgeGraphStore: knowledgeGraphStore,
                fabricationFindingStore: fabricationFindingStore,
                targetApp: targetApp
            )
        }

        return CrossAgentHarness(
            db: db,
            contentStore: contentStore,
            snapshotStore: snapshotStore,
            auditStore: auditStore,
            grantStore: grantStore,
            emailStore: emailStore,
            artifactIndex: artifactIndex,
            exposureStore: exposureStore,
            ledgerStore: ledgerStore,
            memoryStore: memoryStore,
            skillStore: skillStore,
            capabilityHandleStore: capabilityHandleStore,
            execRunStore: execRunStore,
            knowledgeGraphStore: knowledgeGraphStore,
            fabricationFindingStore: fabricationFindingStore,
            codexBridge: makeBridge(targetApp: .codex),
            coworkBridge: makeBridge(targetApp: .cowork),
            tempDir: tempDir
        )
    }

    /// Hero shot: Codex reads a file and saves a memory; Cowork (Claude) then
    /// surfaces both via reuse_prior_context, recall_memory, and was_exposed_before.
    /// This is the demo's "What did Codex just do?" payoff. If this test fails,
    /// the launch demo's pitch beat doesn't work.
    @Test("Hero shot: Cowork surfaces Codex's prior reads and memory across agents")
    func crossAgentHeroShotEndToEnd() async throws {
        let h = try makeCrossAgentHarness()
        defer { cleanup(h.tempDir) }

        // ONE shared source folder. Both agents have grants over it.
        let sourceURL = try createSource(
            in: h.tempDir,
            name: "Alpha",
            files: ["notes.md": "manifold cross-agent demo content"]
        )
        let sourceID = try await h.grantStore.addSource(displayName: "Alpha", rootPath: sourceURL.path)
        let source = try #require(await h.grantStore.source(id: sourceID), "GrantStore must persist the just-added source")

        // Codex grant comes first — represents Codex working in the folder.
        let codexMaterializationRoot = h.tempDir.appendingPathComponent("materialized/codex-\(UUID().uuidString)")
        let codexGrant = try await h.grantStore.startGrant(
            targetApp: .codex,
            profileID: "default",
            sourceIDs: [sourceID],
            materializationRoot: codexMaterializationRoot.path,
            noteCaptureMode: .off
        )
        let codexGrantSources = try await h.grantStore.grantSources(grantID: codexGrant.grantID)
        let codexMountInputs = codexGrantSources.compactMap { gs -> (source: SourceRecord, mountName: String)? in
            guard gs.sourceID == sourceID else { return nil }
            return (source, gs.mountName)
        }
        let codexResults = try MaterializationEngine.materialize(
            grantID: codexGrant.grantID,
            sources: codexMountInputs,
            materializationRoot: codexGrant.materializationRoot
        )
        for r in codexResults {
            try await h.grantStore.setBaselineHash(grantID: codexGrant.grantID, sourceID: r.sourceID, hash: r.manifestHash)
            try await baselineSnapshotMount(
                snapshotStore: h.snapshotStore,
                grantID: codexGrant.grantID,
                sourceID: r.sourceID,
                mountName: r.mountName,
                mountPath: r.mountPath
            )
        }

        // Codex reads the file and saves a memory note.
        let codexMountName = codexGrantSources.first?.mountName ?? "Alpha"
        _ = try await h.codexBridge.readFile(path: "\(codexMountName)/notes.md")
        _ = try await h.codexBridge.saveMemoryNote(
            title: "Cross-agent demo schema",
            body: "Codex captured the manifold cross-agent demo content here."
        )

        // Codex ends its grant. The demo can have Codex disconnected at this point;
        // Cowork should still see Codex's traces because exposures + memory persist.
        try await h.grantStore.endGrant(grantID: codexGrant.grantID)

        // Cowork (Claude) starts its own grant on the SAME source.
        let coworkMaterializationRoot = h.tempDir.appendingPathComponent("materialized/cowork-\(UUID().uuidString)")
        let coworkGrant = try await h.grantStore.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [sourceID],
            materializationRoot: coworkMaterializationRoot.path,
            noteCaptureMode: .off
        )
        let coworkGrantSources = try await h.grantStore.grantSources(grantID: coworkGrant.grantID)
        let coworkMountInputs = coworkGrantSources.compactMap { gs -> (source: SourceRecord, mountName: String)? in
            guard gs.sourceID == sourceID else { return nil }
            return (source, gs.mountName)
        }
        let coworkResults = try MaterializationEngine.materialize(
            grantID: coworkGrant.grantID,
            sources: coworkMountInputs,
            materializationRoot: coworkGrant.materializationRoot
        )
        for r in coworkResults {
            try await h.grantStore.setBaselineHash(grantID: coworkGrant.grantID, sourceID: r.sourceID, hash: r.manifestHash)
            try await baselineSnapshotMount(
                snapshotStore: h.snapshotStore,
                grantID: coworkGrant.grantID,
                sourceID: r.sourceID,
                mountName: r.mountName,
                mountPath: r.mountPath
            )
        }

        // The demo question: "What did Codex just do?"
        // 1. reuse_prior_context with Codex's path should return Codex's exposure + memory.
        let coworkMountName = coworkGrantSources.first?.mountName ?? "Alpha"
        let coworkPath = "\(coworkMountName)/notes.md"
        let priorContext = try await h.coworkBridge.reusePriorContext(path: coworkPath)
        #expect(priorContext.contains("Cross-agent demo schema"),
                "Cowork's reuse_prior_context must surface the memory Codex saved in the same source scope. Got:\n\(priorContext)")
        #expect(priorContext.contains("read_file") || priorContext.contains("save_memory_note"),
                "Cowork's reuse_prior_context must include Codex's prior tool exposure. Got:\n\(priorContext)")

        // 2. recall_memory should surface Codex's memory because both grants share the source.
        let recall = try await h.coworkBridge.recallMemory(query: "demo")
        #expect(recall.contains("Cross-agent demo schema"),
                "Cowork's recall_memory must return memory Codex saved in the same source scope. Got:\n\(recall)")

        // 3. was_exposed_before by path must show Codex's read of notes.md.
        let exposureLookup = try await h.coworkBridge.wasExposedBefore(path: coworkPath)
        #expect(exposureLookup.contains("Prior exposures"),
                "Cowork's was_exposed_before must surface Codex's prior read. Got:\n\(exposureLookup)")
    }

    /// Scope isolation negative: when Cowork's grant is over a DIFFERENT
    /// source than Codex's grant, Cowork must NOT see Codex's saved memory.
    /// This guards against regressions that would silently widen scope past
    /// the lineage check (e.g. if MemoryStore.recall stopped filtering by
    /// allowedSourceIDs, the positive hero-shot test would still pass).
    @Test("Cross-agent: Cowork over different source sees no memory from Codex")
    func crossAgentScopeIsolation() async throws {
        let h = try makeCrossAgentHarness()
        defer { cleanup(h.tempDir) }

        // TWO source folders. Codex gets one, Cowork gets the other.
        let codexSourceURL = try createSource(
            in: h.tempDir,
            name: "CodexSource",
            files: ["notes.md": "codex-only content"]
        )
        let coworkSourceURL = try createSource(
            in: h.tempDir,
            name: "CoworkSource",
            files: ["notes.md": "cowork-only content"]
        )
        let codexSourceID = try await h.grantStore.addSource(displayName: "CodexSource", rootPath: codexSourceURL.path)
        let coworkSourceID = try await h.grantStore.addSource(displayName: "CoworkSource", rootPath: coworkSourceURL.path)
        let codexSource = try #require(await h.grantStore.source(id: codexSourceID), "GrantStore must persist Codex's source")
        let coworkSource = try #require(await h.grantStore.source(id: coworkSourceID), "GrantStore must persist Cowork's source")

        // Codex grant over CodexSource only.
        let codexMaterializationRoot = h.tempDir.appendingPathComponent("materialized/codex-iso-\(UUID().uuidString)")
        let codexGrant = try await h.grantStore.startGrant(
            targetApp: .codex,
            profileID: "default",
            sourceIDs: [codexSourceID],
            materializationRoot: codexMaterializationRoot.path,
            noteCaptureMode: .off
        )
        let codexGrantSources = try await h.grantStore.grantSources(grantID: codexGrant.grantID)
        let codexMountInputs = codexGrantSources.compactMap { gs -> (source: SourceRecord, mountName: String)? in
            guard gs.sourceID == codexSourceID else { return nil }
            return (codexSource, gs.mountName)
        }
        let codexResults = try MaterializationEngine.materialize(
            grantID: codexGrant.grantID,
            sources: codexMountInputs,
            materializationRoot: codexGrant.materializationRoot
        )
        for r in codexResults {
            try await h.grantStore.setBaselineHash(grantID: codexGrant.grantID, sourceID: r.sourceID, hash: r.manifestHash)
        }

        let codexMountName = codexGrantSources.first?.mountName ?? "CodexSource"
        _ = try await h.codexBridge.readFile(path: "\(codexMountName)/notes.md")
        _ = try await h.codexBridge.saveMemoryNote(
            title: "Codex private schema",
            body: "should not leak to cowork over a different source"
        )
        try await h.grantStore.endGrant(grantID: codexGrant.grantID)

        // Cowork grant over CoworkSource only — DIFFERENT source from Codex.
        let coworkMaterializationRoot = h.tempDir.appendingPathComponent("materialized/cowork-iso-\(UUID().uuidString)")
        let coworkGrant = try await h.grantStore.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [coworkSourceID],
            materializationRoot: coworkMaterializationRoot.path,
            noteCaptureMode: .off
        )
        let coworkGrantSources = try await h.grantStore.grantSources(grantID: coworkGrant.grantID)
        let coworkMountInputs = coworkGrantSources.compactMap { gs -> (source: SourceRecord, mountName: String)? in
            guard gs.sourceID == coworkSourceID else { return nil }
            return (coworkSource, gs.mountName)
        }
        let coworkResults = try MaterializationEngine.materialize(
            grantID: coworkGrant.grantID,
            sources: coworkMountInputs,
            materializationRoot: coworkGrant.materializationRoot
        )
        for r in coworkResults {
            try await h.grantStore.setBaselineHash(grantID: coworkGrant.grantID, sourceID: r.sourceID, hash: r.manifestHash)
        }

        // Cowork must NOT see Codex's memory (lineage scope mismatch).
        let recall = try await h.coworkBridge.recallMemory(query: "schema")
        #expect(recall.contains("Codex private schema") == false,
                "Cowork's recall_memory leaked memory from a source it has no grant over. Got:\n\(recall)")
        #expect(recall.contains("No memory matched") || recall.isEmpty || recall.contains("Codex") == false,
                "Cowork must report empty/scope-mismatch result, not Codex content. Got:\n\(recall)")
    }
}
