// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - Scope / Action / Source / Window

public enum RuleScope: String, Sendable, Codable, CaseIterable {
    case file
    case email
    case agent

    public var displayName: String {
        switch self {
        case .file: return "Files"
        case .email: return "Emails"
        case .agent: return "Agents"
        }
    }
}

/// The effect a rule has when its matcher hits.
/// Deny short-circuits the engine regardless of list order ("deny-wins");
/// allow/warn/redact/downgrade/log participate in first-match resolution.
public enum RuleAction: String, Sendable, Codable, CaseIterable {
    case allow
    case deny
    case warn
    case redact       // allow but strip detected PII/secrets from payload
    case summarize    // allow but send a summary, not the raw content
    case downgrade    // allow metadata only (no body / no contents)
    case log          // no effect on access, records the match for auditing
}

public enum RuleSource: String, Sendable, Codable, CaseIterable {
    case seeded          // built-in, immutable (secrets, shields, etc.)
    case userOverride    // user-created rule that explicitly outranks a seed
    case user            // user-authored custom rule
    case suggested       // generated from denial history; user must accept
    case imported        // migrated from a legacy store (e.g., EmailRuleSet v1)

    /// Group priority. Lower number = higher priority. Seeded denies always preempt via deny-sweep;
    /// this ordering only applies to same-action first-match resolution.
    public var groupPriority: Int {
        switch self {
        case .seeded: return 0
        case .userOverride: return 10
        case .user: return 20
        case .imported: return 30
        case .suggested: return 40
        }
    }

    public var isMutable: Bool {
        switch self {
        case .seeded: return false
        default: return true
        }
    }
}

/// Time-bounded activation window for a rule.
public enum RuleWindow: Sendable, Codable, Hashable, Equatable {
    case always
    case sessionOnly                // active only during an active grant
    case until(Date)                // active until the given instant
    case expireAfter(TimeInterval)  // active N seconds after createdAt
    case weekdayHours(days: Set<Weekday>, startMinute: Int, endMinute: Int)

    public var displayName: String {
        switch self {
        case .always: return "Always"
        case .sessionOnly: return "Session only"
        case .until(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Until \(formatter.string(from: date))"
        case .expireAfter(let interval):
            return "Expires after \(Int(interval / 3600))h"
        case .weekdayHours(let days, let startMinute, let endMinute):
            let dayNames = days.sorted(by: { $0.rawValue < $1.rawValue }).map(\.shortName).joined(separator: ",")
            let start = String(format: "%02d:%02d", startMinute / 60, startMinute % 60)
            let end = String(format: "%02d:%02d", endMinute / 60, endMinute % 60)
            return "\(dayNames) \(start)–\(end)"
        }
    }

    // Codable — tagged by "kind" so raw JSON is easy to hand-edit for tests.

    private enum CodingKeys: String, CodingKey { case kind, date, interval, days, startMinute, endMinute }
    private enum Kind: String, Codable { case always, sessionOnly, until, expireAfter, weekdayHours }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .always:
            try c.encode(Kind.always, forKey: .kind)
        case .sessionOnly:
            try c.encode(Kind.sessionOnly, forKey: .kind)
        case .until(let date):
            try c.encode(Kind.until, forKey: .kind)
            try c.encode(date, forKey: .date)
        case .expireAfter(let i):
            try c.encode(Kind.expireAfter, forKey: .kind)
            try c.encode(i, forKey: .interval)
        case .weekdayHours(let days, let start, let end):
            try c.encode(Kind.weekdayHours, forKey: .kind)
            try c.encode(days, forKey: .days)
            try c.encode(start, forKey: .startMinute)
            try c.encode(end, forKey: .endMinute)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .always:
            self = .always
        case .sessionOnly:
            self = .sessionOnly
        case .until:
            self = .until(try c.decode(Date.self, forKey: .date))
        case .expireAfter:
            self = .expireAfter(try c.decode(TimeInterval.self, forKey: .interval))
        case .weekdayHours:
            self = .weekdayHours(
                days: try c.decode(Set<Weekday>.self, forKey: .days),
                startMinute: try c.decode(Int.self, forKey: .startMinute),
                endMinute: try c.decode(Int.self, forKey: .endMinute)
            )
        }
    }

    /// Evaluates whether this window permits the rule to fire at `now`.
    public func isActive(now: Date, createdAt: Date, sessionActive: Bool, calendar: Calendar = .current) -> Bool {
        switch self {
        case .always:
            return true
        case .sessionOnly:
            return sessionActive
        case .until(let date):
            return now <= date
        case .expireAfter(let interval):
            return now.timeIntervalSince(createdAt) < interval
        case .weekdayHours(let days, let startMinute, let endMinute):
            let comps = calendar.dateComponents([.weekday, .hour, .minute], from: now)
            guard let weekday = comps.weekday.flatMap({ Weekday(calendarWeekday: $0) }),
                  days.contains(weekday),
                  let hour = comps.hour, let minute = comps.minute else { return false }
            let m = hour * 60 + minute
            return m >= startMinute && m < endMinute
        }
    }
}

