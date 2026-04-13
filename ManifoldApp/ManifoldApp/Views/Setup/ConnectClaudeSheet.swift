// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Standalone connection sheet for Claude — used from Settings > AI Apps.
/// NOT used in the Setup Assistant (that uses inline checks).
/// Two footer buttons only (Cancel + Done). Inline ↻ refresh per failed check.
struct ConnectClaudeSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @State private var installing = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Circle().fill(Color.blue).frame(width: 12, height: 12)
                Text("Connect Claude").font(.title3.weight(.semibold))
            }
            .padding(.top, 24)

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                LiveCheckRow(
                    label: "Claude Desktop installed",
                    status: store.integrationHealth.claude.appInstalled,
                    action: { openWebPage("https://claude.ai/download") },
                    actionLabel: "Download",
                    onRefresh: { await store.integrationHealth.checkClaude() }
                )

                LiveCheckRow(
                    label: "Claude Desktop configured",
                    status: store.integrationHealth.claude.mcpConfigured,
                    action: {
                        installing = true
                        store.installMCP()
                        Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            await store.integrationHealth.checkClaude()
                            installing = false
                        }
                    },
                    actionLabel: installing ? "Installing\u{2026}" : "Install",
                    onRefresh: { await store.integrationHealth.checkClaude() }
                )

                LiveCheckRow(
                    label: "Claude Code configured",
                    status: store.integrationHealth.claude.claudeCodeConfigured,
                    action: {
                        installing = true
                        store.installMCP()
                        Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            await store.integrationHealth.checkClaude()
                            installing = false
                        }
                    },
                    actionLabel: installing ? "Installing\u{2026}" : "Install",
                    onRefresh: { await store.integrationHealth.checkClaude() }
                )

                LiveCheckRow(
                    label: "Connection verified",
                    status: store.integrationHealth.claude.connectionVerified,
                    onRefresh: { await store.integrationHealth.checkClaude() }
                )

                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 4) {
                        DetailLine("Binary", value: ManifoldStore.mcpBinaryPath)
                        DetailLine("Claude Desktop", value: "~/Library/Application Support/Claude/claude_desktop_config.json")
                        DetailLine("Claude Code", value: "~/.claude/settings.json")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 380)

            Spacer()

            // Footer — 2 buttons only (review fix)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if store.integrationHealth.claude.mcpConfigured.isPassingCheck
                    || store.integrationHealth.claude.claudeCodeConfigured.isPassingCheck {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 420)
        .task { await store.integrationHealth.checkAll(force: true) }
    }

    private func openWebPage(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
