// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
@testable import ManifoldKit

@Suite("Rule engine — precedence & matchers")
struct RuleEngineTests {
    let engine = RuleEngine()

    // MARK: - Basics

    @Test("No rules → default policy allow")
    func noRulesDefaultAllow() {
        let decision = engine.evaluate(
            .fileRead(path: "/tmp/notes.md"),
            against: [],
            agent: .cowork,
            context: RuleEvalContext()
        )
        #expect(decision.action == .allow)
        #expect(decision.defaultPolicyApplied == true)
        #expect(decision.matchedRuleID == nil)
    }

    @Test("Path glob match yields deny")
    func pathGlobDeny() {
        let rule = RuleRecord(
            id: "r1",
            name: "Block env files",
            scope: .file,
            matcher: .pathGlob("**/.env"),
            action: .deny,
            source: .user
        )
        let decision = engine.evaluate(
            .fileRead(path: "/Users/x/.env"),
            against: [rule],
            agent: .cowork,
            context: RuleEvalContext()
        )
        #expect(decision.action == .deny)
        #expect(decision.matchedRuleID == "r1")
        #expect(decision.defaultPolicyApplied == false)
    }

    @Test("Disabled rule never fires")
    func disabledRuleIgnored() {
        let rule = RuleRecord(
            id: "r1", name: "Dormant", scope: .file,
            matcher: .pathGlob("**/.env"), action: .deny,
            source: .user, enabled: false
        )
        let decision = engine.evaluate(
            .fileRead(path: "/etc/.env"),
            against: [rule],
            agent: .cowork,
            context: RuleEvalContext()
        )
        #expect(decision.action == .allow)
        #expect(decision.defaultPolicyApplied == true)
    }

    // MARK: - Precedence

    @Test("Deny-wins preempts allow regardless of list order")
    func denyWinsOverOutOfOrderAllow() {
        let allow = RuleRecord(
            id: "allow", name: "Allow source",
            scope: .file, matcher: .pathGlob("**/*.swift"),
            action: .allow, source: .user, orderIndex: 0
        )
        let deny = RuleRecord(
            id: "deny", name: "Deny secrets",
            scope: .file, matcher: .pathGlob("**/.env"),
            action: .deny, source: .user, orderIndex: 1
        )
        let decision = engine.evaluate(
            .fileRead(path: "/app/.env"),
            against: [allow, deny],
            agent: .cowork,
            context: RuleEvalContext()
        )
        #expect(decision.action == .deny)
        #expect(decision.matchedRuleID == "deny")
    }

    @Test("Seeded rules fire before user rules of same action")
    func seededBeatsUserWithinSameAction() {
        let seed = RuleRecord(
            id: "seed", name: "Seed warn",
            scope: .file, matcher: .pathGlob("**/*.zip"),
            action: .warn, source: .seeded, orderIndex: 0
        )
        let user = RuleRecord(
            id: "user", name: "User warn",
            scope: .file, matcher: .pathGlob("**/*.zip"),
            action: .warn, source: .user, orderIndex: 0
        )
        let decision = engine.evaluate(
            .fileRead(path: "/tmp/archive.zip"),
            against: [user, seed],  // user first in list
            agent: .cowork,
            context: RuleEvalContext()
        )
        #expect(decision.action == .warn)
        #expect(decision.matchedRuleID == "seed") // seed preempted by group priority
    }

    @Test("First-match within same-priority group honors orderIndex")
    func firstMatchWithinGroup() {
        let a = RuleRecord(
            id: "a", name: "A", scope: .file,
            matcher: .pathGlob("**/*.log"), action: .log,
            source: .user, orderIndex: 1
        )
        let b = RuleRecord(
            id: "b", name: "B", scope: .file,
            matcher: .pathGlob("**/*.log"), action: .warn,
            source: .user, orderIndex: 0
        )
        let decision = engine.evaluate(
            .fileRead(path: "/tmp/debug.log"),
            against: [a, b],
            agent: .cowork,
            context: RuleEvalContext()
        )
        #expect(decision.matchedRuleID == "b")      // lower orderIndex wins
        #expect(decision.action == .warn)
    }

    // MARK: - Combinators

