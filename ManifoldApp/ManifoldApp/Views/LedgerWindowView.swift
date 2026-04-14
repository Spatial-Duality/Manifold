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
        case .rules:    return "No rules yet"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .activity: return "As agents read files or write changes inside a session, an evidence ledger of every operation will appear here."
        case .access:   return "Nothing is shared until you share it. Add a folder to let an agent read from it inside a session."
        case .mail:     return "Connect a mailbox to share mail with an agent. Subjects and senders are visible by default; message bodies require an explicit grant."
        case .requests: return "When an agent asks for access it will land here. Requests are answered in a ladder — deny, once, session, default."
        case .rules:    return "Rules are the always-on layer: things Claude never does, never reads. Defaults seed the common ones — you can add your own."
        }
    }
}

struct LedgerWindowView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var destination: LedgerDestination = .activity

    var body: some View {
        NavigationSplitView {
            NavSidebar(selection: $destination)
                .navigationSplitViewColumnWidth(min: 184, ideal: 200, max: 240)
        } detail: {
            content
                .navigationTitle(destination.title)
                .toolbar { IntegratedToolbar(destination: destination) }
                .safeAreaInset(edge: .bottom) { StatusBar() }
        }
        .navigationSplitViewStyle(.balanced)
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
    LedgerWindowView()
        .environment(ManifoldStore())
        .frame(width: 1080, height: 720)
}
