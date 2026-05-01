// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ClaudeRelauncher — programmatic restart of Claude Desktop.
//
// Closes the missing link between "Manifold wrote the MCP config" and
// "Claude Desktop reconnected with the new config." Without this the
// user has to know to quit and reopen Claude themselves; most don't,
// and the Connect sheet sits at "configured but not connected" forever.
//
// Approach: NSRunningApplication for the bundle id, terminate, then
// NSWorkspace.openApplication when the running app has cleared. macOS
// asks the user to confirm the quit if Claude has unsaved state — we
// rely on that as the explicit-permission gate. We never force-kill.

import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "claude-relaunch")

enum ClaudeRelaunchOutcome: Sendable, Equatable {
    case relaunched
    case notRunning
    case timedOut(seconds: Int)
    case launchFailed(detail: String)
}

enum ClaudeRelauncher {
    /// Bundle identifier Apple's Claude Desktop ships with. Hard-coded
    /// because there is no first-party API to discover it.
    static let bundleIdentifier = "com.anthropic.claudefordesktop"

    /// Quits Claude Desktop if running, then relaunches it. The quit is
    /// non-forcing: macOS prompts the user if Claude has unsaved state.
    /// Returns the observed outcome so the caller can show feedback.
    @MainActor
    static func relaunch() async -> ClaudeRelaunchOutcome {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard let app = running.first, let bundleURL = app.bundleURL else {
            // Nothing to relaunch — but try a fresh launch by URL.
            return await launchFresh()
        }

        logger.info("Asking Claude Desktop to terminate (pid \(app.processIdentifier))")
        let didRequestTerminate = app.terminate()
        guard didRequestTerminate else {
            logger.warning("NSRunningApplication.terminate() returned false; Claude likely refused.")
            return .launchFailed(detail: "Claude Desktop refused the quit request. Quit it manually and try again.")
        }

        // Poll for the running app to actually clear. Cap at 5 seconds.
        // Most Claude sessions take 200-500ms to close.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(150))
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
                break
            }
        }

        if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
            return .timedOut(seconds: 5)
        }

        return await launch(at: bundleURL)
    }

    @MainActor
    private static func launchFresh() async -> ClaudeRelaunchOutcome {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return .notRunning
        }
        return await launch(at: url)
    }

    @MainActor
    private static func launch(at bundleURL: URL) async -> ClaudeRelaunchOutcome {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
            logger.info("Relaunched Claude Desktop from \(bundleURL.path, privacy: .public)")
            return .relaunched
        } catch {
            logger.error("Failed to relaunch Claude Desktop: \(error.localizedDescription, privacy: .public)")
            return .launchFailed(detail: error.localizedDescription)
        }
    }
}