public enum Weekday: Int, Sendable, Codable, CaseIterable, Hashable {
    case mon = 1, tue, wed, thu, fri, sat, sun

    public var shortName: String {
        switch self {
        case .mon: return "Mon"
        case .tue: return "Tue"
        case .wed: return "Wed"
        case .thu: return "Thu"
        case .fri: return "Fri"
        case .sat: return "Sat"
        case .sun: return "Sun"
        }
    }

    /// Calendar weekday uses 1=Sun through 7=Sat by default; convert to ISO Mon=1.
    public init?(calendarWeekday: Int) {
        switch calendarWeekday {
        case 1: self = .sun
        case 2: self = .mon
        case 3: self = .tue
        case 4: self = .wed
        case 5: self = .thu
        case 6: self = .fri
        case 7: self = .sat
        default: return nil
        }
    }
}

// MARK: - Agent tool / shield kinds (reused by matcher cases)

public enum AgentTool: String, Sendable, Codable, CaseIterable {
    case read
    case write
    case search
    case web
    case execute
    case delete

    public var displayName: String {
        switch self {
        case .read: return "Read"
        case .write: return "Write"
        case .search: return "Search"
        case .web: return "Web fetch"
        case .execute: return "Execute"
        case .delete: return "Delete"
        }
    }
}

/// Typed identifier for the five built-in email shields. Mirrors EmailShieldCatalog.
public enum EmailShieldKind: String, Sendable, Codable, CaseIterable {
    case security
    case financial
    case medical
    case legal
    case personal

    public var shieldID: String { rawValue }

    public var displayName: String {
        switch self {
        case .security: return "Security & 2FA"
        case .financial: return "Financial"
        case .medical: return "Medical"
        case .legal: return "Legal"
        case .personal: return "Personal"
        }
    }
}

public enum EmailKeywordField: String, Sendable, Codable, CaseIterable {
    case subject
    case body
    case subjectAndBody
    case anywhere

    public var displayName: String {
        switch self {
        case .subject: return "Subject"
        case .body: return "Body"
        case .subjectAndBody: return "Subject + Body"
        case .anywhere: return "Anywhere"
        }
    }
}

// MARK: - RuleMatcher (typed predicate tree)

