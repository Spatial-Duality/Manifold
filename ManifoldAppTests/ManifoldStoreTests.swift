// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
import AppKit
import ManifoldKit
@testable import Manifold

@MainActor
final class ManifoldStoreTests: XCTestCase {
    func testFixtureStoreLoadsRuntimeSummaryWithoutStartingServices() async {
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

    func testDemoFixtureContainsCanonicalAnthropologieSurface() async throws {
        let runtime = DemoRuntimeClient.anthropologie()

        let activity = try await runtime.recentActivity(limit: 50)
        let rules = try await runtime.listRules(scope: nil)
        let accounts = try await runtime.listEmailAccounts()
        let sources = try await runtime.listSources()
        let emails = try await runtime.emailMessages(accountID: nil, mailbox: nil, ids: nil, limit: 100)
        let claudeShared = try await runtime.sharedEmailIDs(agent: .cowork)
        let codexShared = try await runtime.sharedEmailIDs(agent: .codex)

        XCTAssertEqual(activity.count, 13)
        XCTAssertTrue(rules.contains { $0.name == "racing/* never shared" })
        XCTAssertEqual(Set(accounts.map(\.displayName)), ["iCloud", "Gmail", "Microsoft 365"])
        XCTAssertEqual(sources.count, 18)
        XCTAssertGreaterThanOrEqual(emails.count, 25)
        XCTAssertGreaterThanOrEqual(DemoFileCatalog.entries.count, 70)
        XCTAssertGreaterThanOrEqual(claudeShared.count, 8)
        XCTAssertGreaterThanOrEqual(codexShared.count, 6)
        XCTAssertTrue(DemoFileCatalog.entries.contains { $0.relativePath.hasSuffix(".pdf") })
        XCTAssertTrue(DemoFileCatalog.entries.contains { $0.relativePath.hasSuffix(".csv") })
        XCTAssertTrue(DemoFileCatalog.entries.contains { $0.relativePath.hasSuffix(".docx") })
        XCTAssertTrue(DemoFileCatalog.entries.contains { $0.relativePath.hasSuffix(".txt") })

        let demoRootChildren = FileNode.loadChildren(at: DemoFileCatalog.rootPath)
        XCTAssertEqual(demoRootChildren.count, sources.count)
        XCTAssertTrue(demoRootChildren.allSatisfy(\.isDirectory))

        for source in sources {
            let files = DemoFileCatalog.files(for: source)
            XCTAssertFalse(files.isEmpty, "Demo source \(source.sourceID) has no catalog files")
            XCTAssertTrue(files.allSatisfy { $0.sourceID == source.sourceID })
            XCTAssertTrue(files.allSatisfy { $0.path.hasPrefix(source.originalRootPath + "/") })
            XCTAssertTrue(files.allSatisfy { $0.canonicalPath.hasPrefix(source.canonicalMountName + "/") })

            let rootChildren = FileNode.loadChildren(at: source.originalRootPath)
            let actualNames = Set(rootChildren.map(\.name))
            let expectedNames = Set(DemoFileCatalog.entries
                .filter { $0.sourceID == source.sourceID }
                .compactMap { $0.relativePath.split(separator: "/").first.map(String.init) })
            XCTAssertEqual(actualNames, expectedNames, "Demo tree root mismatch for \(source.sourceID)")
        }

        let haystack = [
            activity.map { [$0.filePath, $0.metadata].compactMap { $0 }.joined(separator: " ") }.joined(separator: "\n"),
            rules.map(\.name).joined(separator: "\n"),
            accounts.map { "\($0.displayName) \($0.username ?? "")" }.joined(separator: "\n"),
            sources.map { "\($0.displayName) \($0.originalRootPath)" }.joined(separator: "\n"),
            emails.map { "\($0.sender) \($0.subject)" }.joined(separator: "\n"),
            DemoFileCatalog.entries.map(\.relativePath).joined(separator: "\n"),
        ].joined(separator: "\n")
        for forbidden in ["Dario Amodei", "Daniela Amodei", "Boris Cherny", "Mark Chen", "Tim Cook", "Sam Altman"] {
            XCTAssertFalse(haystack.contains(forbidden), "Demo data leaked forbidden real-name string: \(forbidden)")
        }
    }

    func testDemoWarningDefaultsOnWhenDemoModeIsEnabled() {
        let suiteName = "com.spatialduality.manifold.demo-mode-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ManifoldStore(startServices: false, defaults: defaults)

        store.setDemoModeEnabled(true)

        XCTAssertTrue(store.isDemoModeEnabled)
        XCTAssertTrue(store.showDemoWarning)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRefreshAllLoadsPendingApprovalsFromTrackedWorkFixture() async throws {
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

    func testAnsweringPendingApprovalRemovesItFromFixtureQueue() async throws {
        let runtime = FixtureRuntimeClient(profile: .trackedWork)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .trackedWork))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.refreshAll(force: true)
        let request = try XCTUnwrap(store.pendingRequests.first)

        await store.answer(request, with: .once)

        XCTAssertTrue(store.pendingRequests.isEmpty)
    }

    func testRefreshAllClearsStalePendingApprovalsWhenApprovalLoadFails() async {
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

    func testRefreshAllFiltersRemovedSourcesFromRuntimeStatus() async {
        let runtime = RemovedSourceRuntimeStatusRuntime()
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .baseline))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.refreshAll(force: true)

        XCTAssertEqual(store.sources.map(\.sourceID), ["src-live"])
        XCTAssertFalse(store.sources.contains(where: \.isRemoved))
    }

