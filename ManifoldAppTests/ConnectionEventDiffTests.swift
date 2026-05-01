// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
import ManifoldKit
@testable import Manifold

/// ConnectionEventDiff is the pure logic that turns "what was connected
/// last refresh vs what's connected now" into typed events. These tests
/// pin the contract: order, identity, no double-fire on no-op.
final class ConnectionEventDiffTests: XCTestCase {

    func testNoChangeProducesNoEvents() {
        let now = Date()
        let events = ConnectionEventDiff.events(
            previous: ["cowork"],
            current: ["cowork"],
            at: now
        )
        XCTAssertTrue(events.isEmpty)
    }

    func testEmptyToEmptyProducesNoEvents() {
        let events = ConnectionEventDiff.events(
            previous: [],
            current: [],
            at: Date()
        )
        XCTAssertTrue(events.isEmpty)
    }

    func testFirstConnectFiresConnectedEvent() {
        let events = ConnectionEventDiff.events(
            previous: [],
            current: ["cowork"],
            at: Date()
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].agent, .cowork)
        XCTAssertEqual(events[0].kind, .connected)
    }

    func testDisconnectFiresDisconnectedEvent() {
        let events = ConnectionEventDiff.events(
            previous: ["cowork"],
            current: [],
            at: Date()
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].agent, .cowork)
        XCTAssertEqual(events[0].kind, .disconnected)
    }

    func testBothAgentsConnectedAtOnceProducesTwoEvents() {
        let events = ConnectionEventDiff.events(
            previous: [],
            current: ["cowork", "codex"],
            at: Date()
        )
        XCTAssertEqual(events.count, 2)
        // Both are .connected; deterministic order by raw value.
        XCTAssertEqual(events.map(\.kind), [.connected, .connected])
        XCTAssertEqual(Set(events.map(\.agent)), [.cowork, .codex])
    }

    func testSimultaneousConnectAndDisconnectShowsDisconnectFirst() {
        // Disconnects come first so the UI's chronological feed surfaces
        // the bad-news event ahead of the recovery.
        let events = ConnectionEventDiff.events(
            previous: ["cowork"],
            current: ["codex"],
            at: Date()
        )
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].kind, .disconnected)
        XCTAssertEqual(events[0].agent, .cowork)
        XCTAssertEqual(events[1].kind, .connected)
        XCTAssertEqual(events[1].agent, .codex)
    }

    func testTimestampThreadsThrough() {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let events = ConnectionEventDiff.events(
            previous: [],
            current: ["cowork"],
            at: fixed
        )
        XCTAssertEqual(events.first?.at, fixed)
    }

    func testEventsAreUniqueByID() {
        // Round-trip through a Set to confirm IDs collide ~never.
        let now = Date()
        var ids: Set<UUID> = []
        for _ in 0..<100 {
            let events = ConnectionEventDiff.events(
                previous: [],
                current: ["cowork", "codex"],
                at: now
            )
            for event in events {
                XCTAssertFalse(ids.contains(event.id), "Duplicate UUID")
                ids.insert(event.id)
            }
        }
    }

    func testUnknownRawValuesAreDroppedCleanly() {
        // If the runtime ever surfaces an unknown agent value, it shouldn't
        // crash the diff or produce a phantom event.
        let events = ConnectionEventDiff.events(
            previous: [],
            current: ["cowork", "future-agent-no-such-thing"],
            at: Date()
        )
        XCTAssertEqual(events.count, 1, "Unknown raw values are filtered out")
        XCTAssertEqual(events[0].agent, .cowork)
    }
}
