// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import Observation

// ┌──────────────────────────────────────────────────────────────────────────┐
// │ SharingState                                                             │
// │                                                                          │
// │ Reactive parent-child checkbox model for the unified Access surface.     │
// │ Source of truth for "what AI(s) can see this item right now".            │
// │                                                                          │
// │ Invariant: parent ("All AIs") = ∀children                                │
// │   The parent is never stored independently — it is always derived from   │
// │   the children. This makes drift impossible: the runtime invariant       │
// │   matches the visual invariant.                                          │
// │                                                                          │
// │ Modes:                                                                   │
// │   single     — one item selected. State is one of 4: hidden / claudeOnly │
// │                / codexOnly / allAIs (assuming 2 connected agents).       │
// │   multi      — multiple items. Each agent's state is on / off / mixed.   │
// │                Parent is mixed if any child is mixed OR if children      │
// │                disagree.                                                 │
// │                                                                          │
// │ Adaptive: connectedAgents drives which children render. Zero connected   │
// │ agents → empty state. One connected → no parent row (would be redundant).│
// │ Two+ → parent + N children with cascade transitions.                     │
// └──────────────────────────────────────────────────────────────────────────┘

/// Tri-state value used by the multi-select selector and per-child checkboxes.
public enum SharingTriState: Equatable, Sendable {
    case off
    case on
    case mixed
}

/// Plain-English label for the current selector state. The label is the
/// audit story made visible: every change updates this string and the user
/// always knows what they're sharing in one phrase.
public enum SharingLabel: Equatable, Hashable, Sendable {
    case hiddenFromAll
    case visibleTo(TargetApp)
    case allAIs
    case mixed(connectedAgents: [TargetApp])
    case noAgentsConnected

    public var text: String {
        switch self {
        case .hiddenFromAll:        return "Hidden from all"
        case .visibleTo(let agent): return "\(Self.displayName(for: agent)) only"
        case .allAIs:                return "All AIs"
        case .mixed:                 return "Mixed sharing"
        case .noAgentsConnected:    return "No AI connected"
        }
    }

    static func displayName(for agent: TargetApp) -> String {
        switch agent {
        case .cowork: return "Claude"
        case .codex:  return "Codex"
        }
    }
}

/// Snapshot describing one connected agent's current state in the selector.
public struct SharingAgentState: Equatable, Sendable, Identifiable {
    public let agent: TargetApp
    public let state: SharingTriState
    /// True when this row's state was set explicitly (not just inherited from
    /// a folder default). Used to render the override underline in the UI.
    public let isExplicitOverride: Bool
    public var id: String { agent.rawValue }

    public init(agent: TargetApp, state: SharingTriState, isExplicitOverride: Bool = false) {
        self.agent = agent
        self.state = state
        self.isExplicitOverride = isExplicitOverride
    }
}

/// Reactive selector state. UI views observe this object and call its
/// `toggle*` methods; the model recomputes the derived parent state on
/// every mutation so views never have to.
@Observable
@MainActor
public final class SharingState {
    /// Connected agents in stable display order. Drives which child rows
    /// render and whether the parent ("All AIs") row appears at all.
    public private(set) var connectedAgents: [TargetApp]

    /// Per-agent state. Always has one entry per `connectedAgents` element.
    /// Source of truth — the parent state is derived from this.
    public private(set) var agents: [SharingAgentState]

    /// Whether the user has selected one item or many. Affects how callers
    /// interpret the model (single = state machine; multi = tri-state batch).
    public private(set) var mode: Mode

    public enum Mode: Equatable, Sendable {
        case single
        case multi(itemCount: Int)
    }

    public init(connectedAgents: [TargetApp], mode: Mode = .single) {
        // Defensive copy + dedupe while preserving order.
        var seen = Set<TargetApp>()
        let uniqueOrdered = connectedAgents.filter { seen.insert($0).inserted }
        self.connectedAgents = uniqueOrdered
        self.agents = uniqueOrdered.map {
            SharingAgentState(agent: $0, state: .off, isExplicitOverride: false)
        }
        self.mode = mode
    }

    // MARK: - Derived state

