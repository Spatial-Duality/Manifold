// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AccessCheckboxStrip — per-agent sharing controls.
//
// One native-sized strip is used in folder rows, file rows, mail rows, and
// inspectors so the trust decision is consistent everywhere: Both, Claude,
// Codex.

import Foundation
import SwiftUI
import ManifoldKit

struct AccessCheckboxStrip: View {
    static func compactWidth(agentCount: Int, showsAllControl: Bool = true) -> CGFloat {
        let allControlCount = showsAllControl && agentCount > 1 ? 1 : 0
        let controlCount = agentCount + allControlCount
        guard controlCount > 0 else { return 72 }

        let controlWidth: CGFloat = 34
        let spacing: CGFloat = 5
        return CGFloat(controlCount) * controlWidth + CGFloat(max(0, controlCount - 1)) * spacing
    }

    let agents: [TargetApp]
    let visibleAgents: Set<TargetApp>
    /// Agents whose state was set explicitly (.explicitAllow or
    /// .explicitDeny in the runtime's FileVisibilityEvaluationOrigin).
    /// Used to render a thin tinted underline beneath the chip so the
    /// user can tell at a glance which decisions were inherited vs
    /// manually overridden.
    var explicitOverrideAgents: Set<TargetApp> = []
    var showsAllControl = true
    var showsTitles = true
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
                        showsTitle: showsTitles,
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
                        agent: agent,
                        state: visible ? .on : .off,
                        tint: AgentMeta.color(agent),
                        isExplicitOverride: isOverride,
                        showsTitle: showsTitles,
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
    var agent: TargetApp? = nil
    let state: State
    let tint: Color
    var isExplicitOverride: Bool = false
    var showsTitle = true
    let accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    checkbox
                    if let agent {
                        AgentLogo(
                            agent: agent,
                            size: 10,
                            treatment: .monochrome(state == .off ? ManifoldPalette.text2 : tint)
                        )
                        .accessibilityHidden(true)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    if showsTitle {
                        Text(title)
                            .font(ManifoldType.captionMedium)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(state == .off ? ManifoldPalette.text2 : tint)
                .padding(.horizontal, showsTitle ? 4 : 2)
                .frame(height: 24)

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
        .controlSize(.small)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    private var checkbox: some View {
        switch state {
        case .on:
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 16, weight: .medium))
        case .mixed:
            Image(systemName: "minus.square.fill")
                .font(.system(size: 16, weight: .medium))
        case .off:
            Image(systemName: "square")
                .font(.system(size: 16, weight: .medium))
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

#Preview("Access checkbox strip") {
    VStack(spacing: Spacing.s3) {
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
