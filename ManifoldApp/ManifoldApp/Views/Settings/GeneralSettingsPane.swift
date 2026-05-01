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
        @Bindable var diagnostics = store.diagnostics

        Form {
            Section {
                IdentityRow()
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

            Section("Notifications") {
                Toggle("Session start and finish", isOn: $store.notifyOnSessionEnd)
                Toggle("Access denied alerts", isOn: $store.notifyOnAccessDenied)
            }

            Section {
                Toggle("Check for updates automatically", isOn: $diagnostics.updateChecksEnabled)
                Toggle("Share diagnostic reports", isOn: $diagnostics.diagnosticSharingEnabled)
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
                Text("Updates and diagnostics")
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text("Diagnostic reports are kept on this Mac. Sending is manual — see the Advanced tab to preview, save, or send.")
                    Text("All governed data stays on your Mac. Manifold records what Claude and Codex see through it. Activity outside Manifold is not tracked.")
                }
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
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
            // Mark tints to brand saffron while spinning — the easter egg
            // is a small celebration of identity, so the colour shift
            // matches the motion. Cross-fade is animated so the colour
            // change isn't a jarring step.
            BrandMark(
                placement: .display,
                color: spinning ? ManifoldPalette.brand : ManifoldPalette.text
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
