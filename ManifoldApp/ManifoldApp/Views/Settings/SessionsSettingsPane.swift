// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// SessionsSettingsPane — browse + start + delete saved session templates.
//
// Read-only browse for v1. Templates are created via XPC programmatically
// for now; the UI for picking files/sources at create time arrives with
// the unified Access surface (Lane A consumer). This pane lets users see
// what's saved, run a saved session in one click, and clean up stale
// templates.

import SwiftUI
import ManifoldKit

struct SessionsSettingsPane: View {
    @Environment(ManifoldStore.self) private var store
    @State private var templates: [TemplateGroup] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var startingTemplateID: String?
    @State private var statusMessage: String?

    var body: some View {
        Form {
            headerSection
            if !loaded {
                Section {
                    ProgressView("Loading saved sessions…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if templates.isEmpty {
                emptySection
            } else {
                ForEach(templates) { group in
                    templateGroupSection(group)
                }
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(ManifoldType.caption)
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.sessions.pane")
        .task { await loadIfNeeded() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        Section {
            HStack(spacing: Spacing.s3) {
                Image(systemName: "person.badge.clock")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Named saved sessions")
                        .font(ManifoldType.bodyMedium)
                    Text("Save a scope as a named template, then start it on demand. Each template targets one assistant and applies on top of your default sharing for the duration of the session.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(ManifoldPalette.active)
                    .font(ManifoldType.caption)
            }
        }
    }

    @ViewBuilder
    private var emptySection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.section) {
                Text("No saved sessions yet")
                    .font(ManifoldType.bodyMedium)
                Text("When the unified Access surface ships its create-template flow, you'll be able to save the current scope as a named session here. For now, this pane lists templates created programmatically.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func templateGroupSection(_ group: TemplateGroup) -> some View {
        Section {
            ForEach(group.templates) { template in
                templateRow(template, agent: group.agent)
            }
        } header: {
            Text(headerLabel(for: group.agent))
                .font(ManifoldType.title)
        }
    }

    @ViewBuilder
    private func templateRow(_ template: AccessPresetRecord, agent: TargetApp) -> some View {
        HStack(spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(ManifoldType.body)
                Text(scopeSummary(for: template, agent: agent))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if startingTemplateID == template.presetID {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 20, height: 20)
            } else {
                Button("Start") {
                    Task { await startTemplate(template, defaultAgent: agent) }
                }
                .controlSize(.small)
            }
            Menu {
                Button("Start session") {
                    Task { await startTemplate(template, defaultAgent: agent) }
                }
                Divider()
                Button("Delete template", role: .destructive) {
                    Task { await deleteTemplate(template) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
    }

    // MARK: - Actions

    private func loadIfNeeded() async {
        guard !loaded else { return }
        do {
            let connectedAgents = store.connectedAgents.compactMap { TargetApp(rawValue: $0) }
            let agents: [TargetApp] = connectedAgents.isEmpty ? [.cowork, .codex] : connectedAgents
            var groups: [TemplateGroup] = []
            for agent in agents {
                let list = try await store.runtime.accessTemplates(for: agent)
                if !list.isEmpty {
                    // Filter out unscoped templates from the second agent's
                    // listing — they belong under "Default templates" only.
                    let scoped = list.filter { $0.targetApp == agent || $0.targetApp == nil && agent == agents.first }
                    if !scoped.isEmpty {
                        groups.append(TemplateGroup(agent: agent, templates: scoped))
                    }
                }
            }
            templates = groups
            loaded = true
            error = nil
        } catch {
            self.error = "Couldn't load saved sessions: \(error.localizedDescription)"
            loaded = true
        }
    }

    private func startTemplate(_ template: AccessPresetRecord, defaultAgent: TargetApp) async {
        startingTemplateID = template.presetID
        defer { startingTemplateID = nil }
        let agent = template.targetApp ?? defaultAgent
        do {
            let result = try await store.runtime.startSessionFromTemplate(
                presetID: template.presetID,
                targetApp: agent,
                summaryFraming: nil,
                noteCaptureMode: .off,
                emailSensitivity: nil
            )
            var note = "Started '\(result.templateName)' for \(displayName(for: agent))."
            if !result.skippedSources.isEmpty {
                let names = result.skippedSources
                    .prefix(2)
                    .map { (skip: StartSessionFromTemplateResult.SkippedSource) -> String in skip.displayName }
                    .joined(separator: ", ")
                let suffix = result.skippedSources.count > 2 ? "…" : ""
                note += " Skipped \(result.skippedSources.count) missing source\(result.skippedSources.count == 1 ? "" : "s"): \(names)\(suffix)"
            }
            statusMessage = note
            error = nil
        } catch {
            self.error = "Couldn't start session: \(error.localizedDescription)"
        }
    }

    private func deleteTemplate(_ template: AccessPresetRecord) async {
        do {
            try await store.runtime.deleteAccessTemplate(presetID: template.presetID)
            templates = templates.compactMap { group in
                let remaining = group.templates.filter { $0.presetID != template.presetID }
                return remaining.isEmpty ? nil : TemplateGroup(agent: group.agent, templates: remaining)
            }
            statusMessage = "Deleted '\(template.name)'."
            error = nil
        } catch {
            self.error = "Couldn't delete template: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func headerLabel(for agent: TargetApp) -> String {
        "For \(displayName(for: agent))"
    }

    private func displayName(for agent: TargetApp) -> String {
        switch agent {
        case .cowork: return "Claude"
        case .codex:  return "Codex"
        }
    }

    private func scopeSummary(for template: AccessPresetRecord, agent: TargetApp) -> String {
        var parts: [String] = []
        if template.targetApp == nil {
            parts.append("Unscoped (any agent)")
        } else if template.targetApp != agent {
            parts.append("for \(displayName(for: template.targetApp ?? agent))")
        }
        if !template.updatedAt.isEmpty {
            parts.append("updated \(formatTimestamp(template.updatedAt))")
        }
        return parts.isEmpty ? "Saved template" : parts.joined(separator: " · ")
    }

    private func formatTimestamp(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

private struct TemplateGroup: Identifiable {
    let agent: TargetApp
    let templates: [AccessPresetRecord]
    var id: String { agent.rawValue }
}