public indirect enum RuleMatcher: Sendable, Codable, Hashable, Equatable {
    // File predicates
    case pathGlob(String)
    case pathRegex(String)
    case fileSizeOver(Int64)
    case fileSizeUnder(Int64)
    case fileAgeOlderThan(TimeInterval)
    case fileAgeNewerThan(TimeInterval)
    case fileHidden
    case fileBinary
    case fileSecretDetected
    case gitignored
    case fileExtension(String)

    // Email predicates
    case emailSender(String)
    case emailDomain(String)                               // wildcard ok: "*.bank.com"
    case emailSubjectKeyword(String, regex: Bool)
    case emailBodyKeyword(String, regex: Bool)
    case emailKeyword(EmailKeywordField, String, regex: Bool)
    case emailHasAttachment
    case emailAttachmentLargerThan(Int64)
    case emailShield(EmailShieldKind)
    case emailInFolder(String)
    case emailAccount(String)
    case emailOlderThan(TimeInterval)

    // Agent-behavior predicates
    case agentTool(AgentTool)
    case agentWrite                                        // any write-family request
    case agentDelete
    case agentSessionLongerThan(TimeInterval)
    case agentPayloadLargerThan(Int64)

    // Privacy predicates — scope-agnostic. Read from `PrivacyProbe`
    // supplied at evaluation time. A privacy matcher composes cleanly with
    // any scope-specific matcher via `.all` / `.any`, and alone it matches
    // regardless of scope (so a rule like "deny anything with a secret"
    // works whether the payload came from a file read, an email body, or
    // an agent tool call).
    case privacyContainsCategory(PrivacyCategory)
    case privacyMatchesMyIdentity
    case privacyInOrgAllowlist
    case privacySeverityAtLeast(PrivacySeverity)

    // Combinators
    case all([RuleMatcher])                                // AND
    case any([RuleMatcher])                                // OR
    case not(RuleMatcher)
    case always
    case never

    /// Convenience: flatten to the distinct top-level leaf cases, ignoring combinators.
    /// Used by the UI's match-preview to pick quick "what does this hit?" queries without
    /// full engine evaluation.
    public var leafCases: [RuleMatcher] {
        switch self {
        case .all(let subs), .any(let subs):
            return subs.flatMap(\.leafCases)
        case .not(let sub):
            return sub.leafCases
        default:
            return [self]
        }
    }

    /// The scope(s) this matcher touches. A rule whose matcher mixes scopes is rejected
    /// by validation — each rule picks exactly one of file/email/agent.
    public var inferredScopes: Set<RuleScope> {
        switch self {
        case .pathGlob, .pathRegex, .fileSizeOver, .fileSizeUnder,
             .fileAgeOlderThan, .fileAgeNewerThan, .fileHidden, .fileBinary,
             .fileSecretDetected, .gitignored, .fileExtension:
            return [.file]
        case .emailSender, .emailDomain, .emailSubjectKeyword, .emailBodyKeyword,
             .emailKeyword, .emailHasAttachment, .emailAttachmentLargerThan,
             .emailShield, .emailInFolder, .emailAccount, .emailOlderThan:
            return [.email]
        case .agentTool, .agentWrite, .agentDelete, .agentSessionLongerThan,
             .agentPayloadLargerThan:
            return [.agent]
        case .privacyContainsCategory, .privacyMatchesMyIdentity,
             .privacyInOrgAllowlist, .privacySeverityAtLeast:
            // Privacy matchers are scope-agnostic — they apply anywhere a
            // payload carries content, so we return an empty set and let
            // the rule's declared scope stand. Validation treats empty
            // as "any scope is fine" (see RuleValidator).
            return []
        case .all(let s), .any(let s):
            return s.reduce(into: Set<RuleScope>()) { $0.formUnion($1.inferredScopes) }
        case .not(let sub):
            return sub.inferredScopes
        case .always, .never:
            return []
        }
    }

    // Codable — tagged by "kind" so matchers round-trip cleanly through JSON & SQLite blobs.

    private enum CodingKeys: String, CodingKey { case kind, s1, s2, n1, b1, field, children, child }
    private enum Kind: String, Codable {
        case pathGlob, pathRegex
        case fileSizeOver, fileSizeUnder
        case fileAgeOlderThan, fileAgeNewerThan
        case fileHidden, fileBinary, fileSecretDetected, gitignored
        case fileExtension
        case emailSender, emailDomain
        case emailSubjectKeyword, emailBodyKeyword, emailKeyword
        case emailHasAttachment, emailAttachmentLargerThan
        case emailShield, emailInFolder, emailAccount, emailOlderThan
        case agentTool, agentWrite, agentDelete
        case agentSessionLongerThan, agentPayloadLargerThan
        case privacyContainsCategory, privacyMatchesMyIdentity
        case privacyInOrgAllowlist, privacySeverityAtLeast
        case all, any, not, always, never
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pathGlob(let s):
            try c.encode(Kind.pathGlob, forKey: .kind); try c.encode(s, forKey: .s1)
        case .pathRegex(let s):
            try c.encode(Kind.pathRegex, forKey: .kind); try c.encode(s, forKey: .s1)
        case .fileSizeOver(let n):
            try c.encode(Kind.fileSizeOver, forKey: .kind); try c.encode(n, forKey: .n1)
        case .fileSizeUnder(let n):
            try c.encode(Kind.fileSizeUnder, forKey: .kind); try c.encode(n, forKey: .n1)
        case .fileAgeOlderThan(let n):
            try c.encode(Kind.fileAgeOlderThan, forKey: .kind); try c.encode(n, forKey: .n1)
        case .fileAgeNewerThan(let n):
            try c.encode(Kind.fileAgeNewerThan, forKey: .kind); try c.encode(n, forKey: .n1)
        case .fileHidden: try c.encode(Kind.fileHidden, forKey: .kind)
        case .fileBinary: try c.encode(Kind.fileBinary, forKey: .kind)
        case .fileSecretDetected: try c.encode(Kind.fileSecretDetected, forKey: .kind)
        case .gitignored: try c.encode(Kind.gitignored, forKey: .kind)
        case .fileExtension(let s):
            try c.encode(Kind.fileExtension, forKey: .kind); try c.encode(s, forKey: .s1)
        case .emailSender(let s):
            try c.encode(Kind.emailSender, forKey: .kind); try c.encode(s, forKey: .s1)
        case .emailDomain(let s):
            try c.encode(Kind.emailDomain, forKey: .kind); try c.encode(s, forKey: .s1)
        case .emailSubjectKeyword(let s, let r):
            try c.encode(Kind.emailSubjectKeyword, forKey: .kind); try c.encode(s, forKey: .s1); try c.encode(r, forKey: .b1)
        case .emailBodyKeyword(let s, let r):
            try c.encode(Kind.emailBodyKeyword, forKey: .kind); try c.encode(s, forKey: .s1); try c.encode(r, forKey: .b1)
        case .emailKeyword(let f, let s, let r):
            try c.encode(Kind.emailKeyword, forKey: .kind); try c.encode(f, forKey: .field); try c.encode(s, forKey: .s1); try c.encode(r, forKey: .b1)
        case .emailHasAttachment: try c.encode(Kind.emailHasAttachment, forKey: .kind)
        case .emailAttachmentLargerThan(let n):
            try c.encode(Kind.emailAttachmentLargerThan, forKey: .kind); try c.encode(n, forKey: .n1)
        case .emailShield(let k):
            try c.encode(Kind.emailShield, forKey: .kind); try c.encode(k, forKey: .field)
        case .emailInFolder(let s):
            try c.encode(Kind.emailInFolder, forKey: .kind); try c.encode(s, forKey: .s1)
        case .emailAccount(let s):
            try c.encode(Kind.emailAccount, forKey: .kind); try c.encode(s, forKey: .s1)
        case .emailOlderThan(let n):
            try c.encode(Kind.emailOlderThan, forKey: .kind); try c.encode(n, forKey: .n1)
        case .agentTool(let t):
            try c.encode(Kind.agentTool, forKey: .kind); try c.encode(t, forKey: .field)
        case .agentWrite: try c.encode(Kind.agentWrite, forKey: .kind)
        case .agentDelete: try c.encode(Kind.agentDelete, forKey: .kind)
        case .agentSessionLongerThan(let n):
            try c.encode(Kind.agentSessionLongerThan, forKey: .kind); try c.encode(n, forKey: .n1)
        case .agentPayloadLargerThan(let n):
            try c.encode(Kind.agentPayloadLargerThan, forKey: .kind); try c.encode(n, forKey: .n1)
        case .privacyContainsCategory(let cat):
            try c.encode(Kind.privacyContainsCategory, forKey: .kind); try c.encode(cat, forKey: .field)
        case .privacyMatchesMyIdentity:
            try c.encode(Kind.privacyMatchesMyIdentity, forKey: .kind)
        case .privacyInOrgAllowlist:
            try c.encode(Kind.privacyInOrgAllowlist, forKey: .kind)
        case .privacySeverityAtLeast(let sev):
            try c.encode(Kind.privacySeverityAtLeast, forKey: .kind); try c.encode(sev, forKey: .field)
        case .all(let children):
            try c.encode(Kind.all, forKey: .kind); try c.encode(children, forKey: .children)
        case .any(let children):
            try c.encode(Kind.any, forKey: .kind); try c.encode(children, forKey: .children)
        case .not(let child):
            try c.encode(Kind.not, forKey: .kind); try c.encode(child, forKey: .child)
        case .always: try c.encode(Kind.always, forKey: .kind)
        case .never: try c.encode(Kind.never, forKey: .kind)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .pathGlob: self = .pathGlob(try c.decode(String.self, forKey: .s1))
        case .pathRegex: self = .pathRegex(try c.decode(String.self, forKey: .s1))
        case .fileSizeOver: self = .fileSizeOver(try c.decode(Int64.self, forKey: .n1))
        case .fileSizeUnder: self = .fileSizeUnder(try c.decode(Int64.self, forKey: .n1))
        case .fileAgeOlderThan: self = .fileAgeOlderThan(try c.decode(TimeInterval.self, forKey: .n1))
        case .fileAgeNewerThan: self = .fileAgeNewerThan(try c.decode(TimeInterval.self, forKey: .n1))
        case .fileHidden: self = .fileHidden
        case .fileBinary: self = .fileBinary
        case .fileSecretDetected: self = .fileSecretDetected
        case .gitignored: self = .gitignored
        case .fileExtension: self = .fileExtension(try c.decode(String.self, forKey: .s1))
        case .emailSender: self = .emailSender(try c.decode(String.self, forKey: .s1))
        case .emailDomain: self = .emailDomain(try c.decode(String.self, forKey: .s1))
        case .emailSubjectKeyword:
            self = .emailSubjectKeyword(try c.decode(String.self, forKey: .s1), regex: try c.decode(Bool.self, forKey: .b1))
        case .emailBodyKeyword:
            self = .emailBodyKeyword(try c.decode(String.self, forKey: .s1), regex: try c.decode(Bool.self, forKey: .b1))
        case .emailKeyword:
            self = .emailKeyword(
                try c.decode(EmailKeywordField.self, forKey: .field),
                try c.decode(String.self, forKey: .s1),
                regex: try c.decode(Bool.self, forKey: .b1)
            )
        case .emailHasAttachment: self = .emailHasAttachment
        case .emailAttachmentLargerThan: self = .emailAttachmentLargerThan(try c.decode(Int64.self, forKey: .n1))
        case .emailShield: self = .emailShield(try c.decode(EmailShieldKind.self, forKey: .field))
        case .emailInFolder: self = .emailInFolder(try c.decode(String.self, forKey: .s1))
        case .emailAccount: self = .emailAccount(try c.decode(String.self, forKey: .s1))
        case .emailOlderThan: self = .emailOlderThan(try c.decode(TimeInterval.self, forKey: .n1))
        case .agentTool: self = .agentTool(try c.decode(AgentTool.self, forKey: .field))
        case .agentWrite: self = .agentWrite
        case .agentDelete: self = .agentDelete
        case .agentSessionLongerThan: self = .agentSessionLongerThan(try c.decode(TimeInterval.self, forKey: .n1))
        case .agentPayloadLargerThan: self = .agentPayloadLargerThan(try c.decode(Int64.self, forKey: .n1))
        case .privacyContainsCategory:
            self = .privacyContainsCategory(try c.decode(PrivacyCategory.self, forKey: .field))
        case .privacyMatchesMyIdentity: self = .privacyMatchesMyIdentity
        case .privacyInOrgAllowlist: self = .privacyInOrgAllowlist
        case .privacySeverityAtLeast:
            self = .privacySeverityAtLeast(try c.decode(PrivacySeverity.self, forKey: .field))
        case .all: self = .all(try c.decode([RuleMatcher].self, forKey: .children))
        case .any: self = .any(try c.decode([RuleMatcher].self, forKey: .children))
        case .not: self = .not(try c.decode(RuleMatcher.self, forKey: .child))
        case .always: self = .always
        case .never: self = .never
        }
    }
}

