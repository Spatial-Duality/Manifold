// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
import ManifoldKit
@testable import Manifold

final class DashboardStateTests: XCTestCase {
    func testFixtureDataControlSummaryCarriesPerAgentTruth() async throws {
        let client = FixtureRuntimeClient(profile: .dashboard)
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
        let client = FixtureRuntimeClient(profile: .dashboard)
        let state = try await client.startTrackedRun(
            targetApp: .codex,
            fileScopes: [],
            selectedEmailIDs: [],
            summaryFraming: "Codex scoped work",
            noteCaptureMode: .basic,
            emailSensitivity: nil
        )

        XCTAssertEqual(state.targetApp, TargetApp.codex.rawValue)
        XCTAssertEqual(Set(state.activeGrantSources.map(\.sourceID)), Set(["src-shared"]))
        XCTAssertFalse(state.activeGrantSources.contains { $0.sourceID == "src-claude" })
    }

    func testLegacyDashboardPayloadDecodesWithFallbackGovernanceAndCoverageDefaults() throws {
        let encoder = JSONEncoder()
        let claudePolicy = AgentAccessPolicy(
            agent: .cowork,
            allowedSourceIDs: ["src-shared"],
            allowedEmailDomains: ["anthropic.test"],
            emailSensitivity: .moderate,
            defaultEmailPolicy: .allowUnlessBlocked,
            accessRecordingLevel: .summary
        )
        let codexPolicy = AgentAccessPolicy(
            agent: .codex,
            allowedSourceIDs: ["src-shared"],
            allowedEmailDomains: [],
            emailSensitivity: .strict,
            defaultEmailPolicy: .blockUnlessAllowed,
            accessRecordingLevel: .detailed
        )

        let payload: [String: Any] = [
            "claudePolicy": try XCTUnwrap(jsonObject(from: claudePolicy, encoder: encoder)),
            "codexPolicy": try XCTUnwrap(jsonObject(from: codexPolicy, encoder: encoder)),
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(DashboardState.self, from: data)

        XCTAssertTrue(decoded.runtimeConnected)
        XCTAssertEqual(decoded.connectedAgents, [])
        XCTAssertEqual(decoded.claudeEmailGovernance.domainRuleCount, 1)
        XCTAssertEqual(decoded.codexEmailGovernance.domainRuleCount, 0)
        XCTAssertEqual(decoded.agentCoverages, [])
        XCTAssertEqual(decoded.coverageEvents, [])
    }

    private func jsonObject<T: Encodable>(from value: T, encoder: JSONEncoder) throws -> Any? {
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }
}
