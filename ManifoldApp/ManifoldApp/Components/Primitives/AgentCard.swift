// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AgentCard — shared "here is Claude / here is Codex" identity + health
// card used in Settings → Agents. Can be adopted in the menu bar and
// Requests empty state later.
//
// Shape:
//   ┌─ GradientAvatar ─ name ────── status Pill ─┐
//   │  one-line consequence text                  │
//   ├─ checks (LiveCheckRow ×N) ─────────────────┤
//   │  optional error line                        │
//   └─────────────── primary action ▸────────────┘
//
// The `checks:` content closure takes a `@ViewBuilder` so callers can
// pass any combination of LiveCheckRow (or other primitives) without
// the card knowing the check semantics.

import SwiftUI
import ManifoldKit

/// Non-nested so callers can name it without spelling the generic
/// parameter of AgentCard. Mapped from domain status enums by consumers.
enum AgentCardStatus {
    case ok
    case needsSetup
    case error
    case offline

    var label: String {
        switch self {
        case .ok:         return "Connected"
        case .needsSetup: return "Set up"
        case .error:      return "Error"
        case .offline:    return "Offline"
        }
    }

    var pillVariant: Pill.Variant {
        switch self {
        case .ok:         return .session
        case .needsSetup: return .neutral
        case .error:      return .attention
        case .offline:    return .scope
        }
    }

    var dot: AgentStatusDot.Status {
        switch self {
        case .ok:         return .active
        case .needsSetup: return .offline
        case .error:      return .denied
        case .offline:    return .offline
        }
    }
}

struct AgentCardAction {
    let label: String
    let isDestructive: Bool
    let handler: () -> Void

    init(label: String, isDestructive: Bool = false, handler: @escaping () -> Void) {
        self.label = label
        self.isDestructive = isDestructive
        self.handler = handler
    }
}

struct AgentCard<Checks: View>: View {
    let agent: TargetApp
    let displayName: String
    let consequenceText: String?
    let status: AgentCardStatus
    var errorDetail: String? = nil
    var primaryAction: AgentCardAction? = nil
    @ViewBuilder let checks: Checks

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            header
            VStack(alignment: .leading, spacing: Spacing.s1) {
                checks
            }
            if let errorDetail {
                Text(errorDetail)
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let primaryAction {
                HStack {
                    Spacer()
                    Button(primaryAction.label, action: primaryAction.handler)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(primaryAction.isDestructive
                              ? ManifoldPalette.attention
                              : ManifoldPalette.agent(agent))
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            GradientAvatar(agent: agent, size: .large)
                .alignmentGuide(.firstTextBaseline) { dimension in
                    dimension[.bottom] - 6
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(ManifoldType.title)
                if let consequenceText {
                    Text(consequenceText)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Spacing.s2)

            Pill(
                text: status.label,
                variant: status.pillVariant,
                systemImage: status == .ok ? "checkmark" : nil
            )
        }
    }
}

#Preview("Agent cards — mixed states") {
    ScrollView {
        VStack(spacing: Spacing.s4) {
            AgentCard(
                agent: .cowork,
                displayName: "Claude",
                consequenceText: "Can see 4 folders · @work mail",
                status: .ok,
                primaryAction: AgentCardAction(label: "Reconnect", handler: {})
            ) {
                LiveCheckRow(label: "Claude Desktop installed",
                             status: .installed,
                             onRefresh: { })
                LiveCheckRow(label: "Claude Desktop configured",
                             status: .configured,
                             onRefresh: { })
            }
            .padding(Spacing.s4)
            .background(.quaternary.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: Spacing.r4))

            AgentCard(
                agent: .codex,
                displayName: "Codex",
                consequenceText: "Not configured yet",
                status: .needsSetup,
                primaryAction: AgentCardAction(label: "Set up Codex", handler: {})
            ) {
                LiveCheckRow(label: "Codex app installed",
                             status: .notInstalled,
                             onRefresh: { })
                LiveCheckRow(label: "Manifold added",
                             status: .unknown,
                             onRefresh: { })
            }
            .padding(Spacing.s4)
            .background(.quaternary.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: Spacing.r4))
        }
        .padding(Spacing.s6)
    }
    .frame(width: 520, height: 540)
}
