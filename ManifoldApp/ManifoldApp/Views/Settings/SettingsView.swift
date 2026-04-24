// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Settings window — General / Agents / Storage / Mail / Advanced.
/// Stage-3 structure. Normal users stay in the first four panes; the
/// Advanced pane is a destination, never a gate.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane()
                    .accessibilityIdentifier("settings.tab.general")
            }
            Tab("Agents", systemImage: "sparkle") {
                AgentsSettingsPane()
                    .accessibilityIdentifier("settings.tab.agents")
            }
            Tab("Storage", systemImage: "externaldrive") {
                StorageSettingsPane()
                    .accessibilityIdentifier("settings.tab.storage")
            }
            Tab("Mail", systemImage: "envelope") {
                MailSettingsPane()
                    .accessibilityIdentifier("settings.tab.mail")
            }
            Tab("Rules", systemImage: "checklist") {
                RulesSettingsPane()
                    .accessibilityIdentifier("settings.tab.rules")
            }
            Tab("Privacy", systemImage: "shield.checkered") {
                PrivacySettingsPane()
                    .accessibilityIdentifier("settings.tab.privacy")
            }
            Tab("Advanced", systemImage: "slider.horizontal.3") {
                AdvancedSettingsPane()
                    .accessibilityIdentifier("settings.tab.advanced")
            }
        }
        .frame(minWidth: 580, minHeight: 500)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.window")
    }
}

private struct RulesSettingsPane: View {
    @Environment(ManifoldStore.self) private var store
    @State private var isResetting = false
    @State private var resetMessage: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: Spacing.s3) {
                    Image(systemName: "checklist")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rules live in the Ledger")
                            .font(ManifoldType.bodyMedium)
                        Text("Create, edit, and audit rules from Ledger ▸ Rules. This pane covers global defaults only.")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            Section("Default policy") {
                LabeledContent("Claude (cowork)") {
                    Text(defaultPolicyDescription(.cowork))
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Codex") {
                    Text(defaultPolicyDescription(.codex))
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Default policy applies when no rule matches. Claude allows-unless-blocked (fast iteration); Codex blocks-unless-allowed (security-first). These baselines are the floor — rules refine what each agent sees.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Seeded rules") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restore built-in rules")
                            .font(ManifoldType.body)
                        Text("Re-enables seeded rules that you disabled and resyncs their catalog after an app update.")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Reset Seeded Rules") {
                        Task {
                            isResetting = true
                            defer { isResetting = false }
                            await store.rules.resetSeededRules()
                            resetMessage = "Seeded rules restored."
                        }
                    }
                    .disabled(isResetting)
                }
                if let resetMessage {
                    Label(resetMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(ManifoldPalette.active)
                        .font(ManifoldType.caption)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func defaultPolicyDescription(_ agent: TargetApp) -> String {
        switch agent {
        case .cowork: return "Allow unless blocked"
        case .codex:  return "Block unless allowed"
        }
    }
}
