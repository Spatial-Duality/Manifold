// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "health")

/// Structured, pollable, debounced health state for AI agent integrations.
/// Replaces flat booleans in SetupModel with per-agent, per-check granularity.
/// Uses a 5-second cache to avoid redundant filesystem reads on rapid tab switches.
@Observable
@MainActor
final class IntegrationHealthModel {
    var claude = AgentConnectionState(agent: .cowork)
    var codex = AgentConnectionState(agent: .codex)

    weak var store: ManifoldStore?

    // MARK: - Debounce

    private var lastCheckedAt: Date?
    private static let cacheInterval: TimeInterval = 5.0

    /// Check all agents. Returns cached results if called within 5 seconds.
    /// Pass `force: true` for explicit user-initiated refresh.
    func checkAll(force: Bool = false) async {
        if !force, let last = lastCheckedAt,
           Date().timeIntervalSince(last) < Self.cacheInterval {
            logger.debug("Health check skipped — cached \(Date().timeIntervalSince(last), format: .fixed(precision: 1))s ago")
            return
        }
        lastCheckedAt = Date()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.checkClaude() }
            group.addTask { await self.checkCodex() }
        }
    }

    func state(for agent: TargetApp) -> AgentConnectionState {
        agent == .codex ? codex : claude
    }

    // MARK: - Claude Checks

    func checkClaude() async {
        claude.appInstalled = .checking
        claude.mcpConfigured = .checking
        claude.claudeCodeConfigured = .checking
        claude.connectionVerified = .checking
        claude.errorDetail = nil

        // 1. Claude Desktop.app installed?
        let appPath = "/Applications/Claude.app"
        let altPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Claude.app").path
        claude.appInstalled = FileManager.default.fileExists(atPath: appPath)
            || FileManager.default.fileExists(atPath: altPath)
            ? .installed : .notInstalled

        // 2. Claude Desktop config valid?
        let desktopConfigPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json").path
        let desktopConfig = validateJSONConfig(
            at: desktopConfigPath,
            agent: .cowork,
            label: "Claude Desktop"
        )
        claude.mcpConfigured = desktopConfig.status

        // 3. Claude Code config valid?
        let claudeCodePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json").path
        let claudeCodeConfig = validateJSONConfig(
            at: claudeCodePath,
            agent: .cowork,
            label: "Claude Code"
        )
        claude.claudeCodeConfigured = claudeCodeConfig.status

        // 4. Live connection?
        if let store, store.isClaudeConnected {
            claude.connectionVerified = .connected
        } else if desktopConfig.status.isPassingCheck || claudeCodeConfig.status.isPassingCheck {
            claude.connectionVerified = .configured
        } else if desktopConfig.status == .error || claudeCodeConfig.status == .error {
            claude.connectionVerified = .error
        } else {
            claude.connectionVerified = .notInstalled
        }

        claude.errorDetail = [desktopConfig.detail, claudeCodeConfig.detail]
            .compactMap { $0 }
            .joined(separator: "\n")
            .nilIfEmpty
    }

    // MARK: - Codex Checks

    func checkCodex() async {
        codex.cliInstalled = .checking
        codex.mcpAdded = .checking
        codex.errorDetail = nil

        // 1. Codex CLI installed?
        let paths = ["/usr/local/bin/codex", "/opt/homebrew/bin/codex",
                     FileManager.default.homeDirectoryForCurrentUser
                         .appendingPathComponent(".local/bin/codex").path]
        let found = paths.contains { FileManager.default.fileExists(atPath: $0) }
        codex.cliInstalled = found ? .installed : .notInstalled

        guard found else {
            codex.mcpAdded = .notInstalled
            return
        }

        // 2. Manifold config valid?
        let tomlPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml").path
        let codexConfig = validateCodexConfig(at: tomlPath, agent: .codex)
        if let store, store.isCodexConnected, codexConfig.status == .installed {
            codex.mcpAdded = .connected
        } else {
            codex.mcpAdded = codexConfig.status
        }
        codex.errorDetail = codexConfig.detail
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

private struct ConfigValidation {
    let status: AgentConnectionStatus
    let detail: String?

    init(status: AgentConnectionStatus, detail: String? = nil) {
        self.status = status
        self.detail = detail
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
