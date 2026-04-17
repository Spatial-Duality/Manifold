// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import ManifoldXPC

struct DashboardState: Codable, Sendable {
    let runtimeConnected: Bool
    let activeBridgeCount: Int
    let connectedAgents: [String]
    let sources: [SourceRecord]
    let claudePolicy: AgentAccessPolicy
    let codexPolicy: AgentAccessPolicy
    let claudeEmailGovernance: AgentEmailGovernanceSummary
    let codexEmailGovernance: AgentEmailGovernanceSummary
    let activeSession: WorkBlockRecord?
    let pendingApprovalCount: Int
    let agentCoverages: [AgentCoverageSnapshot]
    let coverageEvents: [CoverageEvent]

    private enum CodingKeys: String, CodingKey {
        case runtimeConnected
        case activeBridgeCount
        case connectedAgents
        case sources
        case claudePolicy
        case codexPolicy
        case claudeEmailGovernance
        case codexEmailGovernance
        case activeSession
        case activeWorkBlock
        case pendingApprovalCount
        case agentCoverages
        case coverageEvents
    }

    init(
        runtimeConnected: Bool,
        activeBridgeCount: Int,
        connectedAgents: [String],
        sources: [SourceRecord],
        claudePolicy: AgentAccessPolicy,
        codexPolicy: AgentAccessPolicy,
        claudeEmailGovernance: AgentEmailGovernanceSummary,
        codexEmailGovernance: AgentEmailGovernanceSummary,
        activeSession: WorkBlockRecord?,
        pendingApprovalCount: Int,
        agentCoverages: [AgentCoverageSnapshot],
        coverageEvents: [CoverageEvent]
    ) {
        self.runtimeConnected = runtimeConnected
        self.activeBridgeCount = activeBridgeCount
        self.connectedAgents = connectedAgents
        self.sources = sources
        self.claudePolicy = claudePolicy
        self.codexPolicy = codexPolicy
        self.claudeEmailGovernance = claudeEmailGovernance
        self.codexEmailGovernance = codexEmailGovernance
        self.activeSession = activeSession
        self.pendingApprovalCount = pendingApprovalCount
        self.agentCoverages = agentCoverages
        self.coverageEvents = coverageEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let claudePolicy = try container.decode(AgentAccessPolicy.self, forKey: .claudePolicy)
        let codexPolicy = try container.decode(AgentAccessPolicy.self, forKey: .codexPolicy)

        self.runtimeConnected = try container.decodeIfPresent(Bool.self, forKey: .runtimeConnected) ?? true
        self.activeBridgeCount = try container.decodeIfPresent(Int.self, forKey: .activeBridgeCount) ?? 0
        self.connectedAgents = try container.decodeIfPresent([String].self, forKey: .connectedAgents) ?? []
        self.sources = try container.decodeIfPresent([SourceRecord].self, forKey: .sources) ?? []
        self.claudePolicy = claudePolicy
        self.codexPolicy = codexPolicy
        self.claudeEmailGovernance =
            try container.decodeIfPresent(AgentEmailGovernanceSummary.self, forKey: .claudeEmailGovernance)
            ?? Self.legacyGovernanceSummary(for: claudePolicy)
        self.codexEmailGovernance =
            try container.decodeIfPresent(AgentEmailGovernanceSummary.self, forKey: .codexEmailGovernance)
            ?? Self.legacyGovernanceSummary(for: codexPolicy)
        if let activeSession = try container.decodeIfPresent(WorkBlockRecord.self, forKey: .activeSession) {
            self.activeSession = activeSession
        } else {
            self.activeSession = try container.decodeIfPresent(WorkBlockRecord.self, forKey: .activeWorkBlock)
        }
        self.pendingApprovalCount = try container.decodeIfPresent(Int.self, forKey: .pendingApprovalCount) ?? 0
        self.agentCoverages = try container.decodeIfPresent([AgentCoverageSnapshot].self, forKey: .agentCoverages) ?? []
        self.coverageEvents = try container.decodeIfPresent([CoverageEvent].self, forKey: .coverageEvents) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(runtimeConnected, forKey: .runtimeConnected)
        try container.encode(activeBridgeCount, forKey: .activeBridgeCount)
        try container.encode(connectedAgents, forKey: .connectedAgents)
        try container.encode(sources, forKey: .sources)
        try container.encode(claudePolicy, forKey: .claudePolicy)
        try container.encode(codexPolicy, forKey: .codexPolicy)
        try container.encode(claudeEmailGovernance, forKey: .claudeEmailGovernance)
        try container.encode(codexEmailGovernance, forKey: .codexEmailGovernance)
        try container.encodeIfPresent(activeSession, forKey: .activeSession)
        try container.encode(pendingApprovalCount, forKey: .pendingApprovalCount)
        try container.encode(agentCoverages, forKey: .agentCoverages)
        try container.encode(coverageEvents, forKey: .coverageEvents)
    }

    private static func legacyGovernanceSummary(for governance: AgentAccessPolicy) -> AgentEmailGovernanceSummary {
        AgentEmailGovernanceSummary(
            agent: governance.agent,
            enabledShieldCount: 0,
            domainRuleCount: governance.allowedEmailDomains.count,
            contactRuleCount: 0,
            keywordRuleCount: 0,
            defaultPolicy: governance.defaultEmailPolicy,
            emailSensitivity: governance.emailSensitivity
        )
    }
}

struct ActiveGrantState: Codable, Sendable {
    let activeGrant: GrantRecord?
    let activeGrantSources: [GrantSourceRecord]
    let targetApp: String?
}

struct StorageStatsSnapshot: Codable, Sendable {
    let storageUsed: Int64
}

struct WorkBlockPreview: Codable, Sendable {
    let applied: [String]
    let conflicts: [String]
    let newFiles: [String]
    let skipped: Int
}

struct ApplyTrackedRunResult: Codable, Sendable {
    let grantID: String
    let filesApplied: [String]
    let filesConflicted: [String]
    let appliedCount: Int
    let conflictCount: Int
}

struct RevertEventResult: Codable, Sendable {
    let status: String
    let message: String?
}

extension RestoreSnapshotResult {
    var isSuccess: Bool { status == "success" }
    var isConflict: Bool { status == "conflict" }
}

struct EmailBackupInfo: Codable, Sendable {
    let path: String
    let diskUsage: Int64
}

struct RuntimePingResult: Sendable {
    let ok: Bool
    let agentVersion: String?
}

enum RuntimeClientStubError: Error, LocalizedError {
    case unimplemented(String)

    var errorDescription: String? {
        switch self {
        case .unimplemented(let method):
            return "Runtime stub does not implement \(method)."
        }
    }
}

protocol RuntimeClientProtocol: Sendable {
    func ping() async -> RuntimePingResult
    func dashboardState() async throws -> DashboardState
    func listSources() async throws -> [SourceRecord]
    func addSource(path: String, displayName: String) async throws -> SourceRecord
    func removeSource(sourceID: String) async throws
    func pauseSource(sourceID: String) async throws
    func resumeSource(sourceID: String) async throws
    func policies() async throws -> DashboardState
    func pauseAgent(_ agent: TargetApp) async throws
    func resumeAgent(_ agent: TargetApp) async throws
    func addSource(_ sourceID: String, to agent: TargetApp) async throws
    func removeSource(_ sourceID: String, from agent: TargetApp) async throws
    func updateAccessRecordingLevel(_ level: AccessRecordingLevel, for agent: TargetApp) async throws
    func getEmailRuleSet(agent: TargetApp) async throws -> EmailRuleSet
    func updateEmailRuleSet(agent: TargetApp, ruleSet: EmailRuleSet) async throws
    func getEmailRuleActivitySummary(agent: TargetApp) async throws -> EmailRuleActivitySummary
    func activeGrantState(targetApp: TargetApp) async throws -> ActiveGrantState
    func sessionPreview(
        targetApp: TargetApp,
        fileScopes: [FileSelectionScope],
        selectedEmailIDs: Set<String>,
        emailSensitivity: String?
    ) async throws -> SessionPreview
    func startTrackedRun(
        targetApp: TargetApp,
        fileScopes: [FileSelectionScope],
        selectedEmailIDs: Set<String>,
        summaryFraming: String?,
        noteCaptureMode: SessionNoteCaptureMode,
        emailSensitivity: String?
    ) async throws -> ActiveGrantState
    func restoreSnapshot(snapshotID: Int, filePath: String) async throws -> RestoreSnapshotResult
    func markWorkBlockReviewing(id: String) async throws
    func cancelWorkBlockReview(id: String) async throws
    func pauseTrackedRun(id: String) async throws
    func resumeTrackedRun(id: String) async throws
    func discardTrackedRun(id: String, grantID: String?, endSession: Bool) async throws
    func promotionPreview(grantID: String) async throws -> WorkBlockPreview
    func applyTrackedRun(grantID: String, endSession: Bool) async throws -> ApplyTrackedRunResult
    func recentActivity(limit: Int) async throws -> [AuditEntry]
    func recentSessions(limit: Int) async throws -> [Session]
    func sessionEvents(sessionID: String) async throws -> [SessionEvent]
    func revertSessionEvent(event: SessionEvent, grantID: String, force: Bool) async throws -> RevertEventResult
    func trackedFiles() async throws -> [String]
    func storageStats() async throws -> StorageStatsSnapshot
    func fileHistory(filePath: String) async throws -> [SnapshotRecord]
    func fileHistoryContext(filePath: String, limit: Int) async throws -> FileHistoryContext
    func sessionContext(sessionID: String, agent: TargetApp?) async throws -> SessionContextDetail
    func snapshotData(hash: String) async throws -> Data?
    func runGarbageCollection() async throws -> Int
    func runIntegrityCheck() async throws -> Bool
    func listEmailAccounts() async throws -> [EmailAccountRecord]
    func syncStates(accountID: String) async throws -> [SyncStateRecord]
    func emailMessageCount() async throws -> Int
    func addIMAPAccount(
        displayName: String,
        provider: EmailProvider,
        server: String,
        port: Int,
        username: String,
        password: String
    ) async throws -> EmailAccountRecord
    func removeEmailAccount(id: String) async throws
    func toggleEmailSync(accountID: String, enabled: Bool) async throws
    func syncEmailNow(accountID: String) async throws -> SyncResult
    func emailMessages(accountID: String?, mailbox: String?, ids: [String]?, limit: Int) async throws -> [EmailMessageRecord]
    func domainCounts() async throws -> [String: Int]
    func unreadCountAll() async throws -> Int
    func unreadCount(accountID: String, mailbox: String?) async throws -> Int
    func imapMailboxes(accountID: String) async throws -> [IMAPMailboxRecord]
    func sharedEmailCount() async throws -> Int
    func sharedEmailIDs() async throws -> Set<String>
    func sharedEmails(limit: Int) async throws -> [EmailMessageRecord]
    func shareEmails(emailIDs: [String]) async throws
    func unshareEmails(emailIDs: [String]) async throws
    func unshareAllEmails() async throws
    func updateEmailReadState(emailID: String, isRead: Bool) async throws
    func updateEmailFlagState(emailID: String, isFlagged: Bool, flagColor: String?) async throws
    func batchUpdateReadState(emailIDs: [String], isRead: Bool) async throws
    func batchUpdateFlagState(emailIDs: [String], isFlagged: Bool, flagColor: String?) async throws
    func searchEmailMessages(
        tokens: [SearchToken],
        freeText: String,
        accountID: String?,
        mailbox: String?,
        filter: QuickFilter?,
        sortKey: EmailSortKey,
        limit: Int
    ) async throws -> [EmailMessageRecord]
    func createSmartMailbox(displayName: String, iconName: String, rulesJSON: String) async throws
    func listSmartMailboxes() async throws -> [SmartMailboxRecord]
    func updateSmartMailbox(mailboxID: String, displayName: String, iconName: String, rulesJSON: String) async throws
    func deleteSmartMailbox(mailboxID: String) async throws
    func emailBackupInfo() async throws -> EmailBackupInfo
    func fileVisibilityOverrides(agent: TargetApp) async throws -> [FileVisibilityOverrideRecord]
    func setFileVisibilityOverride(
        agent: TargetApp,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool,
        decision: FileVisibilityOverrideDecision
    ) async throws
    func clearFileVisibilityOverride(
        agent: TargetApp,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool
    ) async throws

