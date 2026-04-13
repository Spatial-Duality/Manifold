// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import ManifoldKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "health")

struct AgentHealthSnapshot: Sendable {
    var appInstalled: AgentConnectionStatus = .unknown
    var mcpConfigured: AgentConnectionStatus = .unknown
    var claudeCodeConfigured: AgentConnectionStatus = .unknown
    var connectionVerified: AgentConnectionStatus = .unknown
    var codexAppInstalled: AgentConnectionStatus = .unknown
    var mcpAdded: AgentConnectionStatus = .unknown
    var errorDetail: String?
}

protocol IntegrationHealthChecking: Sendable {
    func checkClaude(isConnected: Bool) async -> AgentHealthSnapshot
    func checkCodex(isConnected: Bool) async -> AgentHealthSnapshot
}

struct SystemIntegrationHealthChecker: IntegrationHealthChecking {
    func checkClaude(isConnected: Bool) async -> AgentHealthSnapshot {
        var snapshot = AgentHealthSnapshot(
            appInstalled: .checking,
            mcpConfigured: .checking,
            claudeCodeConfigured: .checking,
            connectionVerified: .checking
        )

        let appPath = "/Applications/Claude.app"
        let altPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Claude.app").path
        snapshot.appInstalled = FileManager.default.fileExists(atPath: appPath)
            || FileManager.default.fileExists(atPath: altPath)
            ? .installed : .notInstalled

        let desktopConfigPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json").path
        let desktopConfig = validateJSONConfig(
            at: desktopConfigPath,
            agent: .cowork,
            label: "Claude Desktop"
        )
        snapshot.mcpConfigured = desktopConfig.status

        let claudeCodePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json").path
        let claudeCodeConfig = validateJSONConfig(
            at: claudeCodePath,
            agent: .cowork,
            label: "Claude Code"
        )
        snapshot.claudeCodeConfigured = claudeCodeConfig.status

        if isConnected {
            snapshot.connectionVerified = .connected
        } else if desktopConfig.status.isPassingCheck || claudeCodeConfig.status.isPassingCheck {
            snapshot.connectionVerified = .configured
        } else if desktopConfig.status == .error || claudeCodeConfig.status == .error {
            snapshot.connectionVerified = .error
        } else {
            snapshot.connectionVerified = .notInstalled
        }

        snapshot.errorDetail = [desktopConfig.detail, claudeCodeConfig.detail]
            .compactMap { $0 }
            .joined(separator: "\n")
            .nilIfEmpty

        return snapshot
    }

    func checkCodex(isConnected: Bool) async -> AgentHealthSnapshot {
        var snapshot = AgentHealthSnapshot(
            codexAppInstalled: .checking,
            mcpAdded: .checking
        )

        let codexHome = FileManager.default.homeDirectoryForCurrentUser
        let configDir = codexHome.appendingPathComponent(".codex")
        let codexAppFound = detectCodexDesktopApp()
        snapshot.codexAppInstalled = codexAppFound ? .installed : .notInstalled

        guard codexAppFound || FileManager.default.fileExists(atPath: configDir.path) else {
            snapshot.mcpAdded = .notInstalled
            return snapshot
        }

        let tomlPath = configDir.appendingPathComponent("config.toml").path
        let codexConfig = validateCodexConfig(at: tomlPath, agent: .codex)
        snapshot.mcpAdded = isConnected && codexConfig.status == .installed ? .connected : codexConfig.status
        snapshot.errorDetail = codexConfig.detail
        return snapshot
    }

    private func detectCodexDesktopApp() -> Bool {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") != nil {
            return true
        }

        let candidatePaths = [
            "/Applications/Codex.app",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Codex.app").path,
        ]

        return candidatePaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func validateJSONConfig(at path: String, agent: TargetApp, label: String) -> ConfigValidation {
        guard FileManager.default.fileExists(atPath: path) else {
            return .init(status: .notInstalled)
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            return .init(status: .error, detail: "\(label) config exists but could not be read.")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .init(status: .error, detail: "\(label) config is not valid JSON.")
        }
        guard let servers = json["mcpServers"] as? [String: Any],
              let manifold = servers["manifold"] as? [String: Any] else {
            return .init(status: .notInstalled)
        }
        return validateServerEntry(manifold, agent: agent, label: label)
    }

    private func validateCodexConfig(at path: String, agent: TargetApp) -> ConfigValidation {
        guard FileManager.default.fileExists(atPath: path) else {
            return .init(status: .notInstalled)
        }
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return .init(status: .error, detail: "Codex config exists but could not be read.")
        }
        guard let block = codexServerBlock(in: contents) else {
            return .init(status: .notInstalled)
        }

        let commandPattern = #"\bcommand\s*=\s*"([^"]+)""#
        guard let command = firstCapture(in: block, pattern: commandPattern) else {
            return .init(status: .error, detail: "Codex Manifold config is missing its command path.")
        }
        guard FileManager.default.isExecutableFile(atPath: command) || FileManager.default.fileExists(atPath: command) else {
            return .init(status: .error, detail: "Codex Manifold command path does not exist: \(command)")
        }

        let expectedArgs = ConfigWriter.expectedArguments(for: agent)
        let argsPattern = #"args\s*=\s*\[\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\]"#
        guard let firstArg = firstCapture(in: block, pattern: argsPattern, group: 1),
              let secondArg = firstCapture(in: block, pattern: argsPattern, group: 2),
              [firstArg, secondArg] == expectedArgs else {
            return .init(
                status: .error,
                detail: "Codex Manifold config must include args \(expectedArgs.joined(separator: " "))."
            )
        }

