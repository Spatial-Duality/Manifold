// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// The bulletproof selector control. Indented parent-child checkbox group
/// with reactive state, cascade animation, and a live state label.
///
/// Adaptive presentation:
///   - 0 connected agents → empty hero card with "Connect an AI to share"
///   - 1 connected agent  → single checkbox (no parent row, would be redundant)
///   - 2+ connected agents → parent ("All AIs") + indented children
///
/// State machine + transitions are owned by `SharingState`. This view is
/// purely presentational — it observes the model and forwards taps.
public struct SharingControl: View {
    @Bindable public var state: SharingState
    public var sourceDefaultDescription: String?
    public var onResetToDefault: (() -> Void)?

    public init(
        state: SharingState,
        sourceDefaultDescription: String? = nil,
        onResetToDefault: (() -> Void)? = nil
    ) {
        self.state = state
        self.sourceDefaultDescription = sourceDefaultDescription
        self.onResetToDefault = onResetToDefault
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            content
            liveLabel
            sourceDefault
        }
        .animation(Anim.stateChange, value: state.allAIsState)
        .animation(Anim.stateChange, value: state.agents.map(\.state))
    }

    // MARK: - Body parts

    @ViewBuilder
    private var content: some View {
        if state.connectedAgents.isEmpty {
            heroEmpty
        } else if state.showsAllAIsRow {
            parentChildGroup
        } else {
            singleAgentRow
        }
    }

    @ViewBuilder
    private var heroEmpty: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            Text("No agents connected")
                .font(.headline)
            Text("Connect Claude or Codex to start sharing files.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Spacing.standard)
    }

    @ViewBuilder
    private var singleAgentRow: some View {
        let agentState = state.agents[0]
        SharingRow(
            triState: agentState.state,
            label: SharingLabel.displayName(for: agentState.agent),
            isExplicitOverride: agentState.isExplicitOverride,
            tint: agentTint(for: agentState.agent)
        ) {
            state.toggleAgent(agentState.agent)
        }
    }

    @ViewBuilder
    private var parentChildGroup: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            // Parent row.
            SharingRow(
                triState: state.allAIsState,
                label: "All AIs",
                isExplicitOverride: false,
                tint: .accentColor
            ) {
                state.toggleAllAIs()
            }
            // Indented children. When parent is on, children get a soft
            // accent-tinted background so the user sees they're "covered
            // by All" rather than independently checked.
            VStack(alignment: .leading, spacing: Spacing.tight) {
                ForEach(state.agents) { agentState in
                    childRow(agentState)
                }
            }
            .padding(.leading, Spacing.large)
        }
    }

    @ViewBuilder
    private func childRow(_ agentState: SharingAgentState) -> some View {
        HStack(spacing: 0) {
            SharingRow(
                triState: agentState.state,
                label: SharingLabel.displayName(for: agentState.agent),
                isExplicitOverride: agentState.isExplicitOverride,
                tint: agentTint(for: agentState.agent)
            ) {
                state.toggleAgent(agentState.agent)
            }
            if state.allAIsState == .on && agentState.state == .on {
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
            // Soft "covered by All" tint when the parent is on.
            (state.allAIsState == .on)
                ? agentTint(for: agentState.agent).opacity(Opacity.rowTint)
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
            Text(state.label.text)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .id(state.label) // forces crossfade on label change
                .transition(.opacity)
        }
        .animation(Anim.micro, value: state.label)
    }

    @ViewBuilder
    private var sourceDefault: some View {
        if let description = sourceDefaultDescription {
            HStack(spacing: Spacing.standard) {
                Text("Source default · \(description)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let onReset = onResetToDefault {
                    Button(action: onReset) {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Reset to source default")
                }
                Spacer()
            }
        }
    }

    // MARK: - Tints

    private func agentTint(for agent: TargetApp) -> Color {
        switch agent {
        case .cowork: return .blue
        case .codex:  return .purple
        }
    }
}

// MARK: - Private row primitive

/// Parent-child indented checkbox row used by `SharingControl`. Action-based
/// (not binding-based) because state ownership lives in `SharingState`. The
/// existing `TriStateCheckbox` primitive in `Components/Primitives/` is
/// binding-based and shaped for the file tree, so we render our own glyph
/// here rather than fight that abstraction.
private struct SharingRow: View {
    let triState: SharingTriState
    let label: String
    let isExplicitOverride: Bool
    let tint: Color
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
    let s = SharingState(connectedAgents: [.cowork, .codex])
    s.setAgent(.cowork, state: .on, explicit: true)
    return SharingControl(
        state: s,
        sourceDefaultDescription: "Both agents (inherited from Project A)",
        onResetToDefault: {}
    )
    .padding()
    .frame(width: 320)
}

#Preview("Two AIs — All AIs") {
    let s = SharingState(connectedAgents: [.cowork, .codex])
    s.setAgent(.cowork, state: .on, explicit: false)
    s.setAgent(.codex, state: .on, explicit: false)
    return SharingControl(state: s, sourceDefaultDescription: "Both agents")
        .padding()
        .frame(width: 320)
}

#Preview("Single AI connected") {
    SharingControl(state: SharingState(connectedAgents: [.cowork]))
        .padding()
        .frame(width: 320)
}

#Preview("Multi-select — mixed") {
    let s = SharingState(connectedAgents: [.cowork, .codex], mode: .multi(itemCount: 3))
    s.setAgent(.cowork, state: .mixed)
    s.setAgent(.codex, state: .off)
    return SharingControl(state: s)
        .padding()
        .frame(width: 320)
}
