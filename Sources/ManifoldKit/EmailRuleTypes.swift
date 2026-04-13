// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum EmailRuleAction: String, Sendable, Codable, CaseIterable {
    case allow
    case block
}

public enum EmailDefaultPolicy: String, Sendable, Codable, CaseIterable {
    case allowUnlessBlocked = "allow_unless_blocked"
    case blockUnlessAllowed = "block_unless_allowed"

    public var displayName: String {
        switch self {
        case .allowUnlessBlocked:
            return "Allow unless blocked"
        case .blockUnlessAllowed:
            return "Block unless allowed"
        }
    }

    public static func defaultValue(for agent: TargetApp) -> EmailDefaultPolicy {
        switch agent {
        case .cowork:
            return .allowUnlessBlocked
        case .codex:
            return .blockUnlessAllowed
        }
    }
}

public enum EmailKeywordMatchLocation: String, Sendable, Codable, CaseIterable {
    case subject = "subject"
    case subjectAndBody = "subject_and_body"
    case anywhere = "anywhere"

    public var displayName: String {
        switch self {
        case .subject:
            return "Subject"
        case .subjectAndBody:
            return "Subject + Body"
        case .anywhere:
            return "Anywhere"
        }
    }
}

public enum EmailRuleDecisionKind: String, Sendable, Codable, CaseIterable {
    case paused
    case explicitGrantSelection = "explicit_grant_selection"
    case temporaryReveal = "temporary_reveal"
    case sharedEmail = "shared_email"
    case contact
    case keyword
    case domain
    case shield
    case sensitivity
    case defaultPolicy = "default_policy"
}

public struct EmailShieldState: Sendable, Codable, Hashable, Identifiable {
    public let shieldID: String
    public let name: String
    public let description: String
    public let icon: String
    public let domains: [String]
    public let patterns: [String]
    public var isEnabled: Bool

    public var id: String { shieldID }

    public init(
        shieldID: String,
        name: String,
        description: String,
        icon: String,
        domains: [String],
        patterns: [String],
        isEnabled: Bool
    ) {
        self.shieldID = shieldID
        self.name = name
        self.description = description
        self.icon = icon
        self.domains = domains
        self.patterns = patterns
        self.isEnabled = isEnabled
    }
}

