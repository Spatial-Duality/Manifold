// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct WorkNavigator: View {
    @Environment(ManifoldStore.self) private var store
    @Bindable var work: WorkModel
    @State private var renamingFocusID: String?
    @State private var renameDraft: String = ""
    @State private var pendingDeleteFocus: AccessPresetRecord?
    @State private var historyExpanded: Bool = false
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            List(selection: focusSelectionBinding) {
                focusesSection
                historySection
            }
            .listStyle(.sidebar)
        }
        .accessibilityIdentifier("work.sessions")
        .task { await store.refreshFocuses() }
        .confirmationDialog(
            pendingDeleteFocus.map { "Delete '\($0.name)'?" } ?? "",
            isPresented: Binding(
                get: { pendingDeleteFocus != nil },
                set: { if !$0 { pendingDeleteFocus = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteFocus
        ) { focus in
            Button("Delete", role: .destructive) {
                Task { await deleteFocus(focus) }
            }
            Button("Cancel", role: .cancel) { pendingDeleteFocus = nil }
        } message: { _ in
            Text("This removes the saved Focus. Live sharing isn't affected.")
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.s2) {
            Text("Focuses")
                .font(ManifoldType.bodyMedium)
            Spacer()
            // Plain button (default style) — `.borderless` had unreliable
            // hit-testing in sidebar headers. SF Symbol + image label
            // gives the standard macOS toolbar-icon look without
            // wrestling button styles.
            Button {
                Task { await beginNewFocus() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Focus")
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .accessibilityIdentifier("work.focuses.new")
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
    }

    /// Sidebar selection drives `editingFocusID` for the active agent.
    /// Selecting pins the editor to that Focus. Activation is the
    /// separate Toggle in the editor pane (System Settings → Focus
    /// pattern). Power users get right-click → Activate now.
    private var focusSelectionBinding: Binding<String?> {
        let agent = store.activeSession?.agents.first ?? store.defaultSessionAgent
        return Binding(
            get: { store.resolvedEditingFocusID(for: agent) },
            set: { newValue in
                if let id = newValue {
                    store.editingFocusID[agent] = id
                } else {
                    store.editingFocusID.removeValue(forKey: agent)
                }
            }
        )
    }

    @ViewBuilder
    private var focusesSection: some View {
        let agent = store.activeSession?.agents.first ?? store.defaultSessionAgent
        let focuses = store.availableFocuses.filter { focus in
            // Show focus rows visible to the current agent: target=null
            // (both AIs) OR target matches.
            focus.targetApp == nil || focus.targetApp == agent
        }
        Section {
            if focuses.isEmpty {
                ContentUnavailableView(
                    "No Focuses yet",
                    systemImage: "circle.lefthalf.filled",
                    description: Text("Click + above to create your first Focus.")
                )
                .listRowSeparator(.hidden)
            }
            // Hidden hot-switch buttons: ⌘1..⌘9 activate the Focus at
            // that index. 1Password's vault-switching convention. Buttons
            // are zero-frame so they don't render visibly — they only
            // exist to register the keyboard shortcut.
            ForEach(Array(focuses.prefix(9).enumerated()), id: \.offset) { index, focus in
                Button("") {
                    Task { await store.setActiveFocus(presetID: focus.presetID, targetApp: focus.targetApp) }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            }
            ForEach(focuses) { focus in
                focusRow(focus, activeAgent: agent)
                    .tag(focus.presetID)
            }
        }
    }

    @ViewBuilder
    private func focusRow(_ focus: AccessPresetRecord, activeAgent: TargetApp) -> some View {
        let isActive = store.activeFocusID[activeAgent] == focus.presetID
        let isDefaultAtLaunch = focus.isDefaultAtLaunch
        HStack(spacing: Spacing.s2) {
            // Single SF Symbol with state via fill, not two distinct
            // icons. SF Symbol's contentTransition gives a smooth morph
            // when the active Focus changes — Apple Focus pattern.
            Image(systemName: isActive ? "circle.inset.filled" : "circle")
                .foregroundStyle(isActive ? ManifoldPalette.active : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .animation(.smooth(duration: 0.25), value: isActive)
                .frame(width: 16)
            if renamingFocusID == focus.presetID {
                TextField("Focus name", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($renameFieldFocused)
                    .onSubmit { Task { await commitRename(focus) } }
                    .onExitCommand { cancelRename() }
            } else {
                Text(focus.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if isDefaultAtLaunch {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(ManifoldPalette.accent)
                    .help("Default at launch")
            }
        }
        .contextMenu {
            Button("Activate") {
                Task { await store.setActiveFocus(presetID: focus.presetID, targetApp: focus.targetApp) }
            }
            .disabled(isActive)
            Divider()
            Button("Rename") { startRename(focus) }
                .disabled(focus.isBuiltIn && focus.name == "Default")
            Button(isDefaultAtLaunch ? "Clear default at launch" : "Set as default at launch") {
                let agent = focus.targetApp ?? activeAgent
                Task {
                    await store.setDefaultAtLaunch(
                        presetID: isDefaultAtLaunch ? nil : focus.presetID,
                        agent: agent
                    )
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                pendingDeleteFocus = focus
            }
            .disabled(focus.isBuiltIn)
        }
        .accessibilityIdentifier("work.focus.row.\(focus.presetID)")
    }

    @ViewBuilder
    private var historySection: some View {
        // Collapsed by default. History is audit, not configuration —
        // keeping it tucked away matches Mail's "Recent" / Music's
        // "Recently Played" pattern: present, but not in the way.
        DisclosureGroup("History", isExpanded: $historyExpanded) {
            activeSection
            preparedSection
            recentSection
        }
        .accessibilityIdentifier("work.history")
    }

    // MARK: - Inline rename

    private func startRename(_ focus: AccessPresetRecord) {
        renameDraft = focus.name
        renamingFocusID = focus.presetID
        DispatchQueue.main.async { renameFieldFocused = true }
    }

    private func cancelRename() {
        renamingFocusID = nil
        renameDraft = ""
        renameFieldFocused = false
    }

    private func commitRename(_ focus: AccessPresetRecord) async {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != focus.name,
              let client = store.runtime as? AppRuntimeClient else {
            cancelRename()
            return
        }
        do {
            _ = try await client.saveAccessTemplate(
                presetID: focus.presetID,
                name: trimmed,
                targetApp: focus.targetApp,
                fileScopes: [],
                emailIDs: []
            )
            await store.refreshFocuses()
        } catch {
            store.lastError = "Couldn't rename: \(error.localizedDescription)"
        }
        cancelRename()
    }

    // MARK: - New / delete

    private func beginNewFocus() async {
        // Per user spec: new custom Focuses default to "Both AIs" with
        // mirror=true. The Default Focus is the only one that ships with
        // mirror=false (preserves Access matrix's per-agent independence).
        // User can change Apply-to / Mirror in the editor afterwards.
        guard let saved = await store.createFocus(
            name: "New Focus",
            targetApp: nil,
            mirrorToBoth: true
        ) else {
            store.lastError = "Couldn't create Focus — runtime not available."
            return
        }
        let agent = store.activeSession?.agents.first ?? store.defaultSessionAgent
        store.editingFocusID[agent] = saved.presetID
        startRename(saved)
    }

    private func deleteFocus(_ focus: AccessPresetRecord) async {
        guard let client = store.runtime as? AppRuntimeClient else { return }
        do {
            try await client.deleteAccessTemplate(presetID: focus.presetID)
            // If the deleted Focus was active for any agent, fall back
            // to the default-at-launch Focus or just clear it.
            for agent in TargetApp.allCases where store.activeFocusID[agent] == focus.presetID {
                if let fallback = store.defaultLaunchFocusID[agent] ?? nil,
                   fallback != focus.presetID {
                    await store.setActiveFocus(presetID: fallback, targetApp: agent)
                } else {
                    store.activeFocusID[agent] = nil
                }
            }
            await store.refreshFocuses()
        } catch {
            store.lastError = "Couldn't delete: \(error.localizedDescription)"
        }
        pendingDeleteFocus = nil
    }

    private var sessionSelection: Binding<WorkSessionSelection?> {
        Binding(
            get: { work.sessionSelection },
            set: { selection in
                guard let selection else { return }
                work.sessionSelection = selection
                work.inspectorSelection = .session(selection)
                if case .recent(let id) = selection,
                   let session = store.activity.sessions.first(where: { $0.id == id }) {
                    Task { await store.activity.selectSession(session) }
                }
            }
        )
    }

    @ViewBuilder
    private var activeSection: some View {
        Section("Active") {
            if let active = store.activeSession {
                WorkSessionListRow(
                    title: sessionDisplayName(active),
                    subtitle: activeSubtitle(active),
                    agent: active.agents.first ?? store.defaultSessionAgent,
                    status: "Active",
                    folderCount: store.session.activeGrantSources.count,
                    mailboxCount: activeMailboxCount(for: store),
                    pendingCount: store.pendingRequests.count
                )
                .tag(WorkSessionSelection.active)
                .accessibilityIdentifier("work.session.active")
            } else if store.sessionStartupMode == .defaultSession {
                WorkSessionListRow(
                    title: "Default session",
                    subtitle: "Starts when the runtime is connected",
                    agent: store.defaultSessionAgent,
                    status: "Standby",
                    folderCount: store.defaultSourceIDs(for: store.defaultSessionAgent).count,
                    mailboxCount: 0,
                    pendingCount: 0
                )
                .tag(WorkSessionSelection.defaultSession)
                .accessibilityIdentifier("work.session.default")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No session active")
                        .font(ManifoldType.captionMedium)
                    Text("Prepare a session to give an agent access.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("work.session.none")
            }
        }
    }

    @ViewBuilder
    private var preparedSection: some View {
        if let preload = store.sessionWorkbench.preload {
            Section("Prepared") {
                let defaultIDs = store.defaultSourceIDs(for: preload.agent)
                let effective = preload.effectiveSourceIDs(defaultSourceIDs: defaultIDs)
                WorkSessionListRow(
                    title: preload.name.isEmpty ? "New session" : preload.name,
                    subtitle: preload.baseMode.label,
                    agent: preload.agent,
                    status: "Prepared",
                    folderCount: effective.count,
                    mailboxCount: preload.selectedEmailIDs.count,
                    pendingCount: 0
                )
                .tag(WorkSessionSelection.prepared)
                .accessibilityIdentifier("work.session.prepared")
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !store.activity.sessions.isEmpty {
            Section("Recent") {
                ForEach(store.activity.sessions.prefix(20)) { session in
                    let agent = TargetApp(rawValue: session.agent) ?? .cowork
                    WorkSessionListRow(
                        title: "\(AgentMeta.label(agent)) session",
                        subtitle: relativeTime(session.endTime),
                        agent: agent,
                        status: "Ended",
                        folderCount: 0,
                        mailboxCount: 0,
                        pendingCount: 0
                    )
                    .tag(WorkSessionSelection.recent(sessionID: session.id))
                    .accessibilityIdentifier("work.session.recent.\(session.id)")
                }
            }
        }
    }

    private func beginPreload(baseMode: PreloadBaseMode) {
        store.beginSessionPreload(
            agent: store.defaultSessionAgent,
            baseMode: baseMode
        )
        work.sessionSelection = .prepared
        work.inspectorSelection = .session(.prepared)
    }

    private func sessionDisplayName(_ session: SessionRecord) -> String {
        if let name = store.session.activeGrant?.summaryFraming, !name.isEmpty {
            return name
        }
        return session.name
    }

    private func activeSubtitle(_ session: SessionRecord) -> String {
        let agent = session.agents.first.map { store.displayName(for: $0) } ?? "Agent"
        let folders = store.session.activeGrantSources.count
        return "\(agent) · \(folders) folder\(folders == 1 ? "" : "s")"
    }

    private func relativeTime(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.shared.date(from: iso) else { return "" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private struct WorkSessionListRow: View {
    let title: String
    let subtitle: String
    let agent: TargetApp
    let status: String
    let folderCount: Int
    let mailboxCount: Int
    let pendingCount: Int

    var body: some View {
        HStack(spacing: Spacing.s2) {
            AgentLogo(agent: agent, size: 14)
                .accessibilityHidden(true)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.s1) {
                    Text(title)
                        .lineLimit(1)
                    if pendingCount > 0 {
                        Text("\(pendingCount)")
                            .font(ManifoldType.tiny.weight(.semibold))
                            .foregroundStyle(ManifoldPalette.attention)
                    }
                }
                Text(detailLine)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.s1)

            Text(status)
                .font(ManifoldType.tiny.weight(.semibold))
                .foregroundStyle(status == "Active" ? ManifoldPalette.active : .secondary)
                .lineLimit(1)
        }
    }

    private var detailLine: String {
        var parts = [AgentMeta.label(agent), subtitle]
        if folderCount > 0 {
            parts.append("\(folderCount) folder\(folderCount == 1 ? "" : "s")")
        }
        if mailboxCount > 0 {
            parts.append("\(mailboxCount) mail")
        }
        return parts.joined(separator: " · ")
    }
}
