import Foundation

/// All errors surfaced by ManifoldKit.
public enum ManifoldError: Error, LocalizedError {
    case database(String)
    case fileNotFound(String)
    case snapshotFailed(String)
    case workspaceError(String)
    case hashMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .database(let msg): return "Database error: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .snapshotFailed(let msg): return "Snapshot failed: \(msg)"
        case .workspaceError(let msg): return "Workspace error: \(msg)"
        case .hashMismatch(let expected, let actual):
            return "Hash mismatch: expected \(expected), got \(actual)"
        }
    }
}
