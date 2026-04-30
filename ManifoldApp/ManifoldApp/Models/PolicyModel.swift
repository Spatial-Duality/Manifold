// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "governance-model")

@Observable
@MainActor
final class GovernanceModel {
    var claudePolicy: AgentAccessPolicy?
    var codexPolicy: AgentAccessPolicy?
    var claudeEmailGovernance: AgentEmailGovernanceSummary?
    var codexEmailGovernance: AgentEmailGovernanceSummary?
    var privacySettings: PrivacyPreflightSettings?
    var claudePrivacyPolicy: AgentPrivacyPolicy?
    var codexPrivacyPolicy: AgentPrivacyPolicy?
    var privacyRuntimeStatus: PrivacyRuntimeStatus?
    var privacyIndexStatus: PrivacyIndexRuntimeStatus?
    var privacyIdentitySuggestions: [PrivacyIdentitySuggestion] = []
    var privacyIdentities: [PrivacyIdentityRecord] = []
    var privacyOrgAllowEntries: [PrivacyOrgAllowEntry] = []
    var privacyRecentIndex: [PrivacyIndexRecord] = []
    var activeSessionRecord: WorkBlockRecord?
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
            activeSessionRecord = state.activeSession
            claudeCoverage = state.agentCoverages.first { $0.agent == TargetApp.cowork.rawValue }
            codexCoverage = state.agentCoverages.first { $0.agent == TargetApp.codex.rawValue }
            coverageEvents = state.coverageEvents
        } catch {
            logger.error("Failed to load policies: \(error.localizedDescription)")
        }
        do {
            let bundle = try await client.getPrivacySettings()
            privacySettings = bundle.settings
            claudePrivacyPolicy = bundle.claudePolicy
            codexPrivacyPolicy = bundle.codexPolicy
            privacyRuntimeStatus = try await client.privacyRuntimeStatus()
        } catch {
            logger.error("Failed to load privacy settings: \(error.localizedDescription)")
        }
        await loadPrivacyDiscovery()
        // Pull pending approvals. Failures here leave the list as-was so the
        // UI doesn't flicker on transient XPC hiccups — honest-state is
        // preserved by the LedgerStatusBar's runtime-connection indicator.
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

    func loadActiveSession() async {
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

    func resumeAllAgents() async {
        if claudePolicy?.isPaused == true { await resumeAgent(.cowork) }
        if codexPolicy?.isPaused == true { await resumeAgent(.codex) }
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

    func updateAccessRecordingLevel(_ level: AccessRecordingLevel, for agent: TargetApp) async {
        guard let client else { return }
        do {
            try await client.updateAccessRecordingLevel(level, for: agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to update access recording level: \(error.localizedDescription)")
        }
    }

    func updatePrivacySettings(_ settings: PrivacyPreflightSettings) async {
        guard let client else { return }
        do {
            try await client.updatePrivacySettings(settings: settings, policy: nil)
            privacyRuntimeStatus = try await client.privacyRuntimeStatus()
            await loadPolicies()
        } catch {
            logger.error("Failed to update privacy settings: \(error.localizedDescription)")
        }
    }

    func updatePrivacyPolicy(_ policy: AgentPrivacyPolicy) async {
        guard let client else { return }
        do {
            try await client.updatePrivacySettings(settings: nil, policy: policy)
            await loadPolicies()
        } catch {
            logger.error("Failed to update privacy policy: \(error.localizedDescription)")
        }
    }

    func installPrivacyRuntime(id: String = PrivacyRuntimeDefaults.mlxRuntimeID) async {
        guard let client else { return }
        do {
            privacyRuntimeStatus = try await client.installPrivacyRuntime(id: id)
            await loadPolicies()
        } catch {
            logger.error("Failed to install privacy scanner model: \(error.localizedDescription)")
        }
    }

    func uninstallPrivacyRuntime(id: String = PrivacyRuntimeDefaults.mlxRuntimeID) async {
        guard let client else { return }
        do {
            privacyRuntimeStatus = try await client.uninstallPrivacyRuntime(id: id)
            await loadPolicies()
        } catch {
            logger.error("Failed to uninstall privacy scanner model: \(error.localizedDescription)")
        }
    }

    func clearPrivacyCache() async {
        guard let client else { return }
        do {
            _ = try await client.clearPrivacyCache()
            privacyRuntimeStatus = try await client.privacyRuntimeStatus()
        } catch {
            logger.error("Failed to clear privacy cache: \(error.localizedDescription)")
        }
    }

    func loadPrivacyDiscovery() async {
        guard let client else { return }
        async let identities = tryFetch { try await client.listPrivacyIdentities() }
        async let allowlist = tryFetch { try await client.listPrivacyOrgAllowEntries() }
        async let suggestions = tryFetch { try await client.listPrivacyIdentitySuggestions() }
        async let indexStatus = tryFetch { try await client.privacyIndexStatus() }
        async let recentIndex = tryFetch {
            try await client.listPrivacyIndex(
                scope: PrivacyIndexScope(),
                filter: PrivacyIndexFilter(),
                limit: 50
            )
        }
        privacyIdentities = await identities ?? []
        privacyOrgAllowEntries = await allowlist ?? []
        privacyIdentitySuggestions = await suggestions ?? []
        privacyIndexStatus = await indexStatus
        privacyRecentIndex = await recentIndex ?? []
    }

    func acceptPrivacyIdentitySuggestion(id: String) async {
        guard let client else { return }
        do {
            try await client.acceptPrivacyIdentitySuggestion(id: id)
            await loadPrivacyDiscovery()
        } catch {
            logger.error("Failed to accept suggestion \(id): \(error.localizedDescription)")
        }
    }

    func rejectPrivacyIdentitySuggestion(id: String) async {
        guard let client else { return }
        do {
            try await client.rejectPrivacyIdentitySuggestion(id: id)
            await loadPrivacyDiscovery()
        } catch {
            logger.error("Failed to reject suggestion \(id): \(error.localizedDescription)")
        }
    }

    func upsertPrivacyIdentity(_ record: PrivacyIdentityRecord) async {
        guard let client else { return }
        do {
            try await client.upsertPrivacyIdentity(record)
            await loadPrivacyDiscovery()
        } catch {
            logger.error("Failed to upsert identity: \(error.localizedDescription)")
        }
    }

    func upsertPrivacyOrgAllowEntry(_ entry: PrivacyOrgAllowEntry) async {
        guard let client else { return }
        do {
            try await client.upsertPrivacyOrgAllowEntry(entry)
            await loadPrivacyDiscovery()
        } catch {
            logger.error("Failed to upsert allow entry: \(error.localizedDescription)")
        }
    }

    func deletePrivacyIdentity(id: String) async {
        guard let client else { return }
        do {
            try await client.deletePrivacyIdentity(id: id)
            await loadPrivacyDiscovery()
        } catch {
            logger.error("Failed to delete identity: \(error.localizedDescription)")
        }
    }

    func deletePrivacyOrgAllowEntry(id: String) async {
        guard let client else { return }
        do {
            try await client.deletePrivacyOrgAllowEntry(id: id)
            await loadPrivacyDiscovery()
        } catch {
            logger.error("Failed to delete allow entry: \(error.localizedDescription)")
        }
    }

    func rescanPrivacyContent(contentIDs: [String]) async {
        guard let client else { return }
        do {
            try await client.rescanPrivacyContent(contentIDs: contentIDs)
            await loadPrivacyDiscovery()
        } catch {
            logger.error("Failed to rescan privacy content: \(error.localizedDescription)")
        }
    }

    private func tryFetch<T>(_ op: @Sendable () async throws -> T) async -> T? {
        do { return try await op() } catch {
            logger.debug("Privacy discovery fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    func finishSession() async {
        guard let client, let block = activeSessionRecord else { return }
        do {
            try await client.markWorkBlockReviewing(id: block.id)
            await loadActiveSession()
        } catch {
            logger.error("Failed to finish session: \(error.localizedDescription)")
        }
    }

    func cancelReview() async {
        guard let client, let block = activeSessionRecord, block.status == .reviewing else { return }
        do {
            try await client.cancelWorkBlockReview(id: block.id)
            await loadActiveSession()
        } catch {
            logger.error("Failed to cancel review: \(error.localizedDescription)")
        }
    }

    func completeSession() async {
        guard let client, let block = activeSessionRecord else { return }
        do {
            try await client.endSession(grantID: block.grantID)
            await loadActiveSession()
        } catch {
            logger.error("Failed to complete session: \(error.localizedDescription)")
        }
    }

    func pauseSession() async {
        guard let client, let block = activeSessionRecord else { return }
        do {
            if block.isPaused {
                try await client.resumeGatewaySession(id: block.id)
            } else {
                try await client.pauseGatewaySession(id: block.id)
            }
            await loadActiveSession()
        } catch {
            logger.error("Failed to pause/resume session: \(error.localizedDescription)")
        }
    }

    func stopSession() async {
        guard let client, let block = activeSessionRecord else { return }
        do {
            try await client.endSession(grantID: block.grantID)
            await loadActiveSession()
        } catch {
            logger.error("Failed to stop session: \(error.localizedDescription)")
        }
    }

    func governance(for agent: TargetApp) -> AgentAccessPolicy? {
        agent == .codex ? codexPolicy : claudePolicy
    }

    /// Convenience alias — reads better at call sites like
    /// `store.governance.policy(for: agent)?.allowedSourceIDs`.
    func policy(for agent: TargetApp) -> AgentAccessPolicy? {
        governance(for: agent)
    }

    func coverage(for agent: TargetApp) -> AgentCoverageSnapshot? {
        agent == .codex ? codexCoverage : claudeCoverage
    }

    func emailGovernance(for agent: TargetApp) -> AgentEmailGovernanceSummary? {
        agent == .codex ? codexEmailGovernance : claudeEmailGovernance
    }

    func privacyPolicy(for agent: TargetApp) -> AgentPrivacyPolicy? {
        agent == .codex ? codexPrivacyPolicy : claudePrivacyPolicy
    }

    var isAnyAgentPaused: Bool {
        (claudePolicy?.isPaused ?? false) || (codexPolicy?.isPaused ?? false)
    }
}
