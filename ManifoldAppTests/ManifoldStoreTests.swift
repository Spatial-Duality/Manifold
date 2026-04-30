// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
import ManifoldKit
@testable import Manifold

@MainActor
final class ManifoldStoreTests: XCTestCase {
    func testFixtureStoreLoadsDashboardSummaryWithoutStartingServices() async {
        let runtime = FixtureRuntimeClient(profile: .trackedWork)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .trackedWork))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.loadSummary()

        XCTAssertTrue(store.isRuntimeConnected)
        XCTAssertTrue(store.isClaudeConnected)
        XCTAssertTrue(store.isCodexConnected)
        XCTAssertEqual(store.activeSession?.agents, [.codex])
        XCTAssertFalse(store.activity.activityEntries.isEmpty)
    }

    func testRefreshAllLoadsPendingRequestsFromTrackedWorkFixture() async throws {
        let runtime = FixtureRuntimeClient(profile: .trackedWork)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .trackedWork))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.refreshAll(force: true)

        let request = try XCTUnwrap(store.pendingRequests.first)
        XCTAssertEqual(request.agent, .codex)
        XCTAssertEqual(request.operation, .write)
        XCTAssertEqual(request.kind, .standingWrite)
        XCTAssertEqual(request.target, "shared/worklog.md")
        XCTAssertEqual(request.headline, "Codex wants reversible write access.")
        XCTAssertNotNil(store.activeSession)
    }

    func testAnsweringPendingRequestRemovesItFromFixtureQueue() async throws {
        let runtime = FixtureRuntimeClient(profile: .trackedWork)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .trackedWork))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.refreshAll(force: true)
        let request = try XCTUnwrap(store.pendingRequests.first)

        await store.answer(request, with: .once)

        XCTAssertTrue(store.pendingRequests.isEmpty)
    }

    func testRefreshAllClearsStalePendingRequestsWhenApprovalLoadFails() async {
        let runtime = PendingApprovalsFailureRuntime()
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .trackedWork))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        store.governance.pendingApprovals = [
            PendingApprovalRecord(
                id: "stale-approval",
                connectionID: "conn-1",
                agent: TargetApp.codex.rawValue,
                path: "/tmp/stale.txt",
                action: "write",
                requestedAt: 1_715_000_000,
                status: "pending"
            )
        ]

        await store.refreshAll(force: true)

        XCTAssertTrue(store.pendingRequests.isEmpty)
    }

    func testRefreshAllFiltersRemovedSourcesFromDashboard() async {
        let runtime = RemovedSourceDashboardRuntime()
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .dashboard))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.refreshAll(force: true)

        XCTAssertEqual(store.sources.map(\.sourceID), ["src-live"])
        XCTAssertFalse(store.sources.contains(where: \.isRemoved))
    }

    func testAggregateFolderCheckboxClearsPartiallySharedSource() {
        let agents: [TargetApp] = [.cowork, .codex]

        XCTAssertTrue(FoldersMatrixView.aggregateScopeTarget(connectedAgents: agents, scopedAgents: []))
        XCTAssertFalse(FoldersMatrixView.aggregateScopeTarget(connectedAgents: agents, scopedAgents: [.cowork]))
        XCTAssertFalse(FoldersMatrixView.aggregateScopeTarget(connectedAgents: agents, scopedAgents: [.cowork, .codex]))
    }

    // MARK: - Redesign IA

    func testLedgerDestinationHasOnlyFourCases() {
        let cases = LedgerDestination.allCases.map(\.rawValue)
        XCTAssertEqual(Set(cases), ["work", "access", "mail", "rules"])
    }

    func testLedgerDestinationLegacyRawValuesRouteToWork() {
        XCTAssertEqual(LedgerDestination(rawValue: "activity"), .work)
        XCTAssertEqual(LedgerDestination(rawValue: "sessions"), .work)
        XCTAssertEqual(LedgerDestination(rawValue: "requests"), .work)
        XCTAssertEqual(LedgerDestination(rawValue: "provenance"), .work)
        XCTAssertEqual(LedgerDestination(rawValue: "agentOS"), .work)
        XCTAssertNil(LedgerDestination(rawValue: "settings"))
    }

    func testWorkTimelineFilterApprovalsIncludesDeniedActions() {
        let denied = AuditEntry(id: 1, timestamp: "2026-04-30T00:00:00Z", action: "deny_write")
        let warning = AuditEntry(id: 2, timestamp: "2026-04-30T00:00:00Z", action: AuditAction.sensitivityWarning.rawValue)
        let read = AuditEntry(id: 3, timestamp: "2026-04-30T00:00:00Z", action: AuditAction.fileRead.rawValue)

        XCTAssertTrue(WorkTimelineFilter.approvals.includes(denied))
        XCTAssertTrue(WorkTimelineFilter.approvals.includes(warning))
        XCTAssertFalse(WorkTimelineFilter.approvals.includes(read))
        XCTAssertTrue(WorkTimelineFilter.reads.includes(read))
        XCTAssertTrue(WorkTimelineFilter.all.includes(read))
    }

    func testSessionRequestDetailMapsToBackingLevel() {
        XCTAssertEqual(SessionRequestDetail.off.backingLevel, .lightweight)
        XCTAssertEqual(SessionRequestDetail.brief.backingLevel, .summary)
        XCTAssertEqual(SessionRequestDetail.detailed.backingLevel, .detailed)
        XCTAssertEqual(SessionRequestDetail(level: .lightweight), .off)
        XCTAssertEqual(SessionRequestDetail(level: .summary), .brief)
        XCTAssertEqual(SessionRequestDetail(level: .detailed), .detailed)
    }

    func testMailBrowserPrefersSyncedAccountAndInbox() async throws {
        let runtime = FixtureRuntimeClient(profile: .trackedWork)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .trackedWork))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.mailReview.prepare(force: true)

        XCTAssertEqual(store.mailReview.selectedAccountID, "account-1")
        XCTAssertEqual(store.mailReview.selectedMailboxName, "INBOX")
        XCTAssertEqual(store.mailReview.threadRows.count, 2)
        XCTAssertEqual(try XCTUnwrap(store.mailReview.threadRows.first).threadKey, "thread-frontier-sync@anthropic.test")
    }

    func testMailAccountsModelLoadsMailboxMessagesThroughProtocolExistential() async {
        let runtime: any RuntimeClientProtocol = FixtureRuntimeClient(profile: .trackedWork)
        let model = MailAccountsModel()
        model.configure(client: runtime)

        await model.loadAccounts()
        let inboxMessages = await model.messagesInMailbox(accountID: "account-1", mailbox: "INBOX", limit: 20)
        let accountMessages = await model.messages(accountID: "account-1", limit: 20)

        XCTAssertEqual(inboxMessages.count, 4)
        XCTAssertEqual(accountMessages.count, 5)
        XCTAssertEqual(inboxMessages.first?.emailID, "email-3")
    }

    func testMailThreadGroupingUsesReferencesThenReplyHeaders() {
        let root = EmailMessageRecord(
            emailID: "email-root",
            accountID: "account-1",
            mailbox: "INBOX",
            sender: "Dario Amodei <dario@anthropic.test>",
            recipients: "policy@manifold.test",
            subject: "Constitution sync",
            receivedAt: "2026-04-15T09:00:00Z",
            messageIDHeader: "<constitution-sync@anthropic.test>"
        )
        let reply = EmailMessageRecord(
            emailID: "email-reply",
            accountID: "account-1",
            mailbox: "INBOX",
            sender: "Sam Altman <sam@openai.test>",
            recipients: "policy@manifold.test",
            subject: "Re: Constitution sync",
            receivedAt: "2026-04-15T10:00:00Z",
            inReplyTo: "<constitution-sync@anthropic.test>",
            referencesHeader: "<constitution-sync@anthropic.test> <constitution-sync-reply@openai.test>",
            messageIDHeader: "<constitution-sync-reply@openai.test>"
        )
        let unrelated = EmailMessageRecord(
            emailID: "email-unrelated",
            accountID: "account-1",
            mailbox: "INBOX",
            sender: "Greg Brockman <greg@openai.test>",
            recipients: "policy@manifold.test",
            subject: "Operator checklist",
            receivedAt: "2026-04-15T08:00:00Z",
            messageIDHeader: "<operator-checklist@openai.test>"
        )

        let grouped = MailThreadRow.group(messages: [reply, unrelated, root])

        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[0].threadKey, "constitution-sync@anthropic.test")
        XCTAssertEqual(grouped[0].messages.map(\.emailID), ["email-root", "email-reply"])
        XCTAssertEqual(grouped[1].threadKey, "operator-checklist@openai.test")
    }

    func testMailBrowserShareStateRefreshesAfterPerMessageToggle() async throws {
        let runtime = FixtureRuntimeClient(profile: .trackedWork)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .trackedWork))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.mailReview.prepare(force: true)
        // The redesigned mail surface tracks per-agent share state.
        // Push the AI we're asserting on (cowork) into the model so its
        // shared set populates, then drive every assertion through the
        // agent-aware API.
        await store.mailReview.setConnectedAgents([.cowork])

        let boardThread = try XCTUnwrap(store.mailReview.threadRows.first(where: { $0.threadKey == "thread-frontier-sync@anthropic.test" }))
        XCTAssertEqual(store.mailReview.shareState(for: boardThread, agent: .cowork), .mixed)

        await store.mailReview.setMessageShared("email-2", agent: .cowork, isShared: true)
        let afterSecondShare = try XCTUnwrap(store.mailReview.threadRows.first(where: { $0.threadKey == "thread-frontier-sync@anthropic.test" }))
        XCTAssertEqual(store.mailReview.shareState(for: afterSecondShare, agent: .cowork), .mixed)

        await store.mailReview.setMessageShared("email-3", agent: .cowork, isShared: true)
        let fullyShared = try XCTUnwrap(store.mailReview.threadRows.first(where: { $0.threadKey == "thread-frontier-sync@anthropic.test" }))
        XCTAssertEqual(store.mailReview.shareState(for: fullyShared, agent: .cowork), .on)
    }

    func testPrivacyFixtureLoadsDiscoveryStateAndPrivacyApproval() async throws {
        let runtime = FixtureRuntimeClient(profile: .privacy)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .privacy))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.refreshAll(force: true)

        XCTAssertEqual(store.governance.privacyIdentitySuggestions.count, 1)
        XCTAssertEqual(store.governance.privacyRecentIndex.count, 3)
        XCTAssertEqual(store.governance.privacyIndexStatus?.failedJobs, 1)

        let privacyRequest = try XCTUnwrap(store.pendingRequests.first(where: { $0.kind == .privacyExposure }))
        XCTAssertEqual(privacyRequest.operation, .mailboxRead)
        XCTAssertEqual(privacyRequest.matchedCategories, [.email, .secret])
        XCTAssertEqual(privacyRequest.severity, .critical)
        XCTAssertNotNil(privacyRequest.redactedPreview)
    }

    func testPrivacyPresetStrictRoundTripsThroughFixtureRuntime() async throws {
        let runtime = FixtureRuntimeClient(profile: .privacy)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .privacy))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.governance.loadPolicies()

        var settings = try XCTUnwrap(store.governance.privacySettings)
        let claude = try XCTUnwrap(store.governance.claudePrivacyPolicy)
        let codex = try XCTUnwrap(store.governance.codexPrivacyPolicy)
        let (strictSettings, strictClaude, strictCodex) = PrivacyPreset.strict.apply(
            to: &settings,
            claude: claude,
            codex: codex
        )

        await store.governance.updatePrivacySettings(strictSettings)
        await store.governance.updatePrivacyPolicy(strictClaude)
        await store.governance.updatePrivacyPolicy(strictCodex)

        XCTAssertEqual(
            PrivacyPreset.detect(
                settings: store.governance.privacySettings,
                claudePolicy: store.governance.claudePrivacyPolicy,
                codexPolicy: store.governance.codexPrivacyPolicy
            ),
            .strict
        )
    }

    func testFileVisibilityOverridesRoundTripThroughRuntime() async throws {
        let runtime = FixtureRuntimeClient(profile: .dashboard)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .dashboard))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.setFileVisibilityOverride(
            agent: .cowork,
            sourceID: "src-shared",
            relativePath: "Docs/Plan.md",
            decision: .deny
        )

        let overrides = await store.fileVisibilityOverrides(agent: .cowork)
        XCTAssertEqual(overrides.count, 1)
        XCTAssertEqual(overrides.first?.decision, .deny)

        await store.clearFileVisibilityOverride(
            agent: .cowork,
            sourceID: "src-shared",
            relativePath: "Docs/Plan.md"
        )

        let cleared = await store.fileVisibilityOverrides(agent: .cowork)
        XCTAssertTrue(cleared.isEmpty)
    }
}

