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
        #expect(servers.count == 1, "Only manifold server should be present")
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
    }

    // MARK: - Codex Config Tests

    @Test("Codex install skipped when .codex directory missing")
    func codexSkipWhenMissing() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home)
        try writer.installCodex()  // Should not throw

        let configFile = home.appendingPathComponent(".codex/config.toml")
        #expect(!FileManager.default.fileExists(atPath: configFile.path))
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
        #expect(content.contains("model = \"claude-sonnet-4-20250514\""), "Other config preserved")
    }

    @Test("Codex install skips when manifold already configured")
    func codexSkipDuplicate() throws {
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
        #expect(content == existing, "Config unchanged when manifold already present")
    }

    // MARK: - installAll

    @Test("installAll configures both targets")
    func installAll() throws {
        let home = try makeTempHome()
        defer { cleanup(home) }

        // Create .codex directory so Codex install proceeds
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)

        let writer = ConfigWriter(binaryPath: "/usr/bin/manifold-mcp", homeDir: home)
        try writer.installAll()

        let claudeConfig = home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        let codexConfig = home.appendingPathComponent(".codex/config.toml")

        #expect(FileManager.default.fileExists(atPath: claudeConfig.path))
        #expect(FileManager.default.fileExists(atPath: codexConfig.path))
    }
}
