// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
import ManifoldKit
@testable import Manifold

@MainActor
final class DiagnosticsModelTests: XCTestCase {

    private var tempDefaults: UserDefaults!
    private var tempDir: URL!
    private var recorder: DiagnosticsRecorder!

    // Async variants run on the @MainActor-inherited isolation of this
    // class, so mutating @MainActor-isolated stored properties is safe.
    // The sync overrides land on a nonisolated XCTest queue and trip
    // Swift 6 strict-concurrency warnings.
    override func setUp() async throws {
        try await super.setUp()
        let suiteName = "com.spatialduality.manifold.diagnostics-test.\(UUID().uuidString)"
        tempDefaults = UserDefaults(suiteName: suiteName)!
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-diag-model-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        recorder = DiagnosticsRecorder(process: .app, directory: tempDir, launchUUID: "test-launch")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        for key in tempDefaults.dictionaryRepresentation().keys {
            tempDefaults.removeObject(forKey: key)
        }
        try await super.tearDown()
    }

    private func makeModel(endpoint: URL? = nil) -> DiagnosticsModel {
        DiagnosticsModel(defaults: tempDefaults, recorder: recorder, endpoint: endpoint)
    }

    func testInstallIDIsNilUntilSharingIsEnabled() {
        let model = makeModel()
        XCTAssertNil(model.installID, "Install ID must not exist before consent")
        XCTAssertFalse(model.diagnosticSharingEnabled)
    }

    func testEnablingSharingCreatesInstallID() {
        let model = makeModel()
        model.diagnosticSharingEnabled = true
        XCTAssertNotNil(model.installID)
        XCTAssertEqual(model.installID, tempDefaults.string(forKey: "manifold.diagnostics.installID"))
    }

    func testDisablingSharingClearsInstallID() {
        let model = makeModel()
        model.diagnosticSharingEnabled = true
        XCTAssertNotNil(model.installID)
        model.diagnosticSharingEnabled = false
        XCTAssertNil(model.installID)
        XCTAssertNil(tempDefaults.string(forKey: "manifold.diagnostics.installID"))
    }

    func testResetInstallIDRotatesValueWhenConsentOn() {
        let model = makeModel()
        model.diagnosticSharingEnabled = true
        let original = model.installID
        model.resetInstallID()
        XCTAssertNotNil(model.installID)
        XCTAssertNotEqual(model.installID, original)
    }

    func testResetInstallIDLeavesNilWhenConsentOff() {
        let model = makeModel()
        XCTAssertNil(model.installID)
        model.resetInstallID()
        XCTAssertNil(model.installID)
    }

    func testReportOmitsInstallIDWhenSharingDisabled() throws {
        let model = makeModel()
        model.record(.appLaunch)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // Allow recorder queue to drain.
        let exp = expectation(description: "drain")
        DispatchQueue.global().async { Thread.sleep(forTimeInterval: 0.15); exp.fulfill() }
        wait(for: [exp], timeout: 1)

        let report = model.buildReport()
        XCTAssertNil(report.installID)
        XCTAssertFalse(report.consent.diagnosticSharingEnabled)
    }

    func testReportIncludesInstallIDWhenSharingEnabled() throws {
        let model = makeModel()
        model.diagnosticSharingEnabled = true
        let id = model.installID
        let report = model.buildReport()
        XCTAssertNotNil(report.installID)
        XCTAssertEqual(report.installID, id)
        XCTAssertTrue(report.consent.diagnosticSharingEnabled)
    }

    func testCanSendReportsFalseWithoutEndpoint() {
        let model = makeModel(endpoint: nil)
        XCTAssertFalse(model.canSendReports)
    }

    func testCanSendReportsFalseEvenWithEndpointInExportOnlyV1() {
        let model = makeModel(endpoint: URL(string: "https://telemetry.spatialduality.com/v1/reports"))
        XCTAssertFalse(model.canSendReports)
    }

    func testReportPreviewJSONExcludesForbiddenKeys() throws {
        let model = makeModel()
        model.diagnosticSharingEnabled = true
        model.record(.runtimeRegistrationFailedHelperMissing)
        let exp = expectation(description: "drain")
        DispatchQueue.global().async { Thread.sleep(forTimeInterval: 0.15); exp.fulfill() }
        wait(for: [exp], timeout: 1)

        let json = model.reportPreviewJSON()
        for forbidden in DiagnosticReportV1.forbiddenKeys {
            XCTAssertFalse(
                json.contains("\"\(forbidden)\""),
                "Report preview leaked forbidden key: \(forbidden)"
            )
        }
    }

    func testReportRollsUpOnboardingAndPrivacyInstallEvents() throws {
        let model = makeModel()
        model.record(.onboardingCompleted)
        model.record(.privacyModelInstallStateChanged(.installing))
        model.record(.privacyModelInstallStateChanged(.installed))

        let exp = expectation(description: "drain")
        DispatchQueue.global().async { Thread.sleep(forTimeInterval: 0.15); exp.fulfill() }
        wait(for: [exp], timeout: 1)

        let report = model.buildReport()
        XCTAssertTrue(report.rollups.contains {
            $0.process == .app && $0.name == "onboardingCompleted" && $0.count == 1
        })
        XCTAssertTrue(report.rollups.contains {
            $0.process == .app && $0.name == "privacyModelInstallStateChanged" && $0.count == 2
        })
    }

    func testCheckAgentExitStateRecordsUnexpectedExitOnce() throws {
        // Seed an agent state marker that says "running" — i.e. the previous
        // agent run never recorded a clean shutdown.
        let agent = DiagnosticsRecorder(process: .agent, directory: tempDir, launchUUID: "agent-1")
        agent.recordAgentBoot()

        let model = makeModel()
        model.checkAgentExitState()

        let exp = expectation(description: "drain")
        DispatchQueue.global().async { Thread.sleep(forTimeInterval: 0.15); exp.fulfill() }
        wait(for: [exp], timeout: 1)

        let firstRead = recorder.readAllRecords()
        XCTAssertTrue(firstRead.contains { $0.name == "runtimeUnexpectedExit" })

        // Calling again with the same marker must NOT record a duplicate.
        model.checkAgentExitState()
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("app-test-launch.jsonl"))
        let agentRerun = DiagnosticsRecorder(process: .app, directory: tempDir, launchUUID: "test-rerun")
        let model2 = DiagnosticsModel(defaults: tempDefaults, recorder: agentRerun, endpoint: nil)
        model2.checkAgentExitState()
        let exp2 = expectation(description: "drain2")
        DispatchQueue.global().async { Thread.sleep(forTimeInterval: 0.15); exp2.fulfill() }
        wait(for: [exp2], timeout: 1)

        let secondRead = agentRerun.readAllRecords()
        XCTAssertFalse(
            secondRead.contains { $0.name == "runtimeUnexpectedExit" },
            "Same agent-state marker must not produce duplicate unexpected-exit events"
        )
    }
}