    func testAggregateFolderCheckboxSharesPartiallySharedSource() {
        let agents: [TargetApp] = [.cowork, .codex]

        XCTAssertTrue(FoldersMatrixView.aggregateScopeTarget(connectedAgents: agents, scopedAgents: []))
        XCTAssertTrue(FoldersMatrixView.aggregateScopeTarget(connectedAgents: agents, scopedAgents: [.cowork]))
        XCTAssertFalse(FoldersMatrixView.aggregateScopeTarget(connectedAgents: agents, scopedAgents: [.cowork, .codex]))
    }

    // MARK: - Redesign IA

    func testLedgerDestinationHasOnlyFourCases() {
        let cases = LedgerDestination.allCases.map(\.rawValue)
        XCTAssertEqual(Set(cases), ["work", "access", "mail", "rules"])
    }

    func testLedgerDestinationRejectsLegacyRawValues() {
        XCTAssertNil(LedgerDestination(rawValue: "activity"))
        XCTAssertNil(LedgerDestination(rawValue: "sessions"))
        XCTAssertNil(LedgerDestination(rawValue: "requests"))
        XCTAssertNil(LedgerDestination(rawValue: "provenance"))
        XCTAssertNil(LedgerDestination(rawValue: "agentOS"))
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

    func testMailSidebarCollapsesGmailSpecialUseAliases() throws {
        let account = EmailAccountRecord(
            accountID: "gmail-account",
            displayName: "Gmail",
            providerType: EmailProvider.gmail.rawValue
        )
        let mailReview = MailReviewModel()
        mailReview.mailboxesByAccountID[account.accountID] = [
            try mailboxRecord(accountID: account.accountID, name: "INBOX", sortOrder: 0),
            try mailboxRecord(accountID: account.accountID, name: "[Google Mail]/Sent Mail", flags: ["\\Sent"], sortOrder: 1),
            try mailboxRecord(accountID: account.accountID, name: "Sent", sortOrder: 2),
            try mailboxRecord(accountID: account.accountID, name: "Sent Messages", sortOrder: 3),
            try mailboxRecord(accountID: account.accountID, name: "[Google Mail]/Drafts", flags: ["\\Drafts"], sortOrder: 4),
            try mailboxRecord(accountID: account.accountID, name: "Drafts", sortOrder: 5),
            try mailboxRecord(accountID: account.accountID, name: "[Google Mail]/Starred", flags: ["\\Flagged"], sortOrder: 6),
            try mailboxRecord(accountID: account.accountID, name: "[Google Mail]/All Mail", flags: ["\\All"], sortOrder: 7),
            try mailboxRecord(accountID: account.accountID, name: "[Google Mail]/Spam", flags: ["\\Junk"], sortOrder: 8),
            try mailboxRecord(accountID: account.accountID, name: "[Google Mail]/Trash", flags: ["\\Trash"], sortOrder: 9),
            try mailboxRecord(accountID: account.accountID, name: "Deleted Messages", sortOrder: 10),
            try mailboxRecord(accountID: account.accountID, name: "Trash", sortOrder: 11),
            try mailboxRecord(accountID: account.accountID, name: "[Google Mail]/Important", flags: ["\\Important"], sortOrder: 12),
            try mailboxRecord(accountID: account.accountID, name: "Notes", sortOrder: 13),
        ]

        let rows = mailReview.sidebarMailboxes(for: account)

        XCTAssertEqual(rows.map(\.displayName), ["Inbox", "Sent", "Drafts", "Junk", "Trash", "Notes"])
        XCTAssertEqual(rows.first(where: { $0.displayName == "Sent" })?.mailboxName, "[Google Mail]/Sent Mail")
        XCTAssertFalse(rows.contains { $0.mailboxName == "[Google Mail]/All Mail" })
        XCTAssertFalse(rows.contains { $0.mailboxName == "[Google Mail]/Starred" })
        XCTAssertFalse(rows.contains { $0.mailboxName == "[Google Mail]/Important" })
    }

    func testMailSidebarCollapsesGenericSpecialUseDuplicates() throws {
        let account = EmailAccountRecord(
            accountID: "icloud-account",
            displayName: "iCloud",
            providerType: EmailProvider.icloud.rawValue
        )
        let mailReview = MailReviewModel()
        mailReview.mailboxesByAccountID[account.accountID] = [
            try mailboxRecord(accountID: account.accountID, name: "INBOX", sortOrder: 0),
            try mailboxRecord(accountID: account.accountID, name: "Sent Messages", flags: ["\\Sent"], sortOrder: 1),
            try mailboxRecord(accountID: account.accountID, name: "Sent", sortOrder: 2),
            try mailboxRecord(accountID: account.accountID, name: "Deleted Messages", flags: ["\\Trash"], sortOrder: 3),
            try mailboxRecord(accountID: account.accountID, name: "Trash", sortOrder: 4),
            try mailboxRecord(accountID: account.accountID, name: "Projects", sortOrder: 5),
        ]

        let rows = mailReview.sidebarMailboxes(for: account)

        XCTAssertEqual(rows.map(\.displayName), ["Inbox", "Sent", "Trash", "Projects"])
        XCTAssertEqual(rows.first(where: { $0.displayName == "Sent" })?.mailboxName, "Sent Messages")
        XCTAssertEqual(rows.first(where: { $0.displayName == "Trash" })?.mailboxName, "Deleted Messages")
    }

    func testMailReviewSearchTextFiltersFixtureMessages() async throws {
        let runtime = FixtureRuntimeClient(profile: .syntheticMCPUI)
        let mailAccounts = MailAccountsModel()
        mailAccounts.configure(client: runtime)
        let mailReview = MailReviewModel()
        mailReview.configure(mailAccounts: mailAccounts)

        await mailReview.prepare(force: true)

        mailReview.searchText = "tea party"
        await mailReview.retry()
        XCTAssertEqual(mailReview.messages.map(\.subject), ["Model garden tea party"])

        mailReview.searchText = "semicolon"
        await mailReview.retry()
        XCTAssertEqual(mailReview.messages.map(\.subject), ["Codex found the missing semicolon"])
    }

    func testMailReviewNextAndPreviousReloadRuntimePages() async throws {
        let runtime = PagingMailRuntime()
        let mailAccounts = MailAccountsModel()
        mailAccounts.configure(client: runtime)
        let mailReview = MailReviewModel()
        mailReview.configure(mailAccounts: mailAccounts)

        await mailReview.prepare(force: true)

        let firstPageIDs = mailReview.messages.map(\.emailID)
        XCTAssertEqual(mailReview.totalMessageCount, 60)
        XCTAssertEqual(firstPageIDs.first, "page-059")
        XCTAssertEqual(firstPageIDs.last, "page-035")

        await mailReview.nextPage()
        let secondPageIDs = mailReview.messages.map(\.emailID)
        XCTAssertNotEqual(firstPageIDs, secondPageIDs)
        XCTAssertEqual(secondPageIDs.first, "page-034")
        XCTAssertEqual(secondPageIDs.last, "page-010")

        await mailReview.previousPage()
        XCTAssertEqual(mailReview.messages.map(\.emailID), firstPageIDs)

        mailReview.searchText = "sender10@example.com"
        await mailReview.retry()
        let searchRequest = await runtime.lastPageRequest()
        XCTAssertEqual(searchRequest?.freeText, "sender10@example.com")
        XCTAssertNil(searchRequest?.accountID)
        XCTAssertNil(searchRequest?.mailbox)
        XCTAssertNil(searchRequest?.filter)
    }

    func testAccessFileSearchMatchesRawUnfilteredPaths() {
        let file = SourceFile(
            name: "Invoice.pdf",
            path: "/Users/example/Documents/Receipts/Invoice.pdf",
            canonicalPath: "Work/Receipts/Invoice.pdf",
            relativePath: "Receipts/Invoice.pdf",
            sourceName: "Work",
            sourceID: "src-work",
            fileExtension: "pdf",
            sizeBytes: 2048,
            modifiedDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertTrue(FilesFlatView.fileMatchesRawSearch(file, searchText: "invoice"))
        XCTAssertTrue(FilesFlatView.fileMatchesRawSearch(file, searchText: "Work/Receipts"))
        XCTAssertTrue(FilesFlatView.fileMatchesRawSearch(file, searchText: "/Users/example/Documents"))
        XCTAssertFalse(FilesFlatView.fileMatchesRawSearch(file, searchText: "missing"))
    }

    private func mailboxRecord(
        accountID: String,
        name: String,
        flags: [String] = [],
        sortOrder: Int
    ) throws -> IMAPMailboxRecord {
        let flagsData = try JSONSerialization.data(withJSONObject: flags)
        let flagsJSON = String(data: flagsData, encoding: .utf8) ?? "[]"
        return try XCTUnwrap(IMAPMailboxRecord(row: [
            "account_id": accountID,
            "mailbox_name": name,
            "delimiter": "/",
            "flags": flagsJSON,
            "is_selectable": "1",
            "sort_order": "\(sortOrder)",
        ]))
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
            sender: "Mario Amodei <mario@anthropologie.test>",
            recipients: "policy@manifold.test",
            subject: "Constitution sync",
            receivedAt: "2026-04-15T09:00:00Z",
            messageIDHeader: "<constitution-sync@anthropic.test>"
        )
        let reply = EmailMessageRecord(
            emailID: "email-reply",
            accountID: "account-1",
            mailbox: "INBOX",
            sender: "Sable Alman <sable@openai.test>",
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
            sender: "Greg Brackman <greg@openai.test>",
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

    func testPrivacyPresetCustomRoundTripsThroughFixtureRuntime() async throws {
        let runtime = FixtureRuntimeClient(profile: .privacy)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .privacy))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.governance.loadPolicies()

        var settings = try XCTUnwrap(store.governance.privacySettings)
        var claude = try XCTUnwrap(store.governance.claudePrivacyPolicy)
        var codex = try XCTUnwrap(store.governance.codexPrivacyPolicy)
        let (strictSettings, strictClaude, strictCodex) = PrivacyPreset.strict.apply(
            to: &settings,
            claude: claude,
            codex: codex
        )

        await store.governance.updatePrivacySettings(strictSettings)
        await store.governance.updatePrivacyPolicy(strictClaude)
        await store.governance.updatePrivacyPolicy(strictCodex)

        settings = try XCTUnwrap(store.governance.privacySettings)
        claude = try XCTUnwrap(store.governance.claudePrivacyPolicy)
        codex = try XCTUnwrap(store.governance.codexPrivacyPolicy)
        let (customSettings, customClaude, customCodex) = PrivacyPreset.custom.apply(
            to: &settings,
            claude: claude,
            codex: codex
        )

        await store.governance.updatePrivacySettings(customSettings)
        await store.governance.updatePrivacyPolicy(customClaude)
        await store.governance.updatePrivacyPolicy(customCodex)

        XCTAssertEqual(
            PrivacyPreset.detect(
                settings: store.governance.privacySettings,
                claudePolicy: store.governance.claudePrivacyPolicy,
                codexPolicy: store.governance.codexPrivacyPolicy
            ),
            .custom
        )
    }

    func testPrivacyPresetDetectionIncludesFileScanningMode() async throws {
        let runtime = FixtureRuntimeClient(profile: .privacy)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .privacy))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.governance.loadPolicies()

