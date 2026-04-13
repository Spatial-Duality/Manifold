// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct GeneralSettingsPane: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        @Bindable var store = store

        Form {
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
                    .font(Typ.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