    // MARK: - Approval queue (Phase-5 wiring)

    /// Pending approval requests from the runtime's ApprovalQueue.
    func listPendingApprovals() async throws -> [PendingApprovalRecord]
    /// Resolve a pending request. Accepted values depend on the runtime request kind.
    func answerApproval(id: String, answer: String) async throws

    // MARK: - Unified rules (files / emails / agents)

    /// Returns all rules, optionally filtered by scope.
    func listRules(scope: RuleScope?) async throws -> [RuleRecord]
    /// Inserts or updates a rule.
    func upsertRule(_ rule: RuleRecord) async throws
    /// Deletes a user-authored rule. Seeded rules throw.
    func deleteRule(id: String) async throws
    /// Toggles enabled state for a rule.
    func setRuleEnabled(id: String, enabled: Bool) async throws
    /// Replaces the ordering of rules within a scope.
    func reorderRules(scope: RuleScope, ids: [String]) async throws
    /// Re-applies the seeded catalog (idempotent). Used by Settings > Rules > Reset seeded rules.
    func resetSeededRules() async throws
    /// Live preview — "how many files/emails would match this rule right now?"
    func previewRuleMatches(rule: RuleRecord, agent: TargetApp) async throws -> RuleMatchPreview
}

/// Plain Sendable record mirroring ApprovalQueue.PendingRequest across XPC.
public struct PendingApprovalRecord: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let connectionID: String
    public let agent: String
    public let path: String
    public let action: String
    public let kind: String
    public let sourceID: String?
    public let mountName: String?
    public let relativePath: String?
    public let requestedAt: Double
    public let status: String

    public init(
        id: String,
        connectionID: String,
        agent: String,
        path: String,
        action: String,
        kind: String = "standing_write",
        sourceID: String? = nil,
        mountName: String? = nil,
        relativePath: String? = nil,
        requestedAt: Double,
        status: String
    ) {
        self.id = id
        self.connectionID = connectionID
        self.agent = agent
        self.path = path
        self.action = action
        self.kind = kind
        self.sourceID = sourceID
        self.mountName = mountName
        self.relativePath = relativePath
        self.requestedAt = requestedAt
        self.status = status
    }
}

extension RuntimeClientProtocol {
    func ping() async -> RuntimePingResult { RuntimePingResult(ok: false, agentVersion: nil) }
    func dashboardState() async throws -> DashboardState { throw RuntimeClientStubError.unimplemented("dashboardState") }
    func listSources() async throws -> [SourceRecord] { throw RuntimeClientStubError.unimplemented("listSources") }
    func addSource(path: String, displayName: String) async throws -> SourceRecord { throw RuntimeClientStubError.unimplemented("addSource") }
    func removeSource(sourceID: String) async throws { throw RuntimeClientStubError.unimplemented("removeSource") }
    func pauseSource(sourceID: String) async throws { throw RuntimeClientStubError.unimplemented("pauseSource") }
    func resumeSource(sourceID: String) async throws { throw RuntimeClientStubError.unimplemented("resumeSource") }
    func policies() async throws -> DashboardState { try await dashboardState() }
    func pauseAgent(_ agent: TargetApp) async throws { throw RuntimeClientStubError.unimplemented("pauseAgent") }
    func resumeAgent(_ agent: TargetApp) async throws { throw RuntimeClientStubError.unimplemented("resumeAgent") }
    func addSource(_ sourceID: String, to agent: TargetApp) async throws { throw RuntimeClientStubError.unimplemented("addSource(_:to:)") }
    func removeSource(_ sourceID: String, from agent: TargetApp) async throws { throw RuntimeClientStubError.unimplemented("removeSource(_:from:)") }
    func updateAccessRecordingLevel(_ level: AccessRecordingLevel, for agent: TargetApp) async throws { throw RuntimeClientStubError.unimplemented("updateAccessRecordingLevel") }
    func getEmailRuleSet(agent: TargetApp) async throws -> EmailRuleSet { throw RuntimeClientStubError.unimplemented("getEmailRuleSet") }
    func updateEmailRuleSet(agent: TargetApp, ruleSet: EmailRuleSet) async throws { throw RuntimeClientStubError.unimplemented("updateEmailRuleSet") }
    func getEmailRuleActivitySummary(agent: TargetApp) async throws -> EmailRuleActivitySummary { throw RuntimeClientStubError.unimplemented("getEmailRuleActivitySummary") }
    func activeGrantState(targetApp: TargetApp) async throws -> ActiveGrantState { throw RuntimeClientStubError.unimplemented("activeGrantState") }
    func sessionPreview(targetApp: TargetApp, fileScopes: [FileSelectionScope], selectedEmailIDs: Set<String>, emailSensitivity: String?) async throws -> SessionPreview { throw RuntimeClientStubError.unimplemented("sessionPreview") }
    func startTrackedRun(targetApp: TargetApp, fileScopes: [FileSelectionScope], selectedEmailIDs: Set<String>, summaryFraming: String?, noteCaptureMode: SessionNoteCaptureMode, emailSensitivity: String?) async throws -> ActiveGrantState { throw RuntimeClientStubError.unimplemented("startTrackedRun") }
    func restoreSnapshot(snapshotID: Int, filePath: String) async throws -> RestoreSnapshotResult { throw RuntimeClientStubError.unimplemented("restoreSnapshot") }
    func markWorkBlockReviewing(id: String) async throws { throw RuntimeClientStubError.unimplemented("markWorkBlockReviewing") }
    func cancelWorkBlockReview(id: String) async throws { throw RuntimeClientStubError.unimplemented("cancelWorkBlockReview") }
    func pauseTrackedRun(id: String) async throws { throw RuntimeClientStubError.unimplemented("pauseTrackedRun") }
    func resumeTrackedRun(id: String) async throws { throw RuntimeClientStubError.unimplemented("resumeTrackedRun") }
    func discardTrackedRun(id: String, grantID: String?, endSession: Bool) async throws { throw RuntimeClientStubError.unimplemented("discardTrackedRun") }
    func discardTrackedRun(id: String, grantID: String?) async throws { try await discardTrackedRun(id: id, grantID: grantID, endSession: false) }
    func promotionPreview(grantID: String) async throws -> WorkBlockPreview { throw RuntimeClientStubError.unimplemented("promotionPreview") }
    func applyTrackedRun(grantID: String, endSession: Bool) async throws -> ApplyTrackedRunResult { throw RuntimeClientStubError.unimplemented("applyTrackedRun") }
    func applyTrackedRun(grantID: String) async throws -> ApplyTrackedRunResult { try await applyTrackedRun(grantID: grantID, endSession: false) }
    func recentActivity(limit: Int) async throws -> [AuditEntry] { [] }
    func recentSessions(limit: Int) async throws -> [Session] { [] }
    func listPendingApprovals() async throws -> [PendingApprovalRecord] { [] }
    func answerApproval(id: String, answer: String) async throws {}
    func sessionEvents(sessionID: String) async throws -> [SessionEvent] { [] }
    func revertSessionEvent(event: SessionEvent, grantID: String, force: Bool) async throws -> RevertEventResult { throw RuntimeClientStubError.unimplemented("revertSessionEvent") }
    func trackedFiles() async throws -> [String] { [] }
    func storageStats() async throws -> StorageStatsSnapshot { StorageStatsSnapshot(storageUsed: 0) }
    func fileHistory(filePath: String) async throws -> [SnapshotRecord] { [] }
    func fileHistoryContext(filePath: String, limit: Int) async throws -> FileHistoryContext { throw RuntimeClientStubError.unimplemented("fileHistoryContext") }
    func sessionContext(sessionID: String, agent: TargetApp?) async throws -> SessionContextDetail { throw RuntimeClientStubError.unimplemented("sessionContext") }
    func snapshotData(hash: String) async throws -> Data? { nil }
    func runGarbageCollection() async throws -> Int { 0 }
    func runIntegrityCheck() async throws -> Bool { true }
    func listEmailAccounts() async throws -> [EmailAccountRecord] { [] }
    func syncStates(accountID: String) async throws -> [SyncStateRecord] { [] }
    func emailMessageCount() async throws -> Int { 0 }
    func addIMAPAccount(displayName: String, provider: EmailProvider, server: String, port: Int, username: String, password: String) async throws -> EmailAccountRecord { throw RuntimeClientStubError.unimplemented("addIMAPAccount") }
    func removeEmailAccount(id: String) async throws { throw RuntimeClientStubError.unimplemented("removeEmailAccount") }
    func toggleEmailSync(accountID: String, enabled: Bool) async throws { throw RuntimeClientStubError.unimplemented("toggleEmailSync") }
    func syncEmailNow(accountID: String) async throws -> SyncResult { throw RuntimeClientStubError.unimplemented("syncEmailNow") }
    func emailMessages(accountID: String? = nil, mailbox: String? = nil, ids: [String]? = nil, limit: Int = 500) async throws -> [EmailMessageRecord] { [] }
    func domainCounts() async throws -> [String: Int] { [:] }
    func unreadCountAll() async throws -> Int { 0 }
    func unreadCount(accountID: String, mailbox: String? = nil) async throws -> Int { 0 }
    func imapMailboxes(accountID: String) async throws -> [IMAPMailboxRecord] { [] }
    func sharedEmailCount() async throws -> Int { 0 }
    func sharedEmailIDs() async throws -> Set<String> { [] }
    func sharedEmails(limit: Int = 500) async throws -> [EmailMessageRecord] { [] }
    func shareEmails(emailIDs: [String]) async throws { throw RuntimeClientStubError.unimplemented("shareEmails") }
    func unshareEmails(emailIDs: [String]) async throws { throw RuntimeClientStubError.unimplemented("unshareEmails") }
    func unshareAllEmails() async throws { throw RuntimeClientStubError.unimplemented("unshareAllEmails") }
    func updateEmailReadState(emailID: String, isRead: Bool) async throws { throw RuntimeClientStubError.unimplemented("updateEmailReadState") }
    func updateEmailFlagState(emailID: String, isFlagged: Bool, flagColor: String?) async throws { throw RuntimeClientStubError.unimplemented("updateEmailFlagState") }
    func batchUpdateReadState(emailIDs: [String], isRead: Bool) async throws { throw RuntimeClientStubError.unimplemented("batchUpdateReadState") }
    func batchUpdateFlagState(emailIDs: [String], isFlagged: Bool, flagColor: String?) async throws { throw RuntimeClientStubError.unimplemented("batchUpdateFlagState") }
    func searchEmailMessages(tokens: [SearchToken], freeText: String, accountID: String?, mailbox: String?, filter: QuickFilter?, sortKey: EmailSortKey, limit: Int) async throws -> [EmailMessageRecord] { [] }
    func createSmartMailbox(displayName: String, iconName: String, rulesJSON: String) async throws { throw RuntimeClientStubError.unimplemented("createSmartMailbox") }
    func listSmartMailboxes() async throws -> [SmartMailboxRecord] { [] }
    func updateSmartMailbox(mailboxID: String, displayName: String, iconName: String, rulesJSON: String) async throws { throw RuntimeClientStubError.unimplemented("updateSmartMailbox") }
    func deleteSmartMailbox(mailboxID: String) async throws { throw RuntimeClientStubError.unimplemented("deleteSmartMailbox") }
    func emailBackupInfo() async throws -> EmailBackupInfo { EmailBackupInfo(path: "", diskUsage: 0) }
    func fileVisibilityOverrides(agent: TargetApp) async throws -> [FileVisibilityOverrideRecord] { [] }
    func setFileVisibilityOverride(agent: TargetApp, sourceID: String, relativePath: String, isDirectory: Bool, decision: FileVisibilityOverrideDecision) async throws {}
    func clearFileVisibilityOverride(agent: TargetApp, sourceID: String, relativePath: String, isDirectory: Bool) async throws {}