        var settings = try XCTUnwrap(store.governance.privacySettings)
        let claude = try XCTUnwrap(store.governance.claudePrivacyPolicy)
        let codex = try XCTUnwrap(store.governance.codexPrivacyPolicy)
        let (balancedSettings, balancedClaude, balancedCodex) = PrivacyPreset.balanced.apply(
            to: &settings,
            claude: claude,
            codex: codex
        )

        XCTAssertEqual(
            PrivacyPreset.detect(
                settings: balancedSettings,
                claudePolicy: balancedClaude,
                codexPolicy: balancedCodex,
                filterMode: .warn
            ),
            .balanced
        )
        XCTAssertEqual(
            PrivacyPreset.detect(
                settings: balancedSettings,
                claudePolicy: balancedClaude,
                codexPolicy: balancedCodex,
                filterMode: .block
            ),
            .custom
        )
        XCTAssertEqual(PrivacyPreset.off.filterMode, .off)
        XCTAssertEqual(PrivacyPreset.balanced.filterMode, .warn)
        XCTAssertEqual(PrivacyPreset.strict.filterMode, .block)
    }

    func testFileVisibilityOverridesRoundTripThroughRuntime() async throws {
        let runtime = FixtureRuntimeClient(profile: .baseline)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .baseline))
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

    func testRulesSearchTextFiltersFixtureRules() async {
        let rules = RulesModel()
        rules.configure(client: FixtureRuntimeClient(profile: .privacy))

        await rules.load()

        rules.searchText = "digests"
        XCTAssertEqual(rules.filteredRules.map(\.id), ["rule-email-openai"])

        rules.searchText = "secret"
        XCTAssertEqual(rules.filteredRules.map(\.id), ["rule-seeded-secret"])
    }
}

