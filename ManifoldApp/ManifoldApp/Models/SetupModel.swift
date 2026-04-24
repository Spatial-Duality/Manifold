// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import ManifoldKit

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "setup")

/// Slimmed SetupModel — preferences only.
/// MCP/agent config checks moved to IntegrationHealthModel.
@Observable
@MainActor
final class SetupModel {
    private let defaults: UserDefaults

    // Onboarding
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "manifold.onboarding.completed") }
    }

    // Preferences
    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "manifold.launchAtLogin") }
    }
    var notifyOnSessionEnd: Bool {
        didSet { defaults.set(notifyOnSessionEnd, forKey: "manifold.notify.sessionEnd") }
    }
    var notifyOnAccessDenied: Bool {
        didSet { defaults.set(notifyOnAccessDenied, forKey: "manifold.notify.accessDenied") }
    }
    var sessionNotesMode: SessionNoteCaptureMode {
        didSet { defaults.set(sessionNotesMode.rawValue, forKey: "manifold.sessionNotes.mode") }
    }

    init() {
        let defaults = AppTestEnvironment.userDefaults()
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: "manifold.onboarding.completed")
        launchAtLogin = defaults.bool(forKey: "manifold.launchAtLogin")
        notifyOnSessionEnd = defaults.object(forKey: "manifold.notify.sessionEnd") as? Bool ?? true
        notifyOnAccessDenied = defaults.object(forKey: "manifold.notify.accessDenied") as? Bool ?? true
        sessionNotesMode = SessionNoteCaptureMode(
            rawValue: defaults.string(forKey: "manifold.sessionNotes.mode") ?? ""
        ) ?? .off
    }
}