    // Rules — default stubs return empty / no-op so optional profiles don't need to implement them.
    func listRules(scope: RuleScope?) async throws -> [RuleRecord] { [] }
    func upsertRule(_ rule: RuleRecord) async throws { throw RuntimeClientStubError.unimplemented("upsertRule") }
    func deleteRule(id: String) async throws { throw RuntimeClientStubError.unimplemented("deleteRule") }
    func setRuleEnabled(id: String, enabled: Bool) async throws { throw RuntimeClientStubError.unimplemented("setRuleEnabled") }
    func reorderRules(scope: RuleScope, ids: [String]) async throws { throw RuntimeClientStubError.unimplemented("reorderRules") }
    func resetSeededRules() async throws { throw RuntimeClientStubError.unimplemented("resetSeededRules") }
    func previewRuleMatches(rule: RuleRecord, agent: TargetApp) async throws -> RuleMatchPreview {
        RuleMatchPreview(ruleID: rule.id, fileMatches: 0, emailMatches: 0, agentMatches: 0, sample: [])
    }
}

enum AppFixtureProfile: String, Sendable {
    case onboarding
    case dashboard
    case emailRules = "email-rules"
    case trackedWork = "tracked-work"
    case activity
}

enum AppTestMode: Sendable {
    case live
    case fixture(AppFixtureProfile)

    static var current: AppTestMode {
        let env = ProcessInfo.processInfo.environment
        guard env["MANIFOLD_UI_TEST_MODE"] == "1" || env["MANIFOLD_DISABLE_REAL_RUNTIME"] == "1" else {
            return .live
        }
        let profile = AppFixtureProfile(rawValue: env["MANIFOLD_FIXTURE_PROFILE"] ?? "") ?? .dashboard
        return .fixture(profile)
    }
}

