// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import AppKit
import XCTest

@MainActor
class ManifoldUITestCase: XCTestCase {
    private(set) var currentTestHome: String?

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
        currentTestHome = testHome
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
        app.launchEnvironment["MANIFOLD_TEST_PROTECTED_STORAGE_KEY"] = testHome
        app.launchEnvironment["MANIFOLD_TEST_ALLOW_UI_RUNNER_MCP"] = "1"
        currentTestHome = testHome
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

    func firstElement(in app: XCUIApplication, matchingIdentifier predicate: NSPredicate) -> XCUIElement {
        app.descendants(matching: .any).matching(predicate).firstMatch
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

    func waitForLabelContaining(_ text: String, in element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
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

struct MCPToolResult {
    let text: String
    let isError: Bool
}

final class MCPStdioClient: @unchecked Sendable {
    private let process: Process
    private let input: FileHandle
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let responseSemaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var pendingLines: [[String: Any]] = []
    private var buffer = Data()
    private var nextID = 1
    private var stderrBuffer = Data()

    init(agent: String, testHome: String) throws {
        let mcpURL = Self.bundledMCPURL()
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: mcpURL.path), "Expected bundled manifold-mcp at \(mcpURL.path)")

        let inputPipe = Pipe()
        process = Process()
        process.executableURL = mcpURL
        process.arguments = ["--agent", agent]
        var environment = ProcessInfo.processInfo.environment
        environment["MANIFOLD_TEST_HOME"] = testHome
        environment["MANIFOLD_TEST_SCENARIO"] = "synthetic-mcp-ui"
        environment["MANIFOLD_TEST_PROTECTED_STORAGE_KEY"] = testHome
        environment["MANIFOLD_TEST_ALLOW_UI_RUNNER_MCP"] = "1"
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        input = inputPipe.fileHandleForWriting

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consumeOutput(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consumeError(handle.availableData)
        }

        try process.run()
        _ = try request(
            method: "initialize",
            params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [:] as [String: Any],
                "clientInfo": ["name": "ManifoldAppUITests", "version": "1"] as [String: Any],
            ],
            timeout: 20
        )
        sendNotification(method: "notifications/initialized")
    }

    deinit {
        close()
    }

