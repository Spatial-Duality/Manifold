// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "policy-model")

@Observable
@MainActor
final class PolicyModel {
    var claudePolicy: AgentAccessPolicy?
    var codexPolicy: AgentAccessPolicy?
    var claudeEmailGovernance: AgentEmailGovernanceSummary?
    var codexEmailGovernance: AgentEmailGovernanceSummary?
    var activeWorkBlock: WorkBlockRecord?
    var claudeCoverage: AgentCoverageSnapshot?
    var codexCoverage: AgentCoverageSnapshot?
    var coverageEvents: [CoverageEvent] = []
    /// Pending approval requests pulled from the runtime ApprovalQueue.
    /// Populated on every loadPolicies / refresh — if the runtime is
    /// unreachable the list empties out honestly (Principle 10).
    var pendingApprovals: [PendingApprovalRecord] = []

    private var client: (any RuntimeClientProtocol)?

    init() {}

    func configure(client: any RuntimeClientProtocol) {
        self.client = client
    }

    func loadPolicies() async {
        guard let client else { return }
        do {
            let state = try await client.policies()
            claudePolicy = state.claudePolicy
            codexPolicy = state.codexPolicy
            claudeEmailGovernance = state.claudeEmailGovernance
            codexEmailGovernance = state.codexEmailGovernance
            activeWorkBlock = state.activeWorkBlock
            claudeCoverage = state.agentCoverages.first { $0.agent == TargetApp.cowork.rawValue }
            codexCoverage = state.agentCoverages.first { $0.agent == TargetApp.codex.rawValue }
            coverageEvents = state.coverageEvents
        } catch {
            logger.error("Failed to load policies: \(error.localizedDescription)")
        }
        // Pull pending approvals. Failures here leave the list as-was so the
        // UI doesn't flicker on transient XPC hiccups — honest-state is
        // preserved by the StatusBar's runtime-connection indicator.
        do {
            pendingApprovals = try await client.listPendingApprovals()
        } catch {
            logger.error("Failed to load pending approvals: \(error.localizedDescription)")
        }
    }

    /// Answer a pending request. Maps UI ApprovalAnswer cases to the XPC
    /// answer string understood by the runtime's approval queue.
    func answerApproval(id: String, answer: String) async {
        guard let client else { return }
        do {
            try await client.answerApproval(id: id, answer: answer)
            await loadPolicies()
        } catch {
            logger.error("Failed to answer approval \(id): \(error.localizedDescription)")
        }
    }

    func loadActiveWorkBlock() async {
        await loadPolicies()
    }

