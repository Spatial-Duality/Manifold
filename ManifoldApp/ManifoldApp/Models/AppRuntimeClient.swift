// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import ManifoldKit
import ManifoldXPC

struct RuntimeStatusSnapshot: Codable, Sendable {
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
    let selectedEmailCount: Int?
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

struct ApplyWorkspaceResult: Codable, Sendable {
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

struct MailArchiveInfo: Codable, Sendable {
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
    func runtimeStatusSnapshot() async throws -> RuntimeStatusSnapshot
    func dataControlSummary() async throws -> DataControlSummary
    func listSources() async throws -> [SourceRecord]
    func addSource(path: String, displayName: String) async throws -> SourceRecord
    func removeSource(sourceID: String) async throws
    func pauseSource(sourceID: String) async throws
    func resumeSource(sourceID: String) async throws
    func policies() async throws -> RuntimeStatusSnapshot
    func pauseAgent(_ agent: TargetApp) async throws
    func resumeAgent(_ agent: TargetApp) async throws
    func addSource(_ sourceID: String, to agent: TargetApp) async throws
    func removeSource(_ sourceID: String, from agent: TargetApp) async throws
    func updateAccessRecordingLevel(_ level: AccessRecordingLevel, for agent: TargetApp) async throws
    func getPrivacySettings() async throws -> PrivacySettingsBundle
    func updatePrivacySettings(settings: PrivacyPreflightSettings?, policy: AgentPrivacyPolicy?) async throws
    func listPrivacyRuntimes() async throws -> [PrivacyRuntimeDescriptor]
    func installPrivacyRuntime(id: String) async throws -> PrivacyRuntimeStatus
    func uninstallPrivacyRuntime(id: String) async throws -> PrivacyRuntimeStatus
    func privacyRuntimeStatus() async throws -> PrivacyRuntimeStatus
    func clearPrivacyCache() async throws -> Int
    func privacyIndexStatus() async throws -> PrivacyIndexRuntimeStatus
    func listPrivacyIndex(scope: PrivacyIndexScope, filter: PrivacyIndexFilter, limit: Int) async throws -> [PrivacyIndexRecord]
    func listPrivacyIdentitySuggestions() async throws -> [PrivacyIdentitySuggestion]
    func acceptPrivacyIdentitySuggestion(id: String) async throws
    func rejectPrivacyIdentitySuggestion(id: String) async throws
    func upsertPrivacyIdentity(_ record: PrivacyIdentityRecord) async throws
    func upsertPrivacyOrgAllowEntry(_ entry: PrivacyOrgAllowEntry) async throws
    func listPrivacyIdentities() async throws -> [PrivacyIdentityRecord]
    func listPrivacyOrgAllowEntries() async throws -> [PrivacyOrgAllowEntry]
    func deletePrivacyIdentity(id: String) async throws
    func deletePrivacyOrgAllowEntry(id: String) async throws
    func rescanPrivacyContent(contentIDs: [String]) async throws
    func getEmailRuleSet(agent: TargetApp) async throws -> EmailRuleSet
    func updateEmailRuleSet(agent: TargetApp, ruleSet: EmailRuleSet) async throws
    func getEmailRuleActivitySummary(agent: TargetApp) async throws -> EmailRuleActivitySummary
    func activeGrantState(targetApp: TargetApp) async throws -> ActiveGrantState
    func sessionAccessMode() async throws -> SessionAccessMode
    func setSessionAccessMode(_ mode: SessionAccessMode) async throws
    func sessionPreview(
        targetApp: TargetApp,
        fileScopes: [FileSelectionScope],
        selectedEmailIDs: Set<String>,
        emailSensitivity: String?
    ) async throws -> SessionPreview
    func startGatewaySession(
        targetApp: TargetApp,
        fileScopes: [FileSelectionScope],
        selectedEmailIDs: Set<String>,
        summaryFraming: String?,
        noteCaptureMode: SessionNoteCaptureMode,
        requestDetailLevel: AccessRecordingLevel?,
        memoryAccessEnabled: Bool,
        emailSensitivity: String?
    ) async throws -> ActiveGrantState
    func updateGrantRequestDetailLevel(grantID: String, level: AccessRecordingLevel?) async throws -> GrantRecord
    func updateGrantMemoryAccess(grantID: String, enabled: Bool) async throws -> GrantRecord
    func endSession(grantID: String) async throws
    func restoreSnapshot(snapshotID: Int, filePath: String) async throws -> RestoreSnapshotResult
    func markWorkBlockReviewing(id: String) async throws
    func cancelWorkBlockReview(id: String) async throws
    func pauseGatewaySession(id: String) async throws
    func resumeGatewaySession(id: String) async throws
    func discardDraftWorkspace(id: String, grantID: String?, endSession: Bool) async throws
    func promotionPreview(grantID: String) async throws -> WorkBlockPreview
    func applyDraftWorkspace(grantID: String, endSession: Bool) async throws -> ApplyWorkspaceResult
    func recentActivity(limit: Int) async throws -> [AuditEntry]
    func recentSessions(limit: Int) async throws -> [Session]
    func sessionEvents(sessionID: String) async throws -> [SessionEvent]
    func revertSessionEvent(event: SessionEvent, grantID: String, force: Bool) async throws -> RevertEventResult
    func trackedFiles() async throws -> [String]
    func trackedFileCounts() async throws -> [String: Int]
    func storageStats() async throws -> StorageStatsSnapshot
    func recentLedgerEntries(limit: Int) async throws -> [LedgerEntry]
    func verifyLedger() async throws -> LedgerVerificationResult
    func toolCostReport(limit: Int) async throws -> ToolCostReport
    func listMemory(limit: Int, includeDeleted: Bool) async throws -> [MemoryItem]
    func listMemorySources() async throws -> [MemorySourceSummary]
    func getMemorySettings() async throws -> MemorySettings
    func updateMemorySettings(_ settings: MemorySettings) async throws -> MemorySettings
    func forgetMemory(id: String) async throws
    func listSkills(limit: Int) async throws -> [SkillRecord]
    func recentExecRuns(limit: Int) async throws -> [ExecRunRecord]
    func listCapabilityHandles(limit: Int) async throws -> [ValueHandle]
    func queryGraphNodes(query: String, limit: Int) async throws -> [KnowledgeGraphNode]
    func recentFabricationFindings(limit: Int) async throws -> [FabricationFinding]
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
    func addOAuthIMAPAccount(
        displayName: String,
        provider: EmailProvider,
        server: String,
        port: Int,
        username: String,
        tokenSet: MicrosoftOAuthTokenSet
    ) async throws -> EmailAccountRecord
    func removeEmailAccount(id: String) async throws
    func toggleEmailSync(accountID: String, enabled: Bool) async throws
    func syncEmailNow(accountID: String) async throws -> SyncResult
    func emailMessages(accountID: String?, mailbox: String?, ids: [String]?, limit: Int) async throws -> [EmailMessageRecord]
    func domainCounts() async throws -> [String: Int]
    func unreadCountAll() async throws -> Int
    func unreadCount(accountID: String, mailbox: String?) async throws -> Int
    func imapMailboxes(accountID: String) async throws -> [IMAPMailboxRecord]
    func sharedEmailCount(agent: TargetApp) async throws -> Int
    func sharedEmailIDs(agent: TargetApp) async throws -> Set<String>
    func sharedEmails(agent: TargetApp, limit: Int) async throws -> [EmailMessageRecord]
    func shareEmails(emailIDs: [String], for agent: TargetApp) async throws
    func unshareEmails(emailIDs: [String], for agent: TargetApp) async throws
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
    func emailBackupInfo() async throws -> MailArchiveInfo
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

    // MARK: - Named session templates (Lane B-rest)

    /// List saved templates visible to an agent (target_app match + unscoped).
    func accessTemplates(for agent: TargetApp) async throws -> [AccessPresetRecord]
    /// Load a saved template and its scopes.
    func loadAccessTemplate(presetID: String) async throws -> AccessPresetSnapshot
    /// Create or update a saved template.
    func saveAccessTemplate(
        presetID: String?,
        name: String,
        targetApp: TargetApp?,
        fileScopes: [FileSelectionScope],
        emailIDs: [String]
    ) async throws -> AccessPresetRecord
    /// Remove a saved template.
    func deleteAccessTemplate(presetID: String) async throws
    /// Start a gateway session using a saved template's scope. Lenient on
    /// stale references — see `StartSessionFromTemplateResult` for details.
    func startSessionFromTemplate(
        presetID: String,
        targetApp: TargetApp?,
        summaryFraming: String?,
        noteCaptureMode: SessionNoteCaptureMode,
        emailSensitivity: String?
    ) async throws -> StartSessionFromTemplateResult

    // MARK: - Inspector gem fetchers

    /// Recent exposure records for one file path. Used by the inspector to
    /// surface per-agent read/write counts ("Claude read 5×, Codex 0×").
    /// Aggregation lives in the app — the runtime returns the raw timeline.
    func fileExposures(resourcePath: String, limit: Int) async throws -> [ExposureRecord]

    /// File paths whose snapshot timeline contains at least one agent-
    /// authored entry. Drives the per-row sparkle in the Files table.
    func aiTouchedFilePaths() async throws -> Set<String>

    /// Per-source counts of files that have changed since the named
    /// agent's most recently ended grant. Drives the drift badge on
    /// FoldersMatrixView source rows. Returns sourceID → drift count
    /// (only sources with > 0 changes are present in the dictionary).
    /// Empty map means no prior grant exists yet for this agent.
    func sourceDriftCounts(agent: TargetApp) async throws -> [String: Int]

    // MARK: - Filter mode (Sensitive content detection — Lane C)

    /// Effective filter mode for an agent: per-agent override > global > .off.
    func filterMode(for agent: TargetApp) async throws -> FilterMode
    /// Global default filter mode (applied when an agent has no per-agent override).
    func globalFilterMode() async throws -> FilterMode
    /// Set per-agent filter mode override.
    func setFilterMode(_ mode: FilterMode, for agent: TargetApp) async throws
    /// Set global default filter mode.
    func setGlobalFilterMode(_ mode: FilterMode) async throws
    /// Drop a per-agent override so the agent falls back to the global default.
    func clearAgentFilterMode(_ agent: TargetApp) async throws

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

// Default implementations for Lane B-rest (named session templates) and
// Lane C (filter mode) methods so existing stub / in-memory / preview
// implementations stay green. Concrete clients (AppRuntimeClient) override
// these via their own implementations.
extension RuntimeClientProtocol {
    func sessionAccessMode() async throws -> SessionAccessMode { .defaultSession }
    func setSessionAccessMode(_ mode: SessionAccessMode) async throws {}

    // Lane B-rest defaults
    func accessTemplates(for agent: TargetApp) async throws -> [AccessPresetRecord] { [] }
    func loadAccessTemplate(presetID: String) async throws -> AccessPresetSnapshot {
        throw RuntimeClientStubError.unimplemented("loadAccessTemplate")
    }
    func saveAccessTemplate(
        presetID: String?,
        name: String,
        targetApp: TargetApp?,
        fileScopes: [FileSelectionScope],
        emailIDs: [String]
    ) async throws -> AccessPresetRecord {
        throw RuntimeClientStubError.unimplemented("saveAccessTemplate")
    }
    func deleteAccessTemplate(presetID: String) async throws {
        throw RuntimeClientStubError.unimplemented("deleteAccessTemplate")
    }
    func startSessionFromTemplate(
        presetID: String,
        targetApp: TargetApp?,
        summaryFraming: String?,
        noteCaptureMode: SessionNoteCaptureMode,
        emailSensitivity: String?
    ) async throws -> StartSessionFromTemplateResult {
        throw RuntimeClientStubError.unimplemented("startSessionFromTemplate")
    }

    // Lane C defaults
    func filterMode(for agent: TargetApp) async throws -> FilterMode { .off }
    func globalFilterMode() async throws -> FilterMode { .off }
    func setFilterMode(_ mode: FilterMode, for agent: TargetApp) async throws {
        throw RuntimeClientStubError.unimplemented("setFilterMode")
    }
    func setGlobalFilterMode(_ mode: FilterMode) async throws {
        throw RuntimeClientStubError.unimplemented("setGlobalFilterMode")
    }
    func clearAgentFilterMode(_ agent: TargetApp) async throws {
        throw RuntimeClientStubError.unimplemented("clearAgentFilterMode")
    }