@MainActor
final class MailProviderOnboardingGuideTests: XCTestCase {
    func testTopLevelProviderSurfaceIsFourNativeChoices() {
        XCTAssertEqual(MailOnboardingProvider.allCases.map(\.accessibilityIdentifier), [
            "settings.mail.provider.google",
            "settings.mail.provider.microsoft",
            "settings.mail.provider.icloud",
            "settings.mail.provider.other",
        ])
        XCTAssertEqual(MailOnboardingProvider.allCases.map(\.emailProvider), [.gmail, .outlook, .icloud, .other])
        XCTAssertFalse(MailOnboardingProvider.allCases.contains { $0.emailProvider == .fastmail })
        XCTAssertFalse(MailOnboardingProvider.allCases.contains { $0.emailProvider == .yahoo })
    }

    func testTopLevelProviderGuidesHaveRequiredCopyAndLinks() {
        for provider in MailOnboardingProvider.allCases {
            let guide = provider.guide

            XCTAssertFalse(guide.displayLabel.isEmpty)
            XCTAssertFalse(guide.detail.isEmpty)
            XCTAssertFalse(guide.credentialLabel.isEmpty)
            XCTAssertFalse(guide.steps.isEmpty)
            XCTAssertFalse(guide.links.isEmpty)
            XCTAssertFalse(guide.validationHelp.isEmpty)
            XCTAssertFalse(guide.primaryActionTitle.isEmpty)
        }
    }

