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

            Section("Notifications") {
                Toggle("Session start and finish", isOn: $store.notifyOnSessionEnd)
                Toggle("Access denied alerts", isOn: $store.notifyOnAccessDenied)
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
