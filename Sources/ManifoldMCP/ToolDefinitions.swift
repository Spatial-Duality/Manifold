import Foundation

enum ToolDefinitions {
    static func allTools() -> [MCPTool] {
        [
            MCPTool(
                name: "list_files",
                description: "List all files the user has approved for this session.",
                inputSchema: objectSchema(properties: accessIntentProperties, required: [])
            ),
            MCPTool(
                name: "read_file",
                description: "Read the contents of an approved file.",
                inputSchema: objectSchema(properties: withAccessIntent([
                    "path": ["type": "string", "description": "Relative path within the workspace"],
                ]), required: ["path"])
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
                inputSchema: objectSchema(properties: withAccessIntent([
                    "query": ["type": "string", "description": "Text to search for"],
                ]), required: ["query"])
            ),
            MCPTool(
                name: "list_emails",
                description: "List emails the user has shared. Sensitive emails are auto-hidden.",
                inputSchema: objectSchema(properties: accessIntentProperties, required: [])
            ),
            MCPTool(
                name: "read_email",
                description: "Read a specific shared email by ID.",
                inputSchema: objectSchema(properties: withAccessIntent([
                    "id": ["type": "string", "description": "Email message ID"],
                ]), required: ["id"])
            ),
            MCPTool(
                name: "search_emails",
                description: "Search governed emails by sender, subject, preview, and indexed body text.",
                inputSchema: objectSchema(properties: withAccessIntent([
                    "query": ["type": "string", "description": "Text to search for in accessible emails"],
                ]), required: ["query"])
            ),
            MCPTool(
                name: "get_status",
                description: "Check if Manifold access is active and what is available.",
                inputSchema: emptySchema
            ),
            MCPTool(
                name: "get_coverage_status",
                description: "Check whether the current connection is Manifold-routed, in a tracked workspace, or outside coverage.",
                inputSchema: emptySchema
            ),
            MCPTool(
                name: "list_coverage_events",
                description: "List recent drift, verification, and coverage warnings recorded by Manifold.",
                inputSchema: objectSchema(properties: [
                    "limit": ["type": "integer", "description": "Maximum number of events to return (default 20)"],
                ], required: [])
            ),
            MCPTool(
                name: "list_changes",
                description: "List recent file modifications across all sources.",
                inputSchema: emptySchema
            ),
            MCPTool(
                name: "file_info",
                description: "Get detailed info about a file: size, type, whether it's binary, and archive contents if it's a zip.",
                inputSchema: objectSchema(properties: withAccessIntent([
                    "path": ["type": "string", "description": "Relative file path"],
                ]), required: ["path"])
            ),
            MCPTool(
                name: "list_archive",
                description: "List all files inside a zip archive without extracting it.",
                inputSchema: objectSchema(properties: withAccessIntent([
                    "path": ["type": "string", "description": "Path to the zip file"],
                ]), required: ["path"])
            ),
            MCPTool(
                name: "extract_file",
                description: "Extract and read a single file from inside a zip archive. Returns the text content.",
                inputSchema: objectSchema(properties: withAccessIntent([
                    "archive_path": ["type": "string", "description": "Path to the zip archive"],
                    "file_path": ["type": "string", "description": "Path of the file inside the archive"],
                ]), required: ["archive_path", "file_path"])
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
                name: "get_file_history_context",
                description: "Get version history plus nearby activity and exposure context for a governed file.",
                inputSchema: objectSchema(properties: [
                    "file_path": ["type": "string", "description": "Relative file path from Manifold version history"],
                    "limit": ["type": "integer", "description": "Maximum number of snapshots and related events to return (default 20)"],
                ], required: ["file_path"])
            ),
            MCPTool(
                name: "get_session_context",
                description: "Reconstruct the governed context around a recorded session, including files, emails, and notes.",
                inputSchema: objectSchema(properties: [
                    "session_id": ["type": "string", "description": "The session ID from Manifold history"],
                ], required: ["session_id"])
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
                inputSchema: objectSchema(properties: withAccessIntent([
                    "path": ["type": "string", "description": "Relative path within the workspace"],
                    "start_line": ["type": "integer", "description": "1-based start line"],
                    "end_line": ["type": "integer", "description": "1-based end line"],
                ]), required: ["path", "start_line", "end_line"])
            ),
            MCPTool(
                name: "diff_file",
                description: "Show a compact diff between the current file and its baseline snapshot.",
                inputSchema: objectSchema(properties: withAccessIntent([
                    "path": ["type": "string", "description": "Relative path within the workspace"],
                ]), required: ["path"])
            ),
            MCPTool(
                name: "search_structured",
                description: "Search approved files and return structured JSON hits with previews.",
                inputSchema: objectSchema(properties: withAccessIntent([
                    "query": ["type": "string", "description": "Text to search for"],
                    "limit": ["type": "integer", "description": "Maximum number of hits (default 10)"],
                ]), required: ["query"])
            ),
        ]
    }

    private static var accessIntentProperties: [String: [String: String]] {
        [
            "intent_summary": ["type": "string", "description": "Optional short sentence describing why this content is being accessed."],
            "intent_details": ["type": "string", "description": "Optional richer context about how the content will be used. Required when Manifold access recording is set to Detailed."],
        ]
    }

    private static func withAccessIntent(_ properties: [String: [String: String]]) -> [String: [String: String]] {
        properties.merging(accessIntentProperties, uniquingKeysWith: { current, _ in current })
    }

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
