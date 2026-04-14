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
    let skip: () -> Void

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
                Text("Manifold is a trust layer for your AI agents")
                    .font(ManifoldType.display)
                    .multilineTextAlignment(.center)
                Text("It's a daemon running in the background that decides what Claude and Codex can see on your Mac. You won't spend much time in this app — it's here when you need it.")
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
        }
        .padding(Spacing.s6)
    }
}

struct DefaultsPanel: View {
    let next: () -> Void
    let back: () -> Void
    let skip: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s6) {
            Spacer()
            EmptyStateIllustration(
                systemImage: "lock.shield",
                title: "Nothing is shared until you share it",
                subtitle: "Agents start with no scope. The next panel helps you share one folder so they have something to work with."
            )
            Spacer()
            HStack(spacing: Spacing.s3) {
                Button("Back", action: back)
                    .buttonStyle(.bordered)
                Button("Continue", action: next)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.s6)
    }
}

struct GuidedAddPanel: View {
    @Environment(ManifoldStore.self) private var store
    let finish: () -> Void
    let back: () -> Void
    let skip: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s6) {
            Spacer()
            EmptyStateIllustration(
                systemImage: "folder.badge.plus",
                title: "Share your first folder",
                subtitle: "Pick one project folder. Only files inside it are visible to agents — everything else stays private.",
                tint: ManifoldPalette.active
            )
            Spacer()
            HStack(spacing: Spacing.s3) {
                Button("Back", action: back)
                    .buttonStyle(.bordered)
                Button {
                    store.addSourceFromPicker()
                    finish()
                } label: {
                    Label("Choose folder\u{2026}", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.s6)
    }
}
