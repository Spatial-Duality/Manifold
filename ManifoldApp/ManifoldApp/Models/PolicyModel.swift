import Foundation
import ManifoldKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "policy-model")

@Observable
@MainActor
final class PolicyModel {
    var claudePolicy: AgentAccessPolicy?
    var codexPolicy: AgentAccessPolicy?
    var activeWorkBlock: WorkBlockRecord?

    private var client: AppRuntimeClient?

    init() {}

    func configure(client: AppRuntimeClient) {
        self.client = client
    }

    func loadPolicies() async {
        guard let client else { return }
        do {
            let state = try await client.policies()
            claudePolicy = state.claudePolicy
            codexPolicy = state.codexPolicy
            activeWorkBlock = state.activeWorkBlock
        } catch {
            logger.error("Failed to load policies: \(error.localizedDescription)")
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

    func addEmailDomain(_ domain: String, to agent: TargetApp) async {
        guard let client else { return }
        do {
            try await client.addEmailDomain(domain, to: agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to add domain: \(error.localizedDescription)")
        }
    }

    func removeEmailDomain(_ domain: String, from agent: TargetApp) async {
        guard let client else { return }
        do {
            try await client.removeEmailDomain(domain, from: agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to remove domain: \(error.localizedDescription)")
        }
    }

    func updateSensitivity(_ level: EmailSensitivityLevel, for agent: TargetApp) async {
        guard let client else { return }
        do {
            try await client.updateSensitivity(level, for: agent)
            await loadPolicies()
        } catch {
            logger.error("Failed to update sensitivity: \(error.localizedDescription)")
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

    var isAnyAgentPaused: Bool {
        (claudePolicy?.isPaused ?? false) || (codexPolicy?.isPaused ?? false)
    }
}
