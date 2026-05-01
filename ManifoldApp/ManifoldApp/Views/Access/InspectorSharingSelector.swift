// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// InspectorSharingSelector — props-driven sister view to SharingControl.
//
// SharingControl owns its state via SharingState (@Observable). The
// FileInspectorPane uses callback-based plumbing wired to the existing
// FileVisibilityOverrideStore flow, so re-routing through SharingState
// would mean either a feedback-loop suppressor (fragile) or replacing
// the inspector's whole state-ownership pattern (out of scope here).
//
// Instead, this view renders the same visual language — adaptive parent-
// child indented checkboxes with cascade animation, live label, "via All"
// decoration when parent is on — while reading state from props and
// forwarding taps via callbacks. It pairs with FileInspectorPane's
// existing onToggleAgent and onSetAllAgents closures.
//
// Visually identical to SharingControl. Different state ownership.

import SwiftUI
import ManifoldKit

struct InspectorSharingSelector: View {
    let connectedAgents: [TargetApp]
    let visibleAgents: Set<TargetApp>
    /// Agents whose state was set explicitly (not just inherited from a
    /// folder default). Used to render the override underline.
    let explicitAgents: Set<TargetApp>
    var accessibilityIDPrefix: String?
    let onToggleAgent: (TargetApp, Bool) -> Void
    let onSetAllAgents: (Bool) -> Void

    init(
        connectedAgents: [TargetApp],
        visibleAgents: Set<TargetApp>,
        explicitAgents: Set<TargetApp> = [],
        accessibilityIDPrefix: String? = nil,
        onToggleAgent: @escaping (TargetApp, Bool) -> Void,
        onSetAllAgents: @escaping (Bool) -> Void
    ) {
        self.connectedAgents = connectedAgents
        self.visibleAgents = visibleAgents
        self.explicitAgents = explicitAgents
        self.accessibilityIDPrefix = accessibilityIDPrefix
        self.onToggleAgent = onToggleAgent
        self.onSetAllAgents = onSetAllAgents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            content
            liveLabel
        }
        .animation(Anim.stateChange, value: visibleAgents)
    }

    // MARK: - Body parts

    @ViewBuilder
    private var content: some View {
        if connectedAgents.isEmpty {
            heroEmpty
        } else if showsAllAIsRow {
            parentChildGroup
        } else {
            singleAgentRow
        }
    }

    @ViewBuilder
    private var heroEmpty: some View {
        Text("No agents connected")
            .font(.headline)
        Text("Connect Claude or Codex to start sharing this file.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var singleAgentRow: some View {
        let agent = connectedAgents[0]
        let isOn = visibleAgents.contains(agent)
        SelectorRow(
            triState: isOn ? .on : .off,
            label: displayName(for: agent),
            isExplicitOverride: explicitAgents.contains(agent),
            tint: agentTint(for: agent),
            accessibilityIdentifier: accessibilityIDPrefix.map { "\($0).agent.\(agent.rawValue)" }
        ) {
            onToggleAgent(agent, isOn)
        }
    }

    @ViewBuilder
    private var parentChildGroup: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            // Parent.
            SelectorRow(
                triState: allAIsTriState,
                label: "All AIs",
                isExplicitOverride: false,
                tint: .accentColor,
                accessibilityIdentifier: accessibilityIDPrefix.map { "\($0).all" }
            ) {
                // Cascade: if parent is on, turn everything off; otherwise turn on.
                onSetAllAgents(allAIsTriState != .on)
            }
            // Children.
            VStack(alignment: .leading, spacing: Spacing.tight) {
                ForEach(connectedAgents, id: \.rawValue) { agent in
                    childRow(agent)
                }
            }
            .padding(.leading, Spacing.large)
        }
    }

    @ViewBuilder
    private func childRow(_ agent: TargetApp) -> some View {
        let isOn = visibleAgents.contains(agent)
        let parentOn = allAIsTriState == .on
        HStack(spacing: 0) {
            SelectorRow(
                triState: isOn ? .on : .off,
                label: displayName(for: agent),
                isExplicitOverride: explicitAgents.contains(agent),
                tint: agentTint(for: agent),
                accessibilityIdentifier: accessibilityIDPrefix.map { "\($0).agent.\(agent.rawValue)" }
            ) {
                onToggleAgent(agent, isOn)
            }
            if parentOn && isOn {
                Text("via All")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Spacing.standard)
                    .accessibilityHidden(true)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, Spacing.standard)
        .background(
            parentOn
                ? agentTint(for: agent).opacity(Opacity.rowTint)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: Spacing.cornerSmall)
        )
    }

    @ViewBuilder
    private var liveLabel: some View {
        HStack(spacing: Spacing.standard) {
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .font(.caption)
                .accessibilityHidden(true)
            Text(currentLabel)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .id(currentLabel)
                .transition(.opacity)
        }
        .animation(Anim.micro, value: currentLabel)
    }

    // MARK: - Derived state

    private var showsAllAIsRow: Bool {
        connectedAgents.count >= 2
    }

    private var allAIsTriState: SharingTriState {
        guard !connectedAgents.isEmpty else { return .off }
        let onCount = connectedAgents.filter { visibleAgents.contains($0) }.count
        if onCount == connectedAgents.count { return .on }
        if onCount == 0 { return .off }
        return .mixed
    }

    private var currentLabel: String {
        guard !connectedAgents.isEmpty else { return "No AI connected" }
        let onAgents = connectedAgents.filter { visibleAgents.contains($0) }
        switch onAgents.count {
        case 0: return "Hidden from all"
        case connectedAgents.count: return connectedAgents.count == 1
            ? "Visible to \(displayName(for: connectedAgents[0]))"
            : "All AIs"
        case 1: return "\(displayName(for: onAgents[0])) only"
        default: return "Mixed sharing"
        }
    }

    // MARK: - Helpers

    private func agentTint(for agent: TargetApp) -> Color {
        switch agent {
        case .cowork: return .blue
        case .codex:  return .purple
        }
    }

    private func displayName(for agent: TargetApp) -> String {
        switch agent {
        case .cowork: return "Claude"
        case .codex:  return "Codex"
        }
    }
}