    func close() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        try? input.close()
        if process.isRunning {
            process.terminate()
        }
    }

    func callTool(_ name: String, arguments: [String: Any] = [:], timeout: TimeInterval = 20) throws -> MCPToolResult {
        let deadline = Date().addingTimeInterval(timeout)
        var lastResult: MCPToolResult?
        repeat {
            let response = try request(
                method: "tools/call",
                params: ["name": name, "arguments": arguments],
                timeout: max(1, deadline.timeIntervalSinceNow)
            )
            let result = try Self.toolResult(from: response)
            if !result.text.contains("Runtime connection not initialized") {
                return result
            }
            lastResult = result
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return lastResult ?? MCPToolResult(text: "No MCP response before timeout", isError: true)
    }

    private func request(method: String, params: [String: Any], timeout: TimeInterval) throws -> [String: Any] {
        let id = nextID
        nextID += 1
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        try write(payload)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            if responseSemaphore.wait(timeout: .now() + min(remaining, 0.5)) == .success {
                lock.lock()
                if let index = pendingLines.firstIndex(where: { ($0["id"] as? Int) == id }) {
                    let response = pendingLines.remove(at: index)
                    lock.unlock()
                    if let error = response["error"] as? [String: Any] {
                        throw NSError(
                            domain: "MCPStdioClient",
                            code: error["code"] as? Int ?? -1,
                            userInfo: [NSLocalizedDescriptionKey: error["message"] as? String ?? "MCP JSON-RPC error"]
                        )
                    }
                    return response
                }
                lock.unlock()
            }
        }

        throw NSError(
            domain: "MCPStdioClient",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(method). stderr: \(stderrText)"]
        )
    }

    private func sendNotification(method: String) {
        try? write(["jsonrpc": "2.0", "method": method, "params": [:] as [String: Any]])
    }

    private func write(_ payload: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(UInt8(ascii: "\n"))
        input.write(data)
    }

    private func consumeOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                continue
            }
            pendingLines.append(json)
            responseSemaphore.signal()
        }
        lock.unlock()
    }

    private func consumeError(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        stderrBuffer.append(data)
        lock.unlock()
    }

    private var stderrText: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: stderrBuffer, encoding: .utf8) ?? ""
    }

    private static func toolResult(from response: [String: Any]) throws -> MCPToolResult {
        guard let result = response["result"] as? [String: Any] else {
            throw NSError(domain: "MCPStdioClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing MCP result"])
        }
        let content = result["content"] as? [[String: Any]] ?? []
        let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return MCPToolResult(text: text, isError: result["isError"] as? Bool ?? false)
    }

    private static func bundledMCPURL() -> URL {
        let testBundleURL = Bundle(for: MCPStdioClient.self).bundleURL
        let productsURL = testBundleURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // ManifoldAppUITests-Runner.app
            .deletingLastPathComponent() // Debug
        return productsURL
            .appendingPathComponent("Manifold.app", isDirectory: true)
            .appendingPathComponent("Contents/Resources/manifold-mcp", isDirectory: false)
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

    func testAccessFoldersCanSetMixedScopeForBothAgents() {
        let app = launchFixture(profile: "tracked-work")

        openLedgerSpace("access", expectedSurface: "ledger.surface.access", in: app)

        let bothControl = element(in: app, id: "access.folder.src-claude.all")
        XCTAssertTrue(bothControl.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForValue("partially shared", in: bothControl, timeout: 5))

        bothControl.click()

        XCTAssertTrue(waitForValue("shared", in: bothControl, timeout: 5))
        XCTAssertTrue(waitForValue("shared", in: element(in: app, id: "access.folder.src-claude.agent.cowork"), timeout: 5))
        XCTAssertTrue(waitForValue("shared", in: element(in: app, id: "access.folder.src-claude.agent.codex"), timeout: 5))
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
        XCTAssertTrue(waitForValue("not shared", in: codexControl, timeout: 5))

        codexControl.click()

        XCTAssertTrue(waitForValue("shared", elementID: "access.inspector.file.src-claude.marker-txt.agent.codex", in: app, timeout: 5))
    }

    func testApprovalsQueueCanResolveFixtureApproval() {
        let app = launchFixture(profile: "tracked-work")

        openLedgerSpace("work", expectedSurface: "ledger.surface.work", in: app)

        let approvalRow = element(in: app, id: "work.approval.approval-1")
        XCTAssertTrue(approvalRow.waitForExistence(timeout: 8))
        clickElement(in: app, id: "work.approval.approval-1.deny", fallbackButtonTitle: "Deny")
        XCTAssertTrue(waitForNonExistence(approvalRow, timeout: 8))
    }

    func testPrivacySettingsFixtureShowsPaneAndIndexStatus() {
        let app = launchFixture(profile: "privacy")

        XCTAssertTrue(element(in: app, id: "ledger.surface.work").waitForExistence(timeout: 8))
        openSettings(in: app)

        clickSettingsTab("Privacy", contentID: "settings.privacy.model.enabled", in: app)

        XCTAssertTrue(element(in: app, id: "settings.privacy.model.enabled").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.model.enabled").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.preset.picker").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.openRules").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.suggestion.suggestion-primary-name").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, id: "settings.privacy.index.stat.indexed").exists)
        XCTAssertTrue(element(in: app, id: "settings.privacy.index.stat.failed").exists)
    }

    func testPrivacySettingsProtectionLevelPickerAppliesFixtureChanges() {
        let app = launchFixture(profile: "privacy")

        XCTAssertTrue(element(in: app, id: "ledger.surface.work").waitForExistence(timeout: 8))
        openSettings(in: app)
        clickSettingsTab("Privacy", contentID: "settings.privacy.model.enabled", in: app)

        let picker = element(in: app, id: "settings.privacy.preset.picker")
        let description = element(in: app, id: "settings.privacy.preset.description")
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(description.waitForExistence(timeout: 5))

        clickProtectionLevel("Strict", picker: picker, app: app)
        XCTAssertTrue(waitForLabelContaining("Redacts personal information", in: description, timeout: 5))

        clickProtectionLevel("Custom", picker: picker, app: app)
        XCTAssertTrue(waitForLabelContaining("Uses your current agent privacy settings", in: description, timeout: 5))

        clickProtectionLevel("Off", picker: picker, app: app)
        XCTAssertTrue(waitForLabelContaining("The OpenAI Privacy Filter is off", in: description, timeout: 5))
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

    func testRulesFixtureSupportsSearchInspectorAndEmptySuggestedRulesState() {
        let app = launchFixture(profile: "privacy")

        openLedgerSpace("rules", expectedSurface: "ledger.surface.rules", in: app)

        let openAIRule = element(in: app, id: "rules.rowTitle.rule-email-openai")
        XCTAssertTrue(openAIRule.waitForExistence(timeout: 5))
        openAIRule.click()

        XCTAssertTrue(element(in: app, id: "rules.inspector.name").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, id: "rules.inspector.action").exists)

        element(in: app, id: "rules.sidebar.seeded").click()
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

        element(in: app, id: "rules.sidebar.seeded").click()
        XCTAssertTrue(app.staticTexts["Protect Secrets"].waitForExistence(timeout: 5))
    }

    private func clickProtectionLevel(_ title: String, picker: XCUIElement, app: XCUIApplication) {
        let segment = picker.descendants(matching: .any)[title]
        if segment.waitForExistence(timeout: 2) {
            app.activate()
            segment.click()
            return
        }

        let fallback = app.descendants(matching: .any)[title]
        XCTAssertTrue(fallback.waitForExistence(timeout: 5), "Expected Protection Level segment \(title)")
        app.activate()
        fallback.click()
    }
}

