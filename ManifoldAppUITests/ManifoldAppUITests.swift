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
    }

    override func tearDown() {
        Self.terminateExistingAppIfNeeded()
        super.tearDown()
    }

    @discardableResult
    func launchFixture(profile: String) -> XCUIApplication {
        let app = XCUIApplication()
        let testHome = makeTestHome(prefix: "fixture-\(profile)")
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
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
    func launchLocalRuntime(scenario: String = "privacy-e2e") -> XCUIApplication {
        let app = XCUIApplication()
        let testHome = makeTestHome(prefix: "runtime-\(scenario)")
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
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

    func openSidebarDestination(
        _ destinationID: String,
        expectedSurface surfaceID: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 8
    ) {
        let button = element(in: app, id: destinationID)
        XCTAssertTrue(button.waitForExistence(timeout: timeout))
        app.activate()
        button.click()
        XCTAssertTrue(element(in: app, id: surfaceID).waitForExistence(timeout: timeout))
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
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))

        app.buttons["Skip setup"].click()
        XCTAssertTrue(element(in: app, id: "ledger.surface.activity").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, id: "ledger.sidebar.activity").exists)
    }

    func testSidebarNavigationShowsCurrentLedgerSurfaces() {
        let app = launchFixture(profile: "tracked-work")

        XCTAssertTrue(element(in: app, id: "ledger.sidebar").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, id: "ledger.surface.activity").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, labelContaining: "Tracked session live").waitForExistence(timeout: 5))

        openSidebarDestination("ledger.sidebar.access", expectedSurface: "ledger.surface.access", in: app)
        openSidebarDestination("ledger.sidebar.mail", expectedSurface: "ledger.surface.mail", in: app)
        XCTAssertTrue(element(in: app, id: "mail.review.table").waitForExistence(timeout: 8))
        openSidebarDestination("ledger.sidebar.requests", expectedSurface: "ledger.surface.requests", in: app)
        openSidebarDestination("ledger.sidebar.rules", expectedSurface: "ledger.surface.rules", in: app)
    }

    func testMailFixtureLoadsCurrentReviewSurfaceAndInspector() {
        let app = launchFixture(profile: "tracked-work")

        openSidebarDestination("ledger.sidebar.mail", expectedSurface: "ledger.surface.mail", in: app)

        XCTAssertTrue(element(in: app, id: "mail.review.table").waitForExistence(timeout: 8))
        let subject = app.staticTexts["Operator smoke test"]
        XCTAssertTrue(subject.waitForExistence(timeout: 8))
        subject.click()

        XCTAssertTrue(element(in: app, id: "mail.message.inspector.visibility.email-4").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, id: "mail.message.allow").exists)
        XCTAssertTrue(element(in: app, id: "mail.message.hide").exists)
    }

    func testAccessFoldersCanShareMixedScopeWithBothAgents() {
        let app = launchFixture(profile: "tracked-work")

        openSidebarDestination("ledger.sidebar.access", expectedSurface: "ledger.surface.access", in: app)

        let bothControl = element(in: app, id: "access.folder.src-claude.all")
        XCTAssertTrue(bothControl.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForValue("partially shared", in: bothControl, timeout: 5))

        bothControl.click()

        XCTAssertTrue(waitForValue("shared", in: bothControl, timeout: 5))
        XCTAssertTrue(waitForValue("shared", in: element(in: app, id: "access.folder.src-claude.agent.cowork"), timeout: 5))
        XCTAssertTrue(waitForValue("shared", in: element(in: app, id: "access.folder.src-claude.agent.codex"), timeout: 5))
    }

    func testAccessFilesCanToggleSingleFileForBothAgents() {
        let app = launchFixture(profile: "tracked-work")

        openSidebarDestination("ledger.sidebar.access", expectedSurface: "ledger.surface.access", in: app)
        clickElement(in: app, id: "access.tab.files", fallbackButtonTitle: "Files")

        let bothControl = element(in: app, id: "access.file.src-claude.marker-txt.all")
        XCTAssertTrue(bothControl.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForValue("partially shared", in: bothControl, timeout: 5))

        bothControl.click()

        XCTAssertTrue(waitForValue("shared", elementID: "access.file.src-claude.marker-txt.all", in: app, timeout: 5))
        XCTAssertTrue(waitForValue("shared", in: element(in: app, id: "access.file.src-claude.marker-txt.agent.codex"), timeout: 5))
    }

    func testRequestsQueueCanResolveFixtureApproval() {
        let app = launchFixture(profile: "tracked-work")

        openSidebarDestination("ledger.sidebar.requests", expectedSurface: "ledger.surface.requests", in: app)

        let requestCard = element(in: app, id: "requests.card.approval-1")
        XCTAssertTrue(requestCard.waitForExistence(timeout: 8))
        XCTAssertTrue(
            element(in: app, id: "requests.action.notThisTime").waitForExistence(timeout: 5) ||
            app.buttons["Not this time"].waitForExistence(timeout: 2)
        )

        clickElement(in: app, id: "requests.action.notThisTime", fallbackButtonTitle: "Not this time")
        XCTAssertTrue(waitForNonExistence(requestCard, timeout: 8))
    }

    func testCommandPaletteOpensAndAcceptsSearchInput() {
        let app = launchFixture(profile: "tracked-work")

        XCTAssertTrue(element(in: app, id: "ledger.surface.activity").waitForExistence(timeout: 8))
        app.typeKey("k", modifierFlags: .command)

        let palette = element(in: app, id: "commandPalette.sheet")
        XCTAssertTrue(palette.waitForExistence(timeout: 8))

        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("settings")

        XCTAssertTrue(waitForValue("settings", in: searchField, timeout: 5))
    }

    func testPrivacySettingsFixtureShowsPaneAndIndexStatus() {
        let app = launchFixture(profile: "privacy")

        XCTAssertTrue(element(in: app, id: "ledger.surface.activity").waitForExistence(timeout: 8))
        openSettings(in: app)

        clickSettingsTab("Privacy", contentID: "settings.privacy.model.enabled", in: app)

        XCTAssertTrue(element(in: app, id: "settings.privacy.model.enabled").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.model.enabled").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.preset.custom").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.suggestion.suggestion-primary-name").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, id: "settings.privacy.index.stat.indexed").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.index.stat.failed").exists)
    }

    func testPrivacyActivityEvidenceRendersCurrentInspector() {
        let app = launchFixture(profile: "privacy")

        XCTAssertTrue(element(in: app, id: "ledger.surface.activity").waitForExistence(timeout: 8))
        clickElement(in: app, id: "activity.filter.privacy", fallbackButtonTitle: "Privacy")

        let privacyRow = element(in: app, id: "activity.event.3")
        XCTAssertTrue(privacyRow.waitForExistence(timeout: 8))
        privacyRow.click()

        XCTAssertTrue(element(in: app, id: "activity.evidence.privacy").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, id: "activity.evidence.privacy.summary").exists)
        XCTAssertTrue(element(in: app, id: "activity.evidence.privacy.categories").exists)
    }

    func testRulesFixtureSupportsSearchInspectorAndEmptySuggestedState() {
        let app = launchFixture(profile: "privacy")

        openSidebarDestination("ledger.sidebar.rules", expectedSurface: "ledger.surface.rules", in: app)

        let searchField = elementOrTextField(in: app, id: "rules.toolbar.search", fallbackPlaceholder: "Search rules")
        clearAndType(searchField, text: "OpenAI")
        XCTAssertTrue(app.staticTexts["Allow OpenAI mail"].waitForExistence(timeout: 5))
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

        openSidebarDestination("ledger.sidebar.rules", expectedSurface: "ledger.surface.rules", in: app)

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
final class ManifoldRuntimeE2ETests: ManifoldUITestCase {
    func testLocalRuntimeScenarioBootsAndShowsPrivacyRequest() {
        let app = launchLocalRuntime()

        XCTAssertTrue(element(in: app, id: "ledger.surface.activity").waitForExistence(timeout: 15))
        openSidebarDestination("ledger.sidebar.requests", expectedSurface: "ledger.surface.requests", in: app, timeout: 15)

        let requestCard = element(in: app, id: "requests.card.approval-runtime-privacy")
        XCTAssertTrue(requestCard.waitForExistence(timeout: 15))
        XCTAssertTrue(element(in: app, id: "requests.action.shareRedacted").exists)
        XCTAssertTrue(element(in: app, id: "requests.action.shareOriginalOnce").exists)

        element(in: app, id: "requests.action.shareRedacted").click()
        XCTAssertTrue(waitForNonExistence(requestCard, timeout: 15))
    }

    func testLocalRuntimeMailAndActivityReflectSeededRuntimeData() {
        let app = launchLocalRuntime()

        XCTAssertTrue(element(in: app, id: "ledger.surface.activity").waitForExistence(timeout: 15))
        openSidebarDestination("ledger.sidebar.mail", expectedSurface: "ledger.surface.mail", in: app, timeout: 15)

        XCTAssertTrue(element(in: app, id: "mail.review.table").waitForExistence(timeout: 15))
        let subject = app.staticTexts["Privacy review needed"]
        XCTAssertTrue(subject.waitForExistence(timeout: 15))
        subject.click()

        XCTAssertTrue(element(in: app, id: "mail.message.inspector.visibility.runtime-email-1").waitForExistence(timeout: 8))

        openSidebarDestination("ledger.sidebar.activity", expectedSurface: "ledger.surface.activity", in: app, timeout: 15)
        element(in: app, id: "activity.filter.privacy").click()

        let target = element(in: app, id: "activity.event.3")
        XCTAssertTrue(target.waitForExistence(timeout: 15))
        target.click()

        XCTAssertTrue(element(in: app, id: "activity.evidence.privacy").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, id: "activity.evidence.privacy.summary").exists)
    }

    func testLocalRuntimeSettingsPrivacyPaneShowsDiscoveryData() {
        let app = launchLocalRuntime()

        XCTAssertTrue(element(in: app, id: "ledger.surface.activity").waitForExistence(timeout: 15))
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
