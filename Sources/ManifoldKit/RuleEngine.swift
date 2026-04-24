// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let engineLogger = Logger(subsystem: "com.spatialduality.manifold", category: "rule-engine")

/// Stateless evaluator for the unified rule catalog.
///
/// The engine implements the plan's **deny-wins, then first-match** precedence:
///   1. Filter to rules that apply to this `(scope, agent, window)`.
///   2. If any matching rule has `action == .deny`, return `.deny` immediately
///      (seeded denies therefore can't be "out-ordered" by a later allow).
///   3. Otherwise return the first matching rule by `(source.groupPriority, orderIndex)`
///      — seeded pins above user-override, user, imported, suggested.
///   4. If nothing matched, emit `.allow` with `defaultPolicyApplied = true` so the
///      caller's per-agent default policy (`allowUnlessBlocked` / `blockUnlessAllowed`)
///      can make the final decision.
///
/// The engine is pure — no IO, no store access. Callers fetch the rule list, run
/// `evaluate(...)`, and route the resulting `RuleDecision` through whatever enforcement
/// path applies (MCP gate, email filter, tool dispatch).
public struct RuleEngine: Sendable {
    public init() {}

    // MARK: - Public API

    public func evaluate(
        _ request: RuleRequest,
        against rules: [RuleRecord],
        agent: TargetApp,
        context: RuleEvalContext
    ) -> RuleDecision {
        let candidates = rules.filter { rule in
            guard rule.enabled else { return false }
            guard rule.scope == request.scope else { return false }
            guard rule.applies(to: agent) else { return false }
            guard rule.window.isActive(
                now: context.now,
                createdAt: rule.createdAtDate,
                sessionActive: context.sessionActive
            ) else { return false }
            return true
        }

        // Phase 1 — deny sweep.
        for rule in candidates where rule.action == .deny {
            if matches(rule.matcher, request: request, context: context) {
                return .init(
                    action: .deny,
                    matchedRuleID: rule.id,
                    matchedRuleName: rule.name,
                    matchedMatcherSummary: summarize(rule.matcher),
                    explanation: rule.explanation.isEmpty
                        ? "Denied by rule \"\(rule.name)\""
                        : rule.explanation
                )
            }
        }

        // Phase 2 — first-match among same-action candidates.
        // Within `candidates`, sort by (group priority ascending, orderIndex ascending, createdAt ascending)
        // so seeded rules fire before user rules of the same action.
        let ordered = candidates
            .filter { $0.action != .deny }     // denies already handled
            .sorted { lhs, rhs in
                if lhs.source.groupPriority != rhs.source.groupPriority {
                    return lhs.source.groupPriority < rhs.source.groupPriority
                }
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.createdAt < rhs.createdAt
            }

        for rule in ordered {
            if matches(rule.matcher, request: request, context: context) {
                return .init(
                    action: rule.action,
                    matchedRuleID: rule.id,
                    matchedRuleName: rule.name,
                    matchedMatcherSummary: summarize(rule.matcher),
                    explanation: rule.explanation.isEmpty
                        ? "\(verbDescription(rule.action)) by rule \"\(rule.name)\""
                        : rule.explanation
                )
            }
        }

        // Phase 3 — nothing matched; the caller decides based on default policy.
        return .init(
            action: .allow,
            matchedRuleID: nil,
            matchedRuleName: nil,
            matchedMatcherSummary: nil,
            explanation: "No matching rule — default policy applies.",
            defaultPolicyApplied: true
        )
    }

    // MARK: - Matcher evaluation

