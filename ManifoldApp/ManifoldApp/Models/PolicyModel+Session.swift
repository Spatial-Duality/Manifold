// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// PolicyModel+Session — Stage-6 session primitives exposed on PolicyModel.
//
// Additive over the existing PolicyModel. Internally `activeWorkBlock`
// remains the runtime-facing storage type; `activeSession` is the new
// UI vocabulary, computed lazily when called. During Phase 1 the two
// live side-by-side; in Phase 9 the legacy name is removed.

import Foundation
import ManifoldKit

extension PolicyModel {

    /// The live session (if any), derived from the active tracked work block.
    /// Returns nil when no session is running.
    var activeSession: SessionRecord? {
        guard let block = activeWorkBlock else { return nil }
        return SessionRecord(
            workBlock: block,
            expiresAt: nil,
            additions: [],
            removals: []
        )
    }

    /// Source IDs that the live session adds beyond the agent's default
    /// policy (the session can see them, but they aren't in the default
    /// scope). Empty when no session is live or all scope is already
    /// default. Derived from the active workBlock — honest signal.
    var sessionAdditionIDs: Set<String> {
        guard let block = activeWorkBlock else { return [] }
        let defaultIDs: Set<String> = {
            switch block.agent {
            case .cowork: return Set(claudePolicy?.allowedSourceIDs ?? [])
            case .codex:  return Set(codexPolicy?.allowedSourceIDs ?? [])
            }
        }()
        return Set(block.sourceIDs).subtracting(defaultIDs)
    }

    /// Source IDs in the agent's default scope that the live session has
    /// removed. Empty when no session is live. Also derived from the
    /// active workBlock.
    var sessionRemovalIDs: Set<String> {
        guard let block = activeWorkBlock else { return [] }
        let defaultIDs: Set<String> = {
            switch block.agent {
            case .cowork: return Set(claudePolicy?.allowedSourceIDs ?? [])
            case .codex:  return Set(codexPolicy?.allowedSourceIDs ?? [])
            }
        }()
        return defaultIDs.subtracting(Set(block.sourceIDs))
    }

    /// Pending approval requests for the queue. Derived from the real
    /// runtime ApprovalQueue via `pendingApprovals` on every refresh.
    var pendingRequests: [ApprovalRequest] {
        pendingApprovals.compactMap { record in
            guard let agent = TargetApp(rawValue: record.agent) else { return nil }
            return ApprovalRequest(
                id: record.id,
                agent: agent,
                operation: Self.mapOperation(record.action),
                target: record.path,
                headline: Self.headline(for: agent, action: record.action, target: record.path),
                context: Self.context(for: agent, action: record.action),
                createdAt: Date(timeIntervalSince1970: record.requestedAt)
            )
        }
    }

    // MARK: - Approval mapping helpers

    private static func mapOperation(_ action: String) -> ApprovalRequest.Operation {
        switch action {
        case "read":      return .readFile
        case "write":     return .write
        case "list":      return .listDirectory
        case "search":    return .searchContent
        case "mail":      return .mailboxRead
        case "read_folder": return .readFolder
        default:          return .readFile
        }
    }

    private static func headline(for agent: TargetApp, action: String, target: String) -> String {
        let name = agent == .codex ? "Codex" : "Claude"
        switch action {
        case "write":  return "\(name) wants to write a file."
        case "list":   return "\(name) wants to list a directory."
        case "search": return "\(name) wants to search file contents."
        case "mail":   return "\(name) wants to read mail."
        default:       return "\(name) wants to read a file."
        }
    }

    private static func context(for agent: TargetApp, action: String) -> String {
        "Requested outside this \(agent == .codex ? "Codex" : "Claude") session's scope. Answer or ignore."
    }

    /// Recent sessions, most recent first. Empty during Phase 1 — wired
    /// when SessionHistory ships in Phase 3.
    var recentSessions: [SessionHistoryEntry] { [] }

    /// Compute drift between a past session and current scope state.
    /// Phase-1 stub returns a clean drift; Phase 3 replaces with real
    /// comparison against PolicyStore + SnapshotStore.
    func drift(for entry: SessionHistoryEntry) -> SessionDrift {
        SessionDrift(
            historyEntry: entry,
            pathsChangedSinceEnded: [],
            pathsRevokedSinceEnded: [],
            newlyAddedSinceEnded: []
        )
    }
}
