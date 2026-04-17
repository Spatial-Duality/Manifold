// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AppRootView — wrapper that presents either the FirstRunFlow or
// the LedgerView, plus sheet presentations for session start and
// the command palette.
//
// Keeping this separate from ManifoldApp lets the @State sheet flags
// live inside the window (SwiftUI-idiomatic) instead of polluting the
// App type with view state.

import SwiftUI
import ManifoldKit

extension Notification.Name {
    static let manifoldShowSessionStartSheet = Notification.Name("manifold.showSessionStartSheet")
    static let manifoldShowActivityLedger = Notification.Name("manifold.showActivityLedger")
    static let manifoldShowLedgerDestination = Notification.Name("manifold.showLedgerDestination")
    static let manifoldFocusCurrentSearch = Notification.Name("manifold.focusCurrentSearch")
    static let manifoldCycleCurrentSubtab = Notification.Name("manifold.cycleCurrentSubtab")
    static let manifoldPauseAllFromIntent = Notification.Name("manifoldPauseAllFromIntent")
    static let manifoldStartSessionFromIntent = Notification.Name("manifoldStartSessionFromIntent")
    static let manifoldOpenActivityFromIntent = Notification.Name("manifoldOpenActivityFromIntent")
}

struct AppRootView: View {
    @Environment(ManifoldStore.self) private var store
    @Environment(CommandPaletteModel.self) private var commandPalette
    @State private var isPresentingSessionStartSheet = false
    @State private var hasLoadedInitialSummary = false

    private var shouldShowFirstRun: Bool {
        !store.hasCompletedOnboarding && store.sources.isEmpty
    }

    var body: some View {
        Group {
            if shouldShowFirstRun {
                FirstRunFlow()
            } else {
                LedgerView()
            }
        }
        .sheet(isPresented: $isPresentingSessionStartSheet) {
            SessionStartSheet()
        }
        .sheet(isPresented: Binding(
            get: { commandPalette.isPresented },
            set: { commandPalette.isPresented = $0 }
        )) {
            CommandPaletteView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldShowSessionStartSheet)) { _ in
            isPresentingSessionStartSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldStartSessionFromIntent)) { _ in
            isPresentingSessionStartSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldOpenActivityFromIntent)) { _ in
            presentMainLedger(destination: .activity)
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldPauseAllFromIntent)) { _ in
            Task { await store.governance.pauseAllAgents() }
        }
        .task {
            guard !hasLoadedInitialSummary else { return }
            hasLoadedInitialSummary = true
            commandPalette.bind(to: store)
            await store.loadSummary()
        }
    }
}
