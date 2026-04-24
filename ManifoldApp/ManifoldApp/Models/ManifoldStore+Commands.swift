// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ManifoldStore+Commands — ManifoldCommands default implementation.
//
// Routes every write-path operation through the existing store and
// runtime so the XPC boundary stays single-source (CLAUDE.md §Editing
// Rules). Views should inject `store as any ManifoldCommands` — never
// reach into runtime internals directly.

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
        try await startProtectedRun(draft: draft)
    }

    func previewProtectedRun(draft: SessionDraft) async throws {
        let target = draft.agents.first ?? .cowork
        session.previewError = nil
        await session.computePreview(targetApp: target)
        if let error = session.previewError {
            throw StoreCommandError.message(error)
        }
        await refreshAll()
    }

    func startProtectedRun(draft: SessionDraft) async throws {
        let target = draft.agents.first ?? .cowork
        var capturedError: String?
        await session.startSession(
            targetApp: target,
            summaryFraming: draft.name.trimmedNilIfEmpty,
            noteCaptureMode: draft.trackWrites ? .basic : .off,
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

    func reloadSession(historyID: String) async throws {
        logger.info("reloadSession(\(historyID)): preview-only surface, runtime pipeline not wired")
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
        logger.info("createRule(\(rule.id)): preview-only Rules surface")
    }

    func setRule(_ ruleID: String, enabled: Bool) async throws {
        logger.info("setRule(\(ruleID), \(enabled)): preview-only Rules surface")
    }

    func deleteRule(_ ruleID: String) async throws {
        logger.info("deleteRule(\(ruleID)): preview-only Rules surface")
    }

    // MARK: - Revert

    func revert(filePath: String, toSnapshot: String) async -> RevertOutcome {
        // Phase 1: shape-only. Phase 2 (Activity) + Phase 3 (Access Files)
        // wire to the real revertFile / forceRevertFile paths.
        .error(message: "Revert surfaces land in Phase 2 (Activity).")
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

private extension String {
    var trimmedNilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
