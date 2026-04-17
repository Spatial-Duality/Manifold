// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// LedgerView — the single Manifold window.
//
// Per Stage 2, Manifold is a daemon with two visible surfaces: the menu
// bar panel (primary) and this Ledger window (secondary). The Ledger is
// NavigationSplitView with 4 live evidence-oriented destinations.
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

    var keyboardIndex: Int {
        switch self {
        case .activity: return 1
        case .access: return 2
        case .mail: return 3
        case .requests: return 4
        case .rules: return 5
        }
    }

    var title: String {
        switch self {
        case .activity: return "Activity"
        case .access:   return "Access"
        case .mail:     return "Mail"
        case .requests: return "Requests"
        case .rules:    return "Rules"
        }
    }

    var systemImage: String {
        switch self {
        case .activity: return "list.bullet.rectangle"
        case .access:   return "folder.badge.gearshape"
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
        case .rules:    return "No rules configured"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .activity: return "As agents read files or write changes inside a session, an evidence ledger of every operation will appear here."
        case .access:   return "Nothing is shared until you share it. Add a folder to let an agent read from it inside a session."
        case .mail:     return "Connect a mailbox to share mail with an agent. Subjects and senders are visible by default; message bodies require an explicit grant."
        case .requests: return "When an agent asks for standing write access it lands here. Requests are answered in a ladder — not this time, once, or add to default."
        case .rules:    return "Rules control what agents can read, write, or redact. Seeded rules block secrets out of the box; add custom rules for anything else."
        }
    }
}

struct LedgerView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var destination: LedgerDestination = .activity

    var body: some View {
        NavigationSplitView {
            LedgerSidebar(selection: $destination)
        } detail: {
            // Title ownership: the DETAIL column owns the window title on
            // macOS `NavigationSplitView`. Setting `.navigationTitle` on
            // the sidebar as well causes the sidebar `List` to start
            // drawing from Y=0 (the first rows land behind the traffic
            // lights). So: the sidebar sets no title, the detail sets a
            // single canonical title — `destination.title` — and that's
            // it. No `.navigationSubtitle` (two-level titles on a
            // destination-switching split view add nothing but another
            // chrome collision surface).
            //
            // `.frame(minWidth:)` guards the detail pane from being
            // squeezed to zero width when the user drags the sidebar
            // divider aggressively; without it a very narrow detail
            // column caused the ambient banner and toolbar to overlap.
            content
                .frame(minWidth: 640, minHeight: 480)
                .navigationTitle(destination.title)
                .toolbar { LedgerToolbar(destination: destination) }
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: .manifoldShowActivityLedger)) { _ in
            destination = .activity
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldShowLedgerDestination)) { notification in
            guard let rawValue = notification.object as? String,
                  let requestedDestination = LedgerDestination(rawValue: rawValue) else {
                return
            }
            destination = requestedDestination
        }
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .activity:
            ActivityView()
        case .access:
            AccessView()
        case .mail:
            MailView()
        case .requests:
            RequestsView()
        case .rules:
            RulesView()
        }
    }
}

/// Phase 1 destination placeholder. Per Principle 10, we name exactly what
/// the user is looking at and when it ships — no fake data, no illusions
/// of completeness.
private struct LedgerPlaceholder: View {
    let destination: LedgerDestination
    let stageTag: String
    let stageCopy: String

    var body: some View {
        VStack(spacing: Spacing.s6) {
            EmptyStateIllustration(
                systemImage: destination.systemImage,
                title: destination.emptyTitle,
                subtitle: destination.emptySubtitle
            )

            VStack(spacing: Spacing.s2) {
                HStack(spacing: Spacing.s2) {
                    Pill(text: stageTag, variant: .defaultScope)
                    Text("Under construction")
                        .font(ManifoldType.tiny)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.4)
                }
                Text(stageCopy)
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.s4)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .fill(ManifoldPalette.surface3.opacity(0.5))
            )
        }
        .padding(Spacing.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ManifoldPalette.bg)
    }
}

#Preview("Ledger window — Activity") {
    LedgerView()
        .environment(ManifoldStore())
        .frame(width: 1080, height: 720)
}
