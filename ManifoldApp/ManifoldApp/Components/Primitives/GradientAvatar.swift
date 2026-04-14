// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// GradientAvatar — agent identity tile used in rows, cards, and inspectors.
//
// Renders a rounded square with an agent-colored gradient fill and the
// agent's SF Symbol. Color is drawn from the fixed ManifoldPalette
// (Principle 6), never from system accent.

import SwiftUI
import ManifoldKit

struct GradientAvatar: View {
    enum Size { case small, medium, large }

    let agent: TargetApp
    var size: Size = .medium

    private var sideLength: CGFloat {
        switch size {
        case .small:  return 18
        case .medium: return 24
        case .large:  return 32
        }
    }

    private var iconFont: Font {
        switch size {
        case .small:  return .system(size: 9,  weight: .semibold)
        case .medium: return .system(size: 11, weight: .semibold)
        case .large:  return .system(size: 14, weight: .semibold)
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .small:  return 4
        case .medium: return 5
        case .large:  return 7
        }
    }

    private var symbolName: String {
        agent == .codex ? "chevron.left.forwardslash.chevron.right" : "sparkle"
    }

    private var agentColor: Color {
        ManifoldPalette.agent(agent)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [agentColor, agentColor.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: sideLength, height: sideLength)
            .overlay(
                Image(systemName: symbolName)
                    .font(iconFont)
                    .foregroundStyle(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                    .blendMode(.plusLighter)
            )
            .accessibilityLabel(agent == .codex ? "Codex" : "Claude")
    }
}

#Preview("Gradient avatars") {
    HStack(spacing: Spacing.s4) {
        VStack(spacing: Spacing.s2) {
            GradientAvatar(agent: .cowork, size: .small)
            GradientAvatar(agent: .cowork, size: .medium)
            GradientAvatar(agent: .cowork, size: .large)
        }
        VStack(spacing: Spacing.s2) {
            GradientAvatar(agent: .codex, size: .small)
            GradientAvatar(agent: .codex, size: .medium)
            GradientAvatar(agent: .codex, size: .large)
        }
    }
    .padding(Spacing.s6)
    .background(ManifoldPalette.bg)
}
