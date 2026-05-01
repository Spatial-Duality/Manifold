// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import Manifold

/// RuntimeIssueClassifier replaces ad-hoc string-grep error routing with a
/// typed classifier. These tests pin the mapping so the recovery action
/// shown to the user matches the underlying signal.
final class RuntimeIssueClassifierTests: XCTestCase {

    // MARK: - Healthy state

    func testHealthyStateReturnsNil() {
        let issue = RuntimeIssueClassifier.classify(
            isRuntimeConnected: true,
            runtimeLaunchError: nil,
            lastError: nil
        )
        XCTAssertNil(issue)
    }

    func testEmptyErrorStringsAreTreatedAsHealthy() {
        let issue = RuntimeIssueClassifier.classify(
            isRuntimeConnected: true,
            runtimeLaunchError: "",
            lastError: ""
        )
        XCTAssertNil(issue)
    }

    // MARK: - Stale helper detection (highest priority)

    func testStaleHelperKeywordRoutesToReconnect() {
        let issue = RuntimeIssueClassifier.classify(
            isRuntimeConnected: true,
            runtimeLaunchError: "Verifier flagged stale signature",
            lastError: nil
        )
        XCTAssertEqual(issue?.recoveryAction, .reconnect)
        XCTAssertEqual(issue?.title, "Agent helper out of date")
    }

    func testReconnectKeywordRoutesToReconnect() {
        let issue = RuntimeIssueClassifier.classify(
            isRuntimeConnected: true,
            runtimeLaunchError: nil,
            lastError: "Helper needs reconnect after upgrade"
        )
        XCTAssertEqual(issue?.recoveryAction, .reconnect)
    }

    func testStaleTakesPrecedenceOverDisconnected() {
        // If the runtime is also reachable-but-stale, we want reconnect,
        // not retry. Stale wins because retry won't fix it.
        let issue = RuntimeIssueClassifier.classify(
            isRuntimeConnected: false,
            runtimeLaunchError: "stale helper signature",
            lastError: nil
        )
        XCTAssertEqual(issue?.recoveryAction, .reconnect)
    }

    // MARK: - Word-boundary safety (the bug the typed classifier prevents)

    func testReconnectedDoesNotMatch() {
        // "Reconnected to mailbox" used to false-positive into the stale
        // helper path under the old substring grep. The classifier must
        // NOT treat this as a stale-helper signal.
        let issue = RuntimeIssueClassifier.classify(
            isRuntimeConnected: true,
            runtimeLaunchError: nil,
            lastError: "Reconnected to mailbox after retry"
        )
        XCTAssertNotEqual(issue?.recoveryAction, .reconnect)
        XCTAssertEqual(issue?.recoveryAction, .restart)
    }

    func testStalemateDoesNotMatch() {
        // Synthetic edge case: any word starting with "stale" must not
        // trigger the stale-helper path unless it's a whole-word match.
        let issue = RuntimeIssueClassifier.classify(
            isRuntimeConnected: true,
            runtimeLaunchError: nil,
            lastError: "Reached a stalemate fetching mail"
        )
        XCTAssertNotEqual(issue?.recoveryAction, .reconnect)
    }

    // MARK: - Disconnect routing

    func testDisconnectedRoutesToRetry() {
        let issue = RuntimeIssueClassifier.classify(
            isRuntimeConnected: false,
            runtimeLaunchError: nil,
            lastError: nil
        )
        XCTAssertEqual(issue?.recoveryAction, .retry)
        XCTAssertEqual(issue?.title, "Runtime unavailable")
    }

    func testDisconnectedDetailUsesLaunchErrorWhenAvailable() {
        let issue = RuntimeIssueClassifier.classify(
            isRuntimeConnected: false,
            runtimeLaunchError: "launchctl bootstrap failed",
            lastError: nil
        )
        XCTAssertEqual(issue?.detail, "launchctl bootstrap failed")
    }

    func testDisconnectedFallsBackToGenericDetail() {
        let issue = RuntimeIssueClassifier.classify(
            isRuntimeConnected: false,
            runtimeLaunchError: nil,
            lastError: nil
        )
        XCTAssertEqual(issue?.detail, "Manifold can't reach the runtime right now.")
    }

    // MARK: - Helper error routing

    func testConnectedWithLastErrorRoutesToRestart() {
        let issue = RuntimeIssueClassifier.classify(
            isRuntimeConnected: true,
            runtimeLaunchError: nil,
            lastError: "RPC timeout reading mailboxes"
        )
        XCTAssertEqual(issue?.recoveryAction, .restart)
        XCTAssertEqual(issue?.title, "Runtime needs restart")
        XCTAssertEqual(issue?.detail, "RPC timeout reading mailboxes")
    }

    // MARK: - Action label sanity

    func testPrimaryActionLabelsMatchAppleVoice() {
        // Sentence case + matches the post-voice-audit conventions.
        let retry = RuntimeIssueClassifier.classify(
            isRuntimeConnected: false, runtimeLaunchError: nil, lastError: nil
        )
        XCTAssertEqual(retry?.primaryActionLabel, "Retry")

        let restart = RuntimeIssueClassifier.classify(
            isRuntimeConnected: true, runtimeLaunchError: nil, lastError: "boom"
        )
        XCTAssertEqual(restart?.primaryActionLabel, "Restart runtime")

        let reconnect = RuntimeIssueClassifier.classify(
            isRuntimeConnected: true, runtimeLaunchError: nil, lastError: "stale helper"
        )
        XCTAssertEqual(reconnect?.primaryActionLabel, "Reconnect agents")
    }
}
