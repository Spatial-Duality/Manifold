// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// MenuBarPanelView — the primary Manifold surface.
//
// Per Stage 2, the menu bar panel is where ~95% of user contact happens.
// It answers the only two questions a user ever has about a trust product:
// "is it working?" and "what did it just do?". Four states, each matching
// a concrete runtime condition (design/html/menubar.html):
//
//   1. idle — no scope shared
//   2. idleWithRecent — scope shared, no session, recent sessions present
//   3. activeWithQueue — session running, 0+ pending requests
//   4. trackedEdit — session with writes being tracked
//
// Copy is user-as-subject (Principle 5). Pulse halo respects
// reduce-motion (Principle 9). No emoji (Stage 3 §I).

import SwiftUI
import ManifoldKit

struct MenuBarPanelView: View {
    @Environment(ManifoldStore.self) private var store
    @Environment(CommandPaletteModel.self) private var commandPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum PanelState {
        case idle
        case idleWithRecent
        case activeWithQueue
        case trackedEdit
    }

    private var panelState: PanelState {
        if let block = store.dataControlSummary?.activeWorkBlock {
            return (block.modifiedFileCount > 0 || block.newFileCount > 0) ? .trackedEdit : .activeWithQueue
        }
        if let session = store.activeSession {
            return session.isTrackedEdit ? .trackedEdit : .activeWithQueue
        }
        if !store.recentSessionEntries.isEmpty || !store.sources.isEmpty {
            return .idleWithRecent
        }
        return .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusHeader(store: store, state: panelState, reduceMotion: reduceMotion)

            if let session = store.activeSession {
                Divider()
                if session.isTrackedEdit {
                    TrackedEditStrip(session: session, store: store)
                } else {
                    SessionChipStrip(session: session, store: store)
                }
            }

            if store.governance.privacySettings != nil {
                Divider()
                PrivacyPresetChipStrip(store: store)
            }

            if !store.pendingRequests.isEmpty {
                Divider()
                RequestsQueueSection(store: store)
            }

            if panelState != .idle {
                Divider()
                AgentSummaryBlock(store: store, state: panelState)
            }

            if panelState == .idleWithRecent, !store.recentSessionEntries.isEmpty {
                Divider()
                RecentSessionsBlock(sessions: store.recentSessionEntries, store: store)
            }

            Divider()
            FooterActions(store: store, commandPalette: commandPalette, state: panelState)
        }
        .frame(width: 360)
        .accessibilityIdentifier("menubar.panel")
        .task {
            await store.refreshAll()
        }
    }
}

// MARK: - Status header

private struct StatusHeader: View {
    let store: ManifoldStore
    let state: MenuBarPanelView.PanelState
    let reduceMotion: Bool
    @State private var pulse = false

    private var dotStatus: AgentStatusDot.Status {
        if !store.isRuntimeConnected { return .offline }
        switch state {
        case .idle, .idleWithRecent:          return .paused
        case .activeWithQueue, .trackedEdit:  return .active
        }
    }

    private var headlinePrimary: String {
        if !store.isRuntimeConnected {
            return "Manifold can't reach the runtime."
        }
        if let block = store.dataControlSummary?.activeWorkBlock {
            return "\(AgentMeta.label(block.agent)) session is live."
        }
        if let summary = store.dataControlSummary, !summary.agents.isEmpty {
            return summary.agents
                .map { "\($0.defaultFileScopeCount) folders/\($0.visibleEmailCount) emails for \(AgentMeta.label($0.agent))" }
                .joined(separator: " · ")
        }
        let folderCount = store.sources.filter(\.isAccessible).count
        switch state {
        case .idle:
            return "You haven't shared anything yet."
        case .idleWithRecent:
            return folderCount == 0
                ? "No agents are running."
                : "Default scope: \(folderCount) folder\(folderCount == 1 ? "" : "s")."
        case .activeWithQueue:
            let session = store.activeSession
            return "Session running: \(session?.name ?? "unnamed")."
        case .trackedEdit:
            return "Session in progress."
        }
    }

