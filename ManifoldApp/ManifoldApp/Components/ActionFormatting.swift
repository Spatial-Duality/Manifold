import SwiftUI
import ManifoldKit

/// Shared formatting for audit actions across all views.
/// Pro Swift: extract duplicated logic into a single location.
enum ActionFormatting {
    static func icon(for action: String) -> String {
        switch action {
        case "file_read": "eye"
        case "file_modified", "file_created": "pencil"
        case "file_deleted": "trash"
        case "mcp_connection": "antenna.radiowaves.left.and.right"
        case "run_start": "play.circle"
        case "run_end": "stop.circle"
        case "restore": "arrow.uturn.backward"
        case "source_added": "plus.circle"
        case "source_removed": "minus.circle"
        case "tool_call": "terminal"
        default: "circle"
        }
    }

    static func color(for action: String) -> Color {
        switch action {
        case "file_read": .blue
        case "file_modified", "file_created": .green
        case "file_deleted": .red
        case "mcp_connection": .accentColor
        case "restore": .orange
        case "tool_call": .purple
        default: .secondary
        }
    }

    static func description(for entry: AuditEntry) -> String {
        // Tool call entries store tool name in metadata
        if entry.action == "tool_call" {
            if let metadata = entry.metadata,
               let data = metadata.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let tool = json["tool"] {
                return tool
            }
            return "tool call"
        }
        guard let path = entry.filePath else {
            return entry.agent ?? entry.action.replacing("_", with: " ")
        }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return switch entry.action {
        case "source_added": "Folder \"\(name)\" added"
        case "source_removed": "Folder \"\(name)\" removed"
        default: name
        }
    }

    /// Short action verb for compact displays (agent cards, activity rows).
    static func shortAction(for action: String) -> String {
        switch action {
        case "file_read": "Read"
        case "file_modified": "Write"
        case "file_created": "Created"
        case "file_deleted": "Deleted"
        case "mcp_connection": "Connected"
        case "run_start": "Started"
        case "run_end": "Ended"
        case "restore": "Restored"
        case "source_added": "Added"
        case "source_removed": "Removed"
        case "tool_call": "Tool"
        default: action.replacing("_", with: " ").capitalized
        }
    }
}