    @Test("AND combinator requires every sub-matcher to match")
    func andCombinator() {
        let rule = RuleRecord(
            id: "and", name: "Big old binary",
            scope: .file,
            matcher: .all([.fileSizeOver(1_000), .pathGlob("**/*.bin")]),
            action: .deny, source: .user
        )
        let bigBin = RuleEvalContext(fileProbe: FileProbe(path: "/a/big.bin", sizeBytes: { 5_000 }))
        let smallBin = RuleEvalContext(fileProbe: FileProbe(path: "/a/small.bin", sizeBytes: { 100 }))
        let bigTxt = RuleEvalContext(fileProbe: FileProbe(path: "/a/big.txt", sizeBytes: { 5_000 }))

        #expect(engine.evaluate(.fileRead(path: "/a/big.bin"), against: [rule], agent: .cowork, context: bigBin).action == .deny)
        #expect(engine.evaluate(.fileRead(path: "/a/small.bin"), against: [rule], agent: .cowork, context: smallBin).action == .allow)
        #expect(engine.evaluate(.fileRead(path: "/a/big.txt"), against: [rule], agent: .cowork, context: bigTxt).action == .allow)
    }

    @Test("OR combinator fires on any match")
    func orCombinator() {
        let rule = RuleRecord(
            id: "or", name: "Any secret path",
            scope: .file,
            matcher: .any([.pathGlob("**/.env"), .pathGlob("**/.ssh/**")]),
            action: .deny, source: .user
        )
        #expect(engine.evaluate(.fileRead(path: "/x/.env"), against: [rule], agent: .cowork, context: .init()).action == .deny)
        #expect(engine.evaluate(.fileRead(path: "/x/.ssh/id_rsa"), against: [rule], agent: .cowork, context: .init()).action == .deny)
        #expect(engine.evaluate(.fileRead(path: "/x/readme.md"), against: [rule], agent: .cowork, context: .init()).action == .allow)
    }

    @Test("NOT negates the child matcher")
    func notCombinator() {
        let rule = RuleRecord(
            id: "not", name: "Non-markdown files",
            scope: .file, matcher: .not(.pathGlob("**/*.md")),
            action: .warn, source: .user
        )
        #expect(engine.evaluate(.fileRead(path: "/a/notes.txt"), against: [rule], agent: .cowork, context: .init()).action == .warn)
        #expect(engine.evaluate(.fileRead(path: "/a/notes.md"), against: [rule], agent: .cowork, context: .init()).action == .allow)
    }

    // MARK: - Agent targeting

    @Test("Empty agents set applies to every agent")
    func emptyAgentsMeansAll() {
        let rule = RuleRecord(
            id: "r", name: "Global deny",
            scope: .file, matcher: .pathGlob("**/*"),
            action: .deny, agents: [], source: .user
        )
        #expect(engine.evaluate(.fileRead(path: "/x"), against: [rule], agent: .cowork, context: .init()).action == .deny)
        #expect(engine.evaluate(.fileRead(path: "/x"), against: [rule], agent: .codex, context: .init()).action == .deny)
    }

    @Test("Agent-specific rule ignores other agents")
    func agentFiltering() {
        let rule = RuleRecord(
            id: "codex-only", name: "Codex tight",
            scope: .file, matcher: .pathGlob("**/.git/**"),
            action: .deny, agents: [.codex], source: .user
        )
        #expect(engine.evaluate(.fileRead(path: "/r/.git/config"), against: [rule], agent: .codex, context: .init()).action == .deny)
        #expect(engine.evaluate(.fileRead(path: "/r/.git/config"), against: [rule], agent: .cowork, context: .init()).action == .allow)
    }

    // MARK: - Email matchers

    @Test("Email domain wildcard matches subdomains")
    func emailDomainWildcard() {
        let rule = RuleRecord(
            id: "e", name: "Block banks",
            scope: .email, matcher: .emailDomain("*.bank.com"),
            action: .deny, source: .user
        )
        let chase = RuleEvalContext(emailProbe: EmailProbe(
            emailID: "m1", senderEmail: "noreply@cards.bank.com", senderDomain: "cards.bank.com", subject: "x"
        ))
        let other = RuleEvalContext(emailProbe: EmailProbe(
            emailID: "m2", senderEmail: "a@example.com", senderDomain: "example.com", subject: "x"
        ))
        #expect(engine.evaluate(.emailRead(emailID: "m1"), against: [rule], agent: .cowork, context: chase).action == .deny)
        #expect(engine.evaluate(.emailRead(emailID: "m2"), against: [rule], agent: .cowork, context: other).action == .allow)
    }

