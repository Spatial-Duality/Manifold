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
        let privacyStore: PrivacyStore
        let privacyCoordinator: PrivacyPreflightCoordinator
        let filterModeStore: FilterModeStore
        let exposureStore: ExposureStore
        let memoryStore: MemoryStore
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
        let privacyStore = PrivacyStore(db: db)
        let privacyCoordinator = PrivacyPreflightCoordinator(
            store: privacyStore,
            defaultStorageURL: tempDir.appendingPathComponent("privacy-models", isDirectory: true)
        )
        let filterModeStore = FilterModeStore(db: db)
        let exposureStore = ExposureStore(db: db)
        let memoryStore = try MemoryStore(db: db)
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
            memoryStore: memoryStore,
            capabilityHandleStore: capabilityHandleStore,
            ruleStore: ruleStore,
            privacyCoordinator: privacyCoordinator,
            filterModeStore: filterModeStore,
            filterModeFindingsProvider: RegexFilterFindingsProvider(),
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
            privacyStore: privacyStore,
            privacyCoordinator: privacyCoordinator,
            filterModeStore: filterModeStore,
            exposureStore: exposureStore, memoryStore: memoryStore,
            capabilityHandleStore: capabilityHandleStore,
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
        try harness.emailStore.updateBodyText(emailID: id, bodyText: body)
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

    @Test("Synthetic MCP/UI contract explores files, mail, rules, filters, and security")
    func syntheticMCPUIContractReport() async throws {
        let h = try makeHarness(targetApp: .codex)
        defer { cleanup(h.tempDir) }
        var report = SyntheticMCPUIReport()

        func createSource(name: String, files: [String: String]) async throws -> String {
            let sourceDir = h.tempDir.appendingPathComponent("synthetic/\(name)")
            try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
            for (relativePath, content) in files {
                let fileURL = sourceDir.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(content.utf8).write(to: fileURL)
            }
            return try await h.grantStore.addSource(displayName: name, rootPath: sourceDir.path)
        }

        func expectRejected(
            _ tool: String,
            _ invariant: String,
            operation: () async throws -> Void
        ) async {
            do {
                try await operation()
                report.record(tool, invariant, false)
            } catch {
                report.record(tool, invariant, true)
            }
        }

        func reportContains(_ text: String, _ needles: [String]) -> Bool {
            needles.allSatisfy { text.contains($0) }
        }

        let sharedID = try await createSource(
            name: "Shared",
            files: [
                "MANIFOLD_MCP_SHARED.txt": "MANIFOLD_MCP_SHARED original",
                "Docs/ModelGardenTeaParty.md": """
                MANIFOLD_OPENAI_ANTHROPIC_TEA_PARTY
                OpenAI brought eval cupcakes. Anthropic brought a tiny constitution printed on a napkin.
                The deterministic loop brought receipts.
                """,
                "Docs/ContextRequest.md": """
                CONTEXT_REQUEST_BRIEF
                User asks Codex to explain whether the model garden tea party can be shared safely.
                Backend should preserve the request intent without exposing blocked records.
                """,
                "Docs/KeyLimerick.txt": """
                FILTER_MODE_SECRET_MARKER
                There once was a test with a key: sk-OpenAIAnthropic1234567890ABCDE
                It stayed inside Manifold's policy tree.
                """,
                "Secrets/Handshake.txt": "DO_NOT_LEAK_HANDSHAKE shared secret should be denied by override."
            ]
        )
        let codexOnlyID = try await createSource(
            name: "Codex Only",
            files: [
                "CODEX_SYNTHETIC_TASK.md": "MANIFOLD_MCP_CODEX_ONLY task",
                "Evals/OpenAIEvalCupcakes.md": "OPENAI_EVAL_CUPCAKES Codex checks the frosting and the file scope."
            ]
        )
        _ = try await createSource(
            name: "Cowork Only",
            files: ["COWORK_PRIVATE_NOTE.md": "MANIFOLD_MCP_COWORK_ONLY"]
        )
        _ = try await createSource(
            name: "Blocked Private",
            files: ["PRIVATE_SECRET.txt": "MANIFOLD_MCP_BLOCKED_SECRET"]
        )
        let selectiveID = try await createSource(
            name: "Selective Lab",
            files: [
                "Public/BakeOff.md": "SELECTIVE_FILE_ALLOW_OPENAI_ANTHROPIC public bake-off notes.",
                "Private/SafetyValve.md": "DO_NOT_LEAK_SELECTIVE_PRIVATE private safety valve."
            ]
        )

        try await h.policyStore.addSource(sharedID, to: .codex)
        try await h.policyStore.addSource(codexOnlyID, to: .codex)
        try await h.fileVisibilityOverrideStore.setOverride(
            agent: .codex,
            sourceID: sharedID,
            relativePath: "Secrets/Handshake.txt",
            isDirectory: false,
            decision: .deny
        )
        try await h.fileVisibilityOverrideStore.setOverride(
            agent: .codex,
            sourceID: selectiveID,
            relativePath: "Public/BakeOff.md",
            isDirectory: false,
            decision: .allow
        )

        try await h.ruleStore.upsert(RuleRecord(
            name: "Warn on model garden tea party",
            explanation: "Synthetic file warning used by the MCP/UI loop.",
            scope: .file,
            matcher: .pathGlob("shared/Docs/ModelGardenTeaParty.md"),
            action: .warn,
            agents: [.codex]
        ))
        try await h.ruleStore.upsert(RuleRecord(
            name: "Deny shared handshake",
            explanation: "Synthetic deny guard for a shared-source private file.",
            scope: .file,
            matcher: .pathGlob("shared/Secrets/**"),
            action: .deny,
            agents: [.codex]
        ))
        try await h.ruleStore.upsert(RuleRecord(
            name: "Block rule-store email marker",
            explanation: "Synthetic email rule-store deny.",
            scope: .email,
            matcher: .emailKeyword(.anywhere, "RULE_STORE_DENY_MARKER", regex: false),
            action: .deny,
            agents: [.codex]
        ))

        try await h.emailRuleStore.updateRuleSet(EmailRuleSet(
            agent: .codex,
            domainRules: [
                EmailDomainRule(agent: .codex, domain: "openai.test", action: .allow),
                EmailDomainRule(agent: .codex, domain: "anthropic.test", action: .allow)
            ],
            contactRules: [
                EmailContactRule(agent: .codex, name: "Sable Alman", email: "sable@openai.test", action: .block)
            ],
            keywordRules: [
                EmailKeywordRule(
                    agent: .codex,
                    pattern: "confetti cannon",
                    matchLocation: .subjectAndBody,
                    action: .block,
                    isRegex: false
                )
            ],
            defaultPolicy: .blockUnlessAllowed,
            emailSensitivity: .strict
        ))

        try createEmail(
            harness: h,
            id: "synthetic-email-allowed",
            sender: "Synthetic QA <qa@synthetic.test>",
            senderEmail: "qa@synthetic.test",
            senderDomain: "synthetic.test",
            subject: "MANIFOLD_EMAIL_TEST allowed",
            body: "MANIFOLD_EMAIL_TEST_ALLOWED body for the deterministic MCP loop."
        )
        try createEmail(
            harness: h,
            id: "email-openai-tea-party",
            sender: "Model Garden <garden@openai.test>",
            senderEmail: "garden@openai.test",
            senderDomain: "openai.test",
            subject: "Model garden tea party",
            body: "EASTER_EGG_TEA_PARTY_ALLOWED OpenAI set the table with eval cupcakes."
        )
        try createEmail(
            harness: h,
            id: "email-openai-codex-semicolon",
            sender: "Codex Desk <codex@openai.test>",
            senderEmail: "codex@openai.test",
            senderDomain: "openai.test",
            subject: "Codex found the missing semicolon",
            body: "EASTER_EGG_SEMICOLON_ALLOWED The semicolon was under the test fixture."
        )
        try createEmail(
            harness: h,
            id: "email-anthropic-karaoke",
            sender: "Claude Notes <claude@anthropic.test>",
            senderEmail: "claude@anthropic.test",
            senderDomain: "anthropic.test",
            subject: "Constitutional karaoke for deterministic tests",
            body: "EASTER_EGG_KARAOKE_ALLOWED Anthropic harmonized with the acceptance criteria."
        )
        try createEmail(
            harness: h,
            id: "email-anthropic-napkin",
            sender: "Policy Poet <policy@anthropic.test>",
            senderEmail: "policy@anthropic.test",
            senderDomain: "anthropic.test",
            subject: "Tiny constitution on a napkin",
            body: "EASTER_EGG_NAPKIN_ALLOWED Useful, harmless, and easy to assert."
        )
        try createEmail(
            harness: h,
            id: "synthetic-email-blocked",
            sender: "Private QA <private@synthetic.test>",
            senderEmail: "private@synthetic.test",
            senderDomain: "synthetic.test",
            subject: "MANIFOLD_EMAIL_TEST blocked",
            body: "MANIFOLD_EMAIL_TEST_BLOCKED body must stay outside Codex scope."
        )
        try createEmail(
            harness: h,
            id: "email-blocked-contact",
            sender: "Sable Alman <sable@openai.test>",
            senderEmail: "sable@openai.test",
            senderDomain: "openai.test",
            subject: "Direct note that should not pass contact rules",
            body: "DO_NOT_LEAK_BLOCKED_CONTACT contact block should outrank domain allow."
        )
        try createEmail(
            harness: h,
            id: "email-blocked-keyword",
            sender: "Launch Ops <launch@openai.test>",
            senderEmail: "launch@openai.test",
            senderDomain: "openai.test",
            subject: "confetti cannon launch plan",
            body: "DO_NOT_LEAK_BLOCKED_KEYWORD keyword block should outrank domain allow."
        )
        try createEmail(
            harness: h,
            id: "email-blocked-default",
            sender: "Unknown Lab <unknown@external.test>",
            senderEmail: "unknown@external.test",
            senderDomain: "external.test",
            subject: "External default-block test",
            body: "DO_NOT_LEAK_EXTERNAL_DEFAULT default block should hide this thread."
        )
        try createEmail(
            harness: h,
            id: "email-rule-store-deny",
            sender: "Allowed Domain <allowed@openai.test>",
            senderEmail: "allowed@openai.test",
            senderDomain: "openai.test",
            subject: "Allowed domain with a runtime rule marker",
            body: "RULE_STORE_DENY_MARKER email policy allows this, but RuleStore must deny the body read."
        )
        try createEmail(
            harness: h,
            id: "email-shared-only-lighthouse",
            sender: "Shared Inbox <shared@synthetic.test>",
            senderEmail: "shared@synthetic.test",
            senderDomain: "synthetic.test",
            subject: "Shared-only lighthouse",
            body: "EASTER_EGG_SHARED_ONLY_ALLOWED shared email should pass without a domain allow."
        )
        try h.emailStore.shareEmails(emailIDs: [
            "synthetic-email-allowed",
            "email-shared-only-lighthouse"
        ], for: .codex)

        let status = await h.bridge.getStatus()
        report.record("get_status", "Codex standing access is active", status.active)
        report.record("get_status", "seven governed files are visible", status.fileCount == 7)
        report.record("get_status", "seven governed emails are visible", status.emailCount == 7)
        report.record("get_status", "current source map includes override-only source", status.sources.contains("Selective Lab"))

        let files = try await h.bridge.listFiles()
        let filePaths = Set(files.map(\.path))
        report.record("list_files", "shared marker is visible", filePaths.contains("shared/MANIFOLD_MCP_SHARED.txt"))
        report.record("list_files", "Codex-only marker is visible", filePaths.contains("codex-only/CODEX_SYNTHETIC_TASK.md"))
        report.record("list_files", "selectively allowed file is visible", filePaths.contains("selective-lab/Public/BakeOff.md"))
        report.record("list_files", "explicitly denied shared secret is hidden", !filePaths.contains("shared/Secrets/Handshake.txt"))
        report.record("list_files", "Cowork-only marker is hidden", !filePaths.contains("cowork-only/COWORK_PRIVATE_NOTE.md"))
        report.record("list_files", "blocked private marker is hidden", !filePaths.contains("blocked-private/PRIVATE_SECRET.txt"))

        let teaParty = try await h.bridge.readFile(path: "shared/Docs/ModelGardenTeaParty.md")
        report.record(
            "read_file",
            "warned but allowed model-garden file is readable",
            teaParty.contains("MANIFOLD_OPENAI_ANTHROPIC_TEA_PARTY")
        )
        let selective = try await h.bridge.readFile(path: "selective-lab/Public/BakeOff.md")
        report.record(
            "read_file",
            "explicit allow exposes one file from an otherwise hidden source",
            selective.contains("SELECTIVE_FILE_ALLOW_OPENAI_ANTHROPIC")
        )
        await expectRejected("read_file", "explicitly denied shared secret cannot be read") {
            _ = try await h.bridge.readFile(path: "shared/Secrets/Handshake.txt")
        }
        await expectRejected("read_file", "Cowork-only file cannot be read by Codex") {
            _ = try await h.bridge.readFile(path: "cowork-only/COWORK_PRIVATE_NOTE.md")
        }
        await expectRejected("read_file", "override-only source does not expose sibling private file") {
            _ = try await h.bridge.readFile(path: "selective-lab/Private/SafetyValve.md")
        }
        await expectRejected("read_file", "path traversal stays outside governed roots") {
            _ = try await h.bridge.readFile(path: "shared/../Blocked Private/PRIVATE_SECRET.txt")
        }

        let fileSearch = try await h.bridge.searchFiles(query: "OPENAI")
        let fileSearchPayload = fileSearch.map { "\($0.path)\n\($0.matches.joined(separator: "\n"))" }.joined(separator: "\n")
        report.record("search_files", "allowed file search returns Easter egg hits", fileSearchPayload.contains("MANIFOLD_OPENAI_ANTHROPIC_TEA_PARTY") || fileSearchPayload.contains("OPENAI_EVAL_CUPCAKES"))
        report.record("search_files", "blocked file markers are absent from search", !fileSearchPayload.contains("DO_NOT_LEAK"))

        let structured = try await h.bridge.searchStructured(query: "EASTER_EGG", limit: 20)
        report.record(
            "search_structured",
            "structured search includes allowed OpenAI/Anthropic mail",
            reportContains(structured, ["email-openai-tea-party", "email-anthropic-karaoke"])
        )
        report.record("search_structured", "structured search excludes blocked records", !structured.contains("DO_NOT_LEAK"))

        let listedEmails = try await h.bridge.listEmails()
        let listedEmailIDs = Set(listedEmails.map(\.id))
        report.record("list_emails", "domain-allowed OpenAI mail is listed", listedEmailIDs.contains("email-openai-tea-party"))
        report.record("list_emails", "domain-allowed Anthropic mail is listed", listedEmailIDs.contains("email-anthropic-karaoke"))
        report.record("list_emails", "shared-only mail is listed", listedEmailIDs.contains("email-shared-only-lighthouse"))
        report.record("list_emails", "blocked contact mail is not listed", !listedEmailIDs.contains("email-blocked-contact"))
        report.record("list_emails", "blocked keyword mail is not listed", !listedEmailIDs.contains("email-blocked-keyword"))
        report.record("list_emails", "default-blocked external mail is not listed", !listedEmailIDs.contains("email-blocked-default"))

        let searchedEmails = try await h.bridge.searchEmails(query: "MANIFOLD_EMAIL_TEST")
        let searchedEmailIDs = Set(searchedEmails.map(\.emailID))
        report.record("search_emails", "allowed synthetic email is visible", searchedEmailIDs.contains("synthetic-email-allowed"))
        report.record("search_emails", "blocked synthetic email is hidden", !searchedEmailIDs.contains("synthetic-email-blocked"))
        let easterEggEmails = try await h.bridge.searchEmails(query: "EASTER_EGG")
        let easterEggEmailIDs = Set(easterEggEmails.map(\.emailID))
        report.record(
            "search_emails",
            "many allowed Easter egg emails are searchable",
            easterEggEmailIDs.isSuperset(of: [
                "email-openai-tea-party",
                "email-openai-codex-semicolon",
                "email-anthropic-karaoke",
                "email-anthropic-napkin",
                "email-shared-only-lighthouse"
            ])
        )
        report.record("search_emails", "blocked Easter egg mail stays hidden", !easterEggEmails.compactMap(\.preview).joined().contains("DO_NOT_LEAK"))

        let emailBody = try await h.bridge.readEmail(id: "synthetic-email-allowed")
        report.record("read_email", "allowed email body is readable", emailBody.contains("MANIFOLD_EMAIL_TEST_ALLOWED"))
        let teaEmail = try await h.bridge.readEmail(id: "email-openai-tea-party")
        report.record("read_email", "domain-allowed OpenAI Easter egg body is readable", teaEmail.contains("EASTER_EGG_TEA_PARTY_ALLOWED"))
        let karaokeEmail = try await h.bridge.readEmail(id: "email-anthropic-karaoke")
        report.record("read_email", "domain-allowed Anthropic Easter egg body is readable", karaokeEmail.contains("EASTER_EGG_KARAOKE_ALLOWED"))
        await expectRejected("read_email", "blocked shared-policy email read is rejected") {
            _ = try await h.bridge.readEmail(id: "synthetic-email-blocked")
        }
        await expectRejected("read_email", "blocked contact outranks allowed domain") {
            _ = try await h.bridge.readEmail(id: "email-blocked-contact")
        }
        await expectRejected("read_email", "blocked keyword outranks allowed domain") {
            _ = try await h.bridge.readEmail(id: "email-blocked-keyword")
        }
        await expectRejected("read_email", "default block hides external email") {
            _ = try await h.bridge.readEmail(id: "email-blocked-default")
        }
        await expectRejected("read_email", "RuleStore email deny blocks an otherwise allowed domain") {
            _ = try await h.bridge.readEmail(id: "email-rule-store-deny")
        }

        let write = try await h.bridge.writeFile(
            path: "shared/MANIFOLD_MCP_SHARED.txt",
            content: "MANIFOLD_MCP_WRITE_OK by synthetic loop"
        )
        if case .written(_, let path) = write {
            report.record("write_file", "shared marker write uses governed path", path == "shared/MANIFOLD_MCP_SHARED.txt")
        } else {
            report.record("write_file", "shared marker write uses governed path", false)
        }
        await expectRejected("write_file", "writes to hidden source are rejected") {
            _ = try await h.bridge.writeFile(
                path: "blocked-private/PRIVATE_SECRET.txt",
                content: "bad write"
            )
        }
        await expectRejected("write_file", "expected-before-hash mismatch blocks stale writes") {
            _ = try await h.bridge.writeFile(
                path: "shared/MANIFOLD_MCP_SHARED.txt",
                content: "stale write",
                expectedBeforeHash: String(repeating: "0", count: 64)
            )
        }

        let changes = try await h.bridge.listChanges()
        report.record(
            "list_changes",
            "write appears in governed change history",
            changes.contains { $0.path == "shared/MANIFOLD_MCP_SHARED.txt" && $0.action == AuditAction.fileModified.rawValue }
        )

        try await h.filterModeStore.setMode(.warn, for: .codex)
        let warnedSecret = try await h.bridge.readFile(path: "shared/Docs/KeyLimerick.txt")
        report.record("filter_mode", "warn mode allows but records synthetic secret content", warnedSecret.contains("FILTER_MODE_SECRET_MARKER"))
        try await h.filterModeStore.setMode(.block, for: .codex)
        await expectRejected("filter_mode", "block mode denies detected synthetic secret content") {
            _ = try await h.bridge.readFile(path: "shared/Docs/KeyLimerick.txt")
        }
        try await h.filterModeStore.setMode(.off, for: .codex)

        let capabilityCreation = try await h.bridge.createValueHandle(
            origin: "shared/Docs/ContextRequest.md",
            sensitivity: "secret",
            trustLevel: "trusted",
            allowedSinks: ["external_ticket"]
        )
        let handleID = capabilityCreation
            .split(separator: " ")
            .first { $0.hasPrefix("handle-") }
            .map(String.init)
        report.record("create_value_handle", "sensitive contextual data receives a handle", handleID != nil)
        if let handleID {
            let flow = try await h.bridge.checkCapabilityFlow(
                handleID: handleID,
                sink: "external_ticket",
                untrustedInput: true,
                stateChangingAction: true
            )
            report.record(
                "check_capability_flow",
                "Rule of Two blocks untrusted state-changing flow",
                (flow.contains("\"allowed\": false") || flow.contains("\"allowed\":false"))
                    && flow.contains("Rule of Two")
            )
        }

        let verification = try await h.bridge.verifyClaimedActions(
            claimsJSON: #"[{"tool_name":"write_file","resource_path":"shared/MANIFOLD_MCP_SHARED.txt","text":"Synthetic MCP wrote the shared marker."}]"#
        )
        report.record("verify_claimed_actions", "claim verification returns a report", verification.contains("Claim verification"))

        try await h.policyStore.updateAccessRecordingLevel(.summary, for: .codex)
        let requestIntent = AccessIntent(
            summary: "Assess whether the synthetic OpenAI/Anthropic request can be shared",
            details: "CONTEXT_REQUEST_INTENT includes requested purpose, expected output, and safety constraints."
        )
        let contextualRead = try await h.bridge.readFile(
            path: "shared/Docs/ContextRequest.md",
            intent: requestIntent
        )
        report.record("backend_context_analysis", "contextual request file is readable with explicit intent", contextualRead.contains("CONTEXT_REQUEST_BRIEF"))
        let decisions = try await h.exposureStore.decisions(connectionID: h.connectionID, limit: 200)
        report.record(
            "backend_context_analysis",
            "backend access decision stores request summary",
            decisions.contains {
                $0.toolName == "read_file"
                    && $0.resourcePath == "shared/Docs/ContextRequest.md"
                    && $0.intentSummary == requestIntent.summary
            }
        )
        let exposures = try await h.exposureStore.exposures(connectionID: h.connectionID, limit: 200)
        report.record(
            "backend_context_analysis",
            "backend exposure record stores request details and redacted byte accounting",
            exposures.contains {
                $0.toolName == "read_file"
                    && $0.resourcePath == "shared/Docs/ContextRequest.md"
                    && $0.intentDetails == requestIntent.details
                    && $0.byteCount > 0
                    && ($0.payloadPreview?.contains("[redacted full_file") ?? false)
            }
        )

        try report.write(to: Self.syntheticReportURL())
        if !report.failures.isEmpty {
            Issue.record("\(report.render())")
        }
        #expect(report.failures.isEmpty)
    }

    @Test("OpenAI privacy filter synthetic harness protects mail, files, folders, PDFs, and writes")
    func openAIPrivacyFilterSyntheticMCPHarness() async throws {
        let h = try makeHarness(targetApp: .codex)
        defer { cleanup(h.tempDir) }

        func writeFixture(_ relativePath: String, _ content: String) throws -> URL {
            let url = h.tempDir.appendingPathComponent("sources/OpenAI Privacy Lab/\(relativePath)")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        func expectRuleDenied(
            _ expectedRuleName: String,
            operation: () async throws -> Void
        ) async {
            do {
                try await operation()
                Issue.record("Expected ruleDenied from \(expectedRuleName)")
            } catch let error as ManifoldMCPError {
                if case .ruleDenied(let ruleName, _) = error {
                    #expect(ruleName == expectedRuleName)
                } else {
                    Issue.record("Expected ruleDenied from \(expectedRuleName), got \(error)")
                }
            } catch {
                Issue.record("Expected ruleDenied from \(expectedRuleName), got \(error)")
            }
        }

        try await h.privacyCoordinator.updateSettings(PrivacyPreflightSettings(
            isEnabled: true,
            selectedBackend: .mlx,
            installState: .downloadRequired,
            storagePath: h.tempDir.appendingPathComponent("privacy-models", isDirectory: true).path
        ))
        try await h.privacyCoordinator.updatePolicy(AgentPrivacyPolicy(
            agent: .codex,
            textHandling: .warn,
            codeHandling: .ask,
            secretHandling: .warn,
            enabledCategories: Set(PrivacyCategory.allCases)
        ))
        let status = try await h.privacyCoordinator.runtimeStatus()
        #expect(status.selectedBackend == .mlx)
        #expect(status.effectiveBackend == .rulesOnly)

        try await h.emailRuleStore.updateRuleSet(EmailRuleSet(
            agent: .codex,
            domainRules: [
                EmailDomainRule(agent: .codex, domain: "openai.test", action: .allow),
                EmailDomainRule(agent: .codex, domain: "anthropic.test", action: .allow),
            ],
            defaultPolicy: .blockUnlessAllowed,
            emailSensitivity: .strict
        ))

        try await h.ruleStore.upsert(RuleRecord(
            id: "openai-privacy-email-secret-deny",
            name: "Deny synthetic secrets in mail",
            explanation: "Synthetic OpenAI privacy-filter test blocks mail containing detected secrets.",
            scope: .email,
            matcher: .privacyContainsCategory(.secret),
            action: .deny,
            agents: [.codex],
            orderIndex: 0
        ))
        try await h.ruleStore.upsert(RuleRecord(
            id: "openai-privacy-email-high-redact",
            name: "Redact high-risk synthetic mail",
            explanation: "Synthetic OpenAI privacy-filter test redacts high-risk PII/PPI mail.",
            scope: .email,
            matcher: .privacySeverityAtLeast(.high),
            action: .redact,
            agents: [.codex],
            orderIndex: 1
        ))
        try await h.ruleStore.upsert(RuleRecord(
            id: "openai-privacy-email-keyword-deny",
            name: "Block synthetic privacy bypass mail",
            explanation: "Classic email rule blocks a bypass marker before body delivery.",
            scope: .email,
            matcher: .emailKeyword(.anywhere, "DO_NOT_DELIVER_RAW_SYNTHETIC_PRIVACY", regex: false),
            action: .deny,
            agents: [.codex],
            orderIndex: 2
        ))
        try await h.ruleStore.upsert(RuleRecord(
            id: "openai-privacy-email-clean-log",
            name: "Log clean synthetic Anthropic mail",
            explanation: "Clean Anthropic Easter egg mail is allowed but logged for the harness.",
            scope: .email,
            matcher: .emailSubjectKeyword("Constitutional karaoke", regex: false),
            action: .log,
            agents: [.codex],
            orderIndex: 3
        ))
        try await h.ruleStore.upsert(RuleRecord(
            id: "openai-privacy-file-secret-deny",
            name: "Deny synthetic secrets in files",
            explanation: "Synthetic OpenAI privacy-filter test blocks file payloads containing detected secrets.",
            scope: .file,
            matcher: .privacyContainsCategory(.secret),
            action: .deny,
            agents: [.codex],
            orderIndex: 0
        ))
        try await h.ruleStore.upsert(RuleRecord(
            id: "openai-privacy-file-high-redact",
            name: "Redact high-risk synthetic files",
            explanation: "Synthetic OpenAI privacy-filter test redacts high-risk file PII/PPI.",
            scope: .file,
            matcher: .privacySeverityAtLeast(.high),
            action: .redact,
            agents: [.codex],
            orderIndex: 1
        ))
        try await h.ruleStore.upsert(RuleRecord(
            id: "openai-privacy-file-url-summarize",
            name: "Summarize synthetic research links",
            explanation: "URL-only research links should be summarized, not delivered raw.",
            scope: .file,
            matcher: .all([
                .pathGlob("openai-privacy-lab/Folder/ResearchLinks.md"),
                .privacyContainsCategory(.url),
            ]),
            action: .summarize,
            agents: [.codex],
            orderIndex: 2
        ))
        try await h.ruleStore.upsert(RuleRecord(
            id: "openai-privacy-file-date-downgrade",
            name: "Downgrade synthetic schedule dates",
            explanation: "Date-only schedules should expose metadata only.",
            scope: .file,
            matcher: .all([
                .pathGlob("openai-privacy-lab/Folder/Schedule.txt"),
                .privacyContainsCategory(.date),
            ]),
            action: .downgrade,
            agents: [.codex],
            orderIndex: 3
        ))
        try await h.ruleStore.upsert(RuleRecord(
            id: "openai-privacy-folder-deny",
            name: "Block synthetic private folder",
            explanation: "The Blocked folder is never shared with AI.",
            scope: .file,
            matcher: .pathGlob("openai-privacy-lab/Blocked/**"),
            action: .deny,
            agents: [.codex],
            orderIndex: 4
        ))
        try await h.ruleStore.upsert(RuleRecord(
            id: "openai-privacy-hidden-deny",
            name: "Block hidden synthetic files",
            explanation: "Hidden files are not exposed in the synthetic privacy harness.",
            scope: .file,
            matcher: .fileHidden,
            action: .deny,
            agents: [.codex],
            orderIndex: 5
        ))
        try await h.ruleStore.upsert(RuleRecord(
            id: "openai-privacy-write-secret-deny",
            name: "Block synthetic secret writes",
            explanation: "Writes containing obvious secret material are blocked.",
            scope: .file,
            matcher: .fileSecretDetected,
            action: .deny,
            agents: [.codex],
            orderIndex: 6
        ))
        try await h.ruleStore.upsert(RuleRecord(
            id: "openai-privacy-write-large-deny",
            name: "Block oversized synthetic write",
            explanation: "Large writes to this sentinel path require a separate review.",
            scope: .file,
            matcher: .all([
                .pathGlob("openai-privacy-lab/Folder/LargeWrite.md"),
                .fileSizeOver(128),
            ]),
            action: .deny,
            agents: [.codex],
            orderIndex: 7
        ))
        try await h.ruleStore.upsert(RuleRecord(
            id: "openai-privacy-pdf-warn",
            name: "Warn on synthetic PDF writes",
            explanation: "PDF writes are allowed but auditable in the synthetic harness.",
            scope: .file,
            matcher: .all([
                .pathGlob("openai-privacy-lab/Folder/*.pdf"),
                .fileExtension("pdf"),
            ]),
            action: .warn,
            agents: [.codex],
            orderIndex: 8
        ))
        try await h.ruleStore.upsert(RuleRecord(
            id: "openai-privacy-file-clean-log",
            name: "Log synthetic clean file",
            explanation: "Clean synthetic files are allowed but logged for audit coverage.",
            scope: .file,
            matcher: .pathGlob("openai-privacy-lab/Folder/CleanNote.md"),
            action: .log,
            agents: [.codex],
            orderIndex: 9
        ))

        let piiBody = """
        OPENAI_PRIVACY_FILTER_EASTER_EGG_PII eval cupcake picnic.
        Name: Ada Lovelace
        Email: ada.lovelace@openai.test
        Phone: +1 (415) 555-0199
        Address: 123 Eval Cupcake Street
        URL: https://privacy.openai.test/model-garden?ticket=42
        Date: 04/30/2026
        Account number: OPENAI-4242-0001
        Routing: 021000021
        Anthropic brought a tiny constitution printed on a napkin.
        """
        let secretBody = """
        OPENAI_PRIVACY_FILTER_EASTER_EGG_SECRET
        The eval cupcake safe contains OPENAI_API_KEY=sk-openaiAnthropicCupcake1234567890.
        GitHub token ghp_openAIEasterEggPrivacyToken123456 should never pass.
        """
        let cleanBody = """
        OPENAI_PRIVACY_FILTER_EASTER_EGG_CLEAN
        Model garden agenda: compare harmless test fixtures and celebrate deterministic assertions.
        """
        let blockedMarkerBody = """
        DO_NOT_DELIVER_RAW_SYNTHETIC_PRIVACY
        This mail should be blocked by a classic email keyword rule before any body is delivered.
        """

        try createEmail(
            harness: h,
            id: "openai-privacy-pii-mail",
            sender: "Model Garden Privacy <privacy@openai.test>",
            senderEmail: "privacy@openai.test",
            senderDomain: "openai.test",
            subject: "OpenAI privacy filter eval cupcake picnic",
            body: piiBody
        )
        try createEmail(
            harness: h,
            id: "openai-privacy-secret-mail",
            sender: "Token Librarian <tokens@openai.test>",
            senderEmail: "tokens@openai.test",
            senderDomain: "openai.test",
            subject: "OpenAI privacy filter secret cupcake",
            body: secretBody
        )
        try createEmail(
            harness: h,
            id: "anthropic-privacy-clean-mail",
            sender: "Constitutional Karaoke <karaoke@anthropic.test>",
            senderEmail: "karaoke@anthropic.test",
            senderDomain: "anthropic.test",
            subject: "Constitutional karaoke agenda",
            body: cleanBody
        )
        try createEmail(
            harness: h,
            id: "openai-privacy-keyword-blocked-mail",
            sender: "Bypass Tester <bypass@openai.test>",
            senderEmail: "bypass@openai.test",
            senderDomain: "openai.test",
            subject: "Synthetic privacy bypass marker",
            body: blockedMarkerBody
        )
        let extraMailFixtures: [(id: String, sender: String, senderEmail: String, senderDomain: String, subject: String, body: String)] = [
            (
                "openai-privacy-batch-clean-01",
                "OpenAI Eval Bakery <bakery@openai.test>",
                "bakery@openai.test",
                "openai.test",
                "Eval cupcake scorecard",
                "OPENAI_PRIVACY_FILTER_EASTER_EGG_BATCH Clean scorecard: tiny tests, big invariants, zero secrets."
            ),
            (
                "openai-privacy-batch-phone-02",
                "OpenAI Phonebook <phonebook@openai.test>",
                "phonebook@openai.test",
                "openai.test",
                "Phonebook entry for deterministic evals",
                "OPENAI_PRIVACY_FILTER_EASTER_EGG_BATCH Call Sable Alman at +1 (415) 555-0102 about account OPENAI-BATCH-0002."
            ),
            (
                "openai-privacy-batch-address-03",
                "OpenAI Map Room <maps@openai.test>",
                "maps@openai.test",
                "openai.test",
                "Map room coordinates",
                "OPENAI_PRIVACY_FILTER_EASTER_EGG_BATCH Ada Lovelace waits at 77 Transformer Terrace with routing 021000021."
            ),
            (
                "anthropic-privacy-batch-constitution-04",
                "Anthropic Pocket Constitution <rules@anthropic.test>",
                "rules@anthropic.test",
                "anthropic.test",
                "Pocket constitution found near the cupcakes",
                "OPENAI_PRIVACY_FILTER_EASTER_EGG_BATCH Claude left a polite note for Grace Hopper at grace@anthropic.test."
            ),
            (
                "openai-privacy-batch-url-05",
                "OpenAI Link Garden <links@openai.test>",
                "links@openai.test",
                "openai.test",
                "Link garden ticket",
                "OPENAI_PRIVACY_FILTER_EASTER_EGG_BATCH Review https://privacy.openai.test/garden and account OPENAI-BATCH-0005."
            ),
            (
                "anthropic-privacy-batch-date-06",
                "Anthropic Calendar <calendar@anthropic.test>",
                "calendar@anthropic.test",
                "anthropic.test",
                "Constitutional karaoke calendar",
                "OPENAI_PRIVACY_FILTER_EASTER_EGG_BATCH Meet Mario Amodei on May 2, 2026 with ledger ANTHROPIC-BATCH-0006."
            ),
            (
                "openai-privacy-batch-account-07",
                "OpenAI Ledger <ledger@openai.test>",
                "ledger@openai.test",
                "openai.test",
                "Ledger entry with account marker",
                "OPENAI_PRIVACY_FILTER_EASTER_EGG_BATCH Account: OPENAI-BATCH-0007 belongs in redacted output only."
            ),
            (
                "anthropic-privacy-batch-clean-08",
                "Anthropic Neat Relations <neat@anthropic.test>",
                "neat@anthropic.test",
                "anthropic.test",
                "Neat relation: models compare notes",
                "OPENAI_PRIVACY_FILTER_EASTER_EGG_BATCH Clean mail: OpenAI brought eval cupcakes; Anthropic brought napkins."
            ),
        ]
        for fixture in extraMailFixtures {
            try createEmail(
                harness: h,
                id: fixture.id,
                sender: fixture.sender,
                senderEmail: fixture.senderEmail,
                senderDomain: fixture.senderDomain,
                subject: fixture.subject,
                body: fixture.body
            )
        }

        let sourceRoot = h.tempDir.appendingPathComponent("sources/OpenAI Privacy Lab")
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        _ = try writeFixture("Folder/FieldTrip.md", piiBody.replacingOccurrences(of: "OPENAI_PRIVACY_FILTER_EASTER_EGG_PII", with: "OPENAI_PRIVACY_FILTER_FILE_EASTER_EGG"))
        _ = try writeFixture("Folder/CleanNote.md", "OPENAI_PRIVACY_FILTER_CLEAN_FILE OpenAI brought eval cupcakes; Anthropic brought napkins.")
        _ = try writeFixture("Folder/ResearchLinks.md", "OPENAI_PRIVACY_FILTER_LINK_ONLY https://privacy.openai.test/research/eval-cupcakes")
        _ = try writeFixture("Folder/Schedule.txt", "OPENAI_PRIVACY_FILTER_DATE_ONLY May 1, 2026")
        _ = try writeFixture("Secrets/OpenAIKey.env", "OPENAI_SECRET_FILE OPENAI_API_KEY=sk-openaiFileSecretCupcake1234567890")
        _ = try writeFixture("Blocked/DoNotRead.txt", "OPENAI_BLOCKED_FOLDER_MARKER should never reach MCP.")
        _ = try writeFixture("Folder/.HiddenPrompt.txt", "OPENAI_HIDDEN_FILE_MARKER should never reach MCP.")
        _ = try writeFixture("Folder/OpenAIPrivacyMenu.pdf", "FAKE-PDF OpenAI privacy menu\nName: Ada Lovelace\nAccount number: PDF-4242\n")

        let sourceID = try await h.grantStore.addSource(displayName: "OpenAI Privacy Lab", rootPath: sourceRoot.path)
        try await h.policyStore.addSource(sourceID, to: .codex)

        let emailSummaries = try await h.bridge.listEmails()
        let emailIDs = Set(emailSummaries.map(\.id))
        let expectedEmailIDs = Set([
            "openai-privacy-pii-mail",
            "openai-privacy-secret-mail",
            "anthropic-privacy-clean-mail",
            "openai-privacy-keyword-blocked-mail",
        ] + extraMailFixtures.map(\.id))
        #expect(emailIDs.isSuperset(of: expectedEmailIDs))
        #expect(emailIDs.intersection(expectedEmailIDs).count == 12)

        let redactedMail = try await h.bridge.readEmail(id: "openai-privacy-pii-mail")
        #expect(redactedMail.contains("[PERSON REDACTED]"))
        #expect(redactedMail.contains("[EMAIL REDACTED]"))
        #expect(redactedMail.contains("[PHONE REDACTED]"))
        #expect(redactedMail.contains("[ADDRESS REDACTED]"))
        #expect(redactedMail.contains("[URL REDACTED]"))
        #expect(redactedMail.contains("[DATE REDACTED]"))
        #expect(redactedMail.contains("[ACCOUNT REDACTED]"))
        #expect(!redactedMail.contains("Ada Lovelace"))
        #expect(!redactedMail.contains("ada.lovelace@openai.test"))
        #expect(!redactedMail.contains("OPENAI-4242-0001"))
        #expect(redactedMail.contains("eval cupcake picnic"))

        let cleanMail = try await h.bridge.readEmail(id: "anthropic-privacy-clean-mail")
        #expect(cleanMail.contains("Constitutional karaoke"))
        #expect(cleanMail.contains("deterministic assertions"))
        let cleanBatchMail = try await h.bridge.readEmail(id: "openai-privacy-batch-clean-01")
        #expect(cleanBatchMail.contains("tiny tests, big invariants"))
        let redactedBatchMail = try await h.bridge.readEmail(id: "openai-privacy-batch-account-07")
        #expect(redactedBatchMail.contains("[ACCOUNT REDACTED]"))
        #expect(!redactedBatchMail.contains("OPENAI-BATCH-0007"))

        await expectRuleDenied("Deny synthetic secrets in mail") {
            _ = try await h.bridge.readEmail(id: "openai-privacy-secret-mail")
        }
        await expectRuleDenied("Block synthetic privacy bypass mail") {
            _ = try await h.bridge.readEmail(id: "openai-privacy-keyword-blocked-mail")
        }

        let searchResults = try await h.bridge.searchEmails(query: "OPENAI_PRIVACY_FILTER_EASTER_EGG_PII")
        let piiSearch = try #require(searchResults.first { $0.emailID == "openai-privacy-pii-mail" })
        #expect(piiSearch.preview?.contains("[ACCOUNT REDACTED]") == true)
        #expect(piiSearch.preview?.contains("OPENAI-4242-0001") == false)
        #expect(!searchResults.contains { $0.emailID == "openai-privacy-secret-mail" })
        let batchSearchResults = try await h.bridge.searchEmails(query: "OPENAI_PRIVACY_FILTER_EASTER_EGG_BATCH")
        let batchSearchIDs = Set(batchSearchResults.map(\.emailID))
        #expect(batchSearchIDs.isSuperset(of: Set(extraMailFixtures.map(\.id))))
        #expect(batchSearchResults.contains { $0.preview?.contains("[ACCOUNT REDACTED]") == true })
        #expect(!batchSearchResults.contains { $0.preview?.contains("OPENAI-BATCH-0007") == true })

        let files = try await h.bridge.listFiles()
        let filePaths = Set(files.map(\.path))
        #expect(filePaths.contains("openai-privacy-lab/Folder/FieldTrip.md"))
        #expect(filePaths.contains("openai-privacy-lab/Folder/CleanNote.md"))
        #expect(filePaths.contains("openai-privacy-lab/Folder/OpenAIPrivacyMenu.pdf"))
        #expect(filePaths.contains("openai-privacy-lab/Blocked/DoNotRead.txt"))

        let redactedFile = try await h.bridge.readFile(path: "openai-privacy-lab/Folder/FieldTrip.md")
        #expect(redactedFile.contains("[PERSON REDACTED]"))
        #expect(redactedFile.contains("[ACCOUNT REDACTED]"))
        #expect(!redactedFile.contains("Ada Lovelace"))
        #expect(!redactedFile.contains("OPENAI-4242-0001"))

        let summarizedLinks = try await h.bridge.readFile(path: "openai-privacy-lab/Folder/ResearchLinks.md")
        #expect(summarizedLinks.hasPrefix("Privacy summary:"))
        #expect(!summarizedLinks.contains("https://privacy.openai.test"))

        let downgradedSchedule = try await h.bridge.readFile(path: "openai-privacy-lab/Folder/Schedule.txt")
        #expect(downgradedSchedule == "Privacy metadata only: Dates")
        let cleanFile = try await h.bridge.readFile(path: "openai-privacy-lab/Folder/CleanNote.md")
        #expect(cleanFile.contains("eval cupcakes"))

        await expectRuleDenied("Deny synthetic secrets in files") {
            _ = try await h.bridge.readFile(path: "openai-privacy-lab/Secrets/OpenAIKey.env")
        }
        await expectRuleDenied("Block synthetic private folder") {
            _ = try await h.bridge.readFile(path: "openai-privacy-lab/Blocked/DoNotRead.txt")
        }
        await expectRuleDenied("Block hidden synthetic files") {
            _ = try await h.bridge.readFile(path: "openai-privacy-lab/Folder/.HiddenPrompt.txt")
        }

        let fileSearch = try await h.bridge.searchFiles(query: "Account")
        let fieldTripSearch = try #require(fileSearch.first { $0.path == "openai-privacy-lab/Folder/FieldTrip.md" })
        let fieldTripSearchText = fieldTripSearch.matches.joined(separator: "\n")
        #expect(fieldTripSearchText.contains("[ACCOUNT REDACTED]"))
        #expect(!fieldTripSearchText.contains("OPENAI-4242-0001"))

        await expectRuleDenied("Block synthetic secret writes") {
            _ = try await h.bridge.writeFile(
                path: "openai-privacy-lab/Folder/GeneratedSecret.md",
                content: "AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF"
            )
        }
        await expectRuleDenied("Block oversized synthetic write") {
            _ = try await h.bridge.writeFile(
                path: "openai-privacy-lab/Folder/LargeWrite.md",
                content: String(repeating: "large-write-eval-cupcake ", count: 8)
            )
        }

        do {
            _ = try await h.bridge.writeFile(path: "openai-privacy-lab/Folder/OpenAIPrivacyMenu.pdf", content: "%PDF-1.4")
            Issue.record("write_file should reject text writes to PDF paths")
        } catch let error as ManifoldMCPError {
            if case .invalidPath(let message) = error {
                #expect(message.contains("write_file is UTF-8 text only"))
                #expect(message.contains("write_binary_file"))
            } else {
                Issue.record("Expected invalidPath for text PDF write, got \(error)")
            }
        }

        let writtenPDF = Data("%PDF-1.4\n% OPENAI_PRIVACY_FILTER_WRITTEN_PDF\n%%EOF\n".utf8)
        let binaryWrite = try await h.bridge.writeBinaryFile(
            path: "openai-privacy-lab/Folder/GeneratedReport.pdf",
            contentBase64: writtenPDF.base64EncodedString(),
            mimeType: "application/pdf"
        )
        if case .written(_, let path) = binaryWrite {
            #expect(path == "openai-privacy-lab/Folder/GeneratedReport.pdf")
        } else {
            Issue.record("Expected write_binary_file to write the synthetic PDF")
        }
        let generatedPDFURL = sourceRoot.appendingPathComponent("Folder/GeneratedReport.pdf")
        #expect(try Data(contentsOf: generatedPDFURL) == writtenPDF)

        do {
            _ = try await h.bridge.annotatePDF(path: "openai-privacy-lab/Folder/OpenAIPrivacyMenu.pdf", mark: "OpenAI privacy filter checked")
            Issue.record("annotate_pdf should reject the fake unreadable PDF")
        } catch let error as ManifoldMCPError {
            if case .invalidPath(let message) = error {
                #expect(message.contains("annotate_pdf"))
            } else {
                Issue.record("Expected invalidPath for fake PDF annotation, got \(error)")
            }
        }

        let changes = try await h.bridge.listChanges()
        #expect(changes.contains { $0.path == "openai-privacy-lab/Folder/GeneratedReport.pdf" })

        let eventRows = try h.db.queryAll("""
            SELECT tool_name, outcome, matched_categories_json
            FROM privacy_scan_events
            WHERE agent = ?
            ORDER BY created_at ASC
        """, params: [TargetApp.codex.rawValue])
        let eventText = eventRows.map { row in
            [row["tool_name"], row["outcome"], row["matched_categories_json"]]
                .compactMap { $0 }
                .joined(separator: " ")
        }.joined(separator: "\n")
        for category in PrivacyCategory.allCases {
            #expect(eventText.contains(category.rawValue))
        }
        #expect(eventText.contains("warning"))

        let auditRows = try h.db.queryAll("""
            SELECT metadata
            FROM audit_log
            WHERE agent = ? AND metadata LIKE '%rule_decision%'
            ORDER BY id ASC
        """, params: [TargetApp.codex.rawValue])
        let auditText = auditRows.compactMap { $0["metadata"] }.joined(separator: "\n")
        for decision in ["redact", "deny", "summarize", "downgrade", "warn", "log"] {
            #expect(auditText.contains(#""rule_decision":"\#(decision)""#))
        }
    }

    static func syntheticReportURL() throws -> URL {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/self-improvement", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("synthetic-mcp-ui-report.txt")
    }

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

    @Test("Session request detail override is resolved at MCP boundary")
    func sessionRequestDetailOverrideControlsIntentRequirement() async throws {
        let h = try makeHarness()
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "MyApp")
        try await h.policyStore.addSource(sourceID, to: .cowork)
        try await h.policyStore.updateAccessRecordingLevel(.lightweight, for: .cowork)
        let grant = try await h.grantStore.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [sourceID],
            materializationRoot: h.tempDir.appendingPathComponent("request-detail-grant").path,
            requestDetailLevel: .summary
        )

        do {
            _ = try await h.bridge.readFile(path: "myapp/README.md")
            Issue.record("Expected session request detail to require intent")
        } catch let error as ManifoldMCPError {
            if case .intentRequired = error {
                // Expected.
            } else {
                Issue.record("Expected intentRequired, got \(error)")
            }
        }

        try await h.grantStore.updateRequestDetailLevel(grantID: grant.grantID, level: nil)
        let content = try await h.bridge.readFile(path: "myapp/README.md")
        #expect(content == "hello world")

        let policy = try await h.policyStore.policy(for: .cowork)
        #expect(policy.accessRecordingLevel == .lightweight)
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

    @Test("Explicit email work block also exposes later shared emails")
    func explicitEmailWorkBlockKeepsCurrentSharedEmailAccess() async throws {
        let h = try makeHarness(targetApp: .codex)
        defer { cleanup(h.tempDir) }

        try createEmail(
            harness: h,
            id: "email-selected",
            sender: "Session Notes <session@example.com>",
            senderEmail: "session@example.com",
            senderDomain: "example.com",
            subject: "Selected in session",
            body: "Email selected when the session started."
        )
        try createEmail(
            harness: h,
            id: "email-shared-later",
            sender: "Mail UI <share@example.com>",
            senderEmail: "share@example.com",
            senderDomain: "example.com",
            subject: "Shared after session",
            body: "Email explicitly shared with Codex after the session started."
        )
        try createEmail(
            harness: h,
            id: "email-unshared",
            sender: "Private Mail <private@example.com>",
            senderEmail: "private@example.com",
            senderDomain: "example.com",
            subject: "Not shared",
            body: "This email was neither selected nor shared."
        )
        try h.emailStore.shareEmails(emailIDs: ["email-shared-later"], for: .codex)

        let grant = try await h.grantStore.startGrant(
            targetApp: .codex,
            profileID: "default",
            sourceIDs: [],
            materializationRoot: h.tempDir.appendingPathComponent("explicit-email-grant").path,
            emailSensitivity: EmailSensitivityLevel.strict.rawValue,
            explicitSelection: true
        )
        try h.emailStore.replaceGrantEmails(grantID: grant.grantID, emailIDs: ["email-selected"])
        _ = try await h.workBlockStore.startBlock(agent: .codex, grantID: grant.grantID, sourceIDs: [])

        let emails = try await h.bridge.listEmails()
        let ids = Set(emails.map(\.id))
        #expect(ids.contains("email-selected"))
        #expect(ids.contains("email-shared-later"))
        #expect(!ids.contains("email-unshared"))
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

    @Test("Active default work block picks up sources newly shared in Access")
    func activeWorkBlockPicksUpNewlySharedSources() async throws {
        let h = try makeHarness(targetApp: .codex)
        defer { cleanup(h.tempDir) }

        let sourceID = try await createAndRegisterSource(harness: h, name: "HR")
        let grant = try await h.grantStore.startGrant(
            targetApp: .codex,
            profileID: "default",
            sourceIDs: [],
            materializationRoot: h.tempDir.appendingPathComponent("default-grant").path,
            explicitSelection: false
        )
        _ = try await h.workBlockStore.startBlock(
            agent: .codex,
            grantID: grant.grantID,
            sourceIDs: []
        )

        let before = try await h.bridge.listFiles()
        #expect(before.isEmpty)

        try await h.policyStore.addSource(sourceID, to: .codex)

        let after = try await h.bridge.listFiles()
        #expect(after.contains { $0.path == "hr/README.md" && $0.sourceName == "hr" })
        #expect(after.contains { $0.path == "hr/src/main.swift" && $0.sourceName == "hr" })
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

private struct SyntheticMCPUIReport {
    private(set) var rows: [String] = []
    private(set) var failures: [String] = []

    mutating func record(_ tool: String, _ invariant: String, _ passed: Bool) {
        record(
            mcpCall: tool,
            expectedUIState: invariant,
            actualUIState: passed ? "matches MCP contract" : "does not match MCP contract",
            invariant: invariant,
            passed: passed,
            likelySubsystem: likelySubsystem(for: tool)
        )
    }

    mutating func record(
        mcpCall: String,
        expectedUIState: String,
        actualUIState: String,
        invariant: String,
        passed: Bool,
        likelySubsystem: String
    ) {
        let status = passed ? "pass" : "fail"
        let row = """
        [\(status)] mcp_call=\(mcpCall) | expected_ui_state=\(expectedUIState) | actual_ui_state=\(actualUIState) | invariant=\(invariant) | likely_subsystem=\(likelySubsystem)
        """
        rows.append(row)
        if !passed {
            failures.append(row)
        }
    }

    private func likelySubsystem(for tool: String) -> String {
        switch tool {
        case "get_status":
            return "runtime status"
        case "list_files", "read_file", "search_files", "write_file", "list_changes":
            return "file scope"
        case "search_structured":
            return "structured search"
        case "list_emails", "search_emails", "read_email", "read_email_eml":
            return "email scope"
        case "filter_mode":
            return "privacy filter mode"
        case "create_value_handle", "check_capability_flow":
            return "capability flow"
        case "verify_claimed_actions":
            return "action verification"
        case "backend_context_analysis":
            return "access intent recording"
        default:
            return "synthetic MCP/UI loop"
        }
    }

    func render() -> String {
        """
        Synthetic MCP/UI self-improvement report
        \(rows.joined(separator: "\n"))
        """
    }

    func write(to url: URL) throws {
        try render().write(to: url, atomically: true, encoding: .utf8)
    }
}
