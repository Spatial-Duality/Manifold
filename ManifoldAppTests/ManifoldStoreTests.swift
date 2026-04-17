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
        XCTAssertEqual(request.target, "/Users/test/shared/worklog.md")
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

    func testMailBrowserPrefersSyncedAccountAndInbox() async throws {
        let runtime = FixtureRuntimeClient(profile: .trackedWork)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .trackedWork))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.mailReview.prepare(force: true)

        XCTAssertEqual(store.mailReview.selectedAccountID, "account-1")
        XCTAssertEqual(store.mailReview.selectedMailboxName, "INBOX")
        XCTAssertEqual(store.mailReview.threadRows.count, 2)
        XCTAssertEqual(try XCTUnwrap(store.mailReview.threadRows.first).threadKey, "thread-board@example.com")
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
            sender: "Jane Doe <jane@example.com>",
            recipients: "you@example.com",
            subject: "Project kickoff",
            receivedAt: "2026-04-15T09:00:00Z",
            messageIDHeader: "<root@example.com>"
        )
        let reply = EmailMessageRecord(
            emailID: "email-reply",
            accountID: "account-1",
            mailbox: "INBOX",
            sender: "Mark Chen <mark@example.com>",
            recipients: "you@example.com",
            subject: "Re: Project kickoff",
            receivedAt: "2026-04-15T10:00:00Z",
            inReplyTo: "<root@example.com>",
            referencesHeader: "<root@example.com> <reply@example.com>",
            messageIDHeader: "<reply@example.com>"
        )
        let unrelated = EmailMessageRecord(
            emailID: "email-unrelated",
            accountID: "account-1",
            mailbox: "INBOX",
            sender: "Ops <ops@example.com>",
            recipients: "you@example.com",
            subject: "Digest",
            receivedAt: "2026-04-15T08:00:00Z",
            messageIDHeader: "<digest@example.com>"
        )

        let grouped = MailThreadRow.group(messages: [reply, unrelated, root])

        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[0].threadKey, "root@example.com")
        XCTAssertEqual(grouped[0].messages.map(\.emailID), ["email-root", "email-reply"])
        XCTAssertEqual(grouped[1].threadKey, "digest@example.com")
    }

    func testMailBrowserShareStateRefreshesAfterPerMessageToggle() async throws {
        let runtime = FixtureRuntimeClient(profile: .trackedWork)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .trackedWork))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.mailReview.prepare(force: true)

        let boardThread = try XCTUnwrap(store.mailReview.threadRows.first(where: { $0.threadKey == "thread-board@example.com" }))
        XCTAssertEqual(store.mailReview.shareState(for: boardThread), .mixed)

        await store.mailReview.setMessageShared("email-2", isShared: true)
        let afterSecondShare = try XCTUnwrap(store.mailReview.threadRows.first(where: { $0.threadKey == "thread-board@example.com" }))
        XCTAssertEqual(store.mailReview.shareState(for: afterSecondShare), .mixed)

        await store.mailReview.setMessageShared("email-3", isShared: true)
        let fullyShared = try XCTUnwrap(store.mailReview.threadRows.first(where: { $0.threadKey == "thread-board@example.com" }))
        XCTAssertEqual(store.mailReview.shareState(for: fullyShared), .on)
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
            ["Protect Next Session…", "Open Session Recap", "Add Folder…", "Refresh Runtime", "Settings…", "Open Manifold"]
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
            ["Protect Next Session…", "Open Session Recap", "Add Folder…", "Refresh Runtime", "Settings…", "Open Manifold"]
        )
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
