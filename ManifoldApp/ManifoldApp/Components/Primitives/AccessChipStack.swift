// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AccessChipStack — compact per-agent sharing indicator.
//
// Renders one GradientAvatar-sized chip per agent. A filled chip means the
// agent can currently see the resource; a hollow chip means it cannot.
// Tapping a chip fires `onToggle(agent, wasVisible)` — the caller decides
// whether that edits a file override, a source scope, or something else.
//
// Used in the Files tab Access column and as the chip-cell fallback in
// the Scope matrix when more than four agents are connected.

import Foundation
import SwiftUI
import ManifoldKit

struct AccessChipStack: View {
    let agents: [TargetApp]
    let visibleAgents: Set<TargetApp>
    var accessibilityIDPrefix: String? = nil
    let onToggle: (TargetApp, Bool) -> Void

    var body: some View {
        HStack(spacing: 3) {
            if agents.isEmpty {
                Text("—")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(agents, id: \.self) { agent in
                    chip(for: agent)
                }
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func chip(for agent: TargetApp) -> some View {
        let visible = visibleAgents.contains(agent)
        let label = AgentMeta.label(agent)
        let tint = AgentMeta.color(agent)

        Button {
            onToggle(agent, visible)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(visible ? tint : Color.clear)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(visible ? tint.opacity(0.4) : ManifoldPalette.border2,
                                  lineWidth: visible ? 0.5 : 1)
                if visible {
                    Image(systemName: AgentMeta.systemImage(agent))
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .help(visible ? "Unshare from \(label)" : "Share with \(label)")
        .accessibilityLabel(visible ? "Shared with \(label). Click to unshare." : "Not shared with \(label). Click to share.")
        .accessibilityValue(visible ? "shared" : "not shared")
        .accessibilityIdentifier(accessibilityIDPrefix.map { "\($0).agent.\(agent.rawValue)" } ?? "")
    }
}

struct AccessCheckboxStrip: View {
    let agents: [TargetApp]
    let visibleAgents: Set<TargetApp>
    /// Agents whose state was set explicitly (.explicitAllow or
    /// .explicitDeny in the runtime's FileVisibilityEvaluationOrigin).
    /// Used to render a thin tinted underline beneath the chip so the
    /// user can tell at a glance which decisions were inherited vs
    /// manually overridden.
    var explicitOverrideAgents: Set<TargetApp> = []
    var showsAllControl = true
    var accessibilityIDPrefix: String? = nil
    let onToggleAgent: (TargetApp, Bool) -> Void
    let onSetAll: (Bool) -> Void

    private var allVisible: Bool {
        !agents.isEmpty && agents.allSatisfy { visibleAgents.contains($0) }
    }

    private var partiallyVisible: Bool {
        !visibleAgents.isEmpty && !allVisible
    }

    private var allLabel: String {
        agents.count == 2 ? "Both" : "All"
    }

    var body: some View {
        HStack(spacing: 5) {
            if agents.isEmpty {
                Text("No agents")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.tertiary)
            } else {
                if showsAllControl, agents.count > 1 {
                    AccessCheckButton(
                        title: allLabel,
                        systemImage: "person.2",
                        state: allVisible ? .on : (partiallyVisible ? .mixed : .off),
                        tint: ManifoldPalette.selection,
                        accessibilityIdentifier: accessibilityIDPrefix.map { "\($0).all" }
                    ) {
                        onSetAll(!allVisible)
                    }
                    .help(allVisible ? "Unshare from \(allLabel.lowercased())" : "Share with \(allLabel.lowercased())")
                }

                ForEach(agents, id: \.self) { agent in
                    let visible = visibleAgents.contains(agent)
                    let isOverride = explicitOverrideAgents.contains(agent)
                    AccessCheckButton(
                        title: AgentMeta.label(agent),
                        systemImage: AgentMeta.systemImage(agent),
                        state: visible ? .on : .off,
                        tint: AgentMeta.color(agent),
                        isExplicitOverride: isOverride,
                        accessibilityIdentifier: accessibilityIDPrefix.map { "\($0).agent.\(agent.rawValue)" }
                    ) {
                        onToggleAgent(agent, visible)
                    }
                    .help(helpText(agent: agent, visible: visible, isOverride: isOverride))
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func helpText(agent: TargetApp, visible: Bool, isOverride: Bool) -> String {
        let label = AgentMeta.label(agent)
        let action = visible ? "Unshare from \(label)" : "Share with \(label)"
        return isOverride ? "\(action) — explicit override" : action
    }
}

private struct AccessCheckButton: View {
    enum State {
        case off
        case on
        case mixed
    }

    let title: String
    let systemImage: String
    let state: State
    let tint: Color
    var isExplicitOverride: Bool = false
    let accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    checkbox
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                    Text(title)
                        .font(ManifoldType.tiny.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(state == .off ? ManifoldPalette.text2 : tint)
                .padding(.horizontal, 5)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.r2, style: .continuous)
                        .fill(state == .off ? ManifoldPalette.surface.opacity(0.55) : tint.opacity(0.13))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.r2, style: .continuous)
                        .strokeBorder(state == .off ? ManifoldPalette.border2 : tint.opacity(0.45), lineWidth: 0.8)
                )

                // Explicit-override underline. Renders only when the user
                // set this agent's state directly (not inherited from a
                // folder default). Picks up the agent's tint so it reads
                // as "you set this for this AI".
                if isExplicitOverride {
                    Rectangle()
                        .fill(tint)
                        .frame(height: 1.5)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                } else {
                    Color.clear.frame(height: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    private var checkbox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(state == .off ? ManifoldPalette.surface : tint)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(state == .off ? ManifoldPalette.border2 : tint.opacity(0.45), lineWidth: 0.8)
                )
                .frame(width: 13, height: 13)

            switch state {
            case .on:
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            case .mixed:
                Rectangle()
                    .fill(.white)
                    .frame(width: 7, height: 2)
            case .off:
                EmptyView()
            }
        }
    }

    private var accessibilityLabel: String {
        let suffix = isExplicitOverride ? " — explicit override" : ""
        switch state {
        case .on:
            return "\(title), shared\(suffix)"
        case .mixed:
            return "\(title), partially shared\(suffix)"
        case .off:
            return "\(title), not shared\(suffix)"
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .on:
            return "shared"
        case .mixed:
            return "partially shared"
        case .off:
            return "not shared"
        }
    }
}

extension String {
    var manifoldAccessIdentifierComponent: String {
        let allowed = CharacterSet.alphanumerics
        let mapped = unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(Character(scalar)).lowercased() : "-"
        }
        let collapsed = mapped
            .joined()
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "item" : collapsed
    }
}

#Preview("Access chip stack") {
    VStack(spacing: Spacing.s3) {
        AccessChipStack(
            agents: [.cowork, .codex],
            visibleAgents: [.cowork],
            onToggle: { _, _ in }
        )
        AccessChipStack(
            agents: [.cowork, .codex],
            visibleAgents: [.cowork, .codex],
            onToggle: { _, _ in }
        )
        AccessChipStack(
            agents: [.cowork, .codex],
            visibleAgents: [],
            onToggle: { _, _ in }
        )
        AccessChipStack(
            agents: [],
            visibleAgents: [],
            onToggle: { _, _ in }
        )
        AccessCheckboxStrip(
            agents: [.cowork, .codex],
            visibleAgents: [.cowork],
            onToggleAgent: { _, _ in },
            onSetAll: { _ in }
        )
    }
    .padding()
    .background(ManifoldPalette.bg)
}
