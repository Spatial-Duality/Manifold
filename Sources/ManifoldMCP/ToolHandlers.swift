import Foundation
import MCP
import ManifoldKit

/// Registers all Manifold MCP tools with the server.
enum ToolHandlers {
    static func allTools() -> [Tool] {
        [
            Tool(
                name: "list_files",
                description: "List all files the user has approved for this session.",
                inputSchema: .object([:])
            ),
            Tool(
                name: "read_file",
                description: "Read the contents of an approved file.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string"), "description": .string("Relative path within the workspace")])
                    ]),
                    "required": .array([.string("path")])
                ])
            ),
            Tool(
                name: "write_file",
                description: "Write content to a file. The change is versioned.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string"), "description": .string("Relative path")]),
                        "content": .object(["type": .string("string"), "description": .string("File content")])
                    ]),
                    "required": .array([.string("path"), .string("content")])
                ])
            ),
            Tool(
                name: "search_files",
                description: "Search for text within approved files.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object(["type": .string("string"), "description": .string("Text to search for")])
                    ]),
                    "required": .array([.string("query")])
                ])
            ),
            Tool(
                name: "list_emails",
                description: "List emails the user has shared. Sensitive emails are auto-hidden.",
                inputSchema: .object([:])
            ),
            Tool(
                name: "read_email",
                description: "Read a specific shared email by ID.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string"), "description": .string("Email message ID")])
                    ]),
                    "required": .array([.string("id")])
                ])
            ),
            Tool(
                name: "get_status",
                description: "Check if Manifold access is active and what is available.",
                inputSchema: .object([:])
            ),
            Tool(
                name: "list_changes",
                description: "List recent file modifications in the current access run.",
                inputSchema: .object([:])
            ),
        ]
    }

    static func handle(name: String, arguments: [String: Value]?, bridge: ManifoldBridge) async -> CallTool.Result {
        do {
            switch name {
            case "get_status":
                let status = await bridge.getStatus()
                return result(formatStatus(status))

            case "list_files":
                let files = try await bridge.listFiles()
                return result(files.isEmpty ? "No files in workspace." : files.joined(separator: "\n"))

            case "read_file":
                guard let path = arguments?["path"]?.stringValue else {
                    return error("'path' parameter required")
                }
                let content = try await bridge.readFile(path: path)
                return result(content)

            case "write_file":
                guard let path = arguments?["path"]?.stringValue,
                      let content = arguments?["content"]?.stringValue else {
                    return error("'path' and 'content' parameters required")
                }
                let msg = try await bridge.writeFile(path: path, content: content)
                return result(msg)

            case "search_files":
                guard let query = arguments?["query"]?.stringValue else {
                    return error("'query' parameter required")
                }
                let results = try await bridge.searchFiles(query: query)
                if results.isEmpty { return result("No matches found for '\(query)'") }
                let formatted = results.map { "## \($0.path)\n" + $0.matches.joined(separator: "\n") }
                return result(formatted.joined(separator: "\n\n"))

            case "list_emails":
                let emails = try await bridge.listEmails()
                if emails.isEmpty { return result("No shared emails.") }
                let formatted = emails.map { "[\($0.id)] \($0.from) — \($0.subject) (\($0.date))" }
                return result(formatted.joined(separator: "\n"))

            case "read_email":
                guard let id = arguments?["id"]?.stringValue else {
                    return error("'id' parameter required")
                }
                let content = try await bridge.readEmail(id: id)
                return result(content)

            case "list_changes":
                let changes = try await bridge.listChanges()
                if changes.isEmpty { return result("No changes recorded yet.") }
                let formatted = changes.map { "[\($0.timestamp)] \($0.type.uppercased()) \($0.path) (via \($0.source))" }
                return result(formatted.joined(separator: "\n"))

            default:
                return error("Unknown tool: \(name)")
            }
        } catch {
            return CallTool.Result(
                content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    private static func result(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }

    private static func error(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
    }

    private static func formatStatus(_ status: StatusResult) -> String {
        if status.active {
            return """
            Status: ACTIVE
            Run: \(status.runID ?? "unknown")
            Files: \(status.fileCount)
            Emails: \(status.emailCount)
            \(status.message)
            """
        } else {
            return status.message
        }
    }
}

// MARK: - Value helpers

extension Value {
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}
