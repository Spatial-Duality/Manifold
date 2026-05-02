// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
import ManifoldKit
@testable import Manifold

@MainActor
final class RulesModelTests: XCTestCase {
    func testSourceFilterTitlesUsePresentationVocabulary() {
        XCTAssertEqual(RulesModel.Filter.seeded.title, "Suggested")
        XCTAssertEqual(RulesModel.Filter.userAuthored.title, "Mine")
        XCTAssertEqual(RulesModel.Filter.suggested.title, "Recommended")
    }

    func testRuleSourcePresentationLabels() {
        XCTAssertEqual(RuleSource.seeded.presentationLabel, "Suggested")
        XCTAssertEqual(RuleSource.user.presentationLabel, "Mine")
        XCTAssertEqual(RuleSource.userOverride.presentationLabel, "Mine")
        XCTAssertEqual(RuleSource.imported.presentationLabel, "Mine")
        XCTAssertEqual(RuleSource.suggested.presentationLabel, "Recommended")
    }

    func testFixtureRuntimeStatusUsesOpenAIPrivacyFilterName() async throws {
        let client = FixtureRuntimeClient(profile: .privacy)

        let status = try await client.privacyRuntimeStatus()
        let runtimes = try await client.listPrivacyRuntimes()
        let runtime = try XCTUnwrap(runtimes.first)

        XCTAssertEqual(status.runtimeDisplayName, PrivacyRuntimeDefaults.displayName)
        XCTAssertEqual(runtime.displayName, PrivacyRuntimeDefaults.displayName)
        XCTAssertEqual(runtime.publisher, PrivacyRuntimeDefaults.publisherName)
        XCTAssertEqual(runtime.sourceRepository, PrivacyRuntimeDefaults.installedModelRepositoryURL)
    }

    func testPrivacyRuntimePresentationNormalizesStaleOpenAIPrivacyFilterMetadata() {
        let staleName = ["Fast", "Local", "Scanner"].joined(separator: " ")
        let stalePublisher = ["MLX Community", "OpenAI"].joined(separator: " / ")
        let staleRuntime = PrivacyRuntimeDescriptor(
            id: PrivacyRuntimeDefaults.mlxRuntimeID,
            displayName: staleName,
            publisher: stalePublisher,
            installedVersion: "2026-04-23-73372cab9eaf",
            availableVersion: "2026-04-23-73372cab9eaf",
            installState: .installed,
            verificationState: .checksumVerified,
            sourceRepository: PrivacyRuntimeDefaults.installedModelRepositoryURL,
            note: "Verified MLX MXFP8 model pack installed."
        )
        let staleStatus = PrivacyRuntimeStatus(
            featureEnabled: true,
            selectedBackend: .mlx,
            effectiveBackend: .mlx,
            installState: .installed,
            modelLoaded: true,
            cacheEntryCount: 4,
            lastError: nil,
            storagePath: nil,
            backends: [],
            runtimeID: PrivacyRuntimeDefaults.mlxRuntimeID,
            runtimeDisplayName: staleName,
            installedVersion: "2026-04-23-73372cab9eaf",
            availableVersion: "2026-04-23-73372cab9eaf",
            verificationState: .checksumVerified
        )

        XCTAssertEqual(
            PrivacyRuntimePresentation.displayName(status: staleStatus, runtime: staleRuntime),
            PrivacyRuntimeDefaults.displayName
        )
        XCTAssertEqual(PrivacyRuntimePresentation.publisher(runtime: staleRuntime), PrivacyRuntimeDefaults.publisherName)
        XCTAssertEqual(
            PrivacyRuntimePresentation.installedPackURL(runtime: staleRuntime),
            PrivacyRuntimeDefaults.installedModelRepositoryURL
        )
    }

