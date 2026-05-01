// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ManifoldMenuBarPanel.swift — Stage 10 design spike
//
// The menu bar panel as a previewable SwiftUI surface. Replaces the Stage-4
// HTML mockup which failed to convey the material, depth, icon-set, and
// color saturation the real product needs.
//
// This file is self-contained: it does not depend on ManifoldKit or the
// runtime store. All data is mocked via `MenuBarMockState` so the panel
// can be rendered in Xcode's #Preview and iterated visually without the
// full app present. The companion README explains how to wire the real
// ManifoldStore when the design is accepted.
//
// Design decisions traced to the Stage 1–8 docs:
//   - Principle 5 (Stage 2):     user-as-subject headline copy
//   - Principle 10:              no "Connected" when runtime isn't
//   - Stage 3 §I:                360pt width, 4 regions, session chip
//   - Stage 6:                   Default + Session primitives
//   - Stage 6 reload addendum:   Recent sessions list on idle
//   - Principle 6:               fixed agent palette, not system accent
//   - Principle 9:               reduce-motion, accessibility labels
//
// Requires macOS 14+ / Xcode 15+ for the #Preview macro, Observation, and
// the @Observable state model.

import SwiftUI
import AppKit
import Combine

// MARK: - Brand palette (fixed, not system accent)

extension Color {
    /// Manifold Claude identity — calibrated for WCAG AA against both
    /// surfaces, light and dark mode. Not `.blue`.
    static let manifoldClaude = Color(light: Color(red: 0.23, green: 0.43, blue: 0.90),
                                      dark:  Color(red: 0.42, green: 0.58, blue: 0.96))

    /// Manifold Codex identity.
    static let manifoldCodex  = Color(light: Color(red: 0.49, green: 0.27, blue: 0.84),
                                      dark:  Color(red: 0.65, green: 0.48, blue: 0.91))

    /// Session chip / active attention. Reserved.
    static let manifoldSession = Color(light: Color(red: 0.12, green: 0.67, blue: 0.35),
                                       dark:  Color(red: 0.19, green: 0.75, blue: 0.38))

    /// Denials + requests queue badge. Not red — red reserved for errors
    /// that prevent the product from working.
    static let manifoldAttention = Color(light: Color(red: 0.83, green: 0.37, blue: 0.00),
                                         dark:  Color(red: 1.00, green: 0.50, blue: 0.22))

    /// Convenience initializer for scheme-aware colors.
    init(light: Color, dark: Color) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.name {
            case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
                return NSColor(dark)
            default:
                return NSColor(light)
            }
        })
    }
}

// MARK: - Mock state model

/// Stands in for `ManifoldStore` in the spike. Swap for the real store
/// when integrating — the view contract is the public properties below.
@Observable
final class MenuBarMockState {
    enum Mode {
        /// First-run: idle, nothing shared.
        case idle
        /// Idle but has recent sessions available to reload.
        case idleWithRecent
        /// Active: agents running, session live, pending requests.
        case activeSessionWithQueue
        /// Tracked edit in progress (session with writes tracked).
        case trackedEdit
    }

    // Inputs
    var mode: Mode

    // Derived state exposed to the view
    var isRuntimeConnected: Bool { true }
    var claudeConnected: Bool { mode != .idle && mode != .idleWithRecent }
    var codexPaused: Bool { true }  // spike: always show Codex paused

    var defaultFolderCount: Int {
        switch mode {
        case .idle:                   return 0
        case .idleWithRecent:         return 4
        case .activeSessionWithQueue: return 4
        case .trackedEdit:            return 4
        }
    }
    var defaultMailboxCount: Int { mode == .idle ? 0 : 1 }

    var headlinePrimary: String {
        switch mode {
        case .idle:
            return "You haven't shared anything yet."
        case .idleWithRecent:
            return "You've shared 4 folders with Claude by default."
        case .activeSessionWithQueue:
            return "You've shared 4 folders and 1 mailbox with Claude."
        case .trackedEdit:
            return "Claude is editing 3 files in your Acme folder."
        }
    }