    // Inspector gem defaults
    func fileExposures(resourcePath: String, limit: Int) async throws -> [ExposureRecord] { [] }
    func aiTouchedFilePaths() async throws -> Set<String> { [] }
    func sourceDriftCounts(agent: TargetApp) async throws -> [String: Int] { [:] }
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
    public let contextJSON: String?
    public let requestedAt: Double
    public let status: String
    public let resolutionAction: String?

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
        contextJSON: String? = nil,
        requestedAt: Double,
        status: String,
        resolutionAction: String? = nil
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
        self.contextJSON = contextJSON
        self.requestedAt = requestedAt
        self.status = status
        self.resolutionAction = resolutionAction
    }
}

extension RuntimeClientProtocol {
    func ping() async -> RuntimePingResult { RuntimePingResult(ok: false, agentVersion: nil) }
    func runtimeStatusSnapshot() async throws -> RuntimeStatusSnapshot { throw RuntimeClientStubError.unimplemented("runtimeStatusSnapshot") }
    func dataControlSummary() async throws -> DataControlSummary { throw RuntimeClientStubError.unimplemented("dataControlSummary") }
    func listSources() async throws -> [SourceRecord] { throw RuntimeClientStubError.unimplemented("listSources") }
    func addSource(path: String, displayName: String) async throws -> SourceRecord { throw RuntimeClientStubError.unimplemented("addSource") }
    func removeSource(sourceID: String) async throws { throw RuntimeClientStubError.unimplemented("removeSource") }
    func pauseSource(sourceID: String) async throws { throw RuntimeClientStubError.unimplemented("pauseSource") }
    func resumeSource(sourceID: String) async throws { throw RuntimeClientStubError.unimplemented("resumeSource") }
    func policies() async throws -> RuntimeStatusSnapshot { try await runtimeStatusSnapshot() }
    func pauseAgent(_ agent: TargetApp) async throws { throw RuntimeClientStubError.unimplemented("pauseAgent") }
    func resumeAgent(_ agent: TargetApp) async throws { throw RuntimeClientStubError.unimplemented("resumeAgent") }
    func addSource(_ sourceID: String, to agent: TargetApp) async throws { throw RuntimeClientStubError.unimplemented("addSource(_:to:)") }
    func removeSource(_ sourceID: String, from agent: TargetApp) async throws { throw RuntimeClientStubError.unimplemented("removeSource(_:from:)") }
    func updateAccessRecordingLevel(_ level: AccessRecordingLevel, for agent: TargetApp) async throws { throw RuntimeClientStubError.unimplemented("updateAccessRecordingLevel") }
    func getPrivacySettings() async throws -> PrivacySettingsBundle { throw RuntimeClientStubError.unimplemented("getPrivacySettings") }
    func updatePrivacySettings(settings: PrivacyPreflightSettings?, policy: AgentPrivacyPolicy?) async throws { throw RuntimeClientStubError.unimplemented("updatePrivacySettings") }
    func listPrivacyRuntimes() async throws -> [PrivacyRuntimeDescriptor] { [] }
    func installPrivacyRuntime(id: String) async throws -> PrivacyRuntimeStatus { throw RuntimeClientStubError.unimplemented("installPrivacyRuntime") }
    func uninstallPrivacyRuntime(id: String) async throws -> PrivacyRuntimeStatus { throw RuntimeClientStubError.unimplemented("uninstallPrivacyRuntime") }
    func privacyRuntimeStatus() async throws -> PrivacyRuntimeStatus { throw RuntimeClientStubError.unimplemented("privacyRuntimeStatus") }
    func clearPrivacyCache() async throws -> Int { throw RuntimeClientStubError.unimplemented("clearPrivacyCache") }
    func privacyIndexStatus() async throws -> PrivacyIndexRuntimeStatus {
        PrivacyIndexRuntimeStatus(
            enabled: false,
            queuedJobs: 0,
            runningJobs: 0,
            failedJobs: 0,
            indexedItems: 0,
            staleItems: 0,
            watchedSources: [],
            lastError: nil
        )
    }
    func listPrivacyIndex(scope: PrivacyIndexScope, filter: PrivacyIndexFilter, limit: Int) async throws -> [PrivacyIndexRecord] { [] }
    func listPrivacyIdentitySuggestions() async throws -> [PrivacyIdentitySuggestion] { [] }
    func acceptPrivacyIdentitySuggestion(id: String) async throws {}
    func rejectPrivacyIdentitySuggestion(id: String) async throws {}
    func upsertPrivacyIdentity(_ record: PrivacyIdentityRecord) async throws { throw RuntimeClientStubError.unimplemented("upsertPrivacyIdentity") }
    func upsertPrivacyOrgAllowEntry(_ entry: PrivacyOrgAllowEntry) async throws { throw RuntimeClientStubError.unimplemented("upsertPrivacyOrgAllowEntry") }
    func listPrivacyIdentities() async throws -> [PrivacyIdentityRecord] { [] }
    func listPrivacyOrgAllowEntries() async throws -> [PrivacyOrgAllowEntry] { [] }
    func deletePrivacyIdentity(id: String) async throws {}
    func deletePrivacyOrgAllowEntry(id: String) async throws {}
    func rescanPrivacyContent(contentIDs: [String]) async throws {}
    func getEmailRuleSet(agent: TargetApp) async throws -> EmailRuleSet { throw RuntimeClientStubError.unimplemented("getEmailRuleSet") }
    func updateEmailRuleSet(agent: TargetApp, ruleSet: EmailRuleSet) async throws { throw RuntimeClientStubError.unimplemented("updateEmailRuleSet") }
    func getEmailRuleActivitySummary(agent: TargetApp) async throws -> EmailRuleActivitySummary { throw RuntimeClientStubError.unimplemented("getEmailRuleActivitySummary") }
    func activeGrantState(targetApp: TargetApp) async throws -> ActiveGrantState { throw RuntimeClientStubError.unimplemented("activeGrantState") }
    func sessionPreview(targetApp: TargetApp, fileScopes: [FileSelectionScope], selectedEmailIDs: Set<String>, emailSensitivity: String?) async throws -> SessionPreview { throw RuntimeClientStubError.unimplemented("sessionPreview") }
    func startGatewaySession(targetApp: TargetApp, fileScopes: [FileSelectionScope], selectedEmailIDs: Set<String>, summaryFraming: String?, noteCaptureMode: SessionNoteCaptureMode, requestDetailLevel: AccessRecordingLevel?, memoryAccessEnabled: Bool, emailSensitivity: String?) async throws -> ActiveGrantState { throw RuntimeClientStubError.unimplemented("startGatewaySession") }
    func updateGrantRequestDetailLevel(grantID: String, level: AccessRecordingLevel?) async throws -> GrantRecord { throw RuntimeClientStubError.unimplemented("updateGrantRequestDetailLevel") }
    func updateGrantMemoryAccess(grantID: String, enabled: Bool) async throws -> GrantRecord { throw RuntimeClientStubError.unimplemented("updateGrantMemoryAccess") }
    func endSession(grantID: String) async throws { throw RuntimeClientStubError.unimplemented("endSession") }
    func restoreSnapshot(snapshotID: Int, filePath: String) async throws -> RestoreSnapshotResult { throw RuntimeClientStubError.unimplemented("restoreSnapshot") }
    func markWorkBlockReviewing(id: String) async throws { throw RuntimeClientStubError.unimplemented("markWorkBlockReviewing") }
    func cancelWorkBlockReview(id: String) async throws { throw RuntimeClientStubError.unimplemented("cancelWorkBlockReview") }
    func pauseGatewaySession(id: String) async throws { throw RuntimeClientStubError.unimplemented("pauseGatewaySession") }
    func resumeGatewaySession(id: String) async throws { throw RuntimeClientStubError.unimplemented("resumeGatewaySession") }
    func discardDraftWorkspace(id: String, grantID: String?, endSession: Bool) async throws { throw RuntimeClientStubError.unimplemented("discardDraftWorkspace") }
    func discardDraftWorkspace(id: String, grantID: String?) async throws { try await discardDraftWorkspace(id: id, grantID: grantID, endSession: false) }
    func promotionPreview(grantID: String) async throws -> WorkBlockPreview { throw RuntimeClientStubError.unimplemented("promotionPreview") }
    func applyDraftWorkspace(grantID: String, endSession: Bool) async throws -> ApplyWorkspaceResult { throw RuntimeClientStubError.unimplemented("applyDraftWorkspace") }
    func applyDraftWorkspace(grantID: String) async throws -> ApplyWorkspaceResult { try await applyDraftWorkspace(grantID: grantID, endSession: false) }
    func recentActivity(limit: Int) async throws -> [AuditEntry] { [] }
    func recentSessions(limit: Int) async throws -> [Session] { [] }
    func listPendingApprovals() async throws -> [PendingApprovalRecord] { [] }
    func answerApproval(id: String, answer: String) async throws {}
    func sessionEvents(sessionID: String) async throws -> [SessionEvent] { [] }
    func revertSessionEvent(event: SessionEvent, grantID: String, force: Bool) async throws -> RevertEventResult { throw RuntimeClientStubError.unimplemented("revertSessionEvent") }
    func trackedFiles() async throws -> [String] { [] }
    func trackedFileCounts() async throws -> [String: Int] { [:] }
    func storageStats() async throws -> StorageStatsSnapshot { StorageStatsSnapshot(storageUsed: 0) }
    func recentLedgerEntries(limit: Int) async throws -> [LedgerEntry] { [] }
    func verifyLedger() async throws -> LedgerVerificationResult {
        LedgerVerificationResult(verified: true, checkedEntries: 0, firstBrokenEntryID: nil, message: "Ledger is empty.")
    }
    func toolCostReport(limit: Int) async throws -> ToolCostReport {
        ToolCostReport(totalCalls: 0, totalOutputBytes: 0, averageDurationMS: 0, callsByTool: [:], recent: [])
    }
    func listMemory(limit: Int, includeDeleted: Bool) async throws -> [MemoryItem] { [] }
    func listMemorySources() async throws -> [MemorySourceSummary] { [] }
    func getMemorySettings() async throws -> MemorySettings { MemorySettings() }
    func updateMemorySettings(_ settings: MemorySettings) async throws -> MemorySettings { settings }
    func forgetMemory(id: String) async throws {}
    func listSkills(limit: Int) async throws -> [SkillRecord] { [] }
    func recentExecRuns(limit: Int) async throws -> [ExecRunRecord] { [] }
    func listCapabilityHandles(limit: Int) async throws -> [ValueHandle] { [] }
    func queryGraphNodes(query: String, limit: Int) async throws -> [KnowledgeGraphNode] { [] }
    func recentFabricationFindings(limit: Int) async throws -> [FabricationFinding] { [] }
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
    func addOAuthIMAPAccount(displayName: String, provider: EmailProvider, server: String, port: Int, username: String, tokenSet: MicrosoftOAuthTokenSet) async throws -> EmailAccountRecord { throw RuntimeClientStubError.unimplemented("addOAuthIMAPAccount") }
    func removeEmailAccount(id: String) async throws { throw RuntimeClientStubError.unimplemented("removeEmailAccount") }
    func toggleEmailSync(accountID: String, enabled: Bool) async throws { throw RuntimeClientStubError.unimplemented("toggleEmailSync") }
    func syncEmailNow(accountID: String) async throws -> SyncResult { throw RuntimeClientStubError.unimplemented("syncEmailNow") }
    func emailMessages(accountID: String? = nil, mailbox: String? = nil, ids: [String]? = nil, limit: Int = 500) async throws -> [EmailMessageRecord] { [] }
    func domainCounts() async throws -> [String: Int] { [:] }
    func unreadCountAll() async throws -> Int { 0 }
    func unreadCount(accountID: String, mailbox: String? = nil) async throws -> Int { 0 }
    func imapMailboxes(accountID: String) async throws -> [IMAPMailboxRecord] { [] }
    func sharedEmailCount(agent: TargetApp) async throws -> Int { 0 }
    func sharedEmailIDs(agent: TargetApp) async throws -> Set<String> { [] }
    func sharedEmails(agent: TargetApp, limit: Int = 500) async throws -> [EmailMessageRecord] { [] }
    func shareEmails(emailIDs: [String], for agent: TargetApp) async throws { throw RuntimeClientStubError.unimplemented("shareEmails") }
    func unshareEmails(emailIDs: [String], for agent: TargetApp) async throws { throw RuntimeClientStubError.unimplemented("unshareEmails") }
    func sharedEmailCount() async throws -> Int { try await sharedEmailCount(agent: .cowork) }
    func sharedEmailIDs() async throws -> Set<String> { try await sharedEmailIDs(agent: .cowork) }
    func sharedEmails(limit: Int = 500) async throws -> [EmailMessageRecord] { try await sharedEmails(agent: .cowork, limit: limit) }
    func shareEmails(emailIDs: [String]) async throws { try await shareEmails(emailIDs: emailIDs, for: .cowork) }
    func unshareEmails(emailIDs: [String]) async throws { try await unshareEmails(emailIDs: emailIDs, for: .cowork) }
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
    func emailBackupInfo() async throws -> MailArchiveInfo { MailArchiveInfo(path: "", diskUsage: 0) }
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
    case baseline
    case emailRules = "email-rules"
    case trackedWork = "tracked-work"
    case privacy
    case syntheticMCPUI = "synthetic-mcp-ui"
}

enum AppRuntimeScenario: String, Sendable {
    case syntheticMCPUI = "synthetic-mcp-ui"
}

enum AppTestEnvironment {
    static let runtimeModeKey = "MANIFOLD_TEST_RUNTIME_MODE"
    static let onboardingCompletedKey = "manifold.onboarding.completed"

    static func userDefaultsSuiteName(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let testHome = testHomeURL(env: env) else { return nil }
        let digest = SHA256.hash(data: Data(testHome.path.utf8)).prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        return "com.spatialduality.manifold.tests.\(digest)"
    }

    static func testHomeURL(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        ManifoldRuntimeEnvironment.testHomeURL(env: env)
    }

    static func userDefaults(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> UserDefaults {
        guard let suiteName = userDefaultsSuiteName(env: env) else { return .standard }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }
}

enum SyntheticMCPUITestBootstrap {
    private final class ContextBox: @unchecked Sendable {
        let scenario: AppRuntimeScenario
        let testHome: URL
        let runtimeStoreURL: URL
        let grantStore: GrantStore
        let emailStore: EmailStore
        let privacyStore: PrivacyStore
        let policyStore: PolicyStore
        let workBlockStore: WorkBlockStore
        let auditStore: AuditStore
        let db: DatabaseConnection

        init(
            scenario: AppRuntimeScenario,
            testHome: URL,
            runtimeStoreURL: URL,
            grantStore: GrantStore,
            emailStore: EmailStore,
            privacyStore: PrivacyStore,
            policyStore: PolicyStore,
            workBlockStore: WorkBlockStore,
            auditStore: AuditStore,
            db: DatabaseConnection
        ) {
            self.scenario = scenario
            self.testHome = testHome
            self.runtimeStoreURL = runtimeStoreURL
            self.grantStore = grantStore
            self.emailStore = emailStore
            self.privacyStore = privacyStore
            self.policyStore = policyStore
            self.workBlockStore = workBlockStore
            self.auditStore = auditStore
            self.db = db
        }
    }

    private final class ResultBox: @unchecked Sendable {
        let semaphore = DispatchSemaphore(value: 0)
        var error: Error?
    }

    static func prepare(
        scenario: AppRuntimeScenario,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        guard let testHome = AppTestEnvironment.testHomeURL(env: env) else {
            return
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: testHome.path) {
            try fileManager.removeItem(at: testHome)
        }
        try fileManager.createDirectory(at: testHome, withIntermediateDirectories: true)

        let defaults = AppTestEnvironment.userDefaults(env: env)
        if let suiteName = AppTestEnvironment.userDefaultsSuiteName(env: env) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(true, forKey: AppTestEnvironment.onboardingCompletedKey)

        let runtimeStoreURL = ManifoldRuntimeEnvironment.runtimeStoreURL(env: env)
            ?? testHome.appendingPathComponent("runtime-store", isDirectory: true)
        let appSupportRoot = ManifoldRuntimeEnvironment.appSupportRootURL(env: env)
            ?? testHome.appendingPathComponent("app-support", isDirectory: true)
        let launchAgentRoot = (ManifoldRuntimeEnvironment.launchAgentPlistURL(env: env)
            ?? testHome.appendingPathComponent("LaunchAgents", isDirectory: true)
                .appendingPathComponent("\(ManifoldRuntimeEnvironment.xpcServiceName(env: env)).plist")).deletingLastPathComponent()

        try fileManager.createDirectory(at: runtimeStoreURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: launchAgentRoot, withIntermediateDirectories: true)

        let db = try DatabaseConnection(url: runtimeStoreURL.appendingPathComponent("manifold.db"))
        try DatabaseMigrator(db: db).migrate()
        let grantStore = GrantStore(db: db)
        let emailStore = EmailStore(db: db)
        let privacyStore = PrivacyStore(db: db)
        let policyStore = PolicyStore(db: db)
        let workBlockStore = WorkBlockStore(db: db)
        let auditStore = try AuditStore(db: db)
        let context = ContextBox(
            scenario: scenario,
            testHome: testHome,
            runtimeStoreURL: runtimeStoreURL,
            grantStore: grantStore,
            emailStore: emailStore,
            privacyStore: privacyStore,
            policyStore: policyStore,
            workBlockStore: workBlockStore,
            auditStore: auditStore,
            db: db
        )

        switch scenario {
        case .syntheticMCPUI:
            let result = ResultBox()
            Task.detached { [context, result] in
                do {
                    try await seedSyntheticMCPUI(
                        testHome: context.testHome,
                        runtimeStoreURL: context.runtimeStoreURL,
                        grantStore: context.grantStore,
                        emailStore: context.emailStore,
                        privacyStore: context.privacyStore,
                        policyStore: context.policyStore,
                        workBlockStore: context.workBlockStore,
                        auditStore: context.auditStore,
                        db: context.db
                    )
                } catch {
                    result.error = error
                }
                result.semaphore.signal()
            }
            result.semaphore.wait()
            if let error = result.error {
                throw error
            }
        }
    }

    private static func seedSyntheticMCPUI(
        testHome: URL,
        runtimeStoreURL: URL,
        grantStore: GrantStore,
        emailStore: EmailStore,
        privacyStore: PrivacyStore,
        policyStore: PolicyStore,
        workBlockStore: WorkBlockStore,
        auditStore: AuditStore,
        db: DatabaseConnection
    ) async throws {
        let fileManager = FileManager.default
        let now = ISO8601DateFormatter.shared.string(from: Date())
        let sourceRoot = testHome.appendingPathComponent("sources/Synthetic MCP UI", isDirectory: true)
        let materializationRoot = testHome.appendingPathComponent("materialized/codex", isDirectory: true)
        let privacyStorage = runtimeStoreURL.appendingPathComponent("privacy", isDirectory: true)
        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: materializationRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: privacyStorage, withIntermediateDirectories: true)

        let sourceDocs = sourceRoot.appendingPathComponent("Docs", isDirectory: true)
        try fileManager.createDirectory(at: sourceDocs, withIntermediateDirectories: true)

        let sensitiveText = """
        Customer outreach draft for Ada Example
        Email: ada@example.com
        Home address: 123 Market Street, London
        API key: sk-test-1234567890abcdefghijklmnop
        """
        let safeText = """
        Team notes
        - Vendor review is scheduled for Friday.
        - No personal identifiers are stored in this file.
        """
        let teaPartyText = """
        MANIFOLD_OPENAI_ANTHROPIC_TEA_PARTY
        OpenAI brought eval cupcakes. Anthropic brought a tiny constitution printed on a napkin.
        The deterministic UI loop brought the checklist.
        """
        let contextRequestText = """
        CONTEXT_REQUEST_BRIEF
        User asks Codex to explain whether the model garden tea party can be shared safely.
        Backend should preserve the request intent without exposing blocked records.
        """
        let filterText = """
        FILTER_MODE_SECRET_MARKER
        There once was a test with a key: sk-OpenAIAnthropic1234567890ABCDE
        It stayed inside Manifold's policy tree.
        """
        let sensitiveURL = sourceDocs.appendingPathComponent("CustomerDraft.txt")
        let safeURL = sourceDocs.appendingPathComponent("ReleaseNotes.md")
        let teaPartyURL = sourceDocs.appendingPathComponent("ModelGardenTeaParty.md")
        let contextRequestURL = sourceDocs.appendingPathComponent("ContextRequest.md")
        let filterURL = sourceDocs.appendingPathComponent("KeyLimerick.txt")
        let unsupportedURL = sourceDocs.appendingPathComponent("Archive.bin")
        try sensitiveText.write(to: sensitiveURL, atomically: true, encoding: .utf8)
        try safeText.write(to: safeURL, atomically: true, encoding: .utf8)
        try teaPartyText.write(to: teaPartyURL, atomically: true, encoding: .utf8)
        try contextRequestText.write(to: contextRequestURL, atomically: true, encoding: .utf8)
        try filterText.write(to: filterURL, atomically: true, encoding: .utf8)
        try Data([0, 1, 2, 3, 255, 0, 42]).write(to: unsupportedURL)

