// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import AppIntents
import SwiftUI

// MARK: - Pause All Access

struct PauseAllAccessIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause All AI Access"
    static let description: IntentDescription = "Immediately suspends all AI agent access to files and emails."

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .manifoldPauseAllFromIntent, object: nil)
        return .result(dialog: "All AI access has been paused.")
    }
}

// MARK: - Open Manifold

struct OpenManifoldIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Manifold"
    static let description: IntentDescription = "Opens the Manifold window to manage AI access."
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Start Tracked Work Block

struct StartWorkBlockIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Tracked Work Block"
    static let description: IntentDescription = "Opens Manifold to start a tracked work block with change monitoring."
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .manifoldStartWorkBlockFromIntent, object: nil)
        return .result()
    }
}

// MARK: - Open Activity

struct OpenActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Open AI Activity"
    static let description: IntentDescription = "Opens Manifold's activity drawer showing recent AI actions."
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .manifoldOpenActivityFromIntent, object: nil)
        return .result()
    }
}

// MARK: - App Shortcuts Provider

struct ManifoldShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PauseAllAccessIntent(),
            phrases: [
                "Pause all AI access in \(.applicationName)",
                "Stop AI access in \(.applicationName)"
            ],
            shortTitle: "Pause AI Access",
            systemImageName: "shield.slash"
        )

        AppShortcut(
            intent: StartWorkBlockIntent(),
            phrases: [
                "Start tracking changes in \(.applicationName)"
            ],
            shortTitle: "Track Changes",
            systemImageName: "timeline.selection"
        )

        AppShortcut(
            intent: OpenActivityIntent(),
            phrases: [
                "Show AI activity in \(.applicationName)"
            ],
            shortTitle: "AI Activity",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let manifoldPauseAllFromIntent = Notification.Name("manifoldPauseAllFromIntent")
    static let manifoldStartWorkBlockFromIntent = Notification.Name("manifoldStartWorkBlockFromIntent")
    static let manifoldOpenActivityFromIntent = Notification.Name("manifoldOpenActivityFromIntent")
}
