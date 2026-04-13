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

    public static func expectedArguments(for agent: TargetApp) -> [String] {
        ["--agent", agent.rawValue]
    }

    public init(binaryPath: String) {
        self.binaryPath = binaryPath
        self.homeDir = FileManager.default.homeDirectoryForCurrentUser
    }

    /// Test-only initializer with custom home directory.
    public init(binaryPath: String, homeDir: URL) {
        self.binaryPath = binaryPath
        self.homeDir = homeDir
    }

    /// Install config for Claude Desktop, Claude Code, and Codex.
    public func installAll() throws {
        try installClaudeDesktop()
        try installClaudeCode()
        try installCodex()
    }

    /// Write to ~/Library/Application Support/Claude/claude_desktop_config.json
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

    /// Write to ~/.claude/settings.json (Claude Code CLI / IDE extensions)
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

    /// Write to ~/.codex/config.toml
    public func installCodex() throws {
        let configDir = homeDir.appendingPathComponent(".codex")
        let configFile = configDir.appendingPathComponent("config.toml")

        // Only install if Codex directory exists
        guard FileManager.default.fileExists(atPath: configDir.path) else {
            print("Codex not found (~/.codex/ does not exist). Skipping.")
            return
        }

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