    func testFilteredRulesPrioritizeSeededRulesWithinScope() async {
        let seededRule = makeRule(
            id: "rule-seeded-file",
            name: "Protect Frontier Secrets",
            scope: .file,
            matcher: .pathGlob("**/.env"),
            action: .deny,
            source: .seeded,
            orderIndex: 0
        )
        let userRule = makeRule(
            id: "rule-user-file",
            name: "Share Launch Notes",
            scope: .file,
            matcher: .pathGlob("**/ReleaseNotes.md"),
            action: .allow,
            source: .user,
            orderIndex: 20
        )
        let model = RulesModel()
        model.configure(client: RulesRuntimeDouble(initialRules: [userRule, seededRule]))

        await model.load()
        model.filter = .scope(.file)

        XCTAssertEqual(model.filteredRules.map(\.name), ["Protect Frontier Secrets", "Share Launch Notes"])
    }

    func testSearchFiltersRulesWithinSelectedScope() async {
        let emailRule = makeRule(
            id: "rule-email-board",
            name: "Hide Sam + Dario Threads",
            explanation: "Mask cross-lab planning threads during sharing.",
            scope: .email,
            matcher: .emailDomain("openai.test"),
            action: .redact,
            source: .user
        )
        let otherEmailRule = makeRule(
            id: "rule-email-vendors",
            name: "Allow Anthropic Digest",
            explanation: "Keep routine Anthropic digests visible.",
            scope: .email,
            matcher: .emailDomain("anthropic.test"),
            action: .allow,
            source: .imported
        )
        let model = RulesModel()
        model.configure(client: RulesRuntimeDouble(initialRules: [emailRule, otherEmailRule]))

        await model.load()
        model.filter = .scope(.email)
        model.searchText = "sam"

        XCTAssertEqual(model.filteredRules.map(\.id), ["rule-email-board"])
    }

    func testSearchIncludesMatcherSummaryAndPrivacyKeywords() async {
        let privacyRule = makeRule(
            id: "rule-privacy-secret",
            name: "Deny sensitive payloads",
            scope: .agent,
            matcher: .privacyContainsCategory(.secret),
            action: .deny,
            source: .user
        )
        let model = RulesModel()
        model.configure(client: RulesRuntimeDouble(initialRules: [privacyRule]))

        await model.load()
        model.searchText = "openai secret"

        XCTAssertEqual(model.filteredRules.map(\.id), ["rule-privacy-secret"])
    }

    func testPrivacyFilterFilterOnlyShowsPrivacyBackedRules() async {
        let privacyRule = makeRule(
            id: "rule-privacy-email",
            name: "Redact identity",
            scope: .email,
            matcher: .privacyMatchesMyIdentity,
            action: .redact,
            source: .user
        )
        let structuralRule = makeRule(
            id: "rule-agent-write",
            name: "Warn on writes",
            scope: .agent,
            matcher: .agentWrite,
            action: .warn,
            source: .user
        )
        let model = RulesModel()
        model.configure(client: RulesRuntimeDouble(initialRules: [structuralRule, privacyRule]))

        await model.load()
        model.filter = .privacy

        XCTAssertEqual(model.filteredRules.map(\.id), ["rule-privacy-email"])
        XCTAssertTrue(privacyRule.isPrivacyFilterBacked)
        XCTAssertFalse(structuralRule.isPrivacyFilterBacked)
    }

    func testSelectingSidebarFilterUpdatesVisibleRulesAndSelection() async throws {
        let fileRule = makeRule(
            id: "rule-file-scope",
            name: "Deny workspace secrets",
            scope: .file,
            matcher: .pathGlob("**/.env"),
            action: .deny,
            source: .user
        )
        let emailRule = makeRule(
            id: "rule-email-scope",
            name: "Redact invoices",
            scope: .email,
            matcher: .emailDomain("billing.example.com"),
            action: .redact,
            source: .user
        )
        let model = RulesModel()
        model.configure(client: RulesRuntimeDouble(initialRules: [fileRule, emailRule]))

        await model.load()
        model.selectedRuleID = fileRule.id
        model.selectFilter(.scope(.email))

        XCTAssertEqual(model.filter, .scope(.email))
        XCTAssertEqual(model.filteredRules.map(\.id), [emailRule.id])
        XCTAssertEqual(model.selectedRuleID, emailRule.id)
    }

