// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// Pill — the small labeled chip used across the app.
//
// Replaces the bag of ad-hoc capsule styles in the old Badge/StatusBadge
// components. Pill has semantic variants (session/default/attention/
// scope/seeded/user/neutral) so callers don't pick colors manually.

import SwiftUI
import ManifoldKit

struct Pill: View {
    enum Variant {
        case session
        case defaultScope
        case attention
        case scope
        case seeded
        case user
        case agent(TargetApp)
        case preview
        case neutral

        var color: Color {
            switch self {
            case .session:       return ManifoldPalette.active
            case .defaultScope:  return ManifoldPalette.selection
            case .attention:     return ManifoldPalette.attention
            case .scope:         return ManifoldPalette.text2
            case .seeded:        return ManifoldPalette.paused
            case .user:          return ManifoldPalette.selection
            case .agent(let a):  return ManifoldPalette.agent(a)
            case .preview:       return ManifoldPalette.preview
            case .neutral:       return ManifoldPalette.text3
            }
        }
    }

    var backgroundOpacity: Double {
        switch variant {
        case .preview:
            return 0.16
        default:
            return 0.14
        }
    }

    let text: String
    var variant: Variant = .neutral
    var systemImage: String?
    var fills: Bool = false  // true → solid, false → tinted

    var body: some View {
        HStack(spacing: Spacing.s1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(ManifoldType.tiny)
                .textCase(.uppercase)
                .tracking(0.4)
        }
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, 2)
        .foregroundStyle(fills ? .white : variant.color)
        .background(
            Capsule(style: .continuous)
                .fill(fills ? variant.color : variant.color.opacity(backgroundOpacity))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(variant.color.opacity(fills ? 0 : 0.22), lineWidth: 0.5)
        )
        .accessibilityLabel(text)
    }
}

enum VisibilityEffectiveState: String, Hashable, Sendable {
    case allowed
    case hidden
    case mixed
}

enum VisibilityOrigin: String, Hashable, Sendable {
    case explicit
    case defaultScope
    case preview
}

struct VisibilityState: Hashable, Sendable {
    let effective: VisibilityEffectiveState
    let origin: VisibilityOrigin

    var label: String {
        switch (effective, origin) {
        case (.allowed, .explicit): return "Allowed"
        case (.allowed, .defaultScope): return "Inherited"
        case (.allowed, .preview): return "Preview"
        case (.hidden, .explicit): return "Denied"
        case (.hidden, .defaultScope): return "Hidden"
        case (.hidden, .preview): return "Preview"
        case (.mixed, _): return "Mixed"
        }
    }

    var detail: String {
        switch (effective, origin) {
        case (.allowed, .explicit): return "Explicitly shared"
        case (.allowed, .defaultScope): return "Inherited from default scope"
        case (.allowed, .preview): return "Preview-only allowance"
        case (.hidden, .explicit): return "Explicitly hidden"
        case (.hidden, .defaultScope): return "Hidden by default"
        case (.hidden, .preview): return "Preview-only hidden state"
        case (.mixed, _): return "Partially shared"
        }
    }

    var pillVariant: Pill.Variant {
        switch effective {
        case .allowed:
            return origin == .preview ? .preview : .defaultScope
        case .hidden:
            return origin == .explicit ? .attention : .neutral
        case .mixed:
            return .scope
        }
    }

    var icon: String {
        switch effective {
        case .allowed: return "eye"
        case .hidden: return "eye.slash"
        case .mixed: return "circle.lefthalf.filled"
        }
    }
}

struct VisibilityChip: View {
    let state: VisibilityState

    var body: some View {
        Pill(text: state.label, variant: state.pillVariant, systemImage: state.icon)
            .accessibilityLabel("\(state.label). \(state.detail)")
    }
}

#Preview("Pills") {
    HStack(spacing: Spacing.s2) {
        Pill(text: "session",  variant: .session,       systemImage: "play.fill")
        Pill(text: "default",  variant: .defaultScope)
        Pill(text: "blocked",  variant: .attention,     systemImage: "hand.raised")
        Pill(text: "~/Acme",   variant: .scope)
        Pill(text: "seeded",   variant: .seeded)
        Pill(text: "claude",   variant: .agent(.cowork))
        Pill(text: "codex",    variant: .agent(.codex), fills: true)
    }
    .padding(Spacing.s5)
    .background(ManifoldPalette.bg)
}
