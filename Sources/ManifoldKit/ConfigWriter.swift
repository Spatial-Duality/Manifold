// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "ConfigWriter")

/// Writes Manifold MCP server config to Claude Desktop and Codex config files.
/// Merges with existing config — never overwrites other servers.
public struct ConfigWriter {
    private let binaryPath: String
    private let homeDir: URL

    /// Returns the CLI arguments that identify the target agent to `manifold-mcp`.
    public static func expectedArguments(for agent: TargetApp) -> [String] {
        ["--agent", agent.rawValue]
    }

    /// Creates a config writer rooted at the current user's home directory.
    public init(binaryPath: String) {
        self.binaryPath = binaryPath
        self.homeDir = FileManager.default.homeDirectoryForCurrentUser
    }

    /// Creates a config writer with a custom home directory for tests or controlled installs.
    public init(binaryPath: String, homeDir: URL) {
        self.binaryPath = binaryPath
        self.homeDir = homeDir
    }

    /// Installs or updates Manifold config for Claude Desktop, Claude Code, and Codex,
    /// and refreshes the per-tool agent rules files so AI tools prefer
    /// `manifold.*` tools when working in approved sources.
    public func installAll() throws {
        try installClaudeDesktop()
        try installClaudeCode()
        try installCodex()
        try installAgentRules()
    }

    /// Inserts or refreshes the Manifold-managed Markdown block in each
    /// supported AI tool's rules file. Idempotent: re-running replaces only
    /// the Manifold section and preserves user content above and below.
    ///
    /// Currently writes:
    /// - `~/CLAUDE.md` (Claude Code's user-global rules file)
    /// - `~/.codex/AGENTS.md` (Codex CLI's user-global agents instructions)
    ///
    /// Claude Desktop has no Markdown rules file (its system prompt is
    /// configured per-Project inside the app), so it is intentionally
    /// skipped here.
    public func installAgentRules() throws {
        try installClaudeCodeRules()
        try installCodexRules()
    }

    /// Writes the Manifold rules block to `~/CLAUDE.md`. Creates the file if
    /// absent; merges with existing user content otherwise.
    public func installClaudeCodeRules() throws {
        let rulesFile = homeDir.appendingPathComponent("CLAUDE.md")
        try writeManifoldRules(to: rulesFile)
    }

    /// Writes the Manifold rules block to `~/.codex/AGENTS.md`. Creates the
    /// directory and file if absent; merges with existing user content
    /// otherwise.
    public func installCodexRules() throws {
        let rulesDir = homeDir.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        let rulesFile = rulesDir.appendingPathComponent("AGENTS.md")
        try writeManifoldRules(to: rulesFile)
    }

    private func writeManifoldRules(to file: URL) throws {
        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let updated = AgentRulesTemplate.upsert(into: existing)
        guard updated != existing else {
            // Either no change needed (already up to date) or corrupted markers
            // (AgentRulesTemplate.upsert logs a warning and returns existing).
            // Either way, no write — preserves "no spurious file modifications"
            // contract that re-running --install is safe to script.
            logger.info("Manifold rules already up to date or file has corrupted markers: \(file.path, privacy: .public)")
            return
        }
        try updated.write(to: file, atomically: true, encoding: .utf8)
        logger.info("Wrote Manifold rules block: \(file.path, privacy: .public)")
    }

    /// Writes the Manifold MCP entry to Claude Desktop's JSON config.
    public func installClaudeDesktop() throws {
        let configDir = homeDir.appendingPathComponent("Library/Application Support/Claude")
        let configFile = configDir.appendingPathComponent("claude_desktop_config.json")

        var config: [String: Any] = [:]

        // Read existing config if present
        if let data = try? Data(contentsOf: configFile),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = existing
        }

        // Merge manifold server entry
        var mcpServers = config["mcpServers"] as? [String: Any] ?? [:]
        mcpServers["manifold"] = jsonMCPServerConfig(agent: .cowork)
        config["mcpServers"] = mcpServers

        // Write back
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configFile, options: .atomic)

        logger.info("Wrote Claude Desktop config: \(configFile.path)")
    }

    /// Writes the Manifold MCP entry to Claude Code's JSON config.
    public func installClaudeCode() throws {
        let configDir = homeDir.appendingPathComponent(".claude")
        let configFile = configDir.appendingPathComponent("settings.json")

        var config: [String: Any] = [:]

        // Read existing config if present
        if let data = try? Data(contentsOf: configFile),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = existing
        }

        // Merge manifold MCP server entry
        var mcpServers = config["mcpServers"] as? [String: Any] ?? [:]
        mcpServers["manifold"] = jsonMCPServerConfig(agent: .cowork)
        config["mcpServers"] = mcpServers

        // Write back
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configFile, options: .atomic)

        logger.info("Wrote Claude Code config: \(configFile.path)")
    }

    /// Writes the Manifold MCP entry to Codex's TOML config.
    public func installCodex() throws {
        let configDir = homeDir.appendingPathComponent(".codex")
        let configFile = configDir.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        var content = ""
        if let existing = try? String(contentsOf: configFile, encoding: .utf8) {
            content = existing
        }

        content = upsertCodexServerConfig(content, agent: .codex)

        try content.write(to: configFile, atomically: true, encoding: .utf8)
        logger.info("Wrote Codex config: \(configFile.path)")
    }

    private func jsonMCPServerConfig(agent: TargetApp) -> [String: Any] {
        [
            "command": binaryPath,
            "args": Self.expectedArguments(for: agent),
        ]
    }

    private func upsertCodexServerConfig(_ content: String, agent: TargetApp) -> String {
        let block = codexMCPServerBlock(agent: agent)
        let patterns = [
            #"\n?\[mcp_servers\.manifold\]\n(?:[^\[]*(?:\n|$))*"#,
            #"\n?\[mcp\.manifold\]\n(?:[^\[]*(?:\n|$))*"#,
        ]

        var updated = content
        for pattern in patterns {
            let range = NSRange(updated.startIndex..<updated.endIndex, in: updated)
            let regex = try? NSRegularExpression(pattern: pattern, options: [])
            updated = regex?.stringByReplacingMatches(
                in: updated,
                options: [],
                range: range,
                withTemplate: "\n" + block + "\n"
            ) ?? updated
        }

        if updated == content {
            if !updated.isEmpty, !updated.hasSuffix("\n") {
                updated += "\n"
            }
            updated += "\n" + block + "\n"
        }

        return updated
    }

    private func codexMCPServerBlock(agent: TargetApp) -> String {
        """
        [mcp_servers.manifold]
        command = "\(binaryPath)"
        args = ["\(Self.expectedArguments(for: agent)[0])", "\(Self.expectedArguments(for: agent)[1])"]
        """
    }
}