    func testProviderGuidesDescribeExpectedCredentialFlows() {
        let google = MailProviderOnboardingGuide.guide(for: .gmail)
        XCTAssertEqual(google.credentialLabel, "Google app password")
        XCTAssertTrue(google.steps.contains { $0.contains("2-Step Verification") })
        XCTAssertTrue(google.links.contains { $0.title == "Open Google App Passwords" })

        let microsoft = MailProviderOnboardingGuide.guide(for: .outlook)
        XCTAssertEqual(microsoft.credentialLabel, "Microsoft sign-in")
        XCTAssertEqual(microsoft.primaryActionTitle, "Sign in with Microsoft")
        XCTAssertTrue(microsoft.blockers.contains { $0.contains("administrator consent") })

        let iCloud = MailProviderOnboardingGuide.guide(for: .icloud)
        XCTAssertEqual(iCloud.credentialLabel, "Apple app-specific password")
        XCTAssertTrue(iCloud.steps.contains { $0.contains("app-specific password") })
        XCTAssertTrue(iCloud.links.contains { $0.title.contains("Apple App-Specific Passwords") })

        let other = MailProviderOnboardingGuide.guide(for: .other)
        XCTAssertEqual(other.credentialLabel, "Password or app password")
        XCTAssertTrue(other.steps.contains { $0.contains("IMAP host") })
    }

