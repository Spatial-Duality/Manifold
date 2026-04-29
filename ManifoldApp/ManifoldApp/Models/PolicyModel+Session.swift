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
            let privacyContext = Self.privacyContext(for: record)
            return ApprovalRequest(
                id: record.id,
                kind: kind,
                agent: agent,
                operation: Self.mapOperation(record.action, kind: kind, privacyContext: privacyContext),
                target: record.path,
                headline: Self.headline(for: agent, record: record, privacyContext: privacyContext),
                context: Self.context(for: agent, record: record, privacyContext: privacyContext),
                findingsSummary: privacyContext?.findingsSummary,
                recommendation: privacyContext?.recommendation,
                createdAt: Date(timeIntervalSince1970: record.requestedAt),
                snoozedUntil: nil,
                redactedPreview: privacyContext?.redactedPreview,
                matchedCategories: privacyContext?.matchedCategories ?? [],
                severity: privacyContext.map { Self.inferredSeverity(for: $0.matchedCategories) }
            )
        }
    }

    // MARK: - Approval mapping helpers

    private static func mapOperation(
        _ action: String,
        kind: ApprovalRequest.Kind,
        privacyContext: PrivacyApprovalContext?
    ) -> ApprovalRequest.Operation {
        if kind == .privacyExposure {
            if privacyContext?.contentKind == .email {
                return .mailboxRead
            }
            return .readFile
        }
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

    private static func headline(
        for agent: TargetApp,
        record: PendingApprovalRecord,
        privacyContext: PrivacyApprovalContext?
    ) -> String {
        let name = agent == .codex ? "Codex" : "Claude"
        switch record.kind {
        case "standing_write":
            return "\(name) wants reversible write access."
        case "privacy_exposure":
            let content = privacyContext?.contentKind.displayName.lowercased() ?? "content"
            return "\(name) needs privacy review before sharing \(content)."
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

    private static func context(
        for agent: TargetApp,
        record: PendingApprovalRecord,
        privacyContext: PrivacyApprovalContext?
    ) -> String {
        switch record.kind {
        case "standing_write":
            let mountLabel = record.mountName ?? "shared folder"
            var parts = ["Writes to \(mountLabel) are governed by Manifold snapshots and can be restored from version history."]
            if let context = standingWriteContext(for: record) {
                if let tool = context["tool"], !tool.isEmpty {
                    parts.append("Tool: \(tool).")
                }
                if let bytes = context["bytes"], !bytes.isEmpty {
                    parts.append("Size: \(bytes) bytes.")
                }
                if let mime = context["mime_type"], !mime.isEmpty {
                    parts.append("Type: \(mime).")
                }
                if let mode = context["write_mode"], !mode.isEmpty {
                    parts.append("Requested mode: \(mode).")
                }
                if let intent = context["intent_summary"], !intent.isEmpty {
                    parts.append("Intent: \(intent)")
                }
            }
            return parts.joined(separator: " ")
        case "privacy_exposure":
            if let privacyContext {
                return "\(privacyContext.findingsSummary). \(privacyContext.recommendation)"
            }
            return "Privacy Preflight flagged this payload for review."
        default:
            return "Requested outside this \(agent == .codex ? "Codex" : "Claude") session's scope. Answer or ignore."
        }
    }

    /// Severity is not persisted on `PrivacyApprovalContext`; derive from the
    /// matched category taxonomy so the approval UI can paint a bar. Mirrors
    /// the heuristic used by `PrivacyDecisionEngine` when classifying spans.
    private static func inferredSeverity(for categories: [PrivacyCategory]) -> PrivacySeverity {
        if categories.contains(.secret) { return .critical }
        if categories.contains(.accountNumber) { return .high }
        if categories.contains(where: { [.privatePerson, .email, .phone, .address].contains($0) }) {
            return .medium
        }
        if categories.isEmpty { return .none }
        return .low
    }

    private static func privacyContext(for record: PendingApprovalRecord) -> PrivacyApprovalContext? {
        guard let raw = record.contextJSON,
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(PrivacyApprovalContext.self, from: data)
    }

    private static func standingWriteContext(for record: PendingApprovalRecord) -> [String: String]? {
        guard record.kind == "standing_write",
              let raw = record.contextJSON,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return object
    }

    /// Recent sessions, most recent first. The app-level store supplies
    /// runtime-backed history; this policy-only model has no session client.
    var recentSessions: [SessionHistoryEntry] { [] }

    /// Compute drift between a past session and current scope state.
    /// Policy-only callers get a neutral drift; app-level history uses the
    /// runtime-backed store path.
    func drift(for entry: SessionHistoryEntry) -> SessionDrift {
        SessionDrift(
            historyEntry: entry,
            pathsChangedSinceEnded: [],
            pathsRevokedSinceEnded: [],
            newlyAddedSinceEnded: []
        )
    }
}
