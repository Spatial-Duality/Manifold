// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Standalone connection sheet for Codex — used from Settings > AI Apps.
/// Two footer buttons only (Cancel + Done). Same 460×420 size as Claude sheet.
struct ConnectCodexSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var addError: String?

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                title: "Connect Codex",
                subtitle: "Add Manifold to Codex MCP configuration and verify the local bridge.",
                agent: .codex
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    LiveCheckRow(
                        label: "Codex app installed",
                        status: store.integrationHealth.codex.codexAppInstalled,
                        action: { openWebPage("https://openai.com/index/introducing-codex/") },
                        actionLabel: "Install",
                        onRefresh: { await store.integrationHealth.checkCodex() }
                    )

                    LiveCheckRow(
                        label: "Manifold added",
                        status: store.integrationHealth.codex.mcpAdded,
                        action: {
                            adding = true
                            addError = nil
                            do {
                                let writer = ConfigWriter(
                                    binaryPath: ManifoldStore.mcpBinaryPath,
                                    homeDir: FileManager.default.homeDirectoryForCurrentUser
                                )
                                try writer.installCodex()
                                Task {
                                    await store.integrationHealth.checkCodex()
                                    adding = false
                                }
                            } catch {
                                addError = error.localizedDescription
                                adding = false
                            }
                        },
                        actionLabel: adding ? "Adding\u{2026}" : "Add to Codex",
                        onRefresh: { await store.integrationHealth.checkCodex() }
                    )

                    if let addError {
                        Label(addError, systemImage: "exclamationmark.triangle")
                            .font(ManifoldType.caption)
                            .foregroundStyle(ManifoldPalette.attention)
                    }

                    DisclosureGroup("Details") {
                        VStack(alignment: .leading, spacing: 4) {
                            DetailLine("Binary", value: ManifoldStore.mcpBinaryPath)
                            DetailLine("Config", value: "~/.codex/config.toml")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(Spacing.s5)
                .frame(maxWidth: 420, alignment: .leading)
            }
            .background(ManifoldPalette.bg)

            Divider()

            SettingsSheetFooter {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                if store.integrationHealth.codex.mcpAdded.isPassingCheck {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 460, height: 420)
        .task { await store.integrationHealth.checkCodex() }
    }

    private func openWebPage(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
