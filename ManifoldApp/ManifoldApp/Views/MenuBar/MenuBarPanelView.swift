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
                if session.isTrackedEdit {
                    TrackedEditStrip(session: session, store: store)
                } else {
                    SessionChipStrip(session: session, store: store)
                }
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

// MARK: - Tracked edit strip

private struct TrackedEditStrip: View {
    let session: SessionRecord
    let store: ManifoldStore

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: "timeline.selection")
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.claude)
            VStack(alignment: .leading, spacing: 1) {
                Text("TRACKED EDIT")
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
        .background(ManifoldPalette.claudeSoft)
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

            CommitLadder(
                agent: request.agent,
                sessionIsLive: store.activeSession != nil,
                onNotThisTime: { Task { await store.answer(request, with: .notThisTime) } },
                onOnce:        { Task { await store.answer(request, with: .once) } },
                onSession:     { Task {
                    guard let sid = store.activeSession?.id else { return }
                    await store.answer(request, with: .forSession(sessionID: sid))
                } },
                onDefault:     { Task { await store.answer(request, with: .addToDefault) } }
            )
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

            FooterItem(icon: "macwindow", label: "Open Manifold", shortcut: "⌘O") {
                NSApp.activate(ignoringOtherApps: true)
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
