// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// The three first-run panels. Each accepts navigation callbacks so the
// parent orchestrator can sequence them without each panel owning state
// about the others.

import SwiftUI
import ManifoldKit

struct ConceptPanel: View {
    let next: () -> Void

    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Spacing.s6) {
            Spacer()

            ZStack {
                if !reduceMotion {
                    Circle()
                        .fill(ManifoldPalette.claude.opacity(0.22))
                        .frame(width: 160, height: 160)
                        .blur(radius: 28)
                        .scaleEffect(glow ? 1.1 : 0.85)
                        .opacity(glow ? 0.5 : 0.9)
                        .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: glow)
                        .onAppear { glow = true }
                }
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [ManifoldPalette.claude, ManifoldPalette.codex],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Image(systemName: "sparkle")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: ManifoldPalette.claude.opacity(0.4), radius: 20, y: 8)
            }
            .frame(height: 180)

            VStack(spacing: Spacing.s3) {
                Text("Protect your next AI session")
                    .font(ManifoldType.display)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("onboarding.concept.title")
                Text("Manifold governs the files and mail you choose to share here. It records what was exposed and changed, while staying honest about activity outside this boundary.")
                    .font(ManifoldType.body)
                    .foregroundStyle(ManifoldPalette.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Continue", action: next)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.concept.continue")
        }
        .padding(Spacing.s6)
        .accessibilityIdentifier("onboarding.panel.concept")
    }
}

struct DefaultsPanel: View {
    let next: () -> Void
    let back: () -> Void

    var body: some View {
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
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.defaults.continue")
            }
        }
        .padding(Spacing.s6)
        .accessibilityIdentifier("onboarding.panel.defaults")
    }
}

struct GuidedAddPanel: View {
    let choose: () -> Void
    let back: () -> Void

    var body: some View {
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
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.guidedAdd.chooseFolder")
            }
        }
        .padding(Spacing.s6)
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
        VStack(spacing: Spacing.s6) {
            Spacer(minLength: 0)

            VStack(spacing: Spacing.s3) {
                Text("Review your first protected scope")
                    .font(ManifoldType.display)
                    .multilineTextAlignment(.center)
                Text("Only these folders are visible when you start a protected session. Everything else stays outside this governed path unless you choose to share more later.")
                    .font(ManifoldType.body)
                    .foregroundStyle(ManifoldPalette.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Spacing.s3) {
                HStack(spacing: Spacing.s2) {
                    Pill(text: folderCountLabel, variant: .defaultScope)
                    Text("ready for your next protected session")
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
                    Text("Manifold governs the access it mediates. Native app connectors, terminal access, and other local capabilities fall outside this boundary.")
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
                Button("Protect next session", action: finish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.scopeReview.finish")
            }
        }
        .padding(Spacing.s6)
        .accessibilityIdentifier("onboarding.panel.scopeReview")
    }
}

struct HelpImprovePanel: View {
    @Bindable var diagnostics: DiagnosticsModel
    let next: () -> Void
    let back: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s6) {
            Spacer()
            EmptyStateIllustration(
                systemImage: "chart.bar.doc.horizontal",
                title: "Help improve Manifold (optional)",
                subtitle: "Local diagnostics are kept on this Mac. Sending is manual — Manifold never uploads automatically and never sends governed data."
            )
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Toggle("Share diagnostic reports when I press Send", isOn: $diagnostics.diagnosticSharingEnabled)
                    .accessibilityIdentifier("onboarding.help.sharing")
                Toggle("Check for app updates automatically", isOn: $diagnostics.updateChecksEnabled)
                    .accessibilityIdentifier("onboarding.help.updates")
                Text("You can change these later in Settings -> General. Reset the anonymous identifier any time.")
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
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.help.continue")
            }
        }
        .padding(Spacing.s6)
        .accessibilityIdentifier("onboarding.panel.helpImprove")
    }
}
