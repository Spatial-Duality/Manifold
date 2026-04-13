// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import ManifoldKit
import ManifoldXPC

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "mcp")

private actor MCPConnectionState {
    private var connectionID: String?

    func set(_ connectionID: String) {
        self.connectionID = connectionID
    }

    func get() -> String? {
        connectionID
    }
}

@main
struct ManifoldMCPServer {
    static func main() async throws {
        let version = "0.4.0"
        let targetApp = parsedTargetApp(from: CommandLine.arguments)

        // Handle --version flag
        if CommandLine.arguments.contains("--version") {
            print("manifold-mcp \(version)")
            return
        }

        // Handle --install flag
        if CommandLine.arguments.contains("--install") {
            let binaryPath = CommandLine.arguments[0]
            let writer = ConfigWriter(binaryPath: binaryPath)
            try writer.installAll()
            fputs("Manifold MCP server installed. Restart Claude/Codex clients to connect.\n", stderr)
            logger.info("MCP server installed via --install flag")
            return
        }

        let xpc = ManifoldXPCClient()
        let connectionState = MCPConnectionState()

        // Create MCP server
        let server = MCPServer(name: "manifold", version: version)
        await server.registerInitializeHandler { params in
            do {
                let connectionID = try await xpc.connectAgent(
                    agent: targetApp.rawValue,
                    clientName: "manifold-mcp",
                    clientVersion: version,
                    initializeParams: params.value
                )
                await connectionState.set(connectionID)
            } catch {
                logger.error("Failed to connect MCP client to runtime: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Register tools
        await server.registerTools(ToolDefinitions.allTools()) { name, arguments in
            guard let connectionID = await connectionState.get() else {
                return JSONDict(["content": [["type": "text", "text": "Runtime connection not initialized"]], "isError": true])
            }
            do {
                let result = try await xpc.callTool(connectionID: connectionID, toolName: name, arguments: arguments.value)
                return JSONDict(result)
            } catch {
                return JSONDict(["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
            }
        }

        // Register resources
        await server.registerResources([
            MCPResource(name: "Manifold Status", uri: "manifold://status", description: "Current access status"),
            MCPResource(name: "Approved Files", uri: "manifold://files", description: "List of files in workspace"),
            MCPResource(name: "Shared Emails", uri: "manifold://emails", description: "Emails available to agent"),
            MCPResource(name: "Session History", uri: "manifold://sessions", description: "Past session summaries"),
        ]) { uri in
            guard let connectionID = await connectionState.get() else {
                return "Runtime connection not initialized."
            }
            func toolText(_ name: String, arguments: [String: Any] = [:]) async -> String {
                do {
                    let result = try await xpc.callTool(connectionID: connectionID, toolName: name, arguments: arguments)
                    return textContent(from: result)
                } catch {
                    return error.localizedDescription
                }
            }
            switch uri {
            case "manifold://status":
                return await toolText("get_status")
            case "manifold://files":
                return await toolText("list_files")
            case "manifold://emails":
                return await toolText("list_emails")
            case "manifold://sessions":
                return await toolText("list_sessions", arguments: ["limit": "10"])
            default:
                return ""
            }
        }

        // Start stdio transport (blocks until stdin closes)
        do {
            try await server.start()
        } catch {
            if let connectionID = await connectionState.get() {
                xpc.disconnectAgent(connectionID: connectionID)
            }
            throw error
        }
        if let connectionID = await connectionState.get() {
            xpc.disconnectAgent(connectionID: connectionID)
        }
    }

    static func parsedTargetApp(from arguments: [String]) -> TargetApp {
        guard let flagIndex = arguments.firstIndex(of: "--agent"), arguments.indices.contains(flagIndex + 1) else {
            return .cowork
        }
        return TargetApp(rawValue: arguments[flagIndex + 1]) ?? .cowork
    }

    static func textContent(from result: [String: Any]) -> String {
        guard let content = result["content"] as? [[String: Any]] else { return "" }
        return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }
}
