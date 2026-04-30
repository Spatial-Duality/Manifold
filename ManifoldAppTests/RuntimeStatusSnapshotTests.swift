// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
import ManifoldKit
@testable import Manifold

final class RuntimeStatusSnapshotTests: XCTestCase {
    func testFixtureDataControlSummaryCarriesPerAgentTruth() async throws {
        let client = FixtureRuntimeClient(profile: .baseline)
        let summary = try await client.dataControlSummary()

        XCTAssertTrue(summary.runtimeConnected)
        XCTAssertEqual(summary.agents.count, 2)
        let claude = try XCTUnwrap(summary.agents.first { $0.agent == .cowork })
        let codex = try XCTUnwrap(summary.agents.first { $0.agent == .codex })
        XCTAssertEqual(claude.defaultFileScopeCount, 2)
        XCTAssertEqual(codex.defaultFileScopeCount, 1)
        XCTAssertEqual(claude.sharedEmailCount, 1)
        XCTAssertEqual(codex.sharedEmailCount, 1)
        XCTAssertTrue(claude.visibleEmailCount >= codex.visibleEmailCount)
    }

    func testFixtureDefaultTrackedRunUsesTargetAgentPolicy() async throws {
        let client = FixtureRuntimeClient(profile: .baseline)
        let state = try await client.startGatewaySession(
            targetApp: .codex,
            fileScopes: [],
            selectedEmailIDs: [],
            summaryFraming: "Codex scoped work",
            noteCaptureMode: .basic,
            requestDetailLevel: nil,
            memoryAccessEnabled: false,
            emailSensitivity: nil
        )

        XCTAssertEqual(state.targetApp, TargetApp.codex.rawValue)
        XCTAssertEqual(Set(state.activeGrantSources.map { $0.sourceID }), Set(["src-shared"]))
        XCTAssertFalse(state.activeGrantSources.contains { $0.sourceID == "src-claude" })
    }

    func testFixtureRuntimeStatusSnapshotCarriesCurrentShape() async throws {
        let client = FixtureRuntimeClient(profile: .baseline)
        let snapshot = try await client.runtimeStatusSnapshot()

        XCTAssertTrue(snapshot.runtimeConnected)
        XCTAssertEqual(snapshot.activeBridgeCount, 2)
        XCTAssertEqual(Set(snapshot.connectedAgents), Set([TargetApp.cowork.rawValue, TargetApp.codex.rawValue]))
        XCTAssertEqual(Set(snapshot.sources.map { $0.sourceID }), Set(["src-shared", "src-claude"]))
        XCTAssertEqual(snapshot.claudeEmailGovernance.domainRuleCount, 1)
        XCTAssertEqual(snapshot.codexEmailGovernance.domainRuleCount, 1)
    }
}
