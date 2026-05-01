// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// GradientAvatar — agent identity tile used in rows, cards, and inspectors.
//
// Renders a rounded square with an agent-colored fill and the agent's
// product mark. Color is drawn from the fixed ManifoldPalette
// (Principle 6), never from system accent.
//
// A brand-gradient variant (Claude + Codex blended) is available for
// app-identity surfaces like AboutView and General settings.

import SwiftUI
import ManifoldKit

struct GradientAvatar: View {
    enum Size { case tiny, small, medium, large, extraLarge }

    enum Identity {
        case agent(TargetApp)
        /// Combined Claude + Codex gradient for app-brand surfaces.
        case brand
    }

    let identity: Identity
    var size: Size = .medium

    init(agent: TargetApp, size: Size = .medium) {
        self.identity = .agent(agent)
        self.size = size
    }

    init(brand: Bool, size: Size = .medium) {
        self.identity = brand ? .brand : .agent(.cowork)
        self.size = size
    }

    private var sideLength: CGFloat {
        switch size {
        case .tiny:       return 12
        case .small:      return 18
        case .medium:     return 24
        case .large:      return 32
        case .extraLarge: return 56
        }
    }

    private var iconFont: Font {
        switch size {
        case .tiny:       return .system(size: 7,  weight: .semibold)
        case .small:      return .system(size: 9,  weight: .semibold)
        case .medium:     return .system(size: 11, weight: .semibold)
        case .large:      return .system(size: 14, weight: .semibold)
        case .extraLarge: return .system(size: 24, weight: .semibold)
        }
    }

    private var logoLength: CGFloat {
        switch size {
        case .tiny:       return 8
        case .small:      return 12
        case .medium:     return 16
        case .large:      return 21
        case .extraLarge: return 37
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .tiny:       return 3
        case .small:      return 4
        case .medium:     return 5
        case .large:      return 7
        case .extraLarge: return 13
        }
    }

    private var gradientColors: [Color] {
        [ManifoldPalette.claude, ManifoldPalette.codex]
    }

    var body: some View {
        switch identity {
        case .agent(let agent):
            agentAvatar(agent)
        case .brand:
            brandAvatar
        }
    }

    private func agentAvatar(_ agent: TargetApp) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(ManifoldPalette.agentSoft(agent))
            .frame(width: sideLength, height: sideLength)
            .overlay(
                AgentLogo(agent: agent, size: logoLength)
                    .accessibilityHidden(true)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ManifoldPalette.agent(agent).opacity(0.18), lineWidth: 0.5)
            )
            .accessibilityLabel(AgentMeta.label(agent))
    }

    private var brandAvatar: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: sideLength, height: sideLength)
            .overlay(
                Image(systemName: "sparkle")
                    .font(iconFont)
                    .foregroundStyle(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                    .blendMode(.plusLighter)
            )
            .accessibilityLabel("Manifold")
    }
}

struct AgentLogo: View {
    enum Treatment {
        case adaptive
        case monochrome(Color)
    }

    let agent: TargetApp
    var size: CGFloat
    var treatment: Treatment = .adaptive

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        mark
            .frame(width: size, height: size)
            .accessibilityLabel(AgentMeta.label(agent))
    }

    @ViewBuilder
    private var mark: some View {
        switch treatment {
        case .adaptive:
            Image(AgentMeta.logoImageName(agent, colorScheme: colorScheme))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(AgentMeta.color(agent))
        case .monochrome(let color):
            Image(agent == .codex ? "AgentCodexLight" : "AgentClaude")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(color)
        }
    }
}

#Preview("Gradient avatars") {
    HStack(spacing: Spacing.s4) {
        VStack(spacing: Spacing.s2) {
            GradientAvatar(agent: .cowork, size: .small)
            GradientAvatar(agent: .cowork, size: .medium)
            GradientAvatar(agent: .cowork, size: .large)
            GradientAvatar(agent: .cowork, size: .extraLarge)
        }
        VStack(spacing: Spacing.s2) {
            GradientAvatar(agent: .codex, size: .small)
            GradientAvatar(agent: .codex, size: .medium)
            GradientAvatar(agent: .codex, size: .large)
            GradientAvatar(agent: .codex, size: .extraLarge)
        }
        VStack(spacing: Spacing.s2) {
            GradientAvatar(brand: true, size: .small)
            GradientAvatar(brand: true, size: .medium)
            GradientAvatar(brand: true, size: .large)
            GradientAvatar(brand: true, size: .extraLarge)
        }
    }
    .padding(Spacing.s6)
    .background(ManifoldPalette.bg)
}
