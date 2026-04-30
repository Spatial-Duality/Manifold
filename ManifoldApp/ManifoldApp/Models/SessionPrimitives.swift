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
// RequestRecord, etc.). GovernanceModel and ManifoldStore provide the bridge.

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

/// A past session indexed for the Recent / review list.
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

/// Form-backing draft for gateway session activation.
struct SessionDraft: Hashable, Sendable {
    var name: String = ""
    var durationHours: Double = 2
    var agents: Set<TargetApp> = [.cowork]
    var baseMode: SessionRecord.BaseMode = .defaultScope
    var trackWrites: Bool = false
    var usesExplicitFileSelection: Bool = false
    var selectedSourceIDs: Set<String> = []
    var selectedEmailIDs: Set<String> = []
}

// MARK: - Approval queue

/// A pending agent request for expanded scope. Accumulates on the queue
/// rather than firing a modal (Principle 2 — modelessness).
struct ApprovalRequest: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case standingWrite = "standing_write"
        case privacyExposure = "privacy_exposure"
    }

    let id: String
    let kind: Kind
    let agent: TargetApp
    let operation: Operation
    let target: String
    let headline: String
    let context: String
    let findingsSummary: String?
    let recommendation: String?
    let createdAt: Date
    var snoozedUntil: Date?
    /// Populated only for `.privacyExposure`. A short excerpt of what the
    /// agent would see after the privacy model redacts the payload. The
    /// original is never persisted on-disk, so this is the authoritative
    /// surface for approval review.
    let redactedPreview: String?
    /// Populated only for `.privacyExposure`. The category taxonomy the
    /// model matched against the payload (email, secret, account, …).
    let matchedCategories: [PrivacyCategory]
    /// Populated only for `.privacyExposure`. Severity the decision engine
    /// assigned — drives the severity bar in the approval card.
    let severity: PrivacySeverity?

    var supportsSessionScope: Bool {
        switch kind {
        case .standingWrite:
            return false
        case .privacyExposure:
            return false
        }
    }

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
    /// Reserved for future request kinds that bind to a live session.
    case forSession(sessionID: String)
    /// Promote target to the agent's default standing scope.
    case addToDefault
    /// Share the redacted payload one time.
    case shareRedacted
    /// Share the original payload one time.
    case shareOriginalOnce
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
    func previewSession(draft: SessionDraft) async throws
    func startGatewaySession(draft: SessionDraft) async throws
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
    init(storageRecord: WorkBlockRecord,
         grantName: String? = nil,
         expiresAt: Date? = nil,
         additions: [SessionScopeChange] = [],
         removals: [SessionScopeChange] = []) {
        self.id = storageRecord.id
        self.name = grantName
            ?? "Session · \(DateFormatter.sessionName.string(from: Self.parseISO(storageRecord.startedAt) ?? .now))"
        self.startedAt = Self.parseISO(storageRecord.startedAt) ?? .now
        self.expiresAt = expiresAt
        self.agents = [storageRecord.agent]
        self.baseMode = .defaultScope
        self.trackWrites = true
        self.isTrackedEdit = (storageRecord.status == .active
                              || storageRecord.status == .paused
                              || storageRecord.status == .reviewing)
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
