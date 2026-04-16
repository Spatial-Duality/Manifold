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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack {
                Text("Start a session")
                    .font(ManifoldType.heading)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Divider()

            FormRow(label: "Name") {
                TextField("What's this session about?", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
            }

            FormRow(label: "Duration") {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    // Time-limited slider: only shown when a duration is
                    // bound. When the toggle below is on (nil duration),
                    // the slider collapses out of the form entirely so
                    // the user sees what their choice actually means.
                    if let hours = draft.durationHours {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { hours },
                                    set: { draft.durationHours = $0 }
                                ),
                                in: 0.5...8,
                                step: 0.5
                            )
                            HStack(spacing: 0) {
                                Text(hours, format: .number.precision(.fractionLength(1)))
                                Text("h")
                            }
                            .font(ManifoldType.numericBody)
                            .frame(width: 44, alignment: .trailing)
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { draft.durationHours == nil },
                        set: { indefinite in
                            draft.durationHours = indefinite ? nil : 2
                        }
                    )) {
                        Text("Run until I finish it manually")
                            .font(ManifoldType.caption)
                    }
                    .toggleStyle(.checkbox)
                    .help("Session has no time limit. Ends only when you click Finish.")
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
                Button("Start session") {
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

/// ReloadDriftSheet — same shape as SessionStartSheet but prepopulated
/// from a historical session, with a drift preview above the form.
struct ReloadDriftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ManifoldStore.self) private var store
    let historyEntry: SessionHistoryEntry

    @State private var draft: SessionDraft

    init(historyEntry: SessionHistoryEntry) {
        self.historyEntry = historyEntry
        _draft = State(initialValue: SessionDraft(
            name: historyEntry.name,
            durationHours: 2,
            agents: historyEntry.agents,
            baseMode: .defaultScope,
            trackWrites: false
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack {
                Text("Reload session").font(ManifoldType.heading)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            let drift = store.drift(for: historyEntry)
            DriftBanner(drift: drift)

            Divider()

            TextField("Name", text: $draft.name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Reload") {
                    Task {
                        try? await store.reloadSession(historyID: historyEntry.id)
                        dismiss()
                    }
                }
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