    var headlineSecondary: String {
        switch mode {
        case .idle:
            return "Manifold is running. Add a folder or mailbox to start."
        case .idleWithRecent:
            return "No session running. Last active 18 min ago."
        case .activeSessionWithQueue:
            return "Claude read README.md 12 min ago."
        case .trackedEdit:
            return "Tracked — you can undo any of it. 14 min in."
        }
    }

    // Active session (optional)
    struct ActiveSession {
        var name: String
        var remaining: TimeInterval
        var isTrackedEdit: Bool
    }

    var activeSession: ActiveSession? {
        switch mode {
        case .activeSessionWithQueue:
            return .init(name: "Jane follow-up", remaining: 6120, isTrackedEdit: false)
        case .trackedEdit:
            return .init(name: "Jane follow-up · ~/Projects/Acme", remaining: 5160, isTrackedEdit: true)
        default:
            return nil
        }
    }

    // Pending requests
    struct PendingRequest: Identifiable {
        let id = UUID()
        var agent: AgentIdentity
        var headline: String
        var target: String
        var context: String
    }

    var pendingRequests: [PendingRequest] {
        guard mode == .activeSessionWithQueue else { return [] }
        return [
            .init(agent: .claude,
                  headline: "Claude wants access to a new folder.",
                  target: "~/Projects/Acme",
                  context: "Asked while you were working in the Jane follow-up session."),
            .init(agent: .codex,
                  headline: "Codex wants to write to a shared file.",
                  target: "~/Projects/Manifold/test/StoreTests.swift",
                  context: "Codex is in default access, no session.")
        ]
    }

    var requestCount: Int { pendingRequests.count }

    // Recent sessions (idleWithRecent state)
    struct RecentSession: Identifiable {
        let id = UUID()
        var name: String
        var lastRun: String
        var duration: String
    }

    var recentSessions: [RecentSession] {
        guard mode == .idleWithRecent else { return [] }
        return [
            .init(name: "Jane follow-up", lastRun: "Yesterday", duration: "2h"),
            .init(name: "Writing sprint", lastRun: "3 days ago", duration: "4h"),
            .init(name: "Board prep",     lastRun: "Last week",  duration: "until sign-out")
        ]
    }

    init(mode: Mode = .activeSessionWithQueue) { self.mode = mode }
}

enum AgentIdentity: String, CaseIterable {
    case claude = "Claude"
    case codex  = "Codex"

    var color: Color {
        switch self {
        case .claude: return .manifoldClaude
        case .codex:  return .manifoldCodex
        }
    }
    var symbol: String {
        switch self {
        case .claude: return "sparkle"
        case .codex:  return "chevron.left.forwardslash.chevron.right"
        }
    }
}

// MARK: - Root view

struct ManifoldMenuBarPanel: View {
    @Bindable var state: MenuBarMockState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            StatusHeader(state: state, reduceMotion: reduceMotion)

            if let session = state.activeSession {
                Divider()
                if session.isTrackedEdit {
                    TrackedEditStrip(session: session)
                } else {
                    SessionChipStrip(session: session)
                }
            }

            if state.requestCount > 0 {
                Divider()
                RequestsQueueSection(state: state)
            }

            if state.mode == .activeSessionWithQueue || state.mode == .trackedEdit || state.mode == .idleWithRecent {
                Divider()
                AgentSummaryBlock(state: state)
            }

            if !state.recentSessions.isEmpty {
                Divider()
                RecentSessionsBlock(sessions: state.recentSessions)
            }

            Divider()
            FooterActions(state: state)
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 8)
        .shadow(color: .black.opacity(0.08), radius: 4,  x: 0, y: 2)
    }
}

// MARK: - Status header

private struct StatusHeader: View {
    let state: MenuBarMockState
    let reduceMotion: Bool

    @State private var pulse = false

    private var dotColor: Color {
        switch state.mode {
        case .idle, .idleWithRecent:              return .secondary
        case .activeSessionWithQueue, .trackedEdit: return .manifoldClaude
        }
    }

