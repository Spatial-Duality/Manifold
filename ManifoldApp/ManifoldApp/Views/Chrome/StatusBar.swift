// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// LedgerStatusBar — the always-visible honest-state strip at the bottom of the
// Ledger window.
//
// Principle 10: honesty outranks confidence. If the runtime isn't
// connected, this bar says so plainly (no green dot over an XPC failure).
// If it is, it names what the daemon is doing right now.

import SwiftUI
import ManifoldKit

struct LedgerStatusBar: View {
    @Environment(ManifoldStore.self) private var store

    private var status: (AgentStatusDot.Status, String) {
        // Errors are kept concise on the always-visible strip. The full
        // technical message lives in the Work surface's runtime issue
        // banner with a disclosure for details.
        if (store.runtimeLaunchError ?? store.lastError) != nil {
            return (.denied, "Runtime needs restart")
        }
        if !store.isRuntimeConnected {
            return (.offline, "Runtime unavailable")
        }
        if let summary = store.dataControlSummary {
            if summary.pendingApprovalCount > 0 {
                return (.paused, "\(summary.pendingApprovalCount) request\(summary.pendingApprovalCount == 1 ? "" : "s") waiting.")
            }
            if let block = summary.activeWorkBlock {
                return (.active, "\(AgentMeta.label(block.agent)) session live · \(block.sourceIDs.count) folder\(block.sourceIDs.count == 1 ? "" : "s")")
            }
            let agentLine = summary.agents.map { agent in
                let connection = agent.isPaused ? "paused" : (agent.isConnected ? "connected" : "offline")
                return "\(AgentMeta.label(agent.agent)) \(connection): \(agent.defaultFileScopeCount) folders/\(agent.visibleEmailCount) emails"
            }
            if !agentLine.isEmpty {
                return (summary.agents.allSatisfy(\.isPaused) ? .paused : .active, agentLine.joined(separator: " · "))
            }
        }
        if let session = store.activeSession {
            return (.active, "Session live · \(session.name)")
        }
        let agents = [store.isClaudeConnected ? "Claude" : nil, store.isCodexConnected ? "Codex" : nil]
            .compactMap { $0 }
        if agents.isEmpty {
            return (.paused, "No agents connected.")
        }
        return (.active, "\(agents.joined(separator: " · ")) connected · no session")
    }

    var body: some View {
        HStack(spacing: Spacing.s2) {
            AgentStatusDot(status: status.0, size: 7)
            Text(status.1)
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.text2)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if !store.isRuntimeConnected {
                Button("Restart helper") {
                    Task {
                        await store.restartRuntimeHelper()
                    }
                }
                .buttonStyle(.borderless)
                .font(ManifoldType.caption)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Runtime status: \(status.1)")
    }
}
