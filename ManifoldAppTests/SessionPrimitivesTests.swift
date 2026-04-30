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
        XCTAssertEqual(try XCTUnwrap(record.remainingSeconds), 0, accuracy: 2)
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
        let displayDuration = try? XCTUnwrap(record.displayDuration)
        XCTAssertTrue(displayDuration?.hasPrefix("2h ") == true)
        XCTAssertTrue(displayDuration?.hasSuffix(" remaining") == true)
    }

    // MARK: - SessionRecord adapter over WorkBlockRecord

    func testSessionRecordAdapterDerivesTrackedEditFromStatus() {
        let active = WorkBlockRecord(
            agent: .cowork,
            grantID: "g-1",
            status: .active
        )
        let session = SessionRecord(storageRecord: active)
        XCTAssertTrue(session.isTrackedEdit)
        XCTAssertEqual(session.agents, [.cowork])

        let discarded = WorkBlockRecord(
            agent: .cowork,
            grantID: "g-1",
            status: .discarded
        )
        XCTAssertFalse(SessionRecord(storageRecord: discarded).isTrackedEdit)
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
            pathsChangedSinceEnded: ["~/Projects/FrontierSafety/README.md"],
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
        if case .suggested(let denialCount) = Rule.CreatedBy.suggested(denialCount: 5) {
            XCTAssertEqual(denialCount, 5)
        } else {
            XCTFail("Expected .suggested")
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

    func testPendingRequestsMapStandingWriteIntoSessionPrimitives() throws {
        let model = GovernanceModel()
        model.pendingApprovals = [
            PendingApprovalRecord(
                id: "approval-1",
                connectionID: "conn-1",
                agent: TargetApp.codex.rawValue,
                path: "shared/worklog.md",
                action: "write",
                kind: "standing_write",
                mountName: "shared",
                relativePath: "worklog.md",
                requestedAt: 1_715_000_000,
                status: "pending"
            )
        ]

        let request = try XCTUnwrap(model.pendingRequests.first)
        XCTAssertEqual(request.agent, .codex)
        XCTAssertEqual(request.kind, .standingWrite)
        XCTAssertEqual(request.operation, .write)
        XCTAssertEqual(request.headline, "Codex wants reversible write access.")
        XCTAssertEqual(
            request.context,
            "Writes to shared are governed by Manifold snapshots and can be restored from version history."
        )
    }

    func testPendingRequestsMapFolderReadsIntoGenericSessionCopy() throws {
        let model = GovernanceModel()
        model.pendingApprovals = [
            PendingApprovalRecord(
                id: "approval-1",
                connectionID: "conn-1",
                agent: TargetApp.codex.rawValue,
                path: "/tmp/shared",
                action: "read_folder",
                kind: "manual_review",
                requestedAt: 1_715_000_000,
                status: "pending"
            )
        ]

        let request = try XCTUnwrap(model.pendingRequests.first)
        XCTAssertEqual(request.agent, .codex)
        XCTAssertEqual(request.operation, .readFolder)
        XCTAssertEqual(request.headline, "Codex wants to read a folder.")
        XCTAssertEqual(request.context, "Requested outside this Codex session's scope. Answer or ignore.")
    }

    func testPendingRequestsMapPrivacyExposureIntoPrivacyRequest() throws {
        let model = GovernanceModel()
        model.pendingApprovals = [
            PendingApprovalRecord(
                id: "approval-privacy-1",
                connectionID: "conn-1",
                agent: TargetApp.codex.rawValue,
                path: "email-4",
                action: "mail",
                kind: "privacy_exposure",
                contextJSON: #"{"toolName":"read_email","contentKind":"email","inputHash":"hash-1","findingsSummary":"Contains your email plus a secret token.","matchedCategories":["email","secret"],"redactedPreview":"Email: [EMAIL REDACTED]\nSecret: [SECRET REDACTED]","recommendation":"Share the redacted version unless the original is required for this session."}"#,
                requestedAt: 1_715_000_000,
                status: "pending"
            )
        ]

        let request = try XCTUnwrap(model.pendingRequests.first)
        XCTAssertEqual(request.kind, .privacyExposure)
        XCTAssertEqual(request.operation, .mailboxRead)
        XCTAssertEqual(request.headline, "Codex needs privacy review before sharing email.")
        XCTAssertEqual(request.matchedCategories, [.email, .secret])
        XCTAssertEqual(request.severity, .critical)
        XCTAssertEqual(request.findingsSummary, "Contains your email plus a secret token.")
        XCTAssertEqual(request.recommendation, "Share the redacted version unless the original is required for this session.")
        XCTAssertTrue(request.context.contains("Contains your email plus a secret token."))
    }

    func testPendingRequestsIgnoreUnknownAgents() {
        let model = GovernanceModel()
        model.pendingApprovals = [
            PendingApprovalRecord(
                id: "approval-1",
                connectionID: "conn-1",
                agent: "unknown-agent",
                path: "/tmp/shared",
                action: "write",
                requestedAt: 1_715_000_000,
                status: "pending"
            )
        ]

        XCTAssertTrue(model.pendingRequests.isEmpty)
    }

    // MARK: - ManifoldCommands protocol conformance

    func testStoreConformsToManifoldCommands() {
        let runtime = FixtureRuntimeClient(profile: .dashboard)
        let health = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .dashboard))
        let store = ManifoldStore(runtime: runtime, integrationHealth: health, startServices: false)
        let commands: any ManifoldCommands = store
        XCTAssertNotNil(commands)
    }
}
