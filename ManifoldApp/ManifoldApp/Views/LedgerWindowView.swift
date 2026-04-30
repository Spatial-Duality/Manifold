// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// LedgerView — the single Manifold window.
//
// Per the 2026-04-29 redesign, the app is organized around four
// task-oriented surfaces:
//
//   • Work   — sessions, approvals, activity, writes, runtime health
//   • Access — share folders with agents
//   • Mail   — share mailboxes with agents
//   • Rules  — manage reusable guardrails
//
// All earlier "implementation surfaces" (Activity, Sessions, Requests,
// Provenance, Agent OS) collapse into Work or live only as developer
// detail. Legacy deep links (notifications, intents, command palette)
// route to Work.

import SwiftUI
import ManifoldKit

/// The four user-facing destinations in the main window.
enum LedgerDestination: String, Hashable, CaseIterable, Identifiable {
    case work
    case access
    case mail
    case rules

    var id: String { rawValue }

    /// Backwards-compat init: legacy raw values from notifications, intents,
    /// or pre-redesign settings collapse onto the new four-destination set.
    /// Anything related to "what agents did", "approvals", or runtime state
    /// folds into `.work`. Provenance / agentOS were developer surfaces and
    /// also fold into `.work` so the window doesn't open to a missing tab.
    init?(rawValue: String) {
        switch rawValue {
        case "work": self = .work
        case "access": self = .access
        case "mail": self = .mail
        case "rules": self = .rules
        case "activity", "sessions", "requests", "provenance", "agentOS":
            self = .work
        default:
            return nil
        }
    }

    var keyboardIndex: Int {
        switch self {
        case .work: return 1
        case .access: return 2
        case .mail: return 3
        case .rules: return 4
        }
    }

    var title: String {
        switch self {
        case .work:   return "Work"
        case .access: return "Access"
        case .mail:   return "Mail"
        case .rules:  return "Rules"
        }
    }

    var systemImage: String {
        switch self {
        case .work:   return "square.stack.3d.up"
        case .access: return "folder.badge.gearshape"
        case .mail:   return "envelope"
        case .rules:  return "checklist"
        }
    }

    var emptyTitle: String {
        switch self {
        case .work:   return "Nothing is happening right now"
        case .access: return "Nothing shared yet"
        case .mail:   return "No mailboxes connected"
        case .rules:  return "No rules configured"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .work:
            return "Start a session to give Claude or Codex access to your shared folders and mailboxes. Approvals and activity will appear here."
        case .access:
            return "Nothing is shared until you share it. Add a folder to let an agent read from it inside a session."
        case .mail:
            return "Connect a mailbox to share mail with an agent. Subjects and senders are visible by default; message bodies require an explicit grant."
        case .rules:
            return "Rules control what agents can read, write, or redact. Seeded rules block secrets out of the box; add custom rules for anything else."
        }
    }
}

struct LedgerView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var destination: LedgerDestination = .work
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LedgerSidebar(selection: $destination)
        } detail: {
            // Title ownership: the DETAIL column owns the window title on
            // macOS `NavigationSplitView`. Setting `.navigationTitle` on
            // the sidebar as well causes the sidebar `List` to start
            // drawing from Y=0 (the first rows land behind the traffic
            // lights). So: the sidebar sets no title, the detail sets a
            // single canonical title — `destination.title` — and that's
            // it.
            content
                .frame(minWidth: 720, minHeight: 480)
                .navigationTitle(destination.title)
                .toolbar { LedgerToolbar(destination: destination) }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            columnVisibility = .all
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldShowActivityLedger)) { _ in
            destination = .work
            columnVisibility = .all
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldShowLedgerDestination)) { notification in
            guard let rawValue = notification.object as? String,
                  let requestedDestination = LedgerDestination(rawValue: rawValue) else {
                return
            }
            destination = requestedDestination
            columnVisibility = .all
        }
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .work:
            WorkView()
        case .access:
            AccessView()
        case .mail:
            MailView()
        case .rules:
            RulesView()
        }
    }
}

#Preview("Ledger window — Work") {
    LedgerView()
        .environment(ManifoldStore(runtime: FixtureRuntimeClient(profile: .trackedWork), startServices: false))
        .frame(width: 1080, height: 720)
}
