// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Settings window — a native macOS Settings scene with stable panes.
/// Keep broad, infrequently changed preferences here; task-specific controls
/// stay in the Work / Access / Mail / Rules surfaces they affect.
struct SettingsView: View {
    @Environment(ManifoldStore.self) private var store

    @SceneStorage("manifold.settings.selectedPane")
    private var selectedPaneRawValue = SettingsPane.general.rawValue

    @State private var mailAccountSheetPresented = false

    var body: some View {
        TabView(selection: $selectedPaneRawValue) {
            Tab("General", systemImage: "gearshape", value: SettingsPane.general.rawValue) {
                pane(.general) {
                    GeneralSettingsPane()
                        .accessibilityIdentifier("settings.tab.general")
                }
            }
            Tab("Agents", systemImage: "sparkle", value: SettingsPane.agents.rawValue) {
                pane(.agents) {
                    AgentsSettingsPane()
                        .accessibilityIdentifier("settings.tab.agents")
                }
            }
            Tab("Storage", systemImage: "externaldrive", value: SettingsPane.storage.rawValue) {
                pane(.storage) {
                    StorageSettingsPane()
                        .accessibilityIdentifier("settings.tab.storage")
                }
            }
            Tab("Mail", systemImage: "envelope", value: SettingsPane.mail.rawValue) {
                pane(.mail) {
                    MailSettingsPane(addAccountSheetPresented: $mailAccountSheetPresented)
                        .accessibilityIdentifier("settings.tab.mail")
                }
            }
            Tab("Rules", systemImage: "checklist", value: SettingsPane.rules.rawValue) {
                pane(.rules) {
                    RulesSettingsPane()
                        .accessibilityIdentifier("settings.tab.rules")
                }
            }
            Tab("Privacy", systemImage: "shield.checkered", value: SettingsPane.privacy.rawValue) {
                pane(.privacy) {
                    PrivacySettingsPane()
                        .accessibilityIdentifier("settings.tab.privacy")
                }
            }
            Tab("Sessions", systemImage: "person.badge.clock", value: SettingsPane.sessions.rawValue) {
                pane(.sessions) {
                    SessionsSettingsPane()
                        .accessibilityIdentifier("settings.tab.sessions")
                }
            }
            Tab("Advanced", systemImage: "slider.horizontal.3", value: SettingsPane.advanced.rawValue) {
                pane(.advanced) {
                    AdvancedSettingsPane()
                        .accessibilityIdentifier("settings.tab.advanced")
                }
            }
        }
        .frame(minWidth: 680, minHeight: 560)
        .onAppear {
            guard SettingsPane(rawValue: selectedPaneRawValue) != nil else {
                selectedPaneRawValue = SettingsPane.general.rawValue
                return
            }
        }
        .sheet(isPresented: $mailAccountSheetPresented) {
            AddMailAccountSheet()
                .environment(store)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.window")
    }

    @ViewBuilder
    private func pane<Content: View>(
        _ pane: SettingsPane,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsPaneChrome(pane: pane, content: content)
    }
}

private enum SettingsPane: String {
    case general
    case agents
    case storage
    case mail
    case rules
    case privacy
    case sessions
    case advanced

    var title: String {
        switch self {
        case .general: return "General"
        case .agents: return "Agents"
        case .storage: return "Storage"
        case .mail: return "Mail"
        case .rules: return "Rules"
        case .privacy: return "Privacy"
        case .sessions: return "Sessions"
        case .advanced: return "Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Launch behavior, notifications, diagnostics, and local privacy."
        case .agents:
            return "Connection health and per-agent access recording defaults."
        case .storage:
            return "Local storage usage and safe maintenance tasks."
        case .mail:
            return "Mailbox connections, sync state, and local backup totals."
        case .rules:
            return "Global rule defaults and the built-in rule catalog."
        case .privacy:
            return "Sensitive-content scanning, identity records, and allowlists."
        case .sessions:
            return "Saved scopes for repeatable assistant sessions."
        case .advanced:
            return "Runtime paths, helper diagnostics, and local reports."
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .agents: return "sparkle"
        case .storage: return "externaldrive"
        case .mail: return "envelope"
        case .rules: return "checklist"
        case .privacy: return "shield.checkered"
        case .sessions: return "person.badge.clock"
        case .advanced: return "slider.horizontal.3"
        }
    }

    var accent: Color {
        switch self {
        case .general: return ManifoldPalette.brand
        case .agents: return ManifoldPalette.codex
        case .storage: return ManifoldPalette.selection
        case .mail: return ManifoldPalette.claude
        case .rules: return ManifoldPalette.active
        case .privacy: return ManifoldPalette.attention
        case .sessions: return ManifoldPalette.preview
        case .advanced: return ManifoldPalette.text2
        }
    }
}

private struct SettingsPaneChrome<Content: View>: View {
    let pane: SettingsPane
    let content: Content

    init(pane: SettingsPane, @ViewBuilder content: () -> Content) {
        self.pane = pane
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(pane: pane)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ManifoldPalette.bg)
        .accessibilityElement(children: .contain)
    }
}

private struct SettingsPaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .fill(pane.accent.opacity(0.14))
                Image(systemName: pane.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(pane.accent)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .strokeBorder(pane.accent.opacity(0.18), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(pane.title)
                    .font(ManifoldType.heading)
                    .foregroundStyle(ManifoldPalette.text)
                Text(pane.subtitle)
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.s6)
        .padding(.vertical, Spacing.s4)
        .background(ManifoldPalette.surface)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsSheetHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s3) {
            SettingsSymbolTile(systemImage: systemImage, accent: accent, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ManifoldType.heading)
                    .foregroundStyle(ManifoldPalette.text)
                Text(subtitle)
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.s5)
        .padding(.vertical, Spacing.s4)
        .background(ManifoldPalette.surface)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsSheetFooter<Actions: View>: View {
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack {
            Spacer()
            actions()
        }
        .padding(.horizontal, Spacing.s5)
        .padding(.vertical, Spacing.s4)
        .background(ManifoldPalette.surface)
    }
}

struct SettingsSymbolTile: View {
    let systemImage: String
    let accent: Color
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(accent.opacity(0.14))
            Image(systemName: systemImage)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(accent)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(accent.opacity(0.18), lineWidth: 0.5)
        )
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
