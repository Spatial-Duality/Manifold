import Foundation
import ManifoldKit

/// Shield categories for email protection.
@Observable
@MainActor
final class EmailRulesModel {
    var shields: [EmailShield] = EmailShield.defaults
    var domainRules: [DomainRule] = []
    var contactRules: [ContactRule] = []
    var keywordRules: [KeywordRule] = []
    var claudeDefaultPolicy: AgentDefaultPolicy = .allowUnlessBlocked
    var codexDefaultPolicy: AgentDefaultPolicy = .blockUnlessAllowed

    init() {}
}

struct EmailShield: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    var isEnabled: Bool
    let icon: String
    let domains: [String]
    let patterns: [String]
    var blockedCount: Int
    var recentMatches: [ShieldMatch]

    static let defaults: [EmailShield] = [
        EmailShield(
            id: "security",
            name: "Security & 2FA",
            description: "Catches OTP codes, verification emails, password resets, login alerts, and new device notifications. An agent with your 2FA codes could bypass authentication.",
            isEnabled: true,
            icon: "shield.checkered",
            domains: ["accounts.google.com", "appleid.apple.com", "noreply@github.com"],
            patterns: ["verification code", "one-time password", "security alert", "reset your password"],
            blockedCount: 0,
            recentMatches: []
        ),
        EmailShield(
            id: "financial",
            name: "Financial",
            description: "Catches bank statements, transaction alerts, credit card notifications, invoices with account numbers, and tax documents.",
            isEnabled: true,
            icon: "banknote",
            domains: ["chase.com", "bankofamerica.com", "stripe.com", "venmo.com"],
            patterns: ["statement ready", "transaction alert", "payment received", "tax document"],
            blockedCount: 0,
            recentMatches: []
        ),
        EmailShield(
            id: "medical",
            name: "Medical",
            description: "Catches appointment confirmations, lab results, prescription notifications, insurance claims, and provider messages.",
            isEnabled: true,
            icon: "cross.case",
            domains: ["mychart.com", "myhealth.com"],
            patterns: ["appointment confirmation", "lab results", "prescription", "visit summary"],
            blockedCount: 0,
            recentMatches: []
        ),
        EmailShield(
            id: "legal",
            name: "Legal",
            description: "Catches attorney correspondence, legal notices, NDA-related emails, and contract reviews.",
            isEnabled: false,
            icon: "building.columns",
            domains: [],
            patterns: ["attorney-client", "privileged", "NDA", "legal notice", "subpoena"],
            blockedCount: 0,
            recentMatches: []
        ),
        EmailShield(
            id: "personal",
            name: "Personal",
            description: "Catches family/friend emails, dating, personal purchases, and social invitations. Highly subjective, configure contact lists manually.",
            isEnabled: false,
            icon: "person.crop.circle",
            domains: [],
            patterns: [],
            blockedCount: 0,
            recentMatches: []
        ),
    ]
}

struct ShieldMatch: Identifiable, Sendable {
    let id: UUID
    let subject: String
    let from: String
    let date: Date
    let agentBlocked: TargetApp
}

struct DomainRule: Identifiable, Sendable {
    let id: UUID
    let domain: String
    var action: RuleAction
    let category: String
    var agents: [TargetApp]
    let emailCount: Int
    var shieldOverlap: String?
}

struct ContactRule: Identifiable, Sendable {
    let id: UUID
    let name: String
    let email: String
    var action: RuleAction
    let overridesDescription: String
    var agents: [TargetApp]
}

struct KeywordRule: Identifiable, Sendable {
    let id: UUID
    let pattern: String
    let matchLocation: KeywordMatchLocation
    var action: RuleAction
    var matchedCount: Int
    var agents: [TargetApp]
    var isRegex: Bool
}

enum RuleAction: String, CaseIterable, Sendable {
    case allow, block
}

enum KeywordMatchLocation: String, CaseIterable, Sendable {
    case subject = "Subject"
    case subjectAndBody = "Subject + Body"
    case anywhere = "Anywhere"
}

enum AgentDefaultPolicy: String, CaseIterable, Sendable {
    case allowUnlessBlocked = "Allow unless blocked"
    case blockUnlessAllowed = "Block unless allowed"
}

// MARK: - Rule CRUD

extension EmailRulesModel {
    func addDomainRule(domain: String, action: RuleAction, category: String, agents: [TargetApp]) {
        domainRules.append(DomainRule(
            id: UUID(), domain: domain, action: action,
            category: category, agents: agents,
            emailCount: 0, shieldOverlap: nil
        ))
    }

    func addContactRule(name: String, email: String, action: RuleAction, agents: [TargetApp]) {
        let emailDomain = email.split(separator: "@").last.map(String.init) ?? ""
        let existing = domainRules.first { $0.domain == emailDomain }
        let overrides = existing != nil
            ? "\(emailDomain) domain (\(existing!.action.rawValue)) \u{2192} \(action.rawValue) for this contact"
            : "No existing domain or shield override"
        contactRules.append(ContactRule(
            id: UUID(), name: name, email: email,
            action: action, overridesDescription: overrides,
            agents: agents
        ))
    }

    func addKeywordRule(pattern: String, matchLocation: KeywordMatchLocation, action: RuleAction, agents: [TargetApp], isRegex: Bool) {
        keywordRules.append(KeywordRule(
            id: UUID(), pattern: pattern,
            matchLocation: matchLocation, action: action,
            matchedCount: 0, agents: agents, isRegex: isRegex
        ))
    }

    func removeDomainRule(id: UUID) { domainRules.removeAll { $0.id == id } }
    func removeContactRule(id: UUID) { contactRules.removeAll { $0.id == id } }
    func removeKeywordRule(id: UUID) { keywordRules.removeAll { $0.id == id } }
}
