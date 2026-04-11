import Foundation
import os
import ManifoldKit

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "policy-model")

/// @Observable model for managing AgentAccessPolicy per agent.
/// Wraps PolicyStore actor with @MainActor-safe observable properties.
@Observable
@MainActor
final class PolicyModel {
    var claudePolicy: AgentAccessPolicy?
    var codexPolicy: AgentAccessPolicy?
    var activeWorkBlock: WorkBlockRecord?

    private var policyStore: PolicyStore?
    private var workBlockStore: WorkBlockStore?

    init() {}

    func configure(policyStore: PolicyStore, workBlockStore: WorkBlockStore) {
        self.policyStore = policyStore
        self.workBlockStore = workBlockStore
    }

    // MARK: - Loading

    func loadPolicies() async {
        guard let store = policyStore else { return }
        do {
            claudePolicy = try await store.policy(for: .cowork)
            codexPolicy = try await store.policy(for: .codex)
        } catch {
            logger.error("Failed to load policies: \(error.localizedDescription)")
        }
    }

    func loadActiveWorkBlock() async {
        guard let store = workBlockStore else { return }
        do {
            activeWorkBlock = try await store.anyActiveBlock()
        } catch {
            logger.error("Failed to load work block: \(error.localizedDescription)")
        }
    }

    // MARK: - Policy Actions

    func pauseAgent(_ agent: TargetApp) async {
        guard let store = policyStore else { return }
        do {
            try await store.pauseAgent(agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to pause \(agent.rawValue): \(error.localizedDescription)")
        }
    }

    func resumeAgent(_ agent: TargetApp) async {
        guard let store = policyStore else { return }
        do {
            try await store.resumeAgent(agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to resume \(agent.rawValue): \(error.localizedDescription)")
        }
    }

    func addSource(_ sourceID: String, to agent: TargetApp) async {
        guard let store = policyStore else { return }
        do {
            try await store.addSource(sourceID, to: agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to add source: \(error.localizedDescription)")
        }
    }

    /// Pause all agents at once — the panic control.
    func pauseAllAgents() async {
        if claudePolicy?.isPaused != true { await pauseAgent(.cowork) }
        if codexPolicy?.isPaused != true { await pauseAgent(.codex) }
    }

    func removeSource(_ sourceID: String, from agent: TargetApp) async {
        guard let store = policyStore else { return }
        do {
            try await store.removeSource(sourceID, from: agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to remove source: \(error.localizedDescription)")
        }
    }

    // MARK: - Email Domain Actions

    func addEmailDomain(_ domain: String, to agent: TargetApp) async {
        guard let store = policyStore else { return }
        do {
            try await store.addEmailDomain(domain, to: agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to add domain: \(error.localizedDescription)")
        }
    }

    func removeEmailDomain(_ domain: String, from agent: TargetApp) async {
        guard let store = policyStore else { return }
        do {
            try await store.removeEmailDomain(domain, from: agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to remove domain: \(error.localizedDescription)")
        }
    }

    func updateSensitivity(_ level: EmailSensitivityLevel, for agent: TargetApp) async {
        guard let store = policyStore else { return }
        do {
            try await store.updateSensitivity(level, for: agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to update sensitivity: \(error.localizedDescription)")
        }
    }

    // MARK: - Work Block Actions

    /// Marks the work block as reviewing. The caller should then present
    /// the Review Changes sheet with PromoteEngine.dryRun() results.
    /// Call `completeWorkBlock()` after the user confirms promotion.
    func finishWorkBlock() async {
        guard let store = workBlockStore, let block = activeWorkBlock else { return }
        do {
            try await store.markReviewing(id: block.id)
            await loadActiveWorkBlock()
            // ReviewChangesSheet is presented by the caller (MainView)
            // based on activeWorkBlock?.status == .reviewing
        } catch {
            logger.error("Failed to finish work block: \(error.localizedDescription)")
        }
    }

    /// Complete a reviewed work block after user confirms promotion.
    func completeWorkBlock() async {
        guard let store = workBlockStore, let block = activeWorkBlock else { return }
        do {
            try await store.endBlock(id: block.id, status: .promoted)
            activeWorkBlock = nil
        } catch {
            logger.error("Failed to complete work block: \(error.localizedDescription)")
        }
    }

    func pauseWorkBlock() async {
        guard let store = workBlockStore, let block = activeWorkBlock else { return }
        do {
            if block.isPaused {
                try await store.resumeBlock(id: block.id)
            } else {
                try await store.pauseBlock(id: block.id)
            }
            await loadActiveWorkBlock()
        } catch {
            logger.error("Failed to pause/resume work block: \(error.localizedDescription)")
        }
    }

    func stopWorkBlock() async {
        guard let store = workBlockStore, let block = activeWorkBlock else { return }
        do {
            try await store.endBlock(id: block.id, status: .discarded)
            activeWorkBlock = nil
        } catch {
            logger.error("Failed to stop work block: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    func policy(for agent: TargetApp) -> AgentAccessPolicy? {
        agent == .codex ? codexPolicy : claudePolicy
    }

    var isAnyAgentPaused: Bool {
        (claudePolicy?.isPaused ?? false) || (codexPolicy?.isPaused ?? false)
    }
}