// MARK: - RuleRecord

public struct RuleRecord: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public var explanation: String         // plain-English reason surfaced to users
    public var scope: RuleScope
    public var matcher: RuleMatcher
    public var action: RuleAction
    public var agents: Set<TargetApp>      // empty = all agents
    public var window: RuleWindow
    public var source: RuleSource
    public var enabled: Bool
    public var orderIndex: Int             // stable ordering within (scope, source) group
    public var createdAt: String           // ISO8601
    public var updatedAt: String           // ISO8601
    public var lastMatchedAt: String?      // ISO8601, rolling
    public var matchCount: Int             // 30-day rolling count (best-effort)

    public init(
        id: String = RuleRecord.generateID(),
        name: String,
        explanation: String = "",
        scope: RuleScope,
        matcher: RuleMatcher,
        action: RuleAction,
        agents: Set<TargetApp> = [],
        window: RuleWindow = .always,
        source: RuleSource = .user,
        enabled: Bool = true,
        orderIndex: Int = 0,
        createdAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        updatedAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        lastMatchedAt: String? = nil,
        matchCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.explanation = explanation
        self.scope = scope
        self.matcher = matcher
        self.action = action
        self.agents = agents
        self.window = window
        self.source = source
        self.enabled = enabled
        self.orderIndex = orderIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMatchedAt = lastMatchedAt
        self.matchCount = matchCount
    }

    public static func generateID(prefix: String = "rule") -> String {
        "\(prefix)-\(UUID().uuidString.prefix(8).lowercased())"
    }

    /// True if the rule applies to the given agent. Empty agents = all.
    public func applies(to agent: TargetApp) -> Bool {
        agents.isEmpty || agents.contains(agent)
    }

    public var createdAtDate: Date {
        ISO8601DateFormatter.shared.date(from: createdAt) ?? Date()
    }
}