    /// State of the synthetic "All AIs" parent row. Always derived; never
    /// stored. Empty `connectedAgents` returns `.off` (no agents to be on).
    public var allAIsState: SharingTriState {
        guard !agents.isEmpty else { return .off }
        if agents.contains(where: { $0.state == .mixed }) {
            return .mixed
        }
        let onCount = agents.filter { $0.state == .on }.count
        if onCount == agents.count { return .on }
        if onCount == 0 { return .off }
        return .mixed
    }

    /// Whether to render the "All AIs" parent at all. Hidden when zero
    /// connected agents (no children to compose) and when only one
    /// connected agent (parent would just shadow the single child).
    public var showsAllAIsRow: Bool {
        connectedAgents.count >= 2
    }

    /// Plain-English summary of the current state for the live label.
    public var label: SharingLabel {
        guard !agents.isEmpty else { return .noAgentsConnected }

        switch mode {
        case .single:
            let onAgents = agents.filter { $0.state == .on }.map(\.agent)
            switch onAgents.count {
            case 0: return .hiddenFromAll
            case agents.count: return .allAIs
            case 1: return .visibleTo(onAgents[0])
            default: return .mixed(connectedAgents: connectedAgents)
            }
        case .multi:
            // In multi mode any non-uniform state shows "mixed".
            if agents.allSatisfy({ $0.state == .on }) { return .allAIs }
            if agents.allSatisfy({ $0.state == .off }) { return .hiddenFromAll }
            return .mixed(connectedAgents: connectedAgents)
        }
    }

    // MARK: - Mutation

    /// Set the state of a specific agent's child row. Auto-flips the parent
    /// state because the parent is derived. Idempotent.
    public func setAgent(_ agent: TargetApp, state: SharingTriState, explicit: Bool = true) {
        guard let idx = agents.firstIndex(where: { $0.agent == agent }) else { return }
        agents[idx] = SharingAgentState(
            agent: agent,
            state: state,
            isExplicitOverride: explicit
        )
    }

    /// Toggle a single agent's state (single mode: off↔on). In multi mode,
    /// applies the cycle mixed→on→off→on.
    public func toggleAgent(_ agent: TargetApp) {
        guard let idx = agents.firstIndex(where: { $0.agent == agent }) else { return }
        let current = agents[idx].state
        let next: SharingTriState
        switch (mode, current) {
        case (.single, .on):     next = .off
        case (.single, .off):    next = .on
        case (.single, .mixed):  next = .on
        case (.multi, .mixed):   next = .on
        case (.multi, .on):      next = .off
        case (.multi, .off):     next = .on
        }
        agents[idx] = SharingAgentState(
            agent: agent,
            state: next,
            isExplicitOverride: true
        )
    }

    /// Toggle the parent "All AIs" row. Cascades to all children.
    /// Cycle: mixed → on → off → on (matches Apple Finder tri-state).
    public func toggleAllAIs() {
        guard !agents.isEmpty else { return }
        let current = allAIsState
        let nextState: SharingTriState
        switch current {
        case .off:    nextState = .on
        case .on:     nextState = .off
        case .mixed:  nextState = .on // mixed → on (set all)
        }
        for idx in agents.indices {
            agents[idx] = SharingAgentState(
                agent: agents[idx].agent,
                state: nextState,
                isExplicitOverride: true
            )
        }
    }

    // MARK: - Adaptive

    /// Update connected agents (e.g., user connected/disconnected an AI).
    /// Existing per-agent states are preserved if the agent is still
    /// connected. Newly connected agents default to `.off` (most
    /// conservative — explicit user action is required to share).
    public func updateConnectedAgents(_ newConnected: [TargetApp]) {
        var seen = Set<TargetApp>()
        let uniqueOrdered = newConnected.filter { seen.insert($0).inserted }
        let existingByAgent = Dictionary(uniqueKeysWithValues: agents.map { ($0.agent, $0) })
        connectedAgents = uniqueOrdered
        agents = uniqueOrdered.map { agent in
            existingByAgent[agent] ?? SharingAgentState(
                agent: agent, state: .off, isExplicitOverride: false
            )
        }
    }

    /// Switch between single and multi modes. Used when the user changes
    /// table selection size.
    public func setMode(_ mode: Mode) {
        self.mode = mode
    }
}
