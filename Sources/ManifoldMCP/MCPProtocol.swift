// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

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

enum MCPMessageFraming: Sendable {
    case contentLength
    case newline
}

struct MCPStdioMessage: Sendable {
    let body: Data
    let framing: MCPMessageFraming
}

enum MCPStdioFramer {
    private static let crlfHeaderDelimiter = Data([13, 10, 13, 10])
    private static let lfHeaderDelimiter = Data([10, 10])

    static func nextMessage(from buffer: inout Data) -> MCPStdioMessage? {
        trimLeadingNewlines(from: &buffer)
        guard !buffer.isEmpty else { return nil }

        if startsWithContentLengthHeader(buffer) {
            return nextContentLengthMessage(from: &buffer)
        }

        return nextNewlineMessage(from: &buffer)
    }

    static func encode(_ body: Data, framing: MCPMessageFraming) -> Data {
        switch framing {
        case .contentLength:
            var framed = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
            framed.append(body)
            return framed
        case .newline:
            var framed = body
            framed.append(UInt8(ascii: "\n"))
            return framed
        }
    }

    private static func nextContentLengthMessage(from buffer: inout Data) -> MCPStdioMessage? {
        let delimiter: Data
        let delimiterRange: Range<Data.Index>
        if let range = buffer.range(of: crlfHeaderDelimiter) {
            delimiter = crlfHeaderDelimiter
            delimiterRange = range
        } else if let range = buffer.range(of: lfHeaderDelimiter) {
            delimiter = lfHeaderDelimiter
            delimiterRange = range
        } else {
            return nil
        }

        let headerData = buffer[buffer.startIndex..<delimiterRange.lowerBound]
        guard let header = String(data: Data(headerData), encoding: .utf8),
              let contentLength = parseContentLength(from: header) else {
            buffer.removeSubrange(buffer.startIndex..<delimiterRange.upperBound)
            return nil
        }

        let bodyStart = delimiterRange.lowerBound + delimiter.count
        let bodyEnd = bodyStart + contentLength
        guard buffer.count >= bodyEnd else { return nil }

        let body = Data(buffer[bodyStart..<bodyEnd])
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        return MCPStdioMessage(body: body, framing: .contentLength)
    }

    private static func nextNewlineMessage(from buffer: inout Data) -> MCPStdioMessage? {
        guard let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) else {
            return nil
        }

        let lineData = buffer[buffer.startIndex..<newlineIndex]
        buffer = Data(buffer[buffer.index(after: newlineIndex)...])
        let body = Data(lineData).trimmingTrailingCarriageReturn()
        guard !body.isEmpty else { return nextMessage(from: &buffer) }
        return MCPStdioMessage(body: body, framing: .newline)
    }

    private static func startsWithContentLengthHeader(_ buffer: Data) -> Bool {
        guard let firstLineEnd = buffer.firstIndex(of: UInt8(ascii: "\n")) else {
            return String(data: buffer, encoding: .utf8)?
                .lowercased()
                .hasPrefix("content-length:") == true
        }
        let firstLine = buffer[buffer.startIndex..<firstLineEnd]
        return String(data: Data(firstLine), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("content-length:") == true
    }

    private static func parseContentLength(from header: String) -> Int? {
        for line in header.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length",
                  let length = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
                continue
            }
            return length
        }
        return nil
    }

    private static func trimLeadingNewlines(from buffer: inout Data) {
        while let first = buffer.first, first == UInt8(ascii: "\n") || first == UInt8(ascii: "\r") {
            buffer.removeFirst()
        }
    }
}

private extension Data {
    func trimmingTrailingCarriageReturn() -> Data {
        guard last == UInt8(ascii: "\r") else { return self }
        return dropLast()
    }
}

