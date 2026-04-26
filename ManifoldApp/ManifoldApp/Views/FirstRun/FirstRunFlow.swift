// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FirstRunFlow — lightweight three-panel onboarding.
//
// Panels: Concept (what Manifold is), Defaults (nothing is shared),
// GuidedAdd (add your first folder). It is intentionally skippable so
// users can reach the ledger quickly and configure deeper integrations
// from the app itself. Shown only when no sources exist and the user
// hasn't completed onboarding.

import SwiftUI
import ManifoldKit

struct FirstRunFlow: View {
    @Environment(ManifoldStore.self) private var store
    @State private var panel: Panel = .concept
    @State private var selectedPaths: [String] = []

    enum Panel: Int, CaseIterable {
        case concept, defaults, helpImprove, guidedAdd, scopeReview
    }

    var body: some View {
        VStack(spacing: 0) {
            switch panel {
            case .concept:
                ConceptPanel(next: advance)
            case .defaults:
                DefaultsPanel(next: advance, back: back)
            case .helpImprove:
                HelpImprovePanel(diagnostics: store.diagnostics, next: advance, back: back)
            case .guidedAdd:
                GuidedAddPanel(choose: chooseFirstProject, back: back)
            case .scopeReview:
                ScopeReviewPanel(selectedPaths: selectedPaths, finish: finish, back: back)
            }

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

    private func skip() {
        store.hasCompletedOnboarding = true
    }

    private func finish() {
        store.hasCompletedOnboarding = true
        NotificationCenter.default.post(name: .manifoldShowSessionStartSheet, object: nil)
    }
}
