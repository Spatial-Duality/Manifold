import Foundation
import os

private let emailRuleLogger = Logger(subsystem: "com.spatialduality.manifold", category: "email-rules")

public actor EmailRuleStore {
    private let db: DatabaseConnection
    private let policyStore: PolicyStore

    public init(db: DatabaseConnection, policyStore: PolicyStore) {
        self.db = db
        self.policyStore = policyStore
    }

    public func ruleSet(for agent: TargetApp) async throws -> EmailRuleSet {
        let policy = try await policyStore.policy(for: agent)
        let shields = try shieldStates(for: agent)
        let domains = try domainRules(for: agent)
        let contacts = try contactRules(for: agent)
        let keywords = try keywordRules(for: agent)
        return EmailRuleSet(
            agent: agent,
            shields: shields,
            domainRules: domains,
            contactRules: contacts,
            keywordRules: keywords,
            defaultPolicy: policy.defaultEmailPolicy,
            emailSensitivity: policy.emailSensitivity
        )
    }

    public func updateRuleSet(_ ruleSet: EmailRuleSet) async throws {
        try validate(ruleSet)
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.transaction {
            try db.execute("DELETE FROM email_shield_states WHERE agent = ?", params: [ruleSet.agent.rawValue])
            try db.execute("DELETE FROM email_domain_rules WHERE agent = ?", params: [ruleSet.agent.rawValue])
            try db.execute("DELETE FROM email_contact_rules WHERE agent = ?", params: [ruleSet.agent.rawValue])
            try db.execute("DELETE FROM email_keyword_rules WHERE agent = ?", params: [ruleSet.agent.rawValue])

            for shield in normalizedShields(ruleSet.shields) {
                try db.execute(
                    """
                    INSERT INTO email_shield_states (agent, shield_id, is_enabled, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    params: [ruleSet.agent.rawValue, shield.shieldID, shield.isEnabled ? "1" : "0", now]
                )
            }

            for rule in normalizedDomainRules(ruleSet.domainRules, agent: ruleSet.agent, now: now) {
                try db.execute(
                    """
                    INSERT INTO email_domain_rules (rule_id, agent, domain, action, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    params: [rule.id, rule.agent.rawValue, rule.domain, rule.action.rawValue, rule.createdAt, rule.updatedAt]
                )
            }

            for rule in normalizedContactRules(ruleSet.contactRules, agent: ruleSet.agent, now: now) {
                try db.execute(
                    """
                    INSERT INTO email_contact_rules (rule_id, agent, display_name, email, action, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    params: [rule.id, rule.agent.rawValue, rule.name, rule.email, rule.action.rawValue, rule.createdAt, rule.updatedAt]
                )
            }

            for rule in normalizedKeywordRules(ruleSet.keywordRules, agent: ruleSet.agent, now: now) {
                try db.execute(
                    """
                    INSERT INTO email_keyword_rules (rule_id, agent, pattern, match_location, action, is_regex, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    params: [
                        rule.id,
                        rule.agent.rawValue,
                        rule.pattern,
                        rule.matchLocation.rawValue,
                        rule.action.rawValue,
                        rule.isRegex ? "1" : "0",
                        rule.createdAt,
                        rule.updatedAt,
                    ]
                )
            }
        }

        try await policyStore.updateDefaultEmailPolicy(ruleSet.defaultPolicy, for: ruleSet.agent)
        try await policyStore.updateSensitivity(ruleSet.emailSensitivity, for: ruleSet.agent)
        let allowedDomains = Set(
            normalizedDomainRules(ruleSet.domainRules, agent: ruleSet.agent, now: nil)
                .filter { $0.action == .allow }
                .map(\.domain)
        )
        try await policyStore.updateAllowedEmailDomains(allowedDomains, for: ruleSet.agent)
        emailRuleLogger.info("Updated email rule set for \(ruleSet.agent.rawValue)")
    }

    public func emailGovernanceSummary(for agent: TargetApp) async throws -> AgentEmailGovernanceSummary {
        let ruleSet = try await ruleSet(for: agent)
        return AgentEmailGovernanceSummary(
            agent: agent,
            enabledShieldCount: ruleSet.shields.filter(\.isEnabled).count,
            domainRuleCount: ruleSet.domainRules.count,
            contactRuleCount: ruleSet.contactRules.count,
            keywordRuleCount: ruleSet.keywordRules.count,
            defaultPolicy: ruleSet.defaultPolicy,
            emailSensitivity: ruleSet.emailSensitivity
        )
    }

    public func upsertDomainRule(
        agent: TargetApp,
        domain: String,
        action: EmailRuleAction = .allow
    ) async throws {
        var ruleSet = try await ruleSet(for: agent)
        let normalized = normalizedDomain(domain)
        ruleSet.domainRules.removeAll { normalizedDomain($0.domain) == normalized }
        ruleSet.domainRules.append(
            EmailDomainRule(agent: agent, domain: normalized, action: action)
        )
        try await updateRuleSet(ruleSet)
    }

    public func removeDomainRule(agent: TargetApp, domain: String) async throws {
        var ruleSet = try await ruleSet(for: agent)
        let normalized = normalizedDomain(domain)
        ruleSet.domainRules.removeAll { normalizedDomain($0.domain) == normalized }
        try await updateRuleSet(ruleSet)
    }

    private func shieldStates(for agent: TargetApp) throws -> [EmailShieldState] {
        let rows = try db.queryAll(
            "SELECT shield_id, is_enabled FROM email_shield_states WHERE agent = ? ORDER BY shield_id ASC",
            params: [agent.rawValue]
        )
        let enabledByID = rows.reduce(into: [String: Bool]()) { result, row in
            guard let shieldID = row["shield_id"] else { return }
            result[shieldID] = row["is_enabled"] == "1"
        }
        return EmailShieldCatalog.defaults(enabledByDefault: true).map { shield in
            var next = shield
            if let enabled = enabledByID[shield.shieldID] {
                next.isEnabled = enabled
            }
            return next
        }
    }

    private func domainRules(for agent: TargetApp) throws -> [EmailDomainRule] {
        let rows = try db.queryAll(
            "SELECT * FROM email_domain_rules WHERE agent = ? ORDER BY domain ASC",
            params: [agent.rawValue]
        )
        return rows.compactMap { row in
            guard let id = row["rule_id"],
                  let domain = row["domain"],
                  let actionRaw = row["action"],
                  let action = EmailRuleAction(rawValue: actionRaw),
                  let createdAt = row["created_at"],
                  let updatedAt = row["updated_at"] else {
                return nil
            }
            return EmailDomainRule(
                id: id,
                agent: agent,
                domain: domain,
                action: action,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private func contactRules(for agent: TargetApp) throws -> [EmailContactRule] {
        let rows = try db.queryAll(
            "SELECT * FROM email_contact_rules WHERE agent = ? ORDER BY email ASC",
            params: [agent.rawValue]
        )
        return rows.compactMap { row in
            guard let id = row["rule_id"],
                  let email = row["email"],
                  let actionRaw = row["action"],
                  let action = EmailRuleAction(rawValue: actionRaw),
                  let createdAt = row["created_at"],
                  let updatedAt = row["updated_at"] else {
                return nil
            }
            return EmailContactRule(
                id: id,
                agent: agent,
                name: row["display_name"] ?? "",
                email: email,
                action: action,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private func keywordRules(for agent: TargetApp) throws -> [EmailKeywordRule] {
        let rows = try db.queryAll(
            "SELECT * FROM email_keyword_rules WHERE agent = ? ORDER BY pattern ASC",
            params: [agent.rawValue]
        )
        return rows.compactMap { row in
            guard let id = row["rule_id"],
                  let pattern = row["pattern"],
                  let matchLocationRaw = row["match_location"],
                  let matchLocation = EmailKeywordMatchLocation(rawValue: matchLocationRaw),
                  let actionRaw = row["action"],
                  let action = EmailRuleAction(rawValue: actionRaw),
                  let createdAt = row["created_at"],
                  let updatedAt = row["updated_at"] else {
                return nil
            }
            return EmailKeywordRule(
                id: id,
                agent: agent,
                pattern: pattern,
                matchLocation: matchLocation,
                action: action,
                isRegex: row["is_regex"] == "1",
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private func validate(_ ruleSet: EmailRuleSet) throws {
        var seenDomains = Set<String>()
        for rule in normalizedDomainRules(ruleSet.domainRules, agent: ruleSet.agent, now: nil) {
            guard rule.domain.contains(".") else {
                throw EmailRuleValidationError.invalidDomain(rule.domain)
            }
            guard seenDomains.insert(rule.domain).inserted else {
                throw EmailRuleValidationError.duplicateDomain(rule.domain)
            }
        }

        var seenContacts = Set<String>()
        for rule in normalizedContactRules(ruleSet.contactRules, agent: ruleSet.agent, now: nil) {
            guard rule.email.contains("@"), rule.email.contains(".") else {
                throw EmailRuleValidationError.invalidContactEmail(rule.email)
            }
            guard seenContacts.insert(rule.email).inserted else {
                throw EmailRuleValidationError.duplicateContact(rule.email)
            }
        }

        var seenKeywords = Set<String>()
        for rule in normalizedKeywordRules(ruleSet.keywordRules, agent: ruleSet.agent, now: nil) {
            guard !rule.pattern.isEmpty else {
                throw EmailRuleValidationError.emptyKeywordPattern
            }
            let key = "\(rule.pattern.lowercased())|\(rule.matchLocation.rawValue)|\(rule.isRegex)"
            guard seenKeywords.insert(key).inserted else {
                throw EmailRuleValidationError.duplicateKeyword(rule.pattern)
            }
        }

        for shield in ruleSet.shields {
            guard EmailShieldCatalog.contains(shield.shieldID) else {
                throw EmailRuleValidationError.unknownShield(shield.shieldID)
            }
        }
    }

    private func normalizedShields(_ shields: [EmailShieldState]) -> [EmailShieldState] {
        let requested = Dictionary(uniqueKeysWithValues: shields.map { ($0.shieldID, $0.isEnabled) })
        return EmailShieldCatalog.defaults(enabledByDefault: true).map { shield in
            var next = shield
            if let enabled = requested[shield.shieldID] {
                next.isEnabled = enabled
            }
            return next
        }
    }

    private func normalizedDomainRules(_ rules: [EmailDomainRule], agent: TargetApp, now: String?) -> [EmailDomainRule] {
        rules.map { rule in
            let domain = normalizedDomain(rule.domain)
            return EmailDomainRule(
                id: rule.id,
                agent: agent,
                domain: domain,
                action: rule.action,
                createdAt: rule.createdAt,
                updatedAt: now ?? rule.updatedAt
            )
        }
    }

    private func normalizedContactRules(_ rules: [EmailContactRule], agent: TargetApp, now: String?) -> [EmailContactRule] {
        rules.map { rule in
            EmailContactRule(
                id: rule.id,
                agent: agent,
                name: rule.name.trimmingCharacters(in: .whitespacesAndNewlines),
                email: rule.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                action: rule.action,
                createdAt: rule.createdAt,
                updatedAt: now ?? rule.updatedAt
            )
        }
    }

    private func normalizedKeywordRules(_ rules: [EmailKeywordRule], agent: TargetApp, now: String?) -> [EmailKeywordRule] {
        rules.map { rule in
            EmailKeywordRule(
                id: rule.id,
                agent: agent,
                pattern: rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines),
                matchLocation: rule.matchLocation,
                action: rule.action,
                isRegex: rule.isRegex,
                createdAt: rule.createdAt,
                updatedAt: now ?? rule.updatedAt
            )
        }
    }

    private func normalizedDomain(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
    }
}
