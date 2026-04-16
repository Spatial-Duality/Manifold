// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AgentBadgeButton — the single everywhere-available gesture for granting
// or revoking an agent's access to an item.
//
// This is the primitive that carries Principle 4 (scope as spatial primitive)
// and Principle 8 (direct manipulation). A CoverageDot reports state; this
// button *is* the state — clicking toggles the grant.
//
// Visual states:
//   - on      : agent color fill + white checkmark
//   - off     : hollow with dashed-border tint (reads "available, not set")
//   - partial : tinted fill with minus stripe (some children shared)
//
// Depth moves on hover so the control reads as interactive before clicking
// — per §2.5.4 of the design review, flat circles are the failure mode
// when the pixel doesn't promise its own interactivity.

import SwiftUI
import ManifoldKit

struct AgentBadgeButton: View {
    enum Mode: Equatable {
        /// Fully shared (or the explicit leaf grant is on).
        case on
        /// Not shared.
        case off
        /// Some descendants are shared but not all. Rendered as a minus.
        case partial
    }

    let agent: TargetApp
    let mode: Mode
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 18, height: 18)

                Circle()
                    .strokeBorder(strokeColor, style: strokeStyle)
                    .frame(width: 18, height: 18)

                glyph
            }
            .scaleEffect(isHovering && !reduceMotion ? 1.10 : 1.0)
            .animation(reduceMotion ? nil : .snappy(duration: 0.14), value: isHovering)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: mode)
            .contentShape(Rectangle())
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(mode == .on ? [.isButton, .isSelected] : .isButton)
        .help(helpText)
    }

    // MARK: - Visuals

    private var tint: Color { ManifoldPalette.agent(agent) }

    private var fillColor: Color {
        switch mode {
        case .on:      return tint
        case .partial: return tint.opacity(0.25)
        case .off:     return .clear
        }
    }

    private var strokeColor: Color {
        switch mode {
        case .on:      return tint.opacity(0.5)
        case .partial: return tint.opacity(0.8)
        case .off:     return isHovering ? tint.opacity(0.6) : ManifoldPalette.border2
        }
    }

    private var strokeStyle: StrokeStyle {
        switch mode {
        case .on:      return StrokeStyle(lineWidth: 0.6)
        case .partial: return StrokeStyle(lineWidth: 1.2, dash: [2, 2])
        case .off:     return StrokeStyle(lineWidth: 1.2)
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch mode {
        case .on:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        case .partial:
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
        case .off:
            EmptyView()
        }
    }

    // MARK: - A11y copy

    private var agentName: String {
        agent == .codex ? "Codex" : "Claude"
    }

    private var accessibilityLabel: String {
        switch mode {
        case .on:      return "Shared with \(agentName)"
        case .partial: return "Partially shared with \(agentName)"
        case .off:     return "Not shared with \(agentName)"
        }
    }

    private var accessibilityHint: String {
        switch mode {
        case .on:      return "Double-tap to revoke \(agentName)'s access"
        case .partial: return "Double-tap to share the whole item with \(agentName)"
        case .off:     return "Double-tap to share with \(agentName)"
        }
    }

    private var helpText: String {
        switch mode {
        case .on:      return "Revoke \(agentName)'s access"
        case .partial: return "\(agentName) can see some items here — click to share all"
        case .off:     return "Share with \(agentName)"
        }
    }
}

#Preview("Agent badge states") {
    HStack(spacing: 16) {
        AgentBadgeButton(agent: .cowork, mode: .on) {}
        AgentBadgeButton(agent: .cowork, mode: .partial) {}
        AgentBadgeButton(agent: .cowork, mode: .off) {}
        Divider().frame(height: 24)
        AgentBadgeButton(agent: .codex, mode: .on) {}
        AgentBadgeButton(agent: .codex, mode: .partial) {}
        AgentBadgeButton(agent: .codex, mode: .off) {}
    }
    .padding(24)
}
