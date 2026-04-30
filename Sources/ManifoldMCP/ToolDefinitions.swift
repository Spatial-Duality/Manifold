// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

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
                description: "Write UTF-8 text to a governed file. Text only: never use this for PDFs, images, archives, Office documents, or base64-encoded binary bytes. For PDFs use annotate_pdf; for other binary files use write_binary_file. The change is written to the original shared folder and versioned by Manifold.",
                inputSchema: objectSchema(properties: withAccessIntent([
                    "path": ["type": "string", "description": "Relative path"],
                    "content": ["type": "string", "description": "UTF-8 text content. Do not pass base64 binary data."],
                    "expected_before_hash": ["type": "string", "description": "Optional SHA-256 hash of the current file content. If it does not match, the write is rejected."],
                ]), required: ["path", "content"])
            ),
            MCPTool(
                name: "write_binary_file",
                description: "Write base64-encoded bytes to a governed file such as a PDF, image, zip, Pages, Word, or spreadsheet file. Use this instead of write_file for binary bytes. Direct MCP binary writes are limited to 25 MB decoded bytes. Defaults to writing the original shared folder with a Manifold snapshot for rollback.",
                inputSchema: objectSchema(properties: withAccessIntent([
                    "path": ["type": "string", "description": "Relative path"],
                    "content_base64": ["type": "string", "description": "Base64-encoded raw file bytes"],
                    "mime_type": ["type": "string", "description": "Optional MIME type, for example application/pdf"],
                    "expected_before_hash": ["type": "string", "description": "Optional SHA-256 hash of the current file content. If it does not match, the write is rejected."],
                    "write_mode": ["type": "string", "description": "direct or draft_workspace. Defaults to direct. Legacy direct_if_approved is accepted as direct."],
                ]), required: ["path", "content_base64"])
            ),
            MCPTool(
                name: "annotate_pdf",
                description: "Add a small governed text stamp to an existing PDF. PDFs are bounded to 25 MB and 500 pages. Prefer this over reading a PDF, modifying it in a local VM, and writing binary bytes back. Manifold performs the PDF mutation itself and versions the previous bytes.",
                inputSchema: objectSchema(properties: withAccessIntent([
                    "path": ["type": "string", "description": "Relative path to a PDF"],
                    "mark": ["type": "string", "description": "Short stamp text. Defaults to Viewed by Claude."],
                    "expected_before_hash": ["type": "string", "description": "Optional SHA-256 hash of the current PDF bytes. If it does not match, the write is rejected."],
                    "write_mode": ["type": "string", "description": "direct or draft_workspace. Defaults to direct. Legacy direct_if_approved is accepted as direct."],
                ]), required: ["path"])
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
                description: "Check whether the current connection is Manifold-routed, using a draft workspace, or outside coverage.",
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
                description: "List past session summaries. Each session represents a gateway lifecycle (start → agent work → end).",
                inputSchema: objectSchema(properties: [
                    "limit": ["type": "string", "description": "Max sessions to return (default 20)"],
                ], required: [])
            ),
            MCPTool(
                name: "get_session",
                description: "Get full detail for a past session: summary, files modified, files conflicted, and versioned changes.",
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
                description: "Search approved files, emails, and session notes through contextual chunks. Prefer this before list/read loops; it returns scoped previews, line ranges, content hashes, and retrieval metadata.",
                inputSchema: objectSchema(properties: withAccessIntent([
                    "query": ["type": "string", "description": "Text to search for"],
                    "limit": ["type": "integer", "description": "Maximum number of hits (default 10)"],
                ]), required: ["query"])
            ),
            MCPTool(
                name: "tool_cost_report",
                description: "Report recent Manifold tool-call counts, output bytes, truncation, and latency.",
                inputSchema: objectSchema(properties: [
                    "limit": ["type": "integer", "description": "Maximum number of recent tool calls to summarize (default 100)"],
                ], required: [])
            ),
            MCPTool(
                name: "was_exposed_before",
                description: "Check whether Manifold has previously exposed a content hash or governed path. Returns exposures from any agent that touched this content in the same scope, so use it to answer questions like \"has this file been read before?\" or \"what did the other agent see?\".",
                inputSchema: objectSchema(properties: [
                    "content_hash": ["type": "string", "description": "SHA-256 content hash to look up"],
                    "path": ["type": "string", "description": "Governed resource path to look up"],
                    "limit": ["type": "integer", "description": "Maximum matching exposure records (default 10)"],
                ], required: [])
            ),
            MCPTool(
                name: "reuse_prior_context",
                description: "Return scoped prior memories and exposure summaries from any agent that worked in the current source scope. Use this to answer \"what did Codex/Claude just do?\", surface another agent's recent reads, edits, and saved memory, and avoid rereading data the other agent already exposed.",
                inputSchema: objectSchema(properties: [
                    "query": ["type": "string", "description": "Optional memory query"],
                    "path": ["type": "string", "description": "Optional governed path"],
                    "limit": ["type": "integer", "description": "Maximum memory/exposure rows (default 8)"],
                ], required: [])
            ),
            MCPTool(
                name: "verify_ledger_entry",
                description: "Verify the Manifold hash-chain ledger, or inspect one ledger entry by ID.",
                inputSchema: objectSchema(properties: [
                    "entry_id": ["type": "string", "description": "Optional ledger entry ID"],
                ], required: [])
            ),
            MCPTool(
                name: "recall_memory",
                description: "Recall user-owned memory whose lineage is allowed by the current session scope. Includes memory saved by any agent (you or another agent like Codex/Claude) that worked in the same source scope, so use it to surface what was decided, summarized, or noted across recent sessions.",
                inputSchema: objectSchema(properties: [
                    "query": ["type": "string", "description": "Optional memory query"],
                    "limit": ["type": "integer", "description": "Maximum memory rows (default 10)"],
                ], required: [])
            ),
            MCPTool(
                name: "save_memory_note",
                description: "Save a user-owned memory note with lineage to the current session scope.",
                inputSchema: objectSchema(properties: [
                    "title": ["type": "string", "description": "Short memory title"],
                    "body": ["type": "string", "description": "Memory body"],
                    "kind": ["type": "string", "description": "summary, decision, evidence, stale_risk, routine, source_schema, or note"],
                ], required: ["title", "body"])
            ),
            MCPTool(
                name: "list_memory_sources",
                description: "List memory counts for sources available in the current session scope.",
                inputSchema: emptySchema
            ),
            MCPTool(
                name: "forget_memory",
                description: "Mark a memory item deleted by user while preserving the immutable audit ledger.",
                inputSchema: objectSchema(properties: [
                    "memory_id": ["type": "string", "description": "Memory ID returned by recall_memory"],
                ], required: ["memory_id"])
            ),
            MCPTool(
                name: "what_changed_since",
                description: "Summarize recent governed changes, optionally scoped to one path.",
                inputSchema: objectSchema(properties: [
                    "path": ["type": "string", "description": "Optional governed path"],
                    "limit": ["type": "integer", "description": "Maximum recent changes (default 20)"],
                ], required: [])
            ),
            MCPTool(
                name: "create_value_handle",
                description: "Create a capability handle for sensitive data with origin, trust, and allowed sink labels.",
                inputSchema: objectSchema(properties: [
                    "origin": ["type": "string", "description": "Data origin label"],
                    "sensitivity": ["type": "string", "description": "Sensitivity label such as public, private, sensitive, restricted, or secret"],
                    "trust_level": ["type": "string", "description": "Trust label such as trusted or untrusted"],
                    "allowed_sinks": ["type": "string", "description": "Comma-separated allowed sinks, default model_context"],
                ], required: ["origin", "sensitivity", "trust_level"])
            ),
            MCPTool(
                name: "check_capability_flow",
                description: "Check whether a value handle may flow into a sink and apply Rule-of-Two blocking.",
                inputSchema: objectSchema(properties: [
                    "handle_id": ["type": "string", "description": "Value handle ID"],
                    "sink": ["type": "string", "description": "Destination sink, for example model_context, write_file, email_output, external_url, exec_output"],
                    "untrusted_input": ["type": "string", "description": "Optional true/false flag"],
                    "state_changing_action": ["type": "string", "description": "Optional true/false flag"],
                ], required: ["handle_id", "sink"])
            ),
            MCPTool(
                name: "run_code",
                description: "Run a deterministic ManifoldExec JSON plan near governed data. No shell, network, raw filesystem, or state-changing ops are available.",
                inputSchema: objectSchema(properties: [
                    "code": ["type": "string", "description": "JSON plan, for example {\"steps\":[{\"op\":\"recall_memory\",\"query\":\"invoice\"}]}"],
                    "language": ["type": "string", "description": "Optional: manifoldexec-json, json, plan, or status"],
                ], required: ["code"])
            ),
            MCPTool(
                name: "list_skills",
                description: "List saved executable JSON-plan skill manifests.",
                inputSchema: objectSchema(properties: [
                    "limit": ["type": "integer", "description": "Maximum skills (default 50)"],
                ], required: [])
            ),
            MCPTool(
                name: "save_skill",
                description: "Save a versioned skill manifest by hash.",
                inputSchema: objectSchema(properties: [
                    "name": ["type": "string", "description": "Skill name"],
                    "manifest_json": ["type": "string", "description": "Skill manifest JSON"],
                ], required: ["name", "manifest_json"])
            ),
            MCPTool(
                name: "invoke_skill",
                description: "Invoke a saved executable JSON-plan skill. Manifest hashes gate changed scope or sinks.",
                inputSchema: objectSchema(properties: [
                    "name": ["type": "string", "description": "Skill name"],
                ], required: ["name"])
            ),
            MCPTool(
                name: "query_graph",
                description: "Query the scoped knowledge graph. Falls back to scoped memory until the graph index is built.",
                inputSchema: objectSchema(properties: [
                    "query": ["type": "string", "description": "Graph query"],
                    "limit": ["type": "integer", "description": "Maximum results (default 10)"],
                ], required: ["query"])
            ),
            MCPTool(
                name: "verify_claimed_actions",
                description: "Strictly compare structured claimed model actions against scoped Manifold exposure ground truth. Results are supported, ambiguous, or unverified.",
                inputSchema: objectSchema(properties: [
                    "claims_json": ["type": "string", "description": "JSON array of claim objects. Provide content_hash, or both tool_name and resource_path, for supported proof."],
                    "session_id": ["type": "string", "description": "Optional session ID to attach to findings"],
                ], required: ["claims_json"])
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
