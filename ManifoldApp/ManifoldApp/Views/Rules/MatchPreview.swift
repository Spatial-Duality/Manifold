// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// MatchPreview — live "would match" counter for the selected rule.
//
// Reads from RulesModel.preview, which is populated by a debounced XPC
// query into the runtime's snapshot/email stores. The runtime bounds the
// scan to 2000 entries per scope and returns counts + up to 5 samples.

import SwiftUI
import ManifoldKit
import ManifoldXPC

struct MatchPreview: View {
    @Bindable var model: RulesModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            agentPicker

            if let preview = model.preview {
                summary(preview)
                if !preview.sample.isEmpty {
                    sampleList(preview.sample)
                }
            } else {
                HStack(spacing: Spacing.s2) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Computing match preview…")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var agentPicker: some View {
        Picker("Preview against", selection: Binding(
            get: { model.previewAgent },
            set: { newValue in
                model.previewAgent = newValue
                model.refreshPreview(for: model.selectedRule, agent: newValue)
            }
        )) {
            ForEach([TargetApp.cowork, TargetApp.codex], id: \.self) { agent in
                Text(AgentMeta.label(agent)).tag(agent)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func summary(_ preview: RuleMatchPreview) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s4) {
            countPill(preview.fileMatches, label: "files", systemImage: "folder")
            countPill(preview.emailMatches, label: "emails", systemImage: "envelope")
            countPill(preview.agentMatches, label: "agent calls", systemImage: "sparkles")
        }
    }

    private func countPill(_ n: Int, label: String, systemImage: String) -> some View {
        HStack(spacing: Spacing.s1) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text("\(n)")
                .font(ManifoldType.numericBody)
                .monospacedDigit()
            Text(label)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sampleList(_ samples: [RuleMatchPreview.Sample]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text("Sample matches")
                .font(ManifoldType.tiny)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.top, Spacing.s1)
            ForEach(samples, id: \.identifier) { sample in
                HStack(spacing: Spacing.s1) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ManifoldPalette.active)
                        .font(.system(size: 10))
                    Text(sample.label)
                        .font(ManifoldType.mono)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}