// MARK: - Eval context, request, decision

public enum RuleRequest: Sendable, Hashable {
    case fileRead(path: String)
    case fileWrite(path: String)
    case emailRead(emailID: String)
    case agentTool(tool: AgentTool, payloadBytes: Int64?)
    case sessionTick                 // for time-window rules

    public var scope: RuleScope {
        switch self {
        case .fileRead, .fileWrite: return .file
        case .emailRead: return .email
        case .agentTool, .sessionTick: return .agent
        }
    }

    public var resourcePath: String? {
        switch self {
        case .fileRead(let p), .fileWrite(let p): return p
        default: return nil
        }
    }
}

/// Everything the engine needs to answer one question. Kept explicit so tests can
/// construct requests without dragging in the runtime.
public struct RuleEvalContext: Sendable {
    public var now: Date
    public var sessionActive: Bool
    public var fileProbe: FileProbe?
    public var emailProbe: EmailProbe?
    public var agentProbe: AgentProbe?
    public var privacyProbe: PrivacyProbe?

    public init(
        now: Date = Date(),
        sessionActive: Bool = true,
        fileProbe: FileProbe? = nil,
        emailProbe: EmailProbe? = nil,
        agentProbe: AgentProbe? = nil,
        privacyProbe: PrivacyProbe? = nil
    ) {
        self.now = now
        self.sessionActive = sessionActive
        self.fileProbe = fileProbe
        self.emailProbe = emailProbe
        self.agentProbe = agentProbe
        self.privacyProbe = privacyProbe
    }
}

