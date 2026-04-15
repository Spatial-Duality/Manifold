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

        Form {
            Section {
                IdentityRow()
            }

            Section {
                Toggle("Launch at Login", isOn: $store.launchAtLogin)
            }

            Section("Default Agent") {
                Picker("Show access for", selection: $store.agentFocus) {
                    Text("Claude").tag(AgentFocus.claude)
                    Text("Codex").tag(AgentFocus.codex)
                    Text("Compare").tag(AgentFocus.compare)
                }
                .pickerStyle(.menu)
            }

            Section("Notifications") {
                Toggle("Agent connect and disconnect", isOn: $store.notifyOnSessionEnd)
                Toggle("Access denied alerts", isOn: $store.notifyOnAccessDenied)
            }

            Section("Data & Privacy") {
                Text("All data stays on your Mac. Manifold never sends your files or emails to any server.")
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
                Text("A trust layer for your AI agents.")
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
