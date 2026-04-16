// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// SessionPrimitives — UI-facing types for the new surface.
//
// Per design/09-migration-plan.md §1, these replace the implicit concepts
// scattered across the legacy UI (WorkBlock for sessions, ReviewAccessSheet
// for approvals, ad-hoc dictionaries for rules) with named, Hashable,
// Sendable structs the SwiftUI layer can observe directly.
//
// These types live in the app because they are UI adapters. Runtime-side
// storage types remain in ManifoldKit (WorkBlockRecord, GrantRecord,
// RequestRecord, etc.). PolicyModel and ManifoldStore provide the bridge.

import Foundation
import ManifoldKit

// MARK: - Session

/// A live or historical session — what the user named it, the agents it
/// includes, and the scope adjustments made inside it.
struct SessionRecord: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let startedAt: Date
    let expiresAt: Date?
    let agents: Set<TargetApp>
    let baseMode: BaseMode
    let trackWrites: Bool
    /// True when this session is actively tracking file writes.
    let isTrackedEdit: Bool
    let additions: [SessionScopeChange]
    let removals: [SessionScopeChange]

    enum BaseMode: Hashable, Sendable {
        case defaultScope      // starts with the agent's default
        case blank             // starts with no scope
        case defaultMinus      // default minus explicit removals
    }

    var remainingSeconds: TimeInterval? {
        guard let expiresAt else { return nil }
        return max(0, expiresAt.timeIntervalSinceNow)
    }

    /// Display helper: "Jane follow-up · 2h 12m remaining".
    var displayDuration: String? {
        guard let remaining = remainingSeconds else { return nil }
        let h = Int(remaining) / 3600
        let m = (Int(remaining) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m remaining" : "\(m)m remaining"
    }
}

/// A single scope addition or removal made during a session.
struct SessionScopeChange: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let displayName: String
    let kind: Kind
    let at: Date

    enum Kind: Hashable, Sendable { case file, folder, mailbox }
}

/// A past session indexed for the Recent / Resume list.
struct SessionHistoryEntry: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let startedAt: Date
    let endedAt: Date
    let agents: Set<TargetApp>
    let eventCount: Int
    let additions: [SessionScopeChange]
    let removals: [SessionScopeChange]

    var displayLastRun: String {
        RelativeDateTimeFormatter().localizedString(for: endedAt, relativeTo: .now)
    }
    var displayDuration: String {
        let interval = endedAt.timeIntervalSince(startedAt)
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return h > 0 ? "\(h)h" : "\(m)m"
    }
}

/// Drift between a past session and the current scope state, computed
/// when the user asks to reload that session.
struct SessionDrift: Hashable, Sendable {
    let historyEntry: SessionHistoryEntry
    /// Paths in the session whose contents have changed since it ended.
    let pathsChangedSinceEnded: [String]
    /// Session additions that are no longer accessible (user revoked
    /// them after the session closed).
    let pathsRevokedSinceEnded: [String]
    /// Scope additions the user has made since this session ended;
    /// surface so the user can decide whether to inherit them.
    let newlyAddedSinceEnded: [String]

    var isClean: Bool {
        pathsChangedSinceEnded.isEmpty
        && pathsRevokedSinceEnded.isEmpty
        && newlyAddedSinceEnded.isEmpty
    }
}

/// Form-backing draft for the SessionStartSheet / ReloadDriftSheet.
///
/// `durationHours == nil` means "run until the user finishes manually"
/// — no auto-expiry. The default remains a bounded 2-hour session so
/// the safe choice is still the default (Principle 3). When a time-
/// limited session expires, the runtime ends it; with `nil`, the
/// session lives until the user hits Finish in the StatusBar / menu
/// bar panel.
struct SessionDraft: Hashable, Sendable {
    var name: String = ""
    var durationHours: Double? = 2
    var agents: Set<TargetApp> = [.cowork]
    var baseMode: SessionRecord.BaseMode = .defaultScope
    var trackWrites: Bool = false
}

// MARK: - Approval queue

/// A pending agent request for expanded scope. Accumulates on the queue
/// rather than firing a modal (Principle 2 — modelessness).
struct ApprovalRequest: Identifiable, Hashable, Sendable {
    let id: String
    let agent: TargetApp
    let operation: Operation
    let target: String
    let headline: String
    let context: String
    let createdAt: Date
    var snoozedUntil: Date?

    enum Operation: Hashable, Sendable {
        case readFile
        case readFolder
        case write
        case searchContent
        case listDirectory
        case mailboxRead
    }
}

/// How a request was answered. Drives persistence of the decision.
enum ApprovalAnswer: Hashable, Sendable {
    /// One-time deny, no promoted scope, no rule.
    case notThisTime
    /// Allow this exact request, no persisted scope addition.
    case once
    /// Add target to the active session's scope (session must be live).
    case forSession(sessionID: String)
    /// Promote target to the agent's default scope.
    case addToDefault
}

/// A recorded denial — feeds blast-radius charts and the pattern-detection
/// inspector on the Requests surface.
struct DenialEvent: Identifiable, Hashable, Sendable {
    let id: String
    let agent: TargetApp
    let target: String
    let ruleID: String?
    let operation: ApprovalRequest.Operation
    let at: Date
}

// MARK: - Rules