    private var headlineSecondary: String {
        if let error = store.runtimeLaunchError ?? store.lastError {
            return error
        }
        if let summary = store.dataControlSummary {
            if summary.pendingApprovalCount > 0 {
                return "\(summary.pendingApprovalCount) request\(summary.pendingApprovalCount == 1 ? "" : "s") waiting on you."
            }
            if let exposure = summary.lastExposure {
                return "Last exposure: \(exposureLabel(exposure))."
            }
            if summary.agents.allSatisfy(\.isPaused) {
                return "All agents are paused."
            }
        }
        switch state {
        case .idle:
            return "Manifold is running. Add a folder or mailbox for your next session."
        case .idleWithRecent:
            if let last = store.recentSessionEntries.first {
                return "Last session: \(last.name), \(last.displayLastRun)."
            }
            return "No session running."
        case .activeWithQueue:
            let count = store.pendingRequests.count
            if count > 0 { return "\(count) request\(count == 1 ? "" : "s") waiting on you." }
            return "No requests right now. Working quietly."
        case .trackedEdit:
            return "All writes tracked — every change is reversible."
        }
    }

    private func exposureLabel(_ exposure: DataControlSummary.Exposure) -> String {
        let agent = exposure.agent.map(AgentMeta.label) ?? "agent"
        let resource = exposure.resourcePath?.lastPathComponentForDisplay ?? "data"
        return "\(agent) \(exposure.action) \(resource)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            AgentStatusDot(status: dotStatus, size: 8, pulses: true)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(headlinePrimary)
                    .font(ManifoldType.bodyMedium)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(headlineSecondary)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.top, Spacing.s4)
        .padding(.bottom, Spacing.s3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headlinePrimary). \(headlineSecondary)")
    }
}

// MARK: - Session chip (non-tracked)

private struct SessionChipStrip: View {
    let session: SessionRecord
    let store: ManifoldStore

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Circle()
                .fill(ManifoldPalette.active)
                .frame(width: 7, height: 7)
            Text("SESSION")
                .font(ManifoldType.tiny)
                .foregroundStyle(.secondary)
                .tracking(0.4)
            Text(session.name)
                .font(ManifoldType.bodyMedium)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Spacing.s2)
            if let remaining = session.remainingSeconds {
                Text(SessionChip.format(remaining))
                    .font(ManifoldType.numericCaption)
                    .foregroundStyle(.secondary)
            }
            Button("Finish") {
                Task { try? await store.finishActiveSession() }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(ManifoldPalette.activeSoft)
    }
}

// MARK: - Session strip

private struct TrackedEditStrip: View {
    let session: SessionRecord
    let store: ManifoldStore

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: "timeline.selection")
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.claude)
            VStack(alignment: .leading, spacing: 1) {
                Text("SESSION")
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.primary)
                    .tracking(0.5)
                Text(session.name)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Spacing.s2)
            Button("Finish") {
                Task { try? await store.finishActiveSession() }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .background(ManifoldPalette.selectionSoft)
    }
}

// MARK: - Privacy preset chip

/// Compact "Privacy: Balanced ▾" chip. Tapping opens a menu offering the
/// same four presets the Settings pane exposes; applying a preset calls
/// `updatePrivacySettings` + seeds per-agent policies, keeping the menu
/// bar and Settings perfectly in sync.
private struct PrivacyPresetChipStrip: View {
    let store: ManifoldStore

    private var currentPreset: PrivacyPreset {
        PrivacyPreset.detect(
            settings: store.governance.privacySettings,
            claudePolicy: store.governance.claudePrivacyPolicy,
            codexPolicy: store.governance.codexPrivacyPolicy
        )
    }

    private var presetLabel: String {
        switch currentPreset {
        case .off:      return "Off"
        case .balanced: return "Balanced"
        case .strict:   return "Strict"
        case .custom:   return "Custom"
        }
    }

