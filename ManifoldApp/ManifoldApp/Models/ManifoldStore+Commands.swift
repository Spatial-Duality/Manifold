// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ManifoldStore+Commands — ManifoldCommands default implementation.
//
// Routes every write-path operation through the existing store and
// runtime so the XPC boundary stays single-source. Views should inject
// `store as any ManifoldCommands` — never reach into runtime internals
// directly.

import Foundation
import os
import ManifoldKit

extension ManifoldStore: ManifoldCommands {

    // MARK: - Approvals

    func answer(_ request: ApprovalRequest, with answer: ApprovalAnswer) async {
        if case .forSession = answer, !request.supportsSessionScope {
            logger.error("Rejected unsupported session-scoped answer for request \(request.id, privacy: .public)")
            return
        }
        let xpcAnswer: String
        switch answer {
        case .notThisTime:        xpcAnswer = "notThisTime"
        case .once:               xpcAnswer = "once"
        case .forSession:         xpcAnswer = "session"
        case .addToDefault:       xpcAnswer = "default"
        case .shareRedacted:      xpcAnswer = "shareRedacted"
        case .shareOriginalOnce:  xpcAnswer = "shareOriginalOnce"
        }
        await governance.answerApproval(id: request.id, answer: xpcAnswer)
    }

    // MARK: - Sessions

    func startSession(_ draft: SessionDraft) async throws {
        try await startGatewaySession(draft: draft)
    }

    func previewSession(draft: SessionDraft) async throws {
        let target = draft.agents.first ?? .cowork
        session.previewError = nil
        await session.computePreview(
            targetApp: target,
            fileScopes: fileScopes(for: draft),
            selectedEmailIDs: draft.selectedEmailIDs
        )
        if let error = session.previewError {
            throw StoreCommandError.message(error)
        }
        await refreshAll()
    }

    func startGatewaySession(draft: SessionDraft) async throws {
        let target = draft.agents.first ?? .cowork
        var capturedError: String?
        await session.startSession(
            targetApp: target,
            fileScopes: fileScopes(for: draft),
            selectedEmailIDs: draft.selectedEmailIDs,
            summaryFraming: draft.name.trimmedNilIfEmpty,
            noteCaptureMode: draft.trackWrites ? .basic : .off,
            requestDetailOverride: draft.requestDetailOverride,
            allowFileMemory: draft.allowFileMemory,
            onError: { [weak self] message in
                capturedError = message
                self?.lastError = message
            }
        )
        if let capturedError {
            throw StoreCommandError.message(capturedError)
        }
        await refreshAll()
    }

    func finishActiveSession() async throws {
        await endSession()
    }

    private func fileScopes(for draft: SessionDraft) -> [FileSelectionScope] {
        guard draft.usesExplicitFileSelection else { return [] }
        return draft.selectedSourceIDs.sorted().map {
            FileSelectionScope(sourceID: $0, relativePath: "", isDirectory: true)
        }
    }

    func reloadSession(historyID: String) async throws {
        if activity.sessions.isEmpty {
            await activity.loadSessions()
        }
        guard let session = activity.sessions.first(where: { $0.id == historyID }) else {
            throw StoreCommandError.message("Session \(historyID) is no longer available.")
        }
        await activity.selectSession(session)
    }

    // MARK: - Scope

    func shareSource(path: String, with agent: TargetApp) async throws {
        addSource(path: path)
    }

    func revokeScope(entryID: String) async throws {
        if let source = sources.first(where: { $0.sourceID == entryID }) {
            removeSource(path: source.originalRootPath)
        }
    }

    // MARK: - Rules

    func createRule(_ rule: Rule) async throws {
        try await runtime.upsertRule(RuleRecord(legacyRule: rule))
        await rules.load()
    }

    func setRule(_ ruleID: String, enabled: Bool) async throws {
        try await runtime.setRuleEnabled(id: ruleID, enabled: enabled)
        await rules.load()
    }

    func deleteRule(_ ruleID: String) async throws {
        try await runtime.deleteRule(id: ruleID)
        await rules.load()
    }

    // MARK: - Revert