public struct EmailDomainRule: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let agent: TargetApp
    public var domain: String
    public var action: EmailRuleAction
    public let createdAt: String
    public var updatedAt: String

    public init(
        id: String = "email-domain-\(UUID().uuidString.prefix(8).lowercased())",
        agent: TargetApp,
        domain: String,
        action: EmailRuleAction,
        createdAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        updatedAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.id = id
        self.agent = agent
        self.domain = domain
        self.action = action
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct EmailContactRule: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let agent: TargetApp
    public var name: String
    public var email: String
    public var action: EmailRuleAction
    public let createdAt: String
    public var updatedAt: String

    public init(
        id: String = "email-contact-\(UUID().uuidString.prefix(8).lowercased())",
        agent: TargetApp,
        name: String,
        email: String,
        action: EmailRuleAction,
        createdAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        updatedAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.id = id
        self.agent = agent
        self.name = name
        self.email = email
        self.action = action
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct EmailKeywordRule: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let agent: TargetApp
    public var pattern: String
    public var matchLocation: EmailKeywordMatchLocation
    public var action: EmailRuleAction
    public var isRegex: Bool
    public let createdAt: String
    public var updatedAt: String

    public init(
        id: String = "email-keyword-\(UUID().uuidString.prefix(8).lowercased())",
        agent: TargetApp,
        pattern: String,
        matchLocation: EmailKeywordMatchLocation,
        action: EmailRuleAction,
        isRegex: Bool,
        createdAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        updatedAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.id = id
        self.agent = agent
        self.pattern = pattern
        self.matchLocation = matchLocation
        self.action = action
        self.isRegex = isRegex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct EmailRuleSet: Sendable, Codable, Hashable {
    public let agent: TargetApp
    public var shields: [EmailShieldState]
    public var domainRules: [EmailDomainRule]
    public var contactRules: [EmailContactRule]
    public var keywordRules: [EmailKeywordRule]
    public var defaultPolicy: EmailDefaultPolicy
    public var emailSensitivity: EmailSensitivityLevel

    public init(
        agent: TargetApp,
        shields: [EmailShieldState] = EmailShieldCatalog.defaults(enabledByDefault: true),
        domainRules: [EmailDomainRule] = [],
        contactRules: [EmailContactRule] = [],
        keywordRules: [EmailKeywordRule] = [],
        defaultPolicy: EmailDefaultPolicy? = nil,
        emailSensitivity: EmailSensitivityLevel = .moderate
    ) {
        self.agent = agent
        self.shields = shields
        self.domainRules = domainRules
        self.contactRules = contactRules
        self.keywordRules = keywordRules
        self.defaultPolicy = defaultPolicy ?? .defaultValue(for: agent)
        self.emailSensitivity = emailSensitivity
    }
}

public struct AgentEmailGovernanceSummary: Sendable, Codable, Hashable {
    public let agent: TargetApp
    public let enabledShieldCount: Int
    public let domainRuleCount: Int
    public let contactRuleCount: Int
    public let keywordRuleCount: Int
    public let defaultPolicy: EmailDefaultPolicy
    public let emailSensitivity: EmailSensitivityLevel

    public init(
        agent: TargetApp,
        enabledShieldCount: Int,
        domainRuleCount: Int,
        contactRuleCount: Int,
        keywordRuleCount: Int,
        defaultPolicy: EmailDefaultPolicy,
        emailSensitivity: EmailSensitivityLevel
    ) {
        self.agent = agent
        self.enabledShieldCount = enabledShieldCount
        self.domainRuleCount = domainRuleCount
        self.contactRuleCount = contactRuleCount
        self.keywordRuleCount = keywordRuleCount
        self.defaultPolicy = defaultPolicy
        self.emailSensitivity = emailSensitivity
    }

    public var totalRuleCount: Int {
        domainRuleCount + contactRuleCount + keywordRuleCount
    }
}

public struct EmailRuleDecision: Sendable, Codable, Hashable {
    public let agent: TargetApp
    public let emailID: String
    public let allowed: Bool
    public let kind: EmailRuleDecisionKind
    public let ruleID: String?
    public let action: EmailRuleAction?
    public let matchedValue: String?
    public let message: String

    public init(
        agent: TargetApp,
        emailID: String,
        allowed: Bool,
        kind: EmailRuleDecisionKind,
        ruleID: String? = nil,
        action: EmailRuleAction? = nil,
        matchedValue: String? = nil,
        message: String
    ) {
        self.agent = agent
        self.emailID = emailID
        self.allowed = allowed
        self.kind = kind
        self.ruleID = ruleID
        self.action = action
        self.matchedValue = matchedValue
        self.message = message
    }

    public var metadata: [String: String] {
        var metadata: [String: String] = [
            "email_rule_kind": kind.rawValue,
            "email_rule_result": allowed ? "allow" : "deny",
            "email_rule_message": message,
        ]
        if let ruleID, !ruleID.isEmpty {
            metadata["email_rule_id"] = ruleID
        }
        if let action {
            metadata["email_rule_action"] = action.rawValue
        }
        if let matchedValue, !matchedValue.isEmpty {
            metadata["email_rule_match"] = matchedValue
        }
        return metadata
    }
}

public struct EmailShieldMatch: Sendable, Codable, Hashable, Identifiable {
    public let shieldID: String
    public let emailID: String
    public let subject: String
    public let from: String
    public let date: String

    public var id: String { "\(shieldID):\(emailID)" }

    public init(shieldID: String, emailID: String, subject: String, from: String, date: String) {
        self.shieldID = shieldID
        self.emailID = emailID
        self.subject = subject
        self.from = from
        self.date = date
    }
}

public struct EmailRuleHitSummary: Sendable, Codable, Hashable, Identifiable {
    public let ruleID: String
    public let count: Int

    public var id: String { ruleID }

    public init(ruleID: String, count: Int) {
        self.ruleID = ruleID
        self.count = count
    }
}

public struct EmailRuleActivitySummary: Sendable, Codable, Hashable {
    public let agent: TargetApp
    public let shieldBlockedCounts: [String: Int]
    public let recentShieldMatches: [EmailShieldMatch]
    public let domainRuleHits: [EmailRuleHitSummary]
    public let contactRuleHits: [EmailRuleHitSummary]
    public let keywordRuleHits: [EmailRuleHitSummary]

    public init(
        agent: TargetApp,
        shieldBlockedCounts: [String: Int] = [:],
        recentShieldMatches: [EmailShieldMatch] = [],
        domainRuleHits: [EmailRuleHitSummary] = [],
        contactRuleHits: [EmailRuleHitSummary] = [],
        keywordRuleHits: [EmailRuleHitSummary] = []
    ) {
        self.agent = agent
        self.shieldBlockedCounts = shieldBlockedCounts
        self.recentShieldMatches = recentShieldMatches
        self.domainRuleHits = domainRuleHits
        self.contactRuleHits = contactRuleHits
        self.keywordRuleHits = keywordRuleHits
    }
}

public enum EmailRuleValidationError: LocalizedError, Sendable {
    case invalidDomain(String)
    case invalidContactEmail(String)
    case emptyKeywordPattern
    case duplicateDomain(String)
    case duplicateContact(String)
    case duplicateKeyword(String)
    case unknownShield(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDomain(let domain):
            return "Invalid domain rule: \(domain)"
        case .invalidContactEmail(let email):
            return "Invalid contact email: \(email)"
        case .emptyKeywordPattern:
            return "Keyword rules need a pattern."
        case .duplicateDomain(let domain):
            return "A rule for @\(domain) already exists for this agent."
        case .duplicateContact(let email):
            return "A rule for \(email) already exists for this agent."
        case .duplicateKeyword(let key):
            return "A keyword rule for \(key) already exists for this agent."
        case .unknownShield(let shieldID):
            return "Unknown shield: \(shieldID)"
        }
    }
}

public enum EmailShieldCatalog {
    public static func defaults(enabledByDefault: Bool) -> [EmailShieldState] {
        [
            EmailShieldState(
                shieldID: "security",
                name: "Security & 2FA",
                description: "Catches OTP codes, verification emails, password resets, login alerts, and new device notifications.",
                icon: "shield.checkered",
                domains: ["accounts.google.com", "appleid.apple.com", "noreply@github.com"],
                patterns: ["verification code", "one-time password", "security alert", "reset your password"],
                isEnabled: enabledByDefault
            ),
            EmailShieldState(
                shieldID: "financial",
                name: "Financial",
                description: "Catches bank statements, transaction alerts, credit card notifications, invoices with account numbers, and tax documents.",
                icon: "banknote",
                domains: ["chase.com", "bankofamerica.com", "stripe.com", "venmo.com"],
                patterns: ["statement ready", "transaction alert", "payment received", "tax document"],
                isEnabled: enabledByDefault
            ),
            EmailShieldState(
                shieldID: "medical",
                name: "Medical",
                description: "Catches appointment confirmations, lab results, prescription notifications, insurance claims, and provider messages.",
                icon: "cross.case",
                domains: ["mychart.com", "myhealth.com"],
                patterns: ["appointment confirmation", "lab results", "prescription", "visit summary"],
                isEnabled: enabledByDefault
            ),
            EmailShieldState(
                shieldID: "legal",
                name: "Legal",
                description: "Catches attorney correspondence, legal notices, NDA-related emails, and contract reviews.",
                icon: "building.columns",
                domains: [],
                patterns: ["attorney-client", "privileged", "nda", "legal notice", "subpoena"],
                isEnabled: false
            ),
            EmailShieldState(
                shieldID: "personal",
                name: "Personal",
                description: "Catches family/friend emails, dating, personal purchases, and social invitations.",
                icon: "person.crop.circle",
                domains: [],
                patterns: [],
                isEnabled: false
            ),
        ]
    }

    public static func contains(_ shieldID: String) -> Bool {
        defaults(enabledByDefault: true).contains { $0.shieldID == shieldID }
    }
}