    private var isActive: Bool {
        state.mode == .activeSessionWithQueue || state.mode == .trackedEdit
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status dot with optional pulse halo
            ZStack {
                if isActive && !reduceMotion {
                    Circle()
                        .fill(dotColor.opacity(0.35))
                        .frame(width: 16, height: 16)
                        .scaleEffect(pulse ? 1.0 : 0.6)
                        .opacity(pulse ? 0 : 0.9)
                        .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: pulse)
                        .onAppear { pulse = true }
                }
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
            }
            .padding(.top, 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.headlinePrimary)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(state.headlineSecondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.headlinePrimary). \(state.headlineSecondary)")
    }
}

// MARK: - Session chip (non-tracked)

private struct SessionChipStrip: View {
    let session: MenuBarMockState.ActiveSession

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.manifoldSession)
                .frame(width: 7, height: 7)
            Text("Session")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Text(session.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(formatRemaining(session.remaining))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("Finish") { /* mock */ }
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.manifoldSession.opacity(0.10))
    }

    private func formatRemaining(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Tracked edit strip

private struct TrackedEditStrip: View {
    let session: MenuBarMockState.ActiveSession

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "timeline.selection")
                .font(.caption)
                .foregroundStyle(Color.manifoldClaude)
            VStack(alignment: .leading, spacing: 1) {
                Text("Tracked edit")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Text(session.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(formatRemaining(session.remaining))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("Finish") { /* mock */ }
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.manifoldClaude.opacity(0.08))
    }

    private func formatRemaining(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Requests queue

private struct RequestsQueueSection: View {
    let state: MenuBarMockState
    @State private var expanded = true

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text("\(state.requestCount)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.manifoldAttention))
                    Text("pending \(state.requestCount == 1 ? "request" : "requests")")
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if expanded {
                VStack(spacing: 8) {
                    ForEach(state.pendingRequests) { request in
                        RequestCard(request: request, sessionLive: state.activeSession != nil)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(Color.primary.opacity(0.025))
    }
}

private struct RequestCard: View {
    let request: MenuBarMockState.PendingRequest
    let sessionLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: request.agent.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(request.agent.color)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle().fill(request.agent.color.opacity(0.14))
                    )
                Text(request.headline)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label {
                Text(request.target)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            } icon: {
                Image(systemName: "folder.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(request.context)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Button("Not this time") { /* mock */ }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                Button("Once") { /* mock */ }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                if sessionLive {
                    Button("Session") { /* mock */ }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.manifoldSession)
                }
                Button("Default") { /* mock */ }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(request.agent.color)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Agent summary

private struct AgentSummaryBlock: View {
    let state: MenuBarMockState

    var body: some View {
        VStack(spacing: 0) {
            AgentRow(
                agent: .claude,
                connected: state.claudeConnected,
                paused: false,
                statusText: state.mode == .trackedEdit ? "3 reads, 3 writes" : "active · quiet 12m",
                consequenceText: state.mode == .trackedEdit
                    ? "All writes reversible · snapshots in Activity"
                    : "4 folders · @work mail · 1 session addition"
            )
            AgentRow(
                agent: .codex,
                connected: false,
                paused: state.codexPaused,
                statusText: "paused",
                consequenceText: nil
            )
        }
    }
}

private struct AgentRow: View {
    let agent: AgentIdentity
    let connected: Bool
    let paused: Bool
    let statusText: String
    let consequenceText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: agent.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(agent.color)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(agent.color.opacity(0.14)))
                Text(agent.rawValue)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let consequenceText {
                Text(consequenceText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(paused ? 0.55 : 1.0)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Recent sessions (idle + recent state)

private struct RecentSessionsBlock: View {
    let sessions: [MenuBarMockState.RecentSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent sessions")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(sessions) { session in
                Button {
                    /* mock: reload */
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .font(.callout)
                            .foregroundStyle(Color.manifoldSession)
                        Text(session.name)
                            .font(.callout)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text("\(session.lastRun) · \(session.duration)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                }
                .buttonStyle(HoverRowStyle())
            }
            Spacer().frame(height: 6)
        }
    }
}

// MARK: - Footer

private struct FooterActions: View {
    let state: MenuBarMockState

    var body: some View {
        VStack(spacing: 0) {
            // Primary actions contextual to state
            if state.mode == .trackedEdit {
                FooterItem(icon: "arrow.uturn.backward", label: "Review changes…", shortcut: "⌘R") { }
                FooterItem(icon: "checkmark.seal", label: "Finish tracked edit", shortcut: "⌘⇧F") { }
                FooterDivider()
            } else if state.mode == .idle || state.mode == .idleWithRecent {
                FooterItem(icon: "plus.circle", label: "Start new session…", shortcut: "⌘N") { }
                FooterItem(icon: "folder.badge.plus", label: "Add a folder…", shortcut: "⌘⇧F") { }
                FooterItem(icon: "envelope.badge", label: "Add a mailbox…", shortcut: "⌘⇧M") { }
                FooterDivider()
            }

            FooterItem(icon: "macwindow", label: "Open Manifold", shortcut: "⌘O") { }
            FooterItem(icon: "gearshape", label: "Settings…", shortcut: "⌘,") { }

            if state.mode == .activeSessionWithQueue || state.mode == .trackedEdit {
                FooterDivider()
                FooterItem(icon: "pause.circle", label: "Pause all agents", shortcut: "⌘⇧P", tone: .muted) { }
            }

            FooterDivider()
            FooterItem(icon: "power", label: "Quit Manifold", shortcut: "⌘Q", tone: .muted) { }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
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
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(tone == .muted ? .secondary : .primary)
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.caption2.monospaced())
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

// Hover highlight button style used by footer and recent-sessions rows.
private struct HoverRowStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovered ? Color.primary.opacity(0.08) : .clear)
            )
            .onHover { hovered = $0 }
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

// MARK: - Previews

#Preview("Idle — first run (empty)") {
    ManifoldMenuBarPanel(state: MenuBarMockState(mode: .idle))
        .padding(40)
        .background(PreviewBackdrop())
}

#Preview("Idle — recent sessions") {
    ManifoldMenuBarPanel(state: MenuBarMockState(mode: .idleWithRecent))
        .padding(40)
        .background(PreviewBackdrop())
}

#Preview("Active — session live, 2 pending") {
    ManifoldMenuBarPanel(state: MenuBarMockState(mode: .activeSessionWithQueue))
        .padding(40)
        .background(PreviewBackdrop())
}

#Preview("Tracked edit in progress") {
    ManifoldMenuBarPanel(state: MenuBarMockState(mode: .trackedEdit))
        .padding(40)
        .background(PreviewBackdrop())
}

#Preview("All four states — side by side") {
    HStack(alignment: .top, spacing: 32) {
        VStack(spacing: 16) {
            Text("Idle").font(.caption2).foregroundStyle(.secondary)
            ManifoldMenuBarPanel(state: MenuBarMockState(mode: .idle))
        }
        VStack(spacing: 16) {
            Text("Idle · recent").font(.caption2).foregroundStyle(.secondary)
            ManifoldMenuBarPanel(state: MenuBarMockState(mode: .idleWithRecent))
        }
        VStack(spacing: 16) {
            Text("Active · queue").font(.caption2).foregroundStyle(.secondary)
            ManifoldMenuBarPanel(state: MenuBarMockState(mode: .activeSessionWithQueue))
        }
        VStack(spacing: 16) {
            Text("Tracked edit").font(.caption2).foregroundStyle(.secondary)
            ManifoldMenuBarPanel(state: MenuBarMockState(mode: .trackedEdit))
        }
    }
    .padding(48)
    .background(PreviewBackdrop())
}

// Desktop-ish backdrop so previews read like the panel floats above real content.
private struct PreviewBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.18, green: 0.22, blue: 0.32),
                Color(red: 0.08, green: 0.10, blue: 0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            // Soft menu-bar stripe at the top so the panel looks anchored
            VStack(spacing: 0) {
                Rectangle()
                    .fill(.black.opacity(0.25))
                    .frame(height: 24)
                Spacer()
            }
        )
        .ignoresSafeArea()
    }
}