/// Snapshot of the privacy model's findings for the payload under evaluation.
/// Supplied by the runtime so rule evaluation stays synchronous and cheap —
/// the heavy lifting (classification, identity matching, allowlist lookup)
/// happens once, then the probe carries the result to every matcher that
/// cares about privacy.
public struct PrivacyProbe: Sendable {
    public let categories: Set<PrivacyCategory>
    public let severity: PrivacySeverity
    public let matchesMyIdentity: Bool
    public let inOrgAllowlist: Bool

    public init(
        categories: Set<PrivacyCategory> = [],
        severity: PrivacySeverity = .none,
        matchesMyIdentity: Bool = false,
        inOrgAllowlist: Bool = false
    ) {
        self.categories = categories
        self.severity = severity
        self.matchesMyIdentity = matchesMyIdentity
        self.inOrgAllowlist = inOrgAllowlist
    }
}

/// Lazy probe passed into the engine so we don't `stat` files we don't need to.
public struct FileProbe: Sendable {
    public let path: String
    public var sizeBytes: @Sendable () -> Int64?
    public var modifiedAt: @Sendable () -> Date?
    public var isHidden: @Sendable () -> Bool
    public var isBinary: @Sendable () -> Bool
    public var isGitignored: @Sendable () -> Bool
    public var containsSecret: @Sendable () -> Bool

