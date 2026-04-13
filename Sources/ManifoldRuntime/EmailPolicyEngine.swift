import Foundation
import ManifoldKit

enum EmailPolicyEngine {
    struct Context: Sendable {
        let agent: TargetApp
        let ruleSet: EmailRuleSet
        let policy: AgentAccessPolicy
        let sharedEmailIDs: Set<String>
        let temporaryRevealIDs: Set<String>
        let explicitGrantEmailIDs: Set<String>?
        let sensitivity: EmailSensitivityLevel
    }

    static func decision(for email: EmailMessageRecord, context: Context) -> EmailRuleDecision {
        if context.policy.isPaused {
            return EmailRuleDecision(
                agent: context.agent,
                emailID: email.emailID,
                allowed: false,
                kind: .paused,
                message: "Agent access is paused."
            )
        }

        if let explicitGrantEmailIDs = context.explicitGrantEmailIDs {
            if explicitGrantEmailIDs.contains(email.emailID) {
                return EmailRuleDecision(
                    agent: context.agent,
                    emailID: email.emailID,
                    allowed: true,
                    kind: .explicitGrantSelection,
                    matchedValue: email.emailID,
                    message: "Email is in the explicit tracked-work selection."
                )
            }
            return EmailRuleDecision(
                agent: context.agent,
                emailID: email.emailID,
                allowed: false,
                kind: .explicitGrantSelection,
                matchedValue: email.emailID,
                message: "Email is outside the explicit tracked-work selection."
            )
        }

        if context.temporaryRevealIDs.contains(email.emailID) {
            return EmailRuleDecision(
                agent: context.agent,
                emailID: email.emailID,
                allowed: true,
                kind: .temporaryReveal,
                matchedValue: email.emailID,
                message: "Email is visible because the user temporarily revealed it."
            )
        }

        if context.sharedEmailIDs.contains(email.emailID) {
            return EmailRuleDecision(
                agent: context.agent,
                emailID: email.emailID,
                allowed: true,
                kind: .sharedEmail,
                matchedValue: email.emailID,
                message: "Email is visible because the user explicitly shared it."
            )
        }

        if let contactDecision = contactDecision(for: email, context: context) {
            return contactDecision
        }

        if let keywordDecision = keywordDecision(for: email, context: context) {
            return keywordDecision
        }

        if let domainDecision = domainDecision(for: email, context: context) {
            return domainDecision
        }

        if let shieldDecision = shieldDecision(for: email, context: context) {
            return shieldDecision
        }

        let filter = EmailSensitivityFilter(rawValue: context.sensitivity.rawValue)
        if !filter.isVisible(email: email) {
            return EmailRuleDecision(
                agent: context.agent,
                emailID: email.emailID,
                allowed: false,
                kind: .sensitivity,
                matchedValue: context.sensitivity.rawValue,
                message: "Email is hidden by the \(context.sensitivity.rawValue) sensitivity preset."
            )
        }

        switch context.policy.defaultEmailPolicy {
        case .allowUnlessBlocked:
            return EmailRuleDecision(
                agent: context.agent,
                emailID: email.emailID,
                allowed: true,
                kind: .defaultPolicy,
                matchedValue: context.policy.defaultEmailPolicy.rawValue,
                message: "Email is visible because no rule blocked it."
            )
        case .blockUnlessAllowed:
            return EmailRuleDecision(
                agent: context.agent,
                emailID: email.emailID,
                allowed: false,
                kind: .defaultPolicy,
                matchedValue: context.policy.defaultEmailPolicy.rawValue,
                message: "Email is hidden because no rule explicitly allowed it."
            )
        }
    }

