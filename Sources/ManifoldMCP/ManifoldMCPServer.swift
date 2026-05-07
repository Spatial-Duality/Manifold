// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import ManifoldKit
import ManifoldXPC

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "mcp")

private extension JSONEncoder {
    static var manifoldFailureSpool: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

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

    func updateInitializeParams(_ initializeParams: [String: Any]) {
        self.initializeParams = initializeParams
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
        let diagnostics = DiagnosticsRecorder(process: .agent)
        let failureRecorder = makeFailureEventRecorder()

        @Sendable func recordFailure(_ event: MCPFailureEvent) async {
            await Self.recordFailureEvent(event, recorder: failureRecorder, diagnostics: diagnostics)
        }

        @Sendable func connectRuntime(
            requestID: ManifoldRequestID = ManifoldRequestID(),
            toolName: String? = nil,
            initializeParams paramsOverride: JSONDict? = nil
        ) async -> String? {
            let params: JSONDict
            if let paramsOverride {
                params = paramsOverride
            } else {
                params = await connectionState.params()
            }
            do {
                let connectionID = try await xpc.connectAgent(
                    requestID: requestID.rawValue,
                    agent: targetApp.rawValue,
                    clientName: "manifold-mcp",
                    clientVersion: version,
                    initializeParams: params.value
                )
                await connectionState.set(connectionID, initializeParams: params.value)
                return connectionID
            } catch {
                await connectionState.fail(error)
                await recordFailure(MCPFailureEvent(
                    requestID: requestID.rawValue,
                    agent: targetApp.rawValue,
                    clientName: "manifold-mcp",
                    toolName: toolName,
                    boundary: .xpcClient,
                    phase: .connect,
                    classification: .xpcRuntimeUnavailable,
                    isRetryable: true,
                    redactedMessage: error.localizedDescription
                ))
                logger.error("Failed to connect MCP client to runtime: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }

        // Create MCP server
        let server = MCPServer(name: "manifold", version: version)
        await server.registerInitializeHandler { params in
            guard demoRuntime == nil else { return }
            await connectionState.updateInitializeParams(params.value)
        }

        // Register tools
        await server.registerTools(ToolDefinitions.allTools()) { name, arguments, requestID in
            if let demoRuntime {
                return JSONDict(annotateResult(demoRuntime.callTool(name: name, arguments: arguments.value), requestID: requestID))
            }
            if name == "manifold_health" {
                let existingConnectionID = await connectionState.get()
                let connectionID: String?
                if let existingConnectionID {
                    connectionID = existingConnectionID
                } else {
                    connectionID = await connectRuntime(requestID: requestID, toolName: name)
                }
                return JSONDict(Self.healthResult(
                    requestID: requestID,
                    version: version,
                    targetApp: targetApp,
                    connectionID: connectionID,
                    failureRecorderAvailable: failureRecorder != nil,
                    env: ProcessInfo.processInfo.environment
                ))
            }
            let existingConnectionID = await connectionState.get()
            let runtimeConnectionID: String?
            if let existingConnectionID {
                runtimeConnectionID = existingConnectionID
            } else {
                runtimeConnectionID = await connectRuntime(requestID: requestID, toolName: name)
            }
            guard let connectionID = runtimeConnectionID else {
                return JSONDict(annotatedError(
                    await connectionState.unavailableMessage(),
                    requestID: requestID,
                    boundary: .xpcClient,
                    phase: .connect,
                    classification: .xpcRuntimeUnavailable,
                    retryable: true
                ))
            }
            do {
                var result = try await xpc.callTool(
                    connectionID: connectionID,
                    requestID: requestID.rawValue,
                    toolName: name,
                    arguments: arguments.value
                )
                if isInactiveRuntimeResult(result),
                   let reconnectedID = await connectRuntime(requestID: requestID, toolName: name) {
                    result = try await xpc.callTool(
                        connectionID: reconnectedID,
                        requestID: requestID.rawValue,
                        toolName: name,
                        arguments: arguments.value
                    )
                }
                return JSONDict(annotateResult(result, requestID: requestID))
            } catch {
                let classification: MCPFailureClassification
                if let xpcError = error as? ManifoldXPCError, case .timeout = xpcError {
                    classification = .xpcTimeout
                } else {
                    classification = .xpcConnectionInvalidated
                }
                await recordFailure(MCPFailureEvent(
                    requestID: requestID.rawValue,
                    agent: targetApp.rawValue,
                    clientName: "manifold-mcp",
                    toolName: name,
                    boundary: .xpcClient,
                    phase: .reply,
                    classification: classification,
                    isRetryable: true,
                    redactedMessage: error.localizedDescription,
                    connectionID: connectionID
                ))
                return JSONDict(annotatedError(
                    error.localizedDescription,
                    requestID: requestID,
                    boundary: .xpcClient,
                    phase: .reply,
                    classification: classification,
                    retryable: true
                ))
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
        ]) { uri, requestID in
            if let demoRuntime, let text = demoRuntime.resourceText(uri: uri) {
                return text
            }
            let existingConnectionID = await connectionState.get()
            let runtimeConnectionID: String?
            if let existingConnectionID {
                runtimeConnectionID = existingConnectionID
            } else {
                runtimeConnectionID = await connectRuntime(requestID: requestID)
            }
            guard let connectionID = runtimeConnectionID else {
                return await connectionState.unavailableMessage()
            }
            func toolText(_ name: String, arguments: [String: Any] = [:]) async -> String {
                do {
                    var result = try await xpc.callTool(
                        connectionID: connectionID,
                        requestID: requestID.rawValue,
                        toolName: name,
                        arguments: arguments
                    )
                    if isInactiveRuntimeResult(result),
                       let reconnectedID = await connectRuntime(requestID: requestID, toolName: name) {
                        result = try await xpc.callTool(
                            connectionID: reconnectedID,
                            requestID: requestID.rawValue,
                            toolName: name,
                            arguments: arguments
                        )
                    }
                    return textContent(from: result)
                } catch {
                    await recordFailure(MCPFailureEvent(
                        requestID: requestID.rawValue,
                        agent: targetApp.rawValue,
                        clientName: "manifold-mcp",
                        toolName: name,
                        boundary: .xpcClient,
                        phase: .reply,
                        classification: .xpcConnectionInvalidated,
                        isRetryable: true,
                        redactedMessage: error.localizedDescription,
                        connectionID: connectionID
                    ))
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
            await recordFailure(MCPFailureEvent(
                requestID: ManifoldRequestID().rawValue,
                agent: targetApp.rawValue,
                clientName: "manifold-mcp",
                boundary: .stdio,
                phase: .disconnect,
                classification: .transportStdinEOF,
                isRetryable: true,
                redactedMessage: error.localizedDescription
            ))
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

    static func makeFailureEventRecorder(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> (any MCPFailureEventRecording)? {
        guard let rootURL = ManifoldRuntimeEnvironment.runtimeStoreURL(env: env) else {
            return nil
        }
        do {
            let db = try DatabaseConnection(url: rootURL.appendingPathComponent("manifold.db", isDirectory: false))
            return try MCPFailureEventWriter(db: db)
        } catch {
            logger.error("Failed to open MCP failure event store: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    static func recordFailureEvent(
        _ event: MCPFailureEvent,
        recorder: (any MCPFailureEventRecording)?,
        diagnostics: DiagnosticsRecorder?,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) async -> Bool {
        diagnostics?.record(event.classification == .xpcConnectionInvalidated ? .mcpTransportClosed : .mcpRequestFailed)
        if let recorder {
            do {
                try await recorder.record(event)
                return true
            } catch {
                logger.error("Failed to persist MCP failure event \(event.eventID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        } else {
            logger.error("MCP failure event store unavailable for request \(event.requestID, privacy: .public)")
        }

        if let spoolURL = spoolFailureEvent(event, env: env) {
            logger.error("Spooled MCP failure event \(event.eventID, privacy: .public) to \(spoolURL.path, privacy: .public)")
        } else {
            logger.error("Failed to spool MCP failure event \(event.eventID, privacy: .public)")
        }
        return false
    }

    static func failureSpoolURL(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let diagnosticsURL = ManifoldRuntimeEnvironment.diagnosticsDirectoryURL(env: env) else {
            return nil
        }
        return diagnosticsURL.appendingPathComponent("mcp-failure-events-spool.jsonl", isDirectory: false)
    }

    static func spoolFailureEvent(
        _ event: MCPFailureEvent,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let url = failureSpoolURL(env: env) else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.manifoldFailureSpool.encode(event) + Data("\n".utf8)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
            return url
        } catch {
            logger.error("Failed to append MCP failure spool: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func healthResult(
        requestID: ManifoldRequestID,
        version: String,
        targetApp: TargetApp,
        connectionID: String?,
        failureRecorderAvailable: Bool,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: Any] {
        let runtimeStoreURL = ManifoldRuntimeEnvironment.runtimeStoreURL(env: env)
        let dbURL = runtimeStoreURL?.appendingPathComponent("manifold.db", isDirectory: false)
        let spoolURL = failureSpoolURL(env: env)
        let xpcReachable = connectionID != nil

        var health: [String: Any] = [
            "mcp_binary": CommandLine.arguments.first ?? "manifold-mcp",
            "mcp_version": version,
            "agent": targetApp.rawValue,
            "xpc_service": ManifoldRuntimeEnvironment.xpcServiceName(env: env),
            "xpc_reachable": xpcReachable,
            "failure_ledger": failureRecorderAvailable ? "database" : "spool",
            "effective_access_resolver_version": ManifoldReliabilityConstants.effectiveAccessResolverVersion,
        ]
        if let dbURL {
            health["store_path"] = dbURL.path
            health["store_open"] = failureRecorderAvailable
        } else {
            health["store_open"] = false
        }
        if let spoolURL {
            health["failure_spool_path"] = spoolURL.path
        }
        if let connectionID {
            health["connection_id"] = connectionID
        }

        let text = [
            "Manifold MCP health",
            "MCP helper: \(health["mcp_binary"] ?? "manifold-mcp")",
            "MCP version: \(version)",
            "Agent: \(targetApp.rawValue)",
            "Failure ledger: \(health["failure_ledger"] ?? "unknown")",
            "Store open: \(health["store_open"] ?? false)",
            "XPC service: \(health["xpc_service"] ?? "")",
            "XPC reachable: \(xpcReachable ? "yes" : "no")",
            "Effective access resolver: \(ManifoldReliabilityConstants.effectiveAccessResolverVersion)",
        ].joined(separator: "\n")

        var manifoldMeta: [String: Any] = [
            "request_id": requestID.rawValue,
            "health": health,
        ]
        var result: [String: Any] = [
            "content": [["type": "text", "text": text]],
            "_meta": ["manifold": manifoldMeta],
        ]
        if !xpcReachable {
            manifoldMeta["error"] = [
                "boundary": MCPFailureBoundary.xpcClient.rawValue,
                "phase": MCPFailurePhase.connect.rawValue,
                "classification": MCPFailureClassification.xpcRuntimeUnavailable.rawValue,
                "retryable": true,
            ] as [String: Any]
            result["isError"] = true
            result["_meta"] = ["manifold": manifoldMeta]
        }
        return result
    }

    static func annotateResult(_ result: [String: Any], requestID: ManifoldRequestID) -> [String: Any] {
        var annotated = result
        var meta = (annotated["_meta"] as? [String: Any]) ?? [:]
        var manifold = (meta["manifold"] as? [String: Any]) ?? [:]
        manifold["request_id"] = manifold["request_id"] ?? requestID.rawValue
        meta["manifold"] = manifold
        annotated["_meta"] = meta
        return annotated
    }

    static func annotatedError(
        _ message: String,
        requestID: ManifoldRequestID,
        boundary: MCPFailureBoundary,
        phase: MCPFailurePhase,
        classification: MCPFailureClassification,
        retryable: Bool
    ) -> [String: Any] {
        [
            "content": [[
                "type": "text",
                "text": "Manifold error \(requestID.rawValue) at \(boundary.rawValue)/\(phase.rawValue): \(message)",
            ]],
            "isError": true,
            "_meta": [
                "manifold": [
                    "request_id": requestID.rawValue,
                    "error": [
                        "boundary": boundary.rawValue,
                        "phase": phase.rawValue,
                        "classification": classification.rawValue,
                        "retryable": retryable,
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    static func isInactiveRuntimeResult(_ result: [String: Any]) -> Bool {
        guard result["isError"] as? Bool == true else { return false }
        return textContent(from: result).contains("No active runtime connection")
    }
}
