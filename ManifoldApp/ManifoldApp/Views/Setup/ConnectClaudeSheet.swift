// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ConnectClaudeSheet — guided state-machine setup for Claude.
//
// Replaces the previous parallel-checklist with a single-action flow:
// the sheet shows ONE next step at a time and adapts as state advances.
// Mirrors Apple Mail's account-add pattern. The state machine consumes
// `IntegrationHealthModel.claude` and `ManifoldStore.connectedAgents`
// as the source of truth, deriving the active step automatically.
//
// States:
//   1. needsClaudeApp        → "Download Claude Desktop" (link out)
//   2. needsConfig           → "Install Manifold for Claude" (writes both
//                              Desktop + Code configs, atomic)
//   3. needsRestart          → "Restart Claude Desktop" (programmatic via
//                              ClaudeRelauncher; user gets the standard
//                              macOS quit confirmation)
//   4. waitingForConnection  → spinner + "Waiting for Claude to connect…"
//                              with a Quit-Claude escape hatch
//   5. connected             → green check + Done

import SwiftUI
import ManifoldKit

struct ConnectClaudeSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @State private var isInstalling = false
    @State private var isRestarting = false
    @State private var isUninstalling = false
    @State private var actionError: String?
    @State private var lastInstallAt: Date?
    @State private var showUninstallConfirm = false

    fileprivate enum Step: Equatable {
        case needsClaudeApp
        case needsConfig
        case needsRestart
        case waitingForConnection
        case connected
    }

    private var step: Step {
        let h = store.integrationHealth.claude
        if h.appInstalled != .installed { return .needsClaudeApp }
        if !h.mcpConfigured.isPassingCheck && !h.claudeCodeConfigured.isPassingCheck {
            return .needsConfig
        }
        if store.isClaudeConnected { return .connected }
        // Configured but not connected. If the user just installed, we're
        // waiting on Claude to relaunch and reconnect. Otherwise the user
        // needs to take the restart action.
        if let lastInstallAt, Date().timeIntervalSince(lastInstallAt) < 60 {
            return .waitingForConnection
        }
        return .needsRestart
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                title: "Connect Claude",
                subtitle: subtitle(for: step),
                agent: .cowork
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s5) {
                    StepProgressBar(current: step)
                    activeStepContent

                    if let actionError {
                        Label(actionError, systemImage: "exclamationmark.triangle.fill")
                            .font(ManifoldType.caption)
                            .foregroundStyle(ManifoldPalette.attention)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    DisclosureGroup("Details") {
                        VStack(alignment: .leading, spacing: 4) {
                            DetailLine("Binary", value: ManifoldStore.mcpBinaryPath)
                            DetailLine("Claude Desktop", value: "~/Library/Application Support/Claude/claude_desktop_config.json")
                            DetailLine("Claude Code", value: "~/.claude/settings.json")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(Spacing.s5)
                .frame(maxWidth: 460, alignment: .leading)
            }
            .background(ManifoldPalette.bg)

            Divider()

            SettingsSheetFooter {
                if case .connected = step {
                    Button("Remove Manifold from Claude", role: .destructive) {
                        showUninstallConfirm = true
                    }
                    .accessibilityIdentifier("connectClaude.uninstall")
                }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if case .connected = step {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 480, height: 460)
        .task { await store.integrationHealth.checkAll(force: true) }
        .confirmationDialog(
            "Remove Manifold from Claude?",
            isPresented: $showUninstallConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await uninstall() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Manifold's MCP entry will be removed from Claude Desktop and Claude Code. Other MCP servers in those configs are preserved. Restart Claude Desktop afterward to drop the connection.")
        }
    }

    @ViewBuilder
    private var activeStepContent: some View {
        switch step {
        case .needsClaudeApp:
            stepCard(
                icon: "arrow.down.circle",
                title: "Install Claude Desktop",
                body: "Manifold connects to Claude Desktop and Claude Code via MCP. Install Claude Desktop first, then come back here to finish setup.",
                primary: ("Download Claude Desktop", { openURL("https://claude.ai/download") })
            )
        case .needsConfig:
            stepCard(
                icon: "wrench.and.screwdriver",
                title: "Install Manifold for Claude",
                body: "Add Manifold's MCP entry to Claude Desktop and Claude Code. Existing MCP servers in your configs are preserved.",
                primary: (isInstalling ? "Installing…" : "Install Manifold for Claude", { Task { await install() } })
            )
            .disabled(isInstalling)
        case .needsRestart:
            stepCard(
                icon: "arrow.triangle.2.circlepath",
                title: "Restart Claude Desktop",
                body: "Claude Desktop needs to restart to pick up Manifold's new MCP entry. Manifold will quit and reopen it for you. Claude will ask before quitting if you have unsaved state.",
                primary: (isRestarting ? "Restarting…" : "Restart Claude Desktop", { Task { await restart() } })
            )
            .disabled(isRestarting)
        case .waitingForConnection:
            VStack(alignment: .leading, spacing: Spacing.s3) {
                HStack(spacing: Spacing.s2) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for Claude to connect…")
                        .font(ManifoldType.bodyMedium)
                }
                Text("Claude Desktop should connect within 10 seconds of launching. If it doesn't, quit Claude manually and reopen it — the new MCP entry only loads at launch.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.s2) {
                    Button("Quit Claude Desktop") {
                        Task { await restart() }
                    }
                    .controlSize(.small)
                    .disabled(isRestarting)
                    Button("Re-check") {
                        Task { await store.integrationHealth.checkAll(force: true) }
                    }
                    .controlSize(.small)
                }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .fill(ManifoldPalette.brandSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .strokeBorder(ManifoldPalette.brand.opacity(0.20), lineWidth: 0.5)
            )
        case .connected:
            VStack(alignment: .leading, spacing: Spacing.s3) {
                HStack(spacing: Spacing.s2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(ManifoldPalette.active)
                    Text("Claude is connected")
                        .font(ManifoldType.bodyMedium)
                }
                Text("Claude Desktop and Claude Code can now see folders you share through Manifold. Manage default scope in Settings → Agents.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isUninstalling {
                    HStack(spacing: Spacing.s2) {
                        ProgressView().controlSize(.small)
                        Text("Removing…").font(ManifoldType.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .fill(ManifoldPalette.activeSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .strokeBorder(ManifoldPalette.active.opacity(0.20), lineWidth: 0.5)
            )
        }
    }

    private func stepCard(
        icon: String,
        title: String,
        body: String,
        primary: (label: String, action: () -> Void)
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(ManifoldPalette.brand)
                Text(title)
                    .font(ManifoldType.bodyMedium)
            }
            Text(body)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(primary.label) { primary.action() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Spacer(minLength: 0)
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }

    private func subtitle(for step: Step) -> String {
        switch step {
        case .needsClaudeApp:        return "Install Claude Desktop, then return here."
        case .needsConfig:           return "Add Manifold to Claude's MCP configuration."
        case .needsRestart:          return "Restart Claude Desktop to pick up the new MCP entry."
        case .waitingForConnection:  return "Claude is launching. Connection should appear shortly."
        case .connected:             return "Claude can now see folders you share through Manifold."
        }
    }

    // MARK: - Actions

    @MainActor
    private func install() async {
        isInstalling = true
        actionError = nil
        defer { isInstalling = false }
        store.installMCP()
        try? await Task.sleep(for: .milliseconds(400))
        await store.integrationHealth.checkAll(force: true)
        lastInstallAt = Date()
    }

    @MainActor
    private func restart() async {
        isRestarting = true
        actionError = nil
        defer { isRestarting = false }
        let outcome = await ClaudeRelauncher.relaunch()
        switch outcome {
        case .relaunched:
            lastInstallAt = Date() // begin the verification window
            try? await Task.sleep(for: .milliseconds(800))
            await store.integrationHealth.checkAll(force: true)
        case .notRunning:
            actionError = "Couldn't find Claude Desktop. Make sure it's installed."
        case .timedOut(let seconds):
            actionError = "Claude Desktop didn't quit within \(seconds) seconds. Quit it manually and try again."
        case .launchFailed(let detail):
            actionError = detail
        }
    }

    @MainActor
    private func uninstall() async {
        isUninstalling = true
        actionError = nil
        defer { isUninstalling = false }
        do {
            let writer = ConfigWriter(binaryPath: ManifoldStore.mcpBinaryPath)
            try writer.uninstallClaudeDesktop()
            try writer.uninstallClaudeCode()
            await store.integrationHealth.checkAll(force: true)
        } catch {
            actionError = "Couldn't remove Manifold from Claude: \(error.localizedDescription)"
        }
    }

    private func openURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Step progress

private struct StepProgressBar: View {
    let current: ConnectClaudeSheet.Step

    private var stepIndex: Int {
        switch current {
        case .needsClaudeApp:        return 0
        case .needsConfig:           return 1
        case .needsRestart:          return 2
        case .waitingForConnection:  return 2
        case .connected:             return 3
        }
    }

    private let labels = ["Install", "Configure", "Restart", "Connected"]

    var body: some View {
        HStack(spacing: Spacing.s2) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                stepDot(index: index, label: label)
                if index < labels.count - 1 {
                    Rectangle()
                        .fill(stepIndex > index ? ManifoldPalette.brand : ManifoldPalette.border)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(stepIndex + 1) of \(labels.count): \(labels[min(stepIndex, labels.count - 1)])")
    }

    @ViewBuilder
    private func stepDot(index: Int, label: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(stepIndex >= index ? ManifoldPalette.brand : ManifoldPalette.surface3)
                    .frame(width: 18, height: 18)
                if stepIndex > index {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                } else if stepIndex == index {
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                }
            }
            Text(label)
                .font(ManifoldType.tiny)
                .foregroundStyle(stepIndex >= index ? ManifoldPalette.text : ManifoldPalette.text3)
        }
    }
}
