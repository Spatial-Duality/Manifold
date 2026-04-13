// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
import ManifoldKit
@testable import Manifold

final class DashboardStateTests: XCTestCase {
    func testLegacyDashboardPayloadDecodesWithFallbackGovernanceAndCoverageDefaults() throws {
        let encoder = JSONEncoder()
        let claudePolicy = AgentAccessPolicy(
            agent: .cowork,
            allowedSourceIDs: ["src-shared"],
            allowedEmailDomains: ["example.com"],
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
