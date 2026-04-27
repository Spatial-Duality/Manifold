// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CryptoKit
import ManifoldKit
import os

private let runtimeLogger = Logger(subsystem: "com.spatialduality.manifold", category: "runtime")

/// Owns the local runtime graph used by the app, XPC service, and MCP bridge.
public actor ManifoldRuntime {
    /// Shared database connection for runtime-owned stores.
    public nonisolated let db: DatabaseConnection
    /// Content-addressed blob store for tracked file history.
    public nonisolated let contentStore: ContentStore
    /// Audit log for sessions, activity, and coverage events.
    public nonisolated let auditStore: AuditStore
    /// Snapshot timeline store for tracked file changes.
    public nonisolated let snapshotStore: SnapshotStore
    /// Workspace lease manager for tracked materializations.
    public nonisolated let leaseManager: WorkspaceLeaseManager
    /// Store for sources, grants, and tracked-work relationships.
    public nonisolated let grantStore: GrantStore
    /// Local email archive and search store.
    public nonisolated let emailStore: EmailStore
    /// Artifact lookup index for governed files.
    public nonisolated let artifactIndex: ArtifactIndex
    /// Per-agent standing access policy store.
    public nonisolated let policyStore: PolicyStore
    /// Runtime-owned email governance store.
    public nonisolated let emailRuleStore: EmailRuleStore
    /// Persistent tracked work block store.
    public nonisolated let workBlockStore: WorkBlockStore
    /// Persisted per-file visibility overrides used by the review surfaces.
    public nonisolated let fileVisibilityOverrideStore: FileVisibilityOverrideStore
    /// Mail synchronization engine.
    public nonisolated let emailSyncEngine: EmailSyncEngine
    /// Approval queue for governed escalations.
    public nonisolated let approvalQueue: ApprovalQueue
    /// Persisted standing-write grants for queue approvals.
    public nonisolated let standingWriteApprovalStore: StandingWriteApprovalStore
    /// Access decision and exposure record store.
    public nonisolated let exposureStore: ExposureStore
    /// Tamper-evident ledger for provenance, memory, and tool metrics.
    public nonisolated let ledgerStore: LedgerStore
    /// Per-tool cost metrics used to measure context and latency reductions.
    public nonisolated let toolMetricsStore: ToolMetricsStore
    /// User-owned derived memory with lineage and retention state.
    public nonisolated let memoryStore: MemoryStore
    /// Saved skill manifests. Invocation is gated until ManifoldExec is enabled.
    public nonisolated let skillStore: SkillStore
    /// Capability handles used by high-risk dataflow checks.
    public nonisolated let capabilityHandleStore: CapabilityHandleStore
    /// Deterministic ManifoldExec run records.
    public nonisolated let execRunStore: ExecRunStore
    /// Scoped knowledge graph nodes and edges.
    public nonisolated let knowledgeGraphStore: KnowledgeGraphStore
    /// Findings from model-claimed action verification.
    public nonisolated let fabricationFindingStore: FabricationFindingStore
    /// Unified cross-scope rule catalog (file / email / agent).
    public nonisolated let ruleStore: RuleStore
    /// Privacy preflight settings, cache, and approval overrides.
    public nonisolated let privacyStore: PrivacyStore
    /// Runtime coordinator for governed privacy scans and backend selection.
    public nonisolated let privacyCoordinator: PrivacyPreflightCoordinator
    /// Runtime coordinator for background privacy indexing.
    public nonisolated let privacyIndexCoordinator: PrivacyIndexCoordinator

    private var bridges: [String: ManifoldBridge] = [:]
    private var recordedCoverageEventKeys: Set<String> = []

    /// Creates the runtime and initializes all local stores at the chosen root URL.
    public init(storeURL: URL? = nil) throws {
        let rootURL = storeURL ?? Self.defaultStoreURL
        try LocalFileProtection.ensureDirectory(at: rootURL)

        let db = try DatabaseConnection(url: rootURL.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let contentStore = try ContentStore(rootURL: rootURL, db: db)
        let auditStore = try AuditStore(db: db)
        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)
        let leaseManager = try WorkspaceLeaseManager(db: db, snapshotStore: snapshotStore)
        let grantStore = GrantStore(db: db)
        let emailStore = EmailStore(db: db)
        let artifactIndex = try ArtifactIndex(db: db)
        let policyStore = PolicyStore(db: db)
        let emailRuleStore = EmailRuleStore(db: db, policyStore: policyStore)
        let workBlockStore = WorkBlockStore(db: db)
        let fileVisibilityOverrideStore = FileVisibilityOverrideStore(db: db)
        let emailSyncEngine = EmailSyncEngine(emailStore: emailStore)
        let approvalQueue = ApprovalQueue(db: db)
        let standingWriteApprovalStore = StandingWriteApprovalStore(db: db)
        let exposureStore = ExposureStore(db: db)
        let ledgerStore = try LedgerStore(db: db)
        let toolMetricsStore = try ToolMetricsStore(db: db)
        let memoryStore = try MemoryStore(db: db)
        let skillStore = try SkillStore(db: db)
        let capabilityHandleStore = try CapabilityHandleStore(db: db)
        let execRunStore = try ExecRunStore(db: db)
        let knowledgeGraphStore = try KnowledgeGraphStore(db: db)
        let fabricationFindingStore = try FabricationFindingStore(db: db)
        let ruleStore = RuleStore(db: db)
        let privacyStore = PrivacyStore(db: db)
        let privacyStorageURL = rootURL.appendingPathComponent("privacy")
        let rulesOnlyBackend = RulesOnlyPrivacyBackend()
        let officialCLIBackend = OfficialCLIPrivacyBackend(storageURL: privacyStorageURL)
        let privacyCoordinator = PrivacyPreflightCoordinator(
            store: privacyStore,
            defaultStorageURL: privacyStorageURL,
            rulesOnlyBackend: rulesOnlyBackend,
            officialCLIBackend: officialCLIBackend
        )
        let privacyIndexCoordinator = PrivacyIndexCoordinator(
            store: privacyStore,
            grantStore: grantStore,
            emailStore: emailStore,
            emailSyncEngine: emailSyncEngine,
            defaultStoragePath: privacyStorageURL.path,
            rulesOnlyBackend: rulesOnlyBackend,
            officialCLIBackend: officialCLIBackend
        )

        self.db = db
        self.contentStore = contentStore
        self.auditStore = auditStore
        self.snapshotStore = snapshotStore
        self.leaseManager = leaseManager
        self.grantStore = grantStore
        self.emailStore = emailStore
        self.artifactIndex = artifactIndex
        self.policyStore = policyStore
        self.emailRuleStore = emailRuleStore
        self.workBlockStore = workBlockStore
        self.fileVisibilityOverrideStore = fileVisibilityOverrideStore
        self.emailSyncEngine = emailSyncEngine
        self.approvalQueue = approvalQueue
        self.standingWriteApprovalStore = standingWriteApprovalStore
        self.exposureStore = exposureStore
        self.ledgerStore = ledgerStore
        self.toolMetricsStore = toolMetricsStore
        self.memoryStore = memoryStore
        self.skillStore = skillStore
        self.capabilityHandleStore = capabilityHandleStore
        self.execRunStore = execRunStore
        self.knowledgeGraphStore = knowledgeGraphStore
        self.fabricationFindingStore = fabricationFindingStore
        self.ruleStore = ruleStore
        self.privacyStore = privacyStore
        self.privacyCoordinator = privacyCoordinator
        self.privacyIndexCoordinator = privacyIndexCoordinator

        runtimeLogger.info("Initialized runtime at \(rootURL.path, privacy: .public)")
    }

    /// One-shot startup work that's async and shouldn't block `init`.
    /// Idempotent — callers may invoke repeatedly without side effects.
    public func bootstrap() async {
        do {
            try await ruleStore.seedIfNeeded(RuleSeedCatalog.seeds())
            runtimeLogger.info("Seeded rule catalog (idempotent).")
        } catch {
            runtimeLogger.error("Rule catalog seeding failed: \(String(describing: error), privacy: .public)")
        }

        await privacyIndexCoordinator.bootstrap()
    }

    /// Returns the bridge for a connection, creating it if this is the first request for that connection.
    public func bridge(for connectionID: String, targetApp: TargetApp, version: String) -> ManifoldBridge {
        if let existing = bridges[connectionID] {
            return existing
        }

        let bridge = ManifoldBridge(
            db: db,
            auditStore: auditStore,
            contentStore: contentStore,
            grantStore: grantStore,
            emailStore: emailStore,
            snapshotStore: snapshotStore,
            artifactIndex: artifactIndex,
            policyStore: policyStore,
            emailRuleStore: emailRuleStore,
            workBlockStore: workBlockStore,
            fileVisibilityOverrideStore: fileVisibilityOverrideStore,
            approvalQueue: approvalQueue,
            standingWriteApprovalStore: standingWriteApprovalStore,
            exposureStore: exposureStore,
            ledgerStore: ledgerStore,
            memoryStore: memoryStore,
            skillStore: skillStore,
            capabilityHandleStore: capabilityHandleStore,
            execRunStore: execRunStore,
            knowledgeGraphStore: knowledgeGraphStore,
            fabricationFindingStore: fabricationFindingStore,
            ruleStore: ruleStore,
            privacyCoordinator: privacyCoordinator,
            targetApp: targetApp,
            serverName: "manifold",
            serverVersion: version,
            connectionID: connectionID
        )
        bridges[connectionID] = bridge
        return bridge
    }

    /// Removes a bridge after a client disconnects.
    public func removeBridge(_ connectionID: String) {
        bridges.removeValue(forKey: connectionID)
    }

    /// Returns the number of active bridge connections.
    public var activeBridgeCount: Int {
        bridges.count
    }

    /// Returns the set of agent names that currently have active XPC bridge connections.
    public var connectedAgents: [String] {
        Array(Set(bridges.values.map(\.agentName))).sorted()
    }

    /// Returns the best current coverage snapshot for each supported agent.
    public func connectedClientSnapshots() async -> [AgentCoverageSnapshot] {
        let activeBlock = try? await workBlockStore.anyActiveBlock()
        var snapshots: [AgentCoverageSnapshot] = []

        for agent in TargetApp.allCases {
            let identities = await bridges.values
                .filter { $0.agentName == agent.rawValue }
                .asyncCompactMap { await $0.verifiedClientIdentity() }
            let bestIdentity = identities.first(where: \.isVerified) ?? identities.first
            let coverageState: CoverageState
            if activeBlock?.agent == agent {
                coverageState = .trackedWorkspace
            } else if bestIdentity?.status == .verified {
                coverageState = .manifoldRouted
            } else {
                coverageState = .outsideCoverage
            }

            snapshots.append(
                AgentCoverageSnapshot(
                    agent: agent.rawValue,
                    coverageState: coverageState,
                    verificationStatus: bestIdentity?.status ?? .unknown,
                    hostBundleIdentifier: bestIdentity?.hostBundleIdentifier,
                    reason: bestIdentity?.reason
                )
            )
        }

        return snapshots
    }

    /// Records a coverage event in the audit log and optionally deduplicates repeated events.
    public func recordCoverageEvent(
        agent: TargetApp,
        coverageState: CoverageState,
        eventType: String,
        message: String,
        resourcePath: String? = nil,
        metadata: [String: String] = [:],
        dedupeKey: String? = nil
    ) async {
        if let dedupeKey {
            guard !recordedCoverageEventKeys.contains(dedupeKey) else { return }
            recordedCoverageEventKeys.insert(dedupeKey)
        }

        var payload = metadata
        payload["coverage_state"] = coverageState.rawValue
        payload["event_type"] = eventType
        payload["message"] = message

        let action: AuditAction = eventType == "drift" ? .contentDrift : .coverageWarning
        try? await auditStore.log(
            action: action,
            agent: agent.rawValue,
            filePath: resourcePath,
            metadata: payload
        )
    }

    /// Returns recent coverage and drift events.
    public func coverageEvents(limit: Int = 50) async -> [CoverageEvent] {
        let entries = (try? await auditStore.recentEntries(limit: max(limit * 3, 50))) ?? []
        return entries.compactMap { Self.coverageEvent(from: $0) }.prefix(limit).map { $0 }
    }

    /// Scans active tracked work for original-file drift outside the governed workspace.
    public func scanForActiveWorkBlockDrift() async {
        guard let block = try? await workBlockStore.anyActiveBlock(),
              let grant = try? await grantStore.grant(id: block.grantID),
              let grantSources = try? await grantStore.grantSources(grantID: grant.grantID) else {
            return
        }

        let sourceIndex = ((try? await grantStore.allSources()) ?? []).reduce(into: [String: SourceRecord]()) { result, source in
            result[source.sourceID] = source
        }
        let workspaceURL = URL(fileURLWithPath: grant.materializationRoot)

        for grantSource in grantSources {
            guard let source = sourceIndex[grantSource.sourceID] else { continue }
            let baselineURL = workspaceURL
                .appendingPathComponent(grantSource.mountName)
                .appendingPathComponent(".manifold-baseline.json")
            guard let baselineData = try? Data(contentsOf: baselineURL),
                  let baseline = try? JSONSerialization.jsonObject(with: baselineData) as? [String: String] else {
                continue
            }

            for (relativePath, baselineHash) in baseline {
                let originalURL = URL(fileURLWithPath: source.originalRootPath).appendingPathComponent(relativePath)
                let currentHash = Self.hashForFile(at: originalURL) ?? "__missing__"
                guard currentHash != baselineHash else { continue }

                await recordCoverageEvent(
                    agent: block.agent,
                    coverageState: .outsideCoverage,
                    eventType: "drift",
                    message: "Original file changed outside the tracked workflow.",
                    resourcePath: "\(grantSource.mountName)/\(relativePath)",
                    metadata: [
                        "grant_id": grant.grantID,
                        "work_block_id": block.id,
                        "source_id": grantSource.sourceID,
                        "baseline_hash": baselineHash,
                        "current_hash": currentHash,
                    ],
                    dedupeKey: "\(block.id):\(grantSource.sourceID):\(relativePath):\(currentHash)"
                )
            }
        }
    }

    /// Returns version history, recent activity, and exposure context for one file path.
    public func fileHistoryContext(filePath: String, limit: Int = 20) async -> FileHistoryContext {
        let snapshots = ((try? await snapshotStore.fileHistory(filePath: filePath)) ?? []).prefix(limit).map { $0 }
        let activity = ((try? await auditStore.recentEntries(limit: max(limit * 10, 100))) ?? [])
            .filter { $0.filePath == filePath }
            .prefix(limit)
            .map { $0 }
        let exposures = (try? await exposureStore.exposures(resourcePath: filePath, limit: limit)) ?? []
        let sessionIDs = Array(Set(activity.compactMap(\.sessionID))).sorted()
        return FileHistoryContext(
            filePath: filePath,
            snapshots: snapshots,
            relatedActivity: activity,
            recentExposures: exposures,
            relatedSessionIDs: sessionIDs
        )
    }

    /// Returns the governed session context for one session, optionally filtered to the viewer's current visibility.
    public func sessionContext(sessionID: String, viewingAs viewerAgent: TargetApp? = nil) async -> SessionContextDetail {
        let entries = (try? await auditStore.entries(sessionID: sessionID, limit: 200)) ?? []
        let events = (try? await auditStore.sessionEvents(sessionID: sessionID)) ?? []
        let session = (try? await auditStore.recentSessions(limit: 200))?.first { $0.id == sessionID }
        let grantID = entries.compactMap(\.grantID).first
        let notes: [SessionSummaryRecord]
        if let grantID {
            notes = (try? await grantStore.summaries(grantID: grantID)) ?? []
        } else {
            notes = []
        }
        let filePaths = Array(Set(entries.compactMap(\.filePath))).sorted()
        let messageIDs: [String] = Array(
            Set<String>(
                entries.compactMap { entry in
                    guard let metadata = entry.metadata?.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: metadata) as? [String: String] else {
                        return nil
                    }
                    return object["messageID"]
                }
            )
        ).sorted()
        let emails = (try? emailStore.emailMessages(ids: messageIDs)) ?? []
        let viewerPolicy: AgentAccessPolicy?
        if let viewerAgent {
            viewerPolicy = try? await policyStore.policy(for: viewerAgent)
        } else {
            viewerPolicy = nil
        }
        let emailSummaries = (try? await HistoryVisibilityFilter.relatedEmails(
            emails,
            viewerPolicy: viewerPolicy,
            decisionResolver: { [emailRuleStore, policyStore, emailStore] email, policy in
                let ruleSet = (try? await emailRuleStore.ruleSet(for: policy.agent))
                    ?? EmailRuleSet(
                        agent: policy.agent,
                        defaultPolicy: policy.defaultEmailPolicy,
                        emailSensitivity: policy.emailSensitivity
                    )
                let sharedEmailIDs = (try? emailStore.sharedEmailIDs(agent: policy.agent)) ?? []
                let temporaryRevealIDs = Set((try? await policyStore.temporaryReveals(for: policy.agent).map(\.emailID)) ?? [])
                let context = EmailPolicyEngine.Context(
                    agent: policy.agent,
                    ruleSet: ruleSet,
                    policy: policy,
                    sharedEmailIDs: sharedEmailIDs,
                    temporaryRevealIDs: temporaryRevealIDs,
                    explicitGrantEmailIDs: nil,
                    sensitivity: ruleSet.emailSensitivity
                )
                return EmailPolicyEngine.decision(for: email, context: context)
            }
        )) ?? emails.map {
            RelatedEmailContext(id: $0.emailID, from: $0.sender, subject: $0.subject, date: $0.receivedAt)
        }
        return SessionContextDetail(
            session: session,
            grantID: grantID,
            entries: entries,
            events: events,
            filePaths: filePaths,
            emails: emailSummaries,
            notes: notes
        )
    }

    /// Summarizes recent email-rule activity for one agent from the audit trail.
    public func emailRuleActivitySummary(for agent: TargetApp) async throws -> EmailRuleActivitySummary {
        let ruleSet = try await emailRuleStore.ruleSet(for: agent)
        let policy = try await policyStore.policy(for: agent)
        let emails = try emailStore.allEmailMessages(limit: 2_000)
        return EmailPolicyEngine.activitySummary(
            agent: agent,
            ruleSet: ruleSet,
            policy: policy,
            emails: emails
        )
    }

    /// Returns the compact email-governance summary used by the app UI.
    public func emailGovernanceSummary(for agent: TargetApp) async throws -> AgentEmailGovernanceSummary {
        try await emailRuleStore.emailGovernanceSummary(for: agent)
    }

    /// Counts emails currently visible to an agent through the same policy engine
    /// used by MCP reads/searches.
    public func visibleEmailCount(for agent: TargetApp, limit: Int = 5_000) async throws -> Int {
        let policy = try await policyStore.policy(for: agent)
        let ruleSet = try await emailRuleStore.ruleSet(for: agent)
        let sharedEmailIDs = try emailStore.sharedEmailIDs(agent: agent)
        let temporaryRevealIDs = Set((try await policyStore.temporaryReveals(for: agent)).map(\.emailID))
        let context = EmailPolicyEngine.Context(
            agent: agent,
            ruleSet: ruleSet,
            policy: policy,
            sharedEmailIDs: sharedEmailIDs,
            temporaryRevealIDs: temporaryRevealIDs,
            explicitGrantEmailIDs: nil,
            sensitivity: ruleSet.emailSensitivity
        )
        let emails = try emailStore.allEmailMessages(limit: limit)
        return emails.filter { EmailPolicyEngine.decision(for: $0, context: context).allowed }.count
    }

    /// Returns the default local storage root for the runtime.
    public nonisolated static var defaultStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Manifold")
            .appendingPathComponent("store")
    }

    private static func hashForFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func coverageEvent(from entry: ManifoldKit.AuditEntry) -> CoverageEvent? {
        guard entry.action == AuditAction.contentDrift.rawValue || entry.action == AuditAction.coverageWarning.rawValue else {
            return nil
        }
        let metadata = entry.metadata
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        let coverageState = metadata
            .flatMap { $0["coverage_state"] }
            .flatMap(CoverageState.init(rawValue:))
            ?? .outsideCoverage
        return CoverageEvent(
            id: "\(entry.timestamp):\(entry.action):\(entry.filePath ?? "")",
            agent: entry.agent ?? "",
            coverageState: coverageState,
            eventType: metadata?["event_type"] ?? entry.action,
            message: metadata?["message"] ?? entry.action.replacingOccurrences(of: "_", with: " ").capitalized,
            resourcePath: entry.filePath,
            timestamp: entry.timestamp,
            metadata: entry.metadata
        )
    }
}

private extension Sequence {
    func asyncCompactMap<T>(_ transform: @escaping (Element) async -> T?) async -> [T] {
        var values: [T] = []
        for element in self {
            if let value = await transform(element) {
                values.append(value)
            }
        }
        return values
    }
}
