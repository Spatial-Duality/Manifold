// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ConnectCodexSheet — guided state-machine setup for Codex.
//
// Mirrors ConnectClaudeSheet's pattern. Codex doesn't need a "restart"
// step — its CLI picks up MCP config changes per-invocation — so the
// flow is shorter: install app → install config → connected.

import SwiftUI
import ManifoldKit

struct ConnectCodexSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false
    @State private var isUninstalling = false
    @State private var actionError: String?
    @State private var showUninstallConfirm = false

    fileprivate enum Step: Equatable {
        case needsCodexApp
        case needsConfig
        case waitingForConnection
        case connected
    }

    private var step: Step {
        let h = store.integrationHealth.codex
        if h.codexAppInstalled != .installed { return .needsCodexApp }
        if !h.mcpAdded.isPassingCheck { return .needsConfig }
        if store.isCodexConnected { return .connected }
        return .waitingForConnection
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                title: "Connect Codex",
                subtitle: subtitle(for: step),
                agent: .codex
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
                            DetailLine("Config", value: "~/.codex/config.toml")
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
                    Button("Remove Manifold from Codex", role: .destructive) {
                        showUninstallConfirm = true
                    }
                    .accessibilityIdentifier("connectCodex.uninstall")
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
        .frame(width: 480, height: 440)
        // Clamp at xLarge — see ConnectClaudeSheet for rationale.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .task { await store.integrationHealth.checkCodex() }
        .confirmationDialog(
            "Remove Manifold from Codex?",
            isPresented: $showUninstallConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await uninstall() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Manifold's MCP entry will be removed from Codex's config. Other MCP server entries are preserved.")
        }
    }

    @ViewBuilder
    private var activeStepContent: some View {
        switch step {
        case .needsCodexApp:
            stepCard(
                icon: "arrow.down.circle",
                title: "Install Codex",
                body: "Manifold connects to Codex via its MCP support. Install the Codex CLI first, then come back here.",
                primary: ("Install Codex", { openURL("https://openai.com/index/introducing-codex/") })
            )
        case .needsConfig:
            stepCard(
                icon: "wrench.and.screwdriver",
                title: "Add Manifold to Codex",
                body: "Add Manifold's MCP entry to Codex's config.toml. Existing MCP servers in your config are preserved.",
                primary: (isAdding ? "Adding…" : "Add Manifold to Codex", { Task { await add() } })
            )
            .disabled(isAdding)
        case .waitingForConnection:
            VStack(alignment: .leading, spacing: Spacing.s3) {
                HStack(spacing: Spacing.s2) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for Codex to connect…")
                        .font(ManifoldType.bodyMedium)
                }
                Text("Codex picks up MCP config on each invocation. Run any Codex command in a project directory to make the helper connect, then return here.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Re-check") {
                    Task { await store.integrationHealth.checkCodex() }
                }
                .controlSize(.small)
            }
            .padding(Spacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .fill(ManifoldPalette.accentSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .strokeBorder(ManifoldPalette.accent.opacity(0.20), lineWidth: 0.5)
            )
        case .connected:
            VStack(alignment: .leading, spacing: Spacing.s3) {
                HStack(spacing: Spacing.s2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(ManifoldPalette.active)
                    Text("Codex is connected")
                        .font(ManifoldType.bodyMedium)
                }
                Text("Codex can now see folders you share through Manifold. Manage default scope in Settings → Agents.")
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
                    .foregroundStyle(ManifoldPalette.codex)
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
        case .needsCodexApp:        return "Install the Codex CLI, then return here."
        case .needsConfig:          return "Add Manifold to Codex's MCP configuration."
        case .waitingForConnection: return "Run any Codex command to make the helper connect."
        case .connected:            return "Codex can now see folders you share through Manifold."
        }
    }

    @MainActor
    private func add() async {
        isAdding = true
        actionError = nil
        defer { isAdding = false }
        do {
            try store.installCodexMCP()
            await store.integrationHealth.checkCodex()
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func uninstall() async {
        isUninstalling = true
        actionError = nil
        defer { isUninstalling = false }
        do {
            let writer = ConfigWriter(binaryPath: ManifoldStore.mcpBinaryPath)
            try writer.uninstallCodex()
            await store.integrationHealth.checkCodex()
        } catch {
            actionError = "Couldn't remove Manifold from Codex: \(error.localizedDescription)"
        }
    }

    private func openURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Step progress (Codex variant — shorter)

private struct StepProgressBar: View {
    let current: ConnectCodexSheet.Step

    private var stepIndex: Int {
        switch current {
        case .needsCodexApp:        return 0
        case .needsConfig:          return 1
        case .waitingForConnection: return 1
        case .connected:            return 2
        }
    }

    private let labels = ["Install", "Configure", "Connected"]

    var body: some View {
        HStack(spacing: Spacing.s2) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                stepDot(index: index, label: label)
                if index < labels.count - 1 {
                    Rectangle()
                        .fill(stepIndex > index ? ManifoldPalette.codex : ManifoldPalette.border)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func stepDot(index: Int, label: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(stepIndex >= index ? ManifoldPalette.codex : ManifoldPalette.surface3)
                    .frame(width: 18, height: 18)
                if stepIndex > index {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ManifoldPalette.onAccent)
                } else if stepIndex == index {
                    Circle()
                        .fill(ManifoldPalette.onAccent)
                        .frame(width: 6, height: 6)
                }
            }
            Text(label)
                .font(ManifoldType.tiny)
                .foregroundStyle(stepIndex >= index ? ManifoldPalette.text : ManifoldPalette.text3)
        }
    }
}
