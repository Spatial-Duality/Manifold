// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// SessionStartSheet — the short form for starting a new session.
//
// Starts one protected, agent-scoped run. Cross-agent continuation is a
// ledger handoff: finish this run, then let the other agent continue from
// the recorded recap.

import SwiftUI
import ManifoldKit

struct SessionStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ManifoldStore.self) private var store
    @State private var draft = SessionDraft()
    @State private var isStarting = false
    @State private var errorMessage: String?

    private var selectedAgent: TargetApp {
        draft.agents.first ?? .cowork
    }

    private var defaultScopeSummary: String {
        if let agent = store.dataControlSummary?.agents.first(where: { $0.agent == selectedAgent }) {
            let folders = "\(agent.defaultFileScopeCount) folder\(agent.defaultFileScopeCount == 1 ? "" : "s")"
            let emails = "\(agent.visibleEmailCount) email\(agent.visibleEmailCount == 1 ? "" : "s")"
            return "\(AgentMeta.label(selectedAgent)) will start with \(folders) and \(emails) visible. Offline is okay; this config is ready for the next connection."
        }
        let count = store.governance.policy(for: selectedAgent)?.allowedSourceIDs.count ?? 0
        if count == 0 {
            return "\(AgentMeta.label(selectedAgent)) has no default folders yet. Add scope first if this run needs files."
        }
        return "\(AgentMeta.label(selectedAgent)) default scope: \(count) folder\(count == 1 ? "" : "s")."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Protect next session")
                        .font(ManifoldType.heading)
                    Text("Starts a protected run from that agent's current policy.")
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

            FormRow(label: "Agent") {
                HStack(spacing: Spacing.s3) {
                    AgentToggle(agent: .cowork, selection: $draft.agents)
                    AgentToggle(agent: .codex, selection: $draft.agents)
                }
            }

            FormRow(label: "Session notes") {
                Toggle("", isOn: $draft.trackWrites)
                    .labelsHidden()
                    .toggleStyle(.switch)
                Text(draft.trackWrites
                     ? "Agents record start and end notes into your ledger."
                     : "Files and writes are still tracked; agent notes stay off.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }

            Text("To hand off, finish this run and open its recap with the other AI. Grouped multi-agent sessions stay disabled until grouped grants land.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Spacer()
                Button("Start protected session") {
                    Task {
                        isStarting = true
                        errorMessage = nil
                        do {
                            try await store.startProtectedRun(draft: draft)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        isStarting = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.agents.isEmpty || isStarting || !store.isRuntimeConnected)
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
            selection = [agent]
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

/// ReloadDriftSheet — drift review before reopening a historical session.
struct ReloadDriftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ManifoldStore.self) private var store
    let historyEntry: SessionHistoryEntry
    @State private var isOpening = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack {
                Text("Session review").font(ManifoldType.heading)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            let drift = store.drift(for: historyEntry)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Label("Drift check", systemImage: "arrow.triangle.2.circlepath")
                    .font(ManifoldType.captionMedium)
                    .foregroundStyle(ManifoldPalette.active)
                Text("Manifold compares this historical run with the current scope before you reuse its context.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.s3)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .fill(ManifoldPalette.activeSoft)
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

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Open in Activity") {
                    Task {
                        isOpening = true
                        errorMessage = nil
                        do {
                            try await store.reloadSession(historyID: historyEntry.id)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        isOpening = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isOpening)
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
