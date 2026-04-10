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
        claude.connectionVerified = .checking

        // 1. Claude Desktop.app installed?
        let appPath = "/Applications/Claude.app"
        let altPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Claude.app").path
        claude.appInstalled = FileManager.default.fileExists(atPath: appPath)
            || FileManager.default.fileExists(atPath: altPath)
            ? .installed : .notInstalled

        // 2. Manifold MCP configured?
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json").path
        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let servers = json["mcpServers"] as? [String: Any],
           servers.keys.contains(where: { $0.lowercased().contains("manifold") }) {
            claude.mcpConfigured = .installed
        } else {
            claude.mcpConfigured = .notInstalled
        }

        // 3. Live connection?
        if let store, store.isConnected,
           store.connectedAgent?.lowercased().contains("codex") != true {
            claude.connectionVerified = .connected
        } else if claude.mcpConfigured == .installed {
            claude.connectionVerified = .configured
        } else {
            claude.connectionVerified = .notInstalled
        }
    }

    // MARK: - Codex Checks

    func checkCodex() async {
        codex.cliInstalled = .checking
        codex.mcpAdded = .checking

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

        // 2. Manifold in config.toml?
        let tomlPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml").path
        if let contents = try? String(contentsOfFile: tomlPath, encoding: .utf8),
           contents.contains("[mcp_servers.manifold]") || contents.contains("mcp_servers.manifold") {
            codex.mcpAdded = .installed
        } else {
            codex.mcpAdded = .notInstalled
        }
    }
}
