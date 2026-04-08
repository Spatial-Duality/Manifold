import Testing
import Foundation
@testable import ManifoldKit
@testable import ManifoldMCP

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
    }

    func makeHarness() throws -> Harness {
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
            artifactIndex: artifactIndex
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
            tempDir: tempDir
        )
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
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
        sources: [(id: String, record: SourceRecord)]
    ) async throws -> GrantRecord {
        let materializationRoot = harness.tempDir.appendingPathComponent("materialized/\(UUID().uuidString)")
        let grant = try await harness.grantStore.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: sources.map(\.id),
            materializationRoot: materializationRoot.path
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

        let message = try await harness.bridge.writeFile(path: "alpha/notes.md", content: "updated")
        #expect(message.contains("alpha/notes.md"))

        let history = try await harness.snapshotStore.history(runID: grant.grantID, filePath: "alpha/notes.md")
        #expect(!history.isEmpty)
        #expect(history.last?.source == "mcp")
        #expect(history.last?.afterHash != nil)

        let entries = try await harness.auditStore.recentEntries(limit: 10)
        let writeEntry = entries.first { $0.action == "file_modified" }
        #expect(writeEntry?.runID == grant.grantID)
        #expect(writeEntry?.workspaceID == sourceID)
        #expect(writeEntry?.filePath == "alpha/notes.md")
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
