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
    @State private var showCaptureSheet = false

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
        .sheet(isPresented: $showCaptureSheet) {
            CaptureScopeSheet(
                selectableAgents: selectableAgents,
                onSave: { name, agent in
                    Task { await captureScope(name: name, agent: agent) }
                    showCaptureSheet = false
                },
                onCancel: { showCaptureSheet = false }
            )
        }
        .task { await loadIfNeeded() }
    }

    /// All agents the user can pick to capture scope for. Falls back to the full
    /// known set when no agent is currently connected — this is a "selectable"
    /// list, not a connection claim.
    private var selectableAgents: [TargetApp] {
        let raw = store.connectedAgents.compactMap { TargetApp(rawValue: $0) }
        return raw.isEmpty ? [.cowork, .codex] : raw
    }

    /// Snapshot the named agent's current allowed sources as a session
    /// template. Per-file overrides (from FileVisibilityOverrideStore) live
    /// outside the template — they're persistent agent state that applies
    /// to any session, so re-running this template later picks up whatever
    /// overrides exist at that time. The template captures intent — "the
    /// scope I had on this date" — not a frozen snapshot of every file.
    private func captureScope(name: String, agent: TargetApp) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Read the agent's current policy from the governance state the app
        // already keeps in sync via RuntimeStatusSnapshot. This avoids a fresh XPC
        // roundtrip and matches what every other UI surface uses.
        let allowedSourceIDs: Set<String> = store.governance.policy(for: agent)?.allowedSourceIDs ?? []
        guard !allowedSourceIDs.isEmpty else {
            error = "\(displayName(for: agent)) currently has no sources in scope. Add a source first or share existing folders before capturing."
            return
        }
        // One directory-scope per source covers the whole tree. Future
        // callers (StartSessionFromTemplate) interpret this as "agent can
        // see everything under each of these sources, modulo overrides".
        // Per-file overrides live in FileVisibilityOverrideStore — they're
        // persistent agent state that applies to any session, so this
        // template captures intent ("the sources Claude could see on this
        // date") not a frozen file-by-file snapshot.
        let scopes = allowedSourceIDs.sorted().map { sourceID in
            FileSelectionScope(sourceID: sourceID, relativePath: "", isDirectory: true)
        }
        do {
            _ = try await store.runtime.saveAccessTemplate(
                presetID: nil,
                name: trimmed,
                targetApp: agent,
                fileScopes: scopes,
                emailIDs: []
            )
            statusMessage = "Saved '\(trimmed)' for \(displayName(for: agent)) — \(scopes.count) source\(scopes.count == 1 ? "" : "s")."
            error = nil
            loaded = false
            await loadIfNeeded()
        } catch {
            self.error = "Couldn't save scope: \(error.localizedDescription)"
        }
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
                Button {
                    showCaptureSheet = true
                } label: {
                    Label("Capture", systemImage: "plus")
                }
                .controlSize(.small)
                .help("Save what an assistant can currently see as a named template")
                .accessibilityIdentifier("settings.sessions.capture")
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
                Text("Click Capture above to save the sources Claude or Codex can currently see as a named template you can re-run later.")
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
            let agents: [TargetApp] = selectableAgents
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

// MARK: - Capture scope sheet

/// "Capture current scope" sheet. Lets the user name a template and pick
/// which agent's scope to capture. Shows a one-line explanation of what
/// gets saved (sources only, not per-file overrides) so users aren't
/// surprised when they re-run later and find overrides have changed.
private struct CaptureScopeSheet: View {
    let selectableAgents: [TargetApp]
    let onSave: (String, TargetApp) -> Void
    let onCancel: () -> Void

    @State private var draftName: String = ""
    @State private var selectedAgent: TargetApp

    init(
        selectableAgents: [TargetApp],
        onSave: @escaping (String, TargetApp) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.selectableAgents = selectableAgents
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedAgent = State(initialValue: selectableAgents.first ?? .cowork)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                title: "Capture current scope",
                subtitle: "Save the sources \(displayName(for: selectedAgent)) can currently see as a reusable session template.",
                systemImage: "person.badge.clock",
                accent: ManifoldPalette.preview
            )

            Divider()

            Form {
                Section("Template") {
                    TextField("Name", text: $draftName, prompt: Text("e.g. Q4 Reporting"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveIfValid)
                }

                Section("Capture from") {
                    Picker("Agent", selection: $selectedAgent) {
                        ForEach(selectableAgents, id: \.rawValue) { agent in
                            Text(displayName(for: agent)).tag(agent)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Per-file overrides are not copied into the template. They remain persistent policy and apply when the template runs.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(ManifoldPalette.bg)

            Divider()

            SettingsSheetFooter {
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save", action: saveIfValid)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(width: 460, height: 360)
    }

    private func saveIfValid() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, selectedAgent)
    }

    private func displayName(for agent: TargetApp) -> String {
        switch agent {
        case .cowork: return "Claude"
        case .codex:  return "Codex"
        }
    }
}