    func pauseAgent(_ agent: TargetApp) async {
        guard let client else { return }
        do {
            try await client.pauseAgent(agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to pause \(agent.rawValue): \(error.localizedDescription)")
        }
    }

    func resumeAgent(_ agent: TargetApp) async {
        guard let client else { return }
        do {
            try await client.resumeAgent(agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to resume \(agent.rawValue): \(error.localizedDescription)")
        }
    }

    func addSource(_ sourceID: String, to agent: TargetApp) async {
        guard let client else { return }
        do {
            try await client.addSource(sourceID, to: agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to add source: \(error.localizedDescription)")
        }
    }

    func pauseAllAgents() async {
        if claudePolicy?.isPaused != true { await pauseAgent(.cowork) }
        if codexPolicy?.isPaused != true { await pauseAgent(.codex) }
    }

    func removeSource(_ sourceID: String, from agent: TargetApp) async {
        guard let client else { return }
        do {
            try await client.removeSource(sourceID, from: agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to remove source: \(error.localizedDescription)")
        }
    }

    /// Persist a per-node override (include / exclude / inherit) for a
    /// path within a source. `inherit` deletes any prior override so the
    /// node resumes inheriting from its source-level membership.
    func setNodeOverride(
        sourceID: String,
        relativePath: String,
        agent: TargetApp,
        state: NodeOverrideState
    ) async {
        guard let client else { return }
        do {
            try await client.setNodeOverride(
                sourceID: sourceID,
                relativePath: relativePath,
                agent: agent,
                state: state
            )
        } catch {
            logger.error("Failed to set node override: \(error.localizedDescription)")
        }
    }

    /// Fetch all persisted node overrides for a source. Returns an empty
    /// array on failure rather than throwing, so inspectors can surface
    /// "no overrides yet" honestly.
    func nodeOverrides(sourceID: String) async -> [NodeOverrideRecord] {
        guard let client else { return [] }
        do {
            return try await client.listNodeOverrides(sourceID: sourceID)
        } catch {
            logger.error("Failed to list node overrides: \(error.localizedDescription)")
            return []
        }
    }

    func clearNodeOverrides(sourceID: String, agent: TargetApp) async {
        guard let client else { return }
        do {
            try await client.clearNodeOverrides(sourceID: sourceID, agent: agent)
        } catch {
            logger.error("Failed to clear node overrides: \(error.localizedDescription)")
        }
    }

    /// The summary of the most recently reversed action, or nil when the
    /// last ⌘Z tried to undo an empty stack. Observed by UI so the status
    /// bar can flash a one-line "Undid: …" toast. Cleared by the view
    /// after display.
    var lastUndoSummary: UndoActionSummary?

    /// Reverse the most recent user-initiated grant/revoke/override. Runs
    /// on the runtime — we never undo locally. Refreshes policies afterward
    /// so the three-column Scope view reflects the new truth immediately.
    @discardableResult
    func undoLastAction() async -> UndoActionSummary? {
        guard let client else { return nil }
        do {
            let reversed = try await client.undoLastAction()
            lastUndoSummary = reversed
            await loadPolicies()
            return reversed
        } catch {
            logger.error("Undo failed: \(error.localizedDescription)")
            return nil
        }
    }

    func updateAccessRecordingLevel(_ level: AccessRecordingLevel, for agent: TargetApp) async {
        guard let client else { return }
        do {
            try await client.updateAccessRecordingLevel(level, for: agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to update access recording level: \(error.localizedDescription)")
        }
    }

    func finishWorkBlock() async {
        guard let client, let block = activeWorkBlock else { return }
        do {
            try await client.markWorkBlockReviewing(id: block.id)
            await loadActiveWorkBlock()
        } catch {
            logger.error("Failed to finish work block: \(error.localizedDescription)")
        }
    }

    func cancelReview() async {
        guard let client, let block = activeWorkBlock, block.status == .reviewing else { return }
        do {
            try await client.cancelWorkBlockReview(id: block.id)
            await loadActiveWorkBlock()
        } catch {
            logger.error("Failed to cancel review: \(error.localizedDescription)")
        }
    }

    func completeWorkBlock() async {
        guard let client, let block = activeWorkBlock else { return }
        do {
            _ = try await client.applyTrackedRun(grantID: block.grantID)
            await loadActiveWorkBlock()
        } catch {
            logger.error("Failed to complete work block: \(error.localizedDescription)")
        }
    }

    func pauseWorkBlock() async {
        guard let client, let block = activeWorkBlock else { return }
        do {
            if block.isPaused {
                try await client.resumeTrackedRun(id: block.id)
            } else {
                try await client.pauseTrackedRun(id: block.id)
            }
            await loadActiveWorkBlock()
        } catch {
            logger.error("Failed to pause/resume work block: \(error.localizedDescription)")
        }
    }

    func stopWorkBlock() async {
        guard let client, let block = activeWorkBlock else { return }
        do {
            try await client.discardTrackedRun(id: block.id, grantID: block.grantID)
            await loadActiveWorkBlock()
        } catch {
            logger.error("Failed to stop work block: \(error.localizedDescription)")
        }
    }

    func policy(for agent: TargetApp) -> AgentAccessPolicy? {
        agent == .codex ? codexPolicy : claudePolicy
    }

    func coverage(for agent: TargetApp) -> AgentCoverageSnapshot? {
        agent == .codex ? codexCoverage : claudeCoverage
    }

    func emailGovernance(for agent: TargetApp) -> AgentEmailGovernanceSummary? {
        agent == .codex ? codexEmailGovernance : claudeEmailGovernance
    }

    var isAnyAgentPaused: Bool {
        (claudePolicy?.isPaused ?? false) || (codexPolicy?.isPaused ?? false)
    }
}
