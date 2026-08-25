// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// GeneralSettingsPane — the first Settings tab.
//
// Stage-11 redesign: a small identity strip at the top (app
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

            Section("Local Runtime") {
                LabeledContent("Status") {
                    Text(runtimeStatusText)
                        .foregroundStyle(runtimeStatusColor)
                }
                Text("ManifoldAgent runs locally, enables MCP access control for Claude and Codex, and stores governed data on this Mac.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    if store.runtimeEnabled {
                        Button("Restart Runtime Helper") {
                            Task { await store.restartRuntimeHelper() }
                        }
                        .controlSize(.small)
                    } else {
                        Button("Enable Local Runtime") {
                            store.enableRuntime()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section {
                SoftwareUpdateSettings(
                    updater: store.updater,
                    automaticChecksEnabled: Binding(
                        get: { diagnostics.updateChecksEnabled },
                        set: { enabled in
                            diagnostics.updateChecksEnabled = enabled
                            store.updater?.applyAutomaticCheckPreference(enabled)
                        }
                    )
                )
            } header: {
                Text("Software Updates")
            } footer: {
                Text(store.updater == nil
                     ? "This Xcode build is not configured with a signed update feed. Official release builds enable Check for Updates, update download, install, skip, and remind-later choices."
                     : "Manifold uses the standard macOS update flow. When an update is available, the update dialog offers install, skip, and remind-later choices.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

            Section {
                LabeledContent("Finder extension") {
                    Text(store.finderExtensionStatusText)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Manage Finder Extension") {
                        store.openFinderExtensionSettings()
                    }
                    .controlSize(.small)
                }
                Toggle("Tag items added to Manifold", isOn: $store.finderIntegrationTagsEnabled)
                TextField("Tag name", text: $store.finderIntegrationTagName)
                    .disabled(!store.finderIntegrationTagsEnabled)
            } header: {
                Text("Finder Integration")
            } footer: {
                Text("Finder tags are optional. Manifold adds only the configured tag and removes only the tag entries it owns; other user tags are preserved.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Notifications") {
                Toggle("Session start and finish", isOn: $store.notifyOnSessionEnd)
                Toggle("Access denied alerts", isOn: $store.notifyOnAccessDenied)
            }

            Section {
                Toggle("Include anonymous ID in diagnostic exports", isOn: $diagnostics.diagnosticSharingEnabled)
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
            } header: {
                Text("Diagnostics")
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text("Diagnostic reports are kept on this Mac. Export is manual — see the Advanced tab to preview or save the JSON.")
                    Text("All governed data stays on your Mac. Manifold records what Claude and Codex see through it. Activity outside Manifold is not tracked.")
                }
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var runtimeStatusText: String {
        if store.isDemoModeEnabled { return "Demo mode" }
        if !store.runtimeEnabled { return "Off" }
        return store.isRuntimeConnected ? "Running" : "Starting or disconnected"
    }

    private var runtimeStatusColor: Color {
        if store.isDemoModeEnabled { return Color.secondary }
        if !store.runtimeEnabled { return Color.secondary }
        return store.isRuntimeConnected ? ManifoldPalette.active : ManifoldPalette.attention
    }
}

private struct SoftwareUpdateSettings: View {
    var updater: UpdaterModel?
    @Binding var automaticChecksEnabled: Bool

    var body: some View {
        if let updater {
            ConfiguredSoftwareUpdateSettings(
                updater: updater,
                automaticChecksEnabled: $automaticChecksEnabled
            )
        } else {
            SourceBuildSoftwareUpdateSettings(automaticChecksEnabled: $automaticChecksEnabled)
        }
    }
}

private struct ConfiguredSoftwareUpdateSettings: View {
    @ObservedObject var updater: UpdaterModel
    @Binding var automaticChecksEnabled: Bool

    var body: some View {
        Toggle("Automatically check for updates", isOn: $automaticChecksEnabled)

        LabeledContent("Status") {
            HStack(spacing: Spacing.s2) {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Checking for updates")
                } else {
                    Image(systemName: statusSymbol)
                        .foregroundStyle(statusTint)
                        .accessibilityHidden(true)
                }

                Text(statusText)
                    .foregroundStyle(statusTextColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }

        HStack {
            Spacer()
            Button("Check Now") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canStartManualCheck)
            .help("Check for Manifold updates now.")
        }
    }

    private var showsProgress: Bool {
        switch updater.state {
        case .checking, .downloading, .installing, .relaunching:
            return true
        case .ready, .updateAvailable, .downloaded, .upToDate, .skipped, .deferred, .failed:
            return false
        }
    }

    private var statusSymbol: String {
        switch updater.state {
        case .ready:
            return "arrow.triangle.2.circlepath"
        case .updateAvailable:
            return "arrow.down.circle"
        case .downloaded:
            return "checkmark.circle"
        case .upToDate:
            return "checkmark.circle"
        case .skipped:
            return "forward.circle"
        case .deferred:
            return "clock"
        case .failed:
            return "exclamationmark.triangle"
        case .checking, .downloading, .installing, .relaunching:
            return "arrow.triangle.2.circlepath"
        }
    }

    private var statusTint: Color {
        switch updater.state {
        case .updateAvailable, .downloaded:
            return ManifoldPalette.selection
        case .upToDate:
            return ManifoldPalette.active
        case .failed:
            return ManifoldPalette.danger
        case .skipped, .deferred:
            return ManifoldPalette.paused
        case .ready, .checking, .downloading, .installing, .relaunching:
            return .secondary
        }
    }

    private var statusTextColor: Color {
        switch updater.state {
        case .failed:
            return ManifoldPalette.danger
        default:
            return .secondary
        }
    }

    private var statusText: String {
        switch updater.state {
        case .ready:
            return "Ready to check."
        case .checking:
            return "Checking for updates…"
        case .updateAvailable(let version):
            return "Update \(version) is available."
        case .downloading(let version):
            return "Downloading \(version)…"
        case .downloaded(let version):
            return "Update \(version) is ready to install."
        case .installing(let version):
            return "Installing \(version)…"
        case .relaunching:
            return "Restarting Manifold…"
        case .upToDate(let date):
            return "Up to date. Checked \(date.formatted(date: .omitted, time: .shortened))."
        case .skipped(let version):
            return "Skipped \(version). Check manually to see it again."
        case .deferred(let version):
            return "Deferred \(version). Manifold will remind you later."
        case .failed(let reason):
            return failureText(for: reason)
        }
    }

    private func failureText(for reason: DiagnosticEvent.SparkleUpdateFailureReason) -> String {
        switch reason {
        case .signatureMismatch:
            return "Update signature could not be verified."
        case .downloadFailed:
            return "Update check or download failed."
        case .installFailed:
            return "Update installation failed."
        case .userCancelled:
            return "Update was cancelled."
        }
    }
}

private struct SourceBuildSoftwareUpdateSettings: View {
    @Binding var automaticChecksEnabled: Bool

    var body: some View {
        Toggle("Automatically check for updates", isOn: $automaticChecksEnabled)
            .disabled(true)

        LabeledContent("Status") {
            Label("Unavailable in this Xcode build", systemImage: "slash.circle")
                .foregroundStyle(.secondary)
        }

        HStack {
            Spacer()
            Button("Check Now") {}
                .disabled(true)
                .help("Official signed release builds enable update checks.")
        }
    }
}

/// Centered app-identity stack at the top of the General settings pane.
/// Matches the Apple convention of stock Settings panes (Notes,
/// Reminders) where the app icon sits centered above the wordmark.
/// Bold but refined: the wordmark uses display (22pt semibold), large
/// enough to feel like a header but not heavy.
///
/// Easter egg: triple-clicking the mark spins it continuously. Click
/// again to stop and the mark springs back to rest. Reduce-motion is
/// respected — the toggle still works for keyboard cycles, but no
/// rotation runs.
private struct IdentityRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: Spacing.s2) {
            // Mark tints to saffron while spinning — the easter egg
            // is a small celebration of identity, so the colour shift
            // matches the motion. Cross-fade is animated so the colour
            // change isn't a jarring step.
            ManifoldMark(
                placement: .display,
                color: spinning ? ManifoldPalette.accent : ManifoldPalette.text
            )
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(rotation))
                .animation(.easeInOut(duration: 0.4), value: spinning)
                .onTapGesture(count: 3) { toggleSpin() }

            VStack(spacing: 4) {
                Text("Manifold")
                    .font(ManifoldType.display)
                    .foregroundStyle(ManifoldPalette.text)
                Text("A local control layer for Claude and Codex.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Text("Version \(Bundle.main.shortVersionString)")
                    .font(ManifoldType.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.s2)
        .accessibilityIdentifier("settings.general.identity")
    }

    private func toggleSpin() {
        spinning.toggle()
        guard !reduceMotion else { return }
        if spinning {
            // Reset to 0 first so the loop starts cleanly each time.
            rotation = 0
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        } else {
            // Spring back to rest from wherever the rotation currently is.
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                rotation = 0
            }
        }
    }
}
