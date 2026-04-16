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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum PanelState {
        case idle
        case idleWithRecent
        case activeWithQueue
        case trackedEdit
    }

    private var panelState: PanelState {
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
                SessionChipStrip(session: session, store: store)
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
            FooterActions(store: store, state: panelState)
        }
        .frame(width: 360)
        .task {
            await store.policy.loadPolicies()
            await store.policy.loadActiveWorkBlock()
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
        let folderCount = store.sources.filter(\.isAccessible).count
        switch state {
        case .idle:
            return "You haven't shared anything yet."
        case .idleWithRecent:
            return folderCount == 0
                ? "No agents are running."
                : "You've shared \(folderCount) folder\(folderCount == 1 ? "" : "s") by default."
        case .activeWithQueue:
            let session = store.activeSession
            return "Session running: \(session?.name ?? "unnamed")."
        case .trackedEdit:
            return "Tracked edit in progress."
        }
    }

    private var headlineSecondary: String {
        if let error = store.runtimeLaunchError ?? store.lastError {
            return error
        }
        switch state {
        case .idle:
            return "Manifold is running. Add a folder or mailbox to start."
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

// MARK: - Session strip (unified: live + tracked edit share one visual)
//
// Per §2.5.1 reduction — "two agent-row color treatments collapse to
// one." Session-live and tracked-edit are both *something is happening
// now*; the distinguishing information is in the label, not the fill.

private struct SessionChipStrip: View {
    let session: SessionRecord
    let store: ManifoldStore

    private var kindLabel: String {
        session.isTrackedEdit ? "TRACKED EDIT" : "SESSION"
    }

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Circle()
                .fill(ManifoldPalette.active)
                .frame(width: 7, height: 7)
            Text(kindLabel)
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

// MARK: - Requests summary
//
// Per Stage 2 and the user's "quick access and data" framing, the menu
// bar shows the count and a one-line preview of the next request —
// never the full CommitLadder. The ladder is a consequential decision
// and lives on the bigger Ledger surface (RequestsWindowView). ⌘R
// brings that window forward and routes to Requests.

private struct RequestsQueueSection: View {
    let store: ManifoldStore

    private var count: Int { store.pendingRequests.count }
    private var next: ApprovalRequest? { store.pendingRequests.first }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Text("\(count)")
                    .font(ManifoldType.numericCaption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(ManifoldPalette.attention))
                Text("pending \(count == 1 ? "request" : "requests")")
                    .font(ManifoldType.body)
                Spacer(minLength: 0)
            }

            if let request = next {
                HStack(spacing: Spacing.s2) {
                    GradientAvatar(agent: request.agent, size: .small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(request.headline)
                            .font(ManifoldType.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(request.target)
                            .font(ManifoldType.tiny)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                if count > 1 {
                    Text("\(count - 1) more waiting")
                        .font(ManifoldType.tiny)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack {
                Spacer()
                Button("Answer in Ledger") { openRequestsInLedger() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(Color.primary.opacity(0.02))
    }

    /// Activate the app, surface the main window, and route to Requests.
    private func openRequestsInLedger() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(name: .manifoldOpenRequests, object: nil)
    }
}

// MARK: - Agent summary

private struct AgentSummaryBlock: View {
    let store: ManifoldStore
    let state: MenuBarPanelView.PanelState

    var body: some View {
        VStack(spacing: 0) {
            if let claude = store.policy.claudePolicy {
                AgentRow(
                    agent: .cowork,
                    connected: store.isClaudeConnected,
                    paused: claude.isPaused,
                    statusText: agentStatusText(policy: claude, connected: store.isClaudeConnected),
                    consequenceText: consequenceText(policy: claude, agent: .cowork)
                )
            }
            if let codex = store.policy.codexPolicy {
                AgentRow(
                    agent: .codex,
                    connected: store.isCodexConnected,
                    paused: codex.isPaused,
                    statusText: agentStatusText(policy: codex, connected: store.isCodexConnected),
                    consequenceText: consequenceText(policy: codex, agent: .codex)
                )
            }
        }
    }

    private func agentStatusText(policy: AgentAccessPolicy, connected: Bool) -> String {
        if policy.isPaused { return "paused" }
        if !connected { return "offline" }
        return "active"
    }

    private func consequenceText(policy: AgentAccessPolicy, agent: TargetApp) -> String? {
        let count = policy.allowedSourceIDs.count
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
        // Per Priority 6: agent rows are handles, not labels. Tapping an
        // agent opens the Ledger and routes to Scope so the user can edit
        // what the row describes (plan §6.1).
        Button(action: openScopeForAgent) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.s2) {
                    GradientAvatar(agent: agent, size: .small)
                    Text(agent == .codex ? "Codex" : "Claude")
                        .font(ManifoldType.bodyMedium)
                        .foregroundStyle(.primary)
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
            .contentShape(Rectangle())
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
        }
        .buttonStyle(HoverRowStyle())
        .opacity(paused ? 0.55 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Scope for this agent")
    }

    private func openScopeForAgent() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(name: .manifoldOpenScope, object: agent)
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
                    Task { try? await store.reloadSession(historyID: session.id) }
                } label: {
                    HStack(spacing: Spacing.s2) {
                        Image(systemName: "arrow.uturn.backward.circle")
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
    let state: MenuBarPanelView.PanelState

    var body: some View {
        VStack(spacing: 0) {
            if state == .trackedEdit {
                FooterItem(icon: "arrow.uturn.backward", label: "Review changes\u{2026}", shortcut: "⌘R") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                FooterItem(icon: "checkmark.seal", label: "Finish tracked edit", shortcut: "⌘⇧F") {
                    Task { try? await store.finishActiveSession() }
                }
                FooterDivider()
            } else if state == .idle || state == .idleWithRecent {
                FooterItem(icon: "plus.circle", label: "Start new session\u{2026}", shortcut: "⌘N") {
                    Task { try? await store.startSession(SessionDraft()) }
                }
                FooterItem(icon: "folder.badge.plus", label: "Add a folder\u{2026}", shortcut: "⌘⇧F") {
                    store.addSourceFromPicker()
                }
                FooterDivider()
            }

            FooterItem(icon: "gearshape", label: "Settings\u{2026}", shortcut: "⌘,") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }

            if state == .activeWithQueue || state == .trackedEdit {
                FooterDivider()
                FooterItem(icon: "pause.circle", label: "Pause all agents", shortcut: "⌘⇧P", tone: .muted) {
                    Task { await store.policy.pauseAllAgents() }
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