    public init(
        path: String,
        sizeBytes: @escaping @Sendable () -> Int64? = { nil },
        modifiedAt: @escaping @Sendable () -> Date? = { nil },
        isHidden: @escaping @Sendable () -> Bool = { false },
        isBinary: @escaping @Sendable () -> Bool = { false },
        isGitignored: @escaping @Sendable () -> Bool = { false },
        containsSecret: @escaping @Sendable () -> Bool = { false }
    ) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.isHidden = isHidden
        self.isBinary = isBinary
        self.isGitignored = isGitignored
        self.containsSecret = containsSecret
    }
}

public struct EmailProbe: Sendable {
    public let emailID: String
    public let senderEmail: String
    public let senderDomain: String
    public let subject: String
    public let bodyText: String
    public let folder: String
    public let accountID: String
    public let hasAttachment: Bool
    public let largestAttachmentBytes: Int64
    public let receivedAt: Date
    public let matchedShields: Set<EmailShieldKind>

    public init(
        emailID: String,
        senderEmail: String,
        senderDomain: String,
        subject: String,
        bodyText: String = "",
        folder: String = "",
        accountID: String = "",
        hasAttachment: Bool = false,
        largestAttachmentBytes: Int64 = 0,
        receivedAt: Date = Date(),
        matchedShields: Set<EmailShieldKind> = []
    ) {
        self.emailID = emailID
        self.senderEmail = senderEmail.lowercased()
        self.senderDomain = senderDomain.lowercased()
        self.subject = subject
        self.bodyText = bodyText
        self.folder = folder
        self.accountID = accountID
        self.hasAttachment = hasAttachment
        self.largestAttachmentBytes = largestAttachmentBytes
        self.receivedAt = receivedAt
        self.matchedShields = matchedShields
    }
}

public struct AgentProbe: Sendable {
    public let agent: TargetApp
    public let tool: AgentTool?
    public let payloadBytes: Int64?
    public let sessionStartedAt: Date?