    private var presetAccent: Color {
        switch currentPreset {
        case .off:      return ManifoldPalette.text3
        case .balanced: return ManifoldPalette.selection
        case .strict:   return ManifoldPalette.danger
        case .custom:   return ManifoldPalette.claude
        }
    }

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: "shield.lefthalf.filled")
                .font(ManifoldType.caption)
                .foregroundStyle(presetAccent)
            Text("PRIVACY")
                .font(ManifoldType.tiny)
                .foregroundStyle(.secondary)
                .tracking(0.4)

            Menu {
                Button {
                    apply(.off)
                } label: {
                    Label("Off — no filtering", systemImage: currentPreset == .off ? "checkmark" : "shield.slash")
                }
                .accessibilityIdentifier("menubar.privacy.apply.off")
                Button {
                    apply(.balanced)
                } label: {
                    Label("Balanced — warn personal, ask before secrets",
                          systemImage: currentPreset == .balanced ? "checkmark" : "shield.lefthalf.filled")
                }
                .accessibilityIdentifier("menubar.privacy.apply.balanced")
                Button {
                    apply(.strict)
                } label: {
                    Label("Strict — redact PII, block secrets",
                          systemImage: currentPreset == .strict ? "checkmark" : "shield.fill")
                }
                .accessibilityIdentifier("menubar.privacy.apply.strict")
                Divider()
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("Open Privacy settings…", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("menubar.privacy.openSettings")
            } label: {
                HStack(spacing: 4) {
                    Text(presetLabel)
                        .font(ManifoldType.bodyMedium)
                        .foregroundStyle(presetAccent)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(presetAccent)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier("menubar.privacy.menu")

            Spacer(minLength: Spacing.s2)
            if currentPreset == .custom {
                Text("Hand-tuned")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(presetAccent.opacity(0.06))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Privacy preset: \(presetLabel). Tap to change.")
        .accessibilityIdentifier("menubar.privacy.strip")
    }

    private func apply(_ preset: PrivacyPreset) {
        guard var settings = store.governance.privacySettings,
              let claudePolicy = store.governance.claudePrivacyPolicy,
              let codexPolicy = store.governance.codexPrivacyPolicy else { return }
        let (newSettings, newClaude, newCodex) = preset.apply(
            to: &settings,
            claude: claudePolicy,
            codex: codexPolicy
        )
        Task {
            await store.governance.updatePrivacySettings(newSettings)
            await store.governance.updatePrivacyPolicy(newClaude)
            await store.governance.updatePrivacyPolicy(newCodex)
        }
    }
}

// MARK: - Requests queue

private struct RequestsQueueSection: View {
    let store: ManifoldStore
    @State private var expanded = true

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(ManifoldMotion.state) { expanded.toggle() }
            } label: {
                HStack(spacing: Spacing.s2) {
                    Text("\(store.pendingRequests.count)")
                        .font(ManifoldType.numericCaption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(ManifoldPalette.attention))
                    Text("pending \(store.pendingRequests.count == 1 ? "request" : "requests")")
                        .font(ManifoldType.body)
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)

            if expanded {
                VStack(spacing: Spacing.s2) {
                    ForEach(store.pendingRequests) { request in
                        RequestCard(request: request, store: store)
                    }
                }
                .padding(.horizontal, Spacing.s3)
                .padding(.bottom, Spacing.s2)
            }
        }
        .background(Color.primary.opacity(0.02))
    }
}

private struct RequestCard: View {
    let request: ApprovalRequest
    let store: ManifoldStore

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                GradientAvatar(agent: request.agent, size: .small)
                Text(request.headline)
                    .font(ManifoldType.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Spacing.s1) {
                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(request.target)
                    .font(ManifoldType.mono)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            }
            Text(request.context)
                .font(ManifoldType.caption)
                .foregroundStyle(.tertiary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)

            if let findings = request.findingsSummary, request.kind == .privacyExposure {
                Text(findings)
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.attention)
            }

            switch request.kind {
            case .standingWrite:
                CommitLadder(
                    agent: request.agent,
                    showsSessionScope: request.supportsSessionScope && store.activeSession != nil,
                    onNotThisTime: { Task { await store.answer(request, with: .notThisTime) } },
                    onOnce:        { Task { await store.answer(request, with: .once) } },
                    onSession:     { Task {
                        guard let sid = store.activeSession?.id else { return }
                        await store.answer(request, with: .forSession(sessionID: sid))
                    } },
                    onDefault:     { Task { await store.answer(request, with: .addToDefault) } }
                )
            case .privacyExposure:
                PrivacyApprovalButtons(
                    onDeny: { Task { await store.answer(request, with: .notThisTime) } },
                    onShareRedacted: { Task { await store.answer(request, with: .shareRedacted) } },
                    onShareOriginal: { Task { await store.answer(request, with: .shareOriginalOnce) } }
                )
            }
        }
        .padding(Spacing.s3)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Agent summary