    func testProviderLogoAssetsAreAvailableToTheAppBundle() {
        XCTAssertNotNil(NSImage(named: "Google_\"G\"_logo"))
        XCTAssertNotNil(NSImage(named: "microsoft"))
    }

    func testOtherGuideDetectsYahooAndFastmail() {
        let yahoo = MailProviderOnboardingGuide.guide(for: .other, emailAddress: "person@yahoo.com")
        XCTAssertEqual(yahoo.resolvedProvider, .yahoo)
        XCTAssertEqual(yahoo.credentialLabel, "Yahoo app password")
        XCTAssertTrue(yahoo.links.contains { $0.title.contains("Yahoo") })

        let fastmail = MailProviderOnboardingGuide.guide(for: .other, emailAddress: "person@fastmail.com")
        XCTAssertEqual(fastmail.resolvedProvider, .fastmail)
        XCTAssertEqual(fastmail.credentialLabel, "Fastmail app password")
        XCTAssertTrue(fastmail.links.contains { $0.title.contains("Fastmail") })
    }

    func testMailSyncProgressPresentationBuildsAccountSidebarCopy() {
        let progress = mailProgress(stage: .archivingOlderMail, syncedMessageCount: 12_430)
        let subtitle = MailSyncProgressPresentation.accountSubtitle(
            progress: progress,
            account: mailAccount()
        )

        XCTAssertEqual(subtitle, "12,430 synced · Archiving older mail")
    }

    func testMailSyncProgressPresentationDoesNotReportZeroMailboxErrorsForAccountFailure() {
        let progress = mailProgress(stage: .needsAttention, failedMailboxCount: 0)
        let subtitle = MailSyncProgressPresentation.accountSubtitle(
            progress: progress,
            account: mailAccount()
        )

        XCTAssertEqual(subtitle, "Needs attention · Sync error")
    }

    func testMailSyncProgressPresentationShowsRetryQueuedWithoutNeedsAttention() {
        let progress = mailProgress(
            stage: .recentMailReady,
            syncedMessageCount: 2_381,
            retryScheduledCount: 3
        )
        let subtitle = MailSyncProgressPresentation.accountSubtitle(
            progress: progress,
            account: mailAccount()
        )

        XCTAssertEqual(subtitle, "2,381 synced · Retry queued")
    }

