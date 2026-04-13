// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// All errors surfaced by ManifoldKit.
public enum ManifoldError: Error, LocalizedError {
    case database(String)
    case fileNotFound(String)
    case snapshotFailed(String)
    case workspaceError(String)
    case hashMismatch(expected: String, actual: String)
    case materialization(String)
    case promotion(String)
    case email(String)

    public var errorDescription: String? {
        switch self {
        case .database(let msg): return "Database error: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .snapshotFailed(let msg): return "Snapshot failed: \(msg)"
        case .workspaceError(let msg): return "Workspace error: \(msg)"
        case .hashMismatch(let expected, let actual):
            return "Hash mismatch: expected \(expected), got \(actual)"
        case .materialization(let msg): return "Materialization error: \(msg)"
        case .promotion(let msg): return "Promotion error: \(msg)"
        case .email(let msg): return "Email error: \(msg)"
        }
    }
}
