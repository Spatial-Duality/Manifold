// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ConnectionEventTracker — observes connectedAgents transitions and
// records typed connection events. Surfaces user-noticeable changes
// (disconnect during a session) via UNUserNotificationCenter, and
// keeps an in-memory history the UI can display in the Activity
// timeline.
//
// The tracker is pure-logic: it computes the diff between two
// `Set<String>` snapshots and decides what events to emit. No
// side effects in the diff function — the call site decides whether
// to post a system notification or just append to history. Tested.

import Foundation
import ManifoldKit
import UserNotifications

/// One discrete connection-state change. Stored chronologically so the
/// UI can render "Claude connected at 2:34 PM, Claude disconnected at
/// 4:12 PM" without losing earlier history.
struct ConnectionEvent: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable, Equatable {
        case connected
        case disconnected
    }

    let id: UUID
    let agent: TargetApp
    let kind: Kind
    let at: Date

    init(id: UUID = UUID(), agent: TargetApp, kind: Kind, at: Date) {
        self.id = id
        self.agent = agent
        self.kind = kind
        self.at = at
    }
}

/// Pure diff: given the previous and current set of connected agent raw
/// values, returns the events that fired in between. Order: disconnects
/// first (so the UI shows the bad-news event first), then connects.
enum ConnectionEventDiff {
    static func events(
        previous: Set<String>,
        current: Set<String>,
        at now: Date
    ) -> [ConnectionEvent] {
        let disconnected = previous.subtracting(current)
            .compactMap(TargetApp.init(rawValue:))
            .sorted(by: { $0.rawValue < $1.rawValue })
        let connected = current.subtracting(previous)
            .compactMap(TargetApp.init(rawValue:))
            .sorted(by: { $0.rawValue < $1.rawValue })

        return disconnected.map { ConnectionEvent(agent: $0, kind: .disconnected, at: now) }
            + connected.map { ConnectionEvent(agent: $0, kind: .connected, at: now) }
    }
}

/// Wraps UNUserNotificationCenter for the disconnect-during-session
/// alert. Indirection isolates the side effect for testing and keeps
/// the store free of UNNotificationCenter coupling.
@MainActor
protocol ConnectionAlertPresenting: Sendable {
    func presentDisconnectAlert(agent: TargetApp, sessionWasActive: Bool) async
}

/// Production implementation that posts a transient banner via
/// UNUserNotificationCenter. Quiet on purpose — no sound, no badge,
/// because most disconnects are recoverable and the user shouldn't
/// be jolted out of focus by every blip.
struct SystemConnectionAlertPresenter: ConnectionAlertPresenting {
    func presentDisconnectAlert(agent: TargetApp, sessionWasActive: Bool) async {
        // Only surface a system notification when a session was running
        // — at-rest disconnects are typically lid-close / sleep noise
        // and don't deserve a banner.
        guard sessionWasActive else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(label(for: agent)) disconnected"
        content.body = "An active session lost its connection. Manifold tracked the writes; reconnect to continue."
        // No sound — quiet by default. User can enable in System Settings.
        let request = UNNotificationRequest(
            identifier: "manifold.disconnect.\(agent.rawValue)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func label(for agent: TargetApp) -> String {
        switch agent {
        case .cowork: return "Claude"
        case .codex:  return "Codex"
        }
    }
}
