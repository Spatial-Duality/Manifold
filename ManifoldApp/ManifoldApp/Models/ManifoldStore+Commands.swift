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
        let xpcAnswer: String
        switch answer {
        case .notThisTime:        xpcAnswer = "notThisTime"
        case .once:               xpcAnswer = "once"
        case .forSession:         xpcAnswer = "session"
        case .addToDefault:       xpcAnswer = "default"
        }
        await policy.answerApproval(id: request.id, answer: xpcAnswer)
        // Keep the ScopeEntry promotion separate — the runtime records
        // the answer; promotion to default scope still needs a follow-up
        // `addSource(..., to: agent)` once the runtime wires the
        // answer→promotion bridge. For now the UI-level answer is
        // truthful: we stored the user's choice.
    }

    // MARK: - Sessions

    func startSession(_ draft: SessionDraft) async throws {
        // Phase 1: reuse the existing tracked-work-block primitive.
        // Naming / duration / agents will be honored when SessionStore
        // lands in a later phase.
        let target = draft.agents.first ?? .cowork
        await startSession(targetApp: target)
    }

    func finishActiveSession() async throws {
        await endSession()
    }

    func reloadSession(historyID: String) async throws {
        // Phase 1 stub — actual reload pipeline arrives in Phase 3 with
        // SessionHistory + drift computation. Intentionally no-op so call
        // sites compile and can be tested visually.
        logger.info("reloadSession(\(historyID)): pending Phase 3 SessionHistory")
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
        logger.info("createRule(\(rule.id)): pending Phase 6 Rules surface")
    }

    func setRule(_ ruleID: String, enabled: Bool) async throws {
        logger.info("setRule(\(ruleID), \(enabled)): pending Phase 6")
    }

    func deleteRule(_ ruleID: String) async throws {
        logger.info("deleteRule(\(ruleID)): pending Phase 6")
    }

    // MARK: - Revert

    func revert(filePath: String, toSnapshot: String) async -> RevertOutcome {
        // Phase 1: shape-only. Phase 2 (Activity) + Phase 3 (Access Files)
        // wire to the real revertFile / forceRevertFile paths.
        .error(message: "Revert surfaces land in Phase 2 (Activity).")
    }

    // MARK: - Agent lifecycle (bridges to PolicyModel)

    func pauseAgent(_ agent: TargetApp) async {
        await policy.pauseAgent(agent)
    }

    func resumeAgent(_ agent: TargetApp) async {
        await policy.resumeAgent(agent)
    }

    // MARK: - Read-surface convenience
    //
    // Forward PolicyModel's new primitives to the store so views that
    // take a store (or a ManifoldCommands) can read them from one place.

    var activeSession: SessionRecord? { policy.activeSession }
    var pendingRequests: [ApprovalRequest] { policy.pendingRequests }
    var recentSessionEntries: [SessionHistoryEntry] { policy.recentSessions }
    func drift(for entry: SessionHistoryEntry) -> SessionDrift { policy.drift(for: entry) }
}

// Module-scope logger used by the extension (ManifoldStore.swift declares
// its own for its file). Keeps this extension compile-clean.
private let logger = Logger(
    subsystem: "com.spatialduality.manifold",
    category: "store-commands"
)
