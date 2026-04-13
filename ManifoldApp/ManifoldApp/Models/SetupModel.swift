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
    // Onboarding
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "manifold.onboarding.completed") }
    }

    // Preferences
    var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "manifold.launchAtLogin") }
    }
    var notifyOnSessionEnd: Bool {
        didSet { UserDefaults.standard.set(notifyOnSessionEnd, forKey: "manifold.notify.sessionEnd") }
    }
    var notifyOnAccessDenied: Bool {
        didSet { UserDefaults.standard.set(notifyOnAccessDenied, forKey: "manifold.notify.accessDenied") }
    }
    var sessionNotesMode: SessionNoteCaptureMode {
        didSet { UserDefaults.standard.set(sessionNotesMode.rawValue, forKey: "manifold.sessionNotes.mode") }
    }

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "manifold.onboarding.completed")
        launchAtLogin = UserDefaults.standard.bool(forKey: "manifold.launchAtLogin")
        notifyOnSessionEnd = UserDefaults.standard.object(forKey: "manifold.notify.sessionEnd") as? Bool ?? true
        notifyOnAccessDenied = UserDefaults.standard.object(forKey: "manifold.notify.accessDenied") as? Bool ?? true
        sessionNotesMode = SessionNoteCaptureMode(
            rawValue: UserDefaults.standard.string(forKey: "manifold.sessionNotes.mode") ?? ""
        ) ?? .off
    }
}
