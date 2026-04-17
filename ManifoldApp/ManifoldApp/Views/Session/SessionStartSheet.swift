// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// SessionStartSheet — the short form for starting a new session.
//
// Name / duration / base-mode radio / agents / track-writes. Defaults
// are chosen to be unsurprising: name blank, duration 2 hours, default
// scope, Claude-only, no write tracking.

import SwiftUI
import ManifoldKit

struct SessionStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ManifoldStore.self) private var store
    @State private var draft = SessionDraft()

    private var defaultScopeSummary: String {
        let count = store.sources.filter(\.isAccessible).count
        if count == 0 {
            return "Nothing is in default scope yet. Add a folder first if you want this session to start with protected access."
        }
        return "Default scope: \(count) folder\(count == 1 ? "" : "s"). Choose Inherit default to start with the folders already shared here."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Protect next session")
                        .font(ManifoldType.heading)
                    Text("Review what Claude or Codex can access here before the session starts.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Divider()

            Text(defaultScopeSummary)
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Spacing.s3)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                        .fill(ManifoldPalette.surface3.opacity(0.8))
                )

            FormRow(label: "Name") {
                TextField("What's this session about?", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
            }

            FormRow(label: "Duration") {
                HStack {
                    Slider(value: $draft.durationHours, in: 0.5...8, step: 0.5)
                    HStack(spacing: 0) {
                        Text(draft.durationHours, format: .number.precision(.fractionLength(1)))
                        Text("h")
                    }
                    .font(ManifoldType.numericBody)
                    .frame(width: 44, alignment: .trailing)
                }
            }

            FormRow(label: "Starting scope") {
                Picker("", selection: $draft.baseMode) {
                    Text("Inherit default").tag(SessionRecord.BaseMode.defaultScope)
                    Text("Start blank").tag(SessionRecord.BaseMode.blank)
                    Text("Default minus exclusions").tag(SessionRecord.BaseMode.defaultMinus)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            FormRow(label: "Agents") {
                HStack(spacing: Spacing.s3) {
                    AgentToggle(agent: .cowork, selection: $draft.agents)
                    AgentToggle(agent: .codex, selection: $draft.agents)
                }
            }

            FormRow(label: "Track writes") {
                Toggle("", isOn: $draft.trackWrites)
                    .labelsHidden()
                    .toggleStyle(.switch)
                Text(draft.trackWrites
                     ? "Every write is snapshotted and reversible."
                     : "Reads are logged; writes are not tracked.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Spacer()
                Button("Start protected session") {
                    Task {
                        try? await store.startSession(draft)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.agents.isEmpty)
            }
        }
        .padding(Spacing.s5)
        .frame(width: 460)
    }
}

private struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Text(label)
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
                .padding(.top, 2)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AgentToggle: View {
    let agent: TargetApp
    @Binding var selection: Set<TargetApp>

    private var on: Bool { selection.contains(agent) }

    var body: some View {
        Button {
            if on { selection.remove(agent) } else { selection.insert(agent) }
        } label: {
            HStack(spacing: Spacing.s2) {
                GradientAvatar(agent: agent, size: .small)
                Text(agent == .codex ? "Codex" : "Claude")
                    .font(ManifoldType.body)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? ManifoldPalette.agent(agent) : ManifoldPalette.text3)
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s1)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .fill(on ? ManifoldPalette.agentSoft(agent) : ManifoldPalette.surface3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .strokeBorder(on ? ManifoldPalette.agent(agent).opacity(0.35) : ManifoldPalette.border, lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }
}

/// ReloadDriftSheet — preview-only drift review for a future session reload flow.
struct ReloadDriftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ManifoldStore.self) private var store
    let historyEntry: SessionHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack {
                Text("Session reload preview").font(ManifoldType.heading)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            let drift = store.drift(for: historyEntry)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Label("Preview only", systemImage: "eye")
                    .font(ManifoldType.captionMedium)
                    .foregroundStyle(ManifoldPalette.preview)
                Text("Session reload is still a preview surface. This shows the drift Manifold would review before a future reload flow is wired end to end.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.s3)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .fill(ManifoldPalette.previewSoft)
            )

            DriftBanner(drift: drift)

            Divider()

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(historyEntry.name)
                    .font(ManifoldType.bodyMedium)
                Text("\(historyEntry.displayLastRun) · \(historyEntry.displayDuration)")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.s5)
        .frame(width: 460)
    }
}

private struct DriftBanner: View {
    let drift: SessionDrift

    var body: some View {
        if drift.isClean {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(ManifoldPalette.active)
                Text("Your scope hasn't changed since this session ran.")
                    .font(ManifoldType.caption)
            }
            .padding(Spacing.s3)
            .background(RoundedRectangle(cornerRadius: Spacing.r3).fill(ManifoldPalette.activeSoft))
        } else {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text("Scope has drifted")
                    .font(ManifoldType.captionMedium)
                    .foregroundStyle(ManifoldPalette.attention)
                if !drift.pathsChangedSinceEnded.isEmpty {
                    Text("\(drift.pathsChangedSinceEnded.count) file(s) changed since this session ended.")
                        .font(ManifoldType.caption)
                }
                if !drift.pathsRevokedSinceEnded.isEmpty {
                    Text("\(drift.pathsRevokedSinceEnded.count) path(s) are no longer accessible.")
                        .font(ManifoldType.caption)
                }
                if !drift.newlyAddedSinceEnded.isEmpty {
                    Text("\(drift.newlyAddedSinceEnded.count) new folder(s) have been added since.")
                        .font(ManifoldType.caption)
                }
            }
            .padding(Spacing.s3)
            .background(RoundedRectangle(cornerRadius: Spacing.r3).fill(ManifoldPalette.attentionSoft))
        }
    }
}
