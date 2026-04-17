// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import os

private let emailRulesLogger = Logger(subsystem: "com.spatialduality.manifold", category: "email-rules-model")

@Observable
@MainActor
final class EmailRulesModel {
    var selectedAgent: TargetApp = .cowork
    var shields: [EmailShield] = []
    var domainRules: [DomainRule] = []
    var contactRules: [ContactRule] = []
    var keywordRules: [KeywordRule] = []
    var defaultPolicy: AgentDefaultPolicy = .allowUnlessBlocked
    var emailSensitivity: EmailSensitivityLevel = .moderate
    var loading = false
    var errorMessage: String?

    private var client: (any RuntimeClientProtocol)?
    private var ruleSet: EmailRuleSet?
    private var activitySummary: EmailRuleActivitySummary?
    private var domainCounts: [String: Int] = [:]

    func configure(client: any RuntimeClientProtocol) {
        self.client = client
    }

    func load(agent: TargetApp) async {
        guard let client else { return }
        loading = true
        defer { loading = false }

        do {
            selectedAgent = agent
            async let ruleSet = client.getEmailRuleSet(agent: agent)
            async let summary = client.getEmailRuleActivitySummary(agent: agent)
            async let counts = client.domainCounts()
            let resolvedRuleSet = try await ruleSet
            let resolvedSummary = try await summary
            let resolvedCounts = try await counts
            self.ruleSet = resolvedRuleSet
            self.activitySummary = resolvedSummary
            self.domainCounts = resolvedCounts
            apply(ruleSet: resolvedRuleSet, summary: resolvedSummary, domainCounts: resolvedCounts)
            errorMessage = nil
        } catch {
            emailRulesLogger.error("Failed to load email rules: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func toggleShield(shieldID: String, isEnabled: Bool) async {
        guard var ruleSet else { return }
        if let index = ruleSet.shields.firstIndex(where: { $0.shieldID == shieldID }) {
            ruleSet.shields[index].isEnabled = isEnabled
            await persist(ruleSet)
        }
    }

    func addDomainRule(domain: String, action: RuleAction, category _: String) async {
        guard var ruleSet else { return }
        ruleSet.domainRules.append(
            EmailDomainRule(
                agent: selectedAgent,
                domain: domain,
                action: action.runtimeValue
            )
        )
        await persist(ruleSet)
    }

    func removeDomainRule(id: String) async {
        guard var ruleSet else { return }
        ruleSet.domainRules.removeAll { $0.id == id }
        await persist(ruleSet)
    }

    func addContactRule(name: String, email: String, action: RuleAction) async {
        guard var ruleSet else { return }
        ruleSet.contactRules.append(
            EmailContactRule(
                agent: selectedAgent,
                name: name,
                email: email,
                action: action.runtimeValue
            )
        )
        await persist(ruleSet)
    }

    func removeContactRule(id: String) async {
        guard var ruleSet else { return }
        ruleSet.contactRules.removeAll { $0.id == id }
        await persist(ruleSet)
    }

    func addKeywordRule(pattern: String, matchLocation: KeywordMatchLocation, action: RuleAction, isRegex: Bool) async {
        guard var ruleSet else { return }
        ruleSet.keywordRules.append(
            EmailKeywordRule(
                agent: selectedAgent,
                pattern: pattern,
                matchLocation: matchLocation.runtimeValue,
                action: action.runtimeValue,
                isRegex: isRegex
            )
        )
        await persist(ruleSet)
    }

    func removeKeywordRule(id: String) async {
        guard var ruleSet else { return }
        ruleSet.keywordRules.removeAll { $0.id == id }
        await persist(ruleSet)
    }

    func updateDefaultPolicy(_ governance: AgentDefaultPolicy) async {
        guard var ruleSet else { return }
        ruleSet.defaultPolicy = governance.runtimeValue
        await persist(ruleSet)
    }

    func updateSensitivity(_ sensitivity: EmailSensitivityLevel) async {
        guard var ruleSet else { return }
        ruleSet.emailSensitivity = sensitivity
        await persist(ruleSet)
    }

    private func persist(_ ruleSet: EmailRuleSet) async {
        guard let client else { return }
        do {
            try await client.updateEmailRuleSet(agent: selectedAgent, ruleSet: ruleSet)
            await load(agent: selectedAgent)
        } catch {
            emailRulesLogger.error("Failed to persist email rules: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private func apply(ruleSet: EmailRuleSet, summary: EmailRuleActivitySummary, domainCounts: [String: Int]) {
        let recentMatchesByShield = Dictionary(grouping: summary.recentShieldMatches, by: \.shieldID)
        let domainHitCounts = Dictionary(uniqueKeysWithValues: summary.domainRuleHits.map { ($0.ruleID, $0.count) })
        let contactHitCounts = Dictionary(uniqueKeysWithValues: summary.contactRuleHits.map { ($0.ruleID, $0.count) })
        let keywordHitCounts = Dictionary(uniqueKeysWithValues: summary.keywordRuleHits.map { ($0.ruleID, $0.count) })

        shields = ruleSet.shields.map { shield in
            EmailShield(
                id: shield.shieldID,
                name: shield.name,
                description: shield.description,
                isEnabled: shield.isEnabled,
                icon: shield.icon,
                domains: shield.domains,
                patterns: shield.patterns,
                blockedCount: summary.shieldBlockedCounts[shield.shieldID] ?? 0,
                recentMatches: (recentMatchesByShield[shield.shieldID] ?? []).map {
                    ShieldMatch(
                        id: UUID(),
                        subject: $0.subject,
                        from: $0.from,
                        date: ISO8601DateFormatter.shared.date(from: $0.date) ?? Date(),
                        agentBlocked: selectedAgent
                    )
                }
            )
        }

        domainRules = ruleSet.domainRules.map { rule in
            let normalizedDomain = rule.domain.lowercased()
            return DomainRule(
                id: rule.id,
                domain: normalizedDomain,
                action: RuleAction(runtimeValue: rule.action),
                category: EmailDomainCategorizer.categorize(domain: normalizedDomain).rawValue,
                emailCount: domainCounts[normalizedDomain] ?? 0,
                matchedCount: domainHitCounts[rule.id] ?? 0,
                shieldOverlap: shields.first(where: { shield in
                    shield.domains.contains { token in
                        normalizedDomain.contains(token.lowercased()) || token.lowercased().contains(normalizedDomain)
                    }
                })?.name
            )
        }

        contactRules = ruleSet.contactRules.map { rule in
            let domain = rule.email.split(separator: "@").last.map(String.init)?.lowercased() ?? ""
            let existingDomainRule = domainRules.first { $0.domain == domain }
            let overrides = existingDomainRule != nil
                ? "@\(domain) domain (\(existingDomainRule!.action.rawValue)) -> \(RuleAction(runtimeValue: rule.action).rawValue) for this contact"
                : "No existing domain or shield override"
            return ContactRule(
                id: rule.id,
                name: rule.name,
                email: rule.email,
                action: RuleAction(runtimeValue: rule.action),
                matchedCount: contactHitCounts[rule.id] ?? 0,
                overridesDescription: overrides
            )
        }

        keywordRules = ruleSet.keywordRules.map { rule in
            KeywordRule(
                id: rule.id,
                pattern: rule.pattern,
                matchLocation: KeywordMatchLocation(runtimeValue: rule.matchLocation),
                action: RuleAction(runtimeValue: rule.action),
                matchedCount: keywordHitCounts[rule.id] ?? 0,
                isRegex: rule.isRegex
            )
        }

        defaultPolicy = AgentDefaultPolicy(runtimeValue: ruleSet.defaultPolicy)
        emailSensitivity = ruleSet.emailSensitivity
    }
}

private enum EmailDomainCategory: String, CaseIterable, Sendable, Hashable {
    case work = "Work"
    case automated = "Automated"
    case personal = "Personal"
    case hidden = "Hidden by sensitivity"
}

private enum EmailDomainCategorizer {
    private static let automated = ["github.com", "circleci.com", "gitlab.com", "bitbucket.org",
                                    "linear.app", "notion.so", "slack.com", "vercel.com"]
    private static let personal = ["gmail.com", "yahoo.com", "hotmail.com", "outlook.com", "icloud.com",
                                   "protonmail.com", "fastmail.com"]

    static func categorize(domain: String, isHidden: Bool = false) -> EmailDomainCategory {
        if isHidden { return .hidden }
        if automated.contains(where: { domain.hasSuffix($0) }) { return .automated }
        if personal.contains(domain) { return .personal }
        return .work
    }
}

struct EmailShield: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    var isEnabled: Bool
    let icon: String
    let domains: [String]
    let patterns: [String]
    let blockedCount: Int
    let recentMatches: [ShieldMatch]
}

struct ShieldMatch: Identifiable, Sendable {
    let id: UUID
    let subject: String
    let from: String
    let date: Date
    let agentBlocked: TargetApp
}

struct DomainRule: Identifiable, Sendable {
    let id: String
    let domain: String
    var action: RuleAction
    let category: String
    let emailCount: Int
    let matchedCount: Int
    var shieldOverlap: String?
}

struct ContactRule: Identifiable, Sendable {
    let id: String
    let name: String
    let email: String
    var action: RuleAction
    let matchedCount: Int
    let overridesDescription: String
}

struct KeywordRule: Identifiable, Sendable {
    let id: String
    let pattern: String
    let matchLocation: KeywordMatchLocation
    var action: RuleAction
    var matchedCount: Int
    var isRegex: Bool
}

enum RuleAction: String, CaseIterable, Sendable {
    case allow
    case block

    init(runtimeValue: EmailRuleAction) {
        self = runtimeValue == .allow ? .allow : .block
    }

    var runtimeValue: EmailRuleAction {
        self == .allow ? .allow : .block
    }
}

enum KeywordMatchLocation: String, CaseIterable, Sendable {
    case subject = "Subject"
    case subjectAndBody = "Subject + Body"
    case anywhere = "Anywhere"

    init(runtimeValue: EmailKeywordMatchLocation) {
        switch runtimeValue {
        case .subject:
            self = .subject
        case .subjectAndBody:
            self = .subjectAndBody
        case .anywhere:
            self = .anywhere
        }
    }

    var runtimeValue: EmailKeywordMatchLocation {
        switch self {
        case .subject:
            return .subject
        case .subjectAndBody:
            return .subjectAndBody
        case .anywhere:
            return .anywhere
        }
    }
}

enum AgentDefaultPolicy: String, CaseIterable, Sendable {
    case allowUnlessBlocked = "Allow unless blocked"
    case blockUnlessAllowed = "Block unless allowed"

    init(runtimeValue: EmailDefaultPolicy) {
        self = runtimeValue == .allowUnlessBlocked ? .allowUnlessBlocked : .blockUnlessAllowed
    }

    var runtimeValue: EmailDefaultPolicy {
        self == .allowUnlessBlocked ? .allowUnlessBlocked : .blockUnlessAllowed
    }
}