@MainActor
final class ManifoldSharingMCPUITests: ManifoldUITestCase {
    func testUISharingControlsMatchMCPAgentVisibility() throws {
        let app = launchSyntheticMCPUI()
        XCTAssertTrue(element(in: app, id: "ledger.surface.work").waitForExistence(timeout: 30))

        let testHome = try XCTUnwrap(currentTestHome)
        let codex = try MCPStdioClient(agent: "codex", testHome: testHome)
        let claude = try MCPStdioClient(agent: "cowork", testHome: testHome)
        addTeardownBlock {
            codex.close()
            claude.close()
        }

        openLedgerSpace("access", expectedSurface: "ledger.surface.access", in: app, timeout: 30)

        let claudeFolder = firstElement(
            in: app,
            matchingIdentifier: NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "access.folder.", ".agent.cowork")
        )
        XCTAssertTrue(claudeFolder.waitForExistence(timeout: 30))
        XCTAssertTrue(waitForValue("shared", in: claudeFolder, timeout: 10))
        claudeFolder.click()
        XCTAssertTrue(waitForValue("not shared", in: claudeFolder, timeout: 10))

        let bothFolder = firstElement(
            in: app,
            matchingIdentifier: NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "access.folder.", ".all")
        )
        XCTAssertTrue(waitForValue("partially shared", in: bothFolder, timeout: 10))

        let codexStatus = try codex.callTool("get_status")
        XCTAssertFalse(codexStatus.isError, codexStatus.text)

        let codexFiles = try codex.callTool("list_files")
        XCTAssertFalse(codexFiles.isError, codexFiles.text)
        XCTAssertTrue(codexFiles.text.contains("Docs/ReleaseNotes.md"), codexFiles.text)

        let codexRead = try codex.callTool("read_file", arguments: ["path": "Docs/ReleaseNotes.md"])
        XCTAssertFalse(codexRead.isError, codexRead.text)
        XCTAssertTrue(codexRead.text.contains("Team notes"), codexRead.text)

        let claudeFiles = try claude.callTool("list_files")
        XCTAssertTrue(claudeFiles.isError || !claudeFiles.text.contains("Docs/ReleaseNotes.md"), claudeFiles.text)

        let claudeRead = try claude.callTool("read_file", arguments: ["path": "Docs/ReleaseNotes.md"])
        XCTAssertTrue(claudeRead.isError || !claudeRead.text.contains("Team notes"), claudeRead.text)

        let claudeSearch = try claude.callTool("search_files", arguments: ["query": "Team notes"])
        XCTAssertFalse(claudeSearch.text.contains("Team notes"), claudeSearch.text)

        let claudeStructured = try claude.callTool("search_structured", arguments: ["query": "Team notes", "limit": 5])
        XCTAssertFalse(claudeStructured.text.contains("Team notes"), claudeStructured.text)

        openLedgerSpace("mail", expectedSurface: "ledger.surface.mail", in: app, timeout: 30)
        XCTAssertTrue(element(in: app, id: "mail.review.table").waitForExistence(timeout: 30))

        let codexOnlyMessage = element(in: app, id: "mail.message.row.runtime-email-codex-semicolon")
        XCTAssertTrue(codexOnlyMessage.waitForExistence(timeout: 30))
        codexOnlyMessage.click()

        let mailBoth = element(in: app, id: "mail.message.share.all")
        let mailClaude = element(in: app, id: "mail.message.share.agent.cowork")
        let mailCodex = element(in: app, id: "mail.message.share.agent.codex")
        XCTAssertTrue(mailBoth.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForValue("partially shared", in: mailBoth, timeout: 10))
        XCTAssertTrue(waitForValue("not shared", in: mailClaude, timeout: 10))
        XCTAssertTrue(waitForValue("shared", in: mailCodex, timeout: 10))

        let claudeEmailBefore = try claude.callTool("list_emails")
        XCTAssertFalse(claudeEmailBefore.text.contains("runtime-email-codex-semicolon"), claudeEmailBefore.text)

        mailBoth.click()
        XCTAssertTrue(waitForValue("shared", in: mailBoth, timeout: 10))
        XCTAssertTrue(waitForValue("shared", in: mailClaude, timeout: 10))
        XCTAssertTrue(waitForValue("shared", in: mailCodex, timeout: 10))

        codex.close()
        claude.close()
        let codexAfterMailShare = try MCPStdioClient(agent: "codex", testHome: testHome)
        let claudeAfterMailShare = try MCPStdioClient(agent: "cowork", testHome: testHome)
        addTeardownBlock {
            codexAfterMailShare.close()
            claudeAfterMailShare.close()
        }

        let codexEmails = try waitForMCPTool(codexAfterMailShare, "list_emails") {
            !$0.isError && $0.text.contains("runtime-email-codex-semicolon")
        }
        XCTAssertTrue(codexEmails.text.contains("runtime-email-codex-semicolon"), codexEmails.text)

        let claudeEmails = try waitForMCPTool(claudeAfterMailShare, "list_emails") {
            !$0.isError && $0.text.contains("runtime-email-codex-semicolon")
        }
        XCTAssertTrue(claudeEmails.text.contains("runtime-email-codex-semicolon"), claudeEmails.text)

        let claudeReadEmail = try claudeAfterMailShare.callTool("read_email", arguments: ["id": "runtime-email-codex-semicolon"])
        XCTAssertFalse(claudeReadEmail.isError, claudeReadEmail.text)
        XCTAssertTrue(claudeReadEmail.text.contains("EASTER_EGG_SEMICOLON_ALLOWED"), claudeReadEmail.text)

        let claudeEmailSearch = try claudeAfterMailShare.callTool("search_emails", arguments: ["query": "missing semicolon"])
        XCTAssertFalse(claudeEmailSearch.isError, claudeEmailSearch.text)
        XCTAssertTrue(claudeEmailSearch.text.contains("runtime-email-codex-semicolon"), claudeEmailSearch.text)

        let historySection = element(in: app, id: "mail.section.history")
        XCTAssertTrue(historySection.waitForExistence(timeout: 10))
        historySection.click()
        XCTAssertTrue(element(in: app, id: "mail.history").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Codex found the missing semicolon"].waitForExistence(timeout: 10))
    }

    private func waitForMCPTool(
        _ client: MCPStdioClient,
        _ name: String,
        arguments: [String: Any] = [:],
        timeout: TimeInterval = 10,
        until predicate: (MCPToolResult) -> Bool
    ) throws -> MCPToolResult {
        let deadline = Date().addingTimeInterval(timeout)
        var last = try client.callTool(name, arguments: arguments)
        while !predicate(last), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            last = try client.callTool(name, arguments: arguments)
        }
        return last
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
