// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import ManifoldKit
import ManifoldXPC

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "mcp")

private actor MCPConnectionState {
    private var connectionID: String?
    private var connectionError: String?
    private var initializeParams: [String: Any] = [:]

    func set(_ connectionID: String, initializeParams: [String: Any]? = nil) {
        self.connectionID = connectionID
        connectionError = nil
        if let initializeParams {
            self.initializeParams = initializeParams
        }
    }

    func fail(_ error: Error) {
        connectionID = nil
        connectionError = error.localizedDescription
    }

    func get() -> String? {
        connectionID
    }

    func params() -> JSONDict {
        JSONDict(initializeParams)
    }

    func unavailableMessage() -> String {
        if let connectionError, !connectionError.isEmpty {
            return "Runtime connection not initialized: \(connectionError). Make sure the Manifold app/runtime helper is running, then retry the Manifold tool call."
        }
        return "Runtime connection not initialized. Make sure the Manifold app/runtime helper is running, then retry the Manifold tool call."
    }
}

@main
/// Launches the stdio MCP adapter that forwards governed tool calls into the local runtime.
struct ManifoldMCPServer {
    static func main() async throws {
        let version = "0.4.1"
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
        let demoRuntime = DemoMCPRuntime.isEnabled() ? DemoMCPRuntime(targetApp: targetApp) : nil

        @Sendable func connectRuntime(initializeParams paramsOverride: JSONDict? = nil) async -> String? {
            let params: JSONDict
            if let paramsOverride {
                params = paramsOverride
            } else {
                params = await connectionState.params()
            }
            do {
                let connectionID = try await xpc.connectAgent(
                    agent: targetApp.rawValue,
                    clientName: "manifold-mcp",
                    clientVersion: version,
                    initializeParams: params.value
                )
                await connectionState.set(connectionID, initializeParams: params.value)
                return connectionID
            } catch {
                await connectionState.fail(error)
                logger.error("Failed to connect MCP client to runtime: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }

        // Create MCP server
        let server = MCPServer(name: "manifold", version: version)
        await server.registerInitializeHandler { params in
            guard demoRuntime == nil else { return }
            _ = await connectRuntime(initializeParams: params)
        }

        // Register tools
        await server.registerTools(ToolDefinitions.allTools()) { name, arguments in
            if let demoRuntime {
                return JSONDict(demoRuntime.callTool(name: name, arguments: arguments.value))
            }
            let existingConnectionID = await connectionState.get()
            let runtimeConnectionID: String?
            if let existingConnectionID {
                runtimeConnectionID = existingConnectionID
            } else {
                runtimeConnectionID = await connectRuntime()
            }
            guard let connectionID = runtimeConnectionID else {
                return JSONDict(["content": [["type": "text", "text": await connectionState.unavailableMessage()]], "isError": true])
            }
            do {
                var result = try await xpc.callTool(connectionID: connectionID, toolName: name, arguments: arguments.value)
                if isInactiveRuntimeResult(result),
                   let reconnectedID = await connectRuntime() {
                    result = try await xpc.callTool(connectionID: reconnectedID, toolName: name, arguments: arguments.value)
                }
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
            MCPResource(name: "Provenance Ledger", uri: "manifold://ledger", description: "Hash-chain ledger verification and recent entries"),
            MCPResource(name: "Owned Memory", uri: "manifold://memory", description: "Memory available to the current session scope"),
            MCPResource(name: "Saved Skills", uri: "manifold://skills", description: "Saved skill manifests"),
            MCPResource(name: "Exec Status", uri: "manifold://exec/status", description: "ManifoldExec sandbox status"),
            MCPResource(name: "Knowledge Graph", uri: "manifold://graph", description: "Scoped graph query status"),
        ]) { uri in
            if let demoRuntime, let text = demoRuntime.resourceText(uri: uri) {
                return text
            }
            let existingConnectionID = await connectionState.get()
            let runtimeConnectionID: String?
            if let existingConnectionID {
                runtimeConnectionID = existingConnectionID
            } else {
                runtimeConnectionID = await connectRuntime()
            }
            guard let connectionID = runtimeConnectionID else {
                return await connectionState.unavailableMessage()
            }
            func toolText(_ name: String, arguments: [String: Any] = [:]) async -> String {
                do {
                    var result = try await xpc.callTool(connectionID: connectionID, toolName: name, arguments: arguments)
                    if isInactiveRuntimeResult(result),
                       let reconnectedID = await connectRuntime() {
                        result = try await xpc.callTool(connectionID: reconnectedID, toolName: name, arguments: arguments)
                    }
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
            case "manifold://ledger":
                return await toolText("verify_ledger_entry")
            case "manifold://memory":
                return await toolText("recall_memory", arguments: ["limit": 10])
            case "manifold://skills":
                return await toolText("list_skills", arguments: ["limit": 20])
            case "manifold://exec/status":
                return await toolText("run_code", arguments: ["code": "", "language": "status"])
            case "manifold://graph":
                return await toolText("query_graph", arguments: ["query": "", "limit": 10])
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

    static func isInactiveRuntimeResult(_ result: [String: Any]) -> Bool {
        guard result["isError"] as? Bool == true else { return false }
        return textContent(from: result).contains("No active runtime connection")
    }
}