    /// Returns true if `matcher` matches the request in this context.
    /// Probes are pulled lazily so we don't stat files / read bodies we don't need.
    public func matches(_ matcher: RuleMatcher, request: RuleRequest, context: RuleEvalContext) -> Bool {
        switch matcher {
        case .always: return true
        case .never: return false

        case .all(let subs):
            return subs.allSatisfy { matches($0, request: request, context: context) }
        case .any(let subs):
            return subs.contains { matches($0, request: request, context: context) }
        case .not(let sub):
            return !matches(sub, request: request, context: context)

        // File predicates
        case .pathGlob(let pattern):
            guard let path = request.resourcePath else { return false }
            return globMatch(pattern: pattern, path: path)
        case .pathRegex(let pattern):
            guard let path = request.resourcePath else { return false }
            return regexMatch(pattern: pattern, text: path)
        case .fileSizeOver(let threshold):
            guard let size = context.fileProbe?.sizeBytes() else { return false }
            return size > threshold
        case .fileSizeUnder(let threshold):
            guard let size = context.fileProbe?.sizeBytes() else { return false }
            return size < threshold
        case .fileAgeOlderThan(let interval):
            guard let mtime = context.fileProbe?.modifiedAt() else { return false }
            return context.now.timeIntervalSince(mtime) > interval
        case .fileAgeNewerThan(let interval):
            guard let mtime = context.fileProbe?.modifiedAt() else { return false }
            return context.now.timeIntervalSince(mtime) < interval
        case .fileHidden:
            return context.fileProbe?.isHidden() ?? false
        case .fileBinary:
            return context.fileProbe?.isBinary() ?? false
        case .fileSecretDetected:
            return context.fileProbe?.containsSecret() ?? false
        case .gitignored:
            return context.fileProbe?.isGitignored() ?? false
        case .fileExtension(let ext):
            guard let path = request.resourcePath else { return false }
            let trimmed = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
            return (path as NSString).pathExtension.caseInsensitiveCompare(trimmed) == .orderedSame

        // Email predicates
        case .emailSender(let addr):
            guard let probe = context.emailProbe else { return false }
            return probe.senderEmail == addr.lowercased()
        case .emailDomain(let pattern):
            guard let probe = context.emailProbe else { return false }
            return domainMatch(pattern: pattern, domain: probe.senderDomain)
        case .emailSubjectKeyword(let needle, let isRegex):
            guard let probe = context.emailProbe else { return false }
            return keywordHit(needle: needle, isRegex: isRegex, haystack: probe.subject)
        case .emailBodyKeyword(let needle, let isRegex):
            guard let probe = context.emailProbe else { return false }
            return keywordHit(needle: needle, isRegex: isRegex, haystack: probe.bodyText)
        case .emailKeyword(let field, let needle, let isRegex):
            guard let probe = context.emailProbe else { return false }
            let haystack: String
            switch field {
            case .subject: haystack = probe.subject
            case .body: haystack = probe.bodyText
            case .subjectAndBody: haystack = probe.subject + "\n" + probe.bodyText
            case .anywhere:
                haystack = [probe.subject, probe.bodyText, probe.senderEmail, probe.senderDomain, probe.folder]
                    .joined(separator: "\n")
            }
            return keywordHit(needle: needle, isRegex: isRegex, haystack: haystack)
        case .emailHasAttachment:
            return context.emailProbe?.hasAttachment ?? false
        case .emailAttachmentLargerThan(let threshold):
            guard let bytes = context.emailProbe?.largestAttachmentBytes else { return false }
            return bytes > threshold
        case .emailShield(let kind):
            return context.emailProbe?.matchedShields.contains(kind) ?? false
        case .emailInFolder(let folder):
            guard let probe = context.emailProbe else { return false }
            return probe.folder.caseInsensitiveCompare(folder) == .orderedSame
        case .emailAccount(let accountID):
            return context.emailProbe?.accountID == accountID
        case .emailOlderThan(let interval):
            guard let probe = context.emailProbe else { return false }
            return context.now.timeIntervalSince(probe.receivedAt) > interval

        // Agent predicates
        case .agentTool(let tool):
            return context.agentProbe?.tool == tool
        case .agentWrite:
            guard let t = context.agentProbe?.tool else { return false }
            return t == .write || t == .delete
        case .agentDelete:
            return context.agentProbe?.tool == .delete
        case .agentSessionLongerThan(let interval):
            guard let started = context.agentProbe?.sessionStartedAt else { return false }
            return context.now.timeIntervalSince(started) > interval
        case .agentPayloadLargerThan(let threshold):
            guard let bytes = context.agentProbe?.payloadBytes else { return false }
            return bytes > threshold

        // Privacy predicates — read from the privacy probe supplied by the
        // runtime. A missing probe conservatively evaluates to false for
        // positive assertions (no probe → we can't claim PII is present),
        // except for allowlist which defaults to false as well.
        case .privacyContainsCategory(let category):
            return context.privacyProbe?.categories.contains(category) ?? false
        case .privacyMatchesMyIdentity:
            return context.privacyProbe?.matchesMyIdentity ?? false
        case .privacyInOrgAllowlist:
            return context.privacyProbe?.inOrgAllowlist ?? false
        case .privacySeverityAtLeast(let threshold):
            guard let severity = context.privacyProbe?.severity else { return false }
            return severity >= threshold
        }
    }

    // MARK: - Helpers

