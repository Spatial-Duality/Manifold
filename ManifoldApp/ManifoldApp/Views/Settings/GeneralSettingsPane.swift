// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// GeneralSettingsPane — the first Settings tab.
//
// Stage-11 redesign: a small identity strip at the top (brand
// GradientAvatar + "Manifold" + version) followed by the usual
// launch / default-agent / notifications / privacy sections. All
// typography migrated from Typ.* to ManifoldType.*.

import SwiftUI
import ManifoldKit

struct GeneralSettingsPane: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        @Bindable var store = store
        @Bindable var diagnostics = store.diagnostics

        Form {
            Section {
                IdentityRow()
            }

            Section {
                Toggle("Launch at Login", isOn: $store.launchAtLogin)
            }

            Section("Sessions") {
                Picker("On launch", selection: $store.sessionStartupMode) {
                    ForEach(SessionStartupMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                if store.sessionStartupMode == .defaultSession {
                    Picker("Default agent", selection: $store.defaultSessionAgent) {
                        Text("Claude").tag(TargetApp.cowork)
                        Text("Codex").tag(TargetApp.codex)
                    }
                }
                Text("Sessions only gate access. Files written through Manifold stay in their original folders and are visible to any later session that has access to those folders.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Notifications") {
                Toggle("Session start and finish", isOn: $store.notifyOnSessionEnd)
                Toggle("Access denied alerts", isOn: $store.notifyOnAccessDenied)
            }

            Section("Updates & Diagnostics") {
                Toggle("Check for updates automatically", isOn: $diagnostics.updateChecksEnabled)
                Toggle("Share diagnostic reports", isOn: $diagnostics.diagnosticSharingEnabled)
                if diagnostics.diagnosticSharingEnabled {
                    HStack {
                        Text("Anonymous identifier")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(diagnostics.installID?.prefix(8).description ?? "—")
                            .font(ManifoldType.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        Button("Reset") { diagnostics.resetInstallID() }
                            .controlSize(.small)
                    }
                }
                Text("Diagnostic reports are kept on this Mac. Sending is manual — see the Advanced tab to preview, save, or send.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Data & Privacy") {
                Text("All governed data stays on your Mac. Manifold records what Claude and Codex saw through Manifold, not everything they can do outside that path.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

/// Small app-identity row matching Notes / Freeform's Settings top strip.
private struct IdentityRow: View {
    var body: some View {
        HStack(spacing: Spacing.s3) {
            GradientAvatar(brand: true, size: .extraLarge)

            VStack(alignment: .leading, spacing: 2) {
                Text("Manifold")
                    .font(ManifoldType.heading)
                Text("A local control layer for Claude and Codex through Manifold.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                Text("Version \(Bundle.main.shortVersionString)")
                    .font(ManifoldType.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, Spacing.s1)
    }
}
