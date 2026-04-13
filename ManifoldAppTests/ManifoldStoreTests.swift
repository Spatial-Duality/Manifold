// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import Manifold

@MainActor
final class ManifoldStoreTests: XCTestCase {
    func testFixtureStoreLoadsDashboardSummaryWithoutStartingServices() async {
        let runtime = FixtureRuntimeClient(profile: .trackedWork)
        let integration = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .trackedWork))
        let store = ManifoldStore(runtime: runtime, integrationHealth: integration, startServices: false)

        await store.loadSummary()

        XCTAssertTrue(store.isRuntimeConnected)
        XCTAssertTrue(store.isClaudeConnected)
        XCTAssertTrue(store.isCodexConnected)
        XCTAssertEqual(store.policy.activeWorkBlock?.agent, .codex)
        XCTAssertFalse(store.history.activityEntries.isEmpty)
    }
}
