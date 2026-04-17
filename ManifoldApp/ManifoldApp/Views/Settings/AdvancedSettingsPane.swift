// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AdvancedSettingsPane — the Stage-3 "destination for engineering-flavored
// controls" pane. Landing here is a self-selection into diagnostics;
// normal users shouldn't need to visit this.
//
// Collects database paths, MCP binary location, runtime connection
// diagnostics, and maintenance actions (GC, integrity check) that used
// to live under Storage.

import SwiftUI
import ManifoldKit

struct AdvancedSettingsPane: View {
    @Environment(ManifoldStore.self) var store
    @State private var gcResult: Int?
    @State private var integrityResult: Bool?

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

            Section("Maintenance") {
                HStack {
                    Button("Clean up orphan blobs") {
                        Task { gcResult = await store.runGarbageCollection() }
                    }
                    .controlSize(.small)
                    if let gc = gcResult {
                        Text(gc > 0 ? "Removed \(gc) orphaned blobs" : "Nothing to clean up")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Verify database") {
                        Task { integrityResult = await store.runIntegrityCheck() }
                    }
                    .controlSize(.small)
                    if let ok = integrityResult {
                        Label(ok ? "Database OK" : "Issues found",
                              systemImage: ok ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(ManifoldType.caption)
                            .foregroundStyle(ok ? ManifoldPalette.active : ManifoldPalette.attention)
                    }
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
