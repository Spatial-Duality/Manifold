// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// WorkView — the unified work surface.
//
// Three regions, Codex-inspired:
//
//   [ Sessions list | Timeline & approvals | Inspector ]
//
// Sessions live in the left column. The center pane shows the current
// session summary, pending approvals, and a recent-activity timeline.
// The right column is a contextual inspector for whatever the user
// has selected — request, write, session, runtime issue.
//
// All backend logic lives in existing models. WorkView only composes
// them and tracks what the user has selected via WorkModel.

import SwiftUI
import ManifoldKit

struct WorkView: View {
    @Environment(ManifoldStore.self) private var store
    @Bindable var work: WorkModel
    @Binding var inspectorVisible: Bool

    /// Live subtitle reflecting the Focus that's currently running.
    /// Resolution must mirror `editingFocus` in WorkCurrentSessionSummary:
    /// explicit active first, default-at-launch second (Default IS
    /// running on startup even before the user's first switch), then any
    /// Focus, then the fallback string.
    private var activeFocusSubtitle: String {
        let agent = store.activeSession?.agents.first ?? store.defaultSessionAgent
        if let id = store.activeFocusID[agent],
           let f = store.availableFocuses.first(where: { $0.presetID == id }) {
            return f.name
        }
        if let id = store.defaultLaunchFocusID[agent] ?? nil,
           let f = store.availableFocuses.first(where: { $0.presetID == id }) {
            return f.name
        }
        return store.availableFocuses.first?.name ?? "Default"
    }

    var body: some View {
        WorkMainPane(work: work)
        .inspector(isPresented: $inspectorVisible) {
            WorkInspector(work: work)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
        }
        .navigationSubtitle(activeFocusSubtitle)
        .toolbar {
            // Apple-native toolbar items: Liquid Glass auto-applied on
            // macOS 26 via `.primaryAction` placement. Replaces the
            // WorkCommandStrip inline HStack so the actions live where
            // macOS users expect them.
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        store.beginSessionPreload(
                            agent: store.defaultSessionAgent,
                            baseMode: .buildOnDefault
                        )
                        work.sessionSelection = .prepared
                        work.inspectorSelection = .session(.prepared)
                    } label: {
                        Label("Build on default", systemImage: "plus.rectangle.on.rectangle")
                    }
                    Button {
                        store.beginSessionPreload(
                            agent: store.defaultSessionAgent,
                            baseMode: .blank
                        )
                        work.sessionSelection = .prepared
                        work.inspectorSelection = .session(.prepared)
                    } label: {
                        Label("Start blank", systemImage: "plus.rectangle")
                    }
                } label: {
                    Label("New session", systemImage: "plus.square")
                }
                .help("Prepare a new session")
                .accessibilityIdentifier("work.toolbar.newSession")

                if store.sessionWorkbench.preload != nil {
                    Button {
                        Task { await store.activateSessionPreload() }
                    } label: {
                        Label("Activate", systemImage: "play.fill")
                    }
                    .disabled(store.sessionWorkbench.isActivating)
                    .accessibilityIdentifier("work.toolbar.activate")
                }

                if store.activeSession != nil {
                    Button(role: .destructive) {
                        Task { await store.endSession() }
                    } label: {
                        Label("End session", systemImage: "stop.fill")
                    }
                    .accessibilityIdentifier("work.toolbar.end")
                }

                Button {
                    Task { await store.restartRuntimeHelper() }
                } label: {
                    Label("Restart runtime", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("work.toolbar.restart")
            }
        }
        .task {
            await store.refreshFocuses()
            await store.governance.loadPolicies()
            while !Task.isCancelled {
                await store.activity.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ledger.surface.work")
    }
}

// MARK: - Main pane (center column)

private struct WorkMainPane: View {
    @Environment(ManifoldStore.self) private var store
    @Bindable var work: WorkModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.s4) {
                    WorkFirstRunCoachmark()
                    if let issue = workRuntimeIssue(store: store) {
                        WorkRuntimeIssueBanner(issue: issue, work: work)
                    }
                    WorkCurrentSessionSummary()
                    // Approvals are session-scoped: only meaningful when
                    // viewing the Focus that owns the current grant.
                    // Activity is global history — always visible so the
                    // user can see what's happened recently regardless of
                    // which Focus they're inspecting.
                    if isViewingActiveFocus {
                        WorkPendingApprovalsSection(work: work)
                    }
                    WorkTimelineSection(work: work)
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s4)
            }
        }
        .accessibilityIdentifier("work.main")
    }

    /// True when the editor is bound to the same Focus that currently
    /// owns the live grant. Approvals + Activity are session-scoped, so
    /// they only make sense in this state.
    private var isViewingActiveFocus: Bool {
        let agent = store.activeSession?.agents.first ?? store.defaultSessionAgent
        let editingID = store.resolvedEditingFocusID(for: agent)
        let activeID = store.activeFocusID[agent]
        return editingID != nil && editingID == activeID
    }
}

/// One-shot welcome card shown on a fresh user's first visit to Work.
/// Adapts content to whether an agent is connected: if not, point the
/// user at Settings → Agents (R3 — onboarding never mentions Claude /
/// Codex setup, this fixes the post-onboarding gap). If an agent IS
/// connected, the original three-region orientation is shown.
/// Auto-dismisses on first user action so it doesn't outstay its welcome.
private struct WorkFirstRunCoachmark: View {
    @Environment(ManifoldStore.self) private var store
    @AppStorage("focus.coachmark.dismissed") private var dismissed: Bool = false

    private var hasAgentConnected: Bool {
        store.isClaudeConnected || store.isCodexConnected
    }

    private var title: String {
        hasAgentConnected ? "Welcome to Focus" : "Connect an agent to start sharing"
    }

    private var body_text: String {
        if hasAgentConnected {
            return "A Focus is a saved bundle of folders, mailboxes, and settings. Switch Focuses from the chip on the active session card. Pending approvals and the activity ledger flow here."
        } else {
            return "Manifold governs what Claude and Codex can see. Open Settings → Agents to install Manifold for either, then come back here to pick a Focus."
        }
    }

