// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
import ManifoldKit
@testable import Manifold

@MainActor
final class SharingStateTests: XCTestCase {

    // MARK: - Single mode state machine

    func testSingleModeStartsHiddenFromAll() {
        let state = SharingState(connectedAgents: [.cowork, .codex])
        XCTAssertEqual(state.label, .hiddenFromAll)
        XCTAssertEqual(state.allAIsState, .off)
    }

    func testSingleModeToggleClaudeOnlyTransition() {
        let state = SharingState(connectedAgents: [.cowork, .codex])
        state.toggleAgent(.cowork)
        XCTAssertEqual(state.label, .visibleTo(.cowork))
        XCTAssertEqual(state.allAIsState, .off)
        XCTAssertEqual(state.agents[0].state, .on)
        XCTAssertEqual(state.agents[1].state, .off)
    }

    func testSingleModeToggleSecondAgentAutoFlipsAllAIs() {
        let state = SharingState(connectedAgents: [.cowork, .codex])
        state.toggleAgent(.cowork)
        state.toggleAgent(.codex)
        XCTAssertEqual(state.label, .allAIs)
        XCTAssertEqual(state.allAIsState, .on,
            "All AIs must auto-flip on when last child enables")
    }

    func testSingleModeToggleAllAIsCascadesToAllChildren() {
        let state = SharingState(connectedAgents: [.cowork, .codex])
        state.toggleAllAIs()
        XCTAssertEqual(state.label, .allAIs)
        XCTAssertTrue(state.agents.allSatisfy { $0.state == .on })
    }

    func testSingleModeUntogglingChildAutoFlipsAllAIsOff() {
        let state = SharingState(connectedAgents: [.cowork, .codex])
        state.toggleAllAIs() // both on
        state.toggleAgent(.codex) // codex off
        XCTAssertEqual(state.label, .visibleTo(.cowork))
        XCTAssertEqual(state.allAIsState, .off,
            "All AIs must auto-flip off when any child disables")
    }

    func testSingleModeToggleAllAIsTwiceReturnsToHidden() {
        let state = SharingState(connectedAgents: [.cowork, .codex])
        state.toggleAllAIs()    // off → on
        state.toggleAllAIs()    // on → off
        XCTAssertEqual(state.label, .hiddenFromAll)
        XCTAssertTrue(state.agents.allSatisfy { $0.state == .off })
    }

    func testInvariantParentEqualsAndOfChildren() {
        let state = SharingState(connectedAgents: [.cowork, .codex])
        // Walk every state combination and assert the invariant.
        let combos: [(SharingTriState, SharingTriState)] = [
            (.off, .off), (.on, .off), (.off, .on), (.on, .on)
        ]
        for (claude, codex) in combos {
            state.setAgent(.cowork, state: claude)
            state.setAgent(.codex, state: codex)
            let expected: SharingTriState = (claude == .on && codex == .on) ? .on
                : (claude == .off && codex == .off) ? .off
                : .mixed
            XCTAssertEqual(state.allAIsState, expected,
                "Invariant violated for \(claude) / \(codex)")
        }
    }

    // MARK: - Adaptive UI

    func testZeroAgentsShowsNoAllRowAndNoAgentsConnectedLabel() {
        let state = SharingState(connectedAgents: [])
        XCTAssertFalse(state.showsAllAIsRow)
        XCTAssertEqual(state.label, .noAgentsConnected)
        XCTAssertEqual(state.agents.count, 0)
    }

    func testSingleAgentHidesAllAIsParentRow() {
        let state = SharingState(connectedAgents: [.cowork])
        XCTAssertFalse(state.showsAllAIsRow,
            "Parent row is redundant with a single child — must not render")
        XCTAssertEqual(state.agents.count, 1)
    }

    func testTwoAgentsShowsAllAIsParentRow() {
        let state = SharingState(connectedAgents: [.cowork, .codex])
        XCTAssertTrue(state.showsAllAIsRow)
    }

    func testUpdateConnectedAgentsPreservesExistingStates() {
        let state = SharingState(connectedAgents: [.cowork])
        state.toggleAgent(.cowork) // claude on
        state.updateConnectedAgents([.cowork, .codex])
        // Claude state preserved, Codex defaults to off (most conservative).
        XCTAssertEqual(state.agents.count, 2)
        XCTAssertEqual(state.agents[0].state, .on)
        XCTAssertEqual(state.agents[1].state, .off)
    }

    func testUpdateConnectedAgentsRemovesDisconnectedAgent() {
        let state = SharingState(connectedAgents: [.cowork, .codex])
        state.toggleAllAIs()
        state.updateConnectedAgents([.cowork])
        XCTAssertEqual(state.agents.count, 1)
        XCTAssertEqual(state.agents[0].agent, .cowork)
        XCTAssertEqual(state.agents[0].state, .on)
    }

    // MARK: - Multi-select tri-state

    func testMultiModeMixedCycleGoesToOnFirst() {
        let state = SharingState(connectedAgents: [.cowork, .codex],
                                  mode: .multi(itemCount: 3))
        state.setAgent(.cowork, state: .mixed)
        state.toggleAgent(.cowork)
        XCTAssertEqual(state.agents[0].state, .on,
            "Mixed → on is the first click in tri-state cycle")
    }

    func testMultiModeOnCyclesToOff() {
        let state = SharingState(connectedAgents: [.cowork, .codex],
                                  mode: .multi(itemCount: 3))
        state.setAgent(.cowork, state: .on)
        state.toggleAgent(.cowork)
        XCTAssertEqual(state.agents[0].state, .off)
    }

    func testMultiModeAllAIsLabel() {
        let state = SharingState(connectedAgents: [.cowork, .codex],
                                  mode: .multi(itemCount: 3))
        state.setAgent(.cowork, state: .on)
        state.setAgent(.codex, state: .on)
        XCTAssertEqual(state.label, .allAIs)
    }

    func testMultiModeMixedLabelWhenChildrenDisagree() {
        let state = SharingState(connectedAgents: [.cowork, .codex],
                                  mode: .multi(itemCount: 3))
        state.setAgent(.cowork, state: .on)
        state.setAgent(.codex, state: .mixed)
        if case .mixed = state.label {
            // ok
        } else {
            XCTFail("Expected mixed label, got \(state.label)")
        }
    }

    // MARK: - Override tracking

    func testToggleAgentMarksExplicitOverride() {
        let state = SharingState(connectedAgents: [.cowork, .codex])
        XCTAssertFalse(state.agents[0].isExplicitOverride)
        state.toggleAgent(.cowork)
        XCTAssertTrue(state.agents[0].isExplicitOverride,
            "Explicit user toggle must be flagged so the UI can render the override underline")
    }

    func testSetAgentExplicitFalseDoesNotMarkOverride() {
        let state = SharingState(connectedAgents: [.cowork, .codex])
        state.setAgent(.cowork, state: .on, explicit: false)
        XCTAssertFalse(state.agents[0].isExplicitOverride,
            "State seeded from inherited source default should not show as override")
    }
}