actor FixtureRuntimeClient: RuntimeClientProtocol {
    private struct FixtureState {
        var version = "0.4.0"
        var sources: [SourceRecord]
        var claudePolicy: AgentAccessPolicy
        var codexPolicy: AgentAccessPolicy
        var claudeGovernance: AgentEmailGovernanceSummary
        var codexGovernance: AgentEmailGovernanceSummary
        var coverages: [AgentCoverageSnapshot]
        var coverageEvents: [CoverageEvent]
        var activeWorkBlock: WorkBlockRecord?
        var connectedAgents: [String]
        var activityEntries: [AuditEntry]
        var sessions: [Session]
        var sessionEvents: [String: [SessionEvent]]
        var activeGrant: GrantRecord?
        var activeGrantSources: [GrantSourceRecord]
        var pendingApprovals: [PendingApprovalRecord]
        var emailRuleSets: [TargetApp: EmailRuleSet]
        var emailRuleSummaries: [TargetApp: EmailRuleActivitySummary]
        var domainCounts: [String: Int]
        var trackedFiles: [String]
        var storageUsed: Int64
        var mailAccounts: [EmailAccountRecord]
        var syncStates: [String: [SyncStateRecord]]
        var emails: [EmailMessageRecord]
        var imapMailboxes: [String: [IMAPMailboxRecord]]
        var sharedEmailIDs: Set<String>
        var fileVisibilityOverrides: [TargetApp: [FileVisibilityOverrideRecord]]
    }

    private var state: FixtureState

    init(profile: AppFixtureProfile) {
        state = Self.makeState(profile: profile)
    }

    func ping() async -> RuntimePingResult {
        RuntimePingResult(ok: true, agentVersion: state.version)
    }

    func dashboardState() async throws -> DashboardState {
        DashboardState(
            runtimeConnected: true,
            activeBridgeCount: state.connectedAgents.count,
            connectedAgents: state.connectedAgents,
            sources: state.sources,
            claudePolicy: state.claudePolicy,
            codexPolicy: state.codexPolicy,
            claudeEmailGovernance: state.claudeGovernance,
            codexEmailGovernance: state.codexGovernance,
            activeSession: state.activeWorkBlock,
            pendingApprovalCount: state.pendingApprovals.count,
            agentCoverages: state.coverages,
            coverageEvents: state.coverageEvents
        )
    }

    func listSources() async throws -> [SourceRecord] { state.sources }

    func addSource(path: String, displayName: String) async throws -> SourceRecord {
        let source = SourceRecord(
            sourceID: "src-\(UUID().uuidString.prefix(8).lowercased())",
            displayName: displayName,
            originalRootPath: path,
            status: "idle",
            createdAt: ISO8601DateFormatter.shared.string(from: Date()),
            updatedAt: ISO8601DateFormatter.shared.string(from: Date())
        )
        state.sources.append(source)
        return source
    }

    func removeSource(sourceID: String) async throws {
        state.sources.removeAll { $0.sourceID == sourceID }
        state.claudePolicy.allowedSourceIDs.remove(sourceID)
        state.codexPolicy.allowedSourceIDs.remove(sourceID)
        for agent in TargetApp.allCases {
            state.fileVisibilityOverrides[agent]?.removeAll { $0.sourceID == sourceID }
        }
    }

    func pauseSource(sourceID: String) async throws {
        guard let index = state.sources.firstIndex(where: { $0.sourceID == sourceID }) else { return }
        var source = state.sources[index]
        source = SourceRecord(
            sourceID: source.sourceID,
            displayName: source.displayName,
            originalRootPath: source.originalRootPath,
            status: "paused",
            createdAt: source.createdAt,
            updatedAt: ISO8601DateFormatter.shared.string(from: Date())
        )
        state.sources[index] = source
    }

    func resumeSource(sourceID: String) async throws {
        guard let index = state.sources.firstIndex(where: { $0.sourceID == sourceID }) else { return }
        var source = state.sources[index]
        source = SourceRecord(
            sourceID: source.sourceID,
            displayName: source.displayName,
            originalRootPath: source.originalRootPath,
            status: "idle",
            createdAt: source.createdAt,
            updatedAt: ISO8601DateFormatter.shared.string(from: Date())
        )
        state.sources[index] = source
    }

    func pauseAgent(_ agent: TargetApp) async throws {
        updatePolicy(agent: agent) { $0.isPaused = true }
    }

    func resumeAgent(_ agent: TargetApp) async throws {
        updatePolicy(agent: agent) { $0.isPaused = false }
    }

    func addSource(_ sourceID: String, to agent: TargetApp) async throws {
        updatePolicy(agent: agent) { $0.allowedSourceIDs.insert(sourceID) }
    }

    func removeSource(_ sourceID: String, from agent: TargetApp) async throws {
        updatePolicy(agent: agent) { $0.allowedSourceIDs.remove(sourceID) }
    }

    func updateAccessRecordingLevel(_ level: AccessRecordingLevel, for agent: TargetApp) async throws {
        updatePolicy(agent: agent) { $0.accessRecordingLevel = level }
    }

    func getEmailRuleSet(agent: TargetApp) async throws -> EmailRuleSet {
        state.emailRuleSets[agent] ?? EmailRuleSet(agent: agent)
    }

    func updateEmailRuleSet(agent: TargetApp, ruleSet: EmailRuleSet) async throws {
        state.emailRuleSets[agent] = ruleSet
        updateGovernance(agent: agent, ruleSet: ruleSet)
    }

    func getEmailRuleActivitySummary(agent: TargetApp) async throws -> EmailRuleActivitySummary {
        state.emailRuleSummaries[agent] ?? EmailRuleActivitySummary(agent: agent)
    }

    func activeGrantState(targetApp: TargetApp) async throws -> ActiveGrantState {
        ActiveGrantState(activeGrant: state.activeGrant, activeGrantSources: state.activeGrantSources, targetApp: targetApp.rawValue)
    }

    func sessionPreview(targetApp: TargetApp, fileScopes: [FileSelectionScope], selectedEmailIDs: Set<String>, emailSensitivity: String?) async throws -> SessionPreview {
        let estimates = state.sources.filter { source in
            governance(for: targetApp).allowedSourceIDs.contains(source.sourceID)
        }.map { source in
            SessionPreview.SourceEstimate(
                sourceID: source.sourceID,
                displayName: source.displayName,
                fileCount: 12,
                totalBytes: 48_000,
                scopeCount: max(fileScopes.filter { $0.sourceID == source.sourceID }.count, 1)
            )
        }
        return SessionPreview(
            sources: estimates,
            emailCount: state.emails.count,
            visibleEmailCount: state.emails.count,
            sensitivityLevel: emailSensitivity ?? governance(for: targetApp).emailSensitivity.rawValue,
            selectedEmailCount: selectedEmailIDs.count
        )
    }

    func startTrackedRun(targetApp: TargetApp, fileScopes: [FileSelectionScope], selectedEmailIDs: Set<String>, summaryFraming: String?, noteCaptureMode: SessionNoteCaptureMode, emailSensitivity: String?) async throws -> ActiveGrantState {
        let grant = GrantRecord(
            grantID: "grant-\(UUID().uuidString.prefix(8).lowercased())",
            targetApp: targetApp.rawValue,
            profileID: "profile-fixture",
            status: GrantStatus.active.rawValue,
            startedAt: ISO8601DateFormatter.shared.string(from: Date()),
            materializationRoot: "/tmp/manifold-fixture/\(targetApp.rawValue)",
            inactivityDeadline: nil,
            emailSensitivity: (EmailSensitivityLevel(rawValue: emailSensitivity ?? "") ?? governance(for: targetApp).emailSensitivity).rawValue,
            summaryFraming: summaryFraming,
            explicitSelection: !selectedEmailIDs.isEmpty,
            noteCaptureMode: noteCaptureMode.rawValue
        )
        state.activeGrant = grant
        state.activeGrantSources = state.sources.filter { governance(for: targetApp).allowedSourceIDs.contains($0.sourceID) }.map {
            GrantSourceRecord(grantID: grant.grantID, sourceID: $0.sourceID, mountName: $0.displayName.replacingOccurrences(of: " ", with: "-").lowercased())
        }
        state.activeWorkBlock = WorkBlockRecord(agent: targetApp, grantID: grant.grantID, sourceIDs: state.activeGrantSources.map(\.sourceID))
        state.coverages = state.coverages.map { snapshot in
            snapshot.agent == targetApp.rawValue
                ? AgentCoverageSnapshot(agent: snapshot.agent, coverageState: .trackedWorkspace, verificationStatus: snapshot.verificationStatus, hostBundleIdentifier: snapshot.hostBundleIdentifier, reason: snapshot.reason)
                : snapshot
        }
        return ActiveGrantState(activeGrant: grant, activeGrantSources: state.activeGrantSources, targetApp: targetApp.rawValue)
    }

    func restoreSnapshot(snapshotID: Int, filePath: String) async throws -> RestoreSnapshotResult {
        RestoreSnapshotResult(status: "success", message: nil)
    }
    func markWorkBlockReviewing(id: String) async throws { state.activeWorkBlock?.status = .reviewing }
    func cancelWorkBlockReview(id: String) async throws { state.activeWorkBlock?.status = .active }
    func pauseTrackedRun(id: String) async throws { state.activeWorkBlock?.status = .paused }
    func resumeTrackedRun(id: String) async throws { state.activeWorkBlock?.status = .active }

    func discardTrackedRun(id: String, grantID: String?, endSession: Bool) async throws {
        state.activeWorkBlock = nil
        state.activeGrant = nil
        state.activeGrantSources = []
        state.coverages = state.coverages.map { snapshot in
            AgentCoverageSnapshot(agent: snapshot.agent, coverageState: .manifoldRouted, verificationStatus: snapshot.verificationStatus, hostBundleIdentifier: snapshot.hostBundleIdentifier, reason: snapshot.reason)
        }
    }

    func promotionPreview(grantID: String) async throws -> WorkBlockPreview {
        WorkBlockPreview(applied: ["shared/worklog.md"], conflicts: [], newFiles: [], skipped: 0)
    }

    func applyTrackedRun(grantID: String, endSession: Bool) async throws -> ApplyTrackedRunResult {
        try await discardTrackedRun(id: state.activeWorkBlock?.id ?? "", grantID: grantID, endSession: endSession)
        return ApplyTrackedRunResult(
            grantID: grantID,
            filesApplied: ["shared/worklog.md"],
            filesConflicted: [],
            appliedCount: 1,
            conflictCount: 0
        )
    }

    func recentActivity(limit: Int) async throws -> [AuditEntry] { Array(state.activityEntries.prefix(limit)) }
    func recentSessions(limit: Int) async throws -> [Session] { Array(state.sessions.prefix(limit)) }
    func listPendingApprovals() async throws -> [PendingApprovalRecord] { state.pendingApprovals }
    func answerApproval(id: String, answer: String) async throws {
        state.pendingApprovals.removeAll { $0.id == id }
    }
    func sessionEvents(sessionID: String) async throws -> [SessionEvent] { state.sessionEvents[sessionID] ?? [] }
    func trackedFiles() async throws -> [String] { state.trackedFiles }
    func storageStats() async throws -> StorageStatsSnapshot { StorageStatsSnapshot(storageUsed: state.storageUsed) }
    func listEmailAccounts() async throws -> [EmailAccountRecord] { state.mailAccounts }
    func syncStates(accountID: String) async throws -> [SyncStateRecord] { state.syncStates[accountID] ?? [] }
    func emailMessageCount() async throws -> Int { state.emails.count }
    func syncEmailNow(accountID: String) async throws -> SyncResult {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        state.syncStates[accountID] = (state.syncStates[accountID] ?? []).map { existing in
            SyncStateRecord(
                accountID: existing.accountID,
                mailboxName: existing.mailboxName,
                uidValidity: existing.uidValidity,
                lastSyncUID: existing.lastSyncUID,
                lastSyncAt: now,
                messageCount: state.emails.filter { $0.accountID == accountID && $0.mailbox == existing.mailboxName }.count,
                syncStatus: .idle,
                errorMessage: nil
            )
        }
        return SyncResult(accountID: accountID, newMessages: 0, updatedMessages: 0, errors: [], duration: 0.2)
    }
    func domainCounts() async throws -> [String: Int] { state.domainCounts }
    func unreadCountAll() async throws -> Int { state.emails.filter { !$0.isRead }.count }
    func unreadCount(accountID: String, mailbox: String? = nil) async throws -> Int {
        state.emails.filter { $0.accountID == accountID && (mailbox == nil || $0.mailbox == mailbox) && !$0.isRead }.count
    }
    func imapMailboxes(accountID: String) async throws -> [IMAPMailboxRecord] {
        state.imapMailboxes[accountID] ?? []
    }
    func sharedEmailCount() async throws -> Int { state.sharedEmailIDs.count }
    func sharedEmailIDs() async throws -> Set<String> { state.sharedEmailIDs }
    func sharedEmails(limit: Int = 500) async throws -> [EmailMessageRecord] {
        Array(state.emails.filter { state.sharedEmailIDs.contains($0.emailID) }.prefix(limit))
    }
    func emailMessages(accountID: String? = nil, mailbox: String? = nil, ids: [String]? = nil, limit: Int = 500) async throws -> [EmailMessageRecord] {
        let filtered = state.emails.filter { email in
            (accountID == nil || email.accountID == accountID)
                && (mailbox == nil || email.mailbox == mailbox)
                && (ids == nil || ids?.contains(email.emailID) == true)
        }
        return Array(filtered.sorted(by: { $0.receivedAt > $1.receivedAt }).prefix(limit))
    }
    func searchEmailMessages(tokens: [SearchToken], freeText: String, accountID: String?, mailbox: String?, filter: QuickFilter?, sortKey: EmailSortKey, limit: Int) async throws -> [EmailMessageRecord] {
        let term = freeText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let base = try await emailMessages(accountID: accountID, mailbox: mailbox, ids: nil, limit: limit)
        let filteredByQuickFilter = base.filter { email in
            guard let filter else { return true }
            return fixtureMatches(email: email, filter: filter)
        }
        let filtered = term.isEmpty ? filteredByQuickFilter : filteredByQuickFilter.filter { email in
            [email.sender, email.subject, email.preview ?? "", email.bodyText ?? ""]
                .joined(separator: "\n")
                .lowercased()
                .contains(term)
        }
        return Array(filtered.prefix(limit))
    }
    func shareEmails(emailIDs: [String]) async throws {
        for emailID in emailIDs {
            state.sharedEmailIDs.insert(emailID)
        }
    }
    func unshareEmails(emailIDs: [String]) async throws {
        for emailID in emailIDs {
            state.sharedEmailIDs.remove(emailID)
        }
    }
    func unshareAllEmails() async throws {
        state.sharedEmailIDs.removeAll()
    }

    func fileVisibilityOverrides(agent: TargetApp) async throws -> [FileVisibilityOverrideRecord] {
        state.fileVisibilityOverrides[agent] ?? []
    }

    func setFileVisibilityOverride(
        agent: TargetApp,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool,
        decision: FileVisibilityOverrideDecision
    ) async throws {
        let normalized = FileSelectionScope(
            sourceID: sourceID,
            relativePath: relativePath,
            isDirectory: isDirectory
        ).normalizedRelativePath
        var records = state.fileVisibilityOverrides[agent] ?? []
        records.removeAll {
            $0.sourceID == sourceID && $0.relativePath == normalized && $0.isDirectory == isDirectory
        }
        records.append(
            FileVisibilityOverrideRecord(
                agent: agent,
                sourceID: sourceID,
                relativePath: normalized,
                isDirectory: isDirectory,
                decision: decision
            )
        )
        state.fileVisibilityOverrides[agent] = records.sorted { $0.id < $1.id }
    }

    func clearFileVisibilityOverride(
        agent: TargetApp,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool
    ) async throws {
        let normalized = FileSelectionScope(
            sourceID: sourceID,
            relativePath: relativePath,
            isDirectory: isDirectory
        ).normalizedRelativePath
        state.fileVisibilityOverrides[agent]?.removeAll {
            $0.sourceID == sourceID && $0.relativePath == normalized && $0.isDirectory == isDirectory
        }
    }

    private func governance(for agent: TargetApp) -> AgentAccessPolicy {
        agent == .codex ? state.codexPolicy : state.claudePolicy
    }

    private func updatePolicy(agent: TargetApp, mutate: (inout AgentAccessPolicy) -> Void) {
        if agent == .codex {
            mutate(&state.codexPolicy)
        } else {
            mutate(&state.claudePolicy)
        }
    }

    private func updateGovernance(agent: TargetApp, ruleSet: EmailRuleSet) {
        let summary = AgentEmailGovernanceSummary(
            agent: agent,
            enabledShieldCount: ruleSet.shields.filter(\.isEnabled).count,
            domainRuleCount: ruleSet.domainRules.count,
            contactRuleCount: ruleSet.contactRules.count,
            keywordRuleCount: ruleSet.keywordRules.count,
            defaultPolicy: ruleSet.defaultPolicy,
            emailSensitivity: ruleSet.emailSensitivity
        )
        if agent == .codex {
            state.codexGovernance = summary
            state.codexPolicy.emailSensitivity = ruleSet.emailSensitivity
            state.codexPolicy.defaultEmailPolicy = ruleSet.defaultPolicy
            state.codexPolicy.allowedEmailDomains = Set(ruleSet.domainRules.filter { $0.action == .allow }.map(\.domain))
        } else {
            state.claudeGovernance = summary
            state.claudePolicy.emailSensitivity = ruleSet.emailSensitivity
            state.claudePolicy.defaultEmailPolicy = ruleSet.defaultPolicy
            state.claudePolicy.allowedEmailDomains = Set(ruleSet.domainRules.filter { $0.action == .allow }.map(\.domain))
        }
    }

    private static func makeState(profile: AppFixtureProfile) -> FixtureState {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        let sourceA = SourceRecord(sourceID: "src-shared", displayName: "Shared", originalRootPath: "/Users/test/shared", status: "idle", createdAt: now, updatedAt: now)
        let sourceB = SourceRecord(sourceID: "src-claude", displayName: "Claude Only", originalRootPath: "/Users/test/claude-only", status: "idle", createdAt: now, updatedAt: now)
        let claudePolicy = AgentAccessPolicy(agent: .cowork, allowedSourceIDs: ["src-shared", "src-claude"], allowedEmailDomains: ["example.com"], emailSensitivity: .moderate, defaultEmailPolicy: .allowUnlessBlocked, accessRecordingLevel: .summary, isPaused: false)
        let codexPolicy = AgentAccessPolicy(agent: .codex, allowedSourceIDs: ["src-shared"], allowedEmailDomains: [], emailSensitivity: .strict, defaultEmailPolicy: .blockUnlessAllowed, accessRecordingLevel: .detailed, isPaused: false)
        let claudeRules = EmailRuleSet(
            agent: .cowork,
            domainRules: [EmailDomainRule(agent: .cowork, domain: "example.com", action: .allow)],
            contactRules: [EmailContactRule(agent: .cowork, name: "Finance", email: "finance@example.com", action: .block)],
            keywordRules: [EmailKeywordRule(agent: .cowork, pattern: "2fa", matchLocation: .subjectAndBody, action: .block, isRegex: false)],
            defaultPolicy: .allowUnlessBlocked,
            emailSensitivity: .moderate
        )
        let codexRules = EmailRuleSet(
            agent: .codex,
            domainRules: [EmailDomainRule(agent: .codex, domain: "builds.example.com", action: .allow)],
            contactRules: [],
            keywordRules: [EmailKeywordRule(agent: .codex, pattern: "invoice", matchLocation: .subject, action: .block, isRegex: false)],
            defaultPolicy: .blockUnlessAllowed,
            emailSensitivity: .strict
        )
        let claudeGovernance = AgentEmailGovernanceSummary(agent: .cowork, enabledShieldCount: claudeRules.shields.filter(\.isEnabled).count, domainRuleCount: claudeRules.domainRules.count, contactRuleCount: claudeRules.contactRules.count, keywordRuleCount: claudeRules.keywordRules.count, defaultPolicy: claudeRules.defaultPolicy, emailSensitivity: claudeRules.emailSensitivity)
        let codexGovernance = AgentEmailGovernanceSummary(agent: .codex, enabledShieldCount: codexRules.shields.filter(\.isEnabled).count, domainRuleCount: codexRules.domainRules.count, contactRuleCount: codexRules.contactRules.count, keywordRuleCount: codexRules.keywordRules.count, defaultPolicy: codexRules.defaultPolicy, emailSensitivity: codexRules.emailSensitivity)
        let coverages = [
            AgentCoverageSnapshot(agent: TargetApp.cowork.rawValue, coverageState: .manifoldRouted, verificationStatus: .verified, hostBundleIdentifier: "com.anthropic.claudefordesktop", reason: "Fixture verified"),
            AgentCoverageSnapshot(agent: TargetApp.codex.rawValue, coverageState: profile == .trackedWork ? .trackedWorkspace : .manifoldRouted, verificationStatus: .verified, hostBundleIdentifier: "com.openai.codex", reason: "Fixture verified"),
        ]
        let coverageEvents = [
            CoverageEvent(id: "coverage-1", agent: TargetApp.codex.rawValue, coverageState: .outsideCoverage, eventType: "drift", message: "Original file changed outside the tracked workflow.", resourcePath: "shared/worklog.md", timestamp: now, metadata: nil),
        ]
        let activity = [
            AuditEntry(id: 1, timestamp: now, agent: TargetApp.cowork.rawValue, action: AuditAction.fileRead.rawValue, filePath: "claude-only/marker.txt", metadata: "{}", sessionID: "session-1", grantID: nil),
            AuditEntry(id: 2, timestamp: now, agent: TargetApp.codex.rawValue, action: AuditAction.contentDrift.rawValue, filePath: "shared/worklog.md", metadata: "{\"coverage_state\":\"outside_coverage\"}", sessionID: "session-2", grantID: "grant-fixture"),
        ]
        let sessions = [
            Session(id: "session-1", agent: TargetApp.cowork.rawValue, startTime: now, endTime: now, actionCount: 4, readCount: 3, writeCount: 0, searchCount: 1),
        ]
        let sessionEvents = [
            "session-1": [
                SessionEvent(id: 1, timestamp: now, action: AuditAction.fileRead.rawValue, agent: TargetApp.cowork.rawValue, filePath: "shared/worklog.md", metadata: "{}"),
            ]
        ]
        let pendingApprovals = profile == .trackedWork ? [
            PendingApprovalRecord(
                id: "approval-1",
                connectionID: "conn-fixture",
                agent: TargetApp.codex.rawValue,
                path: "shared/worklog.md",
                action: "write",
                kind: "standing_write",
                sourceID: "src-shared",
                mountName: "shared",
                relativePath: "worklog.md",
                requestedAt: Date().addingTimeInterval(-300).timeIntervalSince1970,
                status: "pending"
            )
        ] : []
        let boardRootDate = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(-21_600))
        let boardReplyDate = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(-7_200))
        let boardLatestDate = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(-1_200))
        let digestDate = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(-86_400))
        let archiveDate = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(-172_800))
        let emails = [
            EmailMessageRecord(
                emailID: "email-1",
                accountID: "account-1",
                mailbox: "INBOX",
                sender: "Jane Doe <jane@acme.com>",
                senderEmail: "jane@acme.com",
                senderDomain: "acme.com",
                recipients: "you@example.com",
                subject: "Board deck v2",
                receivedAt: boardRootDate,
                sizeBytes: 3_200,
                preview: "First draft of the board deck for Thursday’s review.",
                isRead: false,
                isFlagged: true,
                messageIDHeader: "<thread-board@example.com>",
                attachmentCount: 1,
                bodyText: "First draft of the board deck for Thursday’s review."
            ),
            EmailMessageRecord(
                emailID: "email-2",
                accountID: "account-1",
                mailbox: "INBOX",
                sender: "Mark Chen <mark@acme.com>",
                senderEmail: "mark@acme.com",
                senderDomain: "acme.com",
                recipients: "you@example.com",
                subject: "Re: Board deck v2",
                receivedAt: boardReplyDate,
                sizeBytes: 2_900,
                preview: "Added a tighter summary slide and trimmed the appendix.",
                isRead: true,
                inReplyTo: "<thread-board@example.com>",
                referencesHeader: "<thread-board@example.com>",
                messageIDHeader: "<thread-board-reply@example.com>",
                bodyText: "Added a tighter summary slide and trimmed the appendix."
            ),
            EmailMessageRecord(
                emailID: "email-3",
                accountID: "account-1",
                mailbox: "INBOX",
                sender: "Jane Doe <jane@acme.com>",
                senderEmail: "jane@acme.com",
                senderDomain: "acme.com",
                recipients: "you@example.com",
                subject: "Re: Board deck v2",
                receivedAt: boardLatestDate,
                sizeBytes: 2_600,
                preview: "Latest revenue numbers are in. This should be the final version.",
                isRead: true,
                inReplyTo: "<thread-board-reply@example.com>",
                referencesHeader: "<thread-board@example.com> <thread-board-reply@example.com>",
                messageIDHeader: "<thread-board-final@example.com>",
                attachmentCount: 1,
                bodyText: "Latest revenue numbers are in. This should be the final version."
            ),
            EmailMessageRecord(
                emailID: "email-4",
                accountID: "account-1",
                mailbox: "INBOX",
                sender: "Ops <ops@example.com>",
                senderEmail: "ops@example.com",
                senderDomain: "example.com",
                recipients: "you@example.com",
                subject: "MANIFOLD_EMAIL_TEST",
                receivedAt: digestDate,
                sizeBytes: 1_200,
                preview: "Governed email preview",
                isRead: false,
                messageIDHeader: "<fixture-digest@example.com>",
                attachmentCount: 2,
                bodyText: "Governed body text for fixture mode."
            ),
            EmailMessageRecord(
                emailID: "email-5",
                accountID: "account-1",
                mailbox: "Archive",
                sender: "Security Team <security@example.com>",
                senderEmail: "security@example.com",
                senderDomain: "example.com",
                recipients: "you@example.com",
                subject: "Quarterly governance review",
                receivedAt: archiveDate,
                sizeBytes: 2_100,
                preview: "Archived governance review summary with the approved checklist.",
                isRead: true,
                messageIDHeader: "<archive-governance@example.com>",
                bodyText: "Archived governance review summary with the approved checklist."
            ),
        ]
        let account = EmailAccountRecord(accountID: "account-1", displayName: "Fixture Inbox", providerType: "gmail", syncEnabled: true, createdAt: now, updatedAt: now)
        let imapMailboxes = [
            "account-1": [
                IMAPMailboxRecord(row: [
                    "account_id": "account-1",
                    "mailbox_name": "INBOX",
                    "flags": "[\"\\\\Inbox\"]",
                    "is_selectable": "1",
                    "sort_order": "0",
                ]),
                IMAPMailboxRecord(row: [
                    "account_id": "account-1",
                    "mailbox_name": "Archive",
                    "flags": "[\"\\\\Archive\"]",
                    "is_selectable": "1",
                    "sort_order": "1",
                ]),
                IMAPMailboxRecord(row: [
                    "account_id": "account-1",
                    "mailbox_name": "Sent",
                    "flags": "[\"\\\\Sent\"]",
                    "is_selectable": "1",
                    "sort_order": "2",
                ]),
            ].compactMap { $0 },
        ]
        let activeGrant: GrantRecord? = profile == .trackedWork ? GrantRecord(
            grantID: "grant-fixture",
            targetApp: TargetApp.codex.rawValue,
            profileID: "profile-fixture",
            status: GrantStatus.active.rawValue,
            startedAt: now,
            materializationRoot: "/tmp/manifold-fixture/codex",
            emailSensitivity: EmailSensitivityLevel.strict.rawValue,
            summaryFraming: "Fixture tracked work",
            explicitSelection: false,
            noteCaptureMode: SessionNoteCaptureMode.basic.rawValue
        ) : nil
        let activeGrantSources = profile == .trackedWork ? [GrantSourceRecord(grantID: "grant-fixture", sourceID: "src-shared", mountName: "shared")] : []
        let activeWorkBlock = profile == .trackedWork ? WorkBlockRecord(id: "wb-fixture", agent: .codex, grantID: "grant-fixture", sourceIDs: ["src-shared"], startedAt: now, status: .active, modifiedFileCount: 1, newFileCount: 0) : nil

        return FixtureState(
            sources: profile == .onboarding ? [] : [sourceA, sourceB],
            claudePolicy: claudePolicy,
            codexPolicy: codexPolicy,
            claudeGovernance: claudeGovernance,
            codexGovernance: codexGovernance,
            coverages: coverages,
            coverageEvents: profile == .activity ? coverageEvents : (profile == .trackedWork ? coverageEvents : []),
            activeWorkBlock: activeWorkBlock,
            connectedAgents: profile == .onboarding ? [] : [TargetApp.cowork.rawValue, TargetApp.codex.rawValue],
            activityEntries: activity,
            sessions: sessions,
            sessionEvents: sessionEvents,
            activeGrant: activeGrant,
            activeGrantSources: activeGrantSources,
            pendingApprovals: pendingApprovals,
            emailRuleSets: [.cowork: claudeRules, .codex: codexRules],
            emailRuleSummaries: [
                .cowork: EmailRuleActivitySummary(agent: .cowork, shieldBlockedCounts: ["security": 2], recentShieldMatches: [], domainRuleHits: [.init(ruleID: claudeRules.domainRules[0].id, count: 5)], contactRuleHits: [.init(ruleID: claudeRules.contactRules[0].id, count: 1)], keywordRuleHits: [.init(ruleID: claudeRules.keywordRules[0].id, count: 3)]),
                .codex: EmailRuleActivitySummary(agent: .codex, shieldBlockedCounts: ["financial": 1], recentShieldMatches: [], domainRuleHits: [.init(ruleID: codexRules.domainRules[0].id, count: 4)], contactRuleHits: [], keywordRuleHits: [.init(ruleID: codexRules.keywordRules[0].id, count: 2)]),
            ],
            domainCounts: ["example.com": 12, "builds.example.com": 7],
            trackedFiles: ["shared/worklog.md"],
            storageUsed: 24_576,
            mailAccounts: profile == .onboarding ? [] : [account],
            syncStates: ["account-1": [SyncStateRecord(accountID: "account-1", mailboxName: "INBOX", lastSyncAt: now, messageCount: 42, syncStatus: .idle)]],
            emails: profile == .onboarding ? [] : emails,
            imapMailboxes: profile == .onboarding ? [:] : imapMailboxes,
            sharedEmailIDs: profile == .onboarding ? [] : ["email-1", "email-4"],
            fileVisibilityOverrides: [:]
        )
    }

    private func fixtureMatches(email: EmailMessageRecord, filter: QuickFilter) -> Bool {
        switch filter {
        case .unread:
            return !email.isRead
        case .flagged:
            return email.isFlagged
        case .attachments:
            return email.attachmentCount > 0
        case .today:
            return Calendar.current.isDateInToday(MailDisplayFormatter.date(from: email.receivedAt))
        case .unviewed:
            return !email.localIsViewed
        case .deletedOnServer:
            return email.deletedOnServerAt != nil
        case .junk:
            return email.isJunk
        case .thisWeek:
            let date = MailDisplayFormatter.date(from: email.receivedAt)
            guard let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return false }
            return date >= weekAgo
        }
    }
}

