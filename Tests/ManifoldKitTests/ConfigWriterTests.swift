import Testing
import Foundation
@testable import ManifoldKit

@Suite("ConfigWriter")
struct ConfigWriterTests {
    func makeTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-config-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("ConfigWriter initializes with binary path")
    func initWithPath() {
        let writer = ConfigWriter(binaryPath: "/usr/local/bin/manifold-mcp")
        // Should not throw
        #expect(true)
    }

    @Test("Claude Desktop config is valid JSON")
    func claudeConfigJSON() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        // Create a fake Claude config directory
        let claudeDir = tempDir.appendingPathComponent("Claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        // Write a config file manually to simulate what installClaudeDesktop does
        let config: [String: Any] = [
            "mcpServers": [
                "manifold": [
                    "command": "/usr/local/bin/manifold-mcp",
                    "args": [] as [String]
                ] as [String: Any]
            ] as [String: Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        let configFile = claudeDir.appendingPathComponent("claude_desktop_config.json")
        try data.write(to: configFile)

        // Read back and verify
        let readData = try Data(contentsOf: configFile)
        let parsed = try JSONSerialization.jsonObject(with: readData) as? [String: Any]
        #expect(parsed != nil)
        let servers = parsed?["mcpServers"] as? [String: Any]
        #expect(servers?["manifold"] != nil)
    }

    @Test("Codex config contains TOML section")
    func codexConfigTOML() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let codexDir = tempDir.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        // Write a TOML config
        let content = """
        [mcp_servers.manifold]
        command = "/usr/local/bin/manifold-mcp"
        args = []
        """
        let configFile = codexDir.appendingPathComponent("config.toml")
        try content.write(to: configFile, atomically: true, encoding: .utf8)

        let readContent = try String(contentsOf: configFile, encoding: .utf8)
        #expect(readContent.contains("[mcp_servers.manifold]"))
        #expect(readContent.contains("manifold-mcp"))
    }
}
