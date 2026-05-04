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

// MARK: - Start Session

struct StartSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Prepare Work Session"
    static let description: IntentDescription = "Opens Manifold to prepare or activate a named AI access session."
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .manifoldStartSessionFromIntent, object: nil)
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
            intent: StartSessionIntent(),
            phrases: [
                "Prepare a Focus in \(.applicationName)"
            ],
            shortTitle: "Prepare Focus",
            systemImageName: "rectangle.stack.badge.play"
        )
    }
}

// MARK: - Notification Names