/// A global rule (files / email / agents domain) with subject/verb/object
/// grammar per design/09-migration-plan.md §7.
struct Rule: Identifiable, Hashable, Sendable {
    let id: String
    let domain: Domain
    let verb: Verb
    /// Human-readable subject: "files matching *.env".
    let subject: String
    /// Human-readable object: "anywhere", "in ~/Finances", etc.
    let object: String
    /// Machine pattern (glob / predicate) used for matching.
    let pattern: String
    var enabled: Bool
    /// True if this rule shipped with Manifold's default seed (cannot be
    /// edited, only toggled).
    let seeded: Bool
    let createdBy: CreatedBy
    let createdAt: Date

    /// Most recent time this rule fired, if ever. Remains nil until the
    /// runtime starts writing rule-fired events to the audit log — the
    /// view reads this and renders "Not yet fired" when it is nil
    /// (Principle 10: honesty — no fake counts).
    var lastFiredAt: Date?
    /// How many times this rule has fired in the past seven days, if the
    /// runtime is tracking it. Defaults to 0 — same honesty contract
    /// as `lastFiredAt`.
    var firesPast7Days: Int

    init(
        id: String,
        domain: Domain,
        verb: Verb,
        subject: String,
        object: String,
        pattern: String,
        enabled: Bool,
        seeded: Bool,
        createdBy: CreatedBy,
        createdAt: Date,
        lastFiredAt: Date? = nil,
        firesPast7Days: Int = 0
    ) {
        self.id = id
        self.domain = domain
        self.verb = verb
        self.subject = subject
        self.object = object
        self.pattern = pattern
        self.enabled = enabled
        self.seeded = seeded
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.lastFiredAt = lastFiredAt
        self.firesPast7Days = firesPast7Days
    }

    enum Domain: String, Hashable, Sendable, CaseIterable {
        case files
        case email
        case agents
    }

    enum Verb: String, Hashable, Sendable {
        case allow
        case deny
        case warn
    }

    enum CreatedBy: Hashable, Sendable {
        case user
        case seeded
        /// Surfaced from the pattern-detection inspector: "You denied
        /// this pattern N times — want a rule?"
        case suggested(denialCount: Int)
    }
}

// MARK: - Scope

/// A single agent-to-source binding (folder, mailbox, or individual file).
/// This is the row type for the Access Folders matrix and the scope rail.
struct ScopeEntry: Identifiable, Hashable, Sendable {
    let id: String
    let agent: TargetApp
    let kind: Kind
    let path: String
    let displayName: String
    let addedAt: Date
    /// True if this entry was added inside a session (lives only as long
    /// as the session is live, unless promoted to default).
    let fromSession: Bool

    enum Kind: Hashable, Sendable { case folder, mailbox, file }
}

// MARK: - Revert

/// Outcome of a user-initiated revert (from Activity evidence inspector
/// or from the Files version timeline).
enum RevertOutcome: Hashable, Sendable {
    case reverted(filePath: String, toVersion: String)
    case alreadyMatchesOrigin
    case conflictWithCurrentEdit
    case missingSnapshot
    case error(message: String)
}

// MARK: - Commands protocol
//
// All write-path operations the UI might perform are declared here so
// view code doesn't reach into model internals. The default implementation
// (see `ManifoldStoreCommands`) routes every call through ManifoldStore
// so the runtime boundary stays single-source (CLAUDE.md §Editing Rules).

@MainActor
protocol ManifoldCommands: AnyObject {
    // Approvals
    func answer(_ request: ApprovalRequest, with answer: ApprovalAnswer) async

    // Sessions
    func startSession(_ draft: SessionDraft) async throws
    func finishActiveSession() async throws
    func reloadSession(historyID: String) async throws

    // Scope
    func shareSource(path: String, with agent: TargetApp) async throws
    func revokeScope(entryID: String) async throws

    // Rules
    func createRule(_ rule: Rule) async throws
    func setRule(_ ruleID: String, enabled: Bool) async throws
    func deleteRule(_ ruleID: String) async throws

    // Revert
    func revert(filePath: String, toSnapshot: String) async -> RevertOutcome

    // Agent lifecycle
    func pauseAgent(_ agent: TargetApp) async
    func resumeAgent(_ agent: TargetApp) async
}

// MARK: - Adapter from legacy runtime types

extension SessionRecord {
    /// Build a SessionRecord view over an active WorkBlockRecord + its
    /// associated grant. Keeps the Stage-6 vocabulary at the UI layer while
    /// the runtime still speaks WorkBlock / Grant.
    init(workBlock: WorkBlockRecord,
         grantName: String? = nil,
         expiresAt: Date? = nil,
         additions: [SessionScopeChange] = [],
         removals: [SessionScopeChange] = []) {
        self.id = workBlock.id
        self.name = grantName
            ?? "Session · \(DateFormatter.sessionName.string(from: Self.parseISO(workBlock.startedAt) ?? .now))"
        self.startedAt = Self.parseISO(workBlock.startedAt) ?? .now
        self.expiresAt = expiresAt
        self.agents = [workBlock.agent]
        self.baseMode = .defaultScope
        self.trackWrites = true
        self.isTrackedEdit = (workBlock.status == .active
                              || workBlock.status == .paused
                              || workBlock.status == .reviewing)
        self.additions = additions
        self.removals = removals
    }

    private static func parseISO(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}

private extension DateFormatter {
    static let sessionName: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm"
        return f
    }()
}
