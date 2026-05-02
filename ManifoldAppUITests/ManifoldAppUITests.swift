// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import AppKit
import XCTest

@MainActor
class ManifoldUITestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        Self.terminateExistingAppIfNeeded()
        NSWorkspace.shared.hideOtherApplications()
    }

    override func tearDown() {
        Self.terminateExistingAppIfNeeded()
        super.tearDown()
    }

    @discardableResult
    func launchFixture(profile: String) -> XCUIApplication {
        let app = XCUIApplication()
        let testHome = makeTestHome(prefix: "fixture-\(profile)")
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-rules.inspectorVisible", "YES",
            "-access.inspector.visible", "YES"
        ]
        app.launchEnvironment["MANIFOLD_UI_TEST_MODE"] = "1"
        app.launchEnvironment["MANIFOLD_DISABLE_REAL_RUNTIME"] = "1"
        app.launchEnvironment["MANIFOLD_TEST_RUNTIME_MODE"] = "fixture"
        app.launchEnvironment["MANIFOLD_FIXTURE_PROFILE"] = profile
        app.launchEnvironment["MANIFOLD_TEST_HOME"] = testHome
        app.launch()
        app.activate()
        return app
    }

    @discardableResult
    func launchSyntheticMCPUI(scenario: String = "synthetic-mcp-ui") -> XCUIApplication {
        let app = XCUIApplication()
        let testHome = makeTestHome(prefix: "synthetic-\(scenario)")
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-rules.inspectorVisible", "YES",
            "-access.inspector.visible", "YES"
        ]
        app.launchEnvironment["MANIFOLD_UI_TEST_MODE"] = "1"
        app.launchEnvironment["MANIFOLD_TEST_RUNTIME_MODE"] = "local"
        app.launchEnvironment["MANIFOLD_TEST_SCENARIO"] = scenario
        app.launchEnvironment["MANIFOLD_TEST_HOME"] = testHome
        app.launch()
        app.activate()
        return app
    }

    func openSettings(in app: XCUIApplication) {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(element(in: app, id: "settings.window").waitForExistence(timeout: 8))
    }

    func openLedgerSpace(
        _ spaceID: String,
        expectedSurface surfaceID: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 8
    ) {
        let button = ledgerSpaceButton(spaceID, in: app, timeout: timeout)
        app.activate()
        button.click()
        XCTAssertTrue(element(in: app, id: surfaceID).waitForExistence(timeout: timeout))
    }

    func ledgerSpaceButton(_ spaceID: String, in app: XCUIApplication, timeout: TimeInterval = 8) -> XCUIElement {
        let title = ledgerSpaceTitle(spaceID)
        let button = app.buttons[title]
        if button.waitForExistence(timeout: 1) {
            return button
        }

        let identified = element(in: app, id: "ledger.space.\(spaceID)")
        XCTAssertTrue(identified.waitForExistence(timeout: timeout), "Expected ledger space \(spaceID)")
        return identified
    }

    func assertLedgerSpaceExists(_ spaceID: String, in app: XCUIApplication) {
        if app.buttons[ledgerSpaceTitle(spaceID)].exists { return }
        let identified = element(in: app, id: "ledger.space.\(spaceID)")
        if identified.exists { return }
        XCTAssertTrue(identified.exists, "Expected ledger space \(spaceID)")
    }

    private func ledgerSpaceTitle(_ spaceID: String) -> String {
        switch spaceID {
        case "work": return "Work"
        case "access": return "Access"
        case "mail": return "Mail"
        case "rules": return "Rules"
        default: return spaceID
        }
    }

    func clearAndType(_ textField: XCUIElement, text: String) {
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.click()
        textField.typeKey("a", modifierFlags: .command)
        textField.typeText(text)
    }

    func clickElement(
        in app: XCUIApplication,
        id: String,
        fallbackButtonTitle: String,
        timeout: TimeInterval = 5
    ) {
        let identified = element(in: app, id: id)
        if identified.waitForExistence(timeout: timeout) {
            app.activate()
            identified.click()
            return
        }

        let fallback = app.buttons[fallbackButtonTitle]
        XCTAssertTrue(fallback.waitForExistence(timeout: timeout), "Expected \(id) or button \(fallbackButtonTitle)")
        app.activate()
        fallback.click()
    }

    func clickSettingsTab(_ title: String, contentID: String, in app: XCUIApplication) {
        let content = element(in: app, id: contentID)
        if content.exists { return }

        let settingsWindow = app.windows["com_apple_SwiftUI_Settings_window"]
        let tab = settingsWindow.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 8), "Expected Settings tab \(title)")
        tab.click()
        XCTAssertTrue(content.waitForExistence(timeout: 8), "Expected Settings content \(contentID)")
    }

    func elementOrTextField(
        in app: XCUIApplication,
        id: String,
        fallbackPlaceholder: String,
        timeout: TimeInterval = 5
    ) -> XCUIElement {
        let identified = element(in: app, id: id)
        if identified.waitForExistence(timeout: timeout) {
            return identified
        }
        let fallback = app.textFields[fallbackPlaceholder]
        return fallback.exists ? fallback : app.textFields.firstMatch
    }

    nonisolated static func terminateExistingAppIfNeeded() {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spatialduality.manifold")
        guard !applications.isEmpty else { return }

        for application in applications {
            application.terminate()
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if applications.allSatisfy(\.isTerminated) {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    func element(in app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    func element(in app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    func waitForValue(_ value: String, in element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitForValue(_ value: String, elementID id: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { [self] _, _ in
            let element = element(in: app, id: id)
            return element.exists && (element.value as? String) == value
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func makeTestHome(prefix: String) -> String {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("manifold-ui-tests", isDirectory: true)
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        addTeardownBlock {
            Self.terminateExistingAppIfNeeded()
            try? FileManager.default.removeItem(at: root)
        }
        return root.path
    }
}

@MainActor
final class ManifoldFixtureUITests: ManifoldUITestCase {
    func testOnboardingFixtureCanSkipIntoLedger() {
        let app = launchFixture(profile: "onboarding")

        XCTAssertTrue(app.staticTexts["Protect your next AI session"].waitForExistence(timeout: 5))

        app.buttons["Continue"].click()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))

        app.buttons["Continue"].click()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))

        app.buttons["Continue"].click()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))

        app.buttons["Skip setup"].click()
        XCTAssertTrue(element(in: app, id: "ledger.surface.work").waitForExistence(timeout: 8))
        assertLedgerSpaceExists("work", in: app)
    }

    func testSpaceSwitcherNavigationShowsCurrentLedgerSurfaces() {
        let app = launchFixture(profile: "tracked-work")

        XCTAssertTrue(element(in: app, id: "ledger.sidebar").waitForExistence(timeout: 8))
        // Default destination is Work.
        XCTAssertTrue(element(in: app, id: "ledger.surface.work").waitForExistence(timeout: 8))

        openLedgerSpace("access", expectedSurface: "ledger.surface.access", in: app)
        openLedgerSpace("mail", expectedSurface: "ledger.surface.mail", in: app)
        XCTAssertTrue(element(in: app, id: "mail.review.table").waitForExistence(timeout: 8))
        openLedgerSpace("rules", expectedSurface: "ledger.surface.rules", in: app)
        openLedgerSpace("work", expectedSurface: "ledger.surface.work", in: app)

        assertLedgerSpaceExists("work", in: app)
        assertLedgerSpaceExists("access", in: app)
        assertLedgerSpaceExists("mail", in: app)
        assertLedgerSpaceExists("rules", in: app)
    }

    func testMailFixtureLoadsCurrentReviewSurfaceAndInspector() {
        let app = launchFixture(profile: "tracked-work")

        openLedgerSpace("mail", expectedSurface: "ledger.surface.mail", in: app)

        XCTAssertTrue(element(in: app, id: "mail.review.table").waitForExistence(timeout: 8))
        let subject = app.staticTexts["Operator smoke test"]
        XCTAssertTrue(subject.waitForExistence(timeout: 8))
        subject.click()

        XCTAssertTrue(element(in: app, id: "mail.message.inspector.visibility.email-4").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, id: "mail.message.share.all").exists)
        XCTAssertTrue(element(in: app, id: "mail.message.share.agent.codex").exists)
    }

    func testMailSettingsConnectMailboxFlowShowsProviderAndCredentialSteps() {
        let app = launchFixture(profile: "tracked-work")

        XCTAssertTrue(element(in: app, id: "ledger.surface.work").waitForExistence(timeout: 8))
        openSettings(in: app)
        clickSettingsTab("Mail", contentID: "settings.mail.connectAccount", in: app)

        let connectAccount = element(in: app, id: "settings.mail.connectAccount")
        XCTAssertTrue(connectAccount.waitForExistence(timeout: 8))
        connectAccount.click()

        XCTAssertTrue(element(in: app, id: "settings.mail.addAccount.header").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, id: "settings.mail.provider.fastmail").exists)

        let gmailProvider = element(in: app, id: "settings.mail.provider.gmail")
        XCTAssertTrue(gmailProvider.waitForExistence(timeout: 8))
        gmailProvider.click()

        XCTAssertTrue(element(in: app, id: "settings.mail.account.header").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, id: "settings.mail.account.displayName").waitForExistence(timeout: 5))

        let username = element(in: app, id: "settings.mail.account.username")
        clearAndType(username, text: "ada.lovelace@example.test")

        let password = element(in: app, id: "settings.mail.account.password")
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.click()
        password.typeText("sample-app-password-only")

        XCTAssertTrue(element(in: app, id: "settings.mail.account.server").exists)
        XCTAssertTrue(element(in: app, id: "settings.mail.account.port").exists)
        XCTAssertTrue(element(in: app, id: "settings.mail.account.connect").isEnabled)
    }

    func testAccessFoldersCanClearMixedScopeForBothAgents() {
        let app = launchFixture(profile: "tracked-work")

        openLedgerSpace("access", expectedSurface: "ledger.surface.access", in: app)

        let bothControl = element(in: app, id: "access.folder.src-claude.all")
        XCTAssertTrue(bothControl.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForValue("partially shared", in: bothControl, timeout: 5))

        bothControl.click()

        XCTAssertTrue(waitForValue("not shared", in: bothControl, timeout: 5))
        XCTAssertTrue(waitForValue("not shared", in: element(in: app, id: "access.folder.src-claude.agent.cowork"), timeout: 5))
        XCTAssertTrue(waitForValue("not shared", in: element(in: app, id: "access.folder.src-claude.agent.codex"), timeout: 5))
    }

    func testAccessFilesCanToggleSingleFileForCodex() {
        let app = launchFixture(profile: "tracked-work")

        openLedgerSpace("access", expectedSurface: "ledger.surface.access", in: app)
        let filesSection = element(in: app, id: "access.sidebar.files")
        XCTAssertTrue(filesSection.waitForExistence(timeout: 8))
        filesSection.click()

        let markerFile = element(in: app, id: "access.file.src-claude.marker-txt.name")
        XCTAssertTrue(markerFile.waitForExistence(timeout: 8))
        markerFile.click()

        let codexControl = element(in: app, id: "access.inspector.file.src-claude.marker-txt.agent.codex")
        XCTAssertTrue(codexControl.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForValue("off", in: codexControl, timeout: 5))

        codexControl.click()

        XCTAssertTrue(waitForValue("on", elementID: "access.inspector.file.src-claude.marker-txt.agent.codex", in: app, timeout: 5))
    }

    func testApprovalsQueueCanResolveFixtureApproval() {
        let app = launchFixture(profile: "tracked-work")

        openLedgerSpace("work", expectedSurface: "ledger.surface.work", in: app)

        let approvalRow = element(in: app, id: "work.approval.approval-1")
        XCTAssertTrue(approvalRow.waitForExistence(timeout: 8))
        clickElement(in: app, id: "work.approval.approval-1.deny", fallbackButtonTitle: "Deny")
        XCTAssertTrue(waitForNonExistence(approvalRow, timeout: 8))
    }

    func testCommandPaletteOpensAndAcceptsSearchInput() {
        let app = launchFixture(profile: "tracked-work")

        XCTAssertTrue(element(in: app, id: "ledger.surface.work").waitForExistence(timeout: 8))
        app.typeKey("k", modifierFlags: .command)

        let palette = element(in: app, id: "commandPalette.sheet")
        XCTAssertTrue(palette.waitForExistence(timeout: 8))

        let searchField = elementOrTextField(in: app, id: "commandPalette.search", fallbackPlaceholder: "Search commands...")
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("settings")

        XCTAssertTrue(waitForValue("settings", in: searchField, timeout: 5))
    }

    func testPrivacySettingsFixtureShowsPaneAndIndexStatus() {
        let app = launchFixture(profile: "privacy")

        XCTAssertTrue(element(in: app, id: "ledger.surface.work").waitForExistence(timeout: 8))
        openSettings(in: app)

        clickSettingsTab("Privacy", contentID: "settings.privacy.model.enabled", in: app)

        XCTAssertTrue(element(in: app, id: "settings.privacy.model.enabled").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.model.enabled").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.preset.custom").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.suggestion.suggestion-primary-name").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, id: "settings.privacy.index.stat.indexed").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.index.stat.failed").exists)
    }

    func testPrivacySettingsPresetCardsApplyFixtureChanges() {
        let app = launchFixture(profile: "privacy")

        XCTAssertTrue(element(in: app, id: "ledger.surface.work").waitForExistence(timeout: 8))
        openSettings(in: app)
        clickSettingsTab("Privacy", contentID: "settings.privacy.model.enabled", in: app)

        let strict = element(in: app, id: "settings.privacy.preset.strict")
        let custom = element(in: app, id: "settings.privacy.preset.custom")
        let off = element(in: app, id: "settings.privacy.preset.off")

        XCTAssertTrue(strict.waitForExistence(timeout: 5))
        strict.click()
        XCTAssertTrue(waitForValue("Selected", in: strict, timeout: 5))

        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()
        XCTAssertTrue(waitForValue("Selected", in: custom, timeout: 5))

        XCTAssertTrue(off.waitForExistence(timeout: 5))
        off.click()
        XCTAssertTrue(waitForValue("Selected", in: off, timeout: 5))
    }

    func testPrivacyWorkEvidenceRendersCurrentInspector() {
        let app = launchFixture(profile: "privacy")

        XCTAssertTrue(element(in: app, id: "ledger.surface.work").waitForExistence(timeout: 8))
        // Approvals filter scopes the Work timeline to privacy / coverage
        // events.
        clickElement(in: app, id: "work.timeline.filter.approvals", fallbackButtonTitle: "Approvals")

        let privacyRow = element(in: app, labelContaining: "Contains sensitive account context")
        XCTAssertTrue(privacyRow.waitForExistence(timeout: 8))
        privacyRow.click()

        XCTAssertTrue(element(in: app, id: "work.inspector").waitForExistence(timeout: 8))
    }

    func testRulesFixtureSupportsSearchInspectorAndEmptySuggestedState() {
        let app = launchFixture(profile: "privacy")

        openLedgerSpace("rules", expectedSurface: "ledger.surface.rules", in: app)

        let searchField = elementOrTextField(in: app, id: "rules.toolbar.search", fallbackPlaceholder: "Search rules")
        clearAndType(searchField, text: "OpenAI")
        let openAIRule = element(in: app, id: "rules.rowTitle.rule-email-openai")
        XCTAssertTrue(openAIRule.waitForExistence(timeout: 5))
        openAIRule.click()

        XCTAssertTrue(element(in: app, id: "rules.inspector.name").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, id: "rules.inspector.action").exists)

        element(in: app, id: "rules.sidebar.suggested").click()
        XCTAssertTrue(element(in: app, id: "rules.emptyState").waitForExistence(timeout: 5))
    }

    func testRulesSidebarFiltersDriveTheVisibleRuleSet() {
        let app = launchFixture(profile: "privacy")

        openLedgerSpace("rules", expectedSurface: "ledger.surface.rules", in: app)

        element(in: app, id: "rules.sidebar.scope-file").click()
        XCTAssertTrue(app.staticTexts["Protect Secrets"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Allow OpenAI mail"].exists)

        element(in: app, id: "rules.sidebar.scope-email").click()
        XCTAssertTrue(app.staticTexts["Allow OpenAI mail"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Protect Secrets"].exists)

        element(in: app, id: "rules.sidebar.privacy").click()
        XCTAssertTrue(app.staticTexts["Protect Secrets"].waitForExistence(timeout: 5))

        element(in: app, id: "rules.sidebar.user").click()
        XCTAssertTrue(app.staticTexts["Allow OpenAI mail"].waitForExistence(timeout: 5))

        element(in: app, id: "rules.sidebar.seeded").click()
        XCTAssertTrue(app.staticTexts["Protect Secrets"].waitForExistence(timeout: 5))
    }
}

@MainActor
final class ManifoldSyntheticMCPUITests: ManifoldUITestCase {
    func testSyntheticScenarioBootsAndShowsPrivacyApproval() {
        let app = launchSyntheticMCPUI()

        XCTAssertTrue(element(in: app, id: "ledger.surface.work").waitForExistence(timeout: 15))

        let approvalRow = element(in: app, id: "work.approval.approval-synthetic-mcp-ui")
        XCTAssertTrue(approvalRow.waitForExistence(timeout: 15))
        // Drill into the inspector for redacted/original actions.
        approvalRow.click()
        clickElement(in: app, id: "work.inspector.request.redact", fallbackButtonTitle: "Share redacted")
        XCTAssertTrue(waitForNonExistence(approvalRow, timeout: 15))
    }

    func testSyntheticMailAndWorkTimelineReflectSeededData() {
        let app = launchSyntheticMCPUI()

        XCTAssertTrue(element(in: app, id: "ledger.surface.work").waitForExistence(timeout: 15))
        openLedgerSpace("mail", expectedSurface: "ledger.surface.mail", in: app, timeout: 15)

        XCTAssertTrue(element(in: app, id: "mail.review.table").waitForExistence(timeout: 15))
        let subject = app.staticTexts["Privacy review needed"]
        XCTAssertTrue(subject.waitForExistence(timeout: 15))

        let searchField = elementOrTextField(
            in: app,
            id: "mail.searchField",
            fallbackPlaceholder: "Search sender, subject, or preview",
            timeout: 8
        )
        clearAndType(searchField, text: "tea party")
        XCTAssertTrue(app.staticTexts["Model garden tea party"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Codex found the missing semicolon"].exists)
        clearAndType(searchField, text: "semicolon")
        XCTAssertTrue(app.staticTexts["Codex found the missing semicolon"].waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeKey("a", modifierFlags: .command)
        searchField.typeKey(.delete, modifierFlags: [])

        subject.click()

        XCTAssertTrue(element(in: app, id: "mail.message.inspector.visibility.runtime-email-1").waitForExistence(timeout: 8))

        openLedgerSpace("work", expectedSurface: "ledger.surface.work", in: app, timeout: 15)
        clickElement(in: app, id: "work.timeline.filter.approvals", fallbackButtonTitle: "Approvals")

        let target = element(in: app, id: "work.timeline.privacy.runtime-email-1")
        XCTAssertTrue(target.waitForExistence(timeout: 15))
        target.click()

        XCTAssertTrue(element(in: app, id: "work.inspector.event.runtime-email-1").waitForExistence(timeout: 8))
    }

    func testSyntheticSettingsPrivacyPaneShowsDiscoveryData() {
        let app = launchSyntheticMCPUI()

        XCTAssertTrue(element(in: app, id: "ledger.surface.work").waitForExistence(timeout: 15))
        openSettings(in: app)

        clickSettingsTab("Privacy", contentID: "settings.privacy.model.enabled", in: app)

        XCTAssertTrue(element(in: app, id: "settings.privacy.model.enabled").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.suggestion.privacy-suggestion-runtime-name").waitForExistence(timeout: 10))
        XCTAssertTrue(element(in: app, id: "settings.privacy.identities.table").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.allowlist.table").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.index.stat.indexed").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.index.stat.failed").exists)
    }
}
