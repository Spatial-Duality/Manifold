// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit
@testable import ManifoldRuntime

@Suite("EmailPolicyEngine")
struct EmailPolicyEngineTests {
    private func makeEmail(
        id: String = "email-1",
        sender: String = "Docs Team <updates@example.com>",
        senderEmail: String = "updates@example.com",
        senderDomain: String = "example.com",
        subject: String = "Weekly update",
        preview: String = "Project update",
        body: String = "Project update body"
    ) -> EmailMessageRecord {
        EmailMessageRecord(row: [
            "email_id": id,
            "account_id": "account-1",
            "mailbox": "Inbox",
            "sender": sender,
            "sender_email": senderEmail,
            "sender_domain": senderDomain,
            "recipients": "user@example.com",
            "cc": "",
            "subject": subject,
            "received_at": ISO8601DateFormatter.shared.string(from: Date()),
            "size_bytes": "\(body.utf8.count)",
            "preview": preview,
            "content_type": "text/plain",
            "is_read": "0",
            "is_flagged": "0",
            "attachment_count": "0",
            "local_is_viewed": "0",
            "is_junk": "0",
            "body_text": body,
        ])!
    }

    private func makeContext(
        agent: TargetApp = .codex,
        ruleSet: EmailRuleSet? = nil,
        isPaused: Bool = false,
        defaultPolicy: EmailDefaultPolicy = .blockUnlessAllowed,
        sensitivity: EmailSensitivityLevel = .moderate,
        sharedEmailIDs: Set<String> = [],
        temporaryRevealIDs: Set<String> = [],
        explicitGrantEmailIDs: Set<String>? = nil
    ) -> EmailPolicyEngine.Context {
        var policy = AgentAccessPolicy(agent: agent)
        policy.isPaused = isPaused
        policy.defaultEmailPolicy = defaultPolicy
        policy.emailSensitivity = sensitivity

        return EmailPolicyEngine.Context(
            agent: agent,
            ruleSet: ruleSet ?? EmailRuleSet(agent: agent, defaultPolicy: defaultPolicy),
            policy: policy,
            sharedEmailIDs: sharedEmailIDs,
            temporaryRevealIDs: temporaryRevealIDs,
            explicitGrantEmailIDs: explicitGrantEmailIDs,
            sensitivity: sensitivity
        )
    }

    @Test("Paused agent denies everything")
    func pausedAgentDenies() {
        let email = makeEmail()
        let decision = EmailPolicyEngine.decision(for: email, context: makeContext(isPaused: true))
        #expect(decision.allowed == false)
        #expect(decision.kind == .paused)
    }

    @Test("Shared email overrides lower rules")
    func sharedEmailWins() {
        let email = makeEmail(subject: "statement ready", preview: "transaction alert", body: "statement ready")
        let ruleSet = EmailRuleSet(
            agent: .codex,
            domainRules: [EmailDomainRule(agent: .codex, domain: "example.com", action: .block)]
        )
        let decision = EmailPolicyEngine.decision(
            for: email,
            context: makeContext(ruleSet: ruleSet, sharedEmailIDs: [email.emailID])
        )
        #expect(decision.allowed)
        #expect(decision.kind == .sharedEmail)
    }

    @Test("Contact rules beat keyword, domain, shield, and default")
    func contactBeatsLowerTiers() {
        let email = makeEmail(
            sender: "Alice <alice@example.com>",
            senderEmail: "alice@example.com",
            senderDomain: "example.com",
            subject: "statement ready",
            preview: "transaction alert",
            body: "statement ready"
        )
        let ruleSet = EmailRuleSet(
            agent: .codex,
            domainRules: [EmailDomainRule(agent: .codex, domain: "example.com", action: .block)],
            contactRules: [EmailContactRule(agent: .codex, name: "Alice", email: "alice@example.com", action: .allow)],
            keywordRules: [EmailKeywordRule(agent: .codex, pattern: "statement", matchLocation: .subjectAndBody, action: .block, isRegex: false)]
        )
        let decision = EmailPolicyEngine.decision(for: email, context: makeContext(ruleSet: ruleSet))
        #expect(decision.allowed)
        #expect(decision.kind == .contact)
    }

