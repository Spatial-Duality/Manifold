// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
@testable import ManifoldKit

@Suite("ConfigWriter")
struct ConfigWriterTests {
    func makeTempHome() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-config-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    // MARK: - Claude Desktop Merge Tests

    @Test("Fresh install creates config from scratch")
    func freshClaudeInstall() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home)
        try writer.installClaudeDesktop()

        let configFile = home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        let data = try Data(contentsOf: configFile)
        let config = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]
        let manifold = servers["manifold"] as! [String: Any]

        #expect(manifold["command"] as? String == "/usr/bin/manifold-mcp")
        #expect(manifold["args"] as? [String] == ["--agent", "cowork"])
        #expect(servers.count == 1, "Only manifold server should be present")
    }

    @Test("Demo install configures Claude Desktop with demo argument")
    func demoClaudeInstallAddsDemoArgument() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home, demoMode: true)
        try writer.installClaudeDesktop()

        let configFile = home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        let data = try Data(contentsOf: configFile)
        let config = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]
        let manifold = servers["manifold"] as! [String: Any]

        #expect(manifold["args"] as? [String] == ["--agent", "cowork", "--demo"])
    }

    @Test("Install preserves existing MCP servers")
    func preserveExistingServers() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        // Pre-populate with another server
        let configDir = home.appendingPathComponent("Library/Application Support/Claude")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let existing: [String: Any] = [
            "mcpServers": [
                "filesystem": [
                    "command": "npx",
                    "args": ["-y", "@modelcontextprotocol/server-filesystem"]
                ] as [String: Any],
                "github": [
                    "command": "npx",
                    "args": ["-y", "@modelcontextprotocol/server-github"]
                ] as [String: Any]
            ] as [String: Any],
            "theme": "dark"
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existing, options: .prettyPrinted)
        try existingData.write(to: configDir.appendingPathComponent("claude_desktop_config.json"))

        // Install manifold
        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home)
        try writer.installClaudeDesktop()

        // Verify all servers preserved
        let data = try Data(contentsOf: configDir.appendingPathComponent("claude_desktop_config.json"))
        let config = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]

        #expect(servers.count == 3, "filesystem + github + manifold")
        #expect(servers["filesystem"] != nil, "filesystem server preserved")
        #expect(servers["github"] != nil, "github server preserved")
        #expect(servers["manifold"] != nil, "manifold added")
        #expect(config["theme"] as? String == "dark", "Non-server config preserved")
    }

    @Test("Re-install updates manifold without duplicating")
    func reinstallUpdatesManifold() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let configDir = home.appendingPathComponent("Library/Application Support/Claude")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        // First install
        let writer1 = ConfigWriter(binaryPath: "/old/path/manifold-mcp", homeDir: home)
        try writer1.installClaudeDesktop()

        // Second install with new path
        let writer2 = ConfigWriter(binaryPath: "/new/path/manifold-mcp", homeDir: home)
        try writer2.installClaudeDesktop()

        let data = try Data(contentsOf: configDir.appendingPathComponent("claude_desktop_config.json"))
        let config = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]
        let manifold = servers["manifold"] as! [String: Any]

        #expect(servers.count == 1, "No duplicate manifold entry")
        #expect(manifold["command"] as? String == "/new/path/manifold-mcp", "Path updated")
        #expect(manifold["args"] as? [String] == ["--agent", "cowork"], "Cowork agent args preserved")
    }

    @Test("Claude Desktop repair rewrites stale manifold args")
    func claudeDesktopRepairsMissingArgs() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let configDir = home.appendingPathComponent("Library/Application Support/Claude")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let existing: [String: Any] = [
            "mcpServers": [
                "manifold": [
                    "command": "/old/path/manifold-mcp",
                    "args": [],
                ] as [String: Any],
            ] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configDir.appendingPathComponent("claude_desktop_config.json"))

        let writer = ConfigWriter(binaryPath: "/new/path/manifold-mcp", homeDir: home)
        try writer.installClaudeDesktop()

        let result = try Data(contentsOf: configDir.appendingPathComponent("claude_desktop_config.json"))
        let config = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]
        let manifold = servers["manifold"] as! [String: Any]

        #expect(manifold["command"] as? String == "/new/path/manifold-mcp")
        #expect(manifold["args"] as? [String] == ["--agent", "cowork"])
    }

    // MARK: - Codex Config Tests

    @Test("Codex install creates config when .codex directory is missing")
    func codexCreatesConfigWhenMissing() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let configFile = home.appendingPathComponent(".codex/config.toml")
        #expect(!FileManager.default.fileExists(atPath: configFile.path))

        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home)
        try writer.installCodex()

        #expect(FileManager.default.fileExists(atPath: configFile.path))
        let content = try String(contentsOf: configFile, encoding: .utf8)
        #expect(content.contains("[mcp_servers.manifold]"))
        #expect(content.contains("command = \"/usr/bin/manifold-mcp\""))
        #expect(content.contains("args = [\"--agent\", \"codex\"]"))
    }

    @Test("Demo install configures Codex with demo argument")
    func demoCodexInstallAddsDemoArgument() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home, demoMode: true)
        try writer.installCodex()

        let content = try String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8)
        #expect(content.contains("args = [\"--agent\", \"codex\", \"--demo\"]"))
        let block = try #require(ConfigWriter.manifoldCodexServerBlock(in: content))
        #expect(ConfigWriter.manifoldCodexServerArguments(in: block) == ["--agent", "codex", "--demo"])
    }

    @Test("Codex install appends to existing config")
    func codexAppendToExisting() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let codexDir = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        // Pre-populate with existing config
        let existing = """
        model = "claude-sonnet-4-20250514"

        [mcp_servers.filesystem]
        command = "npx"
        args = ["-y", "@modelcontextprotocol/server-filesystem"]
        """
        try existing.write(to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home)
        try writer.installCodex()

        let content = try String(contentsOf: codexDir.appendingPathComponent("config.toml"), encoding: .utf8)
        #expect(content.contains("[mcp_servers.filesystem]"), "Existing server preserved")
        #expect(content.contains("[mcp_servers.manifold]"), "Manifold added")
        #expect(content.contains("args = [\"--agent\", \"codex\"]"), "Codex agent args configured")
        #expect(content.contains("model = \"claude-sonnet-4-20250514\""), "Other config preserved")
    }

    @Test("Codex install updates existing manifold config")
    func codexUpdatesExisting() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let codexDir = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        let existing = """
        [mcp_servers.manifold]
        command = "/old/manifold-mcp"
        args = []
        """
        try existing.write(to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let writer = ConfigWriter(binaryPath: "/new/manifold-mcp", homeDir: home)
        try writer.installCodex()

        let content = try String(contentsOf: codexDir.appendingPathComponent("config.toml"), encoding: .utf8)
        #expect(content.contains("command = \"/new/manifold-mcp\""), "Existing command updated")
        #expect(content.contains("args = [\"--agent\", \"codex\"]"), "Codex agent args updated")
        #expect(content.components(separatedBy: "[mcp_servers.manifold]").count == 2, "Single manifold section remains")
    }

    // MARK: - Claude Code Config Tests

    @Test("Claude Code fresh install creates settings.json")
    func freshClaudeCodeInstall() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home)
        try writer.installClaudeCode()

        let configFile = home.appendingPathComponent(".claude/settings.json")
        let data = try Data(contentsOf: configFile)
        let config = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]
        let manifold = servers["manifold"] as! [String: Any]

        #expect(manifold["command"] as? String == "/usr/bin/manifold-mcp")
        #expect(manifold["args"] as? [String] == ["--agent", "cowork"])
    }

    @Test("Claude Code install preserves existing settings")
    func claudeCodePreservesExisting() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let configDir = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let existing: [String: Any] = [
            "permissions": ["allow": ["Read"]] as [String: Any],
            "mcpServers": [
                "other-server": ["command": "other"] as [String: Any],
            ] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: existing, options: .prettyPrinted)
        try data.write(to: configDir.appendingPathComponent("settings.json"))

        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home)
        try writer.installClaudeCode()

        let result = try Data(contentsOf: configDir.appendingPathComponent("settings.json"))
        let config = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]

        #expect(servers.count == 2, "other-server + manifold")
        #expect(servers["other-server"] != nil)
        #expect(servers["manifold"] != nil)
        #expect(config["permissions"] != nil, "Non-MCP settings preserved")
    }

    @Test("Claude Code install updates existing manifold config")
    func claudeCodeUpdatesExisting() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let configDir = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let existing: [String: Any] = [
            "mcpServers": [
                "manifold": ["command": "/old/path"] as [String: Any],
            ] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configDir.appendingPathComponent("settings.json"))

        let writer = ConfigWriter(binaryPath: "/new/path/manifold-mcp", homeDir: home)
        try writer.installClaudeCode()

        let result = try Data(contentsOf: configDir.appendingPathComponent("settings.json"))
        let config = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]
        let manifold = servers["manifold"] as! [String: Any]
        #expect(manifold["command"] as? String == "/new/path/manifold-mcp", "Existing entry updated")
        #expect(manifold["args"] as? [String] == ["--agent", "cowork"], "Cowork agent args added")
    }

    @Test("Claude Code repair rewrites stale manifold args")
    func claudeCodeRepairsMissingArgs() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let configDir = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let existing: [String: Any] = [
            "mcpServers": [
                "manifold": [
                    "command": "/old/path/manifold-mcp",
                    "args": [],
                ] as [String: Any],
            ] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configDir.appendingPathComponent("settings.json"))

        let writer = ConfigWriter(binaryPath: "/new/path/manifold-mcp", homeDir: home)
        try writer.installClaudeCode()

        let result = try Data(contentsOf: configDir.appendingPathComponent("settings.json"))
        let config = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]
        let manifold = servers["manifold"] as! [String: Any]

        #expect(manifold["command"] as? String == "/new/path/manifold-mcp")
        #expect(manifold["args"] as? [String] == ["--agent", "cowork"])
    }

    @Test("Codex repair rewrites stale manifold args")
    func codexRepairsMissingArgs() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let codexDir = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        let existing = """
        [mcp_servers.manifold]
        command = "/old/manifold-mcp"
        args = []
        """
        try existing.write(to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let writer = ConfigWriter(binaryPath: "/new/manifold-mcp", homeDir: home)
        try writer.installCodex()

        let content = try String(contentsOf: codexDir.appendingPathComponent("config.toml"), encoding: .utf8)
        #expect(content.contains("command = \"/new/manifold-mcp\""))
        #expect(content.contains("args = [\"--agent\", \"codex\"]"))
    }

    @Test("Codex config block parser keeps args array inside manifold section")
    func codexBlockParserKeepsArgsArray() throws {
        let content = """
        model = "gpt-5.5"

        [mcp_servers.manifold]
        command = "/Users/me/bin/manifold-mcp"
        args = ["--agent", "codex"]

        [mcp_servers.other]
        command = "/usr/bin/other"
        args = ["--flag"]
        """

        let block = try #require(ConfigWriter.manifoldCodexServerBlock(in: content))
        #expect(block.contains(#"command = "/Users/me/bin/manifold-mcp""#))
        #expect(block.contains(#"args = ["--agent", "codex"]"#))
        #expect(ConfigWriter.manifoldCodexServerArguments(in: block) == ["--agent", "codex"])
        #expect(!block.contains("[mcp_servers.other]"))
    }

    @Test("Codex args parser supports multiline TOML arrays")
    func codexArgsParserSupportsMultilineArrays() throws {
        let block = """
        [mcp_servers.manifold]
        command = "/Users/me/bin/manifold-mcp"
        args = [
          "--agent",
          "codex",
        ]
        """

        #expect(ConfigWriter.manifoldCodexServerArguments(in: block) == ["--agent", "codex"])
    }

    @Test("Codex repair replaces only manifold section when args array is present")
    func codexRepairPreservesOtherSectionsAfterArgsArray() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let codexDir = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        let existing = """
        model = "gpt-5.5"

        [mcp_servers.manifold]
        command = "/old/manifold-mcp"
        args = ["--agent", "cowork"]

        [mcp_servers.other]
        command = "/usr/bin/other"
        args = ["--flag"]
        """
        try existing.write(to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let writer = ConfigWriter(binaryPath: "/new/manifold-mcp", homeDir: home)
        try writer.installCodex()

        let content = try String(contentsOf: codexDir.appendingPathComponent("config.toml"), encoding: .utf8)
        #expect(content.contains(#"command = "/new/manifold-mcp""#))
        #expect(content.contains(#"args = ["--agent", "codex"]"#))
        #expect(!content.contains(#"command = "/old/manifold-mcp""#))
        #expect(content.contains("[mcp_servers.other]"))
        #expect(content.contains(#"args = ["--flag"]"#))
    }

    // MARK: - installAll

    @Test("installAll configures all targets")
    func installAll() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        // Create .codex directory so Codex install proceeds
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)

        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home)
        try writer.installAll()

        let claudeConfig = home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        let claudeCodeConfig = home.appendingPathComponent(".claude/settings.json")
        let codexConfig = home.appendingPathComponent(".codex/config.toml")
        let claudeRules = home.appendingPathComponent("CLAUDE.md")
        let codexRules = home.appendingPathComponent(".codex/AGENTS.md")

        #expect(FileManager.default.fileExists(atPath: claudeConfig.path))
        #expect(FileManager.default.fileExists(atPath: claudeCodeConfig.path))
        #expect(FileManager.default.fileExists(atPath: codexConfig.path))
        #expect(FileManager.default.fileExists(atPath: claudeRules.path),
                "installAll must write the Claude Code rules file")
        #expect(FileManager.default.fileExists(atPath: codexRules.path),
                "installAll must write the Codex rules file")
    }

    // MARK: - Agent Rules Tests

    @Test("Fresh install creates the user rules file with the manifold rules block")
    func freshClaudeCodeRulesInstall() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let rulesFile = home.appendingPathComponent("CLAUDE.md")
        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home)
        try writer.installClaudeCodeRules()

        let content = try String(contentsOf: rulesFile, encoding: .utf8)
        #expect(content.contains(AgentRulesTemplate.beginMarker))
        #expect(content.contains(AgentRulesTemplate.endMarker))
        #expect(content.contains("Manifold MCP tools (preferred when available)"))
        #expect(content.contains("reuse_prior_context"),
                "Rules must reference the cross-agent hero-shot tool")
    }

    @Test("Fresh install creates the agents rules file with the manifold rules block")
    func freshCodexRulesInstall() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let rulesFile = home.appendingPathComponent(".codex/AGENTS.md")
        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home)
        try writer.installCodexRules()

        let content = try String(contentsOf: rulesFile, encoding: .utf8)
        #expect(content.contains(AgentRulesTemplate.beginMarker))
        #expect(content.contains("Manifold MCP tools (preferred when available)"))
    }

    /// CRITICAL regression test: a user with hand-edited rules must keep
    /// every line of their content above and below the Manifold block, even
    /// after multiple re-installs. Without this, `manifold-mcp --install`
    /// would silently destroy user rules on every upgrade.
    @Test("Re-install preserves user content above and below the manifold block")
    func reinstallPreservesUserContent() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let rulesFile = home.appendingPathComponent("CLAUDE.md")
        let userContent = """
        # My personal Claude rules

        - Be terse.
        - Always run tests before committing.
        - Use Swift Testing, not XCTest.

        ## Project conventions
        - Files live in src/, tests in test/.
        """
        try userContent.write(to: rulesFile, atomically: true, encoding: .utf8)

        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home)
        // Run install three times: pure idempotence + content preservation
        try writer.installClaudeCodeRules()
        try writer.installClaudeCodeRules()
        try writer.installClaudeCodeRules()

        let final = try String(contentsOf: rulesFile, encoding: .utf8)

        // Every line of the user's content must survive
        #expect(final.contains("# My personal Claude rules"))
        #expect(final.contains("- Be terse."))
        #expect(final.contains("- Always run tests before committing."))
        #expect(final.contains("- Use Swift Testing, not XCTest."))
        #expect(final.contains("## Project conventions"))
        #expect(final.contains("- Files live in src/, tests in test/."))

        // And the Manifold block appears exactly once
        let beginCount = final.components(separatedBy: AgentRulesTemplate.beginMarker).count - 1
        #expect(beginCount == 1, "Three re-installs should still leave exactly one manifold block")
    }

    // MARK: - Uninstall (R7)

    @Test("Uninstall removes manifold from Claude Desktop while preserving other servers")
    func uninstallClaudeDesktopPreservesOtherServers() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        // Install + add another server alongside.
        let configDir = home.appendingPathComponent("Library/Application Support/Claude")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let initial: [String: Any] = [
            "mcpServers": [
                "manifold": ["command": "/old/manifold-mcp", "args": ["--agent", "cowork"]] as [String: Any],
                "filesystem": ["command": "npx", "args": ["-y", "fs-server"]] as [String: Any],
                "github": ["command": "npx"] as [String: Any],
            ] as [String: Any],
            "theme": "dark",
        ]
        let initialData = try JSONSerialization.data(withJSONObject: initial, options: [.prettyPrinted, .sortedKeys])
        try initialData.write(to: configDir.appendingPathComponent("claude_desktop_config.json"))

        let writer = ConfigWriter(binaryPath: "/new/manifold-mcp", homeDir: home)
        try writer.uninstallClaudeDesktop()

        let result = try Data(contentsOf: configDir.appendingPathComponent("claude_desktop_config.json"))
        let config = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]

        #expect(servers["manifold"] == nil, "Manifold removed")
        #expect(servers["filesystem"] != nil, "Other servers preserved")
        #expect(servers["github"] != nil, "Other servers preserved")
        #expect(servers.count == 2, "Exactly the two non-manifold servers remain")
        #expect(config["theme"] as? String == "dark", "Non-MCP keys preserved")
    }

    @Test("Uninstall removes the mcpServers key entirely if manifold was the only entry")
    func uninstallClaudeDesktopRemovesEmptyMap() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let configDir = home.appendingPathComponent("Library/Application Support/Claude")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let initial: [String: Any] = [
            "mcpServers": [
                "manifold": ["command": "/old/manifold-mcp"] as [String: Any],
            ] as [String: Any],
            "theme": "dark",
        ]
        let data = try JSONSerialization.data(withJSONObject: initial, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configDir.appendingPathComponent("claude_desktop_config.json"))

        let writer = ConfigWriter(binaryPath: "/new/manifold-mcp", homeDir: home)
        try writer.uninstallClaudeDesktop()

        let result = try Data(contentsOf: configDir.appendingPathComponent("claude_desktop_config.json"))
        let config = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        #expect(config["mcpServers"] == nil, "Empty mcpServers map removed for tidiness")
        #expect(config["theme"] as? String == "dark", "Other top-level keys preserved")
    }

    @Test("Uninstall is idempotent when manifold isn't installed")
    func uninstallClaudeDesktopWhenAbsent() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let configDir = home.appendingPathComponent("Library/Application Support/Claude")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let initial: [String: Any] = [
            "mcpServers": ["other": ["command": "x"] as [String: Any]] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: initial, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configDir.appendingPathComponent("claude_desktop_config.json"))

        let writer = ConfigWriter(binaryPath: "/x", homeDir: home)
        try writer.uninstallClaudeDesktop() // No throw, no-op
        try writer.uninstallClaudeDesktop() // Still no throw

        let result = try Data(contentsOf: configDir.appendingPathComponent("claude_desktop_config.json"))
        let config = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]
        #expect(servers["other"] != nil, "Untouched")
    }

    @Test("Uninstall is a no-op when the config file doesn't exist")
    func uninstallClaudeDesktopNoFile() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }
        let writer = ConfigWriter(binaryPath: "/x", homeDir: home)
        try writer.uninstallClaudeDesktop() // Must not throw
    }

    @Test("Uninstall removes manifold from Claude Code while preserving other settings")
    func uninstallClaudeCodePreservesPermissions() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let configDir = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let initial: [String: Any] = [
            "permissions": ["allow": ["Read", "Bash"]] as [String: Any],
            "mcpServers": [
                "manifold": ["command": "/x"] as [String: Any],
                "other-server": ["command": "y"] as [String: Any],
            ] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: initial, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configDir.appendingPathComponent("settings.json"))

        let writer = ConfigWriter(binaryPath: "/x", homeDir: home)
        try writer.uninstallClaudeCode()

        let result = try Data(contentsOf: configDir.appendingPathComponent("settings.json"))
        let config = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]

        #expect(servers["manifold"] == nil)
        #expect(servers["other-server"] != nil)
        #expect(config["permissions"] != nil, "Non-MCP settings survive uninstall")
    }

    @Test("Uninstall removes manifold block from Codex TOML while preserving other sections")
    func uninstallCodexPreservesOtherSections() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let codexDir = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let initial = """
        model = "gpt-5"

        [mcp_servers.filesystem]
        command = "npx"
        args = ["-y", "fs-server"]

        [mcp_servers.manifold]
        command = "/old/manifold-mcp"
        args = ["--agent", "codex"]

        [mcp_servers.github]
        command = "npx"
        """
        try initial.write(to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let writer = ConfigWriter(binaryPath: "/x", homeDir: home)
        try writer.uninstallCodex()

        let content = try String(contentsOf: codexDir.appendingPathComponent("config.toml"), encoding: .utf8)
        #expect(!content.contains("[mcp_servers.manifold]"), "Manifold block removed")
        #expect(content.contains("[mcp_servers.filesystem]"), "Other server block preserved")
        #expect(content.contains("[mcp_servers.github]"), "Other server block preserved")
        #expect(content.contains("model = \"gpt-5\""), "Top-level Codex config preserved")
    }

    @Test("Uninstall round-trip: install then uninstall returns to baseline")
    func uninstallRoundTrip() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let configDir = home.appendingPathComponent("Library/Application Support/Claude")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let baseline: [String: Any] = [
            "mcpServers": [
                "filesystem": ["command": "npx"] as [String: Any],
            ] as [String: Any],
            "theme": "light",
        ]
        let baselineData = try JSONSerialization.data(withJSONObject: baseline, options: [.prettyPrinted, .sortedKeys])
        try baselineData.write(to: configDir.appendingPathComponent("claude_desktop_config.json"))

        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home)
        try writer.installClaudeDesktop()
        try writer.uninstallClaudeDesktop()

        let result = try Data(contentsOf: configDir.appendingPathComponent("claude_desktop_config.json"))
        let config = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]

        #expect(servers.count == 1, "Only the original filesystem server remains")
        #expect(servers["filesystem"] != nil, "Original server preserved through round-trip")
        #expect(config["theme"] as? String == "light", "Top-level keys preserved through round-trip")
    }

    @Test("Re-install on an unchanged file does not modify mtime")
    func reinstallSkipsWriteWhenContentMatches() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let rulesFile = home.appendingPathComponent("CLAUDE.md")
        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home)
        try writer.installClaudeCodeRules()

        let mtime1 = try FileManager.default.attributesOfItem(atPath: rulesFile.path)[.modificationDate] as? Date
        // Sleep briefly so we'd notice an mtime change
        Thread.sleep(forTimeInterval: 0.05)
        try writer.installClaudeCodeRules()
        let mtime2 = try FileManager.default.attributesOfItem(atPath: rulesFile.path)[.modificationDate] as? Date

        #expect(mtime1 == mtime2,
                "Re-running install on an up-to-date file must not touch mtime — scripted re-install should be a no-op")
    }
}
