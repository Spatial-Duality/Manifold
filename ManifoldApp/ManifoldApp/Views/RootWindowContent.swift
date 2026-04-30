// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AppRootView — wrapper that presents either the FirstRunFlow or
// the LedgerView, plus command palette presentation.
//
// Keeping this separate from ManifoldApp lets the @State sheet flags
// live inside the window (SwiftUI-idiomatic) instead of polluting the
// App type with view state.

import SwiftUI
import ManifoldKit

extension Notification.Name {
    static let manifoldShowSessions = Notification.Name("manifold.showSessions")
    static let manifoldShowActivityLedger = Notification.Name("manifold.showActivityLedger")
    static let manifoldShowLedgerDestination = Notification.Name("manifold.showLedgerDestination")
    static let manifoldFocusCurrentSearch = Notification.Name("manifold.focusCurrentSearch")
    static let manifoldCycleCurrentSubtab = Notification.Name("manifold.cycleCurrentSubtab")
    static let manifoldPauseAllFromIntent = Notification.Name("manifoldPauseAllFromIntent")
    static let manifoldStartSessionFromIntent = Notification.Name("manifoldStartSessionFromIntent")
    static let manifoldOpenActivityFromIntent = Notification.Name("manifoldOpenActivityFromIntent")
    static let manifoldOpenSettingsDiagnostics = Notification.Name("manifold.openSettingsDiagnostics")
}

struct AppRootView: View {
    @Environment(ManifoldStore.self) private var store
    @Environment(CommandPaletteModel.self) private var commandPalette
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
        .sheet(isPresented: Binding(
            get: { commandPalette.isPresented },
            set: { commandPalette.isPresented = $0 }
        )) {
            CommandPaletteView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldShowSessions)) { _ in
            presentMainLedger(destination: .work)
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldStartSessionFromIntent)) { _ in
            presentMainLedger(destination: .work)
            if store.sessionWorkbench.preload == nil {
                store.beginSessionPreload(
                    agent: store.defaultSessionAgent,
                    baseMode: .buildOnDefault
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldOpenActivityFromIntent)) { _ in
            presentMainLedger(destination: .work)
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