    @Test("Keyword rules beat domain, shield, and default")
    func keywordBeatsLowerTiers() {
        let email = makeEmail(
            senderDomain: "example.com",
            subject: "project roadmap",
            preview: "sprint plan",
            body: "roadmap"
        )
        let ruleSet = EmailRuleSet(
            agent: .codex,
            domainRules: [EmailDomainRule(agent: .codex, domain: "example.com", action: .block)],
            keywordRules: [EmailKeywordRule(agent: .codex, pattern: "roadmap", matchLocation: .subjectAndBody, action: .allow, isRegex: false)]
        )
        let decision = EmailPolicyEngine.decision(for: email, context: makeContext(ruleSet: ruleSet))
        #expect(decision.allowed)
        #expect(decision.kind == .keyword)
    }

    @Test("Domain rules beat shields and default")
    func domainBeatsShield() {
        let email = makeEmail(
            sender: "Alerts <alerts@stripe.com>",
            senderEmail: "alerts@stripe.com",
            senderDomain: "stripe.com",
            subject: "payment received",
            preview: "transaction alert",
            body: "payment received"
        )
        let ruleSet = EmailRuleSet(
            agent: .codex,
            domainRules: [EmailDomainRule(agent: .codex, domain: "stripe.com", action: .allow)]
        )
        let decision = EmailPolicyEngine.decision(for: email, context: makeContext(ruleSet: ruleSet))
        #expect(decision.allowed)
        #expect(decision.kind == .domain)
    }

    @Test("Same-tier conflicts resolve with block over allow")
    func blockWinsWithinTier() {
        let email = makeEmail(subject: "confidential roadmap", preview: "", body: "confidential roadmap")
        let ruleSet = EmailRuleSet(
            agent: .codex,
            keywordRules: [
                EmailKeywordRule(agent: .codex, pattern: "roadmap", matchLocation: .subjectAndBody, action: .allow, isRegex: false),
                EmailKeywordRule(agent: .codex, pattern: "confidential", matchLocation: .subjectAndBody, action: .block, isRegex: false),
            ]
        )
        let decision = EmailPolicyEngine.decision(for: email, context: makeContext(ruleSet: ruleSet))
        #expect(decision.allowed == false)
        #expect(decision.kind == .keyword)
        #expect(decision.action == .block)
    }

    @Test("Sensitivity beats default when no higher rule matches")
    func sensitivityBeatsDefault() {
        let email = makeEmail(
            sender: "Fidelity <alerts@fidelity.com>",
            senderEmail: "alerts@fidelity.com",
            senderDomain: "fidelity.com",
            subject: "Account notice",
            preview: "Portfolio update",
            body: "Portfolio update"
        )
        let decision = EmailPolicyEngine.decision(
            for: email,
            context: makeContext(defaultPolicy: .allowUnlessBlocked, sensitivity: .moderate)
        )
        #expect(decision.allowed == false)
        #expect(decision.kind == .sensitivity)
    }

    @Test("Activity summary reports domain, contact, and keyword hits")
    func activitySummaryTracksRuleHits() {
        let ruleSet = EmailRuleSet(
            agent: .codex,
            domainRules: [EmailDomainRule(id: "domain-1", agent: .codex, domain: "example.com", action: .allow)],
            contactRules: [EmailContactRule(id: "contact-1", agent: .codex, name: "Alice", email: "alice@example.com", action: .allow)],
            keywordRules: [EmailKeywordRule(id: "keyword-1", agent: .codex, pattern: "roadmap", matchLocation: .subjectAndBody, action: .allow, isRegex: false)]
        )
        var policy = AgentAccessPolicy(agent: .codex)
        policy.defaultEmailPolicy = .blockUnlessAllowed
        let email = makeEmail(
            sender: "Alice <alice@example.com>",
            senderEmail: "alice@example.com",
            senderDomain: "example.com",
            subject: "roadmap update"
        )

        let summary = EmailPolicyEngine.activitySummary(
            agent: .codex,
            ruleSet: ruleSet,
            policy: policy,
            emails: [email]
        )

        #expect(summary.domainRuleHits.first?.ruleID == "domain-1")
        #expect(summary.contactRuleHits.first?.ruleID == "contact-1")
        #expect(summary.keywordRuleHits.first?.ruleID == "keyword-1")
    }
}
