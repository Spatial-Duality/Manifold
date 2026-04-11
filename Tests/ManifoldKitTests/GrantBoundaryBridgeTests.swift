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
        let bridge = ManifoldBridge(
            db: db,
            auditStore: auditStore,
            contentStore: contentStore,
            grantStore: grantStore,
            emailStore: emailStore,
            snapshotStore: snapshotStore,
            artifactIndex: artifactIndex,
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
        let source = try await harness.grantStore.source(id: sourceID)
        #expect(source != nil)
        let grant = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source!)])

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
        let source = try await harness.grantStore.source(id: sourceID)
        #expect(source != nil)
        let grant = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source!)])

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
        let source = try await harness.grantStore.source(id: sourceID)
        #expect(source != nil)
        _ = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source!)])

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
        let source = try await harness.grantStore.source(id: sourceID)
        #expect(source != nil)
        let grant = try await startMaterializedGrant(
            harness: harness,
            sources: [(sourceID, source!)],
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
        let source = try await harness.grantStore.source(id: sourceID)
        #expect(source != nil)
        let grant = try await startMaterializedGrant(
            harness: harness,
            sources: [(sourceID, source!)],
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
        let sourceA = try await harness.grantStore.source(id: sourceAID)
        let sourceB = try await harness.grantStore.source(id: sourceBID)
        _ = try await startMaterializedGrant(
            harness: harness,
            sources: [(sourceAID, sourceA!), (sourceBID, sourceB!)]
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
        let source = try await harness.grantStore.source(id: sourceID)
        #expect(source != nil)
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
            sources: [(source: source!, mountName: grantSources[0].mountName)],
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
        let source = try await harness.grantStore.source(id: sourceID)
        _ = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source!)])

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
        let source = try await harness.grantStore.source(id: sourceID)
        _ = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source!)])

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
        let source = try await harness.grantStore.source(id: sourceID)
        _ = try await startMaterializedGrant(harness: harness, sources: [(sourceID, source!)])

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
    }
}
