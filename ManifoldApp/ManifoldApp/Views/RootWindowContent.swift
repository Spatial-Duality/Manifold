// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AppRootView — wrapper that presents either the FirstRunFlow or
// the LedgerView.
//
// Keeping this separate from ManifoldApp lets the @State sheet flags
// live inside the window (SwiftUI-idiomatic) instead of polluting the
// App type with view state.

import AppKit
import SwiftUI
import ManifoldKit

extension Notification.Name {
    static let manifoldShowWork = Notification.Name("manifold.showWork")
    static let manifoldShowLedgerDestination = Notification.Name("manifold.showLedgerDestination")
    static let manifoldFocusCurrentSearch = Notification.Name("manifold.focusCurrentSearch")
    static let manifoldCycleCurrentSubtab = Notification.Name("manifold.cycleCurrentSubtab")
    static let manifoldToggleCurrentInspector = Notification.Name("manifold.toggleCurrentInspector")
    static let manifoldPauseAllFromIntent = Notification.Name("manifoldPauseAllFromIntent")
    static let manifoldStartSessionFromIntent = Notification.Name("manifoldStartSessionFromIntent")
    static let manifoldOpenSettingsDiagnostics = Notification.Name("manifold.openSettingsDiagnostics")
    static let manifoldFinderCommandQueued = Notification.Name("com.spatialduality.manifold.finderCommandQueued")
}

struct AppRootView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var hasLoadedInitialSummary = false
    @State private var finderCommandObserver: NSObjectProtocol?

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
        .onReceive(NotificationCenter.default.publisher(for: .manifoldShowWork)) { _ in
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
        .onReceive(NotificationCenter.default.publisher(for: .manifoldPauseAllFromIntent)) { _ in
            Task { await store.governance.pauseAllAgents() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refreshAll(force: false) }
        }
        .onAppear {
            guard finderCommandObserver == nil else { return }
            finderCommandObserver = DistributedNotificationCenter.default().addObserver(
                forName: .manifoldFinderCommandQueued,
                object: nil,
                queue: .main
            ) { _ in
                Task { await store.refreshAll(force: false) }
            }
        }
        .onDisappear {
            if let finderCommandObserver {
                DistributedNotificationCenter.default().removeObserver(finderCommandObserver)
                self.finderCommandObserver = nil
            }
        }
        .task {
            guard !hasLoadedInitialSummary else { return }
            hasLoadedInitialSummary = true
            await store.loadSummary()
        }
    }
}
