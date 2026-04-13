// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// First-run setup assistant for connecting apps and choosing the first governed data sources.
struct SetupAssistantView: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen: SetupScreen = .welcome

    enum SetupScreen: Int, CaseIterable {
        case welcome = 0, connectApps = 1, addData = 2, reviewFinish = 3

        var label: String {
            switch self {
            case .welcome: "Welcome"
            case .connectApps: "Connect"
            case .addData: "Data"
            case .reviewFinish: "Done"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator with labels
            HStack(spacing: 4) {
                ForEach(SetupScreen.allCases, id: \.rawValue) { s in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(s.rawValue <= screen.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                        if s == screen {
                            Text(s.label)
                                .font(Typ.caption.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                    }
                    if s.rawValue < SetupScreen.allCases.count - 1 {
                        Rectangle()
                            .fill(s.rawValue < screen.rawValue ? Color.accentColor : Color.gray.opacity(0.2))
                            .frame(width: 20, height: 1)
                    }
                }
            }
            .padding(.top, 20)
            .accessibilityLabel("Step \(screen.rawValue + 1) of \(SetupScreen.allCases.count): \(screen.label)")

            Spacer()

            Group {
                switch screen {
                case .welcome: WelcomeScreen(advance: advance)
                case .connectApps: ConnectAppsScreen(advance: advance, skip: advance)
                case .addData: AddDataScreen(advance: advance, skip: advance)
                case .reviewFinish: ReviewFinishScreen(finish: finish)
                }
            }
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()

            if screen.rawValue > 0 && screen != .reviewFinish {
                HStack {
                    Button("Back") {
                        withAnimation(reduceMotion ? .none : .spring) {
                            screen = SetupScreen(rawValue: screen.rawValue - 1) ?? .welcome
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 580, height: 500)
        .interactiveDismissDisabled(screen != .reviewFinish)
        .accessibilityIdentifier("setup.assistant")
    }

    private func advance() {
        withAnimation(reduceMotion ? .none : .spring) {
            if let next = SetupScreen(rawValue: screen.rawValue + 1) { screen = next }
        }
    }

    private func finish() {
        store.hasCompletedOnboarding = true
        dismiss()
    }
}

// MARK: - Screen 1: Welcome

private struct WelcomeScreen: View {
    let advance: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Control what Claude and Codex can see on your Mac.")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("setup.welcome.title")

            Text("Choose the files and email access you want to share. Reads are recorded, and edits stay reviewable.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("setup.welcome.subtitle")

            Button("Get Started") { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("setup.welcome.continue")
        }
        .padding(.horizontal, 48)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setup.welcome.screen")
    }
}

// MARK: - Screen 2: Connect Apps (Inline — no nested sheets)

private struct ConnectAppsScreen: View {
    let advance: () -> Void
    let skip: () -> Void
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(spacing: 20) {
            Text("Connect your AI apps")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("setup.connect.title")

            Text("Add Manifold to Claude Desktop, Codex, or both. You can always reconnect them later in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                // Claude — inline checks
                InlineAgentCard(
                    agentName: "Claude",
                    agentColor: .blue,
                    checks: [
                        CheckRow("Claude Desktop installed", status: store.integrationHealth.claude.appInstalled),
                        CheckRow("Claude Desktop configured", status: store.integrationHealth.claude.mcpConfigured),
                        CheckRow("Claude Code configured", status: store.integrationHealth.claude.claudeCodeConfigured),
                        CheckRow("Connection verified", status: store.integrationHealth.claude.connectionVerified),
                    ]
                )
                .accessibilityIdentifier("setup.connect.claudeCard")

                // Codex — inline checks
                InlineAgentCard(
                    agentName: "Codex",
                    agentColor: .purple,
                    checks: [
                        CheckRow("Codex app installed", status: store.integrationHealth.codex.codexAppInstalled),
                        CheckRow("Manifold added", status: store.integrationHealth.codex.mcpAdded),
                    ]
                )
                .accessibilityIdentifier("setup.connect.codexCard")
            }
            .frame(maxWidth: 440)

            Button("Install or Repair Manifold MCP") {
                store.installMCP()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("setup.connect.installMCP")

            if store.integrationHealth.claude.overallStatus != .notInstalled
                || store.integrationHealth.codex.overallStatus != .notInstalled {
                Button("Continue") { advance() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("setup.connect.continue")
            }

            Button("Skip, I'll do this later") { skip() }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("setup.connect.skip")
        }
        .padding(.horizontal, 32)
        .task { await store.integrationHealth.checkAll(force: true) }
    }
}

private struct InlineAgentCard: View {
    let agentName: String
    let agentColor: Color
    let checks: [CheckRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(agentColor).frame(width: 8, height: 8)
                Text(agentName).font(.callout.weight(.medium))
            }

            ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                check
            }
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}

// MARK: - Screen 3: Add Data

private struct AddDataScreen: View {
    let advance: () -> Void
    let skip: () -> Void
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(spacing: 20) {
            Text("Choose files and email")
                .font(.title2.weight(.semibold))

            Text("Only the folders and email sources you add here can be shared with Claude or Codex through Manifold.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                // Folders
                VStack(alignment: .leading, spacing: 8) {
                    Label("Folders", systemImage: "folder")
                        .font(.callout.weight(.medium))

                    ForEach(store.sources.filter { !$0.isRemoved }, id: \.sourceID) { source in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .imageScale(.small)
                            Text(source.displayName)
                                .font(.caption)
                        }
                    }

                    Button("Add Folders\u{2026}") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = true
                        panel.message = "Select folders to share with AI agents"
                        panel.prompt = "Add"
                        if panel.runModal() == .OK {
                            for url in panel.urls {
                                store.addSource(path: url.path)
                            }
                        }
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("setup.data.addFolders")
                }

                Divider()

                // Email
                VStack(alignment: .leading, spacing: 8) {
                    Label("Email", systemImage: "envelope")
                        .font(.callout.weight(.medium))

                    ForEach(store.emailAccounts.accounts) { account in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .imageScale(.small)
                            Text(account.displayName).font(.caption)
                        }
                    }

                    Button("Add Email Account\u{2026}") {
                        // Opens standard email setup
                    }
                    .controlSize(.small)
                }
            }
            .padding(20)
            .frame(maxWidth: 400)
            .background(.background, in: .rect(cornerRadius: 10))

            if !store.sources.filter({ !$0.isRemoved }).isEmpty || !store.emailAccounts.accounts.isEmpty {
                Button("Continue") { advance() }
                    .buttonStyle(.borderedProminent)
            }

            Button("Skip for now") { skip() }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Screen 4: Review & Finish

private struct ReviewFinishScreen: View {
    let finish: () -> Void
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("You're ready.")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                SummaryRow(
                    label: "AI Apps",
                    detail: agentSummary,
                    done: store.integrationHealth.claude.overallStatus != .notInstalled
                        || store.integrationHealth.codex.overallStatus != .notInstalled
                )
                SummaryRow(
                    label: "Folders",
                    detail: "\(store.sources.filter { !$0.isRemoved }.count) added",
                    done: !store.sources.filter({ !$0.isRemoved }).isEmpty
                )
                SummaryRow(
                    label: "Email",
                    detail: "\(store.emailAccounts.accounts.count) account\(store.emailAccounts.accounts.count == 1 ? "" : "s")",
                    done: !store.emailAccounts.accounts.isEmpty
                )
            }
            .frame(maxWidth: 360)

            Text("You can change all of this anytime in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Done") { finish() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(.horizontal, 48)
    }

    private var agentSummary: String {
        var parts: [String] = []
        if store.integrationHealth.claude.overallStatus != .notInstalled { parts.append("Claude") }
        if store.integrationHealth.codex.overallStatus != .notInstalled { parts.append("Codex") }
        return parts.isEmpty ? "Not configured" : parts.joined(separator: " + ")
    }
}

private struct SummaryRow: View {
    let label: String
    let detail: String
    let done: Bool

    var body: some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
            Text(label).font(.callout.weight(.medium))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
