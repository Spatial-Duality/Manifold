// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
@testable import ManifoldKit
@testable import ManifoldMCP

// We can't directly test MCPServer (it's in ManifoldMCP target),
// but we can test the JSON-RPC 2.0 protocol compliance by validating
// the message formats that the server produces and consumes.

@Suite("MCP Protocol")
struct MCPProtocolTests {

    @Test("JSON-RPC 2.0 request has required fields")
    func requestFormat() {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list",
            "params": [:] as [String: Any],
        ]
        let data = try! JSONSerialization.data(withJSONObject: request)
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(parsed["jsonrpc"] as? String == "2.0")
        #expect(parsed["id"] as? Int == 1)
        #expect(parsed["method"] as? String == "tools/list")
    }

    @Test("JSON-RPC 2.0 response format")
    func responseFormat() {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "result": ["tools": []] as [String: Any],
        ]
        let data = try! JSONSerialization.data(withJSONObject: response)
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(parsed["jsonrpc"] as? String == "2.0")
        #expect(parsed["id"] as? Int == 1)
        #expect(parsed["result"] != nil)
    }

    @Test("JSON-RPC 2.0 error response format")
    func errorResponseFormat() {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "error": ["code": -32601, "message": "Method not found"] as [String: Any],
        ]
        let data = try! JSONSerialization.data(withJSONObject: response)
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let error = parsed["error"] as? [String: Any]
        #expect(error?["code"] as? Int == -32601)
        #expect(error?["message"] as? String == "Method not found")
    }

    @Test("Initialize response contains required fields")
    func initializeResponse() {
        // Simulate what MCPServer.handleInitialize returns
        let result: [String: Any] = [
            "protocolVersion": "2025-06-18",
            "capabilities": [
                "tools": ["listChanged": true],
                "resources": ["listChanged": true],
            ] as [String: Any],
            "serverInfo": [
                "name": "manifold",
                "version": "0.3.0",
            ] as [String: Any],
        ]
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        let serverInfo = result["serverInfo"] as? [String: Any]
        #expect(serverInfo?["name"] as? String == "manifold")
        let caps = result["capabilities"] as? [String: Any]
        #expect(caps?["tools"] != nil)
        #expect(caps?["resources"] != nil)
        let toolCaps = caps?["tools"] as? [String: Bool]
        #expect(toolCaps?["listChanged"] == true)
    }

    @Test("Tool call result format with text content")
    func toolCallResultFormat() {
        let result: [String: Any] = [
            "content": [["type": "text", "text": "Hello world"]],
        ]
        let content = result["content"] as? [[String: Any]]
        #expect(content?.count == 1)
        #expect(content?[0]["type"] as? String == "text")
        #expect(content?[0]["text"] as? String == "Hello world")
    }

    @Test("Tool call error result has isError flag")
    func toolCallErrorFormat() {
        let result: [String: Any] = [
            "content": [["type": "text", "text": "File not found"]],
            "isError": true,
        ]
        #expect(result["isError"] as? Bool == true)
    }

    @Test("Notification has no id field")
    func notificationFormat() {
        let notification: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": [:] as [String: Any],
        ]
        #expect(notification["id"] == nil)
        #expect(notification["method"] as? String == "notifications/initialized")
    }

    @Test("Newline-delimited messages parse correctly")
    func newlineDelimitedParsing() {
        let msg1: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [:] as [String: Any]]
        let msg2: [String: Any] = ["jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": [:] as [String: Any]]

        let data1 = try! JSONSerialization.data(withJSONObject: msg1)
        let data2 = try! JSONSerialization.data(withJSONObject: msg2)

        var combined = Data()
        combined.append(data1)
        combined.append(UInt8(ascii: "\n"))
        combined.append(data2)
        combined.append(UInt8(ascii: "\n"))

        // Split on newlines
        var messages: [[String: Any]] = []
        var buffer = combined
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[buffer.index(after: newlineIndex)...])
            if let json = try? JSONSerialization.jsonObject(with: Data(lineData)) as? [String: Any] {
                messages.append(json)
            }
        }

        #expect(messages.count == 2)
        #expect(messages[0]["method"] as? String == "initialize")
        #expect(messages[1]["method"] as? String == "tools/list")
    }

    @Test("Content-Length framed messages parse correctly")
    func contentLengthFramedParsing() {
        let msg1: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [:] as [String: Any]]
        let msg2: [String: Any] = ["jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": [:] as [String: Any]]

        let data1 = try! JSONSerialization.data(withJSONObject: msg1)
        let data2 = try! JSONSerialization.data(withJSONObject: msg2)

        var combined = Data()
        combined.append(Data("Content-Length: \(data1.count)\r\n\r\n".utf8))
        combined.append(data1)
        combined.append(Data("Content-Length: \(data2.count)\r\n\r\n".utf8))
        combined.append(data2)

        var parsed: [[String: Any]] = []
        var buffer = combined
        while let message = MCPStdioFramer.nextMessage(from: &buffer) {
            if let json = try? JSONSerialization.jsonObject(with: message.body) as? [String: Any] {
                parsed.append(json)
            }
        }

        #expect(parsed.count == 2)
        #expect(parsed[0]["method"] as? String == "initialize")
        #expect(parsed[1]["method"] as? String == "tools/list")
    }

    @Test("Content-Length responses include MCP stdio header")
    func contentLengthEncoding() {
        let body = Data(#"{"jsonrpc":"2.0","id":1,"result":{}}"#.utf8)
        let framed = MCPStdioFramer.encode(body, framing: .contentLength)
        let text = String(data: framed, encoding: .utf8)

        #expect(text?.hasPrefix("Content-Length: \(body.count)\r\n\r\n") == true)
        #expect(text?.hasSuffix(String(data: body, encoding: .utf8) ?? "") == true)
    }

    @Test("Malformed JSON returns JSON-RPC parse error")
    func malformedJSONReturnsParseError() async throws {
        let server = MCPServer(name: "manifold", version: "test")
        let responseData = try #require(await server.handleMessage(Data(#"{"jsonrpc":"2.0","id":1,"#.utf8)))
        let response = try #require(try JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        let error = try #require(response["error"] as? [String: Any])

        #expect(response["jsonrpc"] as? String == "2.0")
        #expect(error["code"] as? Int == -32700)
    }

    @Test("Missing method returns JSON-RPC invalid request")
    func missingMethodReturnsInvalidRequest() async throws {
        let server = MCPServer(name: "manifold", version: "test")
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 7, "params": [:] as [String: Any]]
        let data = try JSONSerialization.data(withJSONObject: request)
        let responseData = try #require(await server.handleMessage(data))
        let response = try #require(try JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        let error = try #require(response["error"] as? [String: Any])

        #expect(response["id"] as? Int == 7)
        #expect(error["code"] as? Int == -32600)
    }

    @Test("MCP failure recorder persists to DB when store is writable")
    func mcpFailureRecorderPersistsToDB() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-mcp-recorder-db-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let store = try MCPFailureEventStore(db: db)
        let writer = try MCPFailureEventWriter(db: db)
        let event = MCPFailureEvent(
            requestID: "req-negative-db",
            agent: "cowork",
            clientName: "manifold-mcp",
            toolName: "list_files",
            boundary: .xpcClient,
            phase: .connect,
            classification: .xpcRuntimeUnavailable,
            isRetryable: true,
            redactedMessage: "Timed out waiting for the Manifold runtime during connect."
        )

        let persisted = await ManifoldMCPServer.recordFailureEvent(
            event,
            recorder: writer,
            diagnostics: nil,
            env: [ManifoldRuntimeEnvironment.diagnosticsDirectoryURLKey: tempDir.path]
        )
        let recent = try await store.recent(limit: 1)

        #expect(persisted)
        #expect(recent.first?.requestID == "req-negative-db")
        #expect(recent.first?.classification == .xpcRuntimeUnavailable)
    }

    @Test("MCP failure recorder spools when DB store is unavailable")
    func mcpFailureRecorderSpoolsWhenDBUnavailable() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-mcp-recorder-spool-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let env = [ManifoldRuntimeEnvironment.diagnosticsDirectoryURLKey: tempDir.path]
        let event = MCPFailureEvent(
            requestID: "req-negative-spool",
            agent: "cowork",
            clientName: "manifold-mcp",
            toolName: "list_files",
            boundary: .xpcClient,
            phase: .connect,
            classification: .xpcRuntimeUnavailable,
            isRetryable: true,
            redactedMessage: "Unable to connect to the Manifold runtime."
        )

        let persisted = await ManifoldMCPServer.recordFailureEvent(
            event,
            recorder: nil,
            diagnostics: nil,
            env: env
        )
        let spoolURL = try #require(ManifoldMCPServer.failureSpoolURL(env: env))
        let text = try String(contentsOf: spoolURL, encoding: .utf8)
        let line = try #require(text.split(separator: "\n").first)
        let decoded = try JSONDecoder().decode(MCPFailureEvent.self, from: Data(line.utf8))

        #expect(!persisted)
        #expect(decoded.requestID == "req-negative-spool")
        #expect(decoded.classification == .xpcRuntimeUnavailable)
        #expect(decoded.boundary == .xpcClient)
        #expect(decoded.phase == .connect)
    }

    @Test("MCP health result is local, redacted, and classified when XPC is unreachable")
    func mcpHealthResultIncludesLocalPreflightMetadata() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-mcp-health-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let env = [
            ManifoldRuntimeEnvironment.runtimeStoreURLKey: tempDir.appendingPathComponent("store").path,
            ManifoldRuntimeEnvironment.diagnosticsDirectoryURLKey: tempDir.appendingPathComponent("diagnostics").path,
        ]

        let result = ManifoldMCPServer.healthResult(
            requestID: ManifoldRequestID("req-health"),
            version: "test-version",
            targetApp: .cowork,
            connectionID: nil,
            failureRecorderAvailable: false,
            env: env
        )
        let meta = try #require(result["_meta"] as? [String: Any])
        let manifold = try #require(meta["manifold"] as? [String: Any])
        let health = try #require(manifold["health"] as? [String: Any])
        let error = try #require(manifold["error"] as? [String: Any])

        #expect(result["isError"] as? Bool == true)
        #expect(manifold["request_id"] as? String == "req-health")
        #expect(health["failure_ledger"] as? String == "spool")
        #expect(health["xpc_reachable"] as? Bool == false)
        #expect(health["effective_access_resolver_version"] as? String == ManifoldReliabilityConstants.effectiveAccessResolverVersion)
        #expect(error["classification"] as? String == MCPFailureClassification.xpcRuntimeUnavailable.rawValue)
    }
}
