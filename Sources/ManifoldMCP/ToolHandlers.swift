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
            MCPTool(
                name: "list_sessions",
                description: "List past session summaries. Each session represents a grant lifecycle (start → agent work → promote → end).",
                inputSchema: objectSchema(properties: [
                    "limit": ["type": "string", "description": "Max sessions to return (default 20)"],
                ], required: [])
            ),
            MCPTool(
                name: "get_session",
                description: "Get full detail for a past session: summary, files modified, files conflicted, and promotion results.",
                inputSchema: objectSchema(properties: [
                    "grant_id": ["type": "string", "description": "The grant ID from list_sessions"],
                ], required: ["grant_id"])
            ),
            MCPTool(
                name: "save_session_note",
                description: "Save a short session note for the current active session. Use sparingly for start, checkpoint, or end context when that intent would not be obvious from the audit trail.",
                inputSchema: objectSchema(properties: [
                    "note": ["type": "string", "description": "Markdown note about the session"],
                    "note_type": [
                        "type": "string",
                        "description": "Optional note type: start_note, checkpoint_note, or end_note",
                    ],
                ], required: ["note"])
            ),
            MCPTool(
                name: "read_range",
                description: "Read a targeted line range from an approved file.",
                inputSchema: objectSchema(properties: [
                    "path": ["type": "string", "description": "Relative path within the workspace"],
                    "start_line": ["type": "integer", "description": "1-based start line"],
                    "end_line": ["type": "integer", "description": "1-based end line"],
                ], required: ["path", "start_line", "end_line"])
            ),
            MCPTool(
                name: "diff_file",
                description: "Show a compact diff between the current file and its baseline snapshot.",
                inputSchema: objectSchema(properties: [
                    "path": ["type": "string", "description": "Relative path within the workspace"],
                ], required: ["path"])
            ),
            MCPTool(
                name: "search_structured",
                description: "Search approved files and return structured JSON hits with previews.",
                inputSchema: objectSchema(properties: [
                    "query": ["type": "string", "description": "Text to search for"],
                    "limit": ["type": "integer", "description": "Maximum number of hits (default 10)"],
                ], required: ["query"])
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
                let formatted = changes.map { "[\($0.timestamp)] \($0.action.uppercased()) \($0.path ?? "") (by \($0.agent ?? "unknown"))" }
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

            case "list_sessions":
                let limit = (arguments["limit"] as? String).flatMap(Int.init) ?? 20
                let sessions = try await bridge.listSessions(limit: limit)
                if sessions.isEmpty { return textResult("No past sessions recorded.") }
                let formatted = sessions.map { s in
                    "[\(s.grantID.prefix(12))...] \(s.targetApp) | \(s.startedAt.prefix(10)) → \(s.endedAt.prefix(10))\n  \(s.summaryPreview)"
                }
                return textResult("Past sessions (\(sessions.count)):\n\n" + formatted.joined(separator: "\n\n"))

            case "get_session":
                guard let grantID = arguments["grant_id"] as? String else {
                    return errorResult("'grant_id' parameter required")
                }
                let detail = try await bridge.getSession(grantID: grantID)
                return textResult(formatSessionDetail(detail))

            case "save_session_note":
                guard let note = arguments["note"] as? String else {
                    return errorResult("'note' parameter required")
                }
                let noteType = (arguments["note_type"] as? String).flatMap(SessionSummaryKind.init(rawValue:)) ?? .checkpointNote
                let msg = try await bridge.saveSessionNote(note: note, noteType: noteType)
                return textResult(msg)

            case "read_range":
                guard let path = arguments["path"] as? String,
                      let startLine = intArgument(arguments["start_line"]),
                      let endLine = intArgument(arguments["end_line"]) else {
                    return errorResult("'path', 'start_line', and 'end_line' parameters required")
                }
                let content = try await bridge.readRange(path: path, startLine: startLine, endLine: endLine)
                return textResult(content)

            case "diff_file":
                guard let path = arguments["path"] as? String else {
                    return errorResult("'path' parameter required")
                }
                let diff = try await bridge.diffFile(path: path)
                return textResult(diff)

            case "search_structured":
                guard let query = arguments["query"] as? String else {
                    return errorResult("'query' parameter required")
                }
                let limit = intArgument(arguments["limit"]) ?? 10
                let results = try await bridge.searchStructured(query: query, limit: limit)
                return textResult(results)

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

    private static func intArgument(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let stringValue = value as? String {
            return Int(stringValue)
        }
        return nil
    }

    private static func formatStatus(_ status: StatusResult) -> String {
        if status.active {
            var lines: [String] = []
            if let grantID = status.grantID {
                lines.append("Status: ACTIVE (grant \(grantID.prefix(12))...)")
            } else {
                lines.append("Status: ACTIVE (legacy mode)")
            }
            lines.append("Active sources: \(status.sources.joined(separator: ", "))")
            if !status.pausedSources.isEmpty {
                lines.append("Paused sources (not accessible): \(status.pausedSources.joined(separator: ", "))")
            }
            lines.append("Files: \(status.fileCount)")
            lines.append("Emails: \(status.emailCount)")
            if status.noteCaptureMode != SessionNoteCaptureMode.off.rawValue {
                lines.append("Session notes: \(status.noteCaptureMode.uppercased())")
            }
            if let noteGuidance = status.noteGuidance {
                lines.append(noteGuidance)
            }
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

    private static func formatSessionDetail(_ d: SessionDetail) -> String {
        var lines: [String] = []
        lines.append("Grant: \(d.grantID)")
        lines.append("Target: \(d.targetApp)")
        lines.append("Status: \(d.status)")
        lines.append("Started: \(d.startedAt)")
        if let ended = d.endedAt { lines.append("Ended: \(ended)") }
        lines.append("Sources: \(d.sources.joined(separator: ", "))")
        lines.append("Session notes: \(d.noteCaptureMode.uppercased())")
        lines.append("")

        if let summary = d.summaryMarkdown {
            lines.append(summary)
        } else {
            lines.append("No summary recorded.")
        }

        if !d.sessionNotes.isEmpty {
            lines.append("")
            lines.append("Session Notes:")
            for note in d.sessionNotes {
                let kind = SessionSummaryKind(rawValue: note.kind)?.displayName ?? note.kind
                lines.append("- \(kind) (\(note.origin), \(note.endedAt))")
                lines.append(note.markdown)
                lines.append("")
            }
        }

        if !d.filesApplied.isEmpty {
            lines.append("\nFiles applied (\(d.filesApplied.count)):")
            for f in d.filesApplied { lines.append("  ✓ \(f)") }
        }
        if !d.filesConflicted.isEmpty {
            lines.append("\nFiles conflicted (\(d.filesConflicted.count)):")
            for f in d.filesConflicted { lines.append("  ✗ \(f)") }
        }
        if d.totalPromotions == 0 {
            lines.append("\nNo file promotions recorded.")
        }

        return lines.joined(separator: "\n")
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