    var body: some View {
        if !dismissed {
            HStack(alignment: .top, spacing: Spacing.s3) {
                ManifoldMark(placement: .inline, color: ManifoldPalette.accent)
                    .frame(width: 22, height: 22)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(ManifoldType.bodyMedium)
                        .foregroundStyle(ManifoldPalette.text)
                    Text(body_text)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !hasAgentConnected {
                        Button {
                            // SettingsLink-style routing: opens Settings.
                            // The user navigates to Agents themselves on
                            // first visit; once they touch Agents, the
                            // coachmark stays dismissed via the close X.
                            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        } label: {
                            Label("Open Settings → Agents", systemImage: "sparkle")
                        }
                        .controlSize(.small)
                        .padding(.top, 4)
                        .accessibilityIdentifier("work.coachmark.openAgents")
                    }
                }
                Spacer(minLength: Spacing.s2)
                Button {
                    withAnimation(ManifoldMotion.landing) { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss welcome")
            }
            .padding(Spacing.s3)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .fill(ManifoldPalette.accentSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .strokeBorder(ManifoldPalette.accent.opacity(0.18), lineWidth: 0.5)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityIdentifier("work.coachmark")
        }
    }
}

// MARK: - Current session summary card

private struct WorkCurrentSessionSummary: View {
    @Environment(ManifoldStore.self) private var store

    @State private var showSeparateSharingPrompt = false
    @State private var pendingSeparateSharingTarget: Bool = true
    @State private var showSyncSheet = false
    @State private var syncStatusMessage: String?

    var body: some View {
        @Bindable var bindableStore = store
        VStack(alignment: .leading, spacing: Spacing.s3) {
            // Apple-native header: H1 = Focus name, Toggle = active state.
            // Replaces the chip duo with proper SwiftUI controls that
            // get Liquid Glass automatically on macOS 26.
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                AgentStatusDot(status: store.activeSession == nil ? .paused : .active, size: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(focusHeadline)
                        .font(ManifoldType.heading)
                    Text(focusSubline)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("Active", isOn: activeToggleBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(editingFocus == nil)
                    .accessibilityIdentifier("work.focus.activeToggle")
                    .help(toggleHelp)
            }

            // Apply-to: which agent(s) the active/edited Focus targets.
            // null = both AIs; explicit single = just that one. Mirrors
            // Apple Focus's per-Focus filters pattern.
            if let editingFocus {
                HStack(spacing: Spacing.s2) {
                    Text("Apply to")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                    Picker("Apply to", selection: applyToBinding(for: editingFocus)) {
                        Text("Claude").tag(Optional(TargetApp.cowork))
                        Text("Codex").tag(Optional(TargetApp.codex))
                        Text("Both").tag(Optional<TargetApp>.none)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 240)
                    .disabled(editingFocus.isBuiltIn && editingFocus.name == "Default")
                    Spacer()
                }
            }

            Text(subtext)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = activeSummary {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: Spacing.s2)],
                    alignment: .leading,
                    spacing: Spacing.s2
                ) {
                    metric(systemImage: "folder", title: "Folders", value: "\(summary.folders)")
                    metric(systemImage: "envelope", title: "Mailboxes", value: "\(summary.mailboxes)")
                    metric(systemImage: "hand.raised", title: "Pending", value: "\(store.pendingRequests.count)", tint: store.pendingRequests.isEmpty ? nil : ManifoldPalette.attention)
                    metric(systemImage: "doc.text.magnifyingglass", title: "Detail", value: detailLabel(for: summary.agent))
                    metric(systemImage: "clock.arrow.circlepath", title: "File Memory", value: memoryLabel(for: summary.agent))
                }
            }

            if let preload = store.sessionWorkbench.preload {
                preparedSection(preload)
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

            sessionRequestDetailControl
            fileMemoryAccessControl

            // Separate-sharing toggle + sync action. Hidden for
            // built-in Focuses: Default is per-agent independent by
            // design (the toggle would lie), Locked Down has empty
            // scope so mirror state is moot. User-created Focuses get
            // the full control.
            if let editingFocus, !editingFocus.isBuiltIn {
                HStack(spacing: Spacing.s2) {
                    Toggle("Mirror to both AIs", isOn: mirrorBinding(for: editingFocus))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityIdentifier("work.focus.mirrorToggle")
                    Spacer()
                    Button {
                        showSyncSheet = true
                    } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .controlSize(.small)
                    .help("Copy one AI's scope onto the other in one shot — useful when separate-sharing has diverged.")
                    .accessibilityIdentifier("work.focus.syncNow")
                }
                .padding(.top, Spacing.s2)

                Text(editingFocus.mirrorToBoth
                    ? "Sharing this Focus with one AI also shares it with the other."
                    : "Claude and Codex are independent — tick each separately in the Folders matrix. Use Sync now to merge their scopes once.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let editingFocus, editingFocus.name == "Default" {
                // Default-only hint: explain why mirror is missing here
                // and where to find sync if they need it.
                HStack(spacing: Spacing.s2) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Default keeps Claude and Codex independent. Use the Folders matrix per-agent ticks to share separately.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        showSyncSheet = true
                    } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .controlSize(.small)
                    .help("Copy one AI's scope onto the other in one shot.")
                }
                .padding(.top, Spacing.s2)
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
        .accessibilityIdentifier("work.summary")
        .confirmationDialog(
            "Mirror this Focus's scope across both AIs?",
            isPresented: $showSeparateSharingPrompt,
            titleVisibility: .visible
        ) {
            Button("Mirror") {
                Task { await applyMirrorChange(toMirror: pendingSeparateSharingTarget) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anything either AI can currently see will be shared with both. Per-agent decisions in this Focus collapse into a single set.")
        }
        .sheet(isPresented: $showSyncSheet) {
            // Reuse the existing one-shot sync sheet (relocated to
            // Settings → Advanced earlier). Surfacing it inline next to
            // the mirror toggle is the canonical home now — Settings
            // can keep its copy for power-user discovery.
            MirrorScopeSheet(
                runtime: store.runtime,
                onApplied: { summary in
                    syncStatusMessage = summary
                    showSyncSheet = false
                },
                onCancel: { showSyncSheet = false }
            )
        }
        .task { await store.refreshFocuses() }
    }

    /// Which agent's Focus the editor is currently bound to. Prefers
    /// the active grant's agent, falls back to the default-session agent.
    private var activeAgentForChip: TargetApp {
        store.activeSession?.agents.first ?? store.defaultSessionAgent
    }

    /// The Focus the editor is currently bound to. Resolution order:
    /// (1) what the user explicitly selected in the sidebar
    /// (2) what's currently active for the agent
    /// (3) the default-at-launch Focus (Default)
    /// (4) any first available Focus
    /// Drives the H1, the Apply-to picker, and the mirror toggle.
    /// Default is always running on startup, so this should rarely be nil.
    private var editingFocus: AccessPresetRecord? {
        let agent = activeAgentForChip
        if let id = store.resolvedEditingFocusID(for: agent),
           let f = store.availableFocuses.first(where: { $0.presetID == id }) {
            return f
        }
        if let defaultID = store.defaultLaunchFocusID[agent] ?? nil,
           let f = store.availableFocuses.first(where: { $0.presetID == defaultID }) {
            return f
        }
        return store.availableFocuses.first
    }

    /// Whether the Focus the editor is bound to is currently active.
    /// The Default Focus is always considered active when the runtime is
    /// running and no other Focus has been switched to — matches the
    /// "Default focus is always running on startup" mental model.
    private var isFocusActive: Bool {
        guard let editing = editingFocus else { return false }
        let agent = activeAgentForChip
        // Explicit activation wins.
        if store.activeFocusID[agent] == editing.presetID { return true }
        // Default-at-launch is implicitly active when no other Focus has
        // been explicitly switched to.
        let hasExplicitActive = (store.activeFocusID[agent] != nil)
        return !hasExplicitActive && editing.isDefaultAtLaunch
    }

    private var focusHeadline: String {
        editingFocus?.name ?? "Default"
    }

    private var focusSubline: String {
        guard editingFocus != nil else {
            return "Setting up your default Focus…"
        }
        if isFocusActive {
            // Active Focus → show what's running.
            if let active = store.activeSession {
                let agent = active.agents.first.map { store.displayName(for: $0) } ?? "Agent"
                return "\(agent) running"
            }
            return "Running"
        }
        // Selected for editing but not the active one — Default is still
        // running in the background. Make that explicit.
        return "Editing — Default is running. Turn on to switch to this Focus."
    }

    private var toggleHelp: String {
        guard editingFocus != nil else { return "Default Focus is starting up" }
        return isFocusActive
            ? "Turn off to end this Focus's session and return to Default"
            : "Turn on to activate this Focus (replaces Default)"
    }

    private var activeToggleBinding: Binding<Bool> {
        Binding(
            get: { isFocusActive },
            set: { newValue in
                guard let editingID = store.resolvedEditingFocusID(for: activeAgentForChip) else { return }
                Task {
                    if newValue {
                        await store.setActiveFocus(presetID: editingID, targetApp: editingFocus?.targetApp)
                    } else {
                        // Flip-off: switch to Default rather than simply
                        // ending the session. Ending leaves activeFocusID
                        // pointing at the just-deactivated Focus, so
                        // isFocusActive recomputes back to true (Default
                        // fallback) and the toggle snaps ON again — bad
                        // UX. Switching to Default produces the visible
                        // state change the user expects ("Default is
                        // running again").
                        let agent = activeAgentForChip
                        if let defaultID = store.defaultLaunchFocusID[agent] ?? nil,
                           defaultID != editingID {
                            await store.setActiveFocus(presetID: defaultID, targetApp: editingFocus?.targetApp)
                        } else {
                            await store.endSession()
                        }
                    }
                }
            }
        )
    }

    /// Apply-to picker binding: writes target_app on the Focus's preset
    /// row. nil = both AIs (mirror). The target change is persisted via
    /// the savePreset call which preserves all other fields.
    private func applyToBinding(for focus: AccessPresetRecord) -> Binding<TargetApp?> {
        Binding(
            get: { focus.targetApp },
            set: { newValue in
                Task { await updateTargetApp(focus, to: newValue) }
            }
        )
    }

    /// Mirror toggle binding: writes mirror_to_both on the Focus's
    /// preset row. Flipping mirror=false → true on a Focus with diverged
    /// per-agent scope prompts a confirmation (the union behavior).
    private func mirrorBinding(for focus: AccessPresetRecord) -> Binding<Bool> {
        Binding(
            get: { focus.mirrorToBoth },
            set: { newValue in
                if newValue && !focus.mirrorToBoth {
                    // Going from separate → mirror needs the union prompt.
                    pendingSeparateSharingTarget = newValue
                    showSeparateSharingPrompt = true
                } else {
                    Task { await applyMirrorChange(toMirror: newValue) }
                }
            }
        )
    }

    private func updateTargetApp(_ focus: AccessPresetRecord, to newValue: TargetApp?) async {
        guard let client = store.runtime as? AppRuntimeClient else { return }
        do {
            _ = try await client.updatePresetTargetApp(presetID: focus.presetID, targetApp: newValue)
            await store.refreshFocuses()
        } catch {
            store.lastError = "Couldn't change Apply to: \(error.localizedDescription)"
        }
    }

    private func applyMirrorChange(toMirror newValue: Bool) async {
        guard let focus = editingFocus,
              let client = store.runtime as? AppRuntimeClient else { return }
        do {
            _ = try await client.updatePresetMirror(presetID: focus.presetID, mirrorToBoth: newValue)
            await store.refreshFocuses()
        } catch {
            store.lastError = "Couldn't change mirror mode: \(error.localizedDescription)"
        }
    }

    private struct ActiveSummary {
        let agent: TargetApp
        let folders: Int
        let mailboxes: Int
    }

    private var activeSummary: ActiveSummary? {
        if let active = store.activeSession {
            return ActiveSummary(
                agent: active.agents.first ?? store.defaultSessionAgent,
                folders: store.session.activeGrantSources.count,
                mailboxes: activeMailboxCount(for: store)
            )
        }
        if store.sessionStartupMode == .defaultSession {
            return ActiveSummary(
                agent: store.defaultSessionAgent,
                folders: store.defaultSourceIDs(for: store.defaultSessionAgent).count,
                mailboxes: 0
            )
        }
        return nil
    }

    private var headline: String {
        if let active = store.activeSession {
            if let name = store.session.activeGrant?.summaryFraming, !name.isEmpty {
                return name
            }
            return active.name
        }
        if store.sessionStartupMode == .defaultSession {
            return "Default session"
        }
        return "No session active"
    }

    private var subtext: String {
        if store.activeSession != nil {
            let agent = store.activeSession?.agents.first.map { store.displayName(for: $0) } ?? "Agent"
            return "\(agent) is active. Read and write approvals appear below."
        }
        if store.sessionStartupMode == .defaultSession {
            return "Manifold will start the default gateway when the runtime is connected."
        }
        return "Manual mode is on. Activate a prepared session to give an agent access."
    }

    private var startupLabel: String {
        switch store.sessionStartupMode {
        case .defaultSession: return "Default at launch"
        case .manual:         return "Manual"
        }
    }

    private func metric(systemImage: String, title: String, value: String, tint: Color? = nil) -> some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(tint ?? ManifoldPalette.text2)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(ManifoldType.bodyMedium)
                    .monospacedDigit()
                Text(title)
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .fill(ManifoldPalette.surface2.opacity(0.7))
        )
    }

    @ViewBuilder
    private func preparedSection(_ preload: SessionPreloadDraft) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Label("Prepared session", systemImage: "rectangle.stack")
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)
            HStack(spacing: Spacing.s2) {
                Text(preload.name.isEmpty ? "New session" : preload.name)
                    .font(ManifoldType.body)
                Pill(text: preload.baseMode.label, variant: .preview)
                Spacer()
                Button("Clear") { store.clearSessionPreload() }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.top, 4)
    }

