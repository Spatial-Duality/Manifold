import Foundation

enum ToolDefinitions {
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
