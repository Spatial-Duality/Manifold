// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AppRootView — wrapper that presents either the FirstRunFlow or
// the LedgerView.
//
// Keeping this separate from ManifoldApp lets the @State sheet flags
// live inside the window (SwiftUI-idiomatic) instead of polluting the
// App type with view state.

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
}

struct AppRootView: View {
    @Environment(ManifoldStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLoadedInitialSummary = false
    @State private var splashFinished = false

    private var shouldShowFirstRun: Bool {
        !store.hasCompletedOnboarding && store.sources.isEmpty
    }

    /// Plays once before first-run on a cold launch where reduce-motion is
    /// off. After it finishes the user transitions into FirstRunFlow.
    /// There is no replay path — the splash is a one-shot brand moment.
    private var shouldShowSplash: Bool {
        shouldShowFirstRun && !splashFinished && !reduceMotion
    }

    var body: some View {
        Group {
            if shouldShowSplash {
                ManifoldTitleSequence(speed: 2.2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .task {
                        // Compressed runtime: ~2.5s including settle + tagline.
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        withAnimation(.easeOut(duration: 0.4)) {
                            splashFinished = true
                        }
                    }
            } else if shouldShowFirstRun {
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
        .task {
            guard !hasLoadedInitialSummary else { return }
            hasLoadedInitialSummary = true
            await store.loadSummary()
        }
    }
}