    func testPrivacyFilterFactoryCreatesPreflightRule() {
        let rule = RuleRecord.newPrivacyFilterRule(category: .accountNumber)

        // Privacy-filter rules use the cross-content scope so the engine
        // evaluates them on both file and email requests.
        XCTAssertEqual(rule.scope, .content)
        XCTAssertEqual(rule.action, .deny)
        XCTAssertEqual(rule.matcher, .privacyContainsCategory(.accountNumber))
        XCTAssertTrue(rule.isPrivacyFilterBacked)
        XCTAssertFalse(rule.isPreviewOnlyStructuralRule)
    }

    func testAddRulePersistsAndSelectsInsertedRule() async throws {
        let model = RulesModel()
        model.configure(client: RulesRuntimeDouble(initialRules: []))
        let newRule = RuleRecord.newUserFileRule(name: "Claude + Codex Workspace Rule")

        await model.addRule(newRule)

        XCTAssertEqual(model.selectedRuleID, newRule.id)
        XCTAssertEqual(try XCTUnwrap(model.rules.first).name, "Claude + Codex Workspace Rule")
    }

    func testToggleEnabledRefreshesRuleState() async throws {
        let rule = makeRule(
            id: "rule-toggle",
            name: "Review Operator Scripts",
            scope: .file,
            matcher: .pathGlob("**/*.sh"),
            action: .warn,
            source: .user
        )
        let model = RulesModel()
        model.configure(client: RulesRuntimeDouble(initialRules: [rule]))

        await model.load()
        await model.toggleEnabled(id: rule.id)

        XCTAssertFalse(try XCTUnwrap(model.rules.first).enabled)
    }

    func testSetEnabledCanReenableDisabledSeededRule() async throws {
        let rule = makeRule(
            id: "rule-seeded-toggle",
            name: "Suggested Secrets Guard",
            scope: .file,
            matcher: .pathGlob("**/.env"),
            action: .deny,
            source: .seeded,
            enabled: false
        )
        let model = RulesModel()
        model.configure(client: RulesRuntimeDouble(initialRules: [rule]))

        await model.load()
        await model.setEnabled(id: rule.id, enabled: true)

        XCTAssertTrue(try XCTUnwrap(model.rules.first).enabled)
    }

    func testDeleteSelectedRejectsSeededRules() async {
        let seededRule = makeRule(
            id: "rule-seeded-delete",
            name: "Suggested Constitution Guard",
            scope: .file,
            matcher: .pathGlob("**/.env"),
            action: .deny,
            source: .seeded
        )
        let model = RulesModel()
        model.configure(client: RulesRuntimeDouble(initialRules: [seededRule]))

        await model.load()
        model.selectedRuleID = seededRule.id
        await model.deleteSelected()

        XCTAssertEqual(model.errorMessage, "Suggested rules are managed by Manifold. You can disable them, but not delete them.")
        XCTAssertEqual(model.rules.map(\.id), [seededRule.id])
    }

    func testResetSeededRulesRestoresSeededCatalogState() async throws {
        let enabledSeededRule = makeRule(
            id: "rule-seeded-reset",
            name: "Protect API Tokens",
            scope: .file,
            matcher: .pathGlob("**/.env"),
            action: .deny,
            source: .seeded,
            enabled: true
        )
        let disabledSeededRule = makeRule(
            id: "rule-seeded-reset",
            name: "Protect API Tokens",
            scope: .file,
            matcher: .pathGlob("**/.env"),
            action: .deny,
            source: .seeded,
            enabled: false
        )
        let model = RulesModel()
        model.configure(
            client: RulesRuntimeDouble(
                initialRules: [disabledSeededRule],
                seededCatalog: [enabledSeededRule]
            )
        )

        await model.load()
        await model.resetSeededRules()

        XCTAssertTrue(try XCTUnwrap(model.rules.first).enabled)
    }

