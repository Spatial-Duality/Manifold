import Foundation
import ManifoldKit

/// Registers all Manifold MCP tools and dispatches calls.
enum ToolHandlers {

    // MARK: - Tool Definitions

    static func allTools() -> [MCPTool] {
        [
            MCPTool(
                name: "list_files",
                description: "List all files the user has approved for this session.",
                inputSchema: emptySchema
            ),
            MCPTool(
                name: "read_file",
                description: "Read the contents of an approved file.",
                inputSchema: objectSchema(properties: [
                    "path": ["type": "string", "description": "Relative path within the workspace"],
                ], required: ["path"])
            ),
            MCPTool(
                name: "write_file",
                description: "Write content to a file. The change is versioned.",
                inputSchema: objectSchema(properties: [
                    "path": ["type": "string", "description": "Relative path"],
                    "content": ["type": "string", "description": "File content"],
                ], required: ["path", "content"])
            ),
            MCPTool(
                name: "search_files",
                description: "Search for text within approved files.",
                inputSchema: objectSchema(properties: [
                    "query": ["type": "string", "description": "Text to search for"],
                ], required: ["query"])
            ),
            MCPTool(
                name: "list_emails",
                description: "List emails the user has shared. Sensitive emails are auto-hidden.",
                inputSchema: emptySchema
            ),
            MCPTool(
                name: "read_email",
                description: "Read a specific shared email by ID.",
                inputSchema: objectSchema(properties: [
                    "id": ["type": "string", "description": "Email message ID"],
                ], required: ["id"])
            ),
            MCPTool(
                name: "get_status",
                description: "Check if Manifold access is active and what is available.",
                inputSchema: emptySchema
            ),
            MCPTool(
                name: "list_changes",
                description: "List recent file modifications in the current access run.",
                inputSchema: emptySchema
            ),
        ]
    }

    // MARK: - Call Handler

    static func handle(name: String, arguments: [String: Any], bridge: ManifoldBridge) async -> [String: Any] {
        do {
            switch name {
            case "get_status":
                let status = await bridge.getStatus()
                return textResult(formatStatus(status))

            case "list_files":
                let files = try await bridge.listFiles()
                if files.isEmpty { return textResult("No files available.") }
                let formatted = files.map { f in
                    let size = ByteCountFormatter.string(fromByteCount: Int64(f.sizeBytes), countStyle: .file)
                    return "[\(f.sourceName)] \(f.path)  (\(size), modified: \(f.lastModified.prefix(10)))"
                }
                return textResult("Source folders: \(Set(files.map(\.sourceName)).sorted().joined(separator: ", "))\n\n" + formatted.joined(separator: "\n"))

            case "read_file":
                guard let path = arguments["path"] as? String else {
                    return errorResult("'path' parameter required")
                }
                let content = try await bridge.readFile(path: path)
                return textResult(content)

            case "write_file":
                guard let path = arguments["path"] as? String,
                      let content = arguments["content"] as? String else {
                    return errorResult("'path' and 'content' parameters required")
                }
                let msg = try await bridge.writeFile(path: path, content: content)
                return textResult(msg)

            case "search_files":
                guard let query = arguments["query"] as? String else {
                    return errorResult("'query' parameter required")
                }
                let results = try await bridge.searchFiles(query: query)
                if results.isEmpty { return textResult("No matches found for '\(query)'") }
                let formatted = results.map { "## [\($0.source)] \($0.path)\n" + $0.matches.joined(separator: "\n") }
                return textResult(formatted.joined(separator: "\n\n"))

            case "list_emails":
                let emails = try await bridge.listEmails()
                if emails.isEmpty { return textResult("No shared emails.") }
                let formatted = emails.map { "[\($0.id)] \($0.from) — \($0.subject) (\($0.date))" }
                return textResult(formatted.joined(separator: "\n"))

            case "read_email":
                guard let id = arguments["id"] as? String else {
                    return errorResult("'id' parameter required")
                }
                let content = try await bridge.readEmail(id: id)
                return textResult(content)

            case "list_changes":
                let changes = try await bridge.listChanges()
                if changes.isEmpty { return textResult("No changes recorded yet.") }
                let formatted = changes.map { "[\($0.timestamp)] \($0.type.uppercased()) [\($0.source)] \($0.path) (by \($0.agent))" }
                return textResult(formatted.joined(separator: "\n"))

            default:
                return errorResult("Unknown tool: \(name)")
            }
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func textResult(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]]]
    }

    private static func errorResult(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": true]
    }

    private static func formatStatus(_ status: StatusResult) -> String {
        if status.active {
            return """
            Status: ACTIVE
            Sources: \(status.sources.joined(separator: ", "))
            Files: \(status.fileCount)
            Emails: \(status.emailCount)
            \(status.message)
            """
        } else {
            return status.message
        }
    }

    // MARK: - Schema Builders

    private static var emptySchema: [String: Any] {
        ["type": "object"]
    }

    private static func objectSchema(properties: [String: [String: String]], required: [String]) -> [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": required,
        ]
    }
}
