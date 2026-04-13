// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
import ManifoldKit
@testable import Manifold

@MainActor
final class EmailRulesModelTests: XCTestCase {
    func testLoadAndPersistSensitivityThroughFixtureRuntime() async {
        let runtime = FixtureRuntimeClient(profile: .emailRules)
        let model = EmailRulesModel()
        model.configure(client: runtime)

        await model.load(agent: .cowork)
        XCTAssertEqual(model.selectedAgent, .cowork)
        XCTAssertEqual(model.emailSensitivity, .moderate)
        XCTAssertFalse(model.domainRules.isEmpty)

        await model.updateSensitivity(.strict)

        XCTAssertEqual(model.emailSensitivity, .strict)
        let reloaded = try? await runtime.getEmailRuleSet(agent: .cowork)
        XCTAssertEqual(reloaded?.emailSensitivity, .strict)
    }

    func testSelectedAgentSwitchLoadsDifferentFixtureRuleSet() async {
        let runtime = FixtureRuntimeClient(profile: .emailRules)
        let model = EmailRulesModel()
        model.configure(client: runtime)

        await model.load(agent: .cowork)
        let coworkDomainCount = model.domainRules.count
        let coworkSensitivity = model.emailSensitivity

        await model.load(agent: .codex)

        XCTAssertEqual(model.selectedAgent, .codex)
        XCTAssertEqual(model.domainRules.count, coworkDomainCount)
        XCTAssertNotEqual(model.emailSensitivity, coworkSensitivity)
        XCTAssertEqual(model.defaultPolicy, .blockUnlessAllowed)
    }
}
