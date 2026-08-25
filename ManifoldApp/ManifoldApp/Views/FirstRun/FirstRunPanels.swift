// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// First-run panels. Each accepts navigation callbacks so the
// parent orchestrator can sequence them without each panel owning state
// about the others.

import SwiftUI
import ManifoldKit

struct ConceptPanel: View {
    let next: () -> Void
    let tryDemo: () -> Void

    var body: some View {
        // Full-bleed atmospheric backdrop carries the app identity.
        // Replaces the previous halo-glow circle behind a static mark —
        // we now have proper layered atmosphere (breathing mesh + curl
        // cloud + grain) doing the work the halo was approximating.
        AtmosphericBackground {
            VStack(spacing: Spacing.s6) {
                Spacer()

                ManifoldMark(placement: .display, color: ManifoldPalette.text)
                    .frame(width: 140, height: 140)

                VStack(spacing: Spacing.s3) {
                    Text("Protect your next AI session")
                        .font(ManifoldType.display)
                        .foregroundStyle(ManifoldPalette.text)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("onboarding.concept.title")
                    Text("Manifold governs the files and mail you choose to share here. It records what was exposed and changed, while staying honest about activity outside this boundary.")
                        .font(ManifoldType.body)
                        .foregroundStyle(ManifoldPalette.text.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                HStack(spacing: Spacing.s3) {
                    Button("Try with demo data first", action: tryDemo)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityIdentifier("onboarding.concept.demo")

                    Button("Continue", action: next)
                        .buttonStyle(.borderedProminent).saffronProminent()
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("onboarding.concept.continue")
                }
            }
            .padding(Spacing.s6)
        }
        .accessibilityIdentifier("onboarding.panel.concept")
    }
}

struct DefaultsPanel: View {
    let next: () -> Void
    let back: () -> Void

    var body: some View {
        // mesh-only mode keeps saffron warmth without the Metal cloud
        // shader cost — the onboarding flow reads as one experience
        // instead of warm-then-cold.
        AtmosphericBackground(meshOnly: true) {
            VStack(spacing: Spacing.s6) {
                Spacer()
                EmptyStateIllustration(
                    systemImage: "lock.shield",
                    title: "Nothing is shared until you share it",
                    subtitle: "No agent can see anything until you share it. The next panel helps you protect one project folder for the next session."
                )
                Spacer()
                HStack(spacing: Spacing.s3) {
                    Button("Back", action: back)
                        .buttonStyle(.bordered)
                    Button("Continue", action: next)
                        .buttonStyle(.borderedProminent).saffronProminent()
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("onboarding.defaults.continue")
                }
            }
            .padding(Spacing.s6)
        }
        .accessibilityIdentifier("onboarding.panel.defaults")
    }
}

struct RuntimePanel: View {
    @Environment(ManifoldStore.self) private var store
    let enable: () -> Void
    let back: () -> Void

    var body: some View {
        AtmosphericBackground(meshOnly: true) {
            VStack(spacing: Spacing.s6) {
                Spacer()
                EmptyStateIllustration(
                    systemImage: "lock.shield",
                    title: "Enable the local runtime",
                    subtitle: "ManifoldAgent runs locally on this Mac. It registers the MCP tools Claude and Codex use, enforces file and mail access, and stores the audit trail locally.",
                    tint: ManifoldPalette.active
                )
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Label("Runs as a macOS background helper", systemImage: "desktopcomputer")
                    Label("Controls Manifold MCP access", systemImage: "slider.horizontal.3")
                    Label("Keeps governed data on this Mac", systemImage: "internaldrive")
                }
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.text2)
                .padding(Spacing.s4)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.r5, style: .continuous)
                        .fill(ManifoldPalette.surface2)
                )

                Spacer()
                HStack(spacing: Spacing.s3) {
                    Button("Back", action: back)
                        .buttonStyle(.bordered)
                    Button(store.runtimeEnabled ? "Continue" : "Enable runtime", action: enable)
                        .buttonStyle(.borderedProminent).saffronProminent()
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("onboarding.runtime.enable")
                }
            }
            .padding(Spacing.s6)
        }
        .accessibilityIdentifier("onboarding.panel.runtime")
    }
}

struct GuidedAddPanel: View {
    let choose: () -> Void
    let back: () -> Void