    static func activitySummary(
        agent: TargetApp,
        ruleSet: EmailRuleSet,
        policy: AgentAccessPolicy,
        emails: [EmailMessageRecord]
    ) -> EmailRuleActivitySummary {
        let context = Context(
            agent: agent,
            ruleSet: ruleSet,
            policy: policy,
            sharedEmailIDs: [],
            temporaryRevealIDs: [],
            explicitGrantEmailIDs: nil,
            sensitivity: ruleSet.emailSensitivity
        )

        var shieldCounts: [String: Int] = [:]
        var recentShieldMatches: [EmailShieldMatch] = []
        var domainHits: [String: Int] = [:]
        var contactHits: [String: Int] = [:]
        var keywordHits: [String: Int] = [:]

        for email in emails {
            for rule in matchedContactRules(for: email, in: ruleSet) {
                contactHits[rule.id, default: 0] += 1
            }

            for rule in matchedDomainRules(for: email, in: ruleSet) {
                domainHits[rule.id, default: 0] += 1
            }

            if let shield = firstMatchingShield(for: email, in: ruleSet) {
                shieldCounts[shield.shieldID, default: 0] += 1
                recentShieldMatches.append(
                    EmailShieldMatch(
                        shieldID: shield.shieldID,
                        emailID: email.emailID,
                        subject: email.subject,
                        from: email.sender,
                        date: email.receivedAt
                    )
                )
            }

            if let keywordRule = matchedKeywordRules(for: email, in: ruleSet).first {
                keywordHits[keywordRule.id, default: 0] += 1
            }

            _ = decision(for: email, context: context)
        }

        let sortedMatches = recentShieldMatches.sorted { $0.date > $1.date }
        let domainSummaries = domainHits
            .map { EmailRuleHitSummary(ruleID: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
        let contactSummaries = contactHits
            .map { EmailRuleHitSummary(ruleID: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
        let hitSummaries = keywordHits
            .map { EmailRuleHitSummary(ruleID: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        return EmailRuleActivitySummary(
            agent: agent,
            shieldBlockedCounts: shieldCounts,
            recentShieldMatches: Array(sortedMatches.prefix(20)),
            domainRuleHits: domainSummaries,
            contactRuleHits: contactSummaries,
            keywordRuleHits: hitSummaries
        )
    }

    private static func contactDecision(for email: EmailMessageRecord, context: Context) -> EmailRuleDecision? {
        guard let senderEmail = email.senderEmail?.lowercased() else { return nil }
        let matches = matchedContactRules(for: email, in: context.ruleSet)
        return decision(for: matches, kind: .contact, email: email, context: context, matchedValue: senderEmail)
    }

    private static func keywordDecision(for email: EmailMessageRecord, context: Context) -> EmailRuleDecision? {
        let matches = matchedKeywordRules(for: email, in: context.ruleSet)
        return decision(for: matches, kind: .keyword, email: email, context: context, matchedValue: matches.first?.pattern)
    }

    private static func domainDecision(for email: EmailMessageRecord, context: Context) -> EmailRuleDecision? {
        guard let senderDomain = email.senderDomain?.lowercased() else { return nil }
        let matches = matchedDomainRules(for: email, in: context.ruleSet)
        return decision(for: matches, kind: .domain, email: email, context: context, matchedValue: senderDomain)
    }

    private static func shieldDecision(for email: EmailMessageRecord, context: Context) -> EmailRuleDecision? {
        guard let shield = firstMatchingShield(for: email, in: context.ruleSet) else { return nil }
        return EmailRuleDecision(
            agent: context.agent,
            emailID: email.emailID,
            allowed: false,
            kind: .shield,
            ruleID: shield.shieldID,
            action: .block,
            matchedValue: shield.shieldID,
            message: "Email is hidden by the \(shield.name) shield."
        )
    }

    private static func decision<RuleType>(
        for matches: [RuleType],
        kind: EmailRuleDecisionKind,
        email: EmailMessageRecord,
        context: Context,
        matchedValue: String?
    ) -> EmailRuleDecision? where RuleType: Identifiable, RuleType: Sendable {
        guard !matches.isEmpty else { return nil }

        let blocked = matches.first { action(for: $0) == .block }
        if let blocked {
            return EmailRuleDecision(
                agent: context.agent,
                emailID: email.emailID,
                allowed: false,
                kind: kind,
                ruleID: String(describing: blocked.id),
                action: .block,
                matchedValue: matchedValue,
                message: "Email is hidden by a \(kind.rawValue.replacingOccurrences(of: "_", with: " ")) rule."
            )
        }

        guard let allowed = matches.first else { return nil }
        return EmailRuleDecision(
            agent: context.agent,
            emailID: email.emailID,
            allowed: true,
            kind: kind,
            ruleID: String(describing: allowed.id),
            action: .allow,
            matchedValue: matchedValue,
            message: "Email is visible because a \(kind.rawValue.replacingOccurrences(of: "_", with: " ")) rule allowed it."
        )
    }

    private static func action(for rule: some Sendable) -> EmailRuleAction {
        switch rule {
        case let rule as EmailDomainRule:
            return rule.action
        case let rule as EmailContactRule:
            return rule.action
        case let rule as EmailKeywordRule:
            return rule.action
        default:
            return .allow
        }
    }

    private static func matchedKeywordRules(for email: EmailMessageRecord, in ruleSet: EmailRuleSet) -> [EmailKeywordRule] {
        ruleSet.keywordRules.filter { rule in
            matchesKeywordRule(rule, email: email)
        }
    }

    private static func matchedContactRules(for email: EmailMessageRecord, in ruleSet: EmailRuleSet) -> [EmailContactRule] {
        guard let senderEmail = email.senderEmail?.lowercased() else { return [] }
        return ruleSet.contactRules.filter { $0.email.lowercased() == senderEmail }
    }

    private static func matchedDomainRules(for email: EmailMessageRecord, in ruleSet: EmailRuleSet) -> [EmailDomainRule] {
        guard let senderDomain = email.senderDomain?.lowercased() else { return [] }
        return ruleSet.domainRules.filter { rule in
            if rule.domain.hasPrefix("*.") {
                return senderDomain.hasSuffix(String(rule.domain.dropFirst(1)).lowercased())
            }
            return senderDomain == rule.domain.lowercased()
        }
    }

    private static func firstMatchingShield(for email: EmailMessageRecord, in ruleSet: EmailRuleSet) -> EmailShieldState? {
        ruleSet.shields.first { shield in
            shield.isEnabled && matchesShield(shield, email: email)
        }
    }

    private static func matchesShield(_ shield: EmailShieldState, email: EmailMessageRecord) -> Bool {
        let haystacks = [
            email.sender.lowercased(),
            email.senderEmail?.lowercased() ?? "",
            email.senderDomain?.lowercased() ?? "",
            email.subject.lowercased(),
            email.preview?.lowercased() ?? "",
            email.bodyText?.lowercased() ?? "",
        ]

        let domainMatched = shield.domains.contains { matcher in
            let token = matcher.lowercased()
            return haystacks.contains { $0.contains(token) }
        }

        let patternMatched = shield.patterns.contains { pattern in
            let token = pattern.lowercased()
            return haystacks.contains { $0.contains(token) }
        }

        return domainMatched || patternMatched
    }

    private static func matchesKeywordRule(_ rule: EmailKeywordRule, email: EmailMessageRecord) -> Bool {
        let lowercasedPattern = rule.pattern.lowercased()
        let fields: [String]
        switch rule.matchLocation {
        case .subject:
            fields = [email.subject]
        case .subjectAndBody:
            fields = [email.subject, email.bodyText ?? "", email.preview ?? ""]
        case .anywhere:
            fields = [
                email.subject,
                email.sender,
                email.senderEmail ?? "",
                email.recipients,
                email.cc,
                email.bodyText ?? "",
                email.preview ?? "",
            ]
        }

        if rule.isRegex {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) else {
                return false
            }
            return fields.contains { field in
                let range = NSRange(field.startIndex..<field.endIndex, in: field)
                return regex.firstMatch(in: field, options: [], range: range) != nil
            }
        }

        return fields.contains { $0.lowercased().contains(lowercasedPattern) }
    }
}