    func revert(filePath: String, toSnapshot: String) async -> RevertOutcome {
        let targetSnapshotID = Int(toSnapshot)
        guard let event = activity.sessionEvents.first(where: { event in
            guard event.filePath == filePath else { return false }
            if let targetSnapshotID {
                return event.snapshotID == targetSnapshotID
            }
            return event.afterHash == toSnapshot || event.beforeHash == toSnapshot
        }) else {
            return .missingSnapshot
        }

        switch await revertFile(event: event) {
        case .success:
            return .reverted(filePath: filePath, toVersion: toSnapshot)
        case .blobPruned:
            return .missingSnapshot
        case .contentDrift:
            return .conflictWithCurrentEdit
        case .error(let message):
            return .error(message: message)
        }
    }

    // MARK: - Agent lifecycle (bridges to GovernanceModel)

    func pauseAgent(_ agent: TargetApp) async {
        await governance.pauseAgent(agent)
    }

    func resumeAgent(_ agent: TargetApp) async {
        await governance.resumeAgent(agent)
    }

    // MARK: - Read-surface convenience
    //
    // Forward GovernanceModel's new primitives to the store so views that
    // take a store (or a ManifoldCommands) can read them from one place.

    var activeSession: SessionRecord? { governance.activeSession }
    var pendingRequests: [ApprovalRequest] { governance.pendingRequests }
    var recentSessionEntries: [SessionHistoryEntry] {
        (dataControlSummary?.recentHandoffSessions ?? activity.sessions)
            .compactMap(Self.historyEntry(from:))
    }
    func drift(for entry: SessionHistoryEntry) -> SessionDrift { governance.drift(for: entry) }

    private static func historyEntry(from session: Session) -> SessionHistoryEntry? {
        guard let startedAt = ISO8601DateFormatter.shared.date(from: session.startTime),
              let endedAt = ISO8601DateFormatter.shared.date(from: session.endTime) else {
            return nil
        }
        let agent = TargetApp(rawValue: session.agent).map { Set([$0]) } ?? []
        return SessionHistoryEntry(
            id: session.id,
            name: "\(session.agent.capitalized) session",
            startedAt: startedAt,
            endedAt: endedAt,
            agents: agent,
            eventCount: session.actionCount,
            additions: [],
            removals: []
        )
    }
}

// Module-scope logger used by the extension (ManifoldStore.swift declares
// its own for its file). Keeps this extension compile-clean.
private let logger = Logger(
    subsystem: "com.spatialduality.manifold",
    category: "store-commands"
)

private enum StoreCommandError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}

private extension RuleRecord {
    init(legacyRule rule: Rule) {
        self.init(
            id: rule.id,
            name: "\(rule.verb.rawValue.capitalized) \(rule.subject)",
            explanation: rule.object,
            scope: rule.domain.ruleScope,
            matcher: rule.domain.matcher(for: rule.pattern),
            action: rule.verb.ruleAction,
            source: rule.createdBy.ruleSource,
            enabled: rule.enabled,
            orderIndex: 100,
            createdAt: ISO8601DateFormatter.shared.string(from: rule.createdAt),
            updatedAt: ISO8601DateFormatter.shared.string(from: Date())
        )
    }
}

private extension Rule.Domain {
    var ruleScope: RuleScope {
        switch self {
        case .files: return .file
        case .email: return .email
        case .agents: return .agent
        }
    }

    func matcher(for pattern: String) -> RuleMatcher {
        let cleaned = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .files:
            return cleaned.isEmpty ? .always : .pathGlob(cleaned)
        case .email:
            return cleaned.isEmpty ? .always : .emailDomain(cleaned)
        case .agents:
            return .agentWrite
        }
    }
}

private extension Rule.Verb {
    var ruleAction: ManifoldKit.RuleAction {
        switch self {
        case .allow: return .allow
        case .deny: return .deny
        case .warn: return .warn
        }
    }
}

private extension Rule.CreatedBy {
    var ruleSource: RuleSource {
        switch self {
        case .user: return .user
        case .seeded: return .seeded
        case .suggested: return .suggested
        }
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