    private func globMatch(pattern: String, path: String) -> Bool {
        // Reuse the project's gitignore-style matcher; "**" / "*" / "?" as documented there.
        let matcher = GlobMatcher(content: pattern)
        return matcher.shouldExclude(relativePath: path)
    }

    private func regexMatch(pattern: String, text: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return re.firstMatch(in: text, options: [], range: range) != nil
    }

    private func domainMatch(pattern: String, domain: String) -> Bool {
        let pat = pattern.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let dom = domain.lowercased()
        if pat.hasPrefix("*.") {
            let suffix = String(pat.dropFirst(2))
            return dom == suffix || dom.hasSuffix("." + suffix)
        }
        return pat == dom
    }

    private func keywordHit(needle: String, isRegex: Bool, haystack: String) -> Bool {
        if isRegex {
            return regexMatch(pattern: needle, text: haystack)
        }
        return haystack.range(of: needle, options: .caseInsensitive) != nil
    }

    private func verbDescription(_ action: RuleAction) -> String {
        switch action {
        case .allow: return "Allowed"
        case .deny: return "Denied"
        case .warn: return "Warning"
        case .redact: return "Redacted"
        case .summarize: return "Summarized"
        case .downgrade: return "Metadata only"
        case .log: return "Logged"
        }
    }

    /// Short, user-readable summary of a matcher — shown in audit trails and inspectors.
    public func summarize(_ matcher: RuleMatcher) -> String {
        switch matcher {
        case .always: return "any request"
        case .never: return "nothing"
        case .pathGlob(let s): return "path ~ \(s)"
        case .pathRegex(let s): return "path matches /\(s)/"
        case .fileSizeOver(let n): return "size > \(n) bytes"
        case .fileSizeUnder(let n): return "size < \(n) bytes"
        case .fileAgeOlderThan(let t): return "older than \(Int(t)) s"
        case .fileAgeNewerThan(let t): return "newer than \(Int(t)) s"
        case .fileHidden: return "hidden files"
        case .fileBinary: return "binary files"
        case .fileSecretDetected: return "contains a detected secret"
        case .gitignored: return "gitignored files"
        case .fileExtension(let e): return "extension .\(e)"
        case .emailSender(let s): return "sender \(s)"
        case .emailDomain(let s): return "domain \(s)"
        case .emailSubjectKeyword(let s, let r): return r ? "subject ~ /\(s)/" : "subject contains \"\(s)\""
        case .emailBodyKeyword(let s, let r): return r ? "body ~ /\(s)/" : "body contains \"\(s)\""
        case .emailKeyword(let f, let s, let r):
            return r ? "\(f.displayName) ~ /\(s)/" : "\(f.displayName) contains \"\(s)\""
        case .emailHasAttachment: return "has attachment"
        case .emailAttachmentLargerThan(let n): return "attachment > \(n) bytes"
        case .emailShield(let k): return "\(k.displayName) shield"
        case .emailInFolder(let f): return "in folder \(f)"
        case .emailAccount(let a): return "account \(a)"
        case .emailOlderThan(let t): return "older than \(Int(t)) s"
        case .agentTool(let t): return "tool = \(t.displayName)"
        case .agentWrite: return "any write"
        case .agentDelete: return "delete"
        case .agentSessionLongerThan(let t): return "session longer than \(Int(t)) s"
        case .agentPayloadLargerThan(let n): return "payload > \(n) bytes"
        case .privacyContainsCategory(let c): return "contains \(c.displayName.lowercased())"
        case .privacyMatchesMyIdentity: return "matches My Identity"
        case .privacyInOrgAllowlist: return "on org allowlist"
        case .privacySeverityAtLeast(let s): return "privacy severity ≥ \(s.rawValue)"
        case .all(let s): return s.map(summarize).joined(separator: " AND ")
        case .any(let s): return s.map(summarize).joined(separator: " OR ")
        case .not(let s): return "NOT (\(summarize(s)))"
        }
    }
}

// MARK: - Logger convenience

extension RuleEngine {
    /// Log a decision at the right level for ops triage.
    public func log(decision: RuleDecision, request: RuleRequest, agent: TargetApp) {
        switch decision.action {
        case .deny:
            engineLogger.info("\(agent.rawValue) \(String(describing: request)) → DENY (\(decision.matchedRuleName ?? "default"))")
        case .warn:
            engineLogger.info("\(agent.rawValue) \(String(describing: request)) → WARN (\(decision.matchedRuleName ?? ""))")
        default:
            engineLogger.debug("\(agent.rawValue) \(String(describing: request)) → \(decision.action.rawValue)")
        }
    }
}