final class AppRuntimeClient: RuntimeClientProtocol, Sendable {
    let xpc = ManifoldXPCClient()

    func ping() async -> RuntimePingResult {
        do {
            let response = try await xpc.command(name: "ping", payload: [:])
            let ok = response["ok"] as? Bool ?? false
            let version = response["agentVersion"] as? String
            return RuntimePingResult(ok: ok, agentVersion: version)
        } catch {
            return RuntimePingResult(ok: false, agentVersion: nil)
        }
    }

    func dashboardState() async throws -> DashboardState {
        try await command(name: "getStatus", as: DashboardState.self)
    }

    func listSources() async throws -> [SourceRecord] {
        try await command(name: "listSources", field: "sources", as: [SourceRecord].self)
    }

    func addSource(path: String, displayName: String) async throws -> SourceRecord {
        try await command(
            name: "addSource",
            payload: ["path": path, "displayName": displayName],
            field: "source",
            as: SourceRecord.self
        )
    }

    func removeSource(sourceID: String) async throws {
        _ = try await xpc.command(name: "removeSource", payload: ["sourceID": sourceID])
    }

    func pauseSource(sourceID: String) async throws {
        _ = try await xpc.command(name: "pauseSource", payload: ["sourceID": sourceID])
    }

    func resumeSource(sourceID: String) async throws {
        _ = try await xpc.command(name: "resumeSource", payload: ["sourceID": sourceID])
    }