@MainActor
final class CommandPaletteModelTests: XCTestCase {
    func testBindingBuildsPrimaryCommands() {
        let store = ManifoldStore(
            runtime: FixtureRuntimeClient(profile: .dashboard),
            integrationHealth: IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .dashboard)),
            startServices: false
        )
        let commandCenter = CommandPaletteModel()

        commandCenter.bind(to: store)

        XCTAssertEqual(
            commandCenter.filteredCommands().map(\.title),
            [
                "Open Work",
                "Open Access",
                "Open Mail",
                "Open Rules",
                "New Session",
                "Open Session Recap",
                "Add Folder…",
                "Restart Runtime Helper",
                "Settings…",
                "Open Manifold",
            ]
        )
    }

    func testFilteringCommandsUsesSearchText() {
        let store = ManifoldStore(
            runtime: FixtureRuntimeClient(profile: .dashboard),
            integrationHealth: IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .dashboard)),
            startServices: false
        )
        let commandCenter = CommandPaletteModel()
        commandCenter.bind(to: store)

        commandCenter.searchText = "settings"

        XCTAssertEqual(commandCenter.filteredCommands().map(\.title), ["Settings…"])
    }

    func testBindingSameStoreTwiceDoesNotDuplicateCommands() {
        let store = ManifoldStore(
            runtime: FixtureRuntimeClient(profile: .dashboard),
            integrationHealth: IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .dashboard)),
            startServices: false
        )
        let commandCenter = CommandPaletteModel()

        commandCenter.bind(to: store)
        commandCenter.bind(to: store)

        XCTAssertEqual(
            commandCenter.filteredCommands().map(\.title),
            [
                "Open Work",
                "Open Access",
                "Open Mail",
                "Open Rules",
                "New Session",
                "Open Session Recap",
                "Add Folder…",
                "Restart Runtime Helper",
                "Settings…",
                "Open Manifold",
            ]
        )
    }

    func testTrackedSessionAddsFinishTrackedEditCommand() async {
        let store = ManifoldStore(
            runtime: FixtureRuntimeClient(profile: .trackedWork),
            integrationHealth: IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .trackedWork)),
            startServices: false
        )
        let commandCenter = CommandPaletteModel()

        await store.refreshAll(force: true)
        commandCenter.bind(to: store)

        XCTAssertTrue(commandCenter.filteredCommands().contains(where: { $0.id == .finishTrackedEdit }))
    }
}

