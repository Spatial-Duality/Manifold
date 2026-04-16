// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AdvancedSettingsPane — the Stage-3 "destination for engineering-flavored
// controls" pane. Landing here is a self-selection into diagnostics;
// normal users shouldn't need to visit this.
//
// Collects database paths, MCP binary location, and runtime connection
// diagnostics. The plain-language maintenance affordances (GC, integrity
// check) live in StorageSettingsPane — they were duplicated here in an
// earlier stage and that duplicate has been removed.

import SwiftUI
import ManifoldKit

struct AdvancedSettingsPane: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        Form {
            Section("Runtime") {
                LabeledContent("Status") {
                    HStack(spacing: Spacing.s1) {
                        AgentStatusDot(
                            status: store.isRuntimeConnected ? .active : .offline,
                            size: 7, pulses: false
                        )
                        Text(store.isRuntimeConnected ? "Connected" : "Not connected")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Connected agents") {
                    Text(store.connectedAgents.isEmpty
                         ? "none"
                         : store.connectedAgents.joined(separator: ", "))
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Reconnect runtime") {
                    Task {
                        store.registerAgent()
                        await store.refreshAll(force: true)
                    }
                }
                .controlSize(.small)
            }

            Section("Paths") {
                LabeledContent("Database") {
                    PathLabel(ManifoldStore.storeURL.path)
                }
                LabeledContent("MCP binary") {
                    PathLabel(ManifoldStore.mcpBinaryPath)
                }
                LabeledContent("Launch agent") {
                    PathLabel(ManifoldStore.launchAgentPlistURL.path)
                }
            }

            Section {
                Text("Landing here is a self-selection into engineering diagnostics. Plain-language controls live in the other panes; this one exists so you can see exactly what Manifold is doing on your Mac.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// PathLabel promoted to Components/Primitives/PathLabel.swift.
