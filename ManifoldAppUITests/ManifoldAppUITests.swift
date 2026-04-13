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

    func testOnboardingFixtureShowsWelcomeFlow() {
        let app = launch(profile: "onboarding")

        XCTAssertTrue(element(in: app, id: "setup.assistant").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Manifold controls what AI agents see on your Mac."].waitForExistence(timeout: 5))
        XCTAssertTrue(control(named: "Continue", in: app).waitForExistence(timeout: 5))
    }

    func testDashboardFixtureShowsAgentCardsAndTrackedWorkCTA() {
        let app = launch(profile: "dashboard")

        XCTAssertTrue(element(in: app, id: "agentCard.claude.reviewAccess").waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, id: "agentCard.codex.reviewAccess").exists)
        XCTAssertTrue(element(in: app, id: "agentCard.claude.pauseToggle").exists)
        XCTAssertTrue(element(in: app, id: "overview.startTrackedWorkBlock").exists)
    }

    func testReviewAccessEmailTabDeepLinksIntoEmailRules() {
        let app = launch(profile: "dashboard")

        let reviewButton = element(in: app, id: "agentCard.claude.reviewAccess")
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 8))
        reviewButton.click()

        let sheet = element(in: app, id: "reviewAccess.sheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        let emailTab = control(named: "Emails", in: sheet)
        XCTAssertTrue(emailTab.waitForExistence(timeout: 5))
        emailTab.click()
        let openEmailRules = element(in: app, id: "reviewAccess.openEmailRules")
        XCTAssertTrue(openEmailRules.waitForExistence(timeout: 5))
        openEmailRules.click()

        XCTAssertTrue(app.staticTexts["Email Policy"].waitForExistence(timeout: 8))
    }

    func testEmailRulesFixtureShowsPolicyControls() {
        let app = launch(profile: "email-rules")

        XCTAssertTrue(element(in: app, id: "emailRules.sidebar").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Email Policy"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Claude Sensitivity"].waitForExistence(timeout: 5))
        XCTAssertTrue(control(named: "Moderate", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(control(named: "Allow unless blocked", in: app).waitForExistence(timeout: 5))
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

    private func control(named label: String, in container: XCUIElement) -> XCUIElement {
        let radioButton = container.radioButtons[label]
        if radioButton.exists {
            return radioButton
        }

        let button = container.buttons[label]
        if button.exists {
            return button
        }

        return container.descendants(matching: .any)[label]
    }
}
