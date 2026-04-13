// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - MCP Tool & Resource Types

struct MCPTool: @unchecked Sendable {
    let name: String
    let description: String
    let inputSchema: [String: Any]

    var jsonDict: [String: Any] {
        var dict: [String: Any] = ["name": name, "description": description]
        dict["inputSchema"] = inputSchema
        return dict
    }
}

struct MCPResource: Sendable {
    let name: String
    let uri: String
    let description: String
}

/// Sendable wrapper for JSON dictionaries crossing concurrency boundaries.
struct JSONDict: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
}

// MARK: - MCP Server (stdio JSON-RPC 2.0)

/// Minimal MCP server. Reads JSON-RPC 2.0 from stdin, dispatches to handlers, writes responses to stdout.
/// Zero external dependencies. Uses Foundation only.
/// Actor ensures registration and start are serialized — no races on handler state.
actor MCPServer {
    let name: String
    let version: String

    private var toolHandler: ((_ name: String, _ arguments: JSONDict) async -> JSONDict)?
    private var initializeHandler: ((_ params: JSONDict) async -> Void)?
    private var tools: [MCPTool] = []
    private var resources: [MCPResource] = []
    private var resourceReader: ((_ uri: String) async -> String)?

    init(name: String, version: String) {
        self.name = name
        self.version = version
    }

    // MARK: - Registration

    func registerTools(_ tools: [MCPTool], handler: @escaping @Sendable (_ name: String, _ arguments: JSONDict) async -> JSONDict) {
        self.tools = tools
        self.toolHandler = handler
    }

    func registerResources(_ resources: [MCPResource], reader: @escaping @Sendable (_ uri: String) async -> String) {
        self.resources = resources
        self.resourceReader = reader
    }

    func registerInitializeHandler(_ handler: @escaping @Sendable (_ params: JSONDict) async -> Void) {
        self.initializeHandler = handler
    }

    // MARK: - Run

    /// Start the server. Blocks until stdin closes.
    func start() async throws {
        let stdin = FileHandle.standardInput
        let stdout = FileHandle.standardOutput
        var buffer = Data()

        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty { break }

            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[buffer.startIndex..<newlineIndex]
                buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                guard !lineData.isEmpty else { continue }

                if let response = await handleMessage(Data(lineData)) {
                    var out = response
                    out.append(UInt8(ascii: "\n"))
                    stdout.write(out)
                }
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ data: Data) async -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String else {
            return nil
        }

        let id = json["id"]
        let params = json["params"] as? [String: Any] ?? [:]

        let result: Any?
        switch method {
        case "initialize":
            result = await handleInitialize(params: params)
        case "initialized", "notifications/initialized":
            return nil
        case "tools/list":
            result = handleToolsList()
        case "tools/call":
            result = await handleToolCall(params: params)
        case "resources/list":
            result = handleResourcesList()
        case "resources/read":
            result = await handleResourceRead(params: params)
        case "ping":
            result = [String: Any]()
        default:
            return makeErrorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }

        guard let id else { return nil }
        return makeResponse(id: id, result: result)
    }

    // MARK: - Method Handlers

    private func handleInitialize(params: [String: Any]) async -> [String: Any] {
        if let initializeHandler {
            await initializeHandler(JSONDict(params))
        }
        return [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": ["listChanged": false],
                "resources": ["listChanged": true],
            ] as [String: Any],
            "serverInfo": [
                "name": name,
                "version": version,
            ] as [String: Any],
        ]
    }

    private func handleToolsList() -> [String: Any] {
        ["tools": tools.map(\.jsonDict)]
    }

    private func handleToolCall(params: [String: Any]) async -> [String: Any] {
        guard let name = params["name"] as? String else {
            return ["content": [["type": "text", "text": "Missing tool name"]], "isError": true]
        }
        let arguments = JSONDict(params["arguments"] as? [String: Any] ?? [:])

        if let handler = toolHandler {
            return await handler(name, arguments).value
        }
        return ["content": [["type": "text", "text": "No handler registered"]], "isError": true]
    }

    private func handleResourcesList() -> [String: Any] {
        ["resources": resources.map { ["name": $0.name, "uri": $0.uri, "description": $0.description] }]
    }

    private func handleResourceRead(params: [String: Any]) async -> [String: Any] {
        guard let uri = params["uri"] as? String else { return ["contents": []] }
        if let reader = resourceReader {
            let text = await reader(uri)
            return ["contents": [["uri": uri, "text": text]]]
        }
        return ["contents": []]
    }

    // MARK: - JSON-RPC Encoding

    private func makeResponse(id: Any?, result: Any?) -> Data? {
        var response: [String: Any] = ["jsonrpc": "2.0"]
        if let id { response["id"] = id }
        if let result { response["result"] = result }
        return try? JSONSerialization.data(withJSONObject: response)
    }

    private func makeErrorResponse(id: Any?, code: Int, message: String) -> Data? {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message] as [String: Any],
        ]
        if let id { response["id"] = id }
        return try? JSONSerialization.data(withJSONObject: response)
    }
}