    func policies() async throws -> DashboardState {
        try await dashboardState()
    }

    func pauseAgent(_ agent: TargetApp) async throws {
        _ = try await xpc.command(name: "pauseAgent", payload: ["agent": agent.rawValue])
    }

    func resumeAgent(_ agent: TargetApp) async throws {
        _ = try await xpc.command(name: "resumeAgent", payload: ["agent": agent.rawValue])
    }

    func addSource(_ sourceID: String, to agent: TargetApp) async throws {
        _ = try await xpc.command(name: "addSourceToPolicy", payload: ["sourceID": sourceID, "agent": agent.rawValue])
    }

    func removeSource(_ sourceID: String, from agent: TargetApp) async throws {
        _ = try await xpc.command(name: "removeSourceFromPolicy", payload: ["sourceID": sourceID, "agent": agent.rawValue])
    }

    func updateAccessRecordingLevel(_ level: AccessRecordingLevel, for agent: TargetApp) async throws {
        _ = try await xpc.command(name: "updateAccessRecordingLevel", payload: ["level": level.rawValue, "agent": agent.rawValue])
    }

    func getEmailRuleSet(agent: TargetApp) async throws -> EmailRuleSet {
        try await command(
            name: "getEmailRuleSet",
            payload: ["agent": agent.rawValue],
            field: "ruleSet",
            as: EmailRuleSet.self
        )
    }