    @Test("Email shield fires via probe")
    func emailShieldMatches() {
        let rule = RuleRecord(
            id: "shield", name: "Security shield",
            scope: .email, matcher: .emailShield(.security),
            action: .deny, source: .seeded
        )
        let probe = EmailProbe(
            emailID: "m", senderEmail: "no@x.com", senderDomain: "x.com",
            subject: "Verify", matchedShields: [.security]
        )
        let ctx = RuleEvalContext(emailProbe: probe)
        #expect(engine.evaluate(.emailRead(emailID: "m"), against: [rule], agent: .cowork, context: ctx).action == .deny)
    }

    @Test("Email keyword anywhere searches all fields")
    func emailKeywordAnywhere() {
        let rule = RuleRecord(
            id: "kw", name: "Block 2fa",
            scope: .email, matcher: .emailKeyword(.anywhere, "2fa", regex: false),
            action: .deny, source: .user
        )
        let probe = EmailProbe(
            emailID: "m", senderEmail: "x@y.com", senderDomain: "y.com",
            subject: "Hi", bodyText: "Your 2FA code is 123456."
        )
        let ctx = RuleEvalContext(emailProbe: probe)
        #expect(engine.evaluate(.emailRead(emailID: "m"), against: [rule], agent: .cowork, context: ctx).action == .deny)
    }

    // MARK: - Agent-scope matchers

    @Test("agentWrite catches both write and delete tools")
    func agentWriteFamily() {
        let rule = RuleRecord(
            id: "ro", name: "Read-only Codex",
            scope: .agent, matcher: .agentWrite,
            action: .deny, agents: [.codex], source: .user
        )
        let wCtx = RuleEvalContext(agentProbe: AgentProbe(agent: .codex, tool: .write))
        let dCtx = RuleEvalContext(agentProbe: AgentProbe(agent: .codex, tool: .delete))
        let rCtx = RuleEvalContext(agentProbe: AgentProbe(agent: .codex, tool: .read))

        #expect(engine.evaluate(.agentTool(tool: .write, payloadBytes: nil), against: [rule], agent: .codex, context: wCtx).action == .deny)
        #expect(engine.evaluate(.agentTool(tool: .delete, payloadBytes: nil), against: [rule], agent: .codex, context: dCtx).action == .deny)
        #expect(engine.evaluate(.agentTool(tool: .read, payloadBytes: nil), against: [rule], agent: .codex, context: rCtx).action == .allow)
    }

    // MARK: - Privacy matchers

    @Test("Privacy category rules use the privacy probe")
    func privacyCategoryUsesProbe() {
        let rule = RuleRecord(
            id: "privacy-secret",
            name: "Block secrets",
            scope: .file,
            matcher: .privacyContainsCategory(.secret),
            action: .deny,
            source: .user
        )
        let context = RuleEvalContext(
            privacyProbe: PrivacyProbe(categories: [.secret], severity: .critical)
        )

        let decision = engine.evaluate(
            .fileRead(path: "/repo/.env"),
            against: [rule],
            agent: .codex,
            context: context
        )

        #expect(decision.action == .deny)
        #expect(decision.matchedRuleID == "privacy-secret")
    }

    @Test("Privacy rules do not fire without model findings")
    func privacyRulesNeedProbeFindings() {
        let rule = RuleRecord(
            id: "privacy-high",
            name: "Redact high privacy content",
            scope: .email,
            matcher: .privacySeverityAtLeast(.high),
            action: .redact,
            source: .user
        )

        let decision = engine.evaluate(
            .emailRead(emailID: "m1"),
            against: [rule],
            agent: .cowork,
            context: RuleEvalContext()
        )

        #expect(decision.action == .allow)
        #expect(decision.defaultPolicyApplied == true)
    }

    // MARK: - Windows

