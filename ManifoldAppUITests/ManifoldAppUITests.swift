// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest

@MainActor
final class ManifoldAppUITests: XCTestCase {
    private let bundleIdentifier = "com.spatialduality.manifold"

    override func setUpWithError() throws {
        continueAfterFailure = false
        let existingApp = XCUIApplication(bundleIdentifier: bundleIdentifier)
        if existingApp.state != .notRunning {
            existingApp.terminate()
        }
    }

    func testOnboardingFixtureSupportsSkippablePrimerIntoLedger() {
        let app = launch(profile: "onboarding")

        XCTAssertTrue(app.staticTexts["Protect your next AI session"].waitForExistence(timeout: 5))

        app.buttons["Continue"].click()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))

        app.buttons["Continue"].click()
        XCTAssertTrue(app.buttons["Choose folder…"].waitForExistence(timeout: 5))

        app.buttons["Skip setup"].click()
        XCTAssertTrue(element(in: app, id: "ledger.surface.activity").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, id: "ledger.sidebar.activity").exists)
    }

    func testTrackedWorkFixtureShowsSidebarAndLiveSession() {
        let app = launch(profile: "tracked-work")

        XCTAssertTrue(element(in: app, id: "ledger.sidebar").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, id: "ledger.surface.activity").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, id: "ledger.sidebar.session").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, id: "ledger.sidebar.requests").exists)
    }

    func testSidebarNavigationShowsUpdatedLedgerSurfaces() {
        let app = launch(profile: "tracked-work")

        XCTAssertTrue(element(in: app, id: "ledger.surface.activity").waitForExistence(timeout: 8))

        element(in: app, id: "ledger.sidebar.access").click()
        XCTAssertTrue(element(in: app, id: "ledger.surface.access").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Folders"].exists)

        element(in: app, id: "ledger.sidebar.mail").click()
        XCTAssertTrue(element(in: app, id: "mail.tab.review").waitForExistence(timeout: 8))

        element(in: app, id: "ledger.sidebar.requests").click()
        XCTAssertTrue(element(in: app, id: "requests.card.approval-1").waitForExistence(timeout: 8))
        XCTAssertFalse(element(in: app, id: "ledger.sidebar.rules").exists)
    }

    func testMailReviewSurfaceLoadsFixtureMessagesAndSelectsAtomicMessage() {
        let app = launch(profile: "tracked-work")

        element(in: app, id: "ledger.sidebar.mail").click()

        let reviewTab = element(in: app, id: "mail.tab.review")
        XCTAssertTrue(reviewTab.waitForExistence(timeout: 5))
        reviewTab.click()

        let subject = app.staticTexts["Board deck v2"]
        XCTAssertTrue(subject.waitForExistence(timeout: 8))
        subject.click()

        XCTAssertTrue(element(in: app, id: "mail.message.inspector.visibility.email-1").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, id: "mail.message.allow").exists)
        XCTAssertTrue(element(in: app, id: "mail.message.hide").exists)
    }

    func testMailReviewSurfaceCanFilterMailboxAndInspectMessage() {
        let app = launch(profile: "tracked-work")

        element(in: app, id: "ledger.sidebar.mail").click()

        let inboxRow = element(in: app, id: "mail.mailbox.account-1.INBOX")
        XCTAssertTrue(inboxRow.waitForExistence(timeout: 8))
        inboxRow.click()

        XCTAssertTrue(element(in: app, id: "mail.review.table").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Board deck v2"].waitForExistence(timeout: 8))

        app.staticTexts["Board deck v2"].click()
        XCTAssertTrue(element(in: app, id: "mail.message.inspector.visibility.email-1").waitForExistence(timeout: 5))
    }

    func testRequestsQueueCanResolveFixtureApproval() {
        let app = launch(profile: "tracked-work")

        element(in: app, id: "ledger.sidebar.requests").click()

        let requestCard = element(in: app, id: "requests.card.approval-1")
        XCTAssertTrue(requestCard.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["For this session"].exists)
        XCTAssertTrue(app.buttons["Add to default"].waitForExistence(timeout: 5))

        app.buttons["Not this time"].click()
        XCTAssertTrue(waitForNonExistence(requestCard, timeout: 8))
    }

    func testCommandPaletteOpensAndAcceptsSearchInput() {
        let app = launch(profile: "tracked-work")

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

    func testPreviewRulesSurfaceCanOpenFromSettings() {
        let app = launch(profile: "tracked-work")

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Preview"].waitForExistence(timeout: 5))
        app.buttons["Preview"].click()

        let surface = element(in: app, id: "ledger.surface.rules")
        XCTAssertTrue(surface.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Preview surface"].exists)

        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["Rule preview · Files"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save preview"].exists)
    }

    @discardableResult
    private func launch(profile: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["MANIFOLD_UI_TEST_MODE"] = "1"
        app.launchEnvironment["MANIFOLD_DISABLE_REAL_RUNTIME"] = "1"
        app.launchEnvironment["MANIFOLD_FIXTURE_PROFILE"] = profile
        app.launch()
        return app
    }

    private func element(in app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func waitForValue(_ value: String, in element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