    func updateEmailRuleSet(agent: TargetApp, ruleSet: EmailRuleSet) async throws {
        _ = try await xpc.command(
            name: "updateEmailRuleSet",
            payload: [
                "agent": agent.rawValue,
                "ruleSet": try XPCJSON.object(from: ruleSet),
            ]
        )
    }

    func getEmailRuleActivitySummary(agent: TargetApp) async throws -> EmailRuleActivitySummary {
        try await command(
            name: "getEmailRuleActivitySummary",
            payload: ["agent": agent.rawValue],
            field: "summary",
            as: EmailRuleActivitySummary.self
        )
    }

    func activeGrantState(targetApp: TargetApp) async throws -> ActiveGrantState {
        try await command(name: "activeGrantState", payload: ["targetApp": targetApp.rawValue], as: ActiveGrantState.self)
    }

    func sessionPreview(
        targetApp: TargetApp,
        fileScopes: [FileSelectionScope],
        selectedEmailIDs: Set<String>,
        emailSensitivity: String?
    ) async throws -> SessionPreview {
        var payload: [String: Any] = [
            "targetApp": targetApp.rawValue,
            "fileScopes": try XPCJSON.object(from: fileScopes),
            "selectedEmailIDs": Array(selectedEmailIDs),
        ]
        if let emailSensitivity {
            payload["emailSensitivity"] = emailSensitivity
        }
        return try await command(name: "sessionPreview", payload: payload, field: "preview", as: SessionPreview.self)
    }

    func startTrackedRun(
        targetApp: TargetApp,
        fileScopes: [FileSelectionScope],
        selectedEmailIDs: Set<String>,
        summaryFraming: String?,
        noteCaptureMode: SessionNoteCaptureMode,
        emailSensitivity: String?
    ) async throws -> ActiveGrantState {
        var payload: [String: Any] = [
            "targetApp": targetApp.rawValue,
            "fileScopes": try XPCJSON.object(from: fileScopes),
            "selectedEmailIDs": Array(selectedEmailIDs),
            "noteCaptureMode": noteCaptureMode.rawValue,
        ]
        if let summaryFraming {
            payload["summaryFraming"] = summaryFraming
        }
        if let emailSensitivity {
            payload["emailSensitivity"] = emailSensitivity
        }
        return try await command(name: "startTrackedRun", payload: payload, as: ActiveGrantState.self)
    }

    func restoreSnapshot(snapshotID: Int, filePath: String) async throws -> RestoreSnapshotResult {
        try await command(
            name: "restoreSnapshot",
            payload: ["snapshotID": snapshotID, "filePath": filePath],
            field: "result",
            as: RestoreSnapshotResult.self
        )
    }

    func markWorkBlockReviewing(id: String) async throws {
        _ = try await xpc.command(name: "markWorkBlockReviewing", payload: ["workBlockID": id])
    }

    func cancelWorkBlockReview(id: String) async throws {
        _ = try await xpc.command(name: "cancelWorkBlockReview", payload: ["workBlockID": id])
    }

    func pauseTrackedRun(id: String) async throws {
        _ = try await xpc.command(name: "pauseTrackedRun", payload: ["workBlockID": id])
    }

    func resumeTrackedRun(id: String) async throws {
        _ = try await xpc.command(name: "resumeTrackedRun", payload: ["workBlockID": id])
    }

    func discardTrackedRun(id: String, grantID: String?, endSession: Bool = false) async throws {
        var payload: [String: Any] = ["workBlockID": id, "endSession": endSession]
        if let grantID {
            payload["grantID"] = grantID
        }
        _ = try await xpc.command(name: "discardTrackedRun", payload: payload)
    }

    func promotionPreview(grantID: String) async throws -> WorkBlockPreview {
        try await command(name: "promotionPreview", payload: ["grantID": grantID], field: "preview", as: WorkBlockPreview.self)
    }

    func applyTrackedRun(grantID: String, endSession: Bool = false) async throws -> ApplyTrackedRunResult {
        try await command(
            name: "applyTrackedRun",
            payload: ["grantID": grantID, "endSession": endSession],
            field: "result",
            as: ApplyTrackedRunResult.self
        )
    }

    func recentActivity(limit: Int = 100) async throws -> [AuditEntry] {
        try await command(name: "recentActivity", payload: ["limit": limit], field: "entries", as: [AuditEntry].self)
    }

    func recentSessions(limit: Int = 20) async throws -> [Session] {
        try await command(name: "recentSessions", payload: ["limit": limit], field: "sessions", as: [Session].self)
    }

    func sessionEvents(sessionID: String) async throws -> [SessionEvent] {
        try await command(name: "sessionEvents", payload: ["sessionID": sessionID], field: "events", as: [SessionEvent].self)
    }

    func revertSessionEvent(event: SessionEvent, grantID: String, force: Bool) async throws -> RevertEventResult {
        try await command(
            name: "revertSessionEvent",
            payload: [
                "event": try XPCJSON.object(from: event),
                "grantID": grantID,
                "force": force,
            ],
            field: "result",
            as: RevertEventResult.self
        )
    }

    func trackedFiles() async throws -> [String] {
        try await command(name: "trackedFiles", field: "trackedFiles", as: [String].self)
    }

    func storageStats() async throws -> StorageStatsSnapshot {
        try await command(name: "storageStats", field: "stats", as: StorageStatsSnapshot.self)
    }

    func fileHistory(filePath: String) async throws -> [SnapshotRecord] {
        try await command(name: "fileHistory", payload: ["filePath": filePath], field: "snapshots", as: [SnapshotRecord].self)
    }

    func fileHistoryContext(filePath: String, limit: Int = 20) async throws -> FileHistoryContext {
        try await command(
            name: "fileHistoryContext",
            payload: ["filePath": filePath, "limit": limit],
            field: "context",
            as: FileHistoryContext.self
        )
    }

    func sessionContext(sessionID: String, agent: TargetApp? = nil) async throws -> SessionContextDetail {
        var payload: [String: Any] = ["sessionID": sessionID]
        if let agent {
            payload["agent"] = agent.rawValue
        }
        return try await command(
            name: "sessionContext",
            payload: payload,
            field: "context",
            as: SessionContextDetail.self
        )
    }

    func snapshotData(hash: String) async throws -> Data? {
        try await optionalCommand(name: "snapshotData", payload: ["hash": hash], field: "data", as: Data.self)
    }

    func runGarbageCollection() async throws -> Int {
        try await command(name: "runGarbageCollection", field: "count", as: Int.self)
    }

    func runIntegrityCheck() async throws -> Bool {
        try await command(name: "runIntegrityCheck", field: "ok", as: Bool.self)
    }

    func listEmailAccounts() async throws -> [EmailAccountRecord] {
        try await command(name: "listEmailAccounts", field: "accounts", as: [EmailAccountRecord].self)
    }

    func syncStates(accountID: String) async throws -> [SyncStateRecord] {
        try await command(name: "listSyncStates", payload: ["accountID": accountID], field: "states", as: [SyncStateRecord].self)
    }

    func emailMessageCount() async throws -> Int {
        try await command(name: "emailMessageCount", field: "count", as: Int.self)
    }

    func addIMAPAccount(
        displayName: String,
        provider: EmailProvider,
        server: String,
        port: Int,
        username: String,
        password: String
    ) async throws -> EmailAccountRecord {
        try await command(
            name: "addIMAPAccount",
            payload: [
                "displayName": displayName,
                "provider": provider.rawValue,
                "server": server,
                "port": port,
                "username": username,
                "password": password,
            ],
            field: "account",
            as: EmailAccountRecord.self
        )
    }

