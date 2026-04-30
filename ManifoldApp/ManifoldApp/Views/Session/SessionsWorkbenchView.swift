// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct SessionsWorkbenchView: View {
    @Environment(ManifoldStore.self) private var store

    private var availableSources: [SourceRecord] {
        store.sources
            .filter { !$0.isRemoved }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s5) {
                header
                startupSection
                activeSection
                preloadSection
                savedTemplatesSection
            }
            .padding(Spacing.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ManifoldPalette.bg)
        .task {
            await store.loadSessionTemplates()
        }
        .accessibilityIdentifier("sessions.workbench")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Sessions", systemImage: "rectangle.stack.badge.play")
                    .font(ManifoldType.title)
                Text("A session is only the gateway. Files stay in their original folders, and any later session with folder access can see those changes.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                Task { await store.restartRuntimeHelper() }
            } label: {
                Label("Restart Runtime", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var startupSection: some View {
        SessionPanel(title: "Startup") {
            Picker("When Manifold opens", selection: Binding(
                get: { store.sessionStartupMode },
                set: { store.sessionStartupMode = $0 }
            )) {
                ForEach(SessionStartupMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if store.sessionStartupMode == .defaultSession {
                Picker("Default session agent", selection: Binding(
                    get: { store.defaultSessionAgent },
                    set: { store.defaultSessionAgent = $0 }
                )) {
                    Text("Claude").tag(TargetApp.cowork)
                    Text("Codex").tag(TargetApp.codex)
                }
                .pickerStyle(.segmented)
            }

            Text(store.sessionStartupMode == .defaultSession
                ? "Manifold starts a default gateway automatically. A named session can override it, then ending that named session returns to the default."
                : "No agent has Manifold access until you activate a named session.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activeSection: some View {
        SessionPanel(title: "Current Gateway") {
            HStack(alignment: .center, spacing: Spacing.s3) {
                AgentStatusDot(status: store.activeSession == nil ? .paused : .active, size: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeTitle)
                        .font(ManifoldType.bodyMedium)
                    Text(activeSubtitle)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if store.activeSession != nil {
                    Button {
                        Task { await store.endSession() }
                    } label: {
                        Label("End", systemImage: "stop.fill")
                    }
                    .controlSize(.small)

                    Button {
                        Task { await store.stopAllSessions() }
                    } label: {
                        Label("Stop All", systemImage: "xmark.circle")
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var activeTitle: String {
        if let name = store.session.activeGrant?.summaryFraming, !name.isEmpty {
            return "\(name) active"
        }
        if let active = store.activeSession {
            return "\(active.name) active"
        }
        return "No session active"
    }

    private var activeSubtitle: String {
        guard let grant = store.session.activeGrant else {
            return store.sessionStartupMode == .manual
                ? "Manual mode is on. Activate a preload when you want Claude or Codex to see Manifold data."
                : "Default mode will start a gateway when the runtime is connected."
        }
        let agent = TargetApp(rawValue: grant.targetApp).map { store.displayName(for: $0) } ?? grant.targetApp
        let sourceCount = store.session.activeGrantSources.count
        return "\(agent) can access \(sourceCount) source\(sourceCount == 1 ? "" : "s") through Manifold."
    }

    private var preloadSection: some View {
        SessionPanel(title: "Preload") {
            if let preload = store.sessionWorkbench.preload {
                preloadEditor(preload)
            } else {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    Text("Prepare a named session while your current session keeps running.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: Spacing.s2) {
                        Button {
                            store.beginSessionPreload(agent: store.defaultSessionAgent, baseMode: .buildOnDefault)
                        } label: {
                            Label("New from default", systemImage: "plus.rectangle.on.rectangle")
                        }
                        Button {
                            store.beginSessionPreload(agent: store.defaultSessionAgent, baseMode: .blank)
                        } label: {
                            Label("New blank", systemImage: "plus.rectangle")
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func preloadEditor(_ preload: SessionPreloadDraft) -> some View {
        let defaultIDs = store.defaultSourceIDs(for: preload.agent)
        let effectiveIDs = preload.effectiveSourceIDs(defaultSourceIDs: defaultIDs)

        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                TextField("Session name", text: preloadName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)

                Picker("Agent", selection: preloadAgent) {
                    ForEach(store.connectedOrDefaultAgents(), id: \.self) { agent in
                        Text(store.displayName(for: agent)).tag(agent)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()
            }

            Picker("Base", selection: preloadBaseMode) {
                ForEach(PreloadBaseMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Text(preload.baseMode.subtitle)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            sourceList(preload: preload, defaultIDs: defaultIDs, effectiveIDs: effectiveIDs)

            HStack(spacing: Spacing.s2) {
                Button {
                    Task { await store.activateSessionPreload() }
                } label: {
                    if store.sessionWorkbench.isActivating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Activate", systemImage: "play.fill")
                    }
                }
                .disabled(store.sessionWorkbench.isActivating)

                Button {
                    Task { await store.saveSessionPreload() }
                } label: {
                    if store.sessionWorkbench.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Save", systemImage: "tray.and.arrow.down")
                    }
                }
                .disabled(preload.hasUnsavedName || store.sessionWorkbench.isSaving)

                Button("Clear") {
                    store.clearSessionPreload()
                }
                .buttonStyle(.borderless)

                Spacer()
                Text("\(effectiveIDs.count) source\(effectiveIDs.count == 1 ? "" : "s") selected")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = store.sessionWorkbench.lastMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.active)
            }
            if let error = store.sessionWorkbench.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func sourceList(preload: SessionPreloadDraft, defaultIDs: Set<String>, effectiveIDs: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("Folders")
                .font(ManifoldType.bodyMedium)
            if availableSources.isEmpty {
                Text("No folders have been added to Manifold yet.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(availableSources) { source in
                        sourceRow(source, preload: preload, defaultIDs: defaultIDs, effectiveIDs: effectiveIDs)
                        if source.sourceID != availableSources.last?.sourceID {
                            Divider()
                        }
                    }
                }
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator.opacity(0.35))
                }
            }
        }
    }

    private func sourceRow(
        _ source: SourceRecord,
        preload: SessionPreloadDraft,
        defaultIDs: Set<String>,
        effectiveIDs: Set<String>
    ) -> some View {
        Toggle(isOn: Binding(
            get: { effectiveIDs.contains(source.sourceID) },
            set: { store.setPreloadSource(sourceID: source.sourceID, included: $0) }
        )) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(ManifoldPalette.selection)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.s2) {
                        Text(source.displayName)
                            .font(ManifoldType.body)
                        if let badge = sourceBadge(sourceID: source.sourceID, preload: preload, defaultIDs: defaultIDs, effectiveIDs: effectiveIDs) {
                            Text(badge)
                                .font(ManifoldType.captionMedium)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.tertiary.opacity(0.18), in: Capsule())
                        }
                    }
                    Text(source.originalRootPath.abbreviatingHomeDirectory)
                        .font(ManifoldType.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
    }

    private func sourceBadge(
        sourceID: String,
        preload: SessionPreloadDraft,
        defaultIDs: Set<String>,
        effectiveIDs: Set<String>
    ) -> String? {
        guard preload.baseMode == .buildOnDefault else { return nil }
        let inDefault = defaultIDs.contains(sourceID)
        let selected = effectiveIDs.contains(sourceID)
        if inDefault && !selected { return "removed" }
        if !inDefault && selected { return "added" }
        if inDefault { return "default" }
        return nil
    }

    private var savedTemplatesSection: some View {
        SessionPanel(title: "Saved Sessions") {
            if store.sessionWorkbench.isLoadingTemplates {
                ProgressView("Loading sessions...")
            } else if store.sessionWorkbench.templates.isEmpty {
                Text("Saved sessions will appear here after you save a preload.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.sessionWorkbench.templates) { template in
                        savedTemplateRow(template)
                        if template.presetID != store.sessionWorkbench.templates.last?.presetID {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func savedTemplateRow(_ template: AccessPresetRecord) -> some View {
        HStack(spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(ManifoldType.body)
                Text(template.targetApp.map { store.displayName(for: $0) } ?? "Any agent")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.loadSessionTemplate(template) }
            } label: {
                Label("Load", systemImage: "square.and.arrow.down")
            }
            .controlSize(.small)
        }
        .padding(.vertical, Spacing.s2)
    }

    private var preloadName: Binding<String> {
        Binding(
            get: { store.sessionWorkbench.preload?.name ?? "" },
            set: { value in
                guard var preload = store.sessionWorkbench.preload else { return }
                preload.name = value
                store.sessionWorkbench.preload = preload
            }
        )
    }

    private var preloadAgent: Binding<TargetApp> {
        Binding(
            get: { store.sessionWorkbench.preload?.agent ?? store.defaultSessionAgent },
            set: { store.setPreloadAgent($0) }
        )
    }

    private var preloadBaseMode: Binding<PreloadBaseMode> {
        Binding(
            get: { store.sessionWorkbench.preload?.baseMode ?? .buildOnDefault },
            set: { store.setPreloadBaseMode($0) }
        )
    }
}

private struct SessionPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text(title)
                .font(ManifoldType.heading)
            content
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator.opacity(0.35))
        }
    }
}

private extension String {
    var abbreviatingHomeDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard hasPrefix(home) else { return self }
        return "~" + dropFirst(home.count)
    }
}
