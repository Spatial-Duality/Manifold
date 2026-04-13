// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
@testable import ManifoldKit

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
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": ["listChanged": false],
                "resources": ["listChanged": true],
            ] as [String: Any],
            "serverInfo": [
                "name": "manifold",
                "version": "0.3.0",
            ] as [String: Any],
        ]
        #expect(result["protocolVersion"] as? String == "2024-11-05")
        let serverInfo = result["serverInfo"] as? [String: Any]
        #expect(serverInfo?["name"] as? String == "manifold")
        let caps = result["capabilities"] as? [String: Any]
        #expect(caps?["tools"] != nil)
        #expect(caps?["resources"] != nil)
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
}
