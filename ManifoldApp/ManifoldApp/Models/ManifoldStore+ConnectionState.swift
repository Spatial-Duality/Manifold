// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ManifoldStore+ConnectionState — extracted from the monolithic
// ManifoldStore as part of the R4 cohort split.
//
// Owns:
//   - the runtime-connected ping monitor (with exponential backoff)
//   - the XPC connection-state notification observer
//   - the typed RuntimeIssue derivation
//   - the ConnectionEvent stream + per-disconnect notification
//   - the system notification authorization request
//
// The cross-cohort properties (connectionMonitorTask,
// xpcConnectionObserver, lastObservedConnectedAgents, connectionAlerts,
// connectionEventCap, connectionEvents) are declared `internal` on the
// type itself so this extension can access them. Encapsulation is
// preserved at the module boundary; only the type and its extensions
// in the same module touch these.

import Foundation
import ManifoldKit
import ManifoldXPC
import os
import UserNotifications

private let connectionLogger = Logger(subsystem: "com.spatialduality.manifold", category: "store.connection")

extension ManifoldStore {

    /// Typed classification of any active runtime/connection problem.
    /// Single source of truth — replaces ad-hoc string-grep classification
    /// scattered across views. `nil` when everything is healthy.
    var currentRuntimeIssue: RuntimeIssue? {
        RuntimeIssueClassifier.classify(
            isRuntimeConnected: isRuntimeConnected,
            runtimeLaunchError: runtimeLaunchError,
            lastError: lastError
        )
    }

    /// Subscribes to `ManifoldXPCClient.connectionStateChangedNotification`
    /// so disconnects propagate to the UI in <100ms instead of waiting
    /// for the next 5-second ping. The observer is held weakly so the
    /// store doesn't leak.
    func startXPCConnectionObserver() {
        xpcConnectionObserver = NotificationCenter.default.addObserver(
            forName: ManifoldXPCClient.connectionStateChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract the Sendable Bool here so the non-Sendable
            // Notification doesn't cross the actor hop below.
            let connected = (notification.userInfo?["connected"] as? Bool) ?? false
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !connected, self.isRuntimeConnected {
                    // Push the truth immediately; the next ping cycle
                    // will reconcile. Pre-empts the 5-second lying-window.
                    self.isRuntimeConnected = false
                    self.isConnected = false
                    self.connectedAgent = nil
                    self.connectedAgents = []
                    _ = self.runtimeSupervisor.markDegraded(issue: "xpc_interrupted")
                    self.diagnostics.record(.xpcConnectionInterrupted)
                    if self.canStartRuntimeServices,
                       self.runtimeSupervisor.consumeAutomaticRestartSlot() {
                        Task { @MainActor [weak self] in
                            await self?.restartRuntimeHelper(reason: .xpcInterrupted)
                        }
                    }
                }
            }
        }
    }

    /// Diff the previous-vs-new connected-agents set, append events to
    /// the chronological history, and post a system notification when
    /// an agent disconnects during an active session. Idempotent.
    func recordConnectionTransition(newConnectedAgents: Set<String>) {
        let events = ConnectionEventDiff.events(
            previous: lastObservedConnectedAgents,
            current: newConnectedAgents,
            at: Date()
        )
        guard !events.isEmpty else {
            lastObservedConnectedAgents = newConnectedAgents
            return
        }
        // Newest first; cap.
        connectionEvents.insert(contentsOf: events.reversed(), at: 0)
        if connectionEvents.count > Self.connectionEventCap {
            connectionEvents.removeLast(connectionEvents.count - Self.connectionEventCap)
        }
        lastObservedConnectedAgents = newConnectedAgents

        // Notify the user only on disconnect-during-session — at-rest
        // disconnects are typically lid-close noise.
        let sessionWasActive = activeSession != nil
        for event in events where event.kind == .disconnected {
            Task { [presenter = connectionAlerts] in
                await presenter.presentDisconnectAlert(
                    agent: event.agent,
                    sessionWasActive: sessionWasActive
                )
            }
        }
    }

    /// Polls `runtime.ping()` and reconciles connection state.
    /// Exponential backoff while disconnected (5s → 10s → 20s → 30s cap)
    /// keeps idle laptops from burning battery on a dead helper.
    func startConnectionMonitor() {
        connectionMonitorTask?.cancel()
        connectionMonitorTask = Task { [weak self] in
            var ticks = 0
            var previousConnected = false
            var sleepInterval: TimeInterval = 5
            while let self, !Task.isCancelled {
                let pingResult = await self.runtime.ping()
                let connected = pingResult.ok
                await MainActor.run {
                    self.isRuntimeConnected = connected
                    self.isConnected = connected
                    if !connected {
                        self.runtimeSupervisor.markDegraded(issue: "runtime_unavailable")
                        self.connectedAgent = nil
                        self.connectedAgents = []
                        if self.lastError == nil, let runtimeLaunchError = self.runtimeLaunchError {
                            self.lastError = runtimeLaunchError
                        }
                    } else {
                        self.runtimeSupervisor.markHealthy()
                    }
                }

                ticks += 1
                if connected && (!previousConnected || ticks % 6 == 0) {
                    await self.refreshAll()
                }

                // Backoff schedule: connected stays at 5s; disconnected
                // doubles with cap at 30s. Reconnect immediately drops
                // back to 5s on the next loop iteration.
                if connected {
                    sleepInterval = 5
                } else {
                    sleepInterval = min(sleepInterval * 2, 30)
                }

                previousConnected = connected
                try? await Task.sleep(for: .seconds(sleepInterval))
            }
        }
    }

    /// Asks for permission to post system notifications. Used by the
    /// disconnect-during-session alert path. Silent no-op when the
    /// bundle has no identifier (test harness).
    func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
