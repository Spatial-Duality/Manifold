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
        let approvalQueue: ApprovalQueue
        let exposureStore: ExposureStore
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
        let approvalQueue = ApprovalQueue(db: db)
        let exposureStore = ExposureStore(db: db)
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
            emailRuleStore: emailRuleStore,
            workBlockStore: workBlockStore,
            approvalQueue: approvalQueue,
            exposureStore: exposureStore,
            targetApp: targetApp,
            connectionID: connectionID
        )

        return Harness(
            db: db, contentStore: contentStore, snapshotStore: snapshotStore,
            auditStore: auditStore, grantStore: grantStore, emailStore: emailStore,
            artifactIndex: artifactIndex, policyStore: policyStore, emailRuleStore: emailRuleStore,
            workBlockStore: workBlockStore, approvalQueue: approvalQueue,
            exposureStore: exposureStore, bridge: bridge, tempDir: tempDir,
            connectionID: connectionID
        )
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

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

    // MARK: - Status Tests

    @Test("Status shows no access when a block-by-default agent has no standing grants")
    func emptyPolicyStatus() async throws {
        let h = try makeHarness(targetApp: .codex)
        defer { cleanup(h.tempDir) }

        let status = await h.bridge.getStatus()
        #expect(status.active == false)
        #expect(status.message.contains("No access configured"))
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

    @Test("Standing access write escalates and queues approval")
    func standingWriteEscalates() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)

        let result = try await h.bridge.writeFile(path: "myapp/README.md", content: "updated")
        switch result {
        case .escalationRequired(let message, let path):
            #expect(message.contains("read-only"))
            #expect(path == "myapp/README.md")
        case .written:
            Issue.record("Standing access should not write files directly")
        }

        let pending = try await h.approvalQueue.pending()
        #expect(pending.count == 1)
        #expect(pending[0].path == "myapp/README.md")
        #expect(pending[0].action == "write")
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
            $0.payloadPreview == "hello world" &&
            $0.payloadPreviewTruncated == false
        })
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
