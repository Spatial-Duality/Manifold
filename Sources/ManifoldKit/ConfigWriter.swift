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
    private let demoMode: Bool

    /// Returns the CLI arguments that identify the target agent to `manifold-mcp`.
    public static func expectedArguments(for agent: TargetApp, demoMode: Bool = false) -> [String] {
        var arguments = ["--agent", agent.rawValue]
        if demoMode {
            arguments.append("--demo")
        }
        return arguments
    }

    /// Returns the Manifold MCP table from Codex TOML config, preserving TOML
    /// arrays such as `args = ["--agent", "codex"]` inside the table body.
    public static func manifoldCodexServerBlock(in content: String) -> String? {
        guard let range = codexManifoldServerBlockRange(in: content) else { return nil }
        return String(content[range])
    }

    /// Returns the configured `args` array from a Codex Manifold MCP table.
    public static func manifoldCodexServerArguments(in block: String) -> [String]? {
        let argsPattern = #"args\s*=\s*\[(.*?)\]"#
        guard let regex = try? NSRegularExpression(pattern: argsPattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(block.startIndex..<block.endIndex, in: block)
        guard let match = regex.firstMatch(in: block, options: [], range: range),
              let argsRange = Range(match.range(at: 1), in: block) else {
            return nil
        }

        let argsBody = String(block[argsRange])
        guard let stringRegex = try? NSRegularExpression(pattern: #""([^"]+)""#, options: []) else {
            return nil
        }
        let argsBodyRange = NSRange(argsBody.startIndex..<argsBody.endIndex, in: argsBody)
        return stringRegex.matches(in: argsBody, options: [], range: argsBodyRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: argsBody) else { return nil }
            return String(argsBody[range])
        }
    }

    /// Creates a config writer rooted at the current user's home directory.
    public init(binaryPath: String) {
        self.init(binaryPath: binaryPath, demoMode: false)
    }

    /// Creates a config writer rooted at the current user's home directory.
    public init(binaryPath: String, demoMode: Bool) {
        self.binaryPath = binaryPath
        self.homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.demoMode = demoMode
    }

    /// Creates a config writer with a custom home directory for tests or controlled installs.
    public init(binaryPath: String, homeDir: URL) {
        self.init(binaryPath: binaryPath, homeDir: homeDir, demoMode: false)
    }

    /// Creates a config writer with a custom home directory for tests or controlled installs.
    public init(binaryPath: String, homeDir: URL, demoMode: Bool) {
        self.binaryPath = binaryPath
        self.homeDir = homeDir
        self.demoMode = demoMode
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
    /// Currently writes the supported user and agents rules files.
    ///
    /// Claude Desktop has no Markdown rules file (its system prompt is
    /// configured per-Project inside the app), so it is intentionally
    /// skipped here.
    public func installAgentRules() throws {
        try installClaudeCodeRules()
        try installCodexRules()
    }

    /// Writes the Manifold rules block to the supported user rules file.
    /// Creates the file if absent; merges with existing user content otherwise.
    public func installClaudeCodeRules() throws {
        let rulesFile = homeDir.appendingPathComponent("CLAUDE.md")
        try writeManifoldRules(to: rulesFile)
    }

    /// Writes the Manifold rules block to the supported agents rules file.
    /// Creates the directory and file if absent; merges with existing user
    /// content otherwise.
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

    // MARK: - Uninstall

    /// Removes the Manifold MCP entry from Claude Desktop's config while
    /// preserving every other MCP server the user has configured. Idempotent:
    /// safe to call when Manifold isn't installed (no-op).
    public func uninstallClaudeDesktop() throws {
        let configFile = homeDir
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        try removeManifoldFromJSONConfig(at: configFile)
    }

    /// Removes the Manifold MCP entry from Claude Code's config while
    /// preserving every other MCP server. Idempotent.
    public func uninstallClaudeCode() throws {
        let configFile = homeDir.appendingPathComponent(".claude/settings.json")
        try removeManifoldFromJSONConfig(at: configFile)
    }

    /// Removes the Manifold MCP entry from Codex's TOML config while
    /// preserving every other server block in the file. Idempotent.
    public func uninstallCodex() throws {
        let configFile = homeDir.appendingPathComponent(".codex/config.toml")
        try removeManifoldFromCodexConfig(at: configFile)
    }

    /// Surgically removes the `manifold` server entry from a JSON config
    /// file's `mcpServers` map, preserving every other entry. If the
    /// resulting `mcpServers` map is empty the key is removed too,
    /// keeping the file tidy. The file itself is preserved with any
    /// non-MCP keys intact.
    private func removeManifoldFromJSONConfig(at file: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path) else {
            // Nothing to remove. Idempotent.
            return
        }
        guard let data = try? Data(contentsOf: file),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Don't touch a file we can't parse — refuse rather than risk
            // corrupting a hand-crafted config.
            logger.warning("Skipping uninstall: could not parse \(file.path, privacy: .public)")
            return
        }
        guard var mcpServers = config["mcpServers"] as? [String: Any],
              mcpServers["manifold"] != nil else {
            // Manifold wasn't there. Idempotent.
            return
        }
        mcpServers.removeValue(forKey: "manifold")
        if mcpServers.isEmpty {
            config.removeValue(forKey: "mcpServers")
        } else {
            config["mcpServers"] = mcpServers
        }
        let outData = try JSONSerialization.data(
            withJSONObject: config,
            options: [.prettyPrinted, .sortedKeys]
        )
        try outData.write(to: file, options: .atomic)
        logger.info("Removed Manifold from \(file.path, privacy: .public)")
    }

    /// Surgically removes the `[mcp_servers.manifold]` (or legacy
    /// `[mcp.manifold]`) block from a Codex TOML file, leaving every
    /// other section intact. The file itself is preserved.
    private func removeManifoldFromCodexConfig(at file: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return
        }
        guard let original = try? String(contentsOf: file, encoding: .utf8) else {
            logger.warning("Skipping uninstall: could not read \(file.path, privacy: .public)")
            return
        }
        var updated = original
        if let range = Self.codexManifoldServerBlockRange(in: updated) {
            updated.removeSubrange(range)
        }
        // Collapse triple-or-more newlines back to a single blank line
        // so the remaining file stays readable.
        if let collapse = try? NSRegularExpression(pattern: #"\n{3,}"#) {
            let range = NSRange(updated.startIndex..<updated.endIndex, in: updated)
            updated = collapse.stringByReplacingMatches(
                in: updated,
                options: [],
                range: range,
                withTemplate: "\n\n"
            )
        }
        guard updated != original else { return }
        try updated.write(to: file, atomically: true, encoding: .utf8)
        logger.info("Removed Manifold from \(file.path, privacy: .public)")
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
            "args": Self.expectedArguments(for: agent, demoMode: demoMode),
        ]
    }

    private func upsertCodexServerConfig(_ content: String, agent: TargetApp) -> String {
        let block = codexMCPServerBlock(agent: agent)
        var updated = content
        if let range = Self.codexManifoldServerBlockRange(in: updated) {
            updated.replaceSubrange(range, with: block + "\n")
        } else {
            if !updated.isEmpty, !updated.hasSuffix("\n") {
                updated += "\n"
            }
            updated += "\n" + block + "\n"
        }

        return updated
    }

    private func codexMCPServerBlock(agent: TargetApp) -> String {
        let args = Self.expectedArguments(for: agent, demoMode: demoMode)
            .map { "\"\($0)\"" }
            .joined(separator: ", ")
        return """
        [mcp_servers.manifold]
        command = "\(binaryPath)"
        args = [\(args)]
        """
    }

    private static func codexManifoldServerBlockRange(in content: String) -> Range<String.Index>? {
        var lineStart = content.startIndex
        while lineStart < content.endIndex {
            let lineEnd = content[lineStart...].firstIndex(of: "\n") ?? content.endIndex
            let line = content[lineStart..<lineEnd]
                .trimmingCharacters(in: .whitespaces)

            if isCodexManifoldHeader(line) {
                var blockEnd = lineEnd < content.endIndex ? content.index(after: lineEnd) : content.endIndex
                var nextLineStart = blockEnd
                while nextLineStart < content.endIndex {
                    let nextLineEnd = content[nextLineStart...].firstIndex(of: "\n") ?? content.endIndex
                    let nextLine = content[nextLineStart..<nextLineEnd]
                        .trimmingCharacters(in: .whitespaces)
                    if tomlHeaderName(in: nextLine) != nil {
                        break
                    }
                    blockEnd = nextLineEnd < content.endIndex ? content.index(after: nextLineEnd) : content.endIndex
                    nextLineStart = blockEnd
                }
                return lineStart..<blockEnd
            }

            lineStart = lineEnd < content.endIndex ? content.index(after: lineEnd) : content.endIndex
        }
        return nil
    }

    private static func isCodexManifoldHeader(_ line: String) -> Bool {
        let name = tomlHeaderName(in: line)
        return name == "mcp_servers.manifold" || name == "mcp.manifold"
    }

    private static func tomlHeaderName(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") else { return nil }

        let nameStart: String.Index
        let nameEnd: String.Index
        let tailStart: String.Index
        if trimmed.hasPrefix("[[") {
            guard let closeRange = trimmed.range(of: "]]") else { return nil }
            nameStart = trimmed.index(trimmed.startIndex, offsetBy: 2)
            nameEnd = closeRange.lowerBound
            tailStart = closeRange.upperBound
        } else {
            guard let closeIndex = trimmed.firstIndex(of: "]") else { return nil }
            nameStart = trimmed.index(after: trimmed.startIndex)
            nameEnd = closeIndex
            tailStart = trimmed.index(after: closeIndex)
        }

        let tail = trimmed[tailStart...].trimmingCharacters(in: .whitespaces)
        guard tail.isEmpty || tail.hasPrefix("#") else { return nil }
        return trimmed[nameStart..<nameEnd].trimmingCharacters(in: .whitespaces)
    }
}