    func removeEmailAccount(id: String) async throws {
        _ = try await xpc.command(name: "removeEmailAccount", payload: ["accountID": id])
    }

    func toggleEmailSync(accountID: String, enabled: Bool) async throws {
        _ = try await xpc.command(name: "toggleEmailSync", payload: ["accountID": accountID, "enabled": enabled])
    }

    func syncEmailNow(accountID: String) async throws -> SyncResult {
        try await command(name: "syncEmailNow", payload: ["accountID": accountID], field: "result", as: SyncResult.self)
    }

    func emailMessages(accountID: String? = nil, mailbox: String? = nil, ids: [String]? = nil, limit: Int = 500) async throws -> [EmailMessageRecord] {
        var payload: [String: Any] = ["limit": limit]
        if let accountID { payload["accountID"] = accountID }
        if let mailbox { payload["mailbox"] = mailbox }
        if let ids { payload["ids"] = ids }
        return try await command(name: "emailMessages", payload: payload, field: "messages", as: [EmailMessageRecord].self)
    }

    func domainCounts() async throws -> [String: Int] {
        try await command(name: "domainCounts", field: "counts", as: [String: Int].self)
    }

    func unreadCountAll() async throws -> Int {
        try await command(name: "unreadCountAll", field: "count", as: Int.self)
    }

    func unreadCount(accountID: String, mailbox: String? = nil) async throws -> Int {
        var payload: [String: Any] = ["accountID": accountID]
        if let mailbox { payload["mailbox"] = mailbox }
        return try await command(name: "unreadCount", payload: payload, field: "count", as: Int.self)
    }

    func imapMailboxes(accountID: String) async throws -> [IMAPMailboxRecord] {
        try await command(name: "imapMailboxes", payload: ["accountID": accountID], field: "mailboxes", as: [IMAPMailboxRecord].self)
    }

    func sharedEmailCount() async throws -> Int {
        try await command(name: "sharedEmailCount", field: "count", as: Int.self)
    }

    func sharedEmailIDs() async throws -> Set<String> {
        Set(try await command(name: "sharedEmailIDs", field: "ids", as: [String].self))
    }

    func sharedEmails(limit: Int = 500) async throws -> [EmailMessageRecord] {
        try await command(name: "sharedEmails", payload: ["limit": limit], field: "messages", as: [EmailMessageRecord].self)
    }

    func shareEmails(emailIDs: [String]) async throws {
        _ = try await xpc.command(name: "shareEmails", payload: ["emailIDs": emailIDs])
    }

    func unshareEmails(emailIDs: [String]) async throws {
        _ = try await xpc.command(name: "unshareEmails", payload: ["emailIDs": emailIDs])
    }

    func unshareAllEmails() async throws {
        _ = try await xpc.command(name: "unshareAllEmails")
    }

    func updateEmailReadState(emailID: String, isRead: Bool) async throws {
        _ = try await xpc.command(name: "updateEmailReadState", payload: ["emailID": emailID, "isRead": isRead])
    }

    func updateEmailFlagState(emailID: String, isFlagged: Bool, flagColor: String?) async throws {
        var payload: [String: Any] = ["emailID": emailID, "isFlagged": isFlagged]
        if let flagColor { payload["flagColor"] = flagColor }
        _ = try await xpc.command(name: "updateEmailFlagState", payload: payload)
    }

    func batchUpdateReadState(emailIDs: [String], isRead: Bool) async throws {
        _ = try await xpc.command(name: "batchUpdateReadState", payload: ["emailIDs": emailIDs, "isRead": isRead])
    }

    func batchUpdateFlagState(emailIDs: [String], isFlagged: Bool, flagColor: String?) async throws {
        var payload: [String: Any] = ["emailIDs": emailIDs, "isFlagged": isFlagged]
        if let flagColor { payload["flagColor"] = flagColor }
        _ = try await xpc.command(name: "batchUpdateFlagState", payload: payload)
    }

    func searchEmailMessages(
        tokens: [SearchToken],
        freeText: String,
        accountID: String?,
        mailbox: String?,
        filter: QuickFilter?,
        sortKey: EmailSortKey,
        limit: Int
    ) async throws -> [EmailMessageRecord] {
        var payload: [String: Any] = [
            "tokens": try XPCJSON.object(from: tokens),
            "freeText": freeText,
            "sortKey": try XPCJSON.object(from: sortKey),
            "limit": limit,
        ]
        if let accountID { payload["accountID"] = accountID }
        if let mailbox { payload["mailbox"] = mailbox }
        if let filter { payload["filter"] = try XPCJSON.object(from: filter) }
        return try await command(name: "searchEmailMessages", payload: payload, field: "messages", as: [EmailMessageRecord].self)
    }

    func createSmartMailbox(displayName: String, iconName: String, rulesJSON: String) async throws {
        _ = try await xpc.command(
            name: "createSmartMailbox",
            payload: ["displayName": displayName, "iconName": iconName, "rulesJSON": rulesJSON]
        )
    }

    func listSmartMailboxes() async throws -> [SmartMailboxRecord] {
        try await command(name: "listSmartMailboxes", field: "mailboxes", as: [SmartMailboxRecord].self)
    }

    func updateSmartMailbox(mailboxID: String, displayName: String, iconName: String, rulesJSON: String) async throws {
        _ = try await xpc.command(
            name: "updateSmartMailbox",
            payload: [
                "mailboxID": mailboxID,
                "displayName": displayName,
                "iconName": iconName,
                "rulesJSON": rulesJSON,
            ]
        )
    }

    func deleteSmartMailbox(mailboxID: String) async throws {
        _ = try await xpc.command(name: "deleteSmartMailbox", payload: ["mailboxID": mailboxID])
    }

    func emailBackupInfo() async throws -> EmailBackupInfo {
        try await command(name: "emailBackupInfo", field: "info", as: EmailBackupInfo.self)
    }

    func fileVisibilityOverrides(agent: TargetApp) async throws -> [FileVisibilityOverrideRecord] {
        try await command(
            name: "listFileVisibilityOverrides",
            payload: ["agent": agent.rawValue],
            field: "overrides",
            as: [FileVisibilityOverrideRecord].self
        )
    }

    func setFileVisibilityOverride(
        agent: TargetApp,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool,
        decision: FileVisibilityOverrideDecision
    ) async throws {
        _ = try await xpc.command(
            name: "setFileVisibilityOverride",
            payload: [
                "agent": agent.rawValue,
                "sourceID": sourceID,
                "relativePath": relativePath,
                "isDirectory": isDirectory,
                "decision": decision.rawValue,
            ]
        )
    }

    func clearFileVisibilityOverride(
        agent: TargetApp,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool
    ) async throws {
        _ = try await xpc.command(
            name: "clearFileVisibilityOverride",
            payload: [
                "agent": agent.rawValue,
                "sourceID": sourceID,
                "relativePath": relativePath,
                "isDirectory": isDirectory,
            ]
        )
    }

    func listPendingApprovals() async throws -> [PendingApprovalRecord] {
        try await command(name: "listPendingApprovals", field: "requests", as: [PendingApprovalRecord].self)
    }

    func answerApproval(id: String, answer: String) async throws {
        _ = try await xpc.command(name: "answerApproval", payload: ["id": id, "answer": answer])
    }

    // MARK: - Unified rules

    func listRules(scope: RuleScope?) async throws -> [RuleRecord] {
        var payload: [String: Any] = [:]
        if let scope { payload["scope"] = scope.rawValue }
        return try await command(name: "listRules", payload: payload, field: "rules", as: [RuleRecord].self)
    }

    func upsertRule(_ rule: RuleRecord) async throws {
        _ = try await xpc.command(
            name: "upsertRule",
            payload: ["rule": try XPCJSON.object(from: rule)]
        )
    }

    func deleteRule(id: String) async throws {
        _ = try await xpc.command(name: "deleteRule", payload: ["id": id])
    }

    func setRuleEnabled(id: String, enabled: Bool) async throws {
        _ = try await xpc.command(name: "setRuleEnabled", payload: ["id": id, "enabled": enabled])
    }

    func reorderRules(scope: RuleScope, ids: [String]) async throws {
        _ = try await xpc.command(name: "reorderRules", payload: ["scope": scope.rawValue, "ids": ids])
    }

    func resetSeededRules() async throws {
        _ = try await xpc.command(name: "resetSeededRules", payload: [:])
    }

    func previewRuleMatches(rule: RuleRecord, agent: TargetApp) async throws -> RuleMatchPreview {
        try await command(
            name: "previewRuleMatches",
            payload: [
                "rule": try XPCJSON.object(from: rule),
                "agent": agent.rawValue,
            ],
            field: "preview",
            as: RuleMatchPreview.self
        )
    }

    private func command<T: Decodable>(
        name: String,
        payload: [String: Any] = [:],
        field: String? = nil,
        as type: T.Type
    ) async throws -> T {
        let response = try await xpc.command(name: name, payload: payload)
        if let field {
            guard let object = response[field], !(object is NSNull) else {
                throw ManifoldXPCError.malformedReply
            }
            return try XPCJSON.decode(T.self, from: object)
        }
        return try XPCJSON.decode(T.self, from: response)
    }

    private func optionalCommand<T: Decodable>(
        name: String,
        payload: [String: Any] = [:],
        field: String,
        as type: T.Type
    ) async throws -> T? {
        let response = try await xpc.command(name: name, payload: payload)
        guard let object = response[field], !(object is NSNull) else { return nil }
        return try XPCJSON.decode(T.self, from: object)
    }
}
