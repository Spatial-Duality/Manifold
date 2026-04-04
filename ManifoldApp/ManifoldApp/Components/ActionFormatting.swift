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
        default: .secondary
        }
    }

    static func description(for entry: AuditEntry) -> String {
        guard let path = entry.filePath else {
            return entry.agent ?? entry.action.replacingOccurrences(of: "_", with: " ")
        }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return switch entry.action {
        case "source_added": "Folder \"\(name)\" added"
        case "source_removed": "Folder \"\(name)\" removed"
        default: name
        }
    }
}
