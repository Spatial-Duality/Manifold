import Foundation

/// Writes Manifold MCP server config to Claude Desktop and Codex config files.
/// Merges with existing config — never overwrites other servers.
public struct ConfigWriter {
    private let binaryPath: String

    public init(binaryPath: String) {
        self.binaryPath = binaryPath
    }

    /// Install config for both Claude Desktop and Codex.
    public func installAll() throws {
        try installClaudeDesktop()
        try installCodex()
    }

    /// Write to ~/Library/Application Support/Claude/claude_desktop_config.json
    public func installClaudeDesktop() throws {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude")
        let configFile = configDir.appendingPathComponent("claude_desktop_config.json")

        var config: [String: Any] = [:]

        // Read existing config if present
        if let data = try? Data(contentsOf: configFile),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = existing
        }

        // Merge manifold server entry
        var mcpServers = config["mcpServers"] as? [String: Any] ?? [:]
        mcpServers["manifold"] = [
            "command": binaryPath,
            "args": [] as [String]
        ] as [String: Any]
        config["mcpServers"] = mcpServers

        // Write back
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configFile, options: .atomic)

        print("Wrote Claude Desktop config: \(configFile.path)")
    }

    /// Write to ~/.codex/config.toml
    public func installCodex() throws {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
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

        // Check if manifold is already configured
        if content.contains("[mcp_servers.manifold]") || content.contains("[mcp.manifold]") {
            print("Manifold already configured in Codex config. Skipping.")
            return
        }

        // Append manifold MCP server config
        if !content.hasSuffix("\n") { content += "\n" }
        content += """

        [mcp_servers.manifold]
        command = "\(binaryPath)"
        args = []

        """

        try content.write(to: configFile, atomically: true, encoding: .utf8)
        print("Wrote Codex config: \(configFile.path)")
    }
}