// MARK: - Row primitive

/// Renders a single line in the parent-child checkbox group. Uses Apple
/// SF Symbols for the tri-state glyph (square / checkmark.square.fill /
/// minus.square.fill) and an optional override underline that picks up
/// the agent's tint.
private struct SelectorRow: View {
    let triState: SharingTriState
    let label: String
    let isExplicitOverride: Bool
    let tint: Color
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.tight) {
                glyph
                    .frame(width: 14, height: 14)
                    .foregroundStyle(triState == .off ? Color.secondary : tint)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.primary)
                if isExplicitOverride {
                    Rectangle()
                        .fill(tint)
                        .frame(width: 12, height: 1)
                        .padding(.leading, 2)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var glyph: some View {
        switch triState {
        case .on:    Image(systemName: "checkmark.square.fill")
        case .off:   Image(systemName: "square")
        case .mixed: Image(systemName: "minus.square.fill")
        }
    }

    private var accessibilityValue: String {
        switch triState {
        case .on:    return "on"
        case .off:   return "off"
        case .mixed: return "mixed"
        }
    }
}

#Preview("Two AIs — Claude only") {
    InspectorSharingSelector(
        connectedAgents: [.cowork, .codex],
        visibleAgents: [.cowork],
        explicitAgents: [.codex],
        onToggleAgent: { _, _ in },
        onSetAllAgents: { _ in }
    )
    .padding()
    .frame(width: 320)
}

#Preview("Two AIs — All AIs") {
    InspectorSharingSelector(
        connectedAgents: [.cowork, .codex],
        visibleAgents: [.cowork, .codex],
        onToggleAgent: { _, _ in },
        onSetAllAgents: { _ in }
    )
    .padding()
    .frame(width: 320)
}

#Preview("Single AI connected") {
    InspectorSharingSelector(
        connectedAgents: [.cowork],
        visibleAgents: [],
        onToggleAgent: { _, _ in },
        onSetAllAgents: { _ in }
    )
    .padding()
    .frame(width: 320)
}

#Preview("No AIs connected") {
    InspectorSharingSelector(
        connectedAgents: [],
        visibleAgents: [],
        onToggleAgent: { _, _ in },
        onSetAllAgents: { _ in }
    )
    .padding()
    .frame(width: 320)
}