        return .init(status: .installed)
    }

    private func validateServerEntry(_ server: [String: Any], agent: TargetApp, label: String) -> ConfigValidation {
        guard let command = server["command"] as? String, !command.isEmpty else {
            return .init(status: .error, detail: "\(label) Manifold config is missing its command path.")
        }
        guard FileManager.default.isExecutableFile(atPath: command) || FileManager.default.fileExists(atPath: command) else {
            return .init(status: .error, detail: "\(label) Manifold command path does not exist: \(command)")
        }

        let expectedArgs = ConfigWriter.expectedArguments(for: agent)
        let args = server["args"] as? [String] ?? []
        guard args == expectedArgs else {
            return .init(
                status: .error,
                detail: "\(label) Manifold config must include args \(expectedArgs.joined(separator: " "))."
            )
        }
        return .init(status: .installed)
    }

    private func codexServerBlock(in contents: String) -> String? {
        let patterns = [
            #"\[mcp_servers\.manifold\]\n(?:[^\[]*(?:\n|$))*"#,
            #"\[mcp\.manifold\]\n(?:[^\[]*(?:\n|$))*"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
            guard let match = regex.firstMatch(in: contents, options: [], range: range),
                  let blockRange = Range(match.range, in: contents) else { continue }
            return String(contents[blockRange])
        }

        return nil
    }

    private func firstCapture(in text: String, pattern: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let captureRange = Range(match.range(at: group), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }
}

struct FixtureIntegrationHealthChecker: IntegrationHealthChecking {
    let profile: AppFixtureProfile

    func checkClaude(isConnected: Bool) async -> AgentHealthSnapshot {
        switch profile {
        case .onboarding:
            return AgentHealthSnapshot(
                appInstalled: .installed,
                mcpConfigured: .configured,
                claudeCodeConfigured: .notInstalled,
                connectionVerified: .configured
            )
        case .dashboard, .emailRules, .trackedWork, .activity:
            return AgentHealthSnapshot(
                appInstalled: .installed,
                mcpConfigured: .connected,
                claudeCodeConfigured: .configured,
                connectionVerified: isConnected ? .connected : .configured
            )
        }
    }

    func checkCodex(isConnected: Bool) async -> AgentHealthSnapshot {
        switch profile {
        case .onboarding:
            return AgentHealthSnapshot(
                codexAppInstalled: .installed,
                mcpAdded: .configured
            )
        case .dashboard, .emailRules, .trackedWork, .activity:
            return AgentHealthSnapshot(
                codexAppInstalled: .installed,
                mcpAdded: isConnected ? .connected : .configured
            )
        }
    }
}

/// Structured, pollable, debounced health state for AI agent integrations.
/// Replaces flat booleans in SetupModel with per-agent, per-check granularity.
/// Uses a 5-second cache to avoid redundant filesystem reads on rapid tab switches.
@Observable
@MainActor
final class IntegrationHealthModel {
    var claude = AgentConnectionState(agent: .cowork)
    var codex = AgentConnectionState(agent: .codex)

    weak var store: ManifoldStore?
    private let checker: any IntegrationHealthChecking

    private var lastCheckedAt: Date?
    private static let cacheInterval: TimeInterval = 5.0

    init(checker: any IntegrationHealthChecking = SystemIntegrationHealthChecker()) {
        self.checker = checker
    }

    /// Check all agents. Returns cached results if called within 5 seconds.
    /// Pass `force: true` for explicit user-initiated refresh.
    func checkAll(force: Bool = false) async {
        if !force, let last = lastCheckedAt,
           Date().timeIntervalSince(last) < Self.cacheInterval {
            logger.debug("Health check skipped — cached \(Date().timeIntervalSince(last), format: .fixed(precision: 1))s ago")
            return
        }

        lastCheckedAt = Date()
        let claudeConnected = store?.isClaudeConnected ?? false
        let codexConnected = store?.isCodexConnected ?? false

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let snapshot = await self.checker.checkClaude(isConnected: claudeConnected)
                await MainActor.run { self.claude.apply(snapshot: snapshot) }
            }
            group.addTask {
                let snapshot = await self.checker.checkCodex(isConnected: codexConnected)
                await MainActor.run { self.codex.apply(snapshot: snapshot) }
            }
        }
    }

    func state(for agent: TargetApp) -> AgentConnectionState {
        agent == .codex ? codex : claude
    }

    func checkClaude() async {
        let snapshot = await checker.checkClaude(isConnected: store?.isClaudeConnected ?? false)
        claude.apply(snapshot: snapshot)
        lastCheckedAt = Date()
    }

    func checkCodex() async {
        let snapshot = await checker.checkCodex(isConnected: store?.isCodexConnected ?? false)
        codex.apply(snapshot: snapshot)
        lastCheckedAt = Date()
    }
}

private struct ConfigValidation {
    let status: AgentConnectionStatus
    let detail: String?

    init(status: AgentConnectionStatus, detail: String? = nil) {
        self.status = status
        self.detail = detail
    }
}

private extension AgentConnectionState {
    func apply(snapshot: AgentHealthSnapshot) {
        appInstalled = snapshot.appInstalled
        mcpConfigured = snapshot.mcpConfigured
        claudeCodeConfigured = snapshot.claudeCodeConfigured
        connectionVerified = snapshot.connectionVerified
        codexAppInstalled = snapshot.codexAppInstalled
        mcpAdded = snapshot.mcpAdded
        errorDetail = snapshot.errorDetail
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
