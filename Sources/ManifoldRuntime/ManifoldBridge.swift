// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CryptoKit
import ManifoldKit
import os

/// Core logic layer between MCP protocol and ManifoldKit stores.
/// Dual-path access: standing access via PolicyStore, work block via grant materialization.
/// Fail-closed: no policy and no grant = no access.
public actor ManifoldBridge {
    private static let maxExposurePreviewCharacters = 512
    private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "runtime")
    private let db: DatabaseConnection
    private let auditStore: AuditStore
    private let contentStore: ContentStore
    private let grantStore: GrantStore
    private let emailStore: EmailStore
    private let snapshotStore: SnapshotStore
    private let artifactIndex: ArtifactIndex
    private let policyStore: PolicyStore?
    private let emailRuleStore: EmailRuleStore?
    private let workBlockStore: WorkBlockStore?
    private let fileVisibilityOverrideStore: FileVisibilityOverrideStore?
    private let approvalQueue: ApprovalQueue?
    private let standingWriteApprovalStore: StandingWriteApprovalStore?
    private let exposureStore: ExposureStore?
    private let ruleStore: RuleStore?
    private let privacyCoordinator: PrivacyPreflightCoordinator?
    nonisolated let targetApp: TargetApp
    private let profileID: String
    private var runtimeContext: AgentRuntimeContext
    private var connectionLogged = false

    public init(
        db: DatabaseConnection,
        auditStore: AuditStore,
        contentStore: ContentStore,
        grantStore: GrantStore,
        emailStore: EmailStore,
        snapshotStore: SnapshotStore,
        artifactIndex: ArtifactIndex,
        policyStore: PolicyStore? = nil,
        emailRuleStore: EmailRuleStore? = nil,
        workBlockStore: WorkBlockStore? = nil,
        fileVisibilityOverrideStore: FileVisibilityOverrideStore? = nil,
        approvalQueue: ApprovalQueue? = nil,
        standingWriteApprovalStore: StandingWriteApprovalStore? = nil,
        exposureStore: ExposureStore? = nil,
        ruleStore: RuleStore? = nil,
        privacyCoordinator: PrivacyPreflightCoordinator? = nil,
        targetApp: TargetApp = .cowork,
        profileID: String = "default",
        serverName: String = "manifold",
        serverVersion: String = "0.0.0",
        connectionID: String? = nil
    ) {
        self.db = db
        self.auditStore = auditStore
        self.contentStore = contentStore
        self.grantStore = grantStore
        self.emailStore = emailStore
        self.snapshotStore = snapshotStore
        self.artifactIndex = artifactIndex
        self.policyStore = policyStore
        self.emailRuleStore = emailRuleStore
        self.workBlockStore = workBlockStore
        self.fileVisibilityOverrideStore = fileVisibilityOverrideStore
        self.approvalQueue = approvalQueue
        self.standingWriteApprovalStore = standingWriteApprovalStore
        self.exposureStore = exposureStore
        self.ruleStore = ruleStore
        self.privacyCoordinator = privacyCoordinator
        self.targetApp = targetApp
        self.profileID = profileID
        self.runtimeContext = AgentRuntimeContext(
            connectionID: connectionID,
            targetApp: targetApp,
            profileID: profileID,
            serverName: serverName,
            serverVersion: serverVersion
        )
    }

    public nonisolated var agentName: String { targetApp.rawValue }

    private func mergedMetadata(_ metadata: [String: String] = [:]) -> [String: String] {
        runtimeContext.eventContextMetadata.merging(metadata) { _, new in new }
    }

    private struct DecisionContext {
        let reason: String
        let accessMode: String
        let policySnapshot: String?
    }

    private func policySnapshot(for policy: AgentAccessPolicy) -> String? {
        let snapshot: [String: Any] = [
            "allowed_source_ids": policy.allowedSourceIDs.sorted(),
            "allowed_email_domains": policy.allowedEmailDomains.sorted(),
            "email_sensitivity": policy.emailSensitivity.rawValue,
            "default_email_policy": policy.defaultEmailPolicy.rawValue,
            "is_paused": policy.isPaused,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func clientIdentityJSON() -> String? {
        guard let identity = runtimeContext.verifiedClientIdentity,
              let data = try? JSONEncoder().encode(identity) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func decisionContext(for accessContext: AccessContext) -> DecisionContext {
        switch accessContext {
        case .standing(let policy, _):
            return DecisionContext(
                reason: "standing_access",
                accessMode: "standing",
                policySnapshot: policySnapshot(for: policy)
            )
        case .workBlock(let grant, _, let block):
            return DecisionContext(
                reason: "work_block",
                accessMode: "tracked_run",
                policySnapshot: "{\"grant_id\":\"\(grant.grantID)\",\"work_block_id\":\"\(block.id)\"}"
            )
        case .legacyGrant(let grant, _):
            return DecisionContext(
                reason: "work_block",
                accessMode: "legacy_grant",
                policySnapshot: "{\"grant_id\":\"\(grant.grantID)\"}"
            )
        }
    }

    private func deniedDecisionContext(for error: Error) -> DecisionContext {
        if let mcpError = error as? ManifoldMCPError {
            switch mcpError {
            case .accessPaused:
                return DecisionContext(reason: "paused", accessMode: "paused", policySnapshot: nil)
            case .noAccessConfigured:
                return DecisionContext(reason: "policy_denied", accessMode: "standing", policySnapshot: nil)
            case .noActiveSession:
                return DecisionContext(reason: "policy_denied", accessMode: "tracked_run", policySnapshot: nil)
            case .intentRequired:
                return DecisionContext(reason: "intent_required", accessMode: "governed", policySnapshot: nil)
            case .privacyReviewRequired:
                return DecisionContext(reason: "privacy_review_required", accessMode: "privacy", policySnapshot: nil)
            case .noSources, .fileNotFound, .invalidPath:
                return DecisionContext(reason: "policy_denied", accessMode: "unknown", policySnapshot: nil)
            case .ruleDenied:
                return DecisionContext(reason: "rule_denied", accessMode: "rule", policySnapshot: nil)
            }
        }
        return DecisionContext(reason: "policy_denied", accessMode: "unknown", policySnapshot: nil)
    }

    @discardableResult
    private func recordAccessDecision(
        toolName: String,
        resourcePath: String?,
        action: String,
        allowed: Bool,
        reason: String,
        accessMode: String,
        policySnapshot: String? = nil,
        intent: AccessIntent? = nil
    ) async -> String? {
        guard let exposureStore else { return nil }
        let decision = AccessDecision(
            connectionID: runtimeContext.connectionID,
            agent: agentName,
            toolName: toolName,
            resourcePath: resourcePath,
            action: action,
            allowed: allowed,
            reason: reason,
            accessMode: accessMode,
            policySnapshot: policySnapshot,
            clientIdentity: clientIdentityJSON(),
            intentSummary: intent?.summary,
            intentDetails: intent?.details
        )
        do {
            try await exposureStore.recordDecision(decision)
            return decision.id
        } catch {
            logger.error("Failed to record access decision: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func recordExposure(
        toolName: String,
        resourcePath: String?,
        text: String,
        exposureType: String,
        decisionID: String?,
        intent: AccessIntent? = nil
    ) async {
        guard decisionID != nil else { return }
        await recordExposure(
            toolName: toolName,
            resourcePath: resourcePath,
            data: Data(text.utf8),
            exposureType: exposureType,
            decisionID: decisionID,
            intent: intent
        )
    }

    private func recordExposure(
        toolName: String,
        resourcePath: String?,
        data: Data,
        exposureType: String,
        decisionID: String?,
        intent: AccessIntent? = nil
    ) async {
        guard let exposureStore, let decisionID else { return }
        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        let previewText = "[redacted \(exposureType), \(data.count) bytes]"
        let exposure = ExposureRecord(
            connectionID: runtimeContext.connectionID,
            agent: agentName,
            toolName: toolName,
            resourcePath: resourcePath,
            byteCount: data.count,
            contentHash: hash,
            exposureType: exposureType,
            accessDecisionID: decisionID,
            payloadPreview: previewText,
            payloadPreviewTruncated: false,
            clientIdentity: clientIdentityJSON(),
            intentSummary: intent?.summary,
            intentDetails: intent?.details
        )
        do {
            try await exposureStore.recordExposure(exposure)
        } catch {
            logger.error("Failed to record exposure: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func classifyPrivacyContentKind(
        toolName: String,
        resourcePath: String?,
        text: String
    ) -> PrivacyContentKind {
        switch toolName {
        case "diff_file":
            return .diff
        case "read_email", "search_emails":
            return .email
        case "search_files":
            return .snippet
        case "search_structured":
            return .structuredResult
        case "extract_file":
            return .archiveEntry
        default:
            break
        }

        let path = resourcePath?.lowercased() ?? ""
        let ext = (path as NSString).pathExtension.lowercased()
        let codeExtensions: Set<String> = [
            "c", "cc", "cpp", "cs", "css", "go", "h", "hpp", "html", "java", "js", "json",
            "kt", "m", "mdx", "mm", "php", "pl", "py", "rb", "rs", "scss", "sh", "sql",
            "swift", "ts", "tsx", "vue", "xml", "yaml", "yml"
        ]
        let logExtensions: Set<String> = ["log", "trace", "out"]

        if codeExtensions.contains(ext) {
            return .sourceCode
        }
        if logExtensions.contains(ext) {
            return .log
        }
        if toolName == "read_range", codeExtensions.contains(ext) {
            return .sourceCode
        }
        if toolName == "search_structured" {
            return .structuredResult
        }
        if path.contains(".log") || text.contains("INFO ") || text.contains("ERROR ") {
            return .log
        }
        return .document
    }

    private func privacyAuditMetadata(
        for delivery: PrivacyDelivery,
        contentKind: PrivacyContentKind
    ) -> [String: String] {
        [
            "privacy_outcome": delivery.outcome.rawValue,
            "privacy_summary": delivery.findingsSummary,
            "privacy_backend": delivery.backend.rawValue,
            "privacy_model_version": delivery.modelVersion,
            "privacy_content_kind": contentKind.rawValue,
            "privacy_categories": delivery.matchedCategories.map(\.rawValue).joined(separator: ","),
        ]
    }

    private func logPrivacyOutcome(
        resourcePath: String?,
        contentKind: PrivacyContentKind,
        delivery: PrivacyDelivery,
        grantID: String?
    ) async {
        guard delivery.outcome != .clean else { return }
        let metadata = mergedMetadata(privacyAuditMetadata(for: delivery, contentKind: contentKind))
        try? await auditStore.log(
            action: .sensitivityWarning,
            agent: agentName,
            filePath: resourcePath,
            metadata: metadata,
            grantID: grantID
        )
    }

    private func applyPrivacyPreflight(
        toolName: String,
        resourcePath: String?,
        text: String,
        decisionID: String?,
        grantID: String? = nil,
        contentKind: PrivacyContentKind? = nil
    ) async throws -> String {
        guard let privacyCoordinator else { return text }
        let resolvedContentKind = contentKind ?? classifyPrivacyContentKind(
            toolName: toolName,
            resourcePath: resourcePath,
            text: text
        )
        let delivery = try await privacyCoordinator.preflight(
            agent: targetApp,
            toolName: toolName,
            resourcePath: resourcePath,
            text: text,
            contentKind: resolvedContentKind,
            accessDecisionID: decisionID
        )
        await logPrivacyOutcome(
            resourcePath: resourcePath,
            contentKind: resolvedContentKind,
            delivery: delivery,
            grantID: grantID
        )
        let governedDelivery = try await enforcePrivacyRules(
            delivery: delivery,
            toolName: toolName,
            resourcePath: resourcePath,
            contentKind: resolvedContentKind,
            grantID: grantID
        )

        switch governedDelivery.outcome {
        case .clean, .warning, .filtered:
            return governedDelivery.deliveredText ?? text
        case .blocked:
            throw ManifoldMCPError.ruleDenied(
                ruleName: "Privacy Preflight",
                explanation: "Detected secrets or sensitive identifiers and blocked the original payload."
            )
        case .approvalRequired:
            let contextJSON: String?
            if let context = governedDelivery.approvalContext,
               let data = try? JSONEncoder().encode(context) {
                contextJSON = String(data: data, encoding: .utf8)
            } else {
                contextJSON = nil
            }
            _ = try? await approvalQueue?.submit(
                connectionID: runtimeContext.connectionID,
                agent: agentName,
                path: resourcePath ?? toolName,
                action: "read",
                kind: .privacyExposure,
                contextJSON: contextJSON
            )
            throw ManifoldMCPError.privacyReviewRequired(
                "Privacy Preflight needs review before sharing the original. Open Requests in Manifold to share a redacted version or approve the original once."
            )
        }
    }

    private func enforcePrivacyRules(
        delivery: PrivacyDelivery,
        toolName: String,
        resourcePath: String?,
        contentKind: PrivacyContentKind,
        grantID: String?
    ) async throws -> PrivacyDelivery {
        guard let ruleStore else { return delivery }

        switch delivery.outcome {
        case .blocked, .approvalRequired:
            return delivery
        case .clean, .warning, .filtered:
            break
        }

        let request = privacyRuleRequest(
            toolName: toolName,
            resourcePath: resourcePath,
            contentKind: contentKind,
            payloadBytes: delivery.deliveredText?.utf8.count
        )
        let rules: [RuleRecord]
        do {
            rules = try await ruleStore.rules(scope: request.scope).filter { $0.matcher.usesPrivacyProbe }
        } catch {
            logger.error("Privacy rule gate: failed to load rules — \(String(describing: error), privacy: .public)")
            return delivery
        }
        guard !rules.isEmpty else { return delivery }

        let privacyProbe = PrivacyProbe(
            categories: Set(delivery.matchedCategories),
            severity: delivery.severity,
            matchesMyIdentity: false,
            inOrgAllowlist: false
        )
        let context = privacyRuleContext(
            request: request,
            resourcePath: resourcePath,
            payloadBytes: delivery.deliveredText?.utf8.count,
            privacyProbe: privacyProbe
        )
        let decision = RuleEngine().evaluate(
            request,
            against: rules,
            agent: targetApp,
            context: context
        )
        guard decision.action != .allow else { return delivery }

        if let ruleID = decision.matchedRuleID {
            await ruleStore.recordMatch(id: ruleID)
        }
        try? await auditStore.log(
            action: .sensitivityWarning,
            agent: agentName,
            filePath: resourcePath,
            metadata: mergedMetadata([
                "grant_id": grantID ?? "",
                "rule_decision": decision.action.rawValue,
                "matched_rule_id": decision.matchedRuleID ?? "",
                "matched_rule_name": decision.matchedRuleName ?? "",
                "privacy_backend": delivery.backend.rawValue,
                "privacy_model": delivery.modelVersion,
            ]),
            grantID: grantID
        )

        switch decision.action {
        case .deny:
            throw ManifoldMCPError.ruleDenied(
                ruleName: decision.matchedRuleName ?? "Privacy rule",
                explanation: decision.explanation
            )
        case .redact:
            return delivery.replacingDeliveredText(delivery.redactedText, outcome: .filtered)
        case .summarize:
            return delivery.replacingDeliveredText(
                "Privacy summary: \(delivery.findingsSummary)",
                outcome: .filtered
            )
        case .downgrade:
            let categories = delivery.matchedCategories.map(\.displayName).joined(separator: ", ")
            return delivery.replacingDeliveredText(
                "Privacy metadata only: \(categories.isEmpty ? "No sensitive categories" : categories)",
                outcome: .filtered
            )
        case .warn, .log, .allow:
            return delivery
        }
    }

    private func privacyRuleRequest(
        toolName: String,
        resourcePath: String?,
        contentKind: PrivacyContentKind,
        payloadBytes: Int?
    ) -> RuleRequest {
        if contentKind == .email {
            return .emailRead(emailID: resourcePath ?? toolName)
        }
        if let resourcePath {
            return .fileRead(path: resourcePath)
        }
        return .agentTool(tool: .read, payloadBytes: payloadBytes.map(Int64.init))
    }

    private func privacyRuleContext(
        request: RuleRequest,
        resourcePath: String?,
        payloadBytes: Int?,
        privacyProbe: PrivacyProbe
    ) -> RuleEvalContext {
        switch request {
        case .fileRead(let path), .fileWrite(let path):
            return RuleEvalContext(
                fileProbe: FileProbe(path: resourcePath ?? path),
                privacyProbe: privacyProbe
            )
        case .emailRead(let emailID):
            return RuleEvalContext(
                emailProbe: EmailProbe(
                    emailID: emailID,
                    senderEmail: "",
                    senderDomain: "",
                    subject: ""
                ),
                privacyProbe: privacyProbe
            )
        case .agentTool(let tool, let bytes):
            return RuleEvalContext(
                agentProbe: AgentProbe(agent: targetApp, tool: tool, payloadBytes: bytes ?? payloadBytes.map(Int64.init)),
                privacyProbe: privacyProbe
            )
        case .sessionTick:
            return RuleEvalContext(privacyProbe: privacyProbe)
        }
    }

    private func resolveAccessForTool(
        toolName: String,
        action: String,
        resourcePath: String? = nil,
        intent: AccessIntent? = nil
    ) async throws -> (AccessContext, String?) {
        do {
            let context = try await resolveAccess()
            let decision = decisionContext(for: context)
            let decisionID = await recordAccessDecision(
                toolName: toolName,
                resourcePath: resourcePath,
                action: action,
                allowed: true,
                reason: decision.reason,
                accessMode: decision.accessMode,
                policySnapshot: decision.policySnapshot,
                intent: intent
            )
            return (context, decisionID)
        } catch {
            let decision = deniedDecisionContext(for: error)
            _ = await recordAccessDecision(
                toolName: toolName,
                resourcePath: resourcePath,
                action: action,
                allowed: false,
                reason: decision.reason,
                accessMode: decision.accessMode,
                intent: intent
            )
            throw error
        }
    }

    private func validatedAccessIntent(for toolName: String, provided intent: AccessIntent?) async throws -> AccessIntent? {
        let level = (try? await policyStore?.policy(for: targetApp))?.accessRecordingLevel ?? .lightweight
        let sanitized = AccessIntent(
            summary: intent?.summary.map { String($0.prefix(240)) },
            details: intent?.details.map { String($0.prefix(1000)) }
        )

        switch level {
        case .lightweight:
            return sanitized
        case .summary:
            guard sanitized.summary != nil else {
                throw ManifoldMCPError.intentRequired(
                    "\(toolName) requires `intent_summary` because access recording is set to Summary."
                )
            }
            return sanitized
        case .detailed:
            guard sanitized.summary != nil, sanitized.details != nil else {
                throw ManifoldMCPError.intentRequired(
                    "\(toolName) requires both `intent_summary` and `intent_details` because access recording is set to Detailed."
                )
            }
            return sanitized
        }
    }

    private func recordAutomaticSessionNote(
        grant: GrantRecord,
        kind: SessionSummaryKind,
        markdown: String
    ) async {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        _ = try? await grantStore.saveSummary(
            grantID: grant.grantID,
            targetApp: TargetApp(rawValue: grant.targetApp) ?? .cowork,
            startedAt: grant.startedAt,
            endedAt: now,
            markdown: markdown,
            kind: kind,
            origin: .system
        )
        if let summaries = try? await grantStore.summaries(grantID: grant.grantID) {
            try? await artifactIndex.syncSessionSummaries(grantID: grant.grantID, summaries: summaries)
        }
    }

    private func maybeRecordVerboseCheckpointNote(
        grant: GrantRecord,
        canonicalPath: String,
        byteCount: Int
    ) async {
        guard grant.sessionNoteCaptureMode == .verbose else { return }
        let existing = (try? await grantStore.summaries(grantID: grant.grantID, kind: .checkpointNote)) ?? []
        guard existing.isEmpty else { return }

        let modelLabel = runtimeContext.modelHint ?? "unknown"
        let providerLabel = runtimeContext.providerHint ?? "unknown"
        let markdown = """
        # Session Checkpoint Note

        - **Captured by:** Manifold system note
        - **Target app:** \(grant.targetApp)
        - **Checkpoint:** first material change
        - **Changed path:** `\(canonicalPath)`
        - **Bytes written:** \(byteCount)
        - **Provider hint:** \(providerLabel)
        - **Model hint:** \(modelLabel)

        Optional agent follow-up: add a checkpoint note only if the plan changed materially, the task split into phases, or the reason for this change would not be obvious from the file diff.
        """
        await recordAutomaticSessionNote(grant: grant, kind: .checkpointNote, markdown: markdown)
    }

    private func preferredSummary(from summaries: [SessionSummaryRecord]) -> SessionSummaryRecord? {
        summaries.first(where: { $0.kind == .summary })
            ?? summaries.first(where: { $0.kind == .endNote })
            ?? summaries.first
    }

    private func noteGuidance(for grant: GrantRecord, summaries: [SessionSummaryRecord]) -> String? {
        let mode = grant.sessionNoteCaptureMode
        guard mode != .off else { return nil }

        let systemNotes = summaries.filter { $0.kind != .summary && $0.origin == .system }.count
        let agentNotes = summaries.filter { $0.kind != .summary && $0.origin == .agent }.count

        switch mode {
        case .off:
            return nil
        case .basic:
            return "Session notes: BASIC. System start/end notes are captured automatically. Add agent notes only when the objective or final handoff needs extra context. Agent notes: \(agentNotes). System notes: \(systemNotes)."
        case .verbose:
            return "Session notes: VERBOSE. System start, first-write checkpoint, and end notes are captured automatically. Add agent checkpoint notes only for major plan changes or handoff context. Agent notes: \(agentNotes). System notes: \(systemNotes)."
        }
    }

    /// Merges client-provided context into the bridge's runtime metadata.
    public func registerClientContext(initializeParams: [String: Any]) async {
        runtimeContext.mergeInitializeParams(initializeParams)
        guard !connectionLogged else { return }
        connectionLogged = true
        try? await auditStore.log(
            action: .mcpConnection,
            agent: agentName,
            metadata: runtimeContext.connectionMetadata.merging(["event": "connected"]) { _, new in new }
        )
    }

    /// Records the end of a live client connection in the audit trail.
    public func recordDisconnection() async {
        guard connectionLogged else { return }
        try? await auditStore.log(
            action: .mcpConnection,
            agent: agentName,
            metadata: runtimeContext.connectionMetadata.merging([
                "event": "disconnected",
                "disconnected_at": ISO8601DateFormatter.shared.string(from: Date()),
            ]) { _, new in new }
        )
    }

    /// Associates the verified local caller identity with this bridge.
    public func registerVerifiedClientIdentity(_ identity: VerifiedClientIdentity) async {
        runtimeContext.updateVerifiedClientIdentity(identity)
    }

    /// Returns the verified local caller identity for this bridge, if one is known.
    public func verifiedClientIdentity() -> VerifiedClientIdentity? {
        runtimeContext.verifiedClientIdentity
    }

    /// Returns the current coverage snapshot for this bridge.
    public func currentCoverageSnapshot() async -> AgentCoverageSnapshot {
        let verificationStatus = runtimeContext.verifiedClientIdentity?.status ?? .unknown
        let coverageState: CoverageState
        if let workBlockStore,
           let _ = try? await workBlockStore.activeBlock(for: targetApp) {
            coverageState = .trackedWorkspace
        } else if verificationStatus == .verified {
            coverageState = .manifoldRouted
        } else {
            coverageState = .outsideCoverage
        }

        return AgentCoverageSnapshot(
            agent: agentName,
            coverageState: coverageState,
            verificationStatus: verificationStatus,
            hostBundleIdentifier: runtimeContext.verifiedClientIdentity?.hostBundleIdentifier,
            reason: runtimeContext.verifiedClientIdentity?.reason
        )
    }

    /// Returns recent runtime coverage events for this bridge's agent.
    public func recentCoverageEvents(limit: Int = 20) async -> [CoverageEvent] {
        let entries = (try? await auditStore.recentEntries(limit: max(limit * 3, 30))) ?? []
        return entries
            .compactMap { entry in
                guard entry.action == AuditAction.contentDrift.rawValue || entry.action == AuditAction.coverageWarning.rawValue else {
                    return nil
                }
                let metadata = entry.metadata
                    .flatMap { $0.data(using: .utf8) }
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
                return CoverageEvent(
                    id: "\(entry.id)",
                    agent: entry.agent ?? agentName,
                    coverageState: metadata
                        .flatMap { $0["coverage_state"] }
                        .flatMap(CoverageState.init(rawValue:))
                        ?? .outsideCoverage,
                    eventType: metadata?["event_type"] ?? entry.action,
                    message: metadata?["message"] ?? entry.action,
                    resourcePath: entry.filePath,
                    timestamp: entry.timestamp,
                    metadata: entry.metadata
                )
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Access Resolution (dual-path: standing policy + work block grant)

    /// Resolved access context for a tool call.
    /// Standing access: reads go to original source paths (no materialization).
    /// Work block: reads/writes go to materialized workspace via grant.
    enum AccessContext {
        /// Standing access via persistent policy. Files are read from original paths.
        case standing(policy: AgentAccessPolicy, sources: [SourceRecord])
        /// Work block with materialized workspace via grant.
        case workBlock(grant: GrantRecord, grantSources: [GrantSourceRecord], block: WorkBlockRecord)
        /// Legacy grant-only path (no PolicyStore available).
        case legacyGrant(grant: GrantRecord, grantSources: [GrantSourceRecord])
    }

    /// Resolve access for the current agent. Tries standing policy first,
    /// then work block grant, then legacy grant. Fail-closed.
    private func resolveAccess() async throws -> AccessContext {
        // Path 1: Standing access via PolicyStore (v4.1)
        if let policyStore {
            let policy = try await policyStore.policy(for: targetApp)

            // Check pause state first
            if policy.isPaused {
                throw ManifoldMCPError.accessPaused
            }

            // Check for active work block
            if let wbStore = workBlockStore,
               let block = try await wbStore.activeBlock(for: targetApp) {
                // Work block active — route through grant/materialization
                if let grant = try await grantStore.grant(id: block.grantID) {
                    let grantSources = try await grantStore.grantSources(grantID: grant.grantID)
                    try await grantStore.touchGrant(grantID: grant.grantID)
                    return .workBlock(grant: grant, grantSources: grantSources, block: block)
                }
            }

            // Standing access — fail only when neither file policy nor the
            // governed email rule set expose anything to the agent.
            let resolver = try await standingFileVisibilityResolver(for: policy)
            let hasExplicitFileAccess = !resolver.sourceIDsWithAllowOverrides.isEmpty
            if policy.allowedSourceIDs.isEmpty,
               !hasExplicitFileAccess,
               !(try await hasStandingEmailAccess(policy: policy)) {
                throw ManifoldMCPError.noAccessConfigured
            }

            // Resolve allowed source records
            let allSources = try await grantStore.allSources()
            let allowedSources = allSources.filter {
                policy.allowedSourceIDs.contains($0.sourceID)
                    || resolver.sourceIDsWithAllowOverrides.contains($0.sourceID)
            }
            return .standing(policy: policy, sources: allowedSources)
        }

        // Path 2: Legacy grant-only (PolicyStore not injected)
        return try await legacyRequireGrant()
    }

    private func hasStandingEmailAccess(policy: AgentAccessPolicy) async throws -> Bool {
        if policy.defaultEmailPolicy == .allowUnlessBlocked {
            return true
        }

        guard let emailRuleStore, let policyStore else {
            return !policy.allowedEmailDomains.isEmpty
        }

        let ruleSet = try await emailRuleStore.ruleSet(for: policy.agent)
        let hasAllowRules = ruleSet.domainRules.contains { $0.action == .allow }
            || ruleSet.contactRules.contains { $0.action == .allow }
            || ruleSet.keywordRules.contains { $0.action == .allow }
        if hasAllowRules {
            return true
        }

        if !(try await policyStore.temporaryReveals(for: policy.agent)).isEmpty {
            return true
        }

        return (try emailStore.sharedEmailCount()) > 0
    }

    /// Legacy grant resolution — kept for backward compatibility during transition.
    private func legacyRequireGrant() async throws -> AccessContext {
        guard let grant = try await grantStore.activeGrant(targetApp: targetApp, profileID: profileID) else {
            let sources = (try await grantStore.allSources()).filter { !$0.isRemoved }
            if sources.isEmpty {
                throw ManifoldMCPError.noSources
            }
            throw ManifoldMCPError.noActiveSession
        }
        let grantSources = try await grantStore.grantSources(grantID: grant.grantID)
        try await grantStore.touchGrant(grantID: grant.grantID)
        return .legacyGrant(grant: grant, grantSources: grantSources)
    }

    /// Resolve the active grant or throw. Fail-closed: no grant = no access.
    /// Used by tool methods that require grant-specific context (work blocks, sessions).
    private func requireGrant() async throws -> (GrantRecord, [GrantSourceRecord]) {
        let context = try await resolveAccess()
        switch context {
        case .workBlock(let grant, let grantSources, _):
            return (grant, grantSources)
        case .legacyGrant(let grant, let grantSources):
            return (grant, grantSources)
        case .standing:
            // Standing access with no work block — need a grant for grant-specific operations.
            // Try to find an active grant anyway (backward compat).
            if let grant = try await grantStore.activeGrant(targetApp: targetApp, profileID: profileID) {
                let grantSources = try await grantStore.grantSources(grantID: grant.grantID)
                return (grant, grantSources)
            }
            throw ManifoldMCPError.noActiveSession
        }
    }

    private func requireGrantForTool(
        toolName: String,
        action: String,
        resourcePath: String? = nil,
        intent: AccessIntent? = nil
    ) async throws -> (GrantRecord, [GrantSourceRecord], String?) {
        do {
            let (grant, grantSources) = try await requireGrant()
            let decisionID = await recordAccessDecision(
                toolName: toolName,
                resourcePath: resourcePath,
                action: action,
                allowed: true,
                reason: "work_block",
                accessMode: "tracked_run",
                policySnapshot: "{\"grant_id\":\"\(grant.grantID)\"}",
                intent: intent
            )
            return (grant, grantSources, decisionID)
        } catch {
            let decision = deniedDecisionContext(for: error)
            _ = await recordAccessDecision(
                toolName: toolName,
                resourcePath: resourcePath,
                action: action,
                allowed: false,
                reason: decision.reason,
                accessMode: decision.accessMode,
                intent: intent
            )
            throw error
        }
    }

    /// Build mounts for standing access: each source gets a "mount" that points to the original path.
    private func standingMounts(sources: [SourceRecord]) -> [GrantMount] {
        sources.map { source in
            let name = URL(fileURLWithPath: source.originalRootPath).lastPathComponent.lowercased()
            return GrantMount(sourceID: source.sourceID, mountName: name, mountPath: source.originalRootPath)
        }
    }

    /// Resolved mounts + optional grant for read operations.
    /// Standing access: mounts point to original source paths, grantID is nil.
    /// Work block / legacy grant: mounts point to materialized workspace, grantID is set.
    private struct ResolvedMounts {
        let mounts: [GrantMount]
        let grantID: String?
        let grant: GrantRecord?
        let isStanding: Bool
        let decisionID: String?
        let standingPolicy: AgentAccessPolicy?
        let standingResolver: FileVisibilityResolver?
    }

    /// Resolve access and return mounts suitable for file operations.
    /// Handles standing access (original paths) and grant access (materialized paths).
    private func resolveAccessMounts(
        toolName: String,
        action: String,
        resourcePath: String? = nil,
        intent: AccessIntent? = nil
    ) async throws -> ResolvedMounts {
        let (context, decisionID) = try await resolveAccessForTool(
            toolName: toolName,
            action: action,
            resourcePath: resourcePath,
            intent: intent
        )
        switch context {
        case .standing(let policy, let sources):
            let resolver = try await standingFileVisibilityResolver(for: policy)
            return ResolvedMounts(
                mounts: standingMounts(sources: sources),
                grantID: nil,
                grant: nil,
                isStanding: true,
                decisionID: decisionID,
                standingPolicy: policy,
                standingResolver: resolver
            )
        case .workBlock(let grant, let grantSources, _):
            return ResolvedMounts(
                mounts: grantMounts(grant: grant, sources: grantSources),
                grantID: grant.grantID,
                grant: grant,
                isStanding: false,
                decisionID: decisionID,
                standingPolicy: nil,
                standingResolver: nil
            )
        case .legacyGrant(let grant, let grantSources):
            return ResolvedMounts(
                mounts: grantMounts(grant: grant, sources: grantSources),
                grantID: grant.grantID,
                grant: grant,
                isStanding: false,
                decisionID: decisionID,
                standingPolicy: nil,
                standingResolver: nil
            )
        }
    }

    private func standingFileVisibilityResolver(for policy: AgentAccessPolicy) async throws -> FileVisibilityResolver {
        try await fileVisibilityOverrideStore?.resolver(agent: policy.agent) ?? FileVisibilityResolver(overrides: [])
    }

    private func standingFileEvaluation(
        relativePath: String,
        mount: GrantMount,
        access: ResolvedMounts
    ) -> FileVisibilityEvaluation? {
        guard access.isStanding,
              let policy = access.standingPolicy,
              let resolver = access.standingResolver else {
            return nil
        }
        return resolver.evaluate(
            sourceID: mount.sourceID,
            relativePath: relativePath,
            defaultVisible: policy.allowedSourceIDs.contains(mount.sourceID)
        )
    }

    private func assertStandingVisibility(
        relativePath: String,
        mount: GrantMount,
        access: ResolvedMounts,
        originalPath: String
    ) throws {
        guard let evaluation = standingFileEvaluation(relativePath: relativePath, mount: mount, access: access),
              !evaluation.isVisible else {
            return
        }
        throw ManifoldMCPError.fileNotFound(originalPath)
    }

    /// Get mount directories for a grant, including source IDs.
    private func grantMounts(grant: GrantRecord, sources: [GrantSourceRecord]) -> [GrantMount] {
        sources.map { gs in
            let path = URL(fileURLWithPath: grant.materializationRoot)
                .appendingPathComponent(gs.mountName).path
            return GrantMount(sourceID: gs.sourceID, mountName: gs.mountName, mountPath: path)
        }
    }

    private func artifactMounts(from mounts: [GrantMount]) -> [ArtifactMount] {
        mounts.map {
            ArtifactMount(sourceID: $0.sourceID, mountName: $0.mountName, mountPath: $0.mountPath)
        }
    }

    private struct GrantMount {
        let sourceID: String
        let mountName: String
        let mountPath: String
    }

    private enum StandingWriteMode: String {
        case once = "standing_write_once"
        case defaultScope = "standing_write_default"
    }

    private struct ResolvedWriteTarget {
        let mount: GrantMount
        let relativePath: String
        let identity: ScopedFileIdentity
        let canonicalPath: String
    }

    private func ensureIndexed(grant: GrantRecord, mounts: [GrantMount]) async throws {
        try await artifactIndex.ensureGrantIndexed(
            grantID: grant.grantID,
            materializationRoot: grant.materializationRoot,
            mounts: artifactMounts(from: mounts)
        )

        let emails = try await accessibleEmails(grant: grant, limit: 1_000)
        let attachments = try emailStore.emailAttachments(emailIDs: emails.map(\.emailID))
        try await artifactIndex.syncEmails(
            grantID: grant.grantID,
            emails: emails,
            attachments: attachments
        )

        let summaries = try await grantStore.summaries(grantID: grant.grantID)
        try await artifactIndex.syncSessionSummaries(grantID: grant.grantID, summaries: summaries)
    }

    private func accessibleEmails(grant: GrantRecord, limit: Int) async throws -> [EmailMessageRecord] {
        let policy = try await policyStore?.policy(for: targetApp) ?? AgentAccessPolicy(agent: targetApp)
        let context = try await emailPolicyContext(
            policy: policy,
            sensitivity: EmailSensitivityLevel(rawValue: grant.emailSensitivity) ?? policy.emailSensitivity,
            explicitGrantEmailIDs: grant.explicitSelection
                ? Set(try emailStore.grantEmails(grantID: grant.grantID, limit: limit).map(\.emailID))
                : nil
        )
        let allEmails = try emailStore.allEmailMessages(limit: limit)
        return allEmails.filter { email in
            EmailPolicyEngine.decision(for: email, context: context).allowed
        }
    }

    private func accessibleEmails(policy: AgentAccessPolicy, limit: Int) async throws -> [EmailMessageRecord] {
        let context = try await emailPolicyContext(policy: policy, explicitGrantEmailIDs: nil)
        let allEmails = try emailStore.allEmailMessages(limit: limit)
        return allEmails.filter { email in
            EmailPolicyEngine.decision(for: email, context: context).allowed
        }
    }

    private func isEmailAccessible(email: EmailMessageRecord, policy: AgentAccessPolicy) async throws -> Bool {
        let context = try await emailPolicyContext(policy: policy, explicitGrantEmailIDs: nil)
        return EmailPolicyEngine.decision(for: email, context: context).allowed
    }

    private func isEmailAccessible(email: EmailMessageRecord, grant: GrantRecord) async throws -> Bool {
        let policy = try await policyStore?.policy(for: targetApp) ?? AgentAccessPolicy(agent: targetApp)
        let context = try await emailPolicyContext(
            policy: policy,
            sensitivity: EmailSensitivityLevel(rawValue: grant.emailSensitivity) ?? policy.emailSensitivity,
            explicitGrantEmailIDs: grant.explicitSelection
                ? Set(try emailStore.grantEmails(grantID: grant.grantID, limit: 1_000).map(\.emailID))
                : nil
        )
        return EmailPolicyEngine.decision(for: email, context: context).allowed
    }

    private func emailRuleDecision(for email: EmailMessageRecord, policy: AgentAccessPolicy) async throws -> EmailRuleDecision {
        let context = try await emailPolicyContext(policy: policy, explicitGrantEmailIDs: nil)
        return EmailPolicyEngine.decision(for: email, context: context)
    }

    private func emailRuleDecision(for email: EmailMessageRecord, grant: GrantRecord) async throws -> EmailRuleDecision {
        let policy = try await policyStore?.policy(for: targetApp) ?? AgentAccessPolicy(agent: targetApp)
        let context = try await emailPolicyContext(
            policy: policy,
            sensitivity: EmailSensitivityLevel(rawValue: grant.emailSensitivity) ?? policy.emailSensitivity,
            explicitGrantEmailIDs: grant.explicitSelection
                ? Set(try emailStore.grantEmails(grantID: grant.grantID, limit: 1_000).map(\.emailID))
                : nil
        )
        return EmailPolicyEngine.decision(for: email, context: context)
    }

    private func emailPolicyContext(
        policy: AgentAccessPolicy,
        sensitivity: EmailSensitivityLevel? = nil,
        explicitGrantEmailIDs: Set<String>? = nil
    ) async throws -> EmailPolicyEngine.Context {
        let ruleSet = try await emailRuleStore?.ruleSet(for: policy.agent)
            ?? EmailRuleSet(
                agent: policy.agent,
                defaultPolicy: policy.defaultEmailPolicy,
                emailSensitivity: policy.emailSensitivity
            )
        let sharedEmailIDs = try emailStore.sharedEmailIDs(agent: policy.agent)
        let temporaryRevealIDs = Set((try await policyStore?.temporaryReveals(for: policy.agent) ?? []).map(\.emailID))
        return EmailPolicyEngine.Context(
            agent: policy.agent,
            ruleSet: ruleSet,
            policy: policy,
            sharedEmailIDs: sharedEmailIDs,
            temporaryRevealIDs: temporaryRevealIDs,
            explicitGrantEmailIDs: explicitGrantEmailIDs,
            sensitivity: sensitivity ?? ruleSet.emailSensitivity
        )
    }

    private func auditEmailRead(email: EmailMessageRecord, grantID: String?, decision: EmailRuleDecision? = nil) async {
        var metadata = mergedMetadata([
            "type": "email",
            "messageID": email.emailID,
            "grant_id": grantID ?? "",
        ])
        if let decision {
            metadata.merge(decision.metadata) { _, new in new }
        }
        try? await auditStore.log(
            action: .fileRead,
            runID: grantID,
            agent: agentName,
            filePath: email.emlPath,
            metadata: metadata,
            grantID: grantID
        )
    }

    private func messageIDs(from entries: [ManifoldKit.AuditEntry]) -> [String] {
        Array(
            Set(
                entries.compactMap { entry in
                    guard let metadata = entry.metadata?.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: metadata) as? [String: String] else {
                        return nil
                    }
                    return object["messageID"]
                }
            )
        ).sorted()
    }

    // MARK: - Path Safety

    private func cleanPath(_ path: String) -> String {
        var cleaned = path
        while cleaned.hasPrefix("./") { cleaned = String(cleaned.dropFirst(2)) }
        while cleaned.contains("//") { cleaned = cleaned.replacingOccurrences(of: "//", with: "/") }
        while cleaned.hasSuffix("/") && cleaned.count > 1 { cleaned = String(cleaned.dropLast()) }
        return cleaned
    }

    private func validatePath(_ path: String, rootPath: String) throws -> URL {
        do {
            return try ScopedFileAccess.resolve(relativePath: path, rootPath: rootPath).fileURL
        } catch let error as ManifoldError {
            throw ManifoldMCPError.invalidPath(error.localizedDescription)
        } catch {
            throw error
        }
    }

    /// Resolve a cleaned path to a specific mount. Returns nil if no mount prefix matches.
    private func resolveMountAndPath(_ path: String, in mounts: [GrantMount]) -> (GrantMount, String)? {
        for mount in mounts {
            if path.hasPrefix(mount.mountName + "/") {
                let relPath = String(path.dropFirst(mount.mountName.count + 1))
                return (mount, relPath)
            }
        }
        return nil
    }

    private func assertWritableScope(relativePath: String, mount: GrantMount, grant: GrantRecord) async throws {
        guard grant.explicitSelection else { return }
        let scopes = try await grantStore.grantFileScopes(grantID: grant.grantID)
        let allowedScopes = scopes.compactMap { scope -> FileSelectionScope? in
            guard scope.sourceID == mount.sourceID else { return nil }
            return FileSelectionScope(
                sourceID: scope.sourceID,
                relativePath: scope.relativePath,
                isDirectory: scope.isDirectory
            )
        }
        guard !allowedScopes.isEmpty else { return }
        guard FileSelectionScope.allows(relativePath, in: allowedScopes) else {
            throw ManifoldMCPError.invalidPath("Path is outside the approved grant scope")
        }
    }

    private func resolveWriteTarget(_ path: String, in mounts: [GrantMount]) throws -> ResolvedWriteTarget {
        let targetMount: GrantMount
        let resolvedPath: String
        if let (mount, relPath) = resolveMountAndPath(path, in: mounts) {
            targetMount = mount
            resolvedPath = relPath
        } else if mounts.count == 1, let first = mounts.first {
            targetMount = first
            resolvedPath = path
        } else if mounts.count > 1 {
            let (mount, relPath) = try resolveBarePath(path, in: mounts)
            targetMount = mount
            resolvedPath = relPath
        } else {
            throw ManifoldMCPError.noSources
        }

        let identity: ScopedFileIdentity
        do {
            identity = try ScopedFileAccess.resolve(
                relativePath: resolvedPath,
                rootPath: targetMount.mountPath,
                allowMissingLeaf: true
            )
        } catch let error as ManifoldError {
            throw ManifoldMCPError.invalidPath(error.localizedDescription)
        }

        return ResolvedWriteTarget(
            mount: targetMount,
            relativePath: resolvedPath,
            identity: identity,
            canonicalPath: "\(targetMount.mountName)/\(resolvedPath)"
        )
    }

    /// Resolve bare path to a single unambiguous mount. Throws if ambiguous.
    private func resolveBarePath(_ path: String, in mounts: [GrantMount]) throws -> (GrantMount, String) {
        var matches: [(mount: GrantMount, url: URL)] = []
        for mount in mounts {
            if let url = try? validatePath(path, rootPath: mount.mountPath),
               FileManager.default.fileExists(atPath: url.path) {
                matches.append((mount, url))
            }
        }
        switch matches.count {
        case 0:
            throw ManifoldMCPError.fileNotFound(path)
        case 1:
            return (matches[0].mount, path)
        default:
            let names = matches.map(\.mount.mountName).joined(separator: ", ")
            throw ManifoldMCPError.invalidPath("Ambiguous path '\(path)' exists in multiple sources: \(names). Use mount-prefixed path (e.g. '\(matches[0].mount.mountName)/\(path)').")
        }
    }

    // MARK: - Tool Audit

    private func logToolCall(tool: String, arguments: [String: Any] = [:]) async {
        let argsJSON = arguments.isEmpty ? "{}" : (arguments.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
        try? await auditStore.log(
            action: .toolCall,
            agent: agentName,
            metadata: mergedMetadata(["tool": tool, "arguments": argsJSON])
        )
    }

    // MARK: - Tools

    /// Returns the current governed status summary for this bridge.
    public func getStatus() async -> StatusResult {
        await logToolCall(tool: "get_status")
        do {
            let (context, decisionID) = try await resolveAccessForTool(toolName: "get_status", action: "read")
            switch context {
            case .standing(let policy, let sources):
                let sourceNames = sources.map(\.displayName).joined(separator: ", ")
                // Use cached file list for count (avoids full enumeration on every getStatus)
                let mounts = standingMounts(sources: sources)
                let resolver = try? await standingFileVisibilityResolver(for: policy)
                let totalFiles = (try? listFilesFromOriginals(mounts: mounts, policy: policy, resolver: resolver).count) ?? 0
                let emailCount = (try? await accessibleEmails(policy: policy, limit: 5_000).count) ?? 0
                let message = "Manifold standing access active. \(sources.count) source(s): \(sourceNames). \(totalFiles) files, \(emailCount) emails. Sensitivity: \(policy.emailSensitivity.rawValue)."
                let status = StatusResult(
                    active: true,
                    grantID: nil,
                    sources: sources.map(\.displayName),
                    pausedSources: [],
                    fileCount: totalFiles,
                    emailCount: emailCount,
                    message: message,
                    noteCaptureMode: SessionNoteCaptureMode.off.rawValue,
                    noteGuidance: nil
                )
                await recordExposure(toolName: "get_status", resourcePath: nil, text: message, exposureType: "snippet", decisionID: decisionID)
                return status

            case .workBlock(let grant, let grantSources, let block):
                let mounts = grantMounts(grant: grant, sources: grantSources)
                try await ensureIndexed(grant: grant, mounts: mounts)
                let totalFiles = (try? await artifactIndex.fileCount(grantID: grant.grantID)) ?? 0
                let emailCount = (try? await accessibleEmails(grant: grant, limit: 5_000).count) ?? 0
                let summaries = (try? await grantStore.summaries(grantID: grant.grantID)) ?? []
                let noteGuidance = noteGuidance(for: grant, summaries: summaries)
                let sourceNames = mounts.map(\.mountName).joined(separator: ", ")
                let blockStatus = block.isPaused ? " (paused)" : ""
                let message = "Manifold work block active\(blockStatus) (grant \(grant.grantID.prefix(12))...). \(mounts.count) source(s): \(sourceNames). \(totalFiles) files, \(emailCount) emails."
                let status = StatusResult(
                    active: true,
                    grantID: grant.grantID,
                    sources: mounts.map(\.mountName),
                    pausedSources: [],
                    fileCount: totalFiles,
                    emailCount: emailCount,
                    message: message,
                    noteCaptureMode: grant.noteCaptureMode,
                    noteGuidance: noteGuidance
                )
                await recordExposure(toolName: "get_status", resourcePath: grant.grantID, text: message, exposureType: "snippet", decisionID: decisionID)
                return status

            case .legacyGrant(let grant, let grantSources):
                let mounts = grantMounts(grant: grant, sources: grantSources)
                try await ensureIndexed(grant: grant, mounts: mounts)
                let totalFiles = (try? await artifactIndex.fileCount(grantID: grant.grantID)) ?? 0
                let emailCount = (try? await accessibleEmails(grant: grant, limit: 5_000).count) ?? 0
                let summaries = (try? await grantStore.summaries(grantID: grant.grantID)) ?? []
                let noteGuidance = noteGuidance(for: grant, summaries: summaries)
                let sourceNames = mounts.map(\.mountName).joined(separator: ", ")
                let message = "Manifold active (grant \(grant.grantID.prefix(12))...). \(mounts.count) source(s): \(sourceNames). \(totalFiles) files, \(emailCount) emails backed up."
                let status = StatusResult(
                    active: true,
                    grantID: grant.grantID,
                    sources: mounts.map(\.mountName),
                    pausedSources: [],
                    fileCount: totalFiles,
                    emailCount: emailCount,
                    message: message,
                    noteCaptureMode: grant.noteCaptureMode,
                    noteGuidance: noteGuidance
                )
                await recordExposure(toolName: "get_status", resourcePath: grant.grantID, text: message, exposureType: "snippet", decisionID: decisionID)
                return status
            }
        } catch ManifoldMCPError.accessPaused {
            return StatusResult(
                active: false, grantID: nil, sources: [], pausedSources: [],
                fileCount: 0, emailCount: 0,
                message: "Access is paused. Resume access in Manifold to continue.",
                noteCaptureMode: SessionNoteCaptureMode.off.rawValue,
                noteGuidance: nil
            )
        } catch ManifoldMCPError.noAccessConfigured {
            let sources = (try? await grantStore.allSources()) ?? []
            return StatusResult(
                active: false, grantID: nil,
                sources: sources.filter(\.isAccessible).map(\.displayName),
                pausedSources: sources.filter(\.isPaused).map(\.displayName),
                fileCount: 0, emailCount: 0,
                message: "No access configured. Use Review & Update Access in Manifold to grant file or email access.",
                noteCaptureMode: SessionNoteCaptureMode.off.rawValue,
                noteGuidance: nil
            )
        } catch ManifoldMCPError.noActiveSession {
            let sources = (try? await grantStore.allSources()) ?? []
            let paused = sources.filter(\.isPaused)
            let active = sources.filter(\.isAccessible)
            return StatusResult(
                active: false,
                grantID: nil,
                sources: active.map(\.displayName),
                pausedSources: paused.map(\.displayName),
                fileCount: 0,
                emailCount: 0,
                message: "No active session. \(active.count) source(s) configured. Start a session in Manifold to grant access.",
                noteCaptureMode: SessionNoteCaptureMode.off.rawValue,
                noteGuidance: nil
            )
        } catch {
            return StatusResult(
                active: false, grantID: nil, sources: [], pausedSources: [], fileCount: 0, emailCount: 0,
                message: "Error: \(error.localizedDescription)",
                noteCaptureMode: SessionNoteCaptureMode.off.rawValue,
                noteGuidance: nil
            )
        }
    }

    /// Lists the governed files currently visible through this bridge.
    public func listFiles(intent: AccessIntent? = nil) async throws -> [FileInfo] {
        await logToolCall(tool: "list_files")
        let validatedIntent = try await validatedAccessIntent(for: "list_files", provided: intent)
        let resolved = try await resolveAccessMounts(toolName: "list_files", action: "list", intent: validatedIntent)
        let files: [FileInfo]

        // Standing access: enumerate files from original source paths
        if resolved.isStanding {
            files = try listFilesFromOriginals(
                mounts: resolved.mounts,
                policy: resolved.standingPolicy,
                resolver: resolved.standingResolver
            )
        } else {
            // Grant-based: use artifact index
            guard let grant = resolved.grant else { throw ManifoldMCPError.noActiveSession }
            try await ensureIndexed(grant: grant, mounts: resolved.mounts)
            let artifacts = try await artifactIndex.listFiles(grantID: grant.grantID)
            files = artifacts.map { handle in
                let relative = handle.path.hasPrefix(handle.mountName + "/")
                    ? String(handle.path.dropFirst(handle.mountName.count + 1))
                    : handle.path
                return FileInfo(
                    path: relative,
                    sourceName: handle.mountName,
                    sourceAddedAt: grant.startedAt,
                    sizeBytes: handle.sizeBytes,
                    lastModified: handle.lastModified
                )
            }
        }
        let serialized = files.map { "\($0.sourceName)/\($0.path)" }.joined(separator: "\n")
        await recordExposure(toolName: "list_files", resourcePath: nil, text: serialized, exposureType: "snippet", decisionID: resolved.decisionID, intent: validatedIntent)
        return files
    }

    // MARK: - File Enumeration Cache

    private var fileListCache: (entries: [FileInfo], timestamp: Date, mountPaths: Set<String>, visibilityKey: String)?
    private let fileListCacheTTL: TimeInterval = 10

    /// List files from original source paths with 10-second TTL cache.
    /// Avoids re-enumerating 5,000+ files on every list_files MCP call.
    private func listFilesFromOriginals(
        mounts: [GrantMount],
        policy: AgentAccessPolicy? = nil,
        resolver: FileVisibilityResolver? = nil
    ) throws -> [FileInfo] {
        let currentPaths = Set(mounts.map(\.mountPath))
        let visibilityKey = cacheKey(policy: policy, resolver: resolver)
        if let cache = fileListCache,
           Date().timeIntervalSince(cache.timestamp) < fileListCacheTTL,
           cache.mountPaths == currentPaths,
           cache.visibilityKey == visibilityKey {
            return cache.entries
        }
        let files = try enumerateOriginalFiles(mounts: mounts, policy: policy, resolver: resolver)
        fileListCache = (files, Date(), currentPaths, visibilityKey)
        return files
    }

    private func cacheKey(policy: AgentAccessPolicy?, resolver: FileVisibilityResolver?) -> String {
        let allowed = policy?.allowedSourceIDs.sorted().joined(separator: ",") ?? ""
        let overrideKey = resolver?.cacheKey ?? ""
        return "\(allowed)|\(overrideKey)"
    }

    /// Actual file enumeration — only called when cache is stale or mount set changed.
    private func enumerateOriginalFiles(
        mounts: [GrantMount],
        policy: AgentAccessPolicy? = nil,
        resolver: FileVisibilityResolver? = nil
    ) throws -> [FileInfo] {
        let fm = FileManager.default
        var files: [FileInfo] = []
        let now = ISO8601DateFormatter.shared.string(from: Date())

        for mount in mounts {
            let rootURL = URL(fileURLWithPath: mount.mountPath).standardizedFileURL
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let basePath = rootURL.path + "/"
            while let fileURL = enumerator.nextObject() as? URL {
                let filePath = fileURL.standardizedFileURL.path
                guard filePath.hasPrefix(basePath) else { continue }
                let relativePath = String(filePath.dropFirst(basePath.count))

                // Skip noise directories
                let firstComponent = relativePath.split(separator: "/").first.map(String.init) ?? relativePath
                let skip = [".git", ".svn", "node_modules", ".build", "Build", "DerivedData",
                            "Pods", "__pycache__", ".venv", ".DS_Store"]
                if skip.contains(firstComponent) {
                    if fileURL.hasDirectoryPath { enumerator.skipDescendants() }
                    continue
                }

                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }

                if let policy, let resolver {
                    let evaluation = resolver.evaluate(
                        sourceID: mount.sourceID,
                        relativePath: relativePath,
                        defaultVisible: policy.allowedSourceIDs.contains(mount.sourceID)
                    )
                    guard evaluation.isVisible else { continue }
                }

                let modified = values.contentModificationDate.map {
                    ISO8601DateFormatter.shared.string(from: $0)
                } ?? now

                files.append(FileInfo(
                    path: "\(mount.mountName)/\(relativePath)",
                    sourceName: mount.mountName,
                    sourceAddedAt: now,
                    sizeBytes: values.fileSize ?? 0,
                    lastModified: modified
                ))
            }
        }
        return files
    }

    // MARK: - Read File (P1 FIX: reject ambiguous bare paths)

    /// Reads a governed file through the active access context.
    public func readFile(path: String, intent: AccessIntent? = nil) async throws -> String {
        await logToolCall(tool: "read_file", arguments: ["path": path])
        let validatedIntent = try await validatedAccessIntent(for: "read_file", provided: intent)
        let resolved = try await resolveAccessMounts(toolName: "read_file", action: "read", resourcePath: path, intent: validatedIntent)
        let mounts = resolved.mounts
        let cleaned = cleanPath(path)

        // For grant-based access, ensure indexed
        if let grant = resolved.grant {
            try await ensureIndexed(grant: grant, mounts: mounts)
        }

        let grantID = resolved.grantID ?? "standing"

        // Try mount-prefixed resolution first (e.g. "MyProject/src/main.swift")
        if let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) {
            try assertStandingVisibility(relativePath: relPath, mount: mount, access: resolved, originalPath: cleaned)
            return try await readFromMount(
                relativePath: relPath,
                mountPath: mount.mountPath,
                mountName: mount.mountName,
                grantID: grantID,
                decisionID: resolved.decisionID,
                intent: validatedIntent
            )
        }

        // Bare path: resolve unambiguously or reject
        let (mount, relPath) = try resolveBarePath(cleaned, in: mounts)
        try assertStandingVisibility(relativePath: relPath, mount: mount, access: resolved, originalPath: cleaned)
        return try await readFromMount(
            relativePath: relPath,
            mountPath: mount.mountPath,
            mountName: mount.mountName,
            grantID: grantID,
            decisionID: resolved.decisionID,
            intent: validatedIntent
        )
    }

    private func readFromMount(
        relativePath: String,
        mountPath: String,
        mountName: String,
        grantID: String,
        decisionID: String?,
        intent: AccessIntent?
    ) async throws -> String {
        let identity: ScopedFileIdentity
        do {
            identity = try ScopedFileAccess.resolve(relativePath: relativePath, rootPath: mountPath)
        } catch let error as ManifoldError {
            throw ManifoldMCPError.invalidPath(error.localizedDescription)
        }
        let canonicalPath = "\(mountName)/\(relativePath)"

        // Rule gate — consult the unified rule catalog before reading.
        try await enforceFileReadRules(fileURL: identity.fileURL, canonicalPath: canonicalPath, grantID: grantID)

        let artifact = try await artifactIndex.artifact(grantID: grantID, canonicalPath: canonicalPath)
        let read = try ContextEngine.read(
            fileURL: identity.fileURL,
            selection: artifact?.selection
        )
        let deliveredText = try await applyPrivacyPreflight(
            toolName: "read_file",
            resourcePath: canonicalPath,
            text: read.text,
            decisionID: decisionID,
            grantID: grantID
        )

        try? await auditStore.log(
            action: .fileRead,
            agent: agentName,
            filePath: canonicalPath,
            metadata: mergedMetadata([
                "grant_id": grantID,
                "mount": mountName,
                "bytes": "\(deliveredText.utf8.count)",
                "truncated": read.truncated ? "true" : "false",
            ]),
            grantID: grantID
        )
        await recordExposure(toolName: "read_file", resourcePath: canonicalPath, text: deliveredText, exposureType: "full_file", decisionID: decisionID, intent: intent)
        return deliveredText
    }

    /// Consults `RuleStore` / `RuleEngine` for a `fileRead` request. Throws `ManifoldMCPError.ruleDenied`
    /// if a rule blocks the read; logs a `.warn`/`.redact`/etc. outcome but allows the read to continue.
    /// Best-effort — if `ruleStore` is absent (test bridge) or fails, the read proceeds.
    private func enforceFileReadRules(fileURL: URL, canonicalPath: String, grantID: String) async throws {
        guard let ruleStore else { return }
        let rules: [RuleRecord]
        do {
            rules = try await ruleStore.rules(scope: .file)
        } catch {
            logger.error("Rule gate: failed to load file rules — \(String(describing: error), privacy: .public)")
            return
        }
        guard !rules.isEmpty else { return }

        let probe = Self.makeFileProbe(url: fileURL, canonicalPath: canonicalPath)
        let context = RuleEvalContext(fileProbe: probe)
        let decision = RuleEngine().evaluate(
            .fileRead(path: canonicalPath),
            against: rules,
            agent: targetApp,
            context: context
        )

        switch decision.action {
        case .deny:
            if let ruleID = decision.matchedRuleID {
                await ruleStore.recordMatch(id: ruleID)
            }
            try? await auditStore.log(
                action: .fileRead,
                agent: agentName,
                filePath: canonicalPath,
                metadata: mergedMetadata([
                    "grant_id": grantID,
                    "rule_decision": "deny",
                    "matched_rule_id": decision.matchedRuleID ?? "",
                    "matched_rule_name": decision.matchedRuleName ?? "",
                ]),
                grantID: grantID
            )
            throw ManifoldMCPError.ruleDenied(
                ruleName: decision.matchedRuleName ?? "rule",
                explanation: decision.explanation
            )
        case .warn, .redact, .summarize, .downgrade, .log:
            if let ruleID = decision.matchedRuleID {
                await ruleStore.recordMatch(id: ruleID)
            }
            try? await auditStore.log(
                action: .fileRead,
                agent: agentName,
                filePath: canonicalPath,
                metadata: mergedMetadata([
                    "grant_id": grantID,
                    "rule_decision": decision.action.rawValue,
                    "matched_rule_id": decision.matchedRuleID ?? "",
                    "matched_rule_name": decision.matchedRuleName ?? "",
                ]),
                grantID: grantID
            )
        case .allow:
            break
        }
    }

    /// Builds a lazy `FileProbe` for a file URL. `sizeBytes`, `isHidden`, and `containsSecret`
    /// are computed on demand so rules that never need them don't pay the cost.
    nonisolated private static func makeFileProbe(url: URL, canonicalPath: String) -> FileProbe {
        FileProbe(
            path: canonicalPath,
            sizeBytes: {
                (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) }
            },
            modifiedAt: {
                try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            },
            isHidden: {
                url.lastPathComponent.hasPrefix(".")
            },
            isBinary: {
                guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
                defer { try? handle.close() }
                let chunk = (try? handle.read(upToCount: 512)) ?? Data()
                return chunk.contains(0)
            },
            isGitignored: { false },
            containsSecret: {
                // Cheap heuristic: read up to 64KB and test for AWS/GitHub/JWT/private-key patterns.
                guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
                defer { try? handle.close() }
                let chunk = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
                guard let text = String(data: chunk, encoding: .utf8) else { return false }
                let needles = [
                    "AKIA",                               // AWS access key prefix
                    "-----BEGIN PRIVATE KEY-----",
                    "-----BEGIN RSA PRIVATE KEY-----",
                    "-----BEGIN OPENSSH PRIVATE KEY-----",
                    "ghp_",                               // GitHub personal access token
                    "ghs_",                               // GitHub server-to-server
                    "xoxb-",                              // Slack bot token
                    "xoxp-",                              // Slack user token
                ]
                if needles.contains(where: { text.contains($0) }) { return true }
                // Bearer JWT heuristic: 3 base64 segments separated by dots.
                if text.range(of: #"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#, options: .regularExpression) != nil {
                    return true
                }
                return false
            }
        )
    }

    // MARK: - Write File (P1 FIX: record snapshots, use canonical paths, reject ambiguous)

    /// Escalates file writes into tracked work instead of mutating originals directly.
    public func writeFile(path: String, content: String) async throws -> WriteResult {
        await logToolCall(tool: "write_file", arguments: ["path": path, "content_length": "\(content.count)"])
        let cleaned = cleanPath(path)

        guard !cleaned.hasPrefix("_emails/") else {
            throw ManifoldMCPError.invalidPath("Cannot write to email files (read-only)")
        }

        let accessContext: AccessContext
        do {
            accessContext = try await resolveAccess()
        } catch {
            let denied = deniedDecisionContext(for: error)
            _ = await recordAccessDecision(
                toolName: "write_file",
                resourcePath: cleaned,
                action: "write",
                allowed: false,
                reason: denied.reason,
                accessMode: denied.accessMode
            )
            throw error
        }

        let data = content.data(using: .utf8) ?? Data()
        let accessDecisionID: String?
        let access: ResolvedMounts
        let writeID: String
        let writeSource: String
        let writeGrantID: String?
        let writeTarget: ResolvedWriteTarget

        switch accessContext {
        case .standing(let policy, let sources):
            let mounts = standingMounts(sources: sources)
            let target = try resolveWriteTarget(cleaned, in: mounts)
            let visibilityResolver = try await standingFileVisibilityResolver(for: policy)
            let visibility = visibilityResolver.evaluate(
                sourceID: target.mount.sourceID,
                relativePath: target.relativePath,
                defaultVisible: policy.allowedSourceIDs.contains(target.mount.sourceID)
            )
            guard visibility.isVisible else {
                _ = await recordAccessDecision(
                    toolName: "write_file",
                    resourcePath: target.canonicalPath,
                    action: "write",
                    allowed: false,
                    reason: "standing_access",
                    accessMode: "standing",
                    policySnapshot: policySnapshot(for: policy)
                )
                throw ManifoldMCPError.fileNotFound(target.canonicalPath)
            }
            guard policy.allowedSourceIDs.contains(target.mount.sourceID) else {
                _ = await recordAccessDecision(
                    toolName: "write_file",
                    resourcePath: target.canonicalPath,
                    action: "write",
                    allowed: false,
                    reason: "standing_access",
                    accessMode: "standing",
                    policySnapshot: policySnapshot(for: policy)
                )
                throw ManifoldMCPError.invalidPath("Standing writes require the folder to remain in default scope. Explicit file overrides are read-only until a tracked session starts.")
            }
            let defaultApproved = try await standingWriteApprovalStore?.hasDefaultGrant(
                agent: targetApp,
                sourceID: target.mount.sourceID
            ) ?? false
            let onceApproved: Bool
            if defaultApproved {
                onceApproved = false
            } else {
                onceApproved = try await standingWriteApprovalStore?.consumeOnce(
                    agent: targetApp,
                    sourceID: target.mount.sourceID,
                    relativePath: target.relativePath
                ) ?? false
            }

            guard defaultApproved || onceApproved else {
                _ = try? await approvalQueue?.submit(
                    connectionID: runtimeContext.connectionID,
                    agent: agentName,
                    path: target.canonicalPath,
                    action: "write",
                    kind: .standingWrite,
                    sourceID: target.mount.sourceID,
                    mountName: target.mount.mountName,
                    relativePath: target.relativePath
                )
                _ = await recordAccessDecision(
                    toolName: "write_file",
                    resourcePath: target.canonicalPath,
                    action: "write",
                    allowed: false,
                    reason: "standing_access",
                    accessMode: "standing",
                    policySnapshot: policySnapshot(for: policy)
                )
                return .escalationRequired(
                    message: "Always-on access reads by default. Approve one reversible write for this file, or add reversible write access for this shared folder through Manifold.",
                    path: target.canonicalPath
                )
            }

            accessDecisionID = await recordAccessDecision(
                toolName: "write_file",
                resourcePath: target.canonicalPath,
                action: "write",
                allowed: true,
                reason: "standing_access",
                accessMode: defaultApproved ? StandingWriteMode.defaultScope.rawValue : StandingWriteMode.once.rawValue,
                policySnapshot: policySnapshot(for: policy)
            )
            access = ResolvedMounts(
                mounts: mounts,
                grantID: nil,
                grant: nil,
                isStanding: true,
                decisionID: accessDecisionID,
                standingPolicy: policy,
                standingResolver: visibilityResolver
            )
            writeID = "standing-write:\(target.mount.sourceID)"
            writeSource = defaultApproved ? StandingWriteMode.defaultScope.rawValue : StandingWriteMode.once.rawValue
            writeGrantID = nil
            writeTarget = target

        case .workBlock(let grant, let grantSources, _):
            accessDecisionID = await recordAccessDecision(
                toolName: "write_file",
                resourcePath: cleaned,
                action: "write",
                allowed: true,
                reason: "work_block",
                accessMode: "tracked_run"
            )
            access = ResolvedMounts(
                mounts: grantMounts(grant: grant, sources: grantSources),
                grantID: grant.grantID,
                grant: grant,
                isStanding: false,
                decisionID: accessDecisionID,
                standingPolicy: nil,
                standingResolver: nil
            )
            let target = try resolveWriteTarget(cleaned, in: access.mounts)
            try await assertWritableScope(relativePath: target.relativePath, mount: target.mount, grant: grant)
            writeID = grant.grantID
            writeSource = "mcp"
            writeGrantID = grant.grantID
            writeTarget = target

        case .legacyGrant(let grant, let grantSources):
            accessDecisionID = await recordAccessDecision(
                toolName: "write_file",
                resourcePath: cleaned,
                action: "write",
                allowed: true,
                reason: "work_block",
                accessMode: "tracked_run"
            )
            access = ResolvedMounts(
                mounts: grantMounts(grant: grant, sources: grantSources),
                grantID: grant.grantID,
                grant: grant,
                isStanding: false,
                decisionID: accessDecisionID,
                standingPolicy: nil,
                standingResolver: nil
            )
            let target = try resolveWriteTarget(cleaned, in: access.mounts)
            try await assertWritableScope(relativePath: target.relativePath, mount: target.mount, grant: grant)
            writeID = grant.grantID
            writeSource = "mcp"
            writeGrantID = grant.grantID
            writeTarget = target
        }

        let targetMount = writeTarget.mount
        let resolvedPath = writeTarget.relativePath
        let targetIdentity = writeTarget.identity
        let canonicalPath = writeTarget.canonicalPath

        let existed = targetIdentity.exists
        if access.isStanding,
           existed,
           try await snapshotStore.latestHash(runID: writeID, filePath: canonicalPath) == nil {
            let existingData = try ScopedFileAccess.readData(
                relativePath: resolvedPath,
                rootPath: targetMount.mountPath
            ).data
            try await snapshotStore.recordBaseline(
                runID: writeID,
                workspaceID: targetMount.sourceID,
                filePath: canonicalPath,
                data: existingData
            )
        }
        let writtenIdentity: ScopedFileIdentity
        do {
            writtenIdentity = try ScopedFileAccess.writeDataAtomically(
                data,
                relativePath: resolvedPath,
                rootPath: targetMount.mountPath
            )
        } catch let error as ManifoldError {
            throw ManifoldMCPError.invalidPath(error.localizedDescription)
        }

        if let grant = access.grant {
            try await artifactIndex.upsertFile(
                grantID: grant.grantID,
                mount: ArtifactMount(sourceID: targetMount.sourceID, mountName: targetMount.mountName, mountPath: targetMount.mountPath),
                relativePath: resolvedPath,
                fileURL: writtenIdentity.fileURL
            )
        }

        let snapshot = try await snapshotStore.recordModification(
            runID: writeID,
            workspaceID: targetMount.sourceID,
            filePath: canonicalPath,
            newData: data,
            source: writeSource
        )

        var writeMetadata = mergedMetadata([
            "mount": targetMount.mountName,
            "bytes": "\(data.count)",
            "snapshot_id": "\(snapshot.id)",
            "access_mode": access.isStanding ? writeSource : "tracked_run",
        ])
        if let writeGrantID {
            writeMetadata["grant_id"] = writeGrantID
        }

        try? await auditStore.log(
            action: existed ? .fileModified : .fileCreated,
            runID: writeID,
            workspaceID: targetMount.sourceID,
            agent: agentName,
            filePath: canonicalPath,
            beforeHash: snapshot.beforeHash,
            afterHash: snapshot.afterHash,
            metadata: writeMetadata,
            grantID: writeGrantID
        )
        if let grant = access.grant {
            await maybeRecordVerboseCheckpointNote(
                grant: grant,
                canonicalPath: canonicalPath,
                byteCount: data.count
            )
        }
        return .written(message: "Wrote \(data.count) bytes to \(canonicalPath)", path: canonicalPath)
    }

    public func searchFiles(query: String, intent: AccessIntent? = nil) async throws -> [(path: String, source: String, matches: [String])] {
        await logToolCall(tool: "search_files", arguments: ["query": query])
        let validatedIntent = try await validatedAccessIntent(for: "search_files", provided: intent)
        let resolved = try await resolveAccessMounts(toolName: "search_files", action: "search", intent: validatedIntent)
        let results: [(path: String, source: String, matches: [String])]

        // Standing access: grep through original source files
        if resolved.isStanding {
            results = try searchFilesInOriginals(
                query: query,
                mounts: resolved.mounts,
                policy: resolved.standingPolicy,
                resolver: resolved.standingResolver
            )
        } else {
            // Grant-based: use artifact index
            guard let grant = resolved.grant else { throw ManifoldMCPError.noActiveSession }
            try await ensureIndexed(grant: grant, mounts: resolved.mounts)
            let hits = try await artifactIndex.search(grantID: grant.grantID, query: query)
            results = hits.map { hit in
                let relative = hit.handle.path.hasPrefix(hit.handle.mountName + "/")
                    ? String(hit.handle.path.dropFirst(hit.handle.mountName.count + 1))
                    : hit.handle.path
                return (
                    path: hit.handle.path,
                    source: hit.handle.mountName,
                    matches: hit.preview.isEmpty ? [relative] : hit.preview
                )
            }
        }
        var deliveredResults: [(path: String, source: String, matches: [String])] = []
        for result in results {
            var deliveredMatches: [String] = []
            for snippet in result.matches {
                do {
                    let deliveredSnippet = try await applyPrivacyPreflight(
                        toolName: "search_files",
                        resourcePath: result.path,
                        text: snippet,
                        decisionID: resolved.decisionID,
                        grantID: resolved.grantID,
                        contentKind: .snippet
                    )
                    deliveredMatches.append(deliveredSnippet)
                    await recordExposure(
                        toolName: "search_files",
                        resourcePath: result.path,
                        text: deliveredSnippet,
                        exposureType: "snippet",
                        decisionID: resolved.decisionID,
                        intent: validatedIntent
                    )
                } catch {
                    continue
                }
            }
            if !deliveredMatches.isEmpty {
                deliveredResults.append((path: result.path, source: result.source, matches: deliveredMatches))
            }
        }
        return deliveredResults
    }

    /// Search files directly in original source paths (standing access).
    private func searchFilesInOriginals(
        query: String,
        mounts: [GrantMount],
        policy: AgentAccessPolicy? = nil,
        resolver: FileVisibilityResolver? = nil
    ) throws -> [(path: String, source: String, matches: [String])] {
        let fm = FileManager.default
        let queryLower = query.lowercased()
        var results: [(path: String, source: String, matches: [String])] = []

        for mount in mounts {
            let rootURL = URL(fileURLWithPath: mount.mountPath)
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let basePath = rootURL.path + "/"
            while let fileURL = enumerator.nextObject() as? URL {
                guard fileURL.path.hasPrefix(basePath) else { continue }
                let relativePath = String(fileURL.path.dropFirst(basePath.count))

                let firstComponent = relativePath.split(separator: "/").first.map(String.init) ?? relativePath
                let skip = [".git", "node_modules", ".build", "Build", "DerivedData",
                            "Pods", "__pycache__", ".DS_Store"]
                if skip.contains(firstComponent) {
                    if fileURL.hasDirectoryPath { enumerator.skipDescendants() }
                    continue
                }

                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true else { continue }

                if let policy, let resolver {
                    let evaluation = resolver.evaluate(
                        sourceID: mount.sourceID,
                        relativePath: relativePath,
                        defaultVisible: policy.allowedSourceIDs.contains(mount.sourceID)
                    )
                    guard evaluation.isVisible else { continue }
                }

                // Read file and search
                guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
                      data.count < 1_000_000,
                      let content = String(data: data, encoding: .utf8) else { continue }

                let lines = content.components(separatedBy: .newlines)
                var matchLines: [String] = []
                for (i, line) in lines.enumerated() {
                    if line.lowercased().contains(queryLower) {
                        matchLines.append("L\(i+1): \(line.prefix(200))")
                    }
                    if matchLines.count >= 5 { break }
                }

                if !matchLines.isEmpty {
                    results.append((
                        path: "\(mount.mountName)/\(relativePath)",
                        source: mount.mountName,
                        matches: matchLines
                    ))
                }
                if results.count >= 50 { return results }
            }
        }
        return results
    }

    // MARK: - File Info

    public func fileInfo(path: String, intent: AccessIntent? = nil) async throws -> FileInfoDetail {
        await logToolCall(tool: "file_info", arguments: ["path": path])
        let validatedIntent = try await validatedAccessIntent(for: "file_info", provided: intent)
        let access = try await resolveAccessMounts(toolName: "file_info", action: "read", resourcePath: path, intent: validatedIntent)
        let mounts = access.mounts
        if let grant = access.grant {
            try await ensureIndexed(grant: grant, mounts: mounts)
        }
        let cleaned = cleanPath(path)
        let grantID = access.grantID ?? "standing"

        let mountPath: String
        let mountName: String
        let resolvedPath: String

        if let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) {
            mountPath = mount.mountPath
            mountName = mount.mountName
            resolvedPath = relPath
        } else {
            let (mount, relPath) = try resolveBarePath(cleaned, in: mounts)
            mountPath = mount.mountPath
            mountName = mount.mountName
            resolvedPath = relPath
        }

        let fileURL = try validatePath(resolvedPath, rootPath: mountPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ManifoldMCPError.fileNotFound(cleaned)
        }
        let canonicalPath = "\(mountName)/\(resolvedPath)"
        let artifact = try? await artifactIndex.artifact(grantID: grantID, canonicalPath: canonicalPath)

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = artifact?.sizeBytes ?? ((attrs[.size] as? Int) ?? 0)
        let modified = (artifact?.lastModified.isEmpty == false ? artifact?.lastModified : nil)
            ?? (attrs[.modificationDate] as? Date).map { ISO8601DateFormatter.shared.string(from: $0) }
            ?? ""
        let ext = artifact?.fileExtension ?? fileURL.pathExtension
        let isBinary = artifact?.isBinary ?? ContextEngine.isBinary(fileExtension: ext.lowercased(), fileURL: fileURL)

        var archiveContents: [String]? = nil
        if ext.lowercased() == "zip" {
            archiveContents = try await artifactIndex.archiveEntries(grantID: grantID, canonicalPath: canonicalPath)
            if archiveContents?.isEmpty != false {
                archiveContents = listZipContents(atPath: fileURL.path)
            }
        }

        let detail = FileInfoDetail(
            path: canonicalPath,
            sourceName: mountName,
            sizeBytes: size,
            fileExtension: ext,
            isBinary: isBinary,
            lastModified: modified,
            archiveContents: archiveContents
        )
        let detailString = [
            detail.path,
            detail.sourceName,
            String(detail.sizeBytes),
            detail.fileExtension,
            detail.isBinary ? "binary" : "text",
            detail.lastModified,
        ].joined(separator: "\n")
        await recordExposure(toolName: "file_info", resourcePath: canonicalPath, text: detailString, exposureType: "snippet", decisionID: access.decisionID, intent: validatedIntent)
        return detail
    }

    // MARK: - Archive Listing

    public func listArchive(path: String, intent: AccessIntent? = nil) async throws -> [String] {
        await logToolCall(tool: "list_archive", arguments: ["path": path])
        let validatedIntent = try await validatedAccessIntent(for: "list_archive", provided: intent)
        let access = try await resolveAccessMounts(toolName: "list_archive", action: "read", resourcePath: path, intent: validatedIntent)
        let mounts = access.mounts
        if let grant = access.grant {
            try await ensureIndexed(grant: grant, mounts: mounts)
        }
        let cleaned = cleanPath(path)

        guard let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) else {
            throw ManifoldMCPError.fileNotFound(path)
        }
        try assertStandingVisibility(relativePath: relPath, mount: mount, access: access, originalPath: cleaned)

        let archiveURL = try validatePath(relPath, rootPath: mount.mountPath)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ManifoldMCPError.fileNotFound(path)
        }

        let canonicalPath = "\(mount.mountName)/\(relPath)"
        let grantID = access.grantID ?? "standing"
        let indexedEntries = try await artifactIndex.archiveEntries(grantID: grantID, canonicalPath: canonicalPath)
        if !indexedEntries.isEmpty {
            await recordExposure(toolName: "list_archive", resourcePath: canonicalPath, text: indexedEntries.joined(separator: "\n"), exposureType: "snippet", decisionID: access.decisionID, intent: validatedIntent)
            return indexedEntries
        }

        guard let contents = listZipContents(atPath: archiveURL.path) else {
            throw ManifoldMCPError.invalidPath("Not a valid zip archive or archive is empty")
        }
        await recordExposure(toolName: "list_archive", resourcePath: canonicalPath, text: contents.joined(separator: "\n"), exposureType: "snippet", decisionID: access.decisionID, intent: validatedIntent)
        return contents
    }

    // MARK: - Extract File

    public func extractFile(archivePath: String, filePath: String, intent: AccessIntent? = nil) async throws -> String {
        await logToolCall(tool: "extract_file", arguments: ["archive": archivePath, "file": filePath])
        let validatedIntent = try await validatedAccessIntent(for: "extract_file", provided: intent)
        let access = try await resolveAccessMounts(toolName: "extract_file", action: "read", resourcePath: archivePath, intent: validatedIntent)
        let mounts = access.mounts
        let cleaned = cleanPath(archivePath)

        // Resolve mount for the archive
        guard let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) else {
            throw ManifoldMCPError.fileNotFound(archivePath)
        }
        try assertStandingVisibility(relativePath: relPath, mount: mount, access: access, originalPath: cleaned)

        let archiveURL = try validatePath(relPath, rootPath: mount.mountPath)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ManifoldMCPError.fileNotFound(archivePath)
        }

        // Size check: 50MB limit
        let attrs = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
        let archiveSize = (attrs[.size] as? Int64) ?? 0
        guard archiveSize <= 50_000_000 else {
            throw ManifoldMCPError.invalidPath("Archive exceeds 50MB extraction limit")
        }

        let archiveContents = listZipContents(atPath: archiveURL.path)
        guard let targetEntry = archiveContents?.first(where: { $0 == filePath }) else {
            let available = (archiveContents ?? []).prefix(20).joined(separator: "\n")
            throw ManifoldMCPError.fileNotFound("'\(filePath)' not found in archive. Available files:\n\(available)")
        }

        let content = try extractFromZip(archivePath: archiveURL.path, entryPath: targetEntry)
        let exposedResource = "\(archivePath)#\(targetEntry)"
        let deliveredText = try await applyPrivacyPreflight(
            toolName: "extract_file",
            resourcePath: exposedResource,
            text: content,
            decisionID: access.decisionID,
            grantID: access.grantID
        )
        await recordExposure(toolName: "extract_file", resourcePath: exposedResource, text: deliveredText, exposureType: "full_file", decisionID: access.decisionID, intent: validatedIntent)
        return deliveredText
    }

    public func readRange(path: String, startLine: Int, endLine: Int, intent: AccessIntent? = nil) async throws -> String {
        await logToolCall(
            tool: "read_range",
            arguments: ["path": path, "start_line": "\(startLine)", "end_line": "\(endLine)"]
        )
        let validatedIntent = try await validatedAccessIntent(for: "read_range", provided: intent)
        guard startLine > 0, endLine >= startLine else {
            throw ManifoldMCPError.invalidPath("Line range must be positive and end_line must be >= start_line")
        }

        let access = try await resolveAccessMounts(toolName: "read_range", action: "read", resourcePath: path, intent: validatedIntent)
        let mounts = access.mounts
        if let grant = access.grant {
            try await ensureIndexed(grant: grant, mounts: mounts)
        }
        let cleaned = cleanPath(path)
        let grantID = access.grantID ?? "standing"

        let resolved: (mount: GrantMount, relativePath: String)
        if let match = resolveMountAndPath(cleaned, in: mounts) {
            resolved = match
        } else {
            resolved = try resolveBarePath(cleaned, in: mounts)
        }
        try assertStandingVisibility(relativePath: resolved.relativePath, mount: resolved.mount, access: access, originalPath: cleaned)

        let fileURL = try validatePath(resolved.relativePath, rootPath: resolved.mount.mountPath)
        let read = try ContextEngine.read(
            fileURL: fileURL,
            selection: ArtifactSelection(lineStart: startLine, lineEnd: endLine)
        )
        let canonicalPath = "\(resolved.mount.mountName)/\(resolved.relativePath)"
        let deliveredText = try await applyPrivacyPreflight(
            toolName: "read_range",
            resourcePath: canonicalPath,
            text: read.text,
            decisionID: access.decisionID,
            grantID: access.grantID
        )

        try? await auditStore.log(
            action: .fileRead,
            agent: agentName,
            filePath: canonicalPath,
            metadata: mergedMetadata([
                "grant_id": grantID,
                "mount": resolved.mount.mountName,
                "selection": "lines:\(startLine)-\(endLine)",
                "truncated": read.truncated ? "true" : "false",
            ]),
            grantID: grantID
        )

        await recordExposure(toolName: "read_range", resourcePath: canonicalPath, text: deliveredText, exposureType: "range", decisionID: access.decisionID, intent: validatedIntent)
        return deliveredText
    }

    public func diffFile(path: String, intent: AccessIntent? = nil) async throws -> String {
        await logToolCall(tool: "diff_file", arguments: ["path": path])
        let validatedIntent = try await validatedAccessIntent(for: "diff_file", provided: intent)
        let access = try await resolveAccessMounts(toolName: "diff_file", action: "read", resourcePath: path, intent: validatedIntent)
        let mounts = access.mounts
        if let grant = access.grant {
            try await ensureIndexed(grant: grant, mounts: mounts)
        }
        let cleaned = cleanPath(path)
        let grantID = access.grantID ?? "standing"

        let resolved: (mount: GrantMount, relativePath: String)
        if let match = resolveMountAndPath(cleaned, in: mounts) {
            resolved = match
        } else {
            resolved = try resolveBarePath(cleaned, in: mounts)
        }
        try assertStandingVisibility(relativePath: resolved.relativePath, mount: resolved.mount, access: access, originalPath: cleaned)

        let canonicalPath = "\(resolved.mount.mountName)/\(resolved.relativePath)"
        let fileURL = try validatePath(resolved.relativePath, rootPath: resolved.mount.mountPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ManifoldMCPError.fileNotFound(canonicalPath)
        }
        let baselineData: Data?
        if let baselineHash = try await snapshotStore.baselineHash(runID: grantID, filePath: canonicalPath),
           let retrieved = try await contentStore.retrieve(hash: baselineHash) {
            baselineData = retrieved
        } else {
            let history = try await snapshotStore.runTimeline(runID: grantID)
            if let fallbackHash = history.first(where: { record in
                record.isBaseline
                    && (record.filePath == canonicalPath
                        || record.filePath == resolved.relativePath
                        || record.filePath.hasSuffix("/\(resolved.relativePath)"))
            })?.afterHash {
                baselineData = try await contentStore.retrieve(hash: fallbackHash)
            } else if let source = try await grantStore.source(id: resolved.mount.sourceID) {
                let originalURL = URL(fileURLWithPath: source.originalRootPath).appendingPathComponent(resolved.relativePath)
                baselineData = try? Data(contentsOf: originalURL, options: [.mappedIfSafe])
            } else {
                baselineData = nil
            }
        }

        guard let baselineData else {
            return "No baseline snapshot available for \(canonicalPath)"
        }

        let currentData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard let diffLines = DiffEngine().diff(beforeData: baselineData, afterData: currentData) else {
            return "No inline text diff available for \(canonicalPath)"
        }

        if diffLines.isEmpty {
            return "No changes in \(canonicalPath) relative to the baseline snapshot."
        }

        let rendered = diffLines.map { line -> String in
            switch line.type {
            case .addition:
                return "+\(line.text)"
            case .removal:
                return "-\(line.text)"
            case .context:
                return " \(line.text)"
            }
        }.joined(separator: "\n")
        let deliveredText = try await applyPrivacyPreflight(
            toolName: "diff_file",
            resourcePath: canonicalPath,
            text: rendered,
            decisionID: access.decisionID,
            grantID: access.grantID,
            contentKind: .diff
        )

        await recordExposure(toolName: "diff_file", resourcePath: canonicalPath, text: deliveredText, exposureType: "diff", decisionID: access.decisionID, intent: validatedIntent)
        return deliveredText
    }

    public func searchStructured(query: String, limit: Int = 10, intent: AccessIntent? = nil) async throws -> String {
        await logToolCall(tool: "search_structured", arguments: ["query": query, "limit": "\(limit)"])
        let validatedIntent = try await validatedAccessIntent(for: "search_structured", provided: intent)
        let access = try await resolveAccessMounts(toolName: "search_structured", action: "search", intent: validatedIntent)
        let mounts = access.mounts
        if let grant = access.grant {
            try await ensureIndexed(grant: grant, mounts: mounts)
        }
        let grantID = access.grantID ?? "standing"

        let hits = try await artifactIndex.search(
            grantID: grantID,
            query: query,
            limit: limit,
            kinds: [.file, .email, .emailAttachment, .sessionSummary]
        )
        var payload: [[String: Any]] = []
        for hit in hits {
            var deliveredPreview: [String] = []
            for snippet in hit.preview {
                do {
                    let deliveredSnippet = try await applyPrivacyPreflight(
                        toolName: "search_structured",
                        resourcePath: hit.handle.path,
                        text: snippet,
                        decisionID: access.decisionID,
                        grantID: access.grantID,
                        contentKind: .structuredResult
                    )
                    deliveredPreview.append(deliveredSnippet)
                    await recordExposure(
                        toolName: "search_structured",
                        resourcePath: hit.handle.path,
                        text: deliveredSnippet,
                        exposureType: "snippet",
                        decisionID: access.decisionID,
                        intent: validatedIntent
                    )
                } catch {
                    continue
                }
            }
            payload.append(
                [
                    "kind": hit.handle.kind.rawValue,
                    "path": hit.handle.path,
                    "source": hit.handle.mountName,
                    "score": hit.score,
                    "preview": deliveredPreview,
                    "selection": selectionJSON(hit.selection),
                ]
            )
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let json = String(data: data, encoding: .utf8) ?? "[]"
        return json
    }

    // MARK: - Changes

    public func listChanges() async throws -> [ChangeInfo] {
        await logToolCall(tool: "list_changes")
        let access = try await resolveAccessMounts(toolName: "list_changes", action: "list")
        let grantID = access.grantID
        let entries = try await auditStore.recentEntries(limit: 50)
        let changes = entries
            .filter { grantID == nil || $0.grantID == grantID }
            .map { entry in
                ChangeInfo(
                    action: entry.action,
                    path: entry.filePath,
                    agent: entry.agent,
                    timestamp: entry.timestamp
                )
            }
        let rendered = changes.map { "\($0.timestamp) \($0.action) \($0.path ?? "")" }.joined(separator: "\n")
        await recordExposure(toolName: "list_changes", resourcePath: grantID, text: rendered, exposureType: "snippet", decisionID: access.decisionID)
        return changes
    }

    // MARK: - Zip Helpers

    private func listZipContents(atPath path: String) -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let files = trimmed.components(separatedBy: "\n").filter { !$0.hasSuffix("/") }
        return files.isEmpty ? nil : files
    }

    private func extractFromZip(archivePath: String, entryPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archivePath, entryPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ManifoldMCPError.fileNotFound("Failed to extract '\(entryPath)' from archive")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: data, encoding: .utf8) {
            return text
        } else {
            return "<binary content, \(data.count) bytes>"
        }
    }

    private func relativePath(file: URL, base: URL) -> String {
        let filePath = file.standardizedFileURL.path
        let basePath = base.standardizedFileURL.path + "/"
        if filePath.hasPrefix(basePath) {
            return String(filePath.dropFirst(basePath.count))
        }
        return file.lastPathComponent
    }

    private func selectionJSON(_ selection: ArtifactSelection?) -> [String: Any] {
        [
            "line_start": (selection?.lineStart as Any?) ?? NSNull(),
            "line_end": (selection?.lineEnd as Any?) ?? NSNull(),
            "byte_start": (selection?.byteStart as Any?) ?? NSNull(),
            "byte_end": (selection?.byteEnd as Any?) ?? NSNull(),
        ]
    }

    // MARK: - Sessions

    /// Lists recent governed sessions.
    public func listSessions(limit: Int) async throws -> [SessionSummary] {
        await logToolCall(tool: "list_sessions", arguments: ["limit": "\(limit)"])
        let grants = try await grantStore.allGrants(limit: limit)
        let ended = grants.filter { $0.endedAt != nil }
        var results: [SessionSummary] = []
        for grant in ended {
            let summaries = (try? await grantStore.summaries(grantID: grant.grantID)) ?? []
            let preview = preferredSummary(from: summaries)?.summaryMarkdown.prefix(200).description ?? "No summary"
            results.append(SessionSummary(
                grantID: grant.grantID,
                targetApp: grant.targetApp,
                startedAt: grant.startedAt,
                endedAt: grant.endedAt ?? "",
                summaryPreview: preview
            ))
        }
        let rendered = results.map { "\($0.grantID) \($0.summaryPreview)" }.joined(separator: "\n")
        await recordExposure(toolName: "list_sessions", resourcePath: nil, text: rendered, exposureType: "snippet", decisionID: nil)
        return results
    }

    /// Returns the detailed governed record for one session or grant identifier.
    public func getSession(grantID: String) async throws -> SessionDetail {
        await logToolCall(tool: "get_session", arguments: ["grant_id": grantID])
        let grants = try await grantStore.allGrants(limit: 100)
        guard let grant = grants.first(where: { $0.grantID == grantID }) else {
            throw ManifoldMCPError.fileNotFound("Session not found: \(grantID)")
        }
        let grantSources = try await grantStore.grantSources(grantID: grantID)
        let summaries = try await grantStore.summaries(grantID: grantID)
        let primarySummary = preferredSummary(from: summaries)
        let notes = summaries
            .filter { $0.kind != .summary }
            .map {
                SessionNoteDetail(
                    summaryID: $0.summaryID,
                    kind: $0.summaryKind,
                    origin: $0.summaryOrigin,
                    endedAt: $0.endedAt,
                    markdown: $0.summaryMarkdown
                )
            }
        let entries = try await auditStore.recentEntries(limit: 200)
        let grantEntries = entries.filter { $0.grantID == grantID }
        let filesModified = Set(grantEntries.compactMap(\.filePath)).sorted()
        let promotions = try await grantStore.promotions(grantID: grantID)
        let conflicts = promotions
            .filter(\.isConflict)
            .map(\.relativePath)

        let detail = SessionDetail(
            grantID: grantID,
            targetApp: grant.targetApp,
            status: grant.status,
            startedAt: grant.startedAt,
            endedAt: grant.endedAt,
            sources: grantSources.map(\.mountName),
            summaryMarkdown: primarySummary?.summaryMarkdown,
            noteCaptureMode: grant.noteCaptureMode,
            sessionNotes: notes,
            filesApplied: filesModified,
            filesConflicted: conflicts,
            totalPromotions: promotions.count
        )
        await recordExposure(
            toolName: "get_session",
            resourcePath: grantID,
            text: [detail.summaryMarkdown ?? "", detail.filesApplied.joined(separator: "\n"), detail.filesConflicted.joined(separator: "\n")].joined(separator: "\n"),
            exposureType: "snippet",
            decisionID: nil
        )
        return detail
    }

    /// Saves a session note into the current governed history.
    public func saveSessionNote(note: String, noteType: SessionSummaryKind = .checkpointNote) async throws -> String {
        await logToolCall(
            tool: "save_session_note",
            arguments: ["note_length": "\(note.count)", "note_type": noteType.rawValue]
        )
        let (grant, _) = try await requireGrant()
        let now = ISO8601DateFormatter.shared.string(from: Date())

        _ = try await grantStore.saveSummary(
            grantID: grant.grantID,
            targetApp: TargetApp(rawValue: grant.targetApp) ?? .cowork,
            startedAt: grant.startedAt,
            endedAt: now,
            markdown: note,
            kind: noteType,
            origin: .agent
        )
        let summaries = try await grantStore.summaries(grantID: grant.grantID)
        try await artifactIndex.syncSessionSummaries(grantID: grant.grantID, summaries: summaries)
        return "Session \(noteType.displayName.lowercased()) saved for grant \(grant.grantID.prefix(12))..."
    }

    // MARK: - Email Tools (reads from .eml-backed email index)

    /// Lists governed emails currently visible to this bridge.
    public func listEmails(intent: AccessIntent? = nil) async throws -> [EmailSummary] {
        await logToolCall(tool: "list_emails")
        let validatedIntent = try await validatedAccessIntent(for: "list_emails", provided: intent)
        let (context, decisionID) = try await resolveAccessForTool(toolName: "list_emails", action: "list", intent: validatedIntent)
        let emails: [EmailMessageRecord]
        switch context {
        case .standing(let policy, _):
            emails = try await accessibleEmails(policy: policy, limit: 200)
        case .workBlock(let grant, _, _), .legacyGrant(let grant, _):
            emails = try await accessibleEmails(grant: grant, limit: 200)
        }
        let summaries = emails.map {
            EmailSummary(id: $0.emailID, from: $0.sender, subject: $0.subject, date: $0.receivedAt)
        }
        for summary in summaries {
            await recordExposure(
                toolName: "list_emails",
                resourcePath: summary.id,
                text: "\(summary.from)\n\(summary.subject)\n\(summary.date)",
                exposureType: "email_preview",
                decisionID: decisionID,
                intent: validatedIntent
            )
        }
        return summaries
    }

    /// Reads one governed email message.
    public func readEmail(id: String, intent: AccessIntent? = nil) async throws -> String {
        await logToolCall(tool: "read_email", arguments: ["id": id])
        let validatedIntent = try await validatedAccessIntent(for: "read_email", provided: intent)
        let (context, decisionID) = try await resolveAccessForTool(
            toolName: "read_email",
            action: "read",
            resourcePath: id,
            intent: validatedIntent
        )

        guard let email = try emailStore.emailMessage(id: id) else {
            throw ManifoldMCPError.fileNotFound("Email not found: \(id)")
        }

        let grantID: String?
        let emailDecision: EmailRuleDecision
        switch context {
        case .standing(let policy, _):
            let decision = try await emailRuleDecision(for: email, policy: policy)
            guard decision.allowed else {
                throw ManifoldMCPError.fileNotFound("Email not accessible with current standing access rules")
            }
            emailDecision = decision
            grantID = nil
        case .workBlock(let grant, _, _), .legacyGrant(let grant, _):
            let decision = try await emailRuleDecision(for: email, grant: grant)
            guard decision.allowed else {
                throw ManifoldMCPError.fileNotFound("Email not accessible with current sensitivity settings")
            }
            emailDecision = decision
            grantID = grant.grantID
        }

        // Read from .eml file on disk
        if let emlPath = email.emlPath,
           let data = EmailSyncEngine.readStoredMessage(at: emlPath) {
            let parsed = MIMEParser.parse(data: data)
            let excerpt = parsed.safeExcerpt(maxCharacters: 4_000) ?? email.preview ?? "(no preview available)"
            let content = """
            From: \(email.sender)
            To: \(email.recipients)
            Subject: \(email.subject)
            Date: \(email.receivedAt)

            \(excerpt)
            """
            let deliveredText = try await applyPrivacyPreflight(
                toolName: "read_email",
                resourcePath: id,
                text: content,
                decisionID: decisionID,
                grantID: grantID,
                contentKind: .email
            )
            await auditEmailRead(email: email, grantID: grantID, decision: emailDecision)
            await recordExposure(toolName: "read_email", resourcePath: id, text: deliveredText, exposureType: "email_body", decisionID: decisionID, intent: validatedIntent)
            return deliveredText
        }

        // Fallback: return metadata summary
        await auditEmailRead(email: email, grantID: grantID, decision: emailDecision)

        let preview = """
        From: \(email.sender)
        To: \(email.recipients)
        Subject: \(email.subject)
        Date: \(email.receivedAt)

        \(email.preview ?? "(no preview available)")
        """
        let deliveredPreview = try await applyPrivacyPreflight(
            toolName: "read_email",
            resourcePath: id,
            text: preview,
            decisionID: decisionID,
            grantID: grantID,
            contentKind: .email
        )
        await recordExposure(toolName: "read_email", resourcePath: id, text: deliveredPreview, exposureType: "email_preview", decisionID: decisionID, intent: validatedIntent)
        return deliveredPreview
    }

    /// Searches governed email content through the runtime email policy engine.
    public func searchEmails(query: String, intent: AccessIntent? = nil) async throws -> [EmailMessageRecord] {
        await logToolCall(tool: "search_emails", arguments: ["query": query])
        let validatedIntent = try await validatedAccessIntent(for: "search_emails", provided: intent)
        let (context, decisionID) = try await resolveAccessForTool(toolName: "search_emails", action: "search", resourcePath: query, intent: validatedIntent)
        let results = try emailStore.searchEmailMessages(freeText: query, limit: 200)
        let visible: [EmailMessageRecord]
        let grantID: String?
        switch context {
        case .standing(let policy, _):
            var allowed: [EmailMessageRecord] = []
            for email in results {
                if try await isEmailAccessible(email: email, policy: policy) {
                    allowed.append(email)
                }
            }
            visible = allowed
            grantID = nil
        case .workBlock(let grant, _, _), .legacyGrant(let grant, _):
            var allowed: [EmailMessageRecord] = []
            for email in results {
                if try await isEmailAccessible(email: email, grant: grant) {
                    allowed.append(email)
                }
            }
            visible = allowed
            grantID = grant.grantID
        }
        var delivered: [EmailMessageRecord] = []
        for email in visible {
            let preview = [email.sender, email.subject, email.preview ?? ""]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            do {
                let deliveredPreview = try await applyPrivacyPreflight(
                    toolName: "search_emails",
                    resourcePath: email.emailID,
                    text: preview,
                    decisionID: decisionID,
                    grantID: grantID,
                    contentKind: .email
                )
                let updated = EmailMessageRecord(
                    emailID: email.emailID,
                    accountID: email.accountID,
                    mailbox: email.mailbox,
                    sender: email.sender,
                    senderEmail: email.senderEmail,
                    senderDomain: email.senderDomain,
                    recipients: email.recipients,
                    cc: email.cc,
                    subject: email.subject,
                    receivedAt: email.receivedAt,
                    emlPath: email.emlPath,
                    sizeBytes: email.sizeBytes,
                    preview: deliveredPreview,
                    contentType: email.contentType,
                    isRead: email.isRead,
                    isFlagged: email.isFlagged,
                    flagColor: email.flagColor,
                    inReplyTo: email.inReplyTo,
                    referencesHeader: email.referencesHeader,
                    messageIDHeader: email.messageIDHeader,
                    attachmentCount: email.attachmentCount,
                    localIsViewed: email.localIsViewed,
                    isJunk: email.isJunk,
                    deletedOnServerAt: email.deletedOnServerAt,
                    bodyText: email.bodyText,
                )
                delivered.append(updated)
                await recordExposure(
                    toolName: "search_emails",
                    resourcePath: email.emailID,
                    text: deliveredPreview,
                    exposureType: "email_preview",
                    decisionID: decisionID,
                    intent: validatedIntent
                )
            } catch {
                continue
            }
        }
        return delivered
    }

    /// Returns the durable history context for one governed file path.
    public func fileHistoryContext(filePath: String, limit: Int = 20) async throws -> FileHistoryContext {
        await logToolCall(tool: "get_file_history_context", arguments: ["file_path": filePath, "limit": limit])
        let (_, decisionID) = try await resolveAccessForTool(
            toolName: "get_file_history_context",
            action: "read",
            resourcePath: filePath
        )
        let snapshots = (try await snapshotStore.fileHistory(filePath: filePath)).prefix(limit).map { $0 }
        let activity = (try await auditStore.recentEntries(limit: max(limit * 10, 100)))
            .filter { $0.filePath == filePath }
            .prefix(limit)
            .map { $0 }
        let exposures = (try? await exposureStore?.exposures(resourcePath: filePath, limit: limit)) ?? []
        let sessionIDs = Array(Set(activity.compactMap(\.sessionID))).sorted()
        let context = FileHistoryContext(
            filePath: filePath,
            snapshots: snapshots,
            relatedActivity: activity,
            recentExposures: exposures,
            relatedSessionIDs: sessionIDs
        )
        let exposureText = """
        File: \(filePath)
        Snapshots: \(snapshots.count)
        Related activity: \(activity.count)
        Related sessions: \(sessionIDs.joined(separator: ", "))
        """
        await recordExposure(
            toolName: "get_file_history_context",
            resourcePath: filePath,
            text: exposureText,
            exposureType: "history_context",
            decisionID: decisionID
        )
        return context
    }

    /// Returns the durable history context for one governed session.
    public func sessionContext(sessionID: String) async throws -> SessionContextDetail {
        await logToolCall(tool: "get_session_context", arguments: ["session_id": sessionID])
        let (_, decisionID) = try await resolveAccessForTool(
            toolName: "get_session_context",
            action: "read",
            resourcePath: sessionID
        )
        let entries = try await auditStore.entries(sessionID: sessionID, limit: 200)
        let events = try await auditStore.sessionEvents(sessionID: sessionID)
        let recentSessions = try await auditStore.recentSessions(limit: 200)
        let session = recentSessions.first { $0.id == sessionID }
        let grantID = entries.compactMap(\.grantID).first
        let notes: [SessionSummaryRecord]
        if let grantID {
            notes = (try? await grantStore.summaries(grantID: grantID)) ?? []
        } else {
            notes = []
        }
        let filePaths = Array(Set(entries.compactMap(\.filePath))).sorted()
        let emailIDs = messageIDs(from: entries)
        let emails = (try? emailStore.emailMessages(ids: emailIDs)) ?? []
        let viewerPolicy = try? await policyStore?.policy(for: targetApp)
        let emailSummaries = try await HistoryVisibilityFilter.relatedEmails(
            emails,
            viewerPolicy: viewerPolicy,
            decisionResolver: { [weak self] email, policy in
                guard let self else {
                    return EmailRuleDecision(
                        agent: policy.agent,
                        emailID: email.emailID,
                        allowed: false,
                        kind: .defaultPolicy,
                        message: "Email history is unavailable because the bridge is no longer active."
                    )
                }
                return try await self.emailRuleDecision(for: email, policy: policy)
            }
        )
        let context = SessionContextDetail(
            session: session,
            grantID: grantID,
            entries: entries,
            events: events,
            filePaths: filePaths,
            emails: emailSummaries,
            notes: notes
        )
        let exposureText = """
        Session: \(sessionID)
        Grant: \(grantID ?? "none")
        Files: \(filePaths.count)
        Emails: \(emailSummaries.count)
        Events: \(events.count)
        """
        await recordExposure(
            toolName: "get_session_context",
            resourcePath: sessionID,
            text: exposureText,
            exposureType: "history_context",
            decisionID: decisionID
        )
        return context
    }
}

private extension PrivacyDelivery {
    func replacingDeliveredText(_ text: String, outcome: PrivacyOutcome) -> PrivacyDelivery {
        PrivacyDelivery(
            deliveredText: text,
            redactedText: redactedText,
            outcome: outcome,
            findingsSummary: findingsSummary,
            matchedCategories: matchedCategories,
            severity: severity,
            backend: backend,
            modelVersion: modelVersion,
            inputHash: inputHash,
            deliveredHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined(),
            approvalContext: approvalContext
        )
    }
}

private extension RuleMatcher {
    var usesPrivacyProbe: Bool {
        leafCases.contains { matcher in
            switch matcher {
            case .privacyContainsCategory,
                 .privacyMatchesMyIdentity,
                 .privacyInOrgAllowlist,
                 .privacySeverityAtLeast:
                return true
            default:
                return false
            }
        }
    }
}
