// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
import ManifoldKit
@testable import Manifold

@MainActor
final class SessionPrimitivesTests: XCTestCase {

    // MARK: - SessionRecord.remainingSeconds / displayDuration

    func testRemainingSecondsIsNilWhenNoExpiration() {
        let record = SessionRecord(
            id: "s-1", name: "Test",
            startedAt: .now,
            expiresAt: nil,
            agents: [.cowork],
            baseMode: .defaultScope,
            trackWrites: false,
            isTrackedEdit: false,
            additions: [], removals: []
        )
        XCTAssertNil(record.remainingSeconds)
        XCTAssertNil(record.displayDuration)
    }

    func testRemainingSecondsClampsToZero() {
        let record = SessionRecord(
            id: "s-2", name: "Expired",
            startedAt: Date(timeIntervalSinceNow: -7200),
            expiresAt: Date(timeIntervalSinceNow: -3600),
            agents: [.cowork],
            baseMode: .defaultScope,
            trackWrites: false,
            isTrackedEdit: false,
            additions: [], removals: []
        )
        XCTAssertEqual(record.remainingSeconds, 0, accuracy: 2)
    }

    func testDisplayDurationFormats() {
        let record = SessionRecord(
            id: "s-3", name: "Test",
            startedAt: .now,
            expiresAt: Date(timeIntervalSinceNow: 7320), // 2h 2m
            agents: [.cowork],
            baseMode: .defaultScope,
            trackWrites: false,
            isTrackedEdit: false,
            additions: [], removals: []
        )
        XCTAssertEqual(record.displayDuration, "2h 2m remaining")
    }

    // MARK: - SessionRecord adapter over WorkBlockRecord

    func testSessionRecordAdapterDerivesTrackedEditFromStatus() {
        let active = WorkBlockRecord(
            agent: .cowork,
            grantID: "g-1",
            status: .active
        )
        let session = SessionRecord(workBlock: active)
        XCTAssertTrue(session.isTrackedEdit)
        XCTAssertEqual(session.agents, [.cowork])

        let discarded = WorkBlockRecord(
            agent: .cowork,
            grantID: "g-1",
            status: .discarded
        )
        XCTAssertFalse(SessionRecord(workBlock: discarded).isTrackedEdit)
    }

    // MARK: - Drift

    func testCleanDriftReportsIsClean() {
        let entry = SessionHistoryEntry(
            id: "h-1", name: "Old",
            startedAt: .now.addingTimeInterval(-7200),
            endedAt: .now.addingTimeInterval(-3600),
            agents: [.cowork], eventCount: 0,
            additions: [], removals: []
        )
        let drift = SessionDrift(
            historyEntry: entry,
            pathsChangedSinceEnded: [],
            pathsRevokedSinceEnded: [],
            newlyAddedSinceEnded: []
        )
        XCTAssertTrue(drift.isClean)
    }

    func testDirtyDriftReportsIsNotClean() {
        let entry = SessionHistoryEntry(
            id: "h-2", name: "Dirty",
            startedAt: .now.addingTimeInterval(-7200),
            endedAt: .now.addingTimeInterval(-3600),
            agents: [.cowork], eventCount: 0,
            additions: [], removals: []
        )
        let drift = SessionDrift(
            historyEntry: entry,
            pathsChangedSinceEnded: ["~/Projects/Acme/README.md"],
            pathsRevokedSinceEnded: [],
            newlyAddedSinceEnded: []
        )
        XCTAssertFalse(drift.isClean)
    }

    // MARK: - Rule

    func testRuleDomainsAreExhaustive() {
        XCTAssertEqual(Set(Rule.Domain.allCases), [.files, .email, .agents])
    }

    func testSuggestedRuleCarriesDenialCount() {
        switch Rule.CreatedBy.suggested(denialCount: 5) {
        case .suggested(let n): XCTAssertEqual(n, 5)
        default: XCTFail("Expected .suggested")
        }
    }

    // MARK: - ApprovalAnswer

    func testApprovalAnswerForSessionEquality() {
        let a = ApprovalAnswer.forSession(sessionID: "abc")
        let b = ApprovalAnswer.forSession(sessionID: "abc")
        let c = ApprovalAnswer.forSession(sessionID: "xyz")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - ManifoldCommands protocol conformance

    func testStoreConformsToManifoldCommands() {
        let runtime = FixtureRuntimeClient(profile: .empty)
        let health = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .empty))
        let store = ManifoldStore(runtime: runtime, integrationHealth: health, startServices: false)
        let commands: any ManifoldCommands = store
        XCTAssertNotNil(commands)
    }
}
