import Foundation
import Testing
@testable import ManifoldKit

@Suite("EmailRuleStore")
struct EmailRuleStoreTests {
    func makeStores() throws -> (DatabaseConnection, PolicyStore, EmailRuleStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-email-rules-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        let policyStore = PolicyStore(db: db)
        let ruleStore = EmailRuleStore(db: db, policyStore: policyStore)
        return (db, policyStore, ruleStore, tempDir)
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Rule set roundtrips and syncs compatibility domains")
    func roundtripAndCompatibilitySync() async throws {
        let (_, policyStore, ruleStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let ruleSet = EmailRuleSet(
            agent: .codex,
            shields: EmailShieldCatalog.defaults(enabledByDefault: true),
            domainRules: [
                EmailDomainRule(agent: .codex, domain: "Example.COM", action: .allow),
                EmailDomainRule(agent: .codex, domain: "bank.com", action: .block),
            ],
            contactRules: [
                EmailContactRule(agent: .codex, name: "Ops", email: "ops@example.com", action: .allow),
            ],
            keywordRules: [
                EmailKeywordRule(agent: .codex, pattern: "confidential", matchLocation: .subjectAndBody, action: .block, isRegex: false),
            ],
            defaultPolicy: .blockUnlessAllowed,
            emailSensitivity: .strict
        )

        try await ruleStore.updateRuleSet(ruleSet)

        let reloaded = try await ruleStore.ruleSet(for: .codex)
        #expect(reloaded.defaultPolicy == .blockUnlessAllowed)
        #expect(reloaded.emailSensitivity == .strict)
        #expect(reloaded.domainRules.map(\.domain).contains("example.com"))
        #expect(reloaded.domainRules.map(\.domain).contains("bank.com"))
        #expect(reloaded.contactRules.first?.email == "ops@example.com")

        let policy = try await policyStore.policy(for: .codex)
        #expect(policy.defaultEmailPolicy == .blockUnlessAllowed)
        #expect(policy.emailSensitivity == .strict)
        #expect(policy.allowedEmailDomains == ["example.com"])
    }

    @Test("Duplicate domain rules are rejected")
    func duplicateDomainsRejected() async throws {
        let (_, _, ruleStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        let ruleSet = EmailRuleSet(
            agent: .cowork,
            domainRules: [
                EmailDomainRule(agent: .cowork, domain: "example.com", action: .allow),
                EmailDomainRule(agent: .cowork, domain: "EXAMPLE.com", action: .block),
            ]
        )

        await #expect(throws: EmailRuleValidationError.self) {
            try await ruleStore.updateRuleSet(ruleSet)
        }
    }

    @Test("Legacy domain command path updates runtime rule set")
    func upsertAndRemoveDomainRule() async throws {
        let (_, policyStore, ruleStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await ruleStore.upsertDomainRule(agent: .cowork, domain: "@docs.example.com", action: .allow)
        var ruleSet = try await ruleStore.ruleSet(for: .cowork)
        #expect(ruleSet.domainRules.count == 1)
        #expect(ruleSet.domainRules.first?.domain == "docs.example.com")
        #expect(try await policyStore.policy(for: .cowork).allowedEmailDomains == ["docs.example.com"])

        try await ruleStore.removeDomainRule(agent: .cowork, domain: "docs.example.com")
        ruleSet = try await ruleStore.ruleSet(for: .cowork)
        #expect(ruleSet.domainRules.isEmpty)
        #expect(try await policyStore.policy(for: .cowork).allowedEmailDomains.isEmpty)
    }

    @Test("Governance summary reflects runtime rule set instead of compatibility storage alone")
    func governanceSummaryReflectsRuleSet() async throws {
        let (_, _, ruleStore, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        var shields = EmailShieldCatalog.defaults(enabledByDefault: false)
        shields[0].isEnabled = true

        let ruleSet = EmailRuleSet(
            agent: .cowork,
            shields: shields,
            domainRules: [
                EmailDomainRule(agent: .cowork, domain: "example.com", action: .allow),
                EmailDomainRule(agent: .cowork, domain: "bank.com", action: .block),
            ],
            contactRules: [
                EmailContactRule(agent: .cowork, name: "Alice", email: "alice@example.com", action: .allow),
            ],
            keywordRules: [
                EmailKeywordRule(agent: .cowork, pattern: "roadmap", matchLocation: .subjectAndBody, action: .allow, isRegex: false),
                EmailKeywordRule(agent: .cowork, pattern: "confidential", matchLocation: .subjectAndBody, action: .block, isRegex: false),
            ],
            defaultPolicy: .allowUnlessBlocked,
            emailSensitivity: .open
        )

        try await ruleStore.updateRuleSet(ruleSet)

        let summary = try await ruleStore.emailGovernanceSummary(for: .cowork)
        #expect(summary.agent == .cowork)
        #expect(summary.enabledShieldCount == 1)
        #expect(summary.domainRuleCount == 2)
        #expect(summary.contactRuleCount == 1)
        #expect(summary.keywordRuleCount == 2)
        #expect(summary.defaultPolicy == .allowUnlessBlocked)
        #expect(summary.emailSensitivity == .open)
        #expect(summary.totalRuleCount == 5)
    }
}