    @Test("sessionOnly rule ignored when no session is active")
    func sessionOnlyWindow() {
        let rule = RuleRecord(
            id: "s", name: "Session-only",
            scope: .file, matcher: .pathGlob("**/*.md"),
            action: .warn, window: .sessionOnly, source: .user
        )
        let active = RuleEvalContext(sessionActive: true)
        let inactive = RuleEvalContext(sessionActive: false)

        #expect(engine.evaluate(.fileRead(path: "/a.md"), against: [rule], agent: .cowork, context: active).action == .warn)
        #expect(engine.evaluate(.fileRead(path: "/a.md"), against: [rule], agent: .cowork, context: inactive).action == .allow)
    }

    @Test("until(date) window expires")
    func untilWindow() {
        let past = Date().addingTimeInterval(-60)
        let future = Date().addingTimeInterval(60)

        let expired = RuleRecord(
            id: "x", name: "Expired",
            scope: .file, matcher: .pathGlob("**/*"), action: .deny,
            window: .until(past), source: .user
        )
        let live = RuleRecord(
            id: "l", name: "Live",
            scope: .file, matcher: .pathGlob("**/*"), action: .deny,
            window: .until(future), source: .user
        )

        #expect(engine.evaluate(.fileRead(path: "/x"), against: [expired], agent: .cowork, context: .init()).action == .allow)
        #expect(engine.evaluate(.fileRead(path: "/x"), against: [live], agent: .cowork, context: .init()).action == .deny)
    }

    // MARK: - Codec round-trip

    @Test("RuleMatcher round-trips through JSON")
    func matcherRoundTrip() throws {
        let matcher: RuleMatcher = .all([
            .pathGlob("**/*.rs"),
            .not(.fileHidden),
            .any([.fileSizeOver(1_000), .fileBinary]),
        ])
        let data = try JSONEncoder().encode(matcher)
        let decoded = try JSONDecoder().decode(RuleMatcher.self, from: data)
        #expect(decoded == matcher)
    }

    @Test("RuleRecord round-trips through JSON")
    func recordRoundTrip() throws {
        let rule = RuleRecord(
            id: "rt", name: "Round-trip",
            scope: .email, matcher: .emailShield(.financial),
            action: .warn, agents: [.cowork, .codex],
            window: .sessionOnly, source: .user
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RuleRecord.self, from: data)
        #expect(decoded == rule)
    }

    // MARK: - Validation

    @Test("Validator rejects scope mismatches")
    func validatorRejectsScopeMismatch() {
        let bad = RuleRecord(
            id: "mismatch", name: "Bad",
            scope: .file, matcher: .emailShield(.security),
            action: .deny, source: .user
        )
        #expect(throws: RuleValidationError.self) { try RuleValidator.validate(bad) }
    }

    @Test("Validator rejects empty names")
    func validatorRejectsEmptyName() {
        let bad = RuleRecord(
            id: "e", name: "   ",
            scope: .file, matcher: .pathGlob("**/*"),
            action: .deny, source: .user
        )
        #expect(throws: RuleValidationError.self) { try RuleValidator.validate(bad) }
    }

    @Test("Validator rejects invalid regex patterns")
    func validatorRejectsBadRegex() {
        let bad = RuleRecord(
            id: "r", name: "Bad regex",
            scope: .file, matcher: .pathRegex("[unterminated"),
            action: .deny, source: .user
        )
        #expect(throws: RuleValidationError.self) { try RuleValidator.validate(bad) }
    }

    // MARK: - Cross-content scope

    @Test("Content-scoped rule fires on both file and email requests")
    func contentScopeMatchesFileAndEmail() {
        let rule = RuleRecord(
            id: "content-1",
            name: "Redact privacy findings everywhere",
            scope: .content,
            matcher: .privacySeverityAtLeast(.medium),
            action: .redact,
            source: .user
        )

        let probe = PrivacyProbe(
            categories: [.privatePerson],
            severity: .high
        )
        let fileContext = RuleEvalContext(privacyProbe: probe)
        let emailContext = RuleEvalContext(emailProbe: EmailProbe(
            emailID: "m", senderEmail: "a@x.com", senderDomain: "x.com", subject: "x"
        ), privacyProbe: probe)

        #expect(engine.evaluate(.fileRead(path: "/tmp/x"), against: [rule], agent: .cowork, context: fileContext).action == .redact)
        #expect(engine.evaluate(.emailRead(emailID: "m"), against: [rule], agent: .cowork, context: emailContext).action == .redact)
    }

