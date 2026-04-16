// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// LedgerWindowView — the single Manifold window.
//
// Per Stage 2, Manifold is a daemon with two visible surfaces: the menu
// bar panel (primary) and this Ledger window (secondary). The Ledger is
// NavigationSplitView with 5 evidence-oriented destinations, matching
// design/html/{activity, access, mail, requests, rules}.html.
//
// Each destination is filled in during its phase. Phase 1 renders the
// shell with calm empty-state placeholders; Phase 2 lands Activity;
// subsequent phases replace the placeholders in situ.

import SwiftUI
import ManifoldKit

/// Sidebar destinations — read as "the kind of evidence you want to see",
/// not "the tabs of an app" (Principle 10, Stage 2).
enum LedgerDestination: String, Hashable, CaseIterable, Identifiable {
    case activity
    case access
    case mail
    case requests
    case rules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return "Activity"
        case .access:   return "Scope"
        case .mail:     return "Mail"
        case .requests: return "Requests"
        case .rules:    return "Rules"
        }
    }

    var systemImage: String {
        switch self {
        case .activity: return "list.bullet.rectangle"
        case .access:   return "rectangle.3.group"
        case .mail:     return "envelope"
        case .requests: return "hand.raised"
        case .rules:    return "checklist"
        }
    }

    var emptyTitle: String {
        switch self {
        case .activity: return "No activity yet"
        case .access:   return "Nothing shared yet"
        case .mail:     return "No mailboxes connected"
        case .requests: return "Nothing is waiting on you"
        case .rules:    return "No rules yet"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .activity: return "As agents read files or write changes inside a session, an evidence ledger of every operation will appear here."
        case .access:   return "Scope is the picture of what each agent can see right now. Add a folder to grant Claude, Codex, or both."
        case .mail:     return "Connect a mailbox to share mail with an agent. Subjects and senders are visible by default; message bodies require an explicit grant."
        case .requests: return "When an agent asks for access it will land here. Requests are answered in a ladder — deny, once, session, default."
        case .rules:    return "Rules are the always-on layer: things Claude never does, never reads. Defaults seed the common ones — you can add your own."
        }
    }
}

struct LedgerWindowView: View {
    @Environment(ManifoldStore.self) private var store
    // Scope is the default landing per plan §6.3 — "what each agent can
    // see right now" is the question the Ledger most often opens to.
    @State private var destination: LedgerDestination = .access

    var body: some View {
        NavigationSplitView {
            NavSidebar(selection: $destination)
        } detail: {
            // Detail sets a `navigationSubtitle` rather than a second
            // `navigationTitle` so the sidebar's "Manifold" title retains
            // ownership of the window chrome. Two `.navigationTitle`
            // calls on a NavigationSplitView on macOS 26 cause the
            // sidebar List to intermittently render blank (reported on
            // the Requests destination); keeping the detail's label as
            // a subtitle avoids that collision.
            content
                .navigationTitle("Manifold")
                .navigationSubtitle(destination.title)
                .toolbar { IntegratedToolbar(destination: destination) }
                .safeAreaInset(edge: .top, spacing: 0) { ambientSessionBanner }
                .safeAreaInset(edge: .bottom) { StatusBar() }
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: .manifoldOpenRequests)) { _ in
            destination = .requests
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldOpenScope)) { _ in
            // TODO (Priority 2 — agent-centric Scope): consume
            // `notification.object as? TargetApp` to pre-focus the agent
            // column. Until then the payload is intentionally dropped; the
            // three-column Scope has no concept of a focused agent.
            destination = .access
        }
    }

    /// Ambient top-of-canvas session banner (plan §11 Q5). Renders when a
    /// session is live on every destination except Scope (which carries
    /// its own richer banner with the session-only filter toggle). One
    /// ambient home — no duplication across sidebar / StatusBar / menu
    /// bar panel.
    @ViewBuilder
    private var ambientSessionBanner: some View {
        if destination != .access, let session = store.policy.activeSession {
            AmbientSessionBanner(session: session)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .activity:
            ActivityWindowView()
        case .access:
            AccessWindowView()
        case .mail:
            MailWindowView()
        case .requests:
            RequestsWindowView()
        case .rules:
            RulesWindowView()
        }
    }
}

#Preview("Ledger window — Activity") {
    LedgerWindowView()
        .environment(ManifoldStore())
        .frame(width: 1080, height: 720)
}

// MARK: - Ambient session banner
//
// Read-only variant of ScopeColumnsView's private SessionBanner (no
// session-only filter picker — Scope is the one destination that
// actually filters on this axis). Shown at the top of Activity, Mail,
// Rules, and Requests whenever a session is live, so the user always
// knows "a Claude session is happening right now" without having to
// look at the menu bar. One ambient home, top of canvas — plan §11 Q5.
//
// When no session is live this view is never instantiated (its caller
// guards with `if let session = store.policy.activeSession`). No state,
// no cost when idle.

struct AmbientSessionBanner: View {
    @Environment(ManifoldStore.self) private var store
    let session: SessionRecord

    private var agentName: String {
        guard let agent = session.agents.first else { return "Agent" }
        return agent == .codex ? "Codex" : "Claude"
    }

    private var agentAccent: Color {
        guard let agent = session.agents.first else { return ManifoldPalette.text2 }
        return agent == .codex ? ManifoldPalette.codex : ManifoldPalette.claude
    }

    private var deltaSentence: String {
        let additions = store.policy.sessionAdditionIDs.count
        let removals = store.policy.sessionRemovalIDs.count
        switch (additions, removals) {
        case (0, 0): return "No changes relative to default scope."
        case (let a, 0): return "Session adds \(a) source\(a == 1 ? "" : "s") beyond default."
        case (0, let r): return "Session removes \(r) source\(r == 1 ? "" : "s") from default."
        case (let a, let r): return "Session adds \(a), removes \(r)."
        }
    }

    var body: some View {
        HStack(spacing: Spacing.s3) {
            HStack(spacing: Spacing.s2) {
                Circle()
                    .fill(agentAccent)
                    .frame(width: 8, height: 8)
                Text("\(agentName) session · live")
                    .font(ManifoldType.captionMedium)
                    .foregroundStyle(.primary)
                if let duration = session.displayDuration {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(duration)
                        .font(ManifoldType.tiny.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(deltaSentence)
                .font(ManifoldType.tiny)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Finish") {
                Task { await store.endSession() }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
