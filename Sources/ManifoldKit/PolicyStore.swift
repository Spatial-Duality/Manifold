import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "policy")

/// Manages persistent standing access policies per agent.
/// Each agent has exactly one policy that controls what files and emails it can access.
/// Policies persist across connections and app restarts.
public actor PolicyStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    // MARK: - Policy CRUD

    /// Get the policy for an agent. Creates a default (empty) policy if none exists.
    public func policy(for agent: TargetApp) throws -> AgentAccessPolicy {
        let rows = try db.queryAll(
            "SELECT * FROM agent_access_policies WHERE agent = ? LIMIT 1",
            params: [agent.rawValue]
        )
        if let row = rows.first, let policy = AgentAccessPolicy(row: row) {
            return policy
        }
        // Create default empty policy
        let policy = AgentAccessPolicy(agent: agent)
        try insertPolicy(policy)
        return policy
    }

    /// Get all policies.
    public func allPolicies() throws -> [AgentAccessPolicy] {
        let rows = try db.queryAll(
            "SELECT * FROM agent_access_policies ORDER BY agent"
        )
        return rows.compactMap { AgentAccessPolicy(row: $0) }
    }

    /// Update an existing policy. Overwrites all fields.
    public func updatePolicy(_ policy: AgentAccessPolicy) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute("""
            UPDATE agent_access_policies
            SET allowed_source_ids = ?, allowed_email_domains = ?,
                email_sensitivity = ?, default_email_policy = ?, access_recording_level = ?, is_paused = ?, has_completed_first_grant = ?,
                updated_at = ?
            WHERE policy_id = ?
        """, params: [
            policy.encodeSourceIDs(),
            policy.encodeDomains(),
            policy.emailSensitivity.rawValue,
            policy.defaultEmailPolicy.rawValue,
            policy.accessRecordingLevel.rawValue,
            policy.isPaused ? "1" : "0",
            policy.hasCompletedFirstGrant ? "1" : "0",
            now,
            policy.id,
        ])
        logger.info("Updated policy \(policy.id) for \(policy.agent.rawValue)")
    }

    // MARK: - Convenience Methods

    /// Add a source to an agent's allowed list.
    public func addSource(_ sourceID: String, to agent: TargetApp) throws {
        var policy = try policy(for: agent)
        policy.allowedSourceIDs.insert(sourceID)
        policy.hasCompletedFirstGrant = true
        try updatePolicy(policy)
    }

    /// Remove a source from an agent's allowed list.
    public func removeSource(_ sourceID: String, from agent: TargetApp) throws {
        var policy = try policy(for: agent)
        policy.allowedSourceIDs.remove(sourceID)
        try updatePolicy(policy)
    }

    /// Add an email domain to an agent's allowed list.
    public func addEmailDomain(_ domain: String, to agent: TargetApp) throws {
        var policy = try policy(for: agent)
        policy.allowedEmailDomains.insert(domain.lowercased())
        policy.hasCompletedFirstGrant = true
        try updatePolicy(policy)
    }

    /// Remove an email domain from an agent's allowed list.
    public func removeEmailDomain(_ domain: String, from agent: TargetApp) throws {
        var policy = try policy(for: agent)
        policy.allowedEmailDomains.remove(domain.lowercased())
        try updatePolicy(policy)
    }

    /// Update email sensitivity for an agent.
    public func updateSensitivity(_ level: EmailSensitivityLevel, for agent: TargetApp) throws {
        var policy = try policy(for: agent)
        policy.emailSensitivity = level
        try updatePolicy(policy)
    }

    /// Update default email policy for an agent.
    public func updateDefaultEmailPolicy(_ defaultPolicy: EmailDefaultPolicy, for agent: TargetApp) throws {
        var policy = try policy(for: agent)
        policy.defaultEmailPolicy = defaultPolicy
        try updatePolicy(policy)
    }

    /// Replace the compatibility domain list for an agent.
    public func updateAllowedEmailDomains(_ domains: Set<String>, for agent: TargetApp) throws {
        var policy = try policy(for: agent)
        policy.allowedEmailDomains = Set(domains.map { $0.lowercased() })
        try updatePolicy(policy)
    }

    /// Update access recording level for an agent.
    public func updateAccessRecordingLevel(_ level: AccessRecordingLevel, for agent: TargetApp) throws {
        var policy = try policy(for: agent)
        policy.accessRecordingLevel = level
        try updatePolicy(policy)
    }

    /// Pause all access for an agent. Immediate, no confirmation needed.
    public func pauseAgent(_ agent: TargetApp) throws {
        var policy = try policy(for: agent)
        policy.isPaused = true
        try updatePolicy(policy)
        logger.info("Paused access for \(agent.rawValue)")
    }

    /// Resume access for a paused agent.
    public func resumeAgent(_ agent: TargetApp) throws {
        var policy = try policy(for: agent)
        policy.isPaused = false
        try updatePolicy(policy)
        logger.info("Resumed access for \(agent.rawValue)")
    }

    /// Check if a source is accessible by an agent (allowed and not paused).
    public func isSourceAccessible(_ sourceID: String, by agent: TargetApp) throws -> Bool {
        let policy = try policy(for: agent)
        return !policy.isPaused && policy.allowedSourceIDs.contains(sourceID)
    }

    /// Check if an email domain is accessible by an agent.
    public func isDomainAccessible(_ domain: String, by agent: TargetApp) throws -> Bool {
        let policy = try policy(for: agent)
        return !policy.isPaused && policy.allowedEmailDomains.contains(domain.lowercased())
    }

    // MARK: - Temporary Reveals

    /// Create a temporary email reveal for an agent.
    public func createTemporaryReveal(agent: TargetApp, emailID: String, workBlockID: String? = nil) throws -> TemporaryReveal {
        let reveal = TemporaryReveal(agent: agent, emailID: emailID, workBlockID: workBlockID)
        try db.execute("""
            INSERT INTO temporary_reveals (reveal_id, agent, email_id, work_block_id, created_at)
            VALUES (?, ?, ?, ?, ?)
        """, params: [reveal.id, agent.rawValue, emailID, workBlockID, reveal.createdAt])
        logger.info("Created temporary reveal \(reveal.id) for \(agent.rawValue)")
        return reveal
    }

    /// Get all active temporary reveals for an agent.
    public func temporaryReveals(for agent: TargetApp) throws -> [TemporaryReveal] {
        let rows = try db.queryAll(
            "SELECT * FROM temporary_reveals WHERE agent = ? ORDER BY created_at DESC",
            params: [agent.rawValue]
        )
        return rows.compactMap { TemporaryReveal(row: $0) }
    }

    /// Clear all temporary reveals for a work block (called when work block ends).
    public func clearReveals(forWorkBlock workBlockID: String) throws {
        try db.execute(
            "DELETE FROM temporary_reveals WHERE work_block_id = ?",
            params: [workBlockID]
        )
    }

    /// Clear all temporary reveals for an agent.
    public func clearAllReveals(for agent: TargetApp) throws {
        try db.execute(
            "DELETE FROM temporary_reveals WHERE agent = ?",
            params: [agent.rawValue]
        )
    }

    // MARK: - Private

    private func insertPolicy(_ policy: AgentAccessPolicy) throws {
        try db.execute("""
            INSERT INTO agent_access_policies (policy_id, agent, allowed_source_ids, allowed_email_domains,
                email_sensitivity, default_email_policy, access_recording_level, is_paused, has_completed_first_grant, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, params: [
            policy.id,
            policy.agent.rawValue,
            policy.encodeSourceIDs(),
            policy.encodeDomains(),
            policy.emailSensitivity.rawValue,
            policy.defaultEmailPolicy.rawValue,
            policy.accessRecordingLevel.rawValue,
            policy.isPaused ? "1" : "0",
            policy.hasCompletedFirstGrant ? "1" : "0",
            policy.createdAt,
            policy.updatedAt,
        ])
        logger.info("Created policy \(policy.id) for \(policy.agent.rawValue)")
    }
}
