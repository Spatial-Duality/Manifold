// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// StatusBar — the always-visible honest-state strip at the bottom of the
// Ledger window.
//
// Principle 10: honesty outranks confidence. If the runtime isn't
// connected, this bar says so plainly (no green dot over an XPC failure).
// If it is, it names what the daemon is doing right now.

import SwiftUI
import ManifoldKit

struct StatusBar: View {
    @Environment(ManifoldStore.self) private var store

    private var status: (AgentStatusDot.Status, String) {
        if let error = store.runtimeLaunchError ?? store.lastError {
            return (.denied, error)
        }
        if !store.isRuntimeConnected {
            return (.offline, "Runtime is not connected. Check that ManifoldAgent is running.")
        }
        if let session = store.activeSession {
            if session.isTrackedEdit {
                return (.active, "Tracked session live · \(session.name)")
            }
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
                Button("Reconnect") {
                    Task {
                        store.registerAgent()
                        await store.refreshAll(force: true)
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