    @Test("Validator accepts content scope with privacy matchers")
    func contentScopeValidatorAcceptsPrivacy() {
        let rule = RuleRecord(
            id: "content-2",
            name: "Block secrets in any payload",
            scope: .content,
            matcher: .privacyContainsCategory(.secret),
            action: .deny,
            source: .user
        )
        try? RuleValidator.validate(rule)
        #expect((try? RuleValidator.validate(rule)) != nil)
    }

    @Test("Validator rejects content scope with agent-only matcher")
    func contentScopeValidatorRejectsAgentMatcher() {
        let rule = RuleRecord(
            id: "content-3",
            name: "Bad mix",
            scope: .content,
            matcher: .agentWrite,
            action: .deny,
            source: .user
        )
        #expect(throws: RuleValidationError.self) { try RuleValidator.validate(rule) }
    }

    @Test("File-scoped rule does not match email requests")
    func fileScopeIsolatedFromEmail() {
        let rule = RuleRecord(
            id: "file-only",
            name: "Block secrets in files",
            scope: .file,
            matcher: .privacyContainsCategory(.secret),
            action: .deny,
            source: .user
        )
        let probe = PrivacyProbe(categories: [.secret], severity: .critical)
        let context = RuleEvalContext(privacyProbe: probe)
        let emailContext = RuleEvalContext(emailProbe: EmailProbe(
            emailID: "m", senderEmail: "a@x.com", senderDomain: "x.com", subject: "x"
        ), privacyProbe: probe)

        // File scope: matcher should match.
        #expect(engine.evaluate(.fileRead(path: "/x"), against: [rule], agent: .cowork, context: context).action == .deny)
        // Email scope: file rule should NOT participate, so default allow.
        let emailDecision = engine.evaluate(.emailRead(emailID: "m"), against: [rule], agent: .cowork, context: emailContext)
        #expect(emailDecision.action == .allow)
        #expect(emailDecision.defaultPolicyApplied == true)
    }
}

@Suite("Rule store — persistence")
struct RuleStoreTests {
    func makeStore() throws -> (RuleStore, DatabaseConnection, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-rules-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: dir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        return (RuleStore(db: db), db, dir)
    }

    @Test("Upsert then fetch yields the same rule")
    func upsertFetch() async throws {
        let (store, _, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let rule = RuleRecord(
            id: "t1", name: "Test",
            scope: .file, matcher: .pathGlob("**/*.swift"),
            action: .warn, source: .user
        )
        try await store.upsert(rule)
        let fetched = try await store.rule(id: "t1")
        #expect(fetched?.name == "Test")
        #expect(fetched?.matcher == .pathGlob("**/*.swift"))
    }

    @Test("Delete seeded rule throws")
    func deleteSeededThrows() async throws {
        let (store, _, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let rule = RuleRecord(
            id: "seed1", name: "Seed",
            scope: .file, matcher: .pathGlob("**/.env"),
            action: .deny, source: .seeded
        )
        try await store.upsert(rule)
        await #expect(throws: RuleValidationError.self) {
            try await store.delete(id: "seed1")
        }
    }

    @Test("seedIfNeeded is idempotent across runs")
    func seedIdempotent() async throws {
        let (store, _, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let seeds = RuleSeedCatalog.seeds()
        try await store.seedIfNeeded(seeds)
        try await store.seedIfNeeded(seeds)
        let all = try await store.allRules()
        #expect(all.count == seeds.count)
    }

    @Test("Reorder updates order_index deterministically")
    func reorder() async throws {
        let (store, _, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = RuleRecord(id: "a", name: "A", scope: .file, matcher: .pathGlob("**/*.a"), action: .warn, source: .user, orderIndex: 0)
        let b = RuleRecord(id: "b", name: "B", scope: .file, matcher: .pathGlob("**/*.b"), action: .warn, source: .user, orderIndex: 1)
        let c = RuleRecord(id: "c", name: "C", scope: .file, matcher: .pathGlob("**/*.c"), action: .warn, source: .user, orderIndex: 2)
        try await store.upsert(a)
        try await store.upsert(b)
        try await store.upsert(c)

        try await store.reorder(scope: .file, ids: ["c", "a", "b"])
        let rules = try await store.rules(scope: .file)
        #expect(rules.map(\.id) == ["c", "a", "b"])
    }
}
