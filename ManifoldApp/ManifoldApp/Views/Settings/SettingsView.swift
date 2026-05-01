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
        .frame(minWidth: 720, minHeight: 600)
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
        content()
            .background(ManifoldPalette.bg)
            .accessibilityElement(children: .contain)
    }
}

private enum SettingsPane: String {
    case general
    case agents
    case storage
    case mail
    case privacy
    case sessions
    case advanced
}

struct SettingsSheetHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    var agent: TargetApp?

    init(title: String, subtitle: String, systemImage: String, accent: Color) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accent = accent
        self.agent = nil
    }

    init(title: String, subtitle: String, agent: TargetApp) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = AgentMeta.systemImage(agent)
        self.accent = AgentMeta.color(agent)
        self.agent = agent
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s3) {
            if let agent {
                SettingsAgentTile(agent: agent, accent: accent, size: 44)
            } else {
                SettingsSymbolTile(systemImage: systemImage, accent: accent, size: 44)
            }

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

struct SettingsAgentTile: View {
    let agent: TargetApp
    let accent: Color
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(accent.opacity(0.14))
            AgentLogo(agent: agent, size: size * 0.58)
                .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(accent.opacity(0.18), lineWidth: 0.5)
        )
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