    private var sessionRequestDetailControl: some View {
        let agent = store.activeSession?.agents.first ?? store.defaultSessionAgent
        let detail = SessionRequestDetail(level: store.effectiveRequestDetail(for: agent))
        let isSessionScoped = store.hasActiveRequestDetailOverride(for: agent)
        let scopeLabel = isSessionScoped
            ? "This session overrides \(store.displayName(for: agent))'s default."
            : (store.activeSession != nil
                ? "Using \(store.displayName(for: agent))'s default. Changes apply only to this session."
                : "Sets \(store.displayName(for: agent))'s default until a session-scoped override replaces it.")
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Label("Request detail", systemImage: "text.append")
                    .font(ManifoldType.captionMedium)
                    .foregroundStyle(.secondary)
                Spacer()
                if isSessionScoped {
                    Pill(text: "Session", variant: .session)
                    Button("Use default") {
                        Task { await store.clearRequestDetailOverride(for: agent) }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            Picker("Request detail", selection: Binding(
                get: { detail },
                set: { newValue in
                    Task {
                        if store.activeSession != nil {
                            // Active session: apply as a session-scoped
                            // override stored on the active grant.
                            await store.applyRequestDetailOverride(newValue.backingLevel, for: agent)
                        } else {
                            // No active session: this is a direct edit
                            // to the agent's persistent default.
                            await store.governance.updateAccessRecordingLevel(newValue.backingLevel, for: agent)
                        }
                    }
                }
            )) {
                ForEach(SessionRequestDetail.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("work.summary.requestDetail")
            Text("\(detail.subtitle) \(scopeLabel)")
                .font(ManifoldType.tiny)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private var fileMemoryAccessControl: some View {
        let agent = store.activeSession?.agents.first ?? store.defaultSessionAgent
        let isActive = store.activeSession != nil && store.session.activeGrant != nil
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            Toggle(isOn: Binding(
                get: { store.hasActiveFileMemoryAccess(for: agent) },
                set: { newValue in
                    Task { await store.applyFileMemoryAccess(newValue, for: agent) }
                }
            )) {
                Label("Allow file memory", systemImage: "clock.arrow.circlepath")
                    .font(ManifoldType.captionMedium)
            }
            .toggleStyle(.switch)
            .disabled(!isActive)
            .accessibilityIdentifier("work.summary.fileMemory")

            Text(isActive
                 ? "Memory is always saved. This lets \(store.displayName(for: agent)) query prior reads, writes, and notes for this session's file scope."
                 : "Memory is always saved. Activate a session to let an agent query prior file memory.")
                .font(ManifoldType.tiny)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private func detailLabel(for agent: TargetApp) -> String {
        let detail = SessionRequestDetail(level: store.effectiveRequestDetail(for: agent))
        return detail.label
    }

    private func memoryLabel(for agent: TargetApp) -> String {
        store.hasActiveFileMemoryAccess(for: agent) ? "On" : "Off"
    }
}

// MARK: - Pending approvals section

private struct WorkPendingApprovalsSection: View {
    @Environment(ManifoldStore.self) private var store
    @Bindable var work: WorkModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack {
                Label("Pending approvals", systemImage: "hand.raised")
                    .font(ManifoldType.bodyMedium)
                    .symbolEffect(.bounce, value: store.pendingRequests.count)
                Spacer()
                if !store.pendingRequests.isEmpty {
                    Pill(text: "\(store.pendingRequests.count) waiting", variant: .attention)
                } else {
                    Pill(text: "Clear", variant: .session)
                }
            }
            if store.pendingRequests.isEmpty {
                Text("Approvals will appear here when an agent asks for read, write, or mail access outside the current session's scope.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVStack(alignment: .leading, spacing: Spacing.s2) {
                    ForEach(store.pendingRequests) { request in
                        WorkApprovalRow(request: request, work: work)
                    }
                }
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
        .accessibilityIdentifier("work.approvals")
    }
}

private struct WorkApprovalRow: View {
    let request: ApprovalRequest
    @Bindable var work: WorkModel
    @Environment(ManifoldStore.self) private var store
    @State private var resolutionTrigger: Int = 0

    /// Resolves the approval through the store, but plays the local
    /// resolution animation first so the user feels the action land.
    /// The store call is delayed by `approvalResolutionDuration` so the
    /// row's keyframe sequence completes before the parent ForEach
    /// removes it.
    private func resolve(with answer: ApprovalAnswer) {
        resolutionTrigger += 1
        Task {
            try? await Task.sleep(nanoseconds: UInt64(approvalResolutionDuration * 1_000_000_000))
            await store.answer(request, with: answer)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Image(systemName: agentSymbol)
                .frame(width: 22, height: 22)
                .foregroundStyle(agentTint)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(agentTint.opacity(0.14))
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.s1) {
                    Text(request.headline)
                        .font(ManifoldType.bodyMedium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(request.createdAt.formatted(.relative(presentation: .named)))
                        .font(ManifoldType.tiny)
                        .foregroundStyle(.tertiary)
                }
                Text(request.target)
                    .font(ManifoldType.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                work.inspectorSelection = .request(approvalID: request.id)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(request.headline), \(request.target)")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("work.approval.\(request.id)")
            Spacer(minLength: 0)
            approvalActionButtons
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            work.inspectorSelection = .request(approvalID: request.id)
        }
        .accessibilityAction {
            work.inspectorSelection = .request(approvalID: request.id)
        }
        .background(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .fill(isSelected ? ManifoldPalette.selectionSoft : ManifoldPalette.surface2.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .strokeBorder(isSelected ? ManifoldPalette.selection.opacity(0.4) : ManifoldPalette.border, lineWidth: 0.5)
        )
        .approvalResolution(trigger: resolutionTrigger)
    }

    private var agentSymbol: String {
        switch request.operation {
        case .write: return "pencil"
        case .mailboxRead: return "envelope"
        case .searchContent: return "magnifyingglass"
        case .listDirectory: return "folder"
        case .readFolder: return "folder"
        case .readFile: return "doc"
        }
    }

    private var agentTint: Color {
        switch request.operation {
        case .write: return ManifoldPalette.attention
        default: return ManifoldPalette.selection
        }
    }

    private var isSelected: Bool {
        if case .request(let id) = work.inspectorSelection { return id == request.id }
        return false
    }

    private var approvalActionButtons: some View {
        HStack(spacing: Spacing.s1) {
            Button("Deny") { resolve(with: .notThisTime) }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .accessibilityIdentifier("work.approval.\(request.id).deny")
            // Standing-write requests get an inline "Add to default"
            // shortcut; everything else just gets "Allow once" inline,
            // with extra options in the inspector.
            if request.kind == .standingWrite {
                Menu {
                    Button("Allow once") { resolve(with: .once) }
                    Button("Add to default") { resolve(with: .addToDefault) }
                } label: {
                    Text("Allow…")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .accessibilityIdentifier("work.approval.\(request.id).allowMenu")
            } else {
                Button("Allow once") { resolve(with: .once) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("work.approval.\(request.id).once")
            }
        }
    }
}

// MARK: - Timeline section

private struct WorkTimelineSection: View {
    @Environment(ManifoldStore.self) private var store
    @Bindable var work: WorkModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack {
                Label("Activity", systemImage: "list.bullet.rectangle")
                    .font(ManifoldType.bodyMedium)
                Spacer()
            }

            if !store.connectionEvents.isEmpty {
                ConnectionEventsStrip(events: store.connectionEvents)
            }

            HStack(spacing: Spacing.s2) {
                ForEach(WorkTimelineFilter.allCases) { filter in
                    Button {
                        work.timelineFilter = filter
                    } label: {
                        Label(filter.label, systemImage: filter.systemImage)
                            .labelStyle(.titleAndIcon)
                            .font(ManifoldType.captionMedium)
                            .padding(.horizontal, Spacing.s2)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(work.timelineFilter == filter ? ManifoldPalette.selectionSoft : Color.clear)
                            )
                            .foregroundStyle(work.timelineFilter == filter ? ManifoldPalette.selection : ManifoldPalette.text2)
                            .overlay(
                                Capsule().strokeBorder(
                                    work.timelineFilter == filter ? ManifoldPalette.selection.opacity(0.35) : ManifoldPalette.border,
                                    lineWidth: 0.5
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("work.timeline.filter.\(filter.id)")
                }
            }

            if filteredEntries.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: Spacing.s2) {
                    ForEach(filteredEntries) { entry in
                        WorkTimelineCard(entry: entry, work: work)
                            .accessibilityIdentifier(timelineAccessibilityIdentifier(for: entry))
                    }
                }
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
        .accessibilityIdentifier("work.timeline")
    }

    private func timelineAccessibilityIdentifier(for entry: AuditEntry) -> String {
        if entry.action == AuditAction.sensitivityWarning.rawValue,
           let filePath = entry.filePath?.workAccessibilityIdentifierFragment {
            return "work.timeline.privacy.\(filePath)"
        }
        return "work.timeline.entry.\(entry.id)"
    }

    private var emptyState: some View {
        // Apple-native empty state per WWDC23 — ContentUnavailableView
        // with a generic "no activity" message instead of a flat Text.
        ContentUnavailableView(
            "No activity yet",
            systemImage: "list.bullet.rectangle",
            description: Text(emptyMessage)
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.s4)
    }

    private var emptyMessage: String {
        if !work.timelineSearch.trimmingCharacters(in: .whitespaces).isEmpty {
            return "No activity matches your search."
        }
        // Honest empty state: if Active/Default is selected but no
        // session is live, say so plainly. Prepared sessions have no
        // events yet by definition.
        switch work.sessionSelection {
        case .active, .defaultSession:
            if store.session.activeGrant == nil {
                return "No session is active. Activate a prepared session or wait for the default to start."
            }
        case .prepared:
            return "Prepared sessions have no activity until you activate them."
        case .recent:
            break
        }
        switch work.timelineFilter {
        case .all:
            return "Nothing has happened in this session yet. Reads, writes, and approvals will appear here as the agent works."
        case .approvals:
            return "No approval-related activity in this session."
        case .writes:
            return "No file writes in this session yet. Writes appear with restorable snapshots."
        case .reads:
            return "No file reads in this session yet."
        case .search:
            return "No searches in this session yet."
        case .blocked:
            return "Nothing was blocked in this session."
        }
    }

    private var filteredEntries: [AuditEntry] {
        let scope = scopedEntries
        let query = work.timelineSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return scope.filter { entry in
            guard work.timelineFilter.includes(entry) else { return false }
            guard !query.isEmpty else { return true }
            let haystack = [entry.action, entry.agent ?? "", entry.filePath ?? "", entry.metadata ?? ""]
                .joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(query)
        }
    }

    private var scopedEntries: [AuditEntry] {
        // The timeline answers "what happened in this session?" — when
        // the user picks Active or Default, scope to the matching
        // grant/session so the event list reflects ONLY that session's
        // work. Prepared sessions have no events yet, so we show an
        // explicit empty.
        switch work.sessionSelection {
        case .recent(let id):
            return store.activityEntries.filter { $0.sessionID == id || $0.grantID == id }
        case .active, .defaultSession:
            if let grant = store.session.activeGrant {
                return activeGrantEntries(grant)
            }
            return store.activityEntries
        case .prepared:
            return []
        }
    }

    private func activeGrantEntries(_ grant: GrantRecord) -> [AuditEntry] {
        store.activityEntries.filter { entry in
            if entry.grantID == grant.grantID || entry.sessionID == grant.grantID {
                return true
            }
            guard entry.agent == grant.targetApp else { return false }
            return entry.timestamp >= grant.startedAt
        }
    }
}

private struct WorkTimelineCard: View {
    let entry: AuditEntry
    @Bindable var work: WorkModel

    var body: some View {
        Button {
            // For write events, switch the inspector into the dedicated
            // write-version view so the user can see hashes/restore.
            if isWriteEvent, let snapshotID = snapshotID, let path = entry.filePath {
                work.inspectorSelection = .writeEvent(snapshotID: snapshotID, filePath: path)
            } else {
                work.inspectorSelection = .activityEvent(eventID: entry.id)
            }
        } label: {
            HStack(alignment: .top, spacing: Spacing.s3) {
                Image(systemName: presentation.symbol)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(presentation.color)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(presentation.color.opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.s1) {
                        Text(presentation.title)
                            .font(ManifoldType.bodyMedium)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(relativeTime)
                            .font(ManifoldType.tiny)
                            .foregroundStyle(.tertiary)
                    }
                    Text(presentation.detail)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .accessibilityIdentifier(contentAccessibilityIdentifier)
                Spacer(minLength: 0)
                Pill(text: presentation.outcomeLabel, variant: presentation.outcomeVariant)
            }
            .padding(Spacing.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .fill(isSelected ? ManifoldPalette.selectionSoft : ManifoldPalette.surface2.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .strokeBorder(isSelected ? ManifoldPalette.selection.opacity(0.4) : ManifoldPalette.border, lineWidth: 0.5)
        )
    }

    private var presentation: ActivityEventPresentation {
        ActivityEventPresentation(entry)
    }

    private var contentAccessibilityIdentifier: String {
        if let filePath = entry.filePath?.workAccessibilityIdentifierFragment {
            if entry.action == AuditAction.sensitivityWarning.rawValue {
                return "work.timeline.privacy.\(filePath).content"
            }
            if isWriteEvent {
                return "work.timeline.write.\(filePath).content"
            }
            if entry.action.contains("read") {
                return "work.timeline.read.\(filePath).content"
            }
        }
        return "work.timeline.entry.\(entry.id).content"
    }

    private var isWriteEvent: Bool {
        entry.action.contains("write")
            || entry.action == AuditAction.fileModified.rawValue
            || entry.action == AuditAction.fileCreated.rawValue
    }

    private var snapshotID: Int? {
        guard let metadata = entry.metadata,
              let data = metadata.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let id = json["snapshot_id"].flatMap(Int.init) else {
            return nil
        }
        return id
    }

    private var isSelected: Bool {
        switch work.inspectorSelection {
        case .activityEvent(let id):
            return id == entry.id
        case .writeEvent(let snapshot, let path):
            return path == entry.filePath && snapshotID == snapshot
        default:
            return false
        }
    }

    private var relativeTime: String {
        guard let date = ISO8601DateFormatter.shared.date(from: entry.timestamp) else { return "" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Runtime issue banner

struct WorkRuntimeIssue: Hashable {
    let title: String
    let primaryAction: String
    let actionKind: ActionKind
    let detail: String
    let lastChecked: Date

    enum ActionKind: Hashable {
        case retry
        case restart
        case reconnect
    }
}

@MainActor
private func workRuntimeIssue(store: ManifoldStore) -> WorkRuntimeIssue? {
    // Single source of truth: ManifoldStore.currentRuntimeIssue.
    // The view layer no longer matches strings — it reads the typed
    // enum and renders whatever the classifier decided.
    guard let issue = store.currentRuntimeIssue else { return nil }
    let actionKind: WorkRuntimeIssue.ActionKind = switch issue.recoveryAction {
    case .retry:     .retry
    case .restart:   .restart
    case .reconnect: .reconnect
    }
    return WorkRuntimeIssue(
        title: issue.title,
        primaryAction: issue.primaryActionLabel,
        actionKind: actionKind,
        detail: issue.detail,
        lastChecked: Date()
    )
}

private struct WorkRuntimeIssueBanner: View {
    let issue: WorkRuntimeIssue
    @Bindable var work: WorkModel
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ManifoldPalette.attention)
                Text(issue.title)
                    .font(ManifoldType.bodyMedium)
                Spacer()
                Button(issue.primaryAction) {
                    handleAction()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("work.runtimeIssue.action")
            }
            Button {
                work.inspectorSelection = .runtimeIssue
            } label: {
                Label("Details", systemImage: "info.circle")
                    .font(ManifoldType.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("work.runtimeIssue.details")
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .fill(ManifoldPalette.attention.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .strokeBorder(ManifoldPalette.attention.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityIdentifier("work.runtimeIssue")
    }

    private func handleAction() {
        switch issue.actionKind {
        case .retry:
            Task { await store.refresh() }
        case .restart:
            Task { await store.restartRuntimeHelper() }
        case .reconnect:
            Task { await store.reconnectAgentHelpers() }
        }
    }
}

// MARK: - Inspector

private struct WorkInspector: View {
    @Environment(ManifoldStore.self) private var store
    @Bindable var work: WorkModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                content
            }
            .padding(Spacing.s4)
        }
        .accessibilityIdentifier("work.inspector")
    }

    @ViewBuilder
    private var content: some View {
        switch work.inspectorSelection {
        case .none:
            emptyInspector
        case .session(let selection):
            WorkSessionInspector(selection: selection)
        case .request(let id):
            if let request = store.pendingRequests.first(where: { $0.id == id }) {
                WorkRequestInspector(request: request)
            } else {
                Text("Approval was answered.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
        case .activityEvent(let id):
            if let entry = store.activityEntries.first(where: { $0.id == id }) {
                WorkActivityInspector(entry: entry)
            } else {
                emptyInspector
            }
        case .writeEvent(let snapshotID, let path):
            WorkWriteInspector(snapshotID: snapshotID, filePath: path)
        case .runtimeIssue:
            WorkRuntimeIssueInspector(work: work)
        }
    }

    private var emptyInspector: some View {
        // HIG-canonical empty state. Per WWDC 2023 ("Inspectors in
        // SwiftUI"): when no item is selected, show ContentUnavailableView
        // rather than ad-hoc inline copy. Auto-centered, system-styled,
        // accessibility-correct.
        ContentUnavailableView(
            "Nothing Selected",
            systemImage: "sidebar.right",
            description: Text("Select a session, approval, or timeline event to see its details.")
        )
        .accessibilityIdentifier("work.inspector.empty")
    }
}

// MARK: Inspector — request

private struct WorkRequestInspector: View {
    let request: ApprovalRequest
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Label("Approval", systemImage: "hand.raised")
                .font(ManifoldType.bodyMedium)
            Text(request.headline)
                .font(ManifoldType.heading)
                .fixedSize(horizontal: false, vertical: true)
            Text(request.target)
                .font(ManifoldType.mono)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(request.context)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = request.findingsSummary {
                divider(label: "Privacy findings")
                Text(summary)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            divider(label: "Operation")
            operationDetails

            divider(label: "Actions")
            VStack(alignment: .leading, spacing: Spacing.s1) {
                // Deny first — the modeless default per Principle 3.
                Button {
                    Task { await store.answer(request, with: .notThisTime) }
                } label: {
                    Label("Deny", systemImage: "hand.raised")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .accessibilityIdentifier("work.inspector.request.deny")

                Button {
                    Task { await store.answer(request, with: .once) }
                } label: {
                    Label("Allow once", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityIdentifier("work.inspector.request.once")

                if request.kind == .standingWrite {
                    Button {
                        Task { await store.answer(request, with: .addToDefault) }
                    } label: {
                        Label("Add to default", systemImage: "plus.rectangle.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.regular)
                    .accessibilityIdentifier("work.inspector.request.addToDefault")
                    Text("Promotes the requested folder to the agent's standing scope so future writes don't ask again.")
                        .font(ManifoldType.tiny)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if request.kind == .privacyExposure {
                    Button {
                        Task { await store.answer(request, with: .shareRedacted) }
                    } label: {
                        Label("Share redacted", systemImage: "text.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.regular)
                    .accessibilityIdentifier("work.inspector.request.redact")

                    Button {
                        Task { await store.answer(request, with: .shareOriginalOnce) }
                    } label: {
                        Label("Share original once", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.regular)
                    .accessibilityIdentifier("work.inspector.request.shareOriginalOnce")
                    Text("Shares the unredacted payload one time; the privacy filter still records the exposure.")
                        .font(ManifoldType.tiny)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Reveals the operation, agent, and a one-line description of
    /// what allowing the request would let the agent do. Closes the
    /// "what does this actually mean?" gap the review flagged.
    private var operationDetails: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            HStack(spacing: Spacing.s2) {
                Text("Agent")
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(AgentMeta.label(request.agent))
                    .font(ManifoldType.caption)
            }
            HStack(spacing: Spacing.s2) {
                Text("Operation")
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(operationLabel)
                    .font(ManifoldType.caption)
            }
            HStack(spacing: Spacing.s2) {
                Text("Kind")
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(kindLabel)
                    .font(ManifoldType.caption)
            }
        }
    }

    private var operationLabel: String {
        switch request.operation {
        case .readFile:       return "Read file"
        case .readFolder:     return "Read folder"
        case .write:          return "Write file"
        case .searchContent:  return "Search content"
        case .listDirectory:  return "List directory"
        case .mailboxRead:    return "Read mailbox"
        }
    }

    private var kindLabel: String {
        switch request.kind {
        case .standingWrite:    return "Standing write"
        case .privacyExposure:  return "Privacy review"
        }
    }

    private func divider(label: String) -> some View {
        HStack(spacing: Spacing.s2) {
            Text(label.uppercased())
                .font(ManifoldType.tiny.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
            Rectangle()
                .fill(ManifoldPalette.border)
                .frame(height: 0.5)
        }
        .padding(.top, Spacing.s2)
    }
}

// MARK: Inspector — activity event

private struct WorkActivityInspector: View {
    let entry: AuditEntry

    var body: some View {
        let presentation = ActivityEventPresentation(entry)
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Label("Event", systemImage: presentation.symbol)
                .font(ManifoldType.bodyMedium)
            Text(presentation.title)
                .font(ManifoldType.heading)
                .fixedSize(horizontal: false, vertical: true)
            if let path = entry.filePath {
                Text(path)
                    .font(ManifoldType.mono)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(presentation.detail)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let agent = entry.agent {
                inspectorRow(label: "Agent", value: agent)
            }
            if let metadata = entry.metadata, !metadata.isEmpty {
                Text("Metadata")
                    .font(ManifoldType.tiny.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text(metadata)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier(inspectorAccessibilityIdentifier)
    }

    private var inspectorAccessibilityIdentifier: String {
        guard let filePath = entry.filePath?.workAccessibilityIdentifierFragment else {
            return "work.inspector.event.\(entry.id)"
        }
        return "work.inspector.event.\(filePath)"
    }

    private func inspectorRow(label: String, value: String) -> some View {
        HStack(spacing: Spacing.s2) {
            Text(label).foregroundStyle(.secondary)
            Text(value).foregroundStyle(.primary)
        }
        .font(ManifoldType.caption)
    }
}

private extension String {
    var workAccessibilityIdentifierFragment: String {
        replacingOccurrences(of: "/", with: ".")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }
}

// MARK: Inspector — write event

private struct WorkWriteInspector: View {
    let snapshotID: Int
    let filePath: String
    @Environment(ManifoldStore.self) private var store
    @State private var restoreMessage: String?
    @State private var isRestoring = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Label("Write", systemImage: "pencil")
                .font(ManifoldType.bodyMedium)
            Text(URL(fileURLWithPath: filePath).lastPathComponent)
                .font(ManifoldType.heading)
                .fixedSize(horizontal: false, vertical: true)
            Text(filePath)
                .font(ManifoldType.mono)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            // Hashes prefer the SessionEvent (loaded only when the
            // user picks a recent session), but fall back to the
            // matching AuditEntry from the global activity feed so
            // the inspector still shows real before/after hashes for
            // active-session writes without forcing a synchronous
            // load.
            let (beforeHash, afterHash) = matchingHashes
            if let beforeHash {
                hashRow(label: "Before", value: shortHash(beforeHash))
            }
            if let afterHash {
                hashRow(label: "After", value: shortHash(afterHash))
            }
            hashRow(label: "Snapshot", value: "#\(snapshotID)")
            if beforeHash == nil && afterHash == nil {
                Text("Hashes load when the session events finish syncing.")
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.tertiary)
            }

            Button {
                isRestoring = true
                Task {
                    let outcome = await store.session.restoreFile(snapshotID: snapshotID, filePath: filePath)
                    restoreMessage = outcome.message ?? (outcome.status == "success" ? "Restored from #\(snapshotID)." : nil)
                    isRestoring = false
                }
            } label: {
                if isRestoring {
                    HStack { ProgressView().controlSize(.small); Text("Restoring…") }
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Restore this version", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRestoring)
            .accessibilityIdentifier("work.inspector.write.restore")

            if let restoreMessage {
                Text(restoreMessage)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var matchingEvent: SessionEvent? {
        store.activity.sessionEvents.first { event in
            event.snapshotID == snapshotID && event.filePath == filePath
        }
    }

    /// Returns the best available before/after hash pair for this
    /// snapshot. SessionEvent first (richest metadata), AuditEntry
    /// from the global feed second (always loaded for active sessions).
    private var matchingHashes: (before: String?, after: String?) {
        if let event = matchingEvent {
            return (event.beforeHash, event.afterHash)
        }
        // Fallback: match against the global activity entries by file
        // path AND snapshot id (parsed from metadata).
        for entry in store.activityEntries where entry.filePath == filePath {
            if let metadata = entry.metadata,
               let data = metadata.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let snap = json["snapshot_id"].flatMap(Int.init),
               snap == snapshotID {
                return (entry.beforeHash, entry.afterHash)
            }
        }
        return (nil, nil)
    }

    private func hashRow(label: String, value: String) -> some View {
        HStack(spacing: Spacing.s2) {
            Text(label).foregroundStyle(.secondary)
            Text(value).font(ManifoldType.mono).textSelection(.enabled)
        }
        .font(ManifoldType.caption)
    }

    private func shortHash(_ hash: String) -> String {
        guard hash.count > 14 else { return hash }
        return "\(hash.prefix(10))…"
    }
}

// MARK: Inspector — session

private struct WorkSessionInspector: View {
    let selection: WorkSessionSelection
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            switch selection {
            case .active:
                activeSessionInspector
            case .defaultSession:
                defaultSessionInspector
            case .prepared:
                preparedInspector
            case .recent(let id):
                recentInspector(sessionID: id)
            }
        }
    }

    @ViewBuilder
    private var activeSessionInspector: some View {
        if let session = store.activeSession {
            Label("Session", systemImage: "rectangle.stack.badge.play")
                .font(ManifoldType.bodyMedium)
            Text(store.session.activeGrant?.summaryFraming ?? session.name)
                .font(ManifoldType.heading)
                .fixedSize(horizontal: false, vertical: true)
            inspectorRow(label: "Agent", value: session.agents.first.map { store.displayName(for: $0) } ?? "Agent")
            inspectorRow(label: "Folders", value: "\(store.session.activeGrantSources.count)")
            inspectorRow(label: "Mailboxes", value: "\(activeMailboxCount(for: store))")
            inspectorRow(label: "Pending", value: "\(store.pendingRequests.count)")
            Button(role: .destructive) {
                Task { await store.endSession() }
            } label: {
                Label("End session", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.regular)
            .accessibilityIdentifier("work.inspector.session.end")
        } else {
            Text("Session ended.").font(ManifoldType.caption).foregroundStyle(.secondary)
        }
    }

    private var defaultSessionInspector: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Label("Default session", systemImage: "circle.dashed")
                .font(ManifoldType.bodyMedium)
            Text("\(store.displayName(for: store.defaultSessionAgent)) at launch")
                .font(ManifoldType.heading)
            Text("Default sessions start automatically when the runtime is connected and use the agent's default folders.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            inspectorRow(label: "Folders", value: "\(store.defaultSourceIDs(for: store.defaultSessionAgent).count)")
        }
    }

    @ViewBuilder
    private var preparedInspector: some View {
        if store.sessionWorkbench.preload != nil {
            WorkPreloadEditor()
        } else {
            Label("Prepared", systemImage: "rectangle.stack")
                .font(ManifoldType.bodyMedium)
            Text("No prepared session.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: Spacing.s2) {
                Button {
                    store.beginSessionPreload(agent: store.defaultSessionAgent, baseMode: .buildOnDefault)
                } label: {
                    Label("Build on default", systemImage: "plus.rectangle.on.rectangle")
                }
                .controlSize(.small)
                Button {
                    store.beginSessionPreload(agent: store.defaultSessionAgent, baseMode: .blank)
                } label: {
                    Label("Start blank", systemImage: "plus.rectangle")
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func recentInspector(sessionID: String) -> some View {
        if let session = store.activity.sessions.first(where: { $0.id == sessionID }) {
            Label("Recent session", systemImage: "clock")
                .font(ManifoldType.bodyMedium)
            Text("\(AgentMeta.label(TargetApp(rawValue: session.agent) ?? .cowork)) session")
                .font(ManifoldType.heading)
            inspectorRow(label: "Reads", value: "\(session.readCount)")
            inspectorRow(label: "Writes", value: "\(session.writeCount)")
            inspectorRow(label: "Searches", value: "\(session.searchCount)")
            inspectorRow(label: "Events", value: "\(session.actionCount)")
        } else {
            Text("Session not found.").font(ManifoldType.caption).foregroundStyle(.secondary)
        }
    }

    private func inspectorRow(label: String, value: String) -> some View {
        HStack(spacing: Spacing.s2) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary)
        }
        .font(ManifoldType.caption)
    }
}

// MARK: - Preload editor (used by the prepared-session inspector)

/// Full-fidelity editor for a `SessionPreloadDraft`. Lets the user
/// name the prepared session, switch agents, choose `buildOnDefault`
/// vs `blank`, toggle individual folders, save it as a template, and
/// activate it. Reuses the existing `SessionWorkbenchModel` so changes
/// are durable across navigation.
private struct WorkPreloadEditor: View {
    @Environment(ManifoldStore.self) private var store
    @State private var availableEmails: [EmailMessageRecord] = []
    @State private var isLoadingEmails = false
    @State private var emailLoadError: String?

    private var availableSources: [SourceRecord] {
        store.sources
            .filter { !$0.isRemoved }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        if let preload = store.sessionWorkbench.preload {
            let defaultIDs = store.defaultSourceIDs(for: preload.agent)
            let effective = preload.effectiveSourceIDs(defaultSourceIDs: defaultIDs)

            VStack(alignment: .leading, spacing: Spacing.s3) {
                Label("Prepared session", systemImage: "rectangle.stack")
                    .font(ManifoldType.bodyMedium)

                TextField("Session name", text: nameBinding)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("work.preload.name")

                Picker("Agent", selection: agentBinding) {
                    ForEach(store.connectedOrDefaultAgents(), id: \.self) { agent in
                        Text(store.displayName(for: agent)).tag(agent)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("work.preload.agent")

                Picker("Base", selection: baseModeBinding) {
                    ForEach(PreloadBaseMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("work.preload.base")

                Text(preload.baseMode.subtitle)
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                requestDetailPicker(preload: preload)
                fileMemoryToggle(preload: preload)

                folderList(preload: preload, defaultIDs: defaultIDs, effective: effective)

                HStack(spacing: Spacing.s1) {
                    Image(systemName: "folder")
                        .font(ManifoldType.tiny)
                        .foregroundStyle(.tertiary)
                    Text("\(effective.count) folder\(effective.count == 1 ? "" : "s") selected")
                        .font(ManifoldType.tiny)
                        .foregroundStyle(.tertiary)
                }

                emailList(preload: preload)

                actionRow(preload: preload)

                if let message = store.sessionWorkbench.lastMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(ManifoldType.tiny)
                        .foregroundStyle(ManifoldPalette.active)
                }
                if let error = store.sessionWorkbench.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(ManifoldType.tiny)
                        .foregroundStyle(.red)
                }
            }
            .task(id: preload.agent) {
                await loadEmails(for: preload.agent)
            }
        }
    }

    private struct PreloadDetailOption: Hashable, Identifiable {
        let label: String
        let level: AccessRecordingLevel?
        var id: String { level?.rawValue ?? "default" }
    }

    private static let preloadDetailOptions: [PreloadDetailOption] = [
        PreloadDetailOption(label: "Agent default", level: nil),
        PreloadDetailOption(label: "Off", level: .lightweight),
        PreloadDetailOption(label: "Brief", level: .summary),
        PreloadDetailOption(label: "Detailed", level: .detailed),
    ]

    @ViewBuilder
    private func requestDetailPicker(preload: SessionPreloadDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Request detail", systemImage: "text.append")
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)
            Picker("Request detail", selection: Binding(
                get: { preload.requestDetailOverride },
                set: { newValue in
                    guard var draft = store.sessionWorkbench.preload else { return }
                    draft.requestDetailOverride = newValue
                    store.sessionWorkbench.preload = draft
                }
            )) {
                ForEach(Self.preloadDetailOptions) { option in
                    Text(option.label).tag(option.level)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("work.preload.requestDetail")
            Text(preload.requestDetailOverride == nil
                 ? "Will use \(store.displayName(for: preload.agent))'s default request detail."
                 : "Overrides the agent default for this session only. Reverts when the session ends.")
                .font(ManifoldType.tiny)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fileMemoryToggle(preload: SessionPreloadDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { preload.allowFileMemory },
                set: { newValue in
                    guard var draft = store.sessionWorkbench.preload else { return }
                    draft.allowFileMemory = newValue
                    store.sessionWorkbench.preload = draft
                }
            )) {
                Label("Allow file memory", systemImage: "clock.arrow.circlepath")
                    .font(ManifoldType.captionMedium)
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier("work.preload.fileMemory")

            Text("Past activity is recorded regardless. Turn this on if the agent should be able to recall what happened with these files in earlier sessions.")
                .font(ManifoldType.tiny)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func folderList(preload: SessionPreloadDraft, defaultIDs: Set<String>, effective: Set<String>) -> some View {
        if availableSources.isEmpty {
            Text("Add a folder in Access first.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(availableSources) { source in
                    folderRow(source, preload: preload, defaultIDs: defaultIDs, effective: effective)
                    if source.sourceID != availableSources.last?.sourceID {
                        Divider()
                    }
                }
            }
            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
            )
        }
    }

    private func folderRow(_ source: SourceRecord, preload: SessionPreloadDraft, defaultIDs: Set<String>, effective: Set<String>) -> some View {
        Toggle(isOn: Binding(
            get: { effective.contains(source.sourceID) },
            set: { store.setPreloadSource(sourceID: source.sourceID, included: $0) }
        )) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(ManifoldPalette.selection)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(source.displayName)
                            .font(ManifoldType.body)
                            .lineLimit(1)
                        if let badge = badge(sourceID: source.sourceID, preload: preload, defaultIDs: defaultIDs, effective: effective) {
                            Text(badge)
                                .font(ManifoldType.tiny)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.tertiary.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(source.effectiveRootPath)
                        .font(ManifoldType.tiny.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, Spacing.s1)
        .accessibilityIdentifier("work.preload.source.\(source.sourceID)")
    }

    private func badge(sourceID: String, preload: SessionPreloadDraft, defaultIDs: Set<String>, effective: Set<String>) -> String? {
        guard preload.baseMode == .buildOnDefault else { return nil }
        let inDefault = defaultIDs.contains(sourceID)
        let selected = effective.contains(sourceID)
        if inDefault && !selected { return "removed" }
        if !inDefault && selected { return "added" }
        if inDefault { return "default" }
        return nil
    }

    @ViewBuilder
    private func emailList(preload: SessionPreloadDraft) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Label("Email scope", systemImage: "envelope")
                    .font(ManifoldType.captionMedium)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(preload.selectedEmailIDs.count) selected")
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.tertiary)
                if !preload.selectedEmailIDs.isEmpty {
                    Button("Clear") {
                        store.clearPreloadEmails()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }

            if isLoadingEmails {
                HStack(spacing: Spacing.s2) {
                    ProgressView().controlSize(.small)
                    Text("Loading mail…")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let emailLoadError {
                Text(emailLoadError)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.red)
            } else if availableEmails.isEmpty {
                Text("No synced emails available. Add mail in Mail first.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(mailboxGroups) { group in
                        mailboxRow(group, preload: preload)
                        Divider()
                    }
                    ForEach(availableEmails.prefix(20)) { email in
                        emailRow(email, preload: preload)
                        if email.id != availableEmails.prefix(20).last?.id {
                            Divider()
                        }
                    }
                }
                .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                        .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
                )
                Text("Mailbox toggles apply to the recent messages shown here. Use Mail for deeper search and sharing.")
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private struct MailboxGroup: Identifiable {
        let id: String
        let label: String
        let emailIDs: Set<String>
    }

    private var mailboxGroups: [MailboxGroup] {
        let grouped = Dictionary(grouping: availableEmails) { email in
            "\(email.accountID)::\(email.mailbox)"
        }
        return grouped.map { key, emails in
            let sample = emails[0]
            return MailboxGroup(
                id: key,
                label: "\(sample.mailbox) (\(emails.count))",
                emailIDs: Set(emails.map(\.emailID))
            )
        }
        .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        .prefix(6)
        .map { $0 }
    }

    private func mailboxRow(_ group: MailboxGroup, preload: SessionPreloadDraft) -> some View {
        let selected = !group.emailIDs.isDisjoint(with: preload.selectedEmailIDs)
        let allSelected = group.emailIDs.isSubset(of: preload.selectedEmailIDs)
        return Toggle(isOn: Binding(
            get: { allSelected },
            set: { store.setPreloadEmails(emailIDs: group.emailIDs, included: $0) }
        )) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: selected ? "tray.full.fill" : "tray")
                    .foregroundStyle(selected ? ManifoldPalette.selection : .secondary)
                    .frame(width: 16)
                Text(group.label)
                    .font(ManifoldType.body)
                    .lineLimit(1)
                if selected && !allSelected {
                    Text("partial")
                        .font(ManifoldType.tiny)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.tertiary.opacity(0.15), in: Capsule())
                }
                Spacer()
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, Spacing.s1)
        .accessibilityIdentifier("work.preload.mailbox.\(group.id)")
    }

    private func emailRow(_ email: EmailMessageRecord, preload: SessionPreloadDraft) -> some View {
        Toggle(isOn: Binding(
            get: { preload.selectedEmailIDs.contains(email.emailID) },
            set: { store.setPreloadEmail(emailID: email.emailID, included: $0) }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                Text(email.subject.isEmpty ? "(No subject)" : email.subject)
                    .font(ManifoldType.body)
                    .lineLimit(1)
                Text("\(email.sender) · \(email.mailbox)")
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, Spacing.s1)
        .accessibilityIdentifier("work.preload.email.\(email.emailID)")
    }

    @MainActor
    private func loadEmails(for agent: TargetApp) async {
        isLoadingEmails = true
        emailLoadError = nil
        let shared = await store.mailAccounts.sharedEmails(agent: agent, limit: 200)
        let all = await store.mailAccounts.allMessages(limit: 200)
        let selectedIDs = store.sessionWorkbench.preload?.selectedEmailIDs ?? []
        let selected = selectedIDs.isEmpty ? [] : await store.mailAccounts.messages(ids: Array(selectedIDs))
        var seen: Set<String> = []
        availableEmails = (shared + selected + all).filter { seen.insert($0.emailID).inserted }
        emailLoadError = store.mailAccounts.lastQueryError
        isLoadingEmails = false
    }

    private func actionRow(preload: SessionPreloadDraft) -> some View {
        HStack(spacing: Spacing.s2) {
            Button {
                Task { await store.activateSessionPreload() }
            } label: {
                if store.sessionWorkbench.isActivating {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Activating…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("Activate", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(store.sessionWorkbench.isActivating)
            .accessibilityIdentifier("work.preload.activate")

            Button {
                Task { await store.saveSessionPreload() }
            } label: {
                if store.sessionWorkbench.isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Save", systemImage: "tray.and.arrow.down")
                }
            }
            .controlSize(.regular)
            .disabled(preload.hasUnsavedName || store.sessionWorkbench.isSaving)
            .accessibilityIdentifier("work.preload.save")

            Button("Clear") { store.clearSessionPreload() }
                .controlSize(.regular)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("work.preload.clear")
        }
    }

    // MARK: Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { store.sessionWorkbench.preload?.name ?? "" },
            set: { value in
                guard var draft = store.sessionWorkbench.preload else { return }
                draft.name = value
                store.sessionWorkbench.preload = draft
            }
        )
    }

    private var agentBinding: Binding<TargetApp> {
        Binding(
            get: { store.sessionWorkbench.preload?.agent ?? store.defaultSessionAgent },
            set: { store.setPreloadAgent($0) }
        )
    }

    private var baseModeBinding: Binding<PreloadBaseMode> {
        Binding(
            get: { store.sessionWorkbench.preload?.baseMode ?? .buildOnDefault },
            set: { store.setPreloadBaseMode($0) }
        )
    }
}

// MARK: Inspector — runtime issue

private struct WorkRuntimeIssueInspector: View {
    @Bindable var work: WorkModel
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Label("Runtime", systemImage: "antenna.radiowaves.left.and.right.slash")
                .font(ManifoldType.bodyMedium)
            Text(title)
                .font(ManifoldType.heading)
            Text(shortMessage)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.s2) {
                if isStaleHelper {
                    // Stale-helper case: relaunching the agent's
                    // helper is the targeted fix. Restart Runtime
                    // demoted to a secondary action.
                    Button {
                        Task { await store.reconnectAgentHelpers() }
                    } label: {
                        Label("Reconnect agents", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .accessibilityIdentifier("work.inspector.runtime.reconnect")

                    Button {
                        Task { await store.restartRuntimeHelper() }
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.regular)
                    .accessibilityIdentifier("work.inspector.runtime.restart")
                } else {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.regular)
                    .accessibilityIdentifier("work.inspector.runtime.retry")

                    Button {
                        Task { await store.restartRuntimeHelper() }
                    } label: {
                        Label("Restart", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .accessibilityIdentifier("work.inspector.runtime.restart")
                }
            }

            DisclosureGroup(isExpanded: $work.runtimeIssueDisclosureExpanded) {
                Text(rawDetail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } label: {
                Label("Details", systemImage: "info.circle")
                    .font(ManifoldType.caption)
            }
            .accessibilityIdentifier("work.inspector.runtime.details")
        }
    }

    private var isStaleHelper: Bool {
        let combined = ((store.runtimeLaunchError ?? "") + " " + (store.lastError ?? "")).lowercased()
        return combined.contains("stale") || combined.contains("reconnect")
    }

    private var title: String {
        if isStaleHelper { return "Agent helper out of date" }
        if !store.isRuntimeConnected { return "Runtime unavailable" }
        if (store.lastError ?? "").isEmpty == false { return "Runtime needs restart" }
        return "Runtime healthy"
    }

    private var shortMessage: String {
        if isStaleHelper {
            return "Claude or Codex is using an older copy of the Manifold helper. Reconnecting will relaunch it from the up-to-date binary."
        }
        if !store.isRuntimeConnected {
            return "Manifold can't reach the runtime helper. Try retry, then restart."
        }
        if !(store.lastError ?? "").isEmpty {
            return "Restarting the runtime helper usually clears this state."
        }
        return "The runtime is connected and ready."
    }

    private var rawDetail: String {
        let parts = [
            store.runtimeLaunchError,
            store.lastError,
        ]
        let joined = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        return joined.isEmpty ? "No additional diagnostics available." : joined
    }
}