private struct AgentSummaryBlock: View {
    let store: ManifoldStore
    let state: MenuBarPanelView.PanelState

    var body: some View {
        VStack(spacing: 0) {
            if let summary = store.dataControlSummary {
                ForEach(summary.agents) { agent in
                    AgentRow(
                        agent: agent.agent,
                        connected: agent.isConnected,
                        paused: agent.isPaused,
                        statusText: agentStatusText(agent),
                        consequenceText: consequenceText(agent)
                    )
                }
            } else {
                if let claude = store.governance.claudePolicy {
                    AgentRow(
                        agent: .cowork,
                        connected: store.isClaudeConnected,
                        paused: claude.isPaused,
                        statusText: agentStatusText(governance: claude, connected: store.isClaudeConnected),
                        consequenceText: consequenceText(governance: claude, agent: .cowork)
                    )
                }
                if let codex = store.governance.codexPolicy {
                    AgentRow(
                        agent: .codex,
                        connected: store.isCodexConnected,
                        paused: codex.isPaused,
                        statusText: agentStatusText(governance: codex, connected: store.isCodexConnected),
                        consequenceText: consequenceText(governance: codex, agent: .codex)
                    )
                }
            }
        }
    }

    private func agentStatusText(_ agent: DataControlSummary.Agent) -> String {
        if agent.isPaused { return "paused" }
        if !agent.isConnected { return "offline" }
        switch agent.verificationStatus {
        case .verified: return "verified"
        case .unverified: return "unverified"
        case .unknown: return "connected"
        }
    }

    private func consequenceText(_ agent: DataControlSummary.Agent) -> String {
        let folders = "\(agent.defaultFileScopeCount) folder\(agent.defaultFileScopeCount == 1 ? "" : "s")"
        let emails = "\(agent.visibleEmailCount) email\(agent.visibleEmailCount == 1 ? "" : "s") visible"
        if agent.sharedEmailCount > 0 {
            return "\(folders) · \(emails) · \(agent.sharedEmailCount) explicit"
        }
        return "\(folders) · \(emails)"
    }

    private func agentStatusText(governance: AgentAccessPolicy, connected: Bool) -> String {
        if governance.isPaused { return "paused" }
        if !connected { return "offline" }
        return "active"
    }

    private func consequenceText(governance: AgentAccessPolicy, agent: TargetApp) -> String? {
        let count = governance.allowedSourceIDs.count
        if count == 0 { return nil }
        return "\(count) folder\(count == 1 ? "" : "s") in default scope"
    }
}

private struct AgentRow: View {
    let agent: TargetApp
    let connected: Bool
    let paused: Bool
    let statusText: String
    let consequenceText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.s2) {
                GradientAvatar(agent: agent, size: .small)
                Text(agent == .codex ? "Codex" : "Claude")
                    .font(ManifoldType.bodyMedium)
                Spacer(minLength: Spacing.s2)
                Text(statusText)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            if let consequenceText {
                Text(consequenceText)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 26)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .opacity(paused ? 0.55 : 1.0)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Recent sessions

private struct RecentSessionsBlock: View {
    let sessions: [SessionHistoryEntry]
    let store: ManifoldStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent sessions")
                .font(ManifoldType.tiny.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, Spacing.s4)
                .padding(.top, Spacing.s2)
                .padding(.bottom, Spacing.s1)

            ForEach(sessions) { session in
                Button {
                    openSessionRecap(for: session, store: store)
                } label: {
                    HStack(spacing: Spacing.s2) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(ManifoldType.body)
                            .foregroundStyle(ManifoldPalette.active)
                        Text(session.name)
                            .font(ManifoldType.body)
                        Spacer(minLength: Spacing.s2)
                        Text("\(session.displayLastRun) · \(session.displayDuration)")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, Spacing.s4)
                    .padding(.vertical, 5)
                }
                .buttonStyle(HoverRowStyle())
            }
            Spacer().frame(height: Spacing.s1)
        }
    }
}