    public init(
        agent: TargetApp,
        tool: AgentTool? = nil,
        payloadBytes: Int64? = nil,
        sessionStartedAt: Date? = nil
    ) {
        self.agent = agent
        self.tool = tool
        self.payloadBytes = payloadBytes
        self.sessionStartedAt = sessionStartedAt
    }
}

/// Outcome of rule evaluation. `matchedRule == nil` with `action == .allow` means
/// nothing hit and the default policy wins.
public struct RuleDecision: Sendable, Codable, Hashable {
    public let action: RuleAction
    public let matchedRuleID: String?
    public let matchedRuleName: String?
    public let matchedMatcherSummary: String?
    public let explanation: String
    public let defaultPolicyApplied: Bool

    public init(
        action: RuleAction,
        matchedRuleID: String? = nil,
        matchedRuleName: String? = nil,
        matchedMatcherSummary: String? = nil,
        explanation: String,
        defaultPolicyApplied: Bool = false
    ) {
        self.action = action
        self.matchedRuleID = matchedRuleID
        self.matchedRuleName = matchedRuleName
        self.matchedMatcherSummary = matchedMatcherSummary
        self.explanation = explanation
        self.defaultPolicyApplied = defaultPolicyApplied
    }

    public var allowed: Bool {
        switch action {
        case .allow, .warn, .redact, .summarize, .downgrade, .log: return true
        case .deny: return false
        }
    }

    public static func allow(defaultPolicy: Bool = true, explanation: String = "Allowed by default policy") -> RuleDecision {
        .init(action: .allow, explanation: explanation, defaultPolicyApplied: defaultPolicy)
    }

    public static func deny(defaultPolicy: Bool = true, explanation: String = "Denied by default policy") -> RuleDecision {
        .init(action: .deny, explanation: explanation, defaultPolicyApplied: defaultPolicy)
    }
}

// MARK: - Validation

public enum RuleValidationError: LocalizedError, Sendable, Equatable {
    case emptyName
    case matcherScopeMismatch(expected: RuleScope, actual: Set<RuleScope>)
    case matcherEmpty
    case seededRuleImmutable
    case invalidRegex(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Rule needs a name."
        case .matcherScopeMismatch(let e, let a):
            return "Rule scope is \(e.displayName) but the matcher touches \(a.map(\.displayName).joined(separator: ", "))."
        case .matcherEmpty: return "Rule needs at least one condition."
        case .seededRuleImmutable: return "Seeded rules can't be edited directly — create an override instead."
        case .invalidRegex(let s): return "Invalid regular expression: \(s)"
        }
    }
}

public enum RuleValidator {
    public static func validate(_ rule: RuleRecord) throws {
        guard !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuleValidationError.emptyName
        }
        let scopes = rule.matcher.inferredScopes
        if !scopes.isEmpty, scopes != [rule.scope] {
            throw RuleValidationError.matcherScopeMismatch(expected: rule.scope, actual: scopes)
        }
        if case .all(let children) = rule.matcher, children.isEmpty {
            throw RuleValidationError.matcherEmpty
        }
        if case .any(let children) = rule.matcher, children.isEmpty {
            throw RuleValidationError.matcherEmpty
        }
        try validateRegex(in: rule.matcher)
    }

    private static func validateRegex(in matcher: RuleMatcher) throws {
        switch matcher {
        case .pathRegex(let s):
            _ = try regex(s)
        case .emailSubjectKeyword(let s, let r), .emailBodyKeyword(let s, let r):
            if r { _ = try regex(s) }
        case .emailKeyword(_, let s, let r):
            if r { _ = try regex(s) }
        case .all(let children), .any(let children):
            for c in children { try validateRegex(in: c) }
        case .not(let c):
            try validateRegex(in: c)
        default:
            return
        }
    }

    private static func regex(_ pattern: String) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            throw RuleValidationError.invalidRegex(pattern)
        }
    }
}
