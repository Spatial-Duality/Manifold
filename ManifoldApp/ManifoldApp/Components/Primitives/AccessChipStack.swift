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

import SwiftUI
import ManifoldKit

struct AccessChipStack: View {
    let agents: [TargetApp]
    let visibleAgents: Set<TargetApp>
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
    }
    .padding()
    .background(ManifoldPalette.bg)
}