// MARK: - Footer

private struct FooterActions: View {
    let store: ManifoldStore
    let commandPalette: CommandPaletteModel
    let state: MenuBarPanelView.PanelState

    var body: some View {
        VStack(spacing: 0) {
            if state == .trackedEdit {
                commandFooterItem(.openSessionRecap)
                commandFooterItem(.finishTrackedEdit)
                FooterDivider()
            } else if state == .idle || state == .idleWithRecent {
                commandFooterItem(.startSession)
                commandFooterItem(.addFolder)
                FooterDivider()
            }

            if state == .activeWithQueue {
                commandFooterItem(.openSessionRecap)
            }

            if !store.pendingRequests.isEmpty {
                FooterItem(icon: "hand.raised", label: "Review requests", shortcut: nil) {
                    presentMainLedger(destination: .work)
                }
            }

            if state == .activeWithQueue || !store.pendingRequests.isEmpty {
                FooterDivider()
            }

            commandFooterItem(.openManifold)
            commandFooterItem(.settings)

            if store.isRuntimeConnected {
                FooterDivider()
                FooterItem(
                    icon: allAgentsPaused ? "play.circle" : "pause.circle",
                    label: allAgentsPaused ? "Resume all agents" : "Pause all agents",
                    shortcut: "⌘⇧P",
                    tone: .muted
                ) {
                    Task {
                        if allAgentsPaused {
                            await store.governance.resumeAllAgents()
                        } else {
                            await store.governance.pauseAllAgents()
                        }
                        await store.refreshAll()
                    }
                }
            }

            FooterDivider()
            FooterItem(icon: "power", label: "Quit Manifold", shortcut: "⌘Q", tone: .muted) {
                store.quitManifold()
            }
        }
        .padding(.vertical, Spacing.s1)
        .padding(.horizontal, Spacing.s1)
        .background(Color.primary.opacity(0.02))
    }

    private var allAgentsPaused: Bool {
        if let agents = store.dataControlSummary?.agents, !agents.isEmpty {
            return agents.allSatisfy(\.isPaused)
        }
        return store.governance.claudePolicy?.isPaused == true
            && store.governance.codexPolicy?.isPaused == true
    }

    @ViewBuilder
    private func commandFooterItem(_ id: ManifoldCommandID) -> some View {
        if let command = commandPalette.command(id, for: store) {
            FooterItem(
                icon: command.icon,
                label: command.title,
                shortcut: command.shortcutLabel
            ) {
                Task { await command.action(store) }
            }
        }
    }
}

private struct FooterItem: View {
    enum Tone { case normal, muted }
    let icon: String
    let label: String
    let shortcut: String?
    var tone: Tone = .normal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: icon)
                    .font(ManifoldType.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(label)
                    .font(ManifoldType.body)
                    .foregroundStyle(tone == .muted ? .secondary : .primary)
                Spacer(minLength: Spacing.s2)
                if let shortcut {
                    Text(shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(HoverRowStyle())
    }
}

private struct FooterDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .opacity(0.5)
    }
}

private struct HoverRowStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Spacing.r2, style: .continuous)
                    .fill(hovered ? Color.primary.opacity(0.08) : .clear)
            )
            .onHover { hovered = $0 }
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private extension String {
    var lastPathComponentForDisplay: String {
        let component = URL(fileURLWithPath: self).lastPathComponent
        return component.isEmpty ? self : component
    }
}

@MainActor
private func openSessionRecap(for entry: SessionHistoryEntry, store: ManifoldStore) {
    Task { @MainActor in
        if store.sessions.isEmpty {
            await store.activity.loadSessions()
        }
        if let session = store.sessions.first(where: { $0.id == entry.id }) {
            await store.activity.selectSession(session)
        }
        presentMainLedger(destination: .work)
    }
}