        let sourceID = try await grantStore.addSource(displayName: "Synthetic MCP UI", rootPath: sourceRoot.path)
        let grant = try await grantStore.startGrant(
            targetApp: .codex,
            profileID: "ui-test-profile",
            sourceIDs: [sourceID],
            materializationRoot: materializationRoot.path,
            emailSensitivity: EmailSensitivityLevel.strict.rawValue,
            summaryFraming: "Synthetic MCP/UI scenario",
            explicitSelection: true,
            noteCaptureMode: .basic
        )
        _ = try await workBlockStore.startBlock(agent: .codex, grantID: grant.grantID, sourceIDs: [sourceID])

        var codexPolicy = try await policyStore.policy(for: .codex)
        codexPolicy.allowedSourceIDs.insert(sourceID)
        try await policyStore.updatePolicy(codexPolicy)

        var coworkPolicy = try await policyStore.policy(for: .cowork)
        coworkPolicy.allowedSourceIDs.insert(sourceID)
        try await policyStore.updatePolicy(coworkPolicy)

        let account = try emailStore.addEmailAccount(
            displayName: "Runtime Inbox",
            providerType: EmailProvider.gmail.rawValue,
            server: "imap.runtime.test",
            port: 993,
            username: "runtime@manifold.test"
        )
        try emailStore.upsertIMAPMailbox(
            accountID: account.accountID,
            name: "INBOX",
            delimiter: "/",
            flags: ["\\\\Inbox"],
            isSelectable: true
        )