    func testRefreshPreviewPublishesRuntimePreview() async {
        let rule = makeRule(
            id: "rule-preview",
            name: "Preview Shared Lab Notes",
            scope: .file,
            matcher: .pathGlob("shared/**"),
            action: .warn,
            source: .user
        )
        let preview = RuleMatchPreview(
            ruleID: rule.id,
            fileMatches: 2,
            emailMatches: 0,
            agentMatches: 1,
            sample: [
                .init(identifier: "shared/worklog.md", label: "shared/worklog.md")
            ]
        )
        let model = RulesModel()
        model.configure(client: RulesRuntimeDouble(initialRules: [rule], previews: [rule.id: preview]))

        await model.load()
        model.selectedRuleID = rule.id
        model.refreshPreview(for: rule, agent: .codex)
        try? await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertEqual(model.preview?.totalMatches, 3)
        XCTAssertEqual(model.preview?.sample.first?.label, "shared/worklog.md")
    }

    private func makeRule(
        id: String,
        name: String,
        explanation: String = "",
        scope: ManifoldKit.RuleScope,
        matcher: ManifoldKit.RuleMatcher,
        action: ManifoldKit.RuleAction,
        source: ManifoldKit.RuleSource,
        enabled: Bool = true,
        orderIndex: Int = 0
    ) -> RuleRecord {
        let timestamp = "2026-04-17T12:00:00Z"
        return RuleRecord(
            id: id,
            name: name,
            explanation: explanation,
            scope: scope,
            matcher: matcher,
            action: action,
            agents: [],
            window: .always,
            source: source,
            enabled: enabled,
            orderIndex: orderIndex,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }
}

private actor RulesRuntimeDouble: RuntimeClientProtocol {
    private var rules: [RuleRecord]
    private let seededCatalog: [RuleRecord]
    private let previews: [String: RuleMatchPreview]

    init(
        initialRules: [RuleRecord],
        seededCatalog: [RuleRecord]? = nil,
        previews: [String: RuleMatchPreview] = [:]
    ) {
        self.rules = initialRules
        self.seededCatalog = seededCatalog ?? initialRules.filter { $0.source == .seeded }
        self.previews = previews
    }

    func listRules(scope: RuleScope?) async throws -> [RuleRecord] {
        if let scope {
            return rules.filter { $0.scope == scope }
        }
        return rules
    }

    func upsertRule(_ rule: RuleRecord) async throws {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
    }

    func deleteRule(id: String) async throws {
        rules.removeAll { $0.id == id }
    }

    func setRuleEnabled(id: String, enabled: Bool) async throws {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].enabled = enabled
    }

    func reorderRules(scope: RuleScope, ids: [String]) async throws {
        var scoped = rules.filter { $0.scope == scope }
        var unscoped = rules.filter { $0.scope != scope }
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        scoped.sort { lhs, rhs in
            let lhsRank = order[lhs.id] ?? Int.max
            let rhsRank = order[rhs.id] ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.orderIndex < rhs.orderIndex
        }
        for (index, ruleIndex) in scoped.indices.enumerated() {
            scoped[ruleIndex].orderIndex = index
        }
        unscoped.append(contentsOf: scoped)
        rules = unscoped
    }

    func resetSeededRules() async throws {
        rules.removeAll { $0.source == .seeded }
        rules.append(contentsOf: seededCatalog)
    }

    func previewRuleMatches(rule: RuleRecord, agent: TargetApp) async throws -> RuleMatchPreview {
        previews[rule.id] ?? RuleMatchPreview(ruleID: rule.id, fileMatches: 0, emailMatches: 0, agentMatches: 0, sample: [])
    }
}
