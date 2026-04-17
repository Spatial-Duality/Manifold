// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// GovernanceModel+Session — Stage-6 session primitives exposed on GovernanceModel.
//
// Additive over the existing GovernanceModel. Internally the runtime still
// stores a `WorkBlockRecord`, but the app-facing vocabulary is `Session`.

import Foundation
import ManifoldKit

extension GovernanceModel {

    /// The live session (if any), derived from the active tracked session record.
    /// Returns nil when no session is running.
    var activeSession: SessionRecord? {
        guard let block = activeSessionRecord else { return nil }
        return SessionRecord(
            storageRecord: block,
            expiresAt: nil,
            additions: [],
            removals: []
        )
    }

    /// Pending approval requests for the queue. Derived from the real
    /// runtime ApprovalQueue via `pendingApprovals` on every refresh.
    var pendingRequests: [ApprovalRequest] {
        pendingApprovals.compactMap { record in
            guard let agent = TargetApp(rawValue: record.agent) else { return nil }
            let kind = ApprovalRequest.Kind(rawValue: record.kind) ?? .standingWrite
            return ApprovalRequest(
                id: record.id,
                kind: kind,
                agent: agent,
                operation: Self.mapOperation(record.action),
                target: record.path,
                headline: Self.headline(for: agent, record: record),
                context: Self.context(for: agent, record: record),
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

    private static func headline(for agent: TargetApp, record: PendingApprovalRecord) -> String {
        let name = agent == .codex ? "Codex" : "Claude"
        switch record.kind {
        case "standing_write":
            return "\(name) wants reversible write access."
        default:
            break
        }

        switch record.action {
        case "write":  return "\(name) wants to write a file."
        case "list":   return "\(name) wants to list a directory."
        case "search": return "\(name) wants to search file contents."
        case "mail":   return "\(name) wants to read mail."
        case "read_folder": return "\(name) wants to read a folder."
        default:       return "\(name) wants to read a file."
        }
    }

    private static func context(for agent: TargetApp, record: PendingApprovalRecord) -> String {
        switch record.kind {
        case "standing_write":
            let mountLabel = record.mountName ?? "shared folder"
            return "Reads are ambient here. Once allows one reversible write to this file. Add to default allows reversible writes anywhere in \(mountLabel)."
        default:
            return "Requested outside this \(agent == .codex ? "Codex" : "Claude") session's scope. Answer or ignore."
        }
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