    func testMailSyncProgressPresentationBuildsMailboxCountAndStatus() {
        let progress = mailProgress(
            stage: .syncingRecentMail,
            mailboxSyncedCounts: ["INBOX": 842],
            currentMailboxName: "INBOX"
        )
        let state = SyncStateRecord(
            accountID: "account-1",
            mailboxName: "INBOX",
            messageCount: 842
        )

        XCTAssertEqual(MailSyncProgressPresentation.mailboxCount(progress: progress, mailboxName: "INBOX"), "842")
        XCTAssertEqual(
            MailSyncProgressPresentation.mailboxSubtitle(
                progress: progress,
                mailboxName: "INBOX",
                syncState: state
            ),
            "Syncing recent mail"
        )
    }

    func testMailSyncProgressPresentationBuildsSelectedToolbarStatus() {
        let progress = mailProgress(
            stage: .archivingOlderMail,
            mailboxSyncedCounts: ["INBOX": 842]
        )

        let status = MailSyncProgressPresentation.toolbarStatus(
            account: mailAccount(),
            mailboxDisplayName: "Inbox",
            mailboxName: "INBOX",
            progress: progress
        )

        XCTAssertEqual(status, "Gmail · Inbox · 842 messages · Archiving older mail")
    }

    func testMailSyncProgressPresentationOrdersActivityByAttentionThenActiveWork() {
        let ordered = MailSyncProgressPresentation.orderedForActivity([
            mailProgress(accountID: "up-to-date", displayName: "Up To Date", stage: .upToDate, syncedMessageCount: 20),
            mailProgress(accountID: "active", displayName: "Active", stage: .syncingRecentMail, syncedMessageCount: 10, runningJobCount: 1),
            mailProgress(accountID: "error", displayName: "Error", stage: .needsAttention, syncedMessageCount: 5, failedMailboxCount: 1),
            mailProgress(accountID: "ready", displayName: "Ready", stage: .recentMailReady, syncedMessageCount: 30),
        ])

        XCTAssertEqual(ordered.map(\.accountID), ["error", "active", "ready", "up-to-date"])
    }

    func testMailSyncProgressPresentationBuildsActivityLogEntryTitle() {
        let event = MailSyncActivityLogEntry(
            accountID: "account-1",
            mailboxName: "INBOX",
            kind: .retryScheduled,
            status: "Retry scheduled",
            jobType: .historicalBackfill,
            createdAt: "2026-05-03T00:30:00Z"
        )

        XCTAssertEqual(
            MailSyncProgressPresentation.eventTitle(event),
            "Retry scheduled · INBOX · Older mail archive"
        )
    }

    private func mailAccount() -> EmailAccountRecord {
        EmailAccountRecord(
            accountID: "account-1",
            displayName: "Gmail",
            providerType: EmailProvider.gmail.rawValue
        )
    }

    private func mailProgress(
        accountID: String = "account-1",
        displayName: String = "Gmail",
        stage: MailSyncProgressStage,
        syncedMessageCount: Int = 842,
        mailboxSyncedCounts: [String: Int] = ["INBOX": 842],
        runningJobCount: Int = 0,
        queuedBackfillCount: Int = 0,
        retryScheduledCount: Int = 0,
        failedMailboxCount: Int = 0,
        currentMailboxName: String? = nil
    ) -> MailSyncProgressSnapshot {
        MailSyncProgressSnapshot(
            accountID: accountID,
            displayName: displayName,
            provider: .gmail,
            syncedMessageCount: syncedMessageCount,
            mailboxSyncedCounts: mailboxSyncedCounts,
            stage: stage,
            runningJobCount: runningJobCount,
            queuedBackfillCount: queuedBackfillCount,
            retryScheduledCount: retryScheduledCount,
            failedMailboxCount: failedMailboxCount,
            currentMailboxName: currentMailboxName,
            lastUpdatedAt: "2026-05-02T10:05:00Z"
        )
    }
}

private enum PendingApprovalsFailure: Error {
    case unavailable
}

private struct MailPageRequest: Sendable {
    let freeText: String
    let accountID: String?
    let mailbox: String?
    let filter: QuickFilter?
}

