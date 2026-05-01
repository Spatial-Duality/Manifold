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
// Approvals, session history, runtime health, and activity evidence live
// inside Work rather than separate top-level destinations.

import SwiftUI
import ManifoldKit

struct LedgerView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var destination: LedgerDestination = .work
    @State private var accessSection: AccessSection = .folders
    @State private var work = WorkModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            UnifiedLedgerSidebar(
                destination: $destination,
                accessSection: $accessSection,
                work: work
            )
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
                .background(workingSurfaceVignette, alignment: .top)
                .navigationTitle(destination.title)
                .toolbar { LedgerToolbar(destination: destination) }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
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
            WorkView(work: work)
        case .access:
            AccessView(selectedSection: $accessSection)
        case .mail:
            MailView()
        case .rules:
            RulesView()
        }
    }

    /// Quiet saffron vignette that fades from a 4% wash at the top of
    /// the detail column to clear by ~220pt. Carries the brand warmth
    /// from the splash + first-run atmosphere into the working surface
    /// without interfering with content readability below.
    private var workingSurfaceVignette: some View {
        LinearGradient(
            stops: [
                .init(color: ManifoldPalette.brand.opacity(0.04), location: 0),
                .init(color: ManifoldPalette.brand.opacity(0.02), location: 0.4),
                .init(color: .clear,                              location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 220)
        .allowsHitTesting(false)
    }
}

#Preview("Ledger window — Work") {
    LedgerView()
        .environment(ManifoldStore(runtime: FixtureRuntimeClient(profile: .trackedWork), startServices: false))
        .frame(width: 1080, height: 720)
}