        let attachmentData = Data("Account number 1234-5678 and secret sk-runtime-abcdef".utf8)
        let attachmentHash = sha256(attachmentData)
        let emlURL = testHome.appendingPathComponent("mail/runtime-message.eml", isDirectory: false)
        try fileManager.createDirectory(at: emlURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try runtimeEML(
            subject: "Privacy review needed",
            body: """
            Hi Ada Example,
            Please review the attached customer packet for ada@example.com before sharing it with Codex.
            """,
            attachmentFilename: "customer-packet.txt",
            attachmentData: attachmentData
        ).write(to: emlURL, atomically: true, encoding: .utf8)

        try emailStore.upsertEmailMessage(
            emailID: "runtime-email-1",
            accountID: account.accountID,
            mailbox: "INBOX",
            sender: "Ops <ops@runtime.test>",
            senderEmail: "ops@runtime.test",
            senderDomain: "runtime.test",
            recipients: "ada@example.com",
            subject: "Privacy review needed",
            receivedAt: now,
            emlPath: emlURL.path,
            sizeBytes: (try Data(contentsOf: emlURL)).count,
            preview: "Please review the attached customer packet before sharing.",
            contentType: "text/plain",
            isRead: false,
            isFlagged: true,
            messageIDHeader: "<runtime-email-1@runtime.test>",
            attachmentCount: 1
        )
        try emailStore.updateBodyText(
            emailID: "runtime-email-1",
            bodyText: """
            Hi Ada Example,
            Please review the attached customer packet for ada@example.com before sharing it with Codex.
            """
        )
        try emailStore.upsertEmailAttachment(
            attachmentID: "runtime-attachment-1",
            emailID: "runtime-email-1",
            filename: "customer-packet.txt",
            mimeType: "text/plain",
            sizeBytes: attachmentData.count,
            contentHash: attachmentHash
        )
        try emailStore.upsertMailboxMembership(
            accountID: account.accountID,
            mailbox: "INBOX",
            imapUID: 1,
            emailID: "runtime-email-1"
        )

        func upsertSyntheticThread(
            id: String,
            imapUID: UInt32,
            sender: String,
            senderEmail: String,
            senderDomain: String,
            subject: String,
            body: String,
            isFlagged: Bool = false
        ) throws {
            let emlURL = testHome.appendingPathComponent("mail/\(id).eml", isDirectory: false)
            try fileManager.createDirectory(at: emlURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let eml = """
            From: \(sender)
            To: runtime@manifold.test
            Subject: \(subject)
            MIME-Version: 1.0
            Content-Type: text/plain; charset="utf-8"

            \(body)
            """
            try eml.write(to: emlURL, atomically: true, encoding: .utf8)
            try emailStore.upsertEmailMessage(
                emailID: id,
                accountID: account.accountID,
                mailbox: "INBOX",
                sender: sender,
                senderEmail: senderEmail,
                senderDomain: senderDomain,
                recipients: "runtime@manifold.test",
                subject: subject,
                receivedAt: now,
                emlPath: emlURL.path,
                sizeBytes: (try Data(contentsOf: emlURL)).count,
                preview: body,
                contentType: "text/plain",
                isRead: false,
                isFlagged: isFlagged,
                messageIDHeader: "<\(id)@runtime.test>",
                attachmentCount: 0
            )
            try emailStore.updateBodyText(emailID: id, bodyText: body)
            try emailStore.upsertMailboxMembership(
                accountID: account.accountID,
                mailbox: "INBOX",
                imapUID: imapUID,
                emailID: id
            )
        }

        try upsertSyntheticThread(
            id: "runtime-email-tea-party",
            imapUID: 2,
            sender: "Model Garden <garden@openai.test>",
            senderEmail: "garden@openai.test",
            senderDomain: "openai.test",
            subject: "Model garden tea party",
            body: "EASTER_EGG_TEA_PARTY_ALLOWED OpenAI set the table with eval cupcakes.",
            isFlagged: true
        )
        try upsertSyntheticThread(
            id: "runtime-email-codex-semicolon",
            imapUID: 3,
            sender: "Codex Desk <codex@openai.test>",
            senderEmail: "codex@openai.test",
            senderDomain: "openai.test",
            subject: "Codex found the missing semicolon",
            body: "EASTER_EGG_SEMICOLON_ALLOWED The semicolon was under the test fixture."
        )
        try upsertSyntheticThread(
            id: "runtime-email-anthropic-karaoke",
            imapUID: 4,
            sender: "Claude Notes <claude@anthropic.test>",
            senderEmail: "claude@anthropic.test",
            senderDomain: "anthropic.test",
            subject: "Constitutional karaoke for deterministic tests",
            body: "EASTER_EGG_KARAOKE_ALLOWED Anthropic harmonized with the acceptance criteria."
        )
        try upsertSyntheticThread(
            id: "runtime-email-shared-lighthouse",
            imapUID: 5,
            sender: "Shared Inbox <shared@synthetic.test>",
            senderEmail: "shared@synthetic.test",
            senderDomain: "synthetic.test",
            subject: "Shared-only lighthouse",
            body: "EASTER_EGG_SHARED_ONLY_ALLOWED shared email should pass without a domain allow."
        )
        try emailStore.shareEmails(emailIDs: ["runtime-email-1"])
        try emailStore.shareEmails(emailIDs: [
            "runtime-email-1",
            "runtime-email-tea-party",
            "runtime-email-codex-semicolon",
            "runtime-email-anthropic-karaoke",
            "runtime-email-shared-lighthouse"
        ], for: .codex)

        let hasSecretRules = SmartMailboxRules(
            match: .all,
            conditions: [RuleCondition(field: "privacy_contains_secret", op: .equals, value: "true")]
        )
        try emailStore.createSmartMailbox(
            displayName: "Has Secret",
            iconName: "shield.lefthalf.filled",
            rulesJSON: hasSecretRules.toJSON() ?? "[]"
        )

        try await privacyStore.upsertSettings(
            PrivacyPreflightSettings(
                isEnabled: true,
                selectedBackend: .mlx,
                installState: .installed,
                modelVersion: "openai-privacy-filter-mlx-mxfp8",
                storagePath: privacyStorage.path,
                installedAt: now
            )
        )
        try await privacyStore.upsertPolicy(
            AgentPrivacyPolicy(agent: .cowork, textHandling: .redact, codeHandling: .ask, secretHandling: .block)
        )
        try await privacyStore.upsertPolicy(
            AgentPrivacyPolicy(agent: .codex, textHandling: .redact, codeHandling: .ask, secretHandling: .block)
        )

        let identity = PrivacyIdentityRecord(
            id: "privacy-identity-runtime-email",
            kind: .email,
            displayName: "Primary email",
            value: "ada@example.com"
        )
        let suggestion = PrivacyIdentitySuggestion(
            id: "privacy-suggestion-runtime-name",
            kind: .personName,
            displayName: "Ada Example",
            value: "Ada Example",
            sourceKind: .emailHeader,
            sourceRef: "runtime-email-1",
            confidence: 0.94
        )
        let allowEntry = PrivacyOrgAllowEntry(
            id: "privacy-allow-runtime-domain",
            kind: .senderDomain,
            pattern: "runtime.test",
            matchMode: .domainSuffix
        )
        try await privacyStore.upsertIdentity(identity)
        try await privacyStore.upsertIdentitySuggestion(suggestion)
        try await privacyStore.upsertOrgAllowEntry(allowEntry)

        let sourceContentID = "source:\(sourceID):Docs/CustomerDraft.txt"
        let emailContentID = "email:runtime-email-1:body"
        let attachmentContentID = "attachment:runtime-attachment-1"
        let unsupportedContentID = "source:\(sourceID):Docs/Archive.bin"

        try await privacyStore.upsertContentIndexRecord(
            PrivacyIndexRecord(
                id: sourceContentID,
                subjectKind: .sourceFile,
                sourceID: sourceID,
                relativePath: "Docs/CustomerDraft.txt",
                displayName: "CustomerDraft.txt",
                mimeType: "text/plain",
                extractor: "plain-text",
                extractStatus: .ready,
                scanStatus: .scanned,
                contentHash: sha256(Data(sensitiveText.utf8)),
                backend: .mlx,
                modelVersion: "openai-privacy-filter-mlx-mxfp8",
                containsSensitive: true,
                containsMyInfo: true,
                containsSecret: true,
                severity: .critical,
                matchedCategories: [.email, .address, .secret],
                matchedIdentityIDs: [identity.id],
                redactedPreview: """
                Customer outreach draft for [PERSON REDACTED]
                Email: [EMAIL REDACTED]
                Home address: [ADDRESS REDACTED]
                API key: [SECRET REDACTED]
                """,
                findingsSummary: "Contains your email, address, and a secret.",
                spanCount: 3,
                lastScannedAt: now
            )
        )
        try await privacyStore.replaceSpans(
            for: sourceContentID,
            spans: [
                PrivacySpanRecord(contentID: sourceContentID, category: .email, startUTF16: 34, endUTF16: 49, confidence: 0.98, source: .identity, placeholder: PrivacyCategory.email.replacementToken),
                PrivacySpanRecord(contentID: sourceContentID, category: .address, startUTF16: 65, endUTF16: 89, confidence: 0.91, source: .model, placeholder: PrivacyCategory.address.replacementToken),
                PrivacySpanRecord(contentID: sourceContentID, category: .secret, startUTF16: 100, endUTF16: 132, confidence: 0.99, source: .model, placeholder: PrivacyCategory.secret.replacementToken),
            ]
        )
        try await privacyStore.upsertContentIndexRecord(
            PrivacyIndexRecord(
                id: emailContentID,
                subjectKind: .emailBody,
                emailID: "runtime-email-1",
                displayName: "Privacy review needed",
                mimeType: "text/plain",
                extractor: "email-body-cache",
                extractStatus: .ready,
                scanStatus: .scanned,
                contentHash: sha256(Data("runtime-email-1".utf8)),
                backend: .mlx,
                modelVersion: "openai-privacy-filter-mlx-mxfp8",
                containsSensitive: true,
                containsMyInfo: true,
                containsThirdPartyPrivate: true,
                severity: .medium,
                matchedCategories: [.privatePerson, .email],
                matchedIdentityIDs: [identity.id],
                matchedAllowIDs: [allowEntry.id],
                redactedPreview: "Hi [PERSON REDACTED], Please review the attached customer packet for [EMAIL REDACTED] before sharing it with Codex.",
                findingsSummary: "Email body contains your name and email address.",
                spanCount: 2,
                lastScannedAt: now
            )
        )
        try await privacyStore.upsertContentIndexRecord(
            PrivacyIndexRecord(
                id: attachmentContentID,
                subjectKind: .emailAttachment,
                emailID: "runtime-email-1",
                attachmentID: "runtime-attachment-1",
                parentContentID: emailContentID,
                displayName: "customer-packet.txt",
                mimeType: "text/plain",
                extractor: "email-attachment",
                extractStatus: .ready,
                scanStatus: .scanned,
                contentHash: attachmentHash,
                backend: .mlx,
                modelVersion: "openai-privacy-filter-mlx-mxfp8",
                containsSensitive: true,
                containsSecret: true,
                severity: .critical,
                matchedCategories: [.accountNumber, .secret],
                redactedPreview: "Account number [ACCOUNT REDACTED] and secret [SECRET REDACTED]",
                findingsSummary: "Attachment contains an account number and a secret.",
                spanCount: 2,
                lastScannedAt: now
            )
        )
        try await privacyStore.upsertContentIndexRecord(
            PrivacyIndexRecord(
                id: unsupportedContentID,
                subjectKind: .sourceFile,
                sourceID: sourceID,
                relativePath: "Docs/Archive.bin",
                displayName: "Archive.bin",
                mimeType: "application/octet-stream",
                extractor: "unsupported",
                extractStatus: .unsupported,
                scanStatus: .failed,
                contentHash: sha256(Data([0, 1, 2, 3, 255, 0, 42])),
                findingsSummary: "Unsupported file type for automatic privacy extraction.",
                lastScannedAt: now,
                lastError: "Unsupported file type for automatic privacy extraction."
            )
        )

        let approvalContext = PrivacyApprovalContext(
            toolName: "read_email",
            contentKind: .email,
            inputHash: sha256(Data("privacy-approval".utf8)),
            findingsSummary: "Attachment contains an account number and a secret.",
            matchedCategories: [.accountNumber, .secret],
            redactedPreview: "Account number [ACCOUNT REDACTED] and secret [SECRET REDACTED]",
            recommendation: "Share the redacted version unless the original is required for this session."
        )
        let approvalJSON = String(data: try JSONEncoder().encode(approvalContext), encoding: .utf8)
        try db.execute(
            """
            INSERT INTO approval_requests (
                id, connection_id, agent, path, action, request_kind, source_id,
                mount_name, relative_path, context_json, requested_at, status, resolution_action
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', NULL)
            """,
            params: [
                "approval-synthetic-mcp-ui",
                "conn-runtime-ui",
                TargetApp.codex.rawValue,
                "runtime-email-1",
                "mail",
                "privacy_exposure",
                nil,
                nil,
                nil,
                approvalJSON,
                "\(Date().addingTimeInterval(-120).timeIntervalSince1970)",
            ]
        )

        try await auditStore.log(
            action: .sensitivityWarning,
            agent: TargetApp.codex.rawValue,
            filePath: "runtime-email-1",
            metadata: [
                "privacy_outcome": PrivacyOutcome.approvalRequired.rawValue,
                "privacy_summary": "Attachment contains an account number and a secret.",
                "privacy_categories": "account_number,secret",
                "privacy_backend": PrivacyBackendKind.mlx.rawValue,
                "privacy_model_version": "openai-privacy-filter-mlx-mxfp8",
                "privacy_content_kind": PrivacyContentKind.email.rawValue,
            ],
            grantID: grant.grantID
        )
    }

    private static func runtimeEML(
        subject: String,
        body: String,
        attachmentFilename: String,
        attachmentData: Data
    ) -> String {
        let boundary = "MANIFOLD-BOUNDARY-TEST"
        let attachment = attachmentData.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return """
        From: Ops <ops@runtime.test>
        To: ada@example.com
        Subject: \(subject)
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="\(boundary)"

        --\(boundary)
        Content-Type: text/plain; charset="utf-8"

        \(body)
        --\(boundary)
        Content-Type: text/plain; name="\(attachmentFilename)"
        Content-Transfer-Encoding: base64
        Content-Disposition: attachment; filename="\(attachmentFilename)"

        \(attachment)
        --\(boundary)--
        """
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum AppTestMode: Sendable {
    case live
    case fixture(AppFixtureProfile)
    case localRuntime(AppRuntimeScenario)

    static var current: AppTestMode {
        let env = ProcessInfo.processInfo.environment
        let isUITest = env["MANIFOLD_UI_TEST_MODE"] == "1"
        let isXCTestHost = env["XCTestConfigurationFilePath"] != nil
        guard isUITest || isXCTestHost || env["MANIFOLD_DISABLE_REAL_RUNTIME"] == "1" else {
            return .live
        }
        if env[AppTestEnvironment.runtimeModeKey] == "local" {
            let scenario = AppRuntimeScenario(
                rawValue: env[ManifoldRuntimeEnvironment.testScenarioKey] ?? ""
            ) ?? .syntheticMCPUI
            return .localRuntime(scenario)
        }
        let profile = AppFixtureProfile(rawValue: env["MANIFOLD_FIXTURE_PROFILE"] ?? "") ?? .baseline
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
        var privacySettings: PrivacyPreflightSettings
        var privacyRuntimes: [PrivacyRuntimeDescriptor]
        var claudePrivacyPolicy: AgentPrivacyPolicy
        var codexPrivacyPolicy: AgentPrivacyPolicy
        var privacyRuntimeStatus: PrivacyRuntimeStatus
        var privacyIdentitySuggestions: [PrivacyIdentitySuggestion]
        var privacyIdentities: [PrivacyIdentityRecord]
        var privacyOrgAllowEntries: [PrivacyOrgAllowEntry]
        var privacyIndexRecords: [PrivacyIndexRecord]
        var coverages: [AgentCoverageSnapshot]
        var coverageEvents: [CoverageEvent]
        var activeWorkBlock: WorkBlockRecord?
        var sessionAccessMode: SessionAccessMode
        var connectedAgents: [String]
        var activityEntries: [AuditEntry]
        var sessions: [Session]
        var sessionEvents: [String: [SessionEvent]]
        var ledgerEntries: [LedgerEntry]
        var ledgerVerification: LedgerVerificationResult
        var toolCostReport: ToolCostReport
        var memorySettings: MemorySettings
        var memoryItems: [MemoryItem]
        var skills: [SkillRecord]
        var execRuns: [ExecRunRecord]
        var capabilityHandles: [ValueHandle]
        var graphNodes: [KnowledgeGraphNode]
        var fabricationFindings: [FabricationFinding]
        var activeGrant: GrantRecord?
        var activeGrantSources: [GrantSourceRecord]
        var activeGrantEmailIDs: Set<String>
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
        var sharedEmailIDsByAgent: [TargetApp: Set<String>]
        var fileVisibilityOverrides: [TargetApp: [FileVisibilityOverrideRecord]]
        var rules: [RuleRecord]
        var seededRules: [RuleRecord]
    }

    private var state: FixtureState

    init(profile: AppFixtureProfile) {
        state = Self.makeState(profile: profile)
    }

    func ping() async -> RuntimePingResult {
        RuntimePingResult(ok: true, agentVersion: state.version)
    }

    func runtimeStatusSnapshot() async throws -> RuntimeStatusSnapshot {
        RuntimeStatusSnapshot(
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

    func dataControlSummary() async throws -> DataControlSummary {
        DataControlSummary(
            runtimeConnected: true,
            activeBridgeCount: state.connectedAgents.count,
            agents: TargetApp.allCases.map(summaryAgent),
            activeWorkBlock: state.activeWorkBlock,
            pendingApprovalCount: state.pendingApprovals.count,
            lastExposure: state.activityEntries.first.map(Self.summaryExposure),
            recentHandoffSessions: Array(state.sessions.prefix(5))
        )
    }

    private func summaryAgent(_ agent: TargetApp) -> DataControlSummary.Agent {
        let policy = governance(for: agent)
        let coverage = state.coverages.first { $0.agent == agent.rawValue }
        let sharedIDs = state.sharedEmailIDsByAgent[agent, default: []]
        let visibleEmailCount: Int
        if policy.isPaused {
            visibleEmailCount = 0
        } else if policy.defaultEmailPolicy == .allowUnlessBlocked {
            visibleEmailCount = state.emails.count
        } else {
            var visibleIDs = sharedIDs
            let domainAllowedIDs = state.emails.compactMap { message -> String? in
                policy.allowedEmailDomains.contains((message.senderDomain ?? "").lowercased())
                    ? message.emailID
                    : nil
            }
            visibleIDs.formUnion(domainAllowedIDs)
            visibleEmailCount = visibleIDs.count
        }

        return DataControlSummary.Agent(
            agent: agent,
            isConnected: state.connectedAgents.contains(agent.rawValue),
            verificationStatus: coverage?.verificationStatus ?? .unknown,
            coverageState: coverage?.coverageState,
            isPaused: policy.isPaused,
            defaultFileScopeCount: policy.allowedSourceIDs.count,
            visibleEmailCount: visibleEmailCount,
            sharedEmailCount: sharedIDs.count,
            emailSensitivity: policy.emailSensitivity,
            defaultEmailPolicy: policy.defaultEmailPolicy
        )
    }

    private static func summaryExposure(from entry: AuditEntry) -> DataControlSummary.Exposure {
        DataControlSummary.Exposure(
            id: entry.id,
            timestamp: entry.timestamp,
            agent: entry.agent.flatMap(TargetApp.init(rawValue:)),
            action: entry.action,
            resourcePath: entry.filePath,
            sessionID: entry.sessionID,
            grantID: entry.grantID
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

    func getPrivacySettings() async throws -> PrivacySettingsBundle {
        PrivacySettingsBundle(
            settings: state.privacySettings,
            claudePolicy: state.claudePrivacyPolicy,
            codexPolicy: state.codexPrivacyPolicy,
            runtimes: state.privacyRuntimes
        )
    }

    func updatePrivacySettings(settings: PrivacyPreflightSettings?, policy: AgentPrivacyPolicy?) async throws {
        if let settings {
            state.privacySettings = settings
        }
        if let policy {
            if policy.agent == .codex {
                state.codexPrivacyPolicy = policy
            } else {
                state.claudePrivacyPolicy = policy
            }
        }
    }

    func listPrivacyRuntimes() async throws -> [PrivacyRuntimeDescriptor] {
        state.privacyRuntimes
    }

    func installPrivacyRuntime(id: String) async throws -> PrivacyRuntimeStatus {
        state.privacySettings.isEnabled = true
        state.privacySettings.installState = .installed
        state.privacySettings.selectedBackend = .mlx
        state.privacySettings.modelVersion = "openai-privacy-filter-mlx-mxfp8"
        state.privacyRuntimes = state.privacyRuntimes.map { runtime in
            guard runtime.id == id else { return runtime }
            var updated = runtime
            updated.installedVersion = runtime.availableVersion ?? "openai-privacy-filter-mlx-mxfp8"
            updated.installState = .installed
            updated.verificationState = .checksumVerified
            updated.note = "Verified MLX MXFP8 model pack installed."
            return updated
        }
        state.privacyRuntimeStatus = PrivacyRuntimeStatus(
            featureEnabled: true,
            selectedBackend: state.privacySettings.selectedBackend,
            effectiveBackend: .mlx,
            installState: .installed,
            modelLoaded: true,
            cacheEntryCount: 3,
            lastError: nil,
            storagePath: state.privacySettings.storagePath,
            backends: state.privacyRuntimeStatus.backends,
            runtimeID: id,
            runtimeDisplayName: state.privacyRuntimes.first(where: { $0.id == id })?.displayName,
            installedVersion: state.privacyRuntimes.first(where: { $0.id == id })?.installedVersion,
            availableVersion: state.privacyRuntimes.first(where: { $0.id == id })?.availableVersion,
            verificationState: state.privacyRuntimes.first(where: { $0.id == id })?.verificationState
        )
        return state.privacyRuntimeStatus
    }

    func uninstallPrivacyRuntime(id: String) async throws -> PrivacyRuntimeStatus {
        state.privacySettings.isEnabled = false
        state.privacySettings.installState = .notInstalled
        state.privacySettings.modelVersion = nil
        state.privacyRuntimes = state.privacyRuntimes.map { runtime in
            guard runtime.id == id else { return runtime }
            var updated = runtime
            updated.installedVersion = nil
            updated.installState = .notInstalled
            updated.verificationState = .notInstalled
            updated.note = "Download required."
            return updated
        }
        state.privacyRuntimeStatus = PrivacyRuntimeStatus(
            featureEnabled: false,
            selectedBackend: state.privacySettings.selectedBackend,
            effectiveBackend: .rulesOnly,
            installState: .notInstalled,
            modelLoaded: false,
            cacheEntryCount: 0,
            lastError: nil,
            storagePath: state.privacySettings.storagePath,
            backends: state.privacyRuntimeStatus.backends,
            runtimeID: id,
            runtimeDisplayName: state.privacyRuntimes.first(where: { $0.id == id })?.displayName,
            installedVersion: nil,
            availableVersion: state.privacyRuntimes.first(where: { $0.id == id })?.availableVersion,
            verificationState: .notInstalled
        )
        return state.privacyRuntimeStatus
    }

    func privacyRuntimeStatus() async throws -> PrivacyRuntimeStatus {
        state.privacyRuntimeStatus
    }

    func clearPrivacyCache() async throws -> Int {
        let count = state.privacyRuntimeStatus.cacheEntryCount
        state.privacyRuntimeStatus = PrivacyRuntimeStatus(
            featureEnabled: state.privacyRuntimeStatus.featureEnabled,
            selectedBackend: state.privacyRuntimeStatus.selectedBackend,
            effectiveBackend: state.privacyRuntimeStatus.effectiveBackend,
            installState: state.privacyRuntimeStatus.installState,
            modelLoaded: state.privacyRuntimeStatus.modelLoaded,
            cacheEntryCount: 0,
            lastError: state.privacyRuntimeStatus.lastError,
            storagePath: state.privacyRuntimeStatus.storagePath,
            backends: state.privacyRuntimeStatus.backends,
            runtimeID: state.privacyRuntimeStatus.runtimeID,
            runtimeDisplayName: state.privacyRuntimeStatus.runtimeDisplayName,
            installedVersion: state.privacyRuntimeStatus.installedVersion,
            availableVersion: state.privacyRuntimeStatus.availableVersion,
            verificationState: state.privacyRuntimeStatus.verificationState
        )
        return count
    }

    func privacyIndexStatus() async throws -> PrivacyIndexRuntimeStatus {
        let records = filteredPrivacyIndex(scope: PrivacyIndexScope(), filter: PrivacyIndexFilter())
        return PrivacyIndexRuntimeStatus(
            enabled: state.privacySettings.isEnabled,
            queuedJobs: records.filter { $0.scanStatus == .queued }.count,
            runningJobs: records.filter { $0.scanStatus == .running }.count,
            failedJobs: records.filter { $0.scanStatus == .failed }.count,
            indexedItems: records.filter { $0.scanStatus == .scanned }.count,
            staleItems: records.filter { $0.scanStatus == .stale }.count,
            watchedSources: state.sources.filter(\.isAccessible).map(\.sourceID),
            lastError: nil
        )
    }

    func listPrivacyIndex(scope: PrivacyIndexScope, filter: PrivacyIndexFilter, limit: Int) async throws -> [PrivacyIndexRecord] {
        Array(filteredPrivacyIndex(scope: scope, filter: filter).prefix(limit))
    }

    func listPrivacyIdentitySuggestions() async throws -> [PrivacyIdentitySuggestion] {
        state.privacyIdentitySuggestions.filter { $0.status == .pending }
    }

    func acceptPrivacyIdentitySuggestion(id: String) async throws {
        guard let index = state.privacyIdentitySuggestions.firstIndex(where: { $0.id == id }) else { return }
        var suggestion = state.privacyIdentitySuggestions[index]
        suggestion.status = .accepted
        suggestion.reviewedAt = ISO8601DateFormatter.shared.string(from: Date())
        state.privacyIdentitySuggestions[index] = suggestion
        state.privacyIdentities.append(
            PrivacyIdentityRecord(
                kind: suggestion.kind,
                displayName: suggestion.displayName,
                value: suggestion.value,
                normalizedHash: suggestion.normalizedHash
            )
        )
    }

    func rejectPrivacyIdentitySuggestion(id: String) async throws {
        guard let index = state.privacyIdentitySuggestions.firstIndex(where: { $0.id == id }) else { return }
        var suggestion = state.privacyIdentitySuggestions[index]
        suggestion.status = .rejected
        suggestion.reviewedAt = ISO8601DateFormatter.shared.string(from: Date())
        state.privacyIdentitySuggestions[index] = suggestion
    }

    func upsertPrivacyIdentity(_ record: PrivacyIdentityRecord) async throws {
        if let index = state.privacyIdentities.firstIndex(where: { $0.id == record.id }) {
            state.privacyIdentities[index] = record
        } else {
            state.privacyIdentities.append(record)
        }
    }

    func upsertPrivacyOrgAllowEntry(_ entry: PrivacyOrgAllowEntry) async throws {
        if let index = state.privacyOrgAllowEntries.firstIndex(where: { $0.id == entry.id }) {
            state.privacyOrgAllowEntries[index] = entry
        } else {
            state.privacyOrgAllowEntries.append(entry)
        }
    }

    func listPrivacyIdentities() async throws -> [PrivacyIdentityRecord] { state.privacyIdentities }

    func listPrivacyOrgAllowEntries() async throws -> [PrivacyOrgAllowEntry] { state.privacyOrgAllowEntries }

    func deletePrivacyIdentity(id: String) async throws {
        state.privacyIdentities.removeAll { $0.id == id }
    }

    func deletePrivacyOrgAllowEntry(id: String) async throws {
        state.privacyOrgAllowEntries.removeAll { $0.id == id }
    }

    func rescanPrivacyContent(contentIDs: [String]) async throws {
        let rescannedAt = ISO8601DateFormatter.shared.string(from: Date())
        for contentID in contentIDs {
            guard let index = state.privacyIndexRecords.firstIndex(where: { $0.id == contentID }) else { continue }
            state.privacyIndexRecords[index].scanStatus = .scanned
            state.privacyIndexRecords[index].lastScannedAt = rescannedAt
            state.privacyIndexRecords[index].updatedAt = rescannedAt
        }
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
        ActiveGrantState(
            activeGrant: state.activeGrant,
            activeGrantSources: state.activeGrantSources,
            targetApp: targetApp.rawValue,
            selectedEmailCount: state.activeGrant?.explicitSelection == true ? state.activeGrantEmailIDs.count : state.sharedEmailIDsByAgent[targetApp, default: []].count
        )
    }

    func sessionAccessMode() async throws -> SessionAccessMode {
        state.sessionAccessMode
    }

    func setSessionAccessMode(_ mode: SessionAccessMode) async throws {
        state.sessionAccessMode = mode
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

    func startGatewaySession(targetApp: TargetApp, fileScopes: [FileSelectionScope], selectedEmailIDs: Set<String>, summaryFraming: String?, noteCaptureMode: SessionNoteCaptureMode, requestDetailLevel: AccessRecordingLevel?, memoryAccessEnabled: Bool, emailSensitivity: String?) async throws -> ActiveGrantState {
        let explicitSourceIDs = Set(fileScopes.map(\.sourceID))
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
            explicitSelection: !explicitSourceIDs.isEmpty || !selectedEmailIDs.isEmpty,
            noteCaptureMode: noteCaptureMode.rawValue,
            requestDetailLevel: requestDetailLevel?.rawValue,
            memoryAccessEnabled: memoryAccessEnabled
        )
        state.activeGrant = grant
        state.activeGrantEmailIDs = selectedEmailIDs
        state.activeGrantSources = state.sources.filter { source in
            explicitSourceIDs.isEmpty
                ? governance(for: targetApp).allowedSourceIDs.contains(source.sourceID)
                : explicitSourceIDs.contains(source.sourceID)
        }.map {
            GrantSourceRecord(grantID: grant.grantID, sourceID: $0.sourceID, mountName: $0.displayName.replacingOccurrences(of: " ", with: "-").lowercased())
        }
        state.activeWorkBlock = WorkBlockRecord(agent: targetApp, grantID: grant.grantID, sourceIDs: state.activeGrantSources.map(\.sourceID))
        state.coverages = state.coverages.map { snapshot in
            snapshot.agent == targetApp.rawValue
                ? AgentCoverageSnapshot(agent: snapshot.agent, coverageState: .manifoldRouted, verificationStatus: snapshot.verificationStatus, hostBundleIdentifier: snapshot.hostBundleIdentifier, reason: snapshot.reason)
                : snapshot
        }
        return ActiveGrantState(
            activeGrant: grant,
            activeGrantSources: state.activeGrantSources,
            targetApp: targetApp.rawValue,
            selectedEmailCount: selectedEmailIDs.isEmpty ? state.sharedEmailIDsByAgent[targetApp, default: []].count : selectedEmailIDs.count
        )
    }

    func updateGrantRequestDetailLevel(grantID: String, level: AccessRecordingLevel?) async throws -> GrantRecord {
        guard let grant = state.activeGrant, grant.grantID == grantID else {
            throw RuntimeClientStubError.unimplemented("updateGrantRequestDetailLevel")
        }
        let updated = GrantRecord(
            grantID: grant.grantID,
            targetApp: grant.targetApp,
            profileID: grant.profileID,
            status: grant.status,
            startedAt: grant.startedAt,
            endedAt: grant.endedAt,
            materializationRoot: grant.materializationRoot,
            inactivityDeadline: grant.inactivityDeadline,
            refreshOfGrantID: grant.refreshOfGrantID,
            emailSensitivity: grant.emailSensitivity,
            summaryFraming: grant.summaryFraming,
            explicitSelection: grant.explicitSelection,
            noteCaptureMode: grant.noteCaptureMode,
            requestDetailLevel: level?.rawValue,
            memoryAccessEnabled: grant.memoryAccessEnabled
        )
        state.activeGrant = updated
        return updated
    }

    func updateGrantMemoryAccess(grantID: String, enabled: Bool) async throws -> GrantRecord {
        guard let grant = state.activeGrant, grant.grantID == grantID else {
            throw RuntimeClientStubError.unimplemented("updateGrantMemoryAccess")
        }
        let updated = GrantRecord(
            grantID: grant.grantID,
            targetApp: grant.targetApp,
            profileID: grant.profileID,
            status: grant.status,
            startedAt: grant.startedAt,
            endedAt: grant.endedAt,
            materializationRoot: grant.materializationRoot,
            inactivityDeadline: grant.inactivityDeadline,
            refreshOfGrantID: grant.refreshOfGrantID,
            emailSensitivity: grant.emailSensitivity,
            summaryFraming: grant.summaryFraming,
            explicitSelection: grant.explicitSelection,
            noteCaptureMode: grant.noteCaptureMode,
            requestDetailLevel: grant.requestDetailLevel,
            memoryAccessEnabled: enabled
        )
        state.activeGrant = updated
        return updated
    }

    func endSession(grantID: String) async throws {
        state.activeWorkBlock = nil
        state.activeGrant = nil
        state.activeGrantSources = []
    }

    func restoreSnapshot(snapshotID: Int, filePath: String) async throws -> RestoreSnapshotResult {
        RestoreSnapshotResult(status: "success", message: nil)
    }
    func markWorkBlockReviewing(id: String) async throws { state.activeWorkBlock?.status = .reviewing }
    func cancelWorkBlockReview(id: String) async throws { state.activeWorkBlock?.status = .active }
    func pauseGatewaySession(id: String) async throws { state.activeWorkBlock?.status = .paused }
    func resumeGatewaySession(id: String) async throws { state.activeWorkBlock?.status = .active }

    func discardDraftWorkspace(id: String, grantID: String?, endSession: Bool) async throws {
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

    func applyDraftWorkspace(grantID: String, endSession: Bool) async throws -> ApplyWorkspaceResult {
        try await discardDraftWorkspace(id: state.activeWorkBlock?.id ?? "", grantID: grantID, endSession: endSession)
        return ApplyWorkspaceResult(
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
    func trackedFileCounts() async throws -> [String: Int] {
        Dictionary(uniqueKeysWithValues: state.trackedFiles.map { ($0, 1) })
    }
    func storageStats() async throws -> StorageStatsSnapshot { StorageStatsSnapshot(storageUsed: state.storageUsed) }
    func recentLedgerEntries(limit: Int) async throws -> [LedgerEntry] { Array(state.ledgerEntries.prefix(limit)) }
    func verifyLedger() async throws -> LedgerVerificationResult { state.ledgerVerification }
    func toolCostReport(limit: Int) async throws -> ToolCostReport {
        ToolCostReport(
            totalCalls: state.toolCostReport.totalCalls,
            totalOutputBytes: state.toolCostReport.totalOutputBytes,
            averageDurationMS: state.toolCostReport.averageDurationMS,
            callsByTool: state.toolCostReport.callsByTool,
            recent: Array(state.toolCostReport.recent.prefix(limit))
        )
    }
    func listMemory(limit: Int, includeDeleted: Bool) async throws -> [MemoryItem] {
        let items = includeDeleted
            ? state.memoryItems
            : state.memoryItems.filter { $0.status != MemoryStatus.deletedByUser.rawValue }
        return Array(items.prefix(limit))
    }
    func listMemorySources() async throws -> [MemorySourceSummary] {
        var counts: [String: (active: Int, tombstoned: Int, deleted: Int)] = [:]
        for item in state.memoryItems {
            for sourceID in item.contributingSourceIDs {
                var current = counts[sourceID, default: (0, 0, 0)]
                switch MemoryStatus(rawValue: item.status) {
                case .active:
                    current.active += 1
                case .hiddenByScope, .tombstonedByRevocation, .expiredByRetention:
                    current.tombstoned += 1
                case .deletedByUser:
                    current.deleted += 1
                case nil:
                    break
                }
                counts[sourceID] = current
            }
        }
        return counts.keys.sorted().map { sourceID in
            let count = counts[sourceID, default: (0, 0, 0)]
            return MemorySourceSummary(
                sourceID: sourceID,
                activeCount: count.active,
                tombstonedCount: count.tombstoned,
                deletedCount: count.deleted
            )
        }
    }
    func getMemorySettings() async throws -> MemorySettings {
        state.memorySettings
    }
    func updateMemorySettings(_ settings: MemorySettings) async throws -> MemorySettings {
        state.memorySettings = MemorySettings(
            settingsID: settings.settingsID,
            amnesiacMode: settings.amnesiacMode,
            derivedRetentionDays: settings.derivedRetentionDays,
            updatedAt: ISO8601DateFormatter.shared.string(from: Date())
        )
        return state.memorySettings
    }
    func forgetMemory(id: String) async throws {
        guard let index = state.memoryItems.firstIndex(where: { $0.memoryID == id }) else { return }
        let item = state.memoryItems[index]
        state.memoryItems[index] = MemoryItem(
            memoryID: item.memoryID,
            kind: MemoryKind(rawValue: item.kind) ?? .note,
            status: .deletedByUser,
            origin: MemoryOrigin(rawValue: item.origin) ?? .agentDerived,
            title: item.title,
            body: item.body,
            contributingSourceIDs: item.contributingSourceIDs,
            contributingGrantIDs: item.contributingGrantIDs,
            contributingExposureIDs: item.contributingExposureIDs,
            contributingContentHashes: item.contributingContentHashes,
            createdSessionID: item.createdSessionID,
            expiresAt: item.expiresAt,
            createdAt: item.createdAt,
            updatedAt: Date().timeIntervalSince1970
        )
        let sequence = (state.ledgerEntries.map(\.sequence).max() ?? 0) + 1
        let previousHash = state.ledgerEntries.first?.entryHash
        let entry = LedgerEntry(
            entryID: "ledger-fixture-forget-\(id)",
            sequence: sequence,
            timestamp: Date().timeIntervalSince1970,
            entryType: LedgerEntryType.memoryChange.rawValue,
            subjectTable: "memory_items",
            subjectID: id,
            previousHash: previousHash,
            payloadHash: "fixture-memory-forget-\(id)",
            entryHash: "fixture-ledger-\(sequence)",
            metadataJSON: #"{"status":"deleted_by_user"}"#
        )
        state.ledgerEntries.insert(entry, at: 0)
        state.ledgerVerification = LedgerVerificationResult(
            verified: true,
            checkedEntries: state.ledgerEntries.count,
            firstBrokenEntryID: nil,
            message: "Ledger chain verified."
        )
    }
    func listSkills(limit: Int) async throws -> [SkillRecord] {
        Array(state.skills.prefix(limit))
    }
    func recentExecRuns(limit: Int) async throws -> [ExecRunRecord] {
        Array(state.execRuns.prefix(limit))
    }
    func listCapabilityHandles(limit: Int) async throws -> [ValueHandle] {
        Array(state.capabilityHandles.prefix(limit))
    }
    func queryGraphNodes(query: String, limit: Int) async throws -> [KnowledgeGraphNode] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let nodes = trimmed.isEmpty
            ? state.graphNodes
            : state.graphNodes.filter {
                $0.label.localizedCaseInsensitiveContains(trimmed)
                    || $0.kind.localizedCaseInsensitiveContains(trimmed)
            }
        return Array(nodes.prefix(limit))
    }
    func recentFabricationFindings(limit: Int) async throws -> [FabricationFinding] {
        Array(state.fabricationFindings.prefix(limit))
    }
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
    func sharedEmailCount(agent: TargetApp) async throws -> Int {
        state.sharedEmailIDsByAgent[agent, default: []].count
    }

    func sharedEmailIDs(agent: TargetApp) async throws -> Set<String> {
        state.sharedEmailIDsByAgent[agent, default: []]
    }

    func sharedEmails(agent: TargetApp, limit: Int = 500) async throws -> [EmailMessageRecord] {
        let shared = state.sharedEmailIDsByAgent[agent, default: []]
        return Array(state.emails.filter { shared.contains($0.emailID) }.prefix(limit))
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
    func shareEmails(emailIDs: [String], for agent: TargetApp) async throws {
        for emailID in emailIDs {
            state.sharedEmailIDsByAgent[agent, default: []].insert(emailID)
        }
    }
    func unshareEmails(emailIDs: [String], for agent: TargetApp) async throws {
        for emailID in emailIDs {
            state.sharedEmailIDsByAgent[agent, default: []].remove(emailID)
        }
    }
    func unshareAllEmails() async throws {
        state.sharedEmailIDsByAgent.removeAll()
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

    func listRules(scope: RuleScope?) async throws -> [RuleRecord] {
        let sortedRules = state.rules.sorted { lhs, rhs in
            if lhs.scope != rhs.scope { return lhs.scope.rawValue < rhs.scope.rawValue }
            if lhs.source.groupPriority != rhs.source.groupPriority {
                return lhs.source.groupPriority < rhs.source.groupPriority
            }
            if lhs.orderIndex != rhs.orderIndex { return lhs.orderIndex < rhs.orderIndex }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        guard let scope else { return sortedRules }
        return sortedRules.filter { $0.scope == scope }
    }

    func upsertRule(_ rule: RuleRecord) async throws {
        if let index = state.rules.firstIndex(where: { $0.id == rule.id }) {
            state.rules[index] = rule
        } else {
            state.rules.append(rule)
        }
    }

    func deleteRule(id: String) async throws {
        state.rules.removeAll { $0.id == id }
    }

    func setRuleEnabled(id: String, enabled: Bool) async throws {
        guard let index = state.rules.firstIndex(where: { $0.id == id }) else { return }
        state.rules[index].enabled = enabled
    }

    func reorderRules(scope: RuleScope, ids: [String]) async throws {
        let ordered = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        for index in state.rules.indices where state.rules[index].scope == scope {
            state.rules[index].orderIndex = ordered[state.rules[index].id] ?? state.rules[index].orderIndex
        }
    }

    func resetSeededRules() async throws {
        let seededIDs = Set(state.seededRules.map(\.id))
        state.rules.removeAll { seededIDs.contains($0.id) }
        state.rules.append(contentsOf: state.seededRules)
    }

    func previewRuleMatches(rule: RuleRecord, agent: TargetApp) async throws -> RuleMatchPreview {
        RuleMatchPreview(
            ruleID: rule.id,
            fileMatches: rule.scope == .file ? 1 : 0,
            emailMatches: rule.scope == .email ? 1 : 0,
            agentMatches: rule.scope == .agent ? 1 : 0,
            sample: [
                .init(
                    identifier: rule.scope == .email ? "runtime-email-1" : "Docs/CustomerDraft.txt",
                    label: rule.scope == .email ? "Privacy review needed" : "Docs/CustomerDraft.txt"
                )
            ]
        )
    }

    private func filteredPrivacyIndex(
        scope: PrivacyIndexScope,
        filter: PrivacyIndexFilter
    ) -> [PrivacyIndexRecord] {
        state.privacyIndexRecords.filter { record in
            if let subjectKinds = scope.subjectKinds, !subjectKinds.contains(record.subjectKind) {
                return false
            }
            if let sourceID = scope.sourceID, record.sourceID != sourceID {
                return false
            }
            if let emailID = scope.emailID, record.emailID != emailID {
                return false
            }
            if let attachmentID = scope.attachmentID, record.attachmentID != attachmentID {
                return false
            }

            if let containsSensitive = filter.containsSensitive, record.containsSensitive != containsSensitive {
                return false
            }
            if let containsMyInfo = filter.containsMyInfo, record.containsMyInfo != containsMyInfo {
                return false
            }
            if let containsSecret = filter.containsSecret, record.containsSecret != containsSecret {
                return false
            }
            if let containsThirdPartyPrivate = filter.containsThirdPartyPrivate,
               record.containsThirdPartyPrivate != containsThirdPartyPrivate {
                return false
            }
            if let containsOrgOnly = filter.containsOrgOnly, record.containsOrgOnly != containsOrgOnly {
                return false
            }
            if let severity = filter.severity, record.severity != severity {
                return false
            }
            if let categories = filter.categories, !Set(categories).isSubset(of: Set(record.matchedCategories)) {
                return false
            }
            return true
        }
        .sorted { lhs, rhs in
            (lhs.lastScannedAt ?? lhs.updatedAt) > (rhs.lastScannedAt ?? rhs.updatedAt)
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

    private static func fixtureSourceRoots() -> (shared: URL, claudeOnly: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-fixture-sources", isDirectory: true)
            .appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString, isDirectory: true)
        let root = base.appendingPathComponent("sources", isDirectory: true)
        return (
            shared: root.appendingPathComponent("Shared", isDirectory: true),
            claudeOnly: root.appendingPathComponent("Claude Only", isDirectory: true)
        )
    }

    private static func seedFixtureSourceFiles(shared: URL, claudeOnly: URL) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: shared, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: claudeOnly, withIntermediateDirectories: true)
            try fileManager.createDirectory(
                at: shared.appendingPathComponent("Docs", isDirectory: true),
                withIntermediateDirectories: true
            )

            try "Initial shared worklog\n".write(
                to: shared.appendingPathComponent("worklog.md"),
                atomically: true,
                encoding: .utf8
            )
            try "Release notes fixture\n".write(
                to: shared.appendingPathComponent("Docs/ReleaseNotes.md"),
                atomically: true,
                encoding: .utf8
            )
            try Data([0, 1, 2, 3, 255]).write(
                to: shared.appendingPathComponent("archive.bin")
            )
            try "CLAUDE_ONLY_MARKER\n".write(
                to: claudeOnly.appendingPathComponent("marker.txt"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            // Fixture files are only needed for UI tests. Keep the runtime usable
            // even if a local temp directory disappears between launches.
        }
    }

    private static func makeState(profile: AppFixtureProfile) -> FixtureState {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        let isSyntheticMCPUI = profile == .syntheticMCPUI
        let isPrivacyProfile = profile == .privacy || isSyntheticMCPUI
        let isTrackedProfile = profile == .trackedWork || isPrivacyProfile
        let privacyEmailID = isSyntheticMCPUI ? "runtime-email-1" : "email-4"
        let privacyEmailSubject = isSyntheticMCPUI ? "Privacy review needed" : "Operator smoke test"
        let privacyEmailPreview = isSyntheticMCPUI
            ? "Please review the attached customer packet before sharing."
            : "Quick operator-style tooling smoke test for fixture mode."
        let privacyEmailBody = isSyntheticMCPUI
            ? "Hi Ada Example,\nPlease review the attached customer packet for ada@example.com before sharing it with Codex."
            : "Quick operator-style tooling smoke test for fixture mode."
        let roots = fixtureSourceRoots()
        if profile != .onboarding {
            seedFixtureSourceFiles(shared: roots.shared, claudeOnly: roots.claudeOnly)
        }
        let sourceA = SourceRecord(sourceID: "src-shared", displayName: "Shared", originalRootPath: roots.shared.path, status: "idle", createdAt: now, updatedAt: now)
        let sourceB = SourceRecord(sourceID: "src-claude", displayName: "Claude Only", originalRootPath: roots.claudeOnly.path, status: "idle", createdAt: now, updatedAt: now)
        let claudePolicy = AgentAccessPolicy(agent: .cowork, allowedSourceIDs: ["src-shared", "src-claude"], allowedEmailDomains: ["anthropic.test"], emailSensitivity: .moderate, defaultEmailPolicy: .allowUnlessBlocked, accessRecordingLevel: .summary, isPaused: false)
        let codexPolicy = AgentAccessPolicy(agent: .codex, allowedSourceIDs: ["src-shared"], allowedEmailDomains: [], emailSensitivity: .strict, defaultEmailPolicy: .blockUnlessAllowed, accessRecordingLevel: .detailed, isPaused: false)
        let claudeRules = EmailRuleSet(
            agent: .cowork,
            domainRules: [EmailDomainRule(agent: .cowork, domain: "anthropic.test", action: .allow)],
            contactRules: [EmailContactRule(agent: .cowork, name: "Daniela Amodei", email: "daniela@anthropic.test", action: .block)],
            keywordRules: [EmailKeywordRule(agent: .cowork, pattern: "constitution", matchLocation: .subjectAndBody, action: .block, isRegex: false)],
            defaultPolicy: .allowUnlessBlocked,
            emailSensitivity: .moderate
        )
        let codexRules = EmailRuleSet(
            agent: .codex,
            domainRules: [EmailDomainRule(agent: .codex, domain: "openai.test", action: .allow)],
            contactRules: [],
            keywordRules: [EmailKeywordRule(agent: .codex, pattern: "operator", matchLocation: .subject, action: .block, isRegex: false)],
            defaultPolicy: .blockUnlessAllowed,
            emailSensitivity: .strict
        )
        let claudeGovernance = AgentEmailGovernanceSummary(agent: .cowork, enabledShieldCount: claudeRules.shields.filter(\.isEnabled).count, domainRuleCount: claudeRules.domainRules.count, contactRuleCount: claudeRules.contactRules.count, keywordRuleCount: claudeRules.keywordRules.count, defaultPolicy: claudeRules.defaultPolicy, emailSensitivity: claudeRules.emailSensitivity)
        let codexGovernance = AgentEmailGovernanceSummary(agent: .codex, enabledShieldCount: codexRules.shields.filter(\.isEnabled).count, domainRuleCount: codexRules.domainRules.count, contactRuleCount: codexRules.contactRules.count, keywordRuleCount: codexRules.keywordRules.count, defaultPolicy: codexRules.defaultPolicy, emailSensitivity: codexRules.emailSensitivity)
        let coverages = [
            AgentCoverageSnapshot(agent: TargetApp.cowork.rawValue, coverageState: .manifoldRouted, verificationStatus: .verified, hostBundleIdentifier: "com.anthropic.claudefordesktop", reason: "Fixture verified"),
            AgentCoverageSnapshot(agent: TargetApp.codex.rawValue, coverageState: isTrackedProfile ? .trackedWorkspace : .manifoldRouted, verificationStatus: .verified, hostBundleIdentifier: "com.openai.codex", reason: "Fixture verified"),
        ]
        let coverageEvents = [
            CoverageEvent(id: "coverage-1", agent: TargetApp.codex.rawValue, coverageState: .outsideCoverage, eventType: "drift", message: "Original file changed outside the tracked workflow.", resourcePath: "shared/worklog.md", timestamp: now, metadata: nil),
        ]
        let privacyActivityEntry = AuditEntry(
            id: 3,
            timestamp: now,
            agent: TargetApp.codex.rawValue,
            action: AuditAction.sensitivityWarning.rawValue,
            filePath: privacyEmailID,
            metadata: #"{"privacy_outcome":"approval_required","privacy_summary":"Contains sensitive account context before sharing.","privacy_categories":"email,secret","privacy_backend":"mlx","privacy_model_version":"openai-privacy-filter-mlx-mxfp8","privacy_content_kind":"email"}"#,
            sessionID: "session-2",
            grantID: "grant-fixture"
        )
        let activity = [
            AuditEntry(id: 1, timestamp: now, agent: TargetApp.cowork.rawValue, action: AuditAction.fileRead.rawValue, filePath: "claude-only/marker.txt", metadata: "{}", sessionID: "session-1", grantID: nil),
            AuditEntry(id: 2, timestamp: now, agent: TargetApp.codex.rawValue, action: AuditAction.contentDrift.rawValue, filePath: "shared/worklog.md", metadata: "{\"coverage_state\":\"outside_coverage\"}", sessionID: "session-2", grantID: "grant-fixture"),
        ] + (isTrackedProfile ? [privacyActivityEntry] : [])
        let sessions = [
            Session(id: "session-1", agent: TargetApp.cowork.rawValue, startTime: now, endTime: now, actionCount: 4, readCount: 3, writeCount: 0, searchCount: 1),
        ]
        let sessionEvents = [
            "session-1": [
                SessionEvent(id: 1, timestamp: now, action: AuditAction.fileRead.rawValue, agent: TargetApp.cowork.rawValue, filePath: "shared/worklog.md", metadata: "{}"),
            ]
        ]
        let pendingApprovals = isTrackedProfile ? [
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
        ] + (isPrivacyProfile ? [
            PendingApprovalRecord(
                id: isSyntheticMCPUI ? "approval-synthetic-mcp-ui" : "approval-privacy-1",
                connectionID: "conn-fixture",
                agent: TargetApp.codex.rawValue,
                path: privacyEmailID,
                action: "mail",
                kind: "privacy_exposure",
                contextJSON: #"{"toolName":"read_email","contentKind":"email","inputHash":"fixture-privacy-hash","findingsSummary":"Contains sensitive account context before sharing.","matchedCategories":["email","secret"],"redactedPreview":"Please review the attached customer packet for [EMAIL REDACTED] before sharing it with Codex.","recommendation":"Share the redacted version unless the original is required for this session."}"#,
                requestedAt: Date().addingTimeInterval(-180).timeIntervalSince1970,
                status: "pending"
            )
        ] : []) : []
        let boardRootDate = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(-21_600))
        let boardReplyDate = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(-7_200))
        let boardLatestDate = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(-1_200))
        let teaPartyDate = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(-1_000))
        let semicolonDate = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(-900))
        let karaokeDate = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(-800))
        let lighthouseDate = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(-700))
        let digestDate = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(-86_400))
        let archiveDate = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(-172_800))
        let syntheticEasterEggEmails = isSyntheticMCPUI ? [
            EmailMessageRecord(
                emailID: "runtime-email-tea-party",
                accountID: "account-1",
                mailbox: "INBOX",
                sender: "Model Garden <garden@openai.test>",
                senderEmail: "garden@openai.test",
                senderDomain: "openai.test",
                recipients: "policy@manifold.test",
                subject: "Model garden tea party",
                receivedAt: teaPartyDate,
                sizeBytes: 1_420,
                preview: "EASTER_EGG_TEA_PARTY_ALLOWED OpenAI set the table with eval cupcakes.",
                isRead: false,
                isFlagged: true,
                messageIDHeader: "<runtime-email-tea-party@runtime.test>",
                bodyText: "EASTER_EGG_TEA_PARTY_ALLOWED OpenAI set the table with eval cupcakes."
            ),
            EmailMessageRecord(
                emailID: "runtime-email-codex-semicolon",
                accountID: "account-1",
                mailbox: "INBOX",
                sender: "Codex Desk <codex@openai.test>",
                senderEmail: "codex@openai.test",
                senderDomain: "openai.test",
                recipients: "policy@manifold.test",
                subject: "Codex found the missing semicolon",
                receivedAt: semicolonDate,
                sizeBytes: 1_260,
                preview: "EASTER_EGG_SEMICOLON_ALLOWED The semicolon was under the test fixture.",
                isRead: false,
                messageIDHeader: "<runtime-email-codex-semicolon@runtime.test>",
                bodyText: "EASTER_EGG_SEMICOLON_ALLOWED The semicolon was under the test fixture."
            ),
            EmailMessageRecord(
                emailID: "runtime-email-anthropic-karaoke",
                accountID: "account-1",
                mailbox: "INBOX",
                sender: "Claude Notes <claude@anthropic.test>",
                senderEmail: "claude@anthropic.test",
                senderDomain: "anthropic.test",
                recipients: "policy@manifold.test",
                subject: "Constitutional karaoke for deterministic tests",
                receivedAt: karaokeDate,
                sizeBytes: 1_330,
                preview: "EASTER_EGG_KARAOKE_ALLOWED Anthropic harmonized with the acceptance criteria.",
                isRead: false,
                messageIDHeader: "<runtime-email-anthropic-karaoke@runtime.test>",
                bodyText: "EASTER_EGG_KARAOKE_ALLOWED Anthropic harmonized with the acceptance criteria."
            ),
            EmailMessageRecord(
                emailID: "runtime-email-shared-lighthouse",
                accountID: "account-1",
                mailbox: "INBOX",
                sender: "Shared Inbox <shared@synthetic.test>",
                senderEmail: "shared@synthetic.test",
                senderDomain: "synthetic.test",
                recipients: "policy@manifold.test",
                subject: "Shared-only lighthouse",
                receivedAt: lighthouseDate,
                sizeBytes: 1_180,
                preview: "EASTER_EGG_SHARED_ONLY_ALLOWED shared email should pass without a domain allow.",
                isRead: false,
                messageIDHeader: "<runtime-email-shared-lighthouse@runtime.test>",
                bodyText: "EASTER_EGG_SHARED_ONLY_ALLOWED shared email should pass without a domain allow."
            ),
        ] : []
        let emails = [
            EmailMessageRecord(
                emailID: "email-1",
                accountID: "account-1",
                mailbox: "INBOX",
                sender: "Dario Amodei <dario@anthropic.test>",
                senderEmail: "dario@anthropic.test",
                senderDomain: "anthropic.test",
                recipients: "policy@manifold.test",
                subject: "Frontier safety sync",
                receivedAt: boardRootDate,
                sizeBytes: 3_200,
                preview: "First pass on the frontier safety sync deck for Thursday.",
                isRead: false,
                isFlagged: true,
                messageIDHeader: "<thread-frontier-sync@anthropic.test>",
                attachmentCount: 1,
                bodyText: "First pass on the frontier safety sync deck for Thursday."
            ),
            EmailMessageRecord(
                emailID: "email-2",
                accountID: "account-1",
                mailbox: "INBOX",
                sender: "Mark Chen <mark@openai.test>",
                senderEmail: "mark@openai.test",
                senderDomain: "openai.test",
                recipients: "policy@manifold.test",
                subject: "Re: Frontier safety sync",
                receivedAt: boardReplyDate,
                sizeBytes: 2_900,
                preview: "Added eval notes and trimmed the appendix.",
                isRead: true,
                inReplyTo: "<thread-frontier-sync@anthropic.test>",
                referencesHeader: "<thread-frontier-sync@anthropic.test>",
                messageIDHeader: "<thread-frontier-sync-reply@openai.test>",
                bodyText: "Added eval notes and trimmed the appendix."
            ),
            EmailMessageRecord(
                emailID: "email-3",
                accountID: "account-1",
                mailbox: "INBOX",
                sender: "Daniela Amodei <daniela@anthropic.test>",
                senderEmail: "daniela@anthropic.test",
                senderDomain: "anthropic.test",
                recipients: "policy@manifold.test",
                subject: "Re: Frontier safety sync",
                receivedAt: boardLatestDate,
                sizeBytes: 2_600,
                preview: "Latest benchmark numbers are in. This should be the final version.",
                isRead: true,
                inReplyTo: "<thread-frontier-sync-reply@openai.test>",
                referencesHeader: "<thread-frontier-sync@anthropic.test> <thread-frontier-sync-reply@openai.test>",
                messageIDHeader: "<thread-frontier-sync-final@anthropic.test>",
                attachmentCount: 1,
                bodyText: "Latest benchmark numbers are in. This should be the final version."
            ),
            EmailMessageRecord(
                emailID: privacyEmailID,
                accountID: "account-1",
                mailbox: "INBOX",
                sender: "Greg Brockman <greg@openai.test>",
                senderEmail: "greg@openai.test",
                senderDomain: "openai.test",
                recipients: "policy@manifold.test",
                subject: privacyEmailSubject,
                receivedAt: digestDate,
                sizeBytes: 1_200,
                preview: privacyEmailPreview,
                isRead: false,
                messageIDHeader: "<operator-smoke-test@openai.test>",
                attachmentCount: 2,
                bodyText: privacyEmailBody
            ),
            EmailMessageRecord(
                emailID: "email-5",
                accountID: "account-1",
                mailbox: "Archive",
                sender: "Fidji Simo <fidji@openai.test>",
                senderEmail: "fidji@openai.test",
                senderDomain: "openai.test",
                recipients: "policy@manifold.test",
                subject: "Quarterly governance review",
                receivedAt: archiveDate,
                sizeBytes: 2_100,
                preview: "Archived governance review summary with the approved checklist.",
                isRead: true,
                messageIDHeader: "<governance-review@openai.test>",
                bodyText: "Archived governance review summary with the approved checklist."
            ),
        ] + syntheticEasterEggEmails
        let codexSharedEmailIDs: Set<String> = isSyntheticMCPUI
            ? [
                privacyEmailID,
                "runtime-email-tea-party",
                "runtime-email-codex-semicolon",
                "runtime-email-anthropic-karaoke",
                "runtime-email-shared-lighthouse",
            ]
            : [privacyEmailID]
        let inboxMessageCount = emails.filter { $0.mailbox == "INBOX" }.count
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
        let hasActiveFixtureSession = isTrackedProfile
        let activeGrant: GrantRecord? = hasActiveFixtureSession ? GrantRecord(
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
        let activeGrantSources = hasActiveFixtureSession ? [GrantSourceRecord(grantID: "grant-fixture", sourceID: "src-shared", mountName: "shared")] : []
        let activeWorkBlock = hasActiveFixtureSession ? WorkBlockRecord(id: "wb-fixture", agent: .codex, grantID: "grant-fixture", sourceIDs: ["src-shared"], startedAt: now, status: .active, modifiedFileCount: 1, newFileCount: 0) : nil
        let privacySettings = PrivacyPreflightSettings(
            isEnabled: profile != .onboarding,
            selectedBackend: .mlx,
            installState: profile == .onboarding ? .notInstalled : .installed,
            modelVersion: profile == .onboarding ? nil : "openai-privacy-filter-mlx-mxfp8",
            storagePath: "/Users/test/Library/Application Support/Manifold/privacy",
            installedAt: profile == .onboarding ? nil : now
        )
        let privacyRuntimes = [
            PrivacyRuntimeDescriptor(
                id: "openai-privacy-filter-mlx-mxfp8",
                displayName: "Fast Local Scanner",
                publisher: "MLX Community / OpenAI",
                installedVersion: profile == .onboarding ? nil : "openai-privacy-filter-mlx-mxfp8",
                availableVersion: "openai-privacy-filter-mlx-mxfp8",
                sizeBytes: 1_473_063_803,
                installState: privacySettings.installState,
                verificationState: profile == .onboarding ? .notInstalled : .checksumVerified,
                sourceRepository: "https://huggingface.co/mlx-community/openai-privacy-filter-mxfp8",
                note: profile == .onboarding ? "Download required." : "Verified MLX MXFP8 model pack installed."
            )
        ]
        let claudePrivacyPolicy = AgentPrivacyPolicy(agent: .cowork, textHandling: .redact, codeHandling: .ask, secretHandling: .block)
        let codexPrivacyPolicy = AgentPrivacyPolicy(agent: .codex, textHandling: .redact, codeHandling: .ask, secretHandling: .block)
        let privacyRuntimeStatus = PrivacyRuntimeStatus(
            featureEnabled: privacySettings.isEnabled,
            selectedBackend: .mlx,
            effectiveBackend: profile == .onboarding ? .rulesOnly : .mlx,
            installState: privacySettings.installState,
            modelLoaded: privacySettings.isEnabled,
            cacheEntryCount: profile == .onboarding ? 0 : 3,
            lastError: nil,
            storagePath: privacySettings.storagePath,
            backends: [
                PrivacyBackendStatus(kind: .rulesOnly, available: true, installed: privacySettings.installState == .installed, note: "Fast local heuristics."),
                PrivacyBackendStatus(kind: .mlx, available: privacySettings.installState == .installed, installed: privacySettings.installState == .installed, note: "MLX MXFP8 model pack."),
            ],
            runtimeID: "openai-privacy-filter-mlx-mxfp8",
            runtimeDisplayName: "Fast Local Scanner",
            installedVersion: privacyRuntimes[0].installedVersion,
            availableVersion: privacyRuntimes[0].availableVersion,
            verificationState: privacyRuntimes[0].verificationState
        )
        let privacyIdentities = [
            PrivacyIdentityRecord(
                id: "identity-primary-email",
                kind: .email,
                displayName: "Primary email",
                value: "ada@example.com"
            ),
            PrivacyIdentityRecord(
                id: "identity-home-address",
                kind: .address,
                displayName: "Home address",
                value: "123 Market Street, London"
            ),
        ]
        let privacyIdentitySuggestions = [
            PrivacyIdentitySuggestion(
                id: isSyntheticMCPUI ? "privacy-suggestion-runtime-name" : "suggestion-primary-name",
                kind: .personName,
                displayName: "Ada Example",
                value: "Ada Example",
                sourceKind: .emailHeader,
                sourceRef: privacyEmailID,
                confidence: 0.92
            )
        ]
        let privacyOrgAllowEntries = [
            PrivacyOrgAllowEntry(
                id: "allow-openai-test",
                kind: .senderDomain,
                pattern: "openai.test",
                matchMode: .domainSuffix
            )
        ]
        let privacyIndexRecords = [
            PrivacyIndexRecord(
                id: "email:\(privacyEmailID):body",
                subjectKind: .emailBody,
                emailID: privacyEmailID,
                displayName: privacyEmailSubject,
                mimeType: "text/plain",
                extractor: "email-body-cache",
                extractStatus: .ready,
                scanStatus: .scanned,
                backend: .mlx,
                modelVersion: "openai-privacy-filter-mlx-mxfp8",
                containsSensitive: true,
                containsMyInfo: true,
                containsThirdPartyPrivate: true,
                severity: .critical,
                matchedCategories: [.privatePerson, .email, .secret],
                matchedIdentityIDs: ["identity-primary-email"],
                matchedAllowIDs: ["allow-openai-test"],
                redactedPreview: isSyntheticMCPUI
                    ? "Please review the attached customer packet for [EMAIL REDACTED] before sharing it with Codex."
                    : "Quick operator-style tooling smoke test for [EMAIL REDACTED]. Secret: [SECRET REDACTED].",
                findingsSummary: isSyntheticMCPUI
                    ? "Email body contains your name and email address."
                    : "Contains your email plus a secret token.",
                spanCount: 3,
                lastScannedAt: now
            ),
            PrivacyIndexRecord(
                id: "source:src-shared:worklog.md",
                subjectKind: .sourceFile,
                sourceID: "src-shared",
                relativePath: "worklog.md",
                displayName: "worklog.md",
                mimeType: "text/plain",
                extractor: "plain-text",
                extractStatus: .ready,
                scanStatus: .stale,
                backend: .mlx,
                modelVersion: "openai-privacy-filter-mlx-mxfp8",
                containsSensitive: true,
                containsMyInfo: true,
                severity: .medium,
                matchedCategories: [.email],
                matchedIdentityIDs: ["identity-primary-email"],
                redactedPreview: "Contact [EMAIL REDACTED] before sending the memo.",
                findingsSummary: "Contains your email address.",
                spanCount: 1,
                lastScannedAt: now
            ),
            PrivacyIndexRecord(
                id: "source:src-shared:archive.bin",
                subjectKind: .sourceFile,
                sourceID: "src-shared",
                relativePath: "archive.bin",
                displayName: "archive.bin",
                mimeType: "application/octet-stream",
                extractor: "unsupported",
                extractStatus: .unsupported,
                scanStatus: .failed,
                findingsSummary: "Unsupported file type for automatic privacy extraction.",
                lastScannedAt: now,
                lastError: "Unsupported file type for automatic privacy extraction."
            ),
        ]
        let seededRules = [
            RuleRecord(
                id: "rule-seeded-secret",
                name: "Protect Secrets",
                explanation: "Deny detected secrets before sharing.",
                scope: .file,
                matcher: .privacyContainsCategory(.secret),
                action: .deny,
                agents: [],
                window: .always,
                source: .seeded,
                enabled: true,
                orderIndex: 0,
                createdAt: now,
                updatedAt: now
            )
        ]
        let rules = seededRules + [
            RuleRecord(
                id: "rule-email-openai",
                name: "Allow OpenAI mail",
                explanation: "Keep routine OpenAI digests visible.",
                scope: .email,
                matcher: .emailDomain("openai.test"),
                action: .allow,
                agents: [.codex],
                window: .always,
                source: .user,
                enabled: true,
                orderIndex: 1,
                createdAt: now,
                updatedAt: now
            )
        ]
        let nowSeconds = Date().timeIntervalSince1970
        let memorySettings = MemorySettings(
            amnesiacMode: false,
            derivedRetentionDays: 90,
            updatedAt: now
        )
        let memoryItems = profile == .onboarding ? [] : [
            MemoryItem(
                memoryID: "mem-fixture-invoice-schema",
                kind: .sourceSchema,
                title: "Shared folder schema",
                body: "Docs contain release notes, worklog summaries, and redacted customer review packets.",
                contributingSourceIDs: ["src-shared"],
                contributingGrantIDs: ["grant-fixture"],
                contributingExposureIDs: ["exposure-fixture-worklog"],
                contributingContentHashes: ["hash-fixture-worklog"],
                createdSessionID: "session-2",
                createdAt: nowSeconds - 3_600,
                updatedAt: nowSeconds - 600
            ),
            MemoryItem(
                memoryID: "mem-fixture-review-routine",
                kind: .routine,
                title: "Review routine",
                body: "Start with search_structured, compare against prior context, then read only the cited range before answering.",
                contributingSourceIDs: ["src-shared"],
                contributingGrantIDs: ["grant-fixture"],
                contributingExposureIDs: ["exposure-fixture-search"],
                contributingContentHashes: ["hash-fixture-search"],
                createdSessionID: "session-2",
                createdAt: nowSeconds - 2_400,
                updatedAt: nowSeconds - 300
            ),
            MemoryItem(
                memoryID: "mem-fixture-claude-only",
                kind: .summary,
                status: .hiddenByScope,
                title: "Claude-only marker",
                body: "Hidden in this session because the active Codex grant does not include the Claude Only source.",
                contributingSourceIDs: ["src-claude"],
                contributingGrantIDs: ["grant-claude-previous"],
                contributingExposureIDs: ["exposure-fixture-claude"],
                contributingContentHashes: ["hash-fixture-claude"],
                createdSessionID: "session-1",
                createdAt: nowSeconds - 86_400,
                updatedAt: nowSeconds - 86_000
            ),
        ]
        let toolMetrics = profile == .onboarding ? [] : [
            ToolCallMetric(
                metricID: "metric-fixture-search",
                connectionID: "conn-fixture",
                agent: TargetApp.codex.rawValue,
                toolName: "search_structured",
                durationMS: 42.5,
                outputBytes: 2_048,
                truncated: false,
                isError: false,
                exposureID: "exposure-fixture-search",
                grantID: "grant-fixture",
                sessionID: "session-2",
                timestamp: nowSeconds - 180
            ),
            ToolCallMetric(
                metricID: "metric-fixture-read",
                connectionID: "conn-fixture",
                agent: TargetApp.codex.rawValue,
                toolName: "read_range",
                durationMS: 31.2,
                outputBytes: 1_224,
                truncated: false,
                isError: false,
                exposureID: "exposure-fixture-worklog",
                grantID: "grant-fixture",
                sessionID: "session-2",
                timestamp: nowSeconds - 120
            ),
        ]
        let toolCostReport = ToolCostReport(
            totalCalls: toolMetrics.count,
            totalOutputBytes: toolMetrics.reduce(0) { $0 + $1.outputBytes },
            averageDurationMS: toolMetrics.isEmpty ? 0 : toolMetrics.reduce(0.0) { $0 + $1.durationMS } / Double(toolMetrics.count),
            callsByTool: toolMetrics.reduce(into: [String: Int]()) { counts, metric in
                counts[metric.toolName, default: 0] += 1
            },
            recent: toolMetrics.sorted { $0.timestamp > $1.timestamp }
        )
        let ledgerEntries = profile == .onboarding ? [] : [
            LedgerEntry(
                entryID: "ledger-fixture-6",
                sequence: 6,
                timestamp: nowSeconds - 90,
                entryType: LedgerEntryType.memoryItem.rawValue,
                subjectTable: "memory_items",
                subjectID: "mem-fixture-review-routine",
                previousHash: "fixture-ledger-5",
                payloadHash: "fixture-payload-6",
                entryHash: "fixture-ledger-6",
                metadataJSON: #"{"kind":"routine"}"#
            ),
            LedgerEntry(
                entryID: "ledger-fixture-5",
                sequence: 5,
                timestamp: nowSeconds - 120,
                entryType: LedgerEntryType.toolMetric.rawValue,
                subjectTable: "tool_call_metrics",
                subjectID: "metric-fixture-read",
                previousHash: "fixture-ledger-4",
                payloadHash: "fixture-payload-5",
                entryHash: "fixture-ledger-5",
                metadataJSON: #"{"tool":"read_range"}"#
            ),
            LedgerEntry(
                entryID: "ledger-fixture-4",
                sequence: 4,
                timestamp: nowSeconds - 180,
                entryType: LedgerEntryType.exposure.rawValue,
                subjectTable: "exposure_records",
                subjectID: "exposure-fixture-search",
                previousHash: "fixture-ledger-3",
                payloadHash: "fixture-payload-4",
                entryHash: "fixture-ledger-4",
                metadataJSON: #"{"contentHash":"hash-fixture-search"}"#
            ),
            LedgerEntry(
                entryID: "ledger-fixture-3",
                sequence: 3,
                timestamp: nowSeconds - 240,
                entryType: LedgerEntryType.accessDecision.rawValue,
                subjectTable: "access_decisions",
                subjectID: "decision-fixture-src-shared",
                previousHash: "fixture-ledger-2",
                payloadHash: "fixture-payload-3",
                entryHash: "fixture-ledger-3",
                metadataJSON: #"{"grantID":"grant-fixture"}"#
            ),
        ]
        let ledgerVerification = LedgerVerificationResult(
            verified: true,
            checkedEntries: ledgerEntries.count,
            firstBrokenEntryID: nil,
            message: ledgerEntries.isEmpty ? "Ledger is empty." : "Ledger chain verified."
        )
        let skills = profile == .onboarding ? [] : [
            SkillRecord(
                skillID: "skill-fixture-recall-routine",
                name: "Recall review routine",
                manifestHash: "fixture-skill-review-routine-hash",
                manifestJSON: #"{"steps":[{"op":"recall_memory","query":"routine","limit":5}]}"#,
                createdAt: nowSeconds - 1_600,
                updatedAt: nowSeconds - 1_000
            )
        ]
        let execRuns = profile == .onboarding ? [] : [
            ExecRunRecord(
                runID: "exec-fixture-recall-routine",
                status: ExecRunStatus.completed.rawValue,
                reason: "ManifoldExec plan completed.",
                suggestedAlternative: nil,
                outputPreview: "Step 1 recall_memory\n- [mem-fixture-review-routine] routine Review routine: Start with search_structured...",
                createdAt: nowSeconds - 980
            ),
            ExecRunRecord(
                runID: "exec-fixture-refused-shell",
                status: ExecRunStatus.refused.rawValue,
                reason: "ManifoldExec refused op shell.",
                suggestedAlternative: "Use governed MCP tools directly for state-changing actions.",
                outputPreview: nil,
                createdAt: nowSeconds - 4_200
            )
        ]
        let capabilityHandles = profile == .onboarding ? [] : [
            ValueHandle(
                handleID: "handle-fixture-sensitive-email",
                origin: "email:customer-review",
                sensitivity: "sensitive",
                trustLevel: "untrusted",
                allowedSinks: ["model_context"],
                grantID: "grant-fixture",
                lineage: [LineageRef(kind: "source", id: "src-shared")],
                createdAt: nowSeconds - 1_200
            )
        ]
        let graphNodes = profile == .onboarding ? [] : [
            KnowledgeGraphNode(
                nodeID: "node-fixture-routine",
                kind: "routine",
                label: "Review routine uses search_structured before read_range",
                lineage: [LineageRef(kind: "source", id: "src-shared")],
                createdAt: nowSeconds - 1_100,
                updatedAt: nowSeconds - 900
            ),
            KnowledgeGraphNode(
                nodeID: "node-fixture-skill",
                kind: "skill",
                label: "Recall review routine",
                lineage: [],
                createdAt: nowSeconds - 1_000,
                updatedAt: nowSeconds - 1_000
            )
        ]
        let fabricationFindings = profile == .onboarding ? [] : [
            FabricationFinding(
                findingID: "finding-fixture-supported-read",
                sessionID: "session-2",
                claimText: "I used search_structured before reading the worklog.",
                status: "supported",
                evidenceJSON: #"{"evidence":"matching exposure exposure-fixture-search"}"#,
                createdAt: nowSeconds - 840
            )
        ]
        return FixtureState(
            sources: profile == .onboarding ? [] : [sourceA, sourceB],
            claudePolicy: claudePolicy,
            codexPolicy: codexPolicy,
            claudeGovernance: claudeGovernance,
            codexGovernance: codexGovernance,
            privacySettings: privacySettings,
            privacyRuntimes: privacyRuntimes,
            claudePrivacyPolicy: claudePrivacyPolicy,
            codexPrivacyPolicy: codexPrivacyPolicy,
            privacyRuntimeStatus: privacyRuntimeStatus,
            privacyIdentitySuggestions: profile == .onboarding ? [] : privacyIdentitySuggestions,
            privacyIdentities: profile == .onboarding ? [] : privacyIdentities,
            privacyOrgAllowEntries: profile == .onboarding ? [] : privacyOrgAllowEntries,
            privacyIndexRecords: profile == .onboarding ? [] : privacyIndexRecords,
            coverages: coverages,
            coverageEvents: isTrackedProfile ? coverageEvents : [],
            activeWorkBlock: activeWorkBlock,
            sessionAccessMode: .defaultSession,
            connectedAgents: profile == .onboarding ? [] : [TargetApp.cowork.rawValue, TargetApp.codex.rawValue],
            activityEntries: activity,
            sessions: sessions,
            sessionEvents: sessionEvents,
            ledgerEntries: ledgerEntries,
            ledgerVerification: ledgerVerification,
            toolCostReport: toolCostReport,
            memorySettings: memorySettings,
            memoryItems: memoryItems,
            skills: skills,
            execRuns: execRuns,
            capabilityHandles: capabilityHandles,
            graphNodes: graphNodes,
            fabricationFindings: fabricationFindings,
            activeGrant: activeGrant,
            activeGrantSources: activeGrantSources,
            activeGrantEmailIDs: [],
            pendingApprovals: pendingApprovals,
            emailRuleSets: [.cowork: claudeRules, .codex: codexRules],
            emailRuleSummaries: [
                .cowork: EmailRuleActivitySummary(agent: .cowork, shieldBlockedCounts: ["security": 2], recentShieldMatches: [], domainRuleHits: [.init(ruleID: claudeRules.domainRules[0].id, count: 5)], contactRuleHits: [.init(ruleID: claudeRules.contactRules[0].id, count: 1)], keywordRuleHits: [.init(ruleID: claudeRules.keywordRules[0].id, count: 3)]),
                .codex: EmailRuleActivitySummary(agent: .codex, shieldBlockedCounts: ["financial": 1], recentShieldMatches: [], domainRuleHits: [.init(ruleID: codexRules.domainRules[0].id, count: 4)], contactRuleHits: [], keywordRuleHits: [.init(ruleID: codexRules.keywordRules[0].id, count: 2)]),
            ],
            domainCounts: ["anthropic.test": 12, "openai.test": 7],
            trackedFiles: ["shared/worklog.md"],
            storageUsed: 24_576,
            mailAccounts: profile == .onboarding ? [] : [account],
            syncStates: ["account-1": [SyncStateRecord(accountID: "account-1", mailboxName: "INBOX", lastSyncAt: now, messageCount: profile == .onboarding ? 0 : inboxMessageCount, syncStatus: .idle)]],
            emails: profile == .onboarding ? [] : emails,
            imapMailboxes: profile == .onboarding ? [:] : imapMailboxes,
            sharedEmailIDsByAgent: profile == .onboarding ? [:] : [
                .cowork: ["email-1"],
                .codex: codexSharedEmailIDs,
            ],
            fileVisibilityOverrides: [:],
            rules: rules,
            seededRules: seededRules
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

    func runtimeStatusSnapshot() async throws -> RuntimeStatusSnapshot {
        try await command(name: "getStatus", as: RuntimeStatusSnapshot.self)
    }

    func dataControlSummary() async throws -> DataControlSummary {
        try await command(name: "dataControlSummary", field: "summary", as: DataControlSummary.self)
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

    func policies() async throws -> RuntimeStatusSnapshot {
        try await runtimeStatusSnapshot()
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

    func getPrivacySettings() async throws -> PrivacySettingsBundle {
        try await command(name: "getPrivacySettings", field: "bundle", as: PrivacySettingsBundle.self)
    }

    func updatePrivacySettings(settings: PrivacyPreflightSettings?, policy: AgentPrivacyPolicy?) async throws {
        var payload: [String: Any] = [:]
        if let settings {
            payload["settings"] = try XPCJSON.object(from: settings)
        }
        if let policy {
            payload["policy"] = try XPCJSON.object(from: policy)
        }
        _ = try await xpc.command(name: "updatePrivacySettings", payload: payload)
    }

    func listPrivacyRuntimes() async throws -> [PrivacyRuntimeDescriptor] {
        try await command(name: "listPrivacyRuntimes", field: "runtimes", as: [PrivacyRuntimeDescriptor].self)
    }

    func installPrivacyRuntime(id: String) async throws -> PrivacyRuntimeStatus {
        try await command(
            name: "installPrivacyRuntime",
            payload: ["runtimeID": id],
            field: "status",
            as: PrivacyRuntimeStatus.self
        )
    }

    func uninstallPrivacyRuntime(id: String) async throws -> PrivacyRuntimeStatus {
        try await command(
            name: "uninstallPrivacyRuntime",
            payload: ["runtimeID": id],
            field: "status",
            as: PrivacyRuntimeStatus.self
        )
    }

    func privacyRuntimeStatus() async throws -> PrivacyRuntimeStatus {
        try await command(name: "privacyRuntimeStatus", field: "status", as: PrivacyRuntimeStatus.self)
    }

    func clearPrivacyCache() async throws -> Int {
        let response = try await xpc.command(name: "clearPrivacyCache", payload: [:])
        return response["count"] as? Int ?? 0
    }

    func privacyIndexStatus() async throws -> PrivacyIndexRuntimeStatus {
        try await command(name: "privacyIndexStatus", field: "status", as: PrivacyIndexRuntimeStatus.self)
    }

    func listPrivacyIndex(
        scope: PrivacyIndexScope = PrivacyIndexScope(),
        filter: PrivacyIndexFilter = PrivacyIndexFilter(),
        limit: Int = 200
    ) async throws -> [PrivacyIndexRecord] {
        try await command(
            name: "listPrivacyIndex",
            payload: [
                "scope": try XPCJSON.object(from: scope),
                "filter": try XPCJSON.object(from: filter),
                "limit": limit,
            ],
            field: "records",
            as: [PrivacyIndexRecord].self
        )
    }

    func listPrivacyIdentitySuggestions() async throws -> [PrivacyIdentitySuggestion] {
        try await command(name: "listPrivacyIdentitySuggestions", field: "suggestions", as: [PrivacyIdentitySuggestion].self)
    }

    func acceptPrivacyIdentitySuggestion(id: String) async throws {
        _ = try await xpc.command(name: "acceptPrivacyIdentitySuggestion", payload: ["id": id])
    }

    func rejectPrivacyIdentitySuggestion(id: String) async throws {
        _ = try await xpc.command(name: "rejectPrivacyIdentitySuggestion", payload: ["id": id])
    }

    func upsertPrivacyIdentity(_ record: PrivacyIdentityRecord) async throws {
        _ = try await xpc.command(
            name: "upsertPrivacyIdentity",
            payload: ["record": try XPCJSON.object(from: record)]
        )
    }

    func upsertPrivacyOrgAllowEntry(_ entry: PrivacyOrgAllowEntry) async throws {
        _ = try await xpc.command(
            name: "upsertPrivacyOrgAllowEntry",
            payload: ["entry": try XPCJSON.object(from: entry)]
        )
    }

    func listPrivacyIdentities() async throws -> [PrivacyIdentityRecord] {
        try await command(name: "listPrivacyIdentities", field: "identities", as: [PrivacyIdentityRecord].self)
    }

    func listPrivacyOrgAllowEntries() async throws -> [PrivacyOrgAllowEntry] {
        try await command(name: "listPrivacyOrgAllowEntries", field: "entries", as: [PrivacyOrgAllowEntry].self)
    }

    func deletePrivacyIdentity(id: String) async throws {
        _ = try await xpc.command(name: "deletePrivacyIdentity", payload: ["id": id])
    }

    func deletePrivacyOrgAllowEntry(id: String) async throws {
        _ = try await xpc.command(name: "deletePrivacyOrgAllowEntry", payload: ["id": id])
    }

    func rescanPrivacyContent(contentIDs: [String]) async throws {
        _ = try await xpc.command(name: "rescanPrivacyContent", payload: ["contentIDs": contentIDs])
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

    func sessionAccessMode() async throws -> SessionAccessMode {
        let response = try await xpc.command(name: "sessionAccessMode", payload: [:])
        guard let raw = response["mode"] as? String,
              let mode = SessionAccessMode(rawValue: raw) else {
            throw ManifoldXPCError.malformedReply
        }
        return mode
    }

    func setSessionAccessMode(_ mode: SessionAccessMode) async throws {
        _ = try await xpc.command(name: "setSessionAccessMode", payload: ["mode": mode.rawValue])
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

    func startGatewaySession(
        targetApp: TargetApp,
        fileScopes: [FileSelectionScope],
        selectedEmailIDs: Set<String>,
        summaryFraming: String?,
        noteCaptureMode: SessionNoteCaptureMode,
        requestDetailLevel: AccessRecordingLevel?,
        memoryAccessEnabled: Bool,
        emailSensitivity: String?
    ) async throws -> ActiveGrantState {
        var payload: [String: Any] = [
            "targetApp": targetApp.rawValue,
            "fileScopes": try XPCJSON.object(from: fileScopes),
            "selectedEmailIDs": Array(selectedEmailIDs),
            "noteCaptureMode": noteCaptureMode.rawValue,
            "memoryAccessEnabled": memoryAccessEnabled,
        ]
        if let summaryFraming {
            payload["summaryFraming"] = summaryFraming
        }
        if let requestDetailLevel {
            payload["requestDetailLevel"] = requestDetailLevel.rawValue
        }
        if let emailSensitivity {
            payload["emailSensitivity"] = emailSensitivity
        }
        return try await command(name: "startGatewaySession", payload: payload, as: ActiveGrantState.self)
    }

    func updateGrantRequestDetailLevel(grantID: String, level: AccessRecordingLevel?) async throws -> GrantRecord {
        var payload: [String: Any] = ["grantID": grantID]
        if let level {
            payload["requestDetailLevel"] = level.rawValue
        }
        return try await command(name: "updateGrantRequestDetailLevel", payload: payload, field: "activeGrant", as: GrantRecord.self)
    }

    func updateGrantMemoryAccess(grantID: String, enabled: Bool) async throws -> GrantRecord {
        try await command(
            name: "updateGrantMemoryAccess",
            payload: ["grantID": grantID, "enabled": enabled],
            field: "activeGrant",
            as: GrantRecord.self
        )
    }

    func endSession(grantID: String) async throws {
        _ = try await xpc.command(name: "endSession", payload: ["grantID": grantID])
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

    func pauseGatewaySession(id: String) async throws {
        _ = try await xpc.command(name: "pauseGatewaySession", payload: ["workBlockID": id])
    }

    func resumeGatewaySession(id: String) async throws {
        _ = try await xpc.command(name: "resumeGatewaySession", payload: ["workBlockID": id])
    }

    func discardDraftWorkspace(id: String, grantID: String?, endSession: Bool = false) async throws {
        var payload: [String: Any] = ["workBlockID": id, "endSession": endSession]
        if let grantID {
            payload["grantID"] = grantID
        }
        _ = try await xpc.command(name: "discardDraftWorkspace", payload: payload)
    }

    func promotionPreview(grantID: String) async throws -> WorkBlockPreview {
        try await command(name: "promotionPreview", payload: ["grantID": grantID], field: "preview", as: WorkBlockPreview.self)
    }

    func applyDraftWorkspace(grantID: String, endSession: Bool = false) async throws -> ApplyWorkspaceResult {
        try await command(
            name: "applyDraftWorkspace",
            payload: ["grantID": grantID, "endSession": endSession],
            field: "result",
            as: ApplyWorkspaceResult.self
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

    func trackedFileCounts() async throws -> [String: Int] {
        try await command(name: "trackedFileCounts", field: "counts", as: [String: Int].self)
    }

    func storageStats() async throws -> StorageStatsSnapshot {
        try await command(name: "storageStats", field: "stats", as: StorageStatsSnapshot.self)
    }

    func recentLedgerEntries(limit: Int = 50) async throws -> [LedgerEntry] {
        try await command(
            name: "recentLedgerEntries",
            payload: ["limit": limit],
            field: "entries",
            as: [LedgerEntry].self
        )
    }

    func verifyLedger() async throws -> LedgerVerificationResult {
        try await command(name: "verifyLedger", field: "result", as: LedgerVerificationResult.self)
    }

    func toolCostReport(limit: Int = 200) async throws -> ToolCostReport {
        try await command(
            name: "toolCostReport",
            payload: ["limit": limit],
            field: "report",
            as: ToolCostReport.self
        )
    }

    func listMemory(limit: Int = 100, includeDeleted: Bool = false) async throws -> [MemoryItem] {
        try await command(
            name: "listMemory",
            payload: ["limit": limit, "includeDeleted": includeDeleted],
            field: "items",
            as: [MemoryItem].self
        )
    }

    func listMemorySources() async throws -> [MemorySourceSummary] {
        try await command(name: "listMemorySources", field: "sources", as: [MemorySourceSummary].self)
    }

    func getMemorySettings() async throws -> MemorySettings {
        try await command(name: "getMemorySettings", field: "settings", as: MemorySettings.self)
    }

    func updateMemorySettings(_ settings: MemorySettings) async throws -> MemorySettings {
        try await command(
            name: "updateMemorySettings",
            payload: ["settings": try XPCJSON.object(from: settings)],
            field: "settings",
            as: MemorySettings.self
        )
    }

    func forgetMemory(id: String) async throws {
        _ = try await xpc.command(name: "forgetMemory", payload: ["memoryID": id])
    }

    func listSkills(limit: Int = 50) async throws -> [SkillRecord] {
        try await command(
            name: "listSkills",
            payload: ["limit": limit],
            field: "skills",
            as: [SkillRecord].self
        )
    }

    func recentExecRuns(limit: Int = 50) async throws -> [ExecRunRecord] {
        try await command(
            name: "recentExecRuns",
            payload: ["limit": limit],
            field: "runs",
            as: [ExecRunRecord].self
        )
    }

    func listCapabilityHandles(limit: Int = 50) async throws -> [ValueHandle] {
        try await command(
            name: "listCapabilityHandles",
            payload: ["limit": limit],
            field: "handles",
            as: [ValueHandle].self
        )
    }

    func queryGraphNodes(query: String = "", limit: Int = 50) async throws -> [KnowledgeGraphNode] {
        try await command(
            name: "queryGraphNodes",
            payload: ["query": query, "limit": limit],
            field: "nodes",
            as: [KnowledgeGraphNode].self
        )
    }

    func recentFabricationFindings(limit: Int = 50) async throws -> [FabricationFinding] {
        try await command(
            name: "recentFabricationFindings",
            payload: ["limit": limit],
            field: "findings",
            as: [FabricationFinding].self
        )
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
        // R5: cleartext password no longer crosses XPC. We stage the
        // password in Keychain at a `pending-{uuid}` slot and send only
        // the UUID over IPC. The agent reads from Keychain, validates
        // the IMAP login, then rotates the entry to its canonical
        // location on success or deletes it on failure.
        let pendingID = UUID().uuidString
        let kind: MailCredentialKind = (
            provider == .gmail || provider == .yahoo || provider == .icloud || provider == .fastmail
        ) ? .appPassword : .manualPassword
        let pendingRef = KeychainMailSecretStore.pendingReference(pendingID: pendingID, kind: kind)
        let secretStore = KeychainMailSecretStore()
        guard let credentialData = password.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              secretStore.store(credentialData, reference: pendingRef) else {
            throw NSError(
                domain: "com.spatialduality.manifold.app",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't stage credential in Keychain. Check Keychain permissions and try again."]
            )
        }
        do {
            return try await command(
                name: "addIMAPAccount",
                payload: [
                    "displayName": displayName,
                    "provider": provider.rawValue,
                    "server": server,
                    "port": port,
                    "username": username,
                    "pendingCredentialID": pendingID,
                ],
                field: "account",
                as: EmailAccountRecord.self
            )
        } catch {
            // Agent failed before consuming the pending entry. Clean up
            // so the launch sweep doesn't have to.
            secretStore.delete(reference: pendingRef)
            throw error
        }
    }

    func addOAuthIMAPAccount(
        displayName: String,
        provider: EmailProvider,
        server: String,
        port: Int,
        username: String,
        tokenSet: MicrosoftOAuthTokenSet
    ) async throws -> EmailAccountRecord {
        // R5: same pattern — token set stays in Keychain, only the
        // pending UUID crosses XPC.
        let pendingID = UUID().uuidString
        let pendingRef = KeychainMailSecretStore.pendingReference(pendingID: pendingID, kind: .oauthTokenSet)
        let secretStore = KeychainMailSecretStore()
        let tokenSetData = try JSONEncoder().encode(tokenSet)
        guard secretStore.store(tokenSetData, reference: pendingRef) else {
            throw NSError(
                domain: "com.spatialduality.manifold.app",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't stage OAuth tokens in Keychain. Check Keychain permissions and try again."]
            )
        }
        do {
            return try await command(
                name: "addOAuthIMAPAccount",
                payload: [
                    "displayName": displayName,
                    "provider": provider.rawValue,
                    "server": server,
                    "port": port,
                    "username": username,
                    "pendingCredentialID": pendingID,
                ],
                field: "account",
                as: EmailAccountRecord.self
            )
        } catch {
            secretStore.delete(reference: pendingRef)
            throw error
        }
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

    func sharedEmailCount(agent: TargetApp) async throws -> Int {
        try await command(name: "sharedEmailCount", payload: ["agent": agent.rawValue], field: "count", as: Int.self)
    }

    func sharedEmailIDs(agent: TargetApp) async throws -> Set<String> {
        Set(try await command(name: "sharedEmailIDs", payload: ["agent": agent.rawValue], field: "ids", as: [String].self))
    }

    func sharedEmails(agent: TargetApp, limit: Int = 500) async throws -> [EmailMessageRecord] {
        try await command(
            name: "sharedEmails",
            payload: ["agent": agent.rawValue, "limit": limit],
            field: "messages",
            as: [EmailMessageRecord].self
        )
    }

    func shareEmails(emailIDs: [String], for agent: TargetApp) async throws {
        _ = try await xpc.command(name: "shareEmails", payload: ["agent": agent.rawValue, "emailIDs": emailIDs])
    }

    func unshareEmails(emailIDs: [String], for agent: TargetApp) async throws {
        _ = try await xpc.command(name: "unshareEmails", payload: ["agent": agent.rawValue, "emailIDs": emailIDs])
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

    func emailBackupInfo() async throws -> MailArchiveInfo {
        try await command(name: "emailBackupInfo", field: "info", as: MailArchiveInfo.self)
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