    var body: some View {
        AtmosphericBackground(meshOnly: true) {
            VStack(spacing: Spacing.s6) {
                Spacer()
                EmptyStateIllustration(
                    systemImage: "folder.badge.plus",
                    title: "Protect one project first",
                    subtitle: "Pick one project folder. Files inside it become visible here when you choose to share them. Everything else stays outside this governed path.",
                    tint: ManifoldPalette.active
                )
                Spacer()
                HStack(spacing: Spacing.s3) {
                    Button("Back", action: back)
                        .buttonStyle(.bordered)
                    Button(action: choose) {
                        Label("Choose folder\u{2026}", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent).saffronProminent()
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.guidedAdd.chooseFolder")
                }
            }
            .padding(Spacing.s6)
        }
        .accessibilityIdentifier("onboarding.panel.guidedAdd")
    }
}

struct ScopeReviewPanel: View {
    let selectedPaths: [String]
    let finish: () -> Void
    let back: () -> Void

    private var folderCountLabel: String {
        let count = selectedPaths.count
        return "\(count) folder\(count == 1 ? "" : "s")"
    }

    var body: some View {
        AtmosphericBackground(meshOnly: true) {
            scopeReviewBody
        }
        .accessibilityIdentifier("onboarding.panel.scopeReview")
    }

    private var scopeReviewBody: some View {
        VStack(spacing: Spacing.s6) {
            Spacer(minLength: 0)

            VStack(spacing: Spacing.s3) {
                Text("Review your first session scope")
                    .font(ManifoldType.display)
                    .multilineTextAlignment(.center)
                Text("Only these folders are visible when you start a Manifold session. Everything else stays outside this governed path unless you choose to share more later.")
                    .font(ManifoldType.body)
                    .foregroundStyle(ManifoldPalette.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Spacing.s3) {
                HStack(spacing: Spacing.s2) {
                    Pill(text: folderCountLabel, variant: .defaultScope)
                    Text("ready for your next session")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(selectedPaths, id: \.self) { path in
                    HStack(alignment: .top, spacing: Spacing.s2) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(ManifoldPalette.active)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(ManifoldType.bodyMedium)
                            Text(path.shortenedPath)
                                .font(ManifoldType.mono)
                                .foregroundStyle(ManifoldPalette.text2)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 2)
                }

                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Boundary")
                        .font(ManifoldType.captionMedium)
                    Text("Manifold governs file and mail access. Native app integrations, terminal access, and other local capabilities fall outside this boundary.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(ManifoldPalette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.s3)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                        .fill(ManifoldPalette.surface3.opacity(0.65))
                )
            }
            .padding(Spacing.s5)
            .frame(maxWidth: 620, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r5, style: .continuous)
                    .fill(ManifoldPalette.surface2)
            )

            Spacer(minLength: 0)

            HStack(spacing: Spacing.s3) {
                Button("Back", action: back)
                    .buttonStyle(.bordered)
                Button("Start session", action: finish)
                    .buttonStyle(.borderedProminent).saffronProminent()
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.scopeReview.finish")
            }
        }
        .padding(Spacing.s6)
    }
}

struct HelpImprovePanel: View {
    @Bindable var diagnostics: DiagnosticsModel
    let supportsSoftwareUpdates: Bool
    let next: () -> Void
    let back: () -> Void

    var body: some View {
        AtmosphericBackground(meshOnly: true) {
            VStack(spacing: Spacing.s6) {
                Spacer()
                EmptyStateIllustration(
                    systemImage: "chart.bar.doc.horizontal",
                    title: "Help improve Manifold (optional)",
                    subtitle: "Local diagnostics are kept on this Mac. Export is manual — Manifold never uploads automatically and never includes governed data."
                )
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Toggle("Include anonymous ID in diagnostic exports", isOn: $diagnostics.diagnosticSharingEnabled)
                        .accessibilityIdentifier("onboarding.help.sharing")
                    if supportsSoftwareUpdates {
                        Toggle("Check for app updates automatically", isOn: $diagnostics.updateChecksEnabled)
                            .accessibilityIdentifier("onboarding.help.updates")
                    }
                    Text("You can change these later in Settings → General. Reset the anonymous identifier any time.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(Spacing.s4)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.r5, style: .continuous)
                        .fill(ManifoldPalette.surface2)
                )

                Spacer()
                HStack(spacing: Spacing.s3) {
                    Button("Back", action: back)
                        .buttonStyle(.bordered)
                    Button("Continue", action: next)
                        .buttonStyle(.borderedProminent).saffronProminent()
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("onboarding.help.continue")
                }
            }
            .padding(Spacing.s6)
        }
        .accessibilityIdentifier("onboarding.panel.helpImprove")
    }
}