private actor PagingMailRuntime: RuntimeClientProtocol {
    private let accountID: String
    private let account: EmailAccountRecord
    private let mailbox: IMAPMailboxRecord
    private let messages: [EmailMessageRecord]
    private var pageRequests: [MailPageRequest] = []

    init() {
        let accountID = "paging-account"
        self.accountID = accountID
        let now = ISO8601DateFormatter.shared.string(from: Date())
        account = EmailAccountRecord(
            accountID: accountID,
            displayName: "Paging Mail",
            providerType: EmailProvider.gmail.rawValue,
            server: "imap.example.com",
            port: 993,
            username: "paging@example.com",
            createdAt: now,
            updatedAt: now
        )
        mailbox = IMAPMailboxRecord(row: [
            "account_id": accountID,
            "mailbox_name": "INBOX",
            "delimiter": "/",
            "flags": #"["\\Inbox"]"#,
            "is_selectable": "1",
            "sort_order": "0",
        ])!
        messages = (0..<60).map { index in
            EmailMessageRecord(
                emailID: String(format: "page-%03d", index),
                accountID: accountID,
                mailbox: "INBOX",
                sender: "Sender \(index) <sender\(index)@example.com>",
                senderEmail: "sender\(index)@example.com",
                senderDomain: "example.com",
                recipients: "recipient@example.com",
                subject: "Paged message \(index)",
                receivedAt: ISO8601DateFormatter.shared.string(
                    from: Date(timeIntervalSince1970: 1_800_000_000 + TimeInterval(index))
                )
            )
        }
    }

    func listEmailAccounts() async throws -> [EmailAccountRecord] {
        [account]
    }

    func emailMessageCount() async throws -> Int {
        messages.count
    }

    func imapMailboxes(accountID: String) async throws -> [IMAPMailboxRecord] {
        accountID == self.accountID ? [mailbox] : []
    }

    func lastPageRequest() -> MailPageRequest? {
        pageRequests.last
    }

    func emailMessagePage(
        tokens: [SearchToken],
        freeText: String,
        accountID: String?,
        mailbox: String?,
        filter: QuickFilter?,
        sortKey: EmailSortKey,
        limit: Int,
        offset: Int
    ) async throws -> EmailMessagePage {
        pageRequests.append(MailPageRequest(freeText: freeText, accountID: accountID, mailbox: mailbox, filter: filter))
        let term = freeText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sorted = messages
            .filter { message in
                (accountID == nil || message.accountID == accountID)
                    && (mailbox == nil || message.mailbox == mailbox)
                    && (term.isEmpty || [message.sender, message.subject, message.preview ?? ""].joined(separator: "\n").lowercased().contains(term))
            }
            .sorted { $0.receivedAt > $1.receivedAt }
        let page = sorted.dropFirst(max(0, offset)).prefix(max(0, limit))
        return EmailMessagePage(
            messages: Array(page),
            totalCount: sorted.count,
            limit: max(0, limit),
            offset: max(0, offset)
        )
    }
}

private actor PendingApprovalsFailureRuntime: RuntimeClientProtocol {
    private let fixture = FixtureRuntimeClient(profile: .trackedWork)

    func ping() async -> RuntimePingResult {
        RuntimePingResult(ok: true, agentVersion: nil)
    }

    func runtimeStatusSnapshot() async throws -> RuntimeStatusSnapshot {
        try await fixture.runtimeStatusSnapshot()
    }

    func activeGrantState(targetApp: TargetApp) async throws -> ActiveGrantState {
        ActiveGrantState(
            activeGrant: nil,
            activeGrantSources: [],
            targetApp: targetApp.rawValue,
            selectedEmailCount: nil
        )
    }

    func listPendingApprovals() async throws -> [PendingApprovalRecord] {
        throw PendingApprovalsFailure.unavailable
    }
}

private actor RemovedSourceRuntimeStatusRuntime: RuntimeClientProtocol {
    func ping() async -> RuntimePingResult {
        RuntimePingResult(ok: true, agentVersion: nil)
    }

    func runtimeStatusSnapshot() async throws -> RuntimeStatusSnapshot {
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

        return RuntimeStatusSnapshot(
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