/// Minimal MCP server. Reads JSON-RPC 2.0 from stdin, dispatches to handlers, writes responses to stdout.
/// Zero external dependencies. Uses Foundation only.
/// Actor ensures registration and start are serialized — no races on handler state.
actor MCPServer {
    private static let supportedProtocolVersions = [
        "2025-06-18",
        "2025-03-26",
        "2024-11-05",
    ]

    let name: String
    let version: String

    private var toolHandler: ((_ name: String, _ arguments: JSONDict, _ requestID: ManifoldRequestID) async -> JSONDict)?
    private var initializeHandler: ((_ params: JSONDict) async -> Void)?
    private var tools: [MCPTool] = []
    private var resources: [MCPResource] = []
    private var resourceReader: ((_ uri: String, _ requestID: ManifoldRequestID) async -> String)?

    init(name: String, version: String) {
        self.name = name
        self.version = version
    }

    // MARK: - Registration

    func registerTools(
        _ tools: [MCPTool],
        handler: @escaping @Sendable (_ name: String, _ arguments: JSONDict, _ requestID: ManifoldRequestID) async -> JSONDict
    ) {
        self.tools = tools
        self.toolHandler = handler
    }

    func registerResources(
        _ resources: [MCPResource],
        reader: @escaping @Sendable (_ uri: String, _ requestID: ManifoldRequestID) async -> String
    ) {
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

            while let message = MCPStdioFramer.nextMessage(from: &buffer) {
                if let response = await handleMessage(message.body) {
                    stdout.write(MCPStdioFramer.encode(response, framing: message.framing))
                }
            }
        }
    }

    // MARK: - Message Handling

    func handleMessage(_ data: Data) async -> Data? {
        let decoded: Any
        do {
            decoded = try JSONSerialization.jsonObject(with: data)
        } catch {
            return makeErrorResponse(id: NSNull(), code: -32700, message: "Parse error")
        }

        guard let json = decoded as? [String: Any] else {
            return makeErrorResponse(id: NSNull(), code: -32600, message: "Invalid Request")
        }

        guard let method = json["method"] as? String else {
            return makeErrorResponse(id: json["id"] ?? NSNull(), code: -32600, message: "Invalid Request")
        }

        let id = json["id"]
        let requestID = ManifoldRequestID.make(jsonRPCID: id)
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
            result = await handleToolCall(params: params, requestID: requestID)
        case "resources/list":
            result = handleResourcesList()
        case "resources/read":
            result = await handleResourceRead(params: params, requestID: requestID)
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
        let requestedProtocolVersion = params["protocolVersion"] as? String
        let protocolVersion = requestedProtocolVersion
            .flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
            ?? Self.supportedProtocolVersions[0]
        return [
            "protocolVersion": protocolVersion,
            "capabilities": [
                "tools": ["listChanged": true],
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

    private func handleToolCall(params: [String: Any], requestID: ManifoldRequestID) async -> [String: Any] {
        guard let name = params["name"] as? String else {
            return annotatedError("Missing tool name", requestID: requestID, classification: .transportMalformedMessage)
        }
        let arguments = JSONDict(params["arguments"] as? [String: Any] ?? [:])

        if let handler = toolHandler {
            return await handler(name, arguments, requestID).value
        }
        return annotatedError("No handler registered", requestID: requestID, classification: .unknown)
    }

    private func handleResourcesList() -> [String: Any] {
        ["resources": resources.map { ["name": $0.name, "uri": $0.uri, "description": $0.description] }]
    }

    private func handleResourceRead(params: [String: Any], requestID: ManifoldRequestID) async -> [String: Any] {
        guard let uri = params["uri"] as? String else { return ["contents": []] }
        if let reader = resourceReader {
            let text = await reader(uri, requestID)
            return ["contents": [["uri": uri, "text": text]]]
        }
        return ["contents": []]
    }

    private func annotatedError(
        _ message: String,
        requestID: ManifoldRequestID,
        classification: MCPFailureClassification
    ) -> [String: Any] {
        [
            "content": [["type": "text", "text": "Manifold error \(requestID.rawValue) at mcp_adapter/decode: \(message)"]],
            "isError": true,
            "_meta": [
                "manifold": [
                    "request_id": requestID.rawValue,
                    "error": [
                        "boundary": MCPFailureBoundary.mcpAdapter.rawValue,
                        "phase": MCPFailurePhase.decode.rawValue,
                        "classification": classification.rawValue,
                        "retryable": false,
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]
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
