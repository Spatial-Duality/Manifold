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
                description: "List recent file modifications across all sources.",
                inputSchema: emptySchema
            ),
            MCPTool(
                name: "file_info",
                description: "Get detailed info about a file: size, type, whether it's binary, and archive contents if it's a zip.",
                inputSchema: objectSchema(properties: [
                    "path": ["type": "string", "description": "Relative file path"],
                ], required: ["path"])
            ),
            MCPTool(
                name: "list_archive",
                description: "List all files inside a zip archive without extracting it.",
                inputSchema: objectSchema(properties: [
                    "path": ["type": "string", "description": "Path to the zip file"],
                ], required: ["path"])
            ),
            MCPTool(
                name: "extract_file",
                description: "Extract and read a single file from inside a zip archive. Returns the text content.",
                inputSchema: objectSchema(properties: [
                    "archive_path": ["type": "string", "description": "Path to the zip archive"],
                    "file_path": ["type": "string", "description": "Path of the file inside the archive"],
                ], required: ["archive_path", "file_path"])
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

            case "file_info":
                guard let path = arguments["path"] as? String else {
                    return errorResult("'path' parameter required")
                }
                let info = try await bridge.fileInfo(path: path)
                let size = ByteCountFormatter.string(fromByteCount: Int64(info.sizeBytes), countStyle: .file)
                var text = """
                File: \(info.path)
                Source: \(info.sourceName)
                Size: \(size)
                Type: .\(info.fileExtension)
                Binary: \(info.isBinary ? "yes" : "no")
                Modified: \(info.lastModified)
                """
                if let contents = info.archiveContents {
                    text += "\n\nArchive contents (\(contents.count) files):\n" + contents.joined(separator: "\n")
                }
                return textResult(text)

            case "list_archive":
                guard let path = arguments["path"] as? String else {
                    return errorResult("'path' parameter required")
                }
                let contents = try await bridge.listArchive(path: path)
                return textResult("Archive: \(path)\n\(contents.count) files:\n\n" + contents.joined(separator: "\n"))

            case "extract_file":
                guard let archivePath = arguments["archive_path"] as? String,
                      let filePath = arguments["file_path"] as? String else {
                    return errorResult("'archive_path' and 'file_path' parameters required")
                }
                let content = try await bridge.extractFile(archivePath: archivePath, filePath: filePath)
                return textResult(content)

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
            var lines = [
                "Status: ACTIVE",
                "Active sources: \(status.sources.joined(separator: ", "))",
            ]
            if !status.pausedSources.isEmpty {
                lines.append("Paused sources (not accessible): \(status.pausedSources.joined(separator: ", "))")
            }
            lines.append("Files: \(status.fileCount)")
            lines.append("Emails: \(status.emailCount)")
            lines.append(status.message)
            return lines.joined(separator: "\n")
        } else if !status.pausedSources.isEmpty {
            return """
            Status: ALL SOURCES PAUSED
            Paused sources: \(status.pausedSources.joined(separator: ", "))
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
