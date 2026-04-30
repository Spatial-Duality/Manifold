// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import Manifold

@MainActor
final class IntegrationHealthModelTests: XCTestCase {
    func testFixtureCheckerReportsOnboardingState() async {
        let model = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .onboarding))
        await model.checkAll(force: true)

        XCTAssertTrue(model.claude.appInstalled.isPassingCheck)
        XCTAssertEqual(model.claude.connectionVerified, .configured)
        XCTAssertTrue(model.codex.codexAppInstalled.isPassingCheck)
        XCTAssertEqual(model.codex.mcpAdded, .configured)
    }

    func testFixtureCheckerReportsRuntimeStatus() async {
        let model = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .baseline))
        await model.checkAll(force: true)

        XCTAssertTrue(model.claude.appInstalled.isPassingCheck)
        XCTAssertTrue(model.claude.mcpConfigured.isPassingCheck)
        XCTAssertTrue(model.codex.codexAppInstalled.isPassingCheck)
        XCTAssertTrue(model.codex.mcpAdded.isPassingCheck)
    }
}
