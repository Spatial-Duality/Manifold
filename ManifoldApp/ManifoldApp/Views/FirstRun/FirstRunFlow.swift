// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FirstRunFlow — lightweight three-panel onboarding.
//
// Panels: Concept (what Manifold is), Defaults (nothing is shared),
// Runtime (local helper), GuidedAdd (add your first folder). It is intentionally skippable so
// users can reach the ledger quickly and configure deeper integrations
// from the app itself. Shown only when no sources exist and the user
// hasn't completed onboarding.

import SwiftUI
import ManifoldKit

struct FirstRunFlow: View {
    @Environment(ManifoldStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panel: Panel = .concept
    @State private var selectedPaths: [String] = []

    enum Panel: Int, CaseIterable {
        case concept, defaults, runtime, helpImprove, guidedAdd, scopeReview, connectAgent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Panels land with the .landing token instead of a hard cut.
            // Reduce-motion collapses this to an instant swap with
            // identical meaning.
            Group {
                switch panel {
                case .concept:
                    ConceptPanel(next: advance, tryDemo: startDemo)
                case .defaults:
                    DefaultsPanel(next: advance, back: back)
                case .runtime:
                    RuntimePanel(enable: enableRuntime, back: back)
                case .helpImprove:
                    HelpImprovePanel(
                        diagnostics: store.diagnostics,
                        supportsSoftwareUpdates: store.updater != nil,
                        next: advance,
                        back: back
                    )
                case .guidedAdd:
                    GuidedAddPanel(choose: chooseFirstProject, back: back)
                case .scopeReview:
                    ScopeReviewPanel(selectedPaths: selectedPaths, finish: advance, back: back)
                case .connectAgent:
                    ConnectAgentPanel(finish: finish, back: back)
                }
            }
            .id(panel)
            .transition(.opacity)
            .animation(ManifoldMotion.effective(ManifoldMotion.landing,
                                                reduceMotion: reduceMotion),
                       value: panel)

            Divider()

            HStack(spacing: Spacing.s2) {
                ForEach(Panel.allCases, id: \.self) { p in
                    Circle()
                        .fill(p == panel ? ManifoldPalette.selection : ManifoldPalette.text4)
                        .frame(width: 6, height: 6)
                }
                Spacer()
                Button("Skip setup", action: skip)
                    .buttonStyle(.plain)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding.skip")
            }
            .padding(Spacing.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ManifoldPalette.bg)
        .accessibilityIdentifier("onboarding.flow")
    }

    private func advance() {
        panel = Panel(rawValue: panel.rawValue + 1) ?? panel
    }

    private func back() {
        panel = Panel(rawValue: panel.rawValue - 1) ?? panel
    }

    private func chooseFirstProject() {
        let paths = store.chooseSourcePathsFromPicker()
        guard !paths.isEmpty else { return }
        selectedPaths = paths
        for path in paths {
            store.addSource(path: path)
        }
        panel = .scopeReview
    }

    private func enableRuntime() {
        store.enableRuntime()
        advance()
    }

    private func skip() {
        completeOnboarding(openWork: false)
    }

    private func finish() {
        completeOnboarding(openWork: true)
    }

    private func startDemo() {
        store.setDemoModeEnabled(true)
        completeOnboarding(openWork: true)
    }

    private func completeOnboarding(openWork: Bool) {
        if !store.hasCompletedOnboarding {
            store.diagnostics.record(.onboardingCompleted)
        }
        store.hasCompletedOnboarding = true
        if openWork {
            NotificationCenter.default.post(name: .manifoldShowWork, object: nil)
        }
    }
}
