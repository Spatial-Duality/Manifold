// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

/// Health status for a single check.
public enum AgentConnectionStatus: String, Sendable {
    case unknown, checking, notInstalled, installed, configured, connected, error

    var isPassingCheck: Bool {
        switch self {
        case .installed, .configured, .connected:
            return true
        case .unknown, .checking, .notInstalled, .error:
            return false
        }
    }

    var displayLabel: String {
        switch self {
        case .unknown: ""
        case .checking: "Checking\u{2026}"
        case .notInstalled: "Not found"
        case .installed: "Installed"
        case .configured: "Configured"
        case .connected: "Connected"
        case .error: "Error"
        }
    }
}

/// Per-agent connection state: Claude has 3 checks, Codex has 2.
@Observable
@MainActor
public final class AgentConnectionState: Identifiable {
    public let id: TargetApp

    // Claude checks
    var appInstalled: AgentConnectionStatus = .unknown
    var mcpConfigured: AgentConnectionStatus = .unknown
    var claudeCodeConfigured: AgentConnectionStatus = .unknown
    var connectionVerified: AgentConnectionStatus = .unknown

    // Codex checks
    var cliInstalled: AgentConnectionStatus = .unknown
    var mcpAdded: AgentConnectionStatus = .unknown

    var errorDetail: String?

    var overallStatus: AgentConnectionStatus {
        switch id {
        case .cowork:
            if connectionVerified == .connected { return .connected }
            if [appInstalled, mcpConfigured, claudeCodeConfigured, connectionVerified].contains(.error) { return .error }
            if mcpConfigured.isPassingCheck || claudeCodeConfigured.isPassingCheck { return .configured }
            if appInstalled == .installed { return .installed }
            return .notInstalled
        case .codex:
            if mcpAdded == .connected { return .connected }
            if [cliInstalled, mcpAdded].contains(.error) { return .error }
            if mcpAdded.isPassingCheck { return .configured }
            if cliInstalled == .installed { return .installed }
            return .notInstalled
        }
    }

    init(agent: TargetApp) { self.id = agent }
}
