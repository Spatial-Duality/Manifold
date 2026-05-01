// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ConnectAgentPanel — R2 onboarding refinement.
//
// Closes the gap where the original 5-panel first-run wizard never
// mentioned Claude or Codex setup, leaving fresh users to land in
// WorkView empty-state and discover Settings → Agents on their own.
// Apple HIG → Onboarding: "An effective onboarding experience welcomes
// new people, helps them learn the most important features, and makes
// them feel comfortable using your app." Apple Mail's account-add
// wizard includes setup as a wizard step, not a post-hoc prompt.
//
// Design call: this panel reuses the existing ConnectClaudeSheet /
// ConnectCodexSheet rather than embedding their content inline. Two
// reasons:
//   1. The sheets already implement the guided state-machine flow
//      (R1 in the prior plan), including programmatic Claude restart.
//      Embedding would duplicate that surface.
//   2. The sheet presentation gives users an explicit "I'm in setup"
//      mode that they can dismiss at any time. The panel is the entry
//      point; the sheet is the work.

import SwiftUI
import ManifoldKit

struct ConnectAgentPanel: View {
    @Environment(ManifoldStore.self) private var store
    let finish: () -> Void
    let back: () -> Void

    @State private var showClaudeSheet = false
    @State private var showCodexSheet = false

    private var claudeConnected: Bool { store.isClaudeConnected }
    private var codexConnected: Bool { store.isCodexConnected }
    private var anyAgentConnected: Bool { claudeConnected || codexConnected }

    var body: some View {
        AtmosphericBackground(meshOnly: true) {
            VStack(spacing: Spacing.s6) {
                Spacer()

                VStack(spacing: Spacing.s3) {
                    Text("Connect an agent")
                        .font(ManifoldType.display)
                        .multilineTextAlignment(.center)
                    Text("Manifold governs what Claude and Codex see. Connect one or both now to start sharing — or skip and set them up later in Settings → Agents.")
                        .font(ManifoldType.body)
                        .foregroundStyle(ManifoldPalette.text2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Spacing.s4) {
                    AgentChoiceCard(
                        agent: .cowork,
                        title: "Claude",
                        subtitle: "Claude Desktop + Claude Code",
                        isConnected: claudeConnected,
                        action: { showClaudeSheet = true }
                    )
                    AgentChoiceCard(
                        agent: .codex,
                        title: "Codex",
                        subtitle: "OpenAI Codex CLI",
                        isConnected: codexConnected,
                        action: { showCodexSheet = true }
                    )
                }
                .frame(maxWidth: 540)

                Spacer()

                HStack(spacing: Spacing.s3) {
                    Button("Back", action: back)
                        .buttonStyle(.bordered)
                    Spacer()
                    Button(anyAgentConnected ? "Continue" : "Skip for now") { finish() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("onboarding.connectAgent.continue")
                }
                .frame(maxWidth: 540)
            }
            .padding(Spacing.s6)
        }
        .sheet(isPresented: $showClaudeSheet) {
            ConnectClaudeSheet().environment(store)
        }
        .sheet(isPresented: $showCodexSheet) {
            ConnectCodexSheet().environment(store)
        }
        .accessibilityIdentifier("onboarding.panel.connectAgent")
    }
}

private struct AgentChoiceCard: View {
    let agent: TargetApp
    let title: String
    let subtitle: String
    let isConnected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                HStack(spacing: Spacing.s2) {
                    AgentLogo(agent: agent, size: 28)
                    Text(title)
                        .font(ManifoldType.heading)
                        .foregroundStyle(ManifoldPalette.text)
                    Spacer()
                    if isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ManifoldPalette.active)
                    }
                }
                Text(subtitle)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(isConnected ? "Connected" : "Set up")
                        .font(ManifoldType.captionMedium)
                        .foregroundStyle(isConnected ? ManifoldPalette.active : AgentMeta.color(agent))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .fill(ManifoldPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .strokeBorder(
                        isConnected ? ManifoldPalette.active.opacity(0.4) : ManifoldPalette.border,
                        lineWidth: 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.connectAgent.\(agent.rawValue)")
    }
}