private enum PendingApprovalsFailure: Error {
    case unavailable
}

private actor PendingApprovalsFailureRuntime: RuntimeClientProtocol {
    private let fixture = FixtureRuntimeClient(profile: .trackedWork)

    func ping() async -> RuntimePingResult {
        RuntimePingResult(ok: true, agentVersion: nil)
    }

    func dashboardState() async throws -> DashboardState {
        try await fixture.dashboardState()
    }

    func activeGrantState(targetApp: TargetApp) async throws -> ActiveGrantState {
        ActiveGrantState(activeGrant: nil, activeGrantSources: [], targetApp: targetApp.rawValue)
    }

    func listPendingApprovals() async throws -> [PendingApprovalRecord] {
        throw PendingApprovalsFailure.unavailable
    }
}

private actor RemovedSourceDashboardRuntime: RuntimeClientProtocol {
    func ping() async -> RuntimePingResult {
        RuntimePingResult(ok: true, agentVersion: nil)
    }

    func dashboardState() async throws -> DashboardState {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        let live = SourceRecord(
            sourceID: "src-live",
            displayName: "Live",
            originalRootPath: "/tmp/live",
            status: "idle",
            createdAt: now,
            updatedAt: now
        )
        let removed = SourceRecord(
            sourceID: "src-removed",
            displayName: "Removed",
            originalRootPath: "/tmp/removed",
            status: "removed",
            createdAt: now,
            updatedAt: now
        )

        return DashboardState(
            runtimeConnected: true,
            activeBridgeCount: 0,
            connectedAgents: [],
            sources: [live, removed],
            claudePolicy: AgentAccessPolicy(agent: .cowork),
            codexPolicy: AgentAccessPolicy(agent: .codex),
            claudeEmailGovernance: Self.emailGovernance(for: .cowork),
            codexEmailGovernance: Self.emailGovernance(for: .codex),
            activeSession: nil,
            pendingApprovalCount: 0,
            agentCoverages: [],
            coverageEvents: []
        )
    }

    private static func emailGovernance(for agent: TargetApp) -> AgentEmailGovernanceSummary {
        AgentEmailGovernanceSummary(
            agent: agent,
            enabledShieldCount: 0,
            domainRuleCount: 0,
            contactRuleCount: 0,
            keywordRuleCount: 0,
            defaultPolicy: .defaultValue(for: agent),
            emailSensitivity: .moderate
        )
    }
}
