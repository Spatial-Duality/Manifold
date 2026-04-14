// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FirstRunFlow — three-panel onboarding.
//
// Panels: Concept (what Manifold is), Defaults (nothing is shared),
// GuidedAdd (share your first folder). Always skippable. Shown only
// when no sources exist and the user hasn't completed onboarding.

import SwiftUI
import ManifoldKit

struct FirstRunFlow: View {
    @Environment(ManifoldStore.self) private var store
    @State private var panel: Panel = .concept

    enum Panel: Int, CaseIterable {
        case concept, defaults, guidedAdd
    }

    var body: some View {
        VStack(spacing: 0) {
            switch panel {
            case .concept:   ConceptPanel(next: advance, skip: skip)
            case .defaults:  DefaultsPanel(next: advance, back: back, skip: skip)
            case .guidedAdd: GuidedAddPanel(finish: finish, back: back, skip: skip)
            }

            Divider()

            HStack(spacing: Spacing.s2) {
                ForEach(Panel.allCases, id: \.self) { p in
                    Circle()
                        .fill(p == panel ? ManifoldPalette.claude : ManifoldPalette.text4)
                        .frame(width: 6, height: 6)
                }
                Spacer()
                Button("Skip setup", action: skip)
                    .buttonStyle(.plain)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Spacing.s4)
        }
        .frame(width: 640, height: 520)
    }

    private func advance() {
        panel = Panel(rawValue: panel.rawValue + 1) ?? panel
    }

    private func back() {
        panel = Panel(rawValue: panel.rawValue - 1) ?? panel
    }

    private func skip() {
        store.hasCompletedOnboarding = true
    }

    private func finish() {
        store.hasCompletedOnboarding = true
    }
}
