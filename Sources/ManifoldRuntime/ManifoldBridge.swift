// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CryptoKit
import AppKit
import ManifoldKit
import os
import PDFKit

/// Core logic layer between MCP protocol and ManifoldKit stores.
/// Dual-path access: standing access via PolicyStore, session grants for gateway scope.
/// Fail-closed: no policy and no grant = no access.
public actor ManifoldBridge {
    // MARK: - Internal state — only for ManifoldBridge+* extensions
    //
    // These properties are `internal` (Swift's default access) so that the
    // sibling-file extensions (ManifoldBridge+Memory, +History, +Capability,
    // +SkillsAndExec) can reach them. Swift has no "extension-only" access
    // level; the cost of file-level extension splitting is that anything in
    // the ManifoldRuntime module can technically reach these.
    //
    // Convention: only ManifoldBridge.swift and ManifoldBridge+*.swift may
    // touch these directly. Other files in ManifoldRuntime/ should treat
    // them as if they were `private`. New tool surfaces should land as a
    // ManifoldBridge+<Group>.swift extension, not as a free function that
    // grabs at bridge state.

    static let maxExposurePreviewCharacters = 512
    static let maxDirectBinaryWriteBytes = 25 * 1024 * 1024
    static let maxPDFAnnotationBytes = 25 * 1024 * 1024
    static let maxPDFAnnotationPages = 500
    static let maxDirectBinaryWriteBase64Characters = ((maxDirectBinaryWriteBytes + 2) / 3) * 4 + 8_192
    static let textWriteBlockedExtensions: Set<String> = [
        "pdf",
        "png", "jpg", "jpeg", "gif", "bmp", "tif", "tiff", "ico", "webp", "heic", "avif",
        "zip", "gz", "tar", "rar", "7z", "pkg", "dmg",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key",
        "sqlite", "sqlite3", "db", "bin", "dat",
        "mp3", "mp4", "wav", "aiff", "avi", "mov", "mkv", "webm",
        "ttf", "otf", "woff", "woff2",
    ]
    let logger = Logger(subsystem: "com.spatialduality.manifold", category: "runtime")
    let db: DatabaseConnection
    let auditStore: AuditStore
    let contentStore: ContentStore
    let grantStore: GrantStore
    let emailStore: EmailStore
    let snapshotStore: SnapshotStore
    let artifactIndex: ArtifactIndex
    let policyStore: PolicyStore?
    let runtimeSettingsStore: RuntimeSettingsStore?
    let emailRuleStore: EmailRuleStore?
    let workBlockStore: WorkBlockStore?
    let fileVisibilityOverrideStore: FileVisibilityOverrideStore?
    let approvalQueue: ApprovalQueue?
    let standingWriteApprovalStore: StandingWriteApprovalStore?
    let exposureStore: ExposureStore?
    let ledgerStore: LedgerStore?
    let memoryStore: MemoryStore?
    let skillStore: SkillStore?
    let capabilityHandleStore: CapabilityHandleStore?
    let execRunStore: ExecRunStore?
    let knowledgeGraphStore: KnowledgeGraphStore?
    let fabricationFindingStore: FabricationFindingStore?
    let ruleStore: RuleStore?
    let privacyCoordinator: PrivacyPreflightCoordinator?
    let filterModeStore: FilterModeStore?
    let filterModeFindingsProvider: (any FilterModeFindingsProvider)?
    nonisolated let targetApp: TargetApp
    let profileID: String
    var runtimeContext: AgentRuntimeContext
    var connectionLogged = false

    public init(
        db: DatabaseConnection,
        auditStore: AuditStore,
        contentStore: ContentStore,
        grantStore: GrantStore,
        emailStore: EmailStore,
        snapshotStore: SnapshotStore,
        artifactIndex: ArtifactIndex,
        policyStore: PolicyStore? = nil,
        runtimeSettingsStore: RuntimeSettingsStore? = nil,
        emailRuleStore: EmailRuleStore? = nil,
        workBlockStore: WorkBlockStore? = nil,
        fileVisibilityOverrideStore: FileVisibilityOverrideStore? = nil,
        approvalQueue: ApprovalQueue? = nil,
        standingWriteApprovalStore: StandingWriteApprovalStore? = nil,
        exposureStore: ExposureStore? = nil,
        ledgerStore: LedgerStore? = nil,
        memoryStore: MemoryStore? = nil,
        skillStore: SkillStore? = nil,
        capabilityHandleStore: CapabilityHandleStore? = nil,
        execRunStore: ExecRunStore? = nil,
        knowledgeGraphStore: KnowledgeGraphStore? = nil,
        fabricationFindingStore: FabricationFindingStore? = nil,
        ruleStore: RuleStore? = nil,
        privacyCoordinator: PrivacyPreflightCoordinator? = nil,
        filterModeStore: FilterModeStore? = nil,
        filterModeFindingsProvider: (any FilterModeFindingsProvider)? = nil,
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
        self.runtimeSettingsStore = runtimeSettingsStore
        self.emailRuleStore = emailRuleStore
        self.workBlockStore = workBlockStore
        self.fileVisibilityOverrideStore = fileVisibilityOverrideStore
        self.approvalQueue = approvalQueue
        self.standingWriteApprovalStore = standingWriteApprovalStore
        self.exposureStore = exposureStore
        self.ledgerStore = ledgerStore
        self.memoryStore = memoryStore
        self.skillStore = skillStore
        self.capabilityHandleStore = capabilityHandleStore
        self.execRunStore = execRunStore
        self.knowledgeGraphStore = knowledgeGraphStore
        self.fabricationFindingStore = fabricationFindingStore
        self.ruleStore = ruleStore
        self.privacyCoordinator = privacyCoordinator
        self.filterModeStore = filterModeStore
        self.filterModeFindingsProvider = filterModeFindingsProvider
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

    static func canonicalJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "\(value)"
        }
        return string
    }

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
            let isDraft = Self.isDraftWorkspaceGrant(grant)
            return DecisionContext(
                reason: isDraft ? "work_block" : "session_gateway",
                accessMode: isDraft ? "tracked_run" : "session_gateway",
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
            try await ledgerStore?.append(
                entryType: .accessDecision,
                subjectTable: "access_decisions",
                subjectID: decision.id,
                payload: Self.canonicalJSON(decision),
                metadata: [
                    "connection_id": decision.connectionID,
                    "agent": decision.agent,
                    "tool": decision.toolName,
                    "allowed": decision.allowed ? "true" : "false",
                ]
            )
            return decision.id
        } catch {
            logger.error("Failed to record access decision: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    func recordExposure(
        toolName: String,
        resourcePath: String?,
        text: String,
        exposureType: String,
        decisionID: String?,
        intent: AccessIntent? = nil
    ) async -> ExposureRecord? {
        guard decisionID != nil else { return nil }
        return await recordExposure(
            toolName: toolName,
            resourcePath: resourcePath,
            data: Data(text.utf8),
            exposureType: exposureType,
            decisionID: decisionID,
            intent: intent
        )
    }

    @discardableResult
    func recordExposure(
        toolName: String,
        resourcePath: String?,
        data: Data,
        exposureType: String,
        decisionID: String?,
        intent: AccessIntent? = nil
    ) async -> ExposureRecord? {
        guard let exposureStore, let decisionID else { return nil }
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
            try await ledgerStore?.append(
                entryType: .exposure,
                subjectTable: "exposure_records",
                subjectID: exposure.id,
                payload: Self.canonicalJSON(exposure),
                metadata: [
                    "connection_id": exposure.connectionID,
                    "agent": exposure.agent,
                    "tool": exposure.toolName,
                    "content_hash": exposure.contentHash,
                ]
            )
            return exposure
        } catch {
            logger.error("Failed to record exposure: \(error.localizedDescription, privacy: .public)")
            return nil
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

    func resolveAccessForTool(
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
        let activeGrantLevel = (try? await grantStore.activeGrant(targetApp: targetApp, profileID: profileID))?
            .sessionRequestDetailLevel
        let policyLevel = (try? await policyStore?.policy(for: targetApp))?.accessRecordingLevel
        let level = activeGrantLevel
            ?? policyLevel
            ?? .lightweight
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
           let block = try? await workBlockStore.activeBlock(for: targetApp),
           let grant = try? await grantStore.grant(id: block.grantID),
           Self.isDraftWorkspaceGrant(grant) {
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

    // MARK: - Access Resolution (standing policy + session grant)

    /// Resolved access context for a tool call.
    /// Standing and gateway access read original source paths; explicit draft
    /// workspaces remain isolated until the user applies them.
    enum AccessContext {
        /// Standing access via persistent policy. Files are read from original paths.
        case standing(policy: AgentAccessPolicy, sources: [SourceRecord])
        /// Active session gateway or explicit draft workspace via grant.
        case workBlock(grant: GrantRecord, grantSources: [GrantSourceRecord], block: WorkBlockRecord)
        /// Legacy grant-only path (no PolicyStore available).
        case legacyGrant(grant: GrantRecord, grantSources: [GrantSourceRecord])
    }

    /// Resolve access for the current agent. Tries standing policy first,
    /// then session grant, then legacy grant. Fail-closed.
    private func resolveAccess() async throws -> AccessContext {
        // Path 1: Standing access via PolicyStore (v4.1)
        if let policyStore {
            let policy = try await policyStore.policy(for: targetApp)

            // Check pause state first
            if policy.isPaused {
                throw ManifoldMCPError.accessPaused
            }

            // Check for active session gateway
            if let wbStore = workBlockStore,
               let block = try await wbStore.activeBlock(for: targetApp) {
                // Session active — route through its grant scope.
                if let grant = try await grantStore.grant(id: block.grantID) {
                    let grantSources = try await scopedGrantSources(grant: grant, policy: policy)
                    try await grantStore.touchGrant(grantID: grant.grantID)
                    return .workBlock(grant: grant, grantSources: grantSources, block: block)
                }
            }

            if let runtimeSettingsStore,
               try await runtimeSettingsStore.sessionAccessMode() == .manualRequiresSession {
                throw ManifoldMCPError.noAccessConfigured
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
            let allSources = try await grantStore.activeSources()
            let allowedSources = allSources.filter {
                policy.allowedSourceIDs.contains($0.sourceID)
                    || resolver.sourceIDsWithAllowOverrides.contains($0.sourceID)
            }
            return .standing(policy: policy, sources: allowedSources)
        }

        // Path 2: Legacy grant-only (PolicyStore not injected)
        return try await legacyRequireGrant()
    }

    private func scopedGrantSources(grant: GrantRecord, policy: AgentAccessPolicy?) async throws -> [GrantSourceRecord] {
        var grantSources = try await grantStore.grantSources(grantID: grant.grantID)
        let activeSourceIDs = Set((try await grantStore.activeSources()).map(\.sourceID))
        grantSources = grantSources.filter { activeSourceIDs.contains($0.sourceID) }

        guard let policy else { return grantSources }
        guard policy.agent.rawValue == grant.targetApp, !policy.isPaused else { return [] }

        if grant.explicitSelection {
            let explicitSourceIDs = Set((try await grantStore.grantFileScopes(grantID: grant.grantID)).map(\.sourceID))
            guard !explicitSourceIDs.isEmpty else { return [] }
            return grantSources.filter { explicitSourceIDs.contains($0.sourceID) }
        }

        let resolver = try await standingFileVisibilityResolver(for: policy)
        let allowedSourceIDs = policy.allowedSourceIDs.union(resolver.sourceIDsWithAllowOverrides)
        return grantSources.filter { allowedSourceIDs.contains($0.sourceID) }
    }

    private func explicitGrantEmailIDs(for grant: GrantRecord, limit: Int) throws -> Set<String>? {
        guard grant.explicitSelection else { return nil }
        let ids = Set(try emailStore.grantEmails(grantID: grant.grantID, limit: limit).map(\.emailID))
        return ids.isEmpty ? nil : ids
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

        return (try emailStore.sharedEmailCount(agent: policy.agent)) > 0
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
            GrantMount(sourceID: source.sourceID, mountName: source.canonicalMountName, mountPath: source.originalRootPath)
        }
    }

    /// Build original-source mounts for a session grant. The grant keeps the
    /// session gateway boundary; the filesystem path remains the user's live
    /// governed folder so writes are immediately visible to later sessions.
    private func originalMounts(sources grantSources: [GrantSourceRecord]) async throws -> [GrantMount] {
        var mounts: [GrantMount] = []
        for grantSource in grantSources {
            guard let source = try await grantStore.source(id: grantSource.sourceID),
                  source.isAccessible else {
                continue
            }
            mounts.append(
                GrantMount(
                    sourceID: grantSource.sourceID,
                    mountName: grantSource.mountName,
                    mountPath: source.originalRootPath
                )
            )
        }
        return mounts
    }

    private func grantFileScopes(for grant: GrantRecord) async throws -> [FileSelectionScope] {
        try await grantStore.grantFileScopes(grantID: grant.grantID).map {
            FileSelectionScope(
                sourceID: $0.sourceID,
                relativePath: $0.relativePath,
                isDirectory: $0.isDirectory
            )
        }
    }

    /// Resolved mounts + optional grant for read operations.
    /// Standing access and normal sessions point to original source paths.
    /// Legacy grants and explicit draft workspaces point to materialized roots.
    private struct ResolvedMounts {
        let mounts: [GrantMount]
        let grantID: String?
        let grant: GrantRecord?
        let isStanding: Bool
        let usesOriginalSources: Bool
        let decisionID: String?
        let standingPolicy: AgentAccessPolicy?
        let standingResolver: FileVisibilityResolver?
        /// Nil means no grant-scoped file filter; non-nil means the listed
        /// source-relative scopes are the complete session file gateway.
        let fileScopes: [FileSelectionScope]?
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
                usesOriginalSources: true,
                decisionID: decisionID,
                standingPolicy: policy,
                standingResolver: resolver,
                fileScopes: nil
            )
        case .workBlock(let grant, let grantSources, _):
            if !Self.isDraftWorkspaceGrant(grant) {
                let policy = try await policyStore?.policy(for: targetApp)
                let resolver: FileVisibilityResolver?
                if let policy {
                    resolver = try await standingFileVisibilityResolver(for: policy)
                } else {
                    resolver = nil
                }
                return ResolvedMounts(
                    mounts: try await originalMounts(sources: grantSources),
                    grantID: grant.grantID,
                    grant: grant,
                    isStanding: false,
                    usesOriginalSources: true,
                    decisionID: decisionID,
                    standingPolicy: grant.explicitSelection ? nil : policy,
                    standingResolver: grant.explicitSelection ? nil : resolver,
                    fileScopes: grant.explicitSelection ? try await grantFileScopes(for: grant) : nil
                )
            }
            return ResolvedMounts(
                mounts: grantMounts(grant: grant, sources: grantSources),
                grantID: grant.grantID,
                grant: grant,
                isStanding: false,
                usesOriginalSources: false,
                decisionID: decisionID,
                standingPolicy: nil,
                standingResolver: nil,
                fileScopes: nil
            )
        case .legacyGrant(let grant, let grantSources):
            return ResolvedMounts(
                mounts: grantMounts(grant: grant, sources: grantSources),
                grantID: grant.grantID,
                grant: grant,
                isStanding: false,
                usesOriginalSources: false,
                decisionID: decisionID,
                standingPolicy: nil,
                standingResolver: nil,
                fileScopes: nil
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
        guard access.usesOriginalSources,
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

    private func assertFileVisible(
        relativePath: String,
        mount: GrantMount,
        access: ResolvedMounts,
        originalPath: String
    ) throws {
        if let fileScopes = access.fileScopes {
            let scopesForSource = fileScopes.filter { $0.sourceID == mount.sourceID }
            guard !scopesForSource.isEmpty,
                  FileSelectionScope.allows(relativePath, in: scopesForSource) else {
                throw ManifoldMCPError.fileNotFound(originalPath)
            }
        }

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
        case automatic = "standing_write_auto"
        case once = "standing_write_once"
        case defaultScope = "standing_write_default"
    }

    private enum GovernedWriteMode: String {
        case direct = "direct"
        case directIfApproved = "direct_if_approved"
        case draftWorkspace = "draft_workspace"
    }

    private struct GovernedWriteOptions {
        let toolName: String
        let data: Data
        let mimeType: String?
        let intent: AccessIntent?
        let expectedBeforeHash: String?
        let writeMode: GovernedWriteMode
        let isBinary: Bool
    }

    private struct DraftWorkBlock {
        let grant: GrantRecord
        let sources: [GrantSourceRecord]
    }

    private enum StandingWriteResolution {
        case ready(access: ResolvedMounts, writeID: String, writeSource: String, writeGrantID: String?, target: ResolvedWriteTarget)
        case escalation(WriteResult)
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
        let explicitEmailIDs = try explicitGrantEmailIDs(for: grant, limit: limit)
        let context = try await emailPolicyContext(
            policy: policy,
            sensitivity: EmailSensitivityLevel(rawValue: grant.emailSensitivity) ?? policy.emailSensitivity,
            explicitGrantEmailIDs: explicitEmailIDs
        )
        let emails = try emailCandidates(
            policy: policy,
            explicitGrantEmailIDs: explicitEmailIDs,
            temporaryRevealIDs: context.temporaryRevealIDs,
            limit: limit
        )
        return emails.filter { email in
            EmailPolicyEngine.decision(for: email, context: context).allowed
        }
    }

    private func accessibleEmails(policy: AgentAccessPolicy, limit: Int) async throws -> [EmailMessageRecord] {
        let context = try await emailPolicyContext(policy: policy, explicitGrantEmailIDs: nil)
        let emails = try emailCandidates(policy: policy, explicitGrantEmailIDs: nil, limit: limit)
        return emails.filter { email in
            EmailPolicyEngine.decision(for: email, context: context).allowed
        }
    }

    private func emailCandidates(
        policy: AgentAccessPolicy,
        explicitGrantEmailIDs: Set<String>?,
        temporaryRevealIDs: Set<String> = [],
        limit: Int
    ) throws -> [EmailMessageRecord] {
        var byID: [String: EmailMessageRecord] = [:]

        if let explicitGrantEmailIDs {
            for email in try emailStore.sharedEmails(agent: policy.agent, limit: limit) {
                byID[email.emailID] = email
            }

            let selectedIDs = explicitGrantEmailIDs.union(temporaryRevealIDs)
            if !selectedIDs.isEmpty {
                for email in try emailStore.emailMessages(ids: Array(selectedIDs)) {
                    byID[email.emailID] = email
                }
            }

            return byID.values.sorted { lhs, rhs in
                if lhs.receivedAt == rhs.receivedAt {
                    return lhs.emailID < rhs.emailID
                }
                return lhs.receivedAt > rhs.receivedAt
            }
        }

        for email in try emailStore.allEmailMessages(limit: limit) {
            byID[email.emailID] = email
        }

        for email in try emailStore.sharedEmails(agent: policy.agent, limit: limit) {
            byID[email.emailID] = email
        }

        return byID.values.sorted { lhs, rhs in
            if lhs.receivedAt == rhs.receivedAt {
                return lhs.emailID < rhs.emailID
            }
            return lhs.receivedAt > rhs.receivedAt
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
            explicitGrantEmailIDs: explicitGrantEmailIDs(for: grant, limit: 1_000)
        )
        return EmailPolicyEngine.decision(for: email, context: context).allowed
    }

    func emailRuleDecision(for email: EmailMessageRecord, policy: AgentAccessPolicy) async throws -> EmailRuleDecision {
        let context = try await emailPolicyContext(policy: policy, explicitGrantEmailIDs: nil)
        return EmailPolicyEngine.decision(for: email, context: context)
    }

    private func emailRuleDecision(for email: EmailMessageRecord, grant: GrantRecord) async throws -> EmailRuleDecision {
        let policy = try await policyStore?.policy(for: targetApp) ?? AgentAccessPolicy(agent: targetApp)
        let context = try await emailPolicyContext(
            policy: policy,
            sensitivity: EmailSensitivityLevel(rawValue: grant.emailSensitivity) ?? policy.emailSensitivity,
            explicitGrantEmailIDs: explicitGrantEmailIDs(for: grant, limit: 1_000)
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

    func messageIDs(from entries: [ManifoldKit.AuditEntry]) -> [String] {
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

    private func resolveWriteTarget(
        _ path: String,
        in mounts: [GrantMount],
        requireMountPrefix: Bool = false
    ) throws -> ResolvedWriteTarget {
        let targetMount: GrantMount
        let resolvedPath: String
        if let (mount, relPath) = resolveMountAndPath(path, in: mounts) {
            targetMount = mount
            resolvedPath = relPath
        } else if requireMountPrefix {
            let mountNames = mounts.map(\.mountName).sorted().joined(separator: ", ")
            throw ManifoldMCPError.invalidPath("Writes to shared folders must use a mount-prefixed path. Available mounts: \(mountNames).")
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

    func logToolCall(tool: String, arguments: [String: Any] = [:]) async {
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
                let mounts: [GrantMount]
                let totalFiles: Int
                if Self.isDraftWorkspaceGrant(grant) {
                    mounts = grantMounts(grant: grant, sources: grantSources)
                    try await ensureIndexed(grant: grant, mounts: mounts)
                    totalFiles = (try? await artifactIndex.fileCount(grantID: grant.grantID)) ?? 0
                } else {
                    mounts = try await originalMounts(sources: grantSources)
                    let policy = try? await policyStore?.policy(for: targetApp)
                    let resolver: FileVisibilityResolver?
                    if let policy {
                        resolver = try? await standingFileVisibilityResolver(for: policy)
                    } else {
                        resolver = nil
                    }
                    let scopes: [FileSelectionScope]?
                    if grant.explicitSelection {
                        scopes = try? await grantFileScopes(for: grant)
                    } else {
                        scopes = nil
                    }
                    totalFiles = (try? listFilesFromOriginals(
                        mounts: mounts,
                        policy: grant.explicitSelection ? nil : policy,
                        resolver: grant.explicitSelection ? nil : resolver,
                        fileScopes: scopes ?? nil
                    ).count) ?? 0
                }
                let emailCount = (try? await accessibleEmails(grant: grant, limit: 5_000).count) ?? 0
                let summaries = (try? await grantStore.summaries(grantID: grant.grantID)) ?? []
                let noteGuidance = noteGuidance(for: grant, summaries: summaries)
                let sourceNames = mounts.map(\.mountName).joined(separator: ", ")
                let blockStatus = block.isPaused ? " (paused)" : ""
                let mode = Self.isDraftWorkspaceGrant(grant) ? "draft workspace" : "session gateway"
                let fileMemory = grant.memoryAccessEnabled ? "File memory query: on." : "File memory query: off."
                let message = "Manifold \(mode) active\(blockStatus) (grant \(grant.grantID.prefix(12))...). \(mounts.count) source(s): \(sourceNames). \(totalFiles) files, \(emailCount) emails. \(fileMemory)"
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
                let fileMemory = grant.memoryAccessEnabled ? "File memory query: on." : "File memory query: off."
                let message = "Manifold active (grant \(grant.grantID.prefix(12))...). \(mounts.count) source(s): \(sourceNames). \(totalFiles) files, \(emailCount) emails backed up. \(fileMemory)"
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
            return StatusResult(
                active: false, grantID: nil,
                sources: [],
                pausedSources: [],
                fileCount: 0, emailCount: 0,
                message: "No access configured. Use Review & Update Access in Manifold to grant file or email access.",
                noteCaptureMode: SessionNoteCaptureMode.off.rawValue,
                noteGuidance: nil
            )
        } catch ManifoldMCPError.noActiveSession {
            let sources = (try? await grantStore.allSources()) ?? []
            let active = sources.filter(\.isAccessible)
            return StatusResult(
                active: false,
                grantID: nil,
                sources: [],
                pausedSources: [],
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

        // Standing access and normal named sessions enumerate the live
        // governed folders. Draft/legacy grant paths still use the index.
        if resolved.usesOriginalSources {
            files = try listFilesFromOriginals(
                mounts: resolved.mounts,
                policy: resolved.standingPolicy,
                resolver: resolved.standingResolver,
                fileScopes: resolved.fileScopes
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
        resolver: FileVisibilityResolver? = nil,
        fileScopes: [FileSelectionScope]? = nil
    ) throws -> [FileInfo] {
        let currentPaths = Set(mounts.map(\.mountPath))
        let visibilityKey = cacheKey(policy: policy, resolver: resolver, fileScopes: fileScopes)
        if let cache = fileListCache,
           Date().timeIntervalSince(cache.timestamp) < fileListCacheTTL,
           cache.mountPaths == currentPaths,
           cache.visibilityKey == visibilityKey {
            return cache.entries
        }
        let files = try enumerateOriginalFiles(mounts: mounts, policy: policy, resolver: resolver, fileScopes: fileScopes)
        fileListCache = (files, Date(), currentPaths, visibilityKey)
        return files
    }

    private func cacheKey(
        policy: AgentAccessPolicy?,
        resolver: FileVisibilityResolver?,
        fileScopes: [FileSelectionScope]?
    ) -> String {
        let allowed = policy?.allowedSourceIDs.sorted().joined(separator: ",") ?? ""
        let overrideKey = resolver?.cacheKey ?? ""
        let scopeKey = fileScopes?
            .map { "\($0.sourceID):\($0.normalizedRelativePath):\($0.isDirectory ? "d" : "f")" }
            .sorted()
            .joined(separator: ",") ?? ""
        return "\(allowed)|\(overrideKey)|\(scopeKey)"
    }

    /// Actual file enumeration — only called when cache is stale or mount set changed.
    private func enumerateOriginalFiles(
        mounts: [GrantMount],
        policy: AgentAccessPolicy? = nil,
        resolver: FileVisibilityResolver? = nil,
        fileScopes: [FileSelectionScope]? = nil
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

                if let fileScopes {
                    let scopesForSource = fileScopes.filter { $0.sourceID == mount.sourceID }
                    guard !scopesForSource.isEmpty,
                          FileSelectionScope.allows(relativePath, in: scopesForSource) else {
                        continue
                    }
                }

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
            try assertFileVisible(relativePath: relPath, mount: mount, access: resolved, originalPath: cleaned)
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
        try assertFileVisible(relativePath: relPath, mount: mount, access: resolved, originalPath: cleaned)
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

        // Filter mode gate — Off / Warn / Block per the Settings ▸ Privacy
        // ▸ Sensitive Content Detection user preference. Composes after
        // rule eval and before privacy preflight so user choice can deny
        // even when rules and overrides allow.
        try await enforceFilterMode(
            sourceID: artifact?.sourceID,
            mountName: mountName,
            relativePath: relativePath,
            canonicalPath: canonicalPath,
            content: read.text,
            grantID: grantID
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

    /// Filter mode enforcement layer per the redesign plan's eng-review
    /// Issue 1. Composes after rule eval and per-file visibility overrides
    /// so user-preference enforcement can deny even when rules + overrides
    /// allow. Disabled (no-op) when the agent's effective mode is .off,
    /// which is the default until the user changes it in Settings.
    ///
    /// Layer order at file-read time:
    ///   1. RuleEngine.evaluate() — already ran before bytes were read
    ///   2. FileVisibilityOverrideStore — already evaluated upstream
    ///   3. THIS — filter mode (off / warn / block) against findings
    ///
    /// Modes:
    ///   off    — bypass entirely
    ///   warn   — log a warning to the audit trail with finding counts
    ///   block  — deny unless an explicit grant-level override exists in
    ///            FilterModeStore for (grantID, agent, sourceID, path)
    private func enforceFilterMode(
        sourceID: String?,
        mountName: String,
        relativePath: String,
        canonicalPath: String,
        content: String,
        grantID: String
    ) async throws {
        // Default-off when the plumbing isn't wired (e.g., test bridges
        // built without the filter-mode dependency). Real bridges always
        // pass these in via ManifoldRuntime.bridge(for:).
        guard let filterModeStore, let filterModeFindingsProvider else { return }

        let mode: FilterMode
        do {
            mode = try await filterModeStore.mode(for: targetApp)
        } catch {
            // Reading the preference shouldn't fail open OR closed for
            // the wrong reason. Log + treat as .off so a misconfigured
            // store doesn't block legitimate reads.
            logger.error("Filter mode: failed to read preference — \(String(describing: error), privacy: .public)")
            return
        }
        guard mode != .off else { return }

        let findings = await filterModeFindingsProvider.findings(
            forFile: canonicalPath,
            content: content
        )
        guard !findings.isEmpty else { return }

        switch mode {
        case .off:
            return // already filtered above; defensive
        case .warn:
            try? await auditStore.log(
                action: .fileRead,
                agent: agentName,
                filePath: canonicalPath,
                metadata: mergedMetadata([
                    "grant_id": grantID,
                    "filter_mode": "warn",
                    "findings_total": "\(findings.totalCount)",
                    "findings_secrets": "\(findings.secretCount)",
                    "findings_pii": "\(findings.piiCount)",
                ]),
                grantID: grantID
            )
        case .block:
            // Honor an existing override-and-share approval — the user
            // explicitly clicked through the warning sheet for this file
            // in this grant. The override is per-(grant, agent, source,
            // path) so a re-grant requires a fresh approval.
            if let sourceID {
                let hasOverride = (try? await filterModeStore.hasOverride(
                    grantID: grantID,
                    agent: targetApp,
                    sourceID: sourceID,
                    relativePath: relativePath
                )) ?? false
                if hasOverride {
                    try? await auditStore.log(
                        action: .fileRead,
                        agent: agentName,
                        filePath: canonicalPath,
                        metadata: mergedMetadata([
                            "grant_id": grantID,
                            "filter_mode": "block_overridden",
                            "findings_total": "\(findings.totalCount)",
                        ]),
                        grantID: grantID
                    )
                    return
                }
            }
            try? await auditStore.log(
                action: .fileRead,
                agent: agentName,
                filePath: canonicalPath,
                metadata: mergedMetadata([
                    "grant_id": grantID,
                    "filter_mode": "block",
                    "filter_decision": "deny",
                    "findings_total": "\(findings.totalCount)",
                    "findings_secrets": "\(findings.secretCount)",
                    "findings_pii": "\(findings.piiCount)",
                ]),
                grantID: grantID
            )
            throw ManifoldMCPError.ruleDenied(
                ruleName: "Sensitive content detection (Block mode)",
                explanation: filterModeDenyExplanation(for: findings)
            )
        }
    }

    private func filterModeDenyExplanation(for findings: FilterFindingsSummary) -> String {
        var parts: [String] = []
        if findings.secretCount > 0 {
            parts.append("\(findings.secretCount) secret\(findings.secretCount == 1 ? "" : "s")")
        }
        if findings.piiCount > 0 {
            parts.append("\(findings.piiCount) PII match\(findings.piiCount == 1 ? "" : "es")")
        }
        if findings.financialCount > 0 {
            parts.append("\(findings.financialCount) financial value\(findings.financialCount == 1 ? "" : "s")")
        }
        let summary = parts.joined(separator: ", ")
        return "File contains \(summary). Block mode is enabled — open Settings ▸ Privacy ▸ Sensitive Content Detection to override per-file or change the mode."
    }

    /// Applies unified RuleStore email rules to governed email reads after
    /// mailbox sensitivity checks and before any message body is delivered.
    private func enforceEmailReadRules(email: EmailMessageRecord, grantID: String?) async throws {
        guard let ruleStore else { return }
        let rules: [RuleRecord]
        do {
            rules = try await ruleStore.rules(scope: .email)
        } catch {
            logger.error("Rule gate: failed to load email rules — \(String(describing: error), privacy: .public)")
            return
        }
        guard !rules.isEmpty else { return }

        let receivedAt = ISO8601DateFormatter.shared.date(from: email.receivedAt) ?? Date()
        let probe = EmailProbe(
            emailID: email.emailID,
            senderEmail: email.senderEmail ?? email.sender,
            senderDomain: email.senderDomain ?? "",
            subject: email.subject,
            bodyText: email.bodyText ?? email.preview ?? "",
            folder: email.mailbox,
            accountID: email.accountID,
            hasAttachment: email.attachmentCount > 0,
            receivedAt: receivedAt
        )
        let decision = RuleEngine().evaluate(
            .emailRead(emailID: email.emailID),
            against: rules,
            agent: targetApp,
            context: RuleEvalContext(emailProbe: probe)
        )

        switch decision.action {
        case .deny:
            if let ruleID = decision.matchedRuleID {
                await ruleStore.recordMatch(id: ruleID)
            }
            try? await auditStore.log(
                action: .fileRead,
                agent: agentName,
                filePath: email.emailID,
                metadata: mergedMetadata([
                    "grant_id": grantID ?? "",
                    "rule_scope": "email",
                    "rule_decision": "deny",
                    "matched_rule_id": decision.matchedRuleID ?? "",
                    "matched_rule_name": decision.matchedRuleName ?? "",
                ]),
                grantID: grantID
            )
            throw ManifoldMCPError.ruleDenied(
                ruleName: decision.matchedRuleName ?? "email rule",
                explanation: decision.explanation
            )
        case .warn, .redact, .summarize, .downgrade, .log:
            if let ruleID = decision.matchedRuleID {
                await ruleStore.recordMatch(id: ruleID)
            }
            try? await auditStore.log(
                action: .fileRead,
                agent: agentName,
                filePath: email.emailID,
                metadata: mergedMetadata([
                    "grant_id": grantID ?? "",
                    "rule_scope": "email",
                    "rule_decision": decision.action.rawValue,
                    "matched_rule_id": decision.matchedRuleID ?? "",
                    "matched_rule_name": decision.matchedRuleName ?? "",
                ]),
                grantID: grantID
            )
        case .allow:
            return
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

    // MARK: - Governed Writes

    public func writeFile(
        path: String,
        content: String,
        intent: AccessIntent? = nil,
        expectedBeforeHash: String? = nil
    ) async throws -> WriteResult {
        let cleaned = cleanPath(path)
        let ext = (cleaned as NSString).pathExtension.lowercased()
        if Self.textWriteBlockedExtensions.contains(ext) {
            throw ManifoldMCPError.invalidPath(
                "write_file is UTF-8 text only and refused to write .\(ext) binary content to \(cleaned). Use annotate_pdf for PDF stamps or write_binary_file with content_base64 for binary files."
            )
        }
        let data = Data(content.utf8)
        return try await writeBytes(
            path: cleaned,
            options: GovernedWriteOptions(
                toolName: "write_file",
                data: data,
                mimeType: "text/plain; charset=utf-8",
                intent: intent,
                expectedBeforeHash: expectedBeforeHash,
                writeMode: .direct,
                isBinary: false
            )
        )
    }

    public func writeBinaryFile(
        path: String,
        contentBase64: String,
        mimeType: String?,
        intent: AccessIntent? = nil,
        expectedBeforeHash: String? = nil,
        writeMode: String? = nil
    ) async throws -> WriteResult {
        guard contentBase64.utf8.count <= Self.maxDirectBinaryWriteBase64Characters else {
            throw ManifoldMCPError.invalidPath("write_binary_file payload is too large for a direct MCP write. Limit is \(Self.maxDirectBinaryWriteBytes) decoded bytes; use a draft workspace or a dedicated operation for larger files.")
        }
        let cleanedBase64 = contentBase64
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        guard let data = Data(base64Encoded: cleanedBase64) else {
            throw ManifoldMCPError.invalidPath("write_binary_file content_base64 is not valid base64")
        }
        guard data.count <= Self.maxDirectBinaryWriteBytes else {
            throw ManifoldMCPError.invalidPath("write_binary_file decoded payload is too large for a direct MCP write. Limit is \(Self.maxDirectBinaryWriteBytes) bytes; use a draft workspace or a dedicated operation for larger files.")
        }
        let mode = writeMode.flatMap(GovernedWriteMode.init(rawValue:)) ?? .direct
        return try await writeBytes(
            path: path,
            options: GovernedWriteOptions(
                toolName: "write_binary_file",
                data: data,
                mimeType: mimeType,
                intent: intent,
                expectedBeforeHash: expectedBeforeHash,
                writeMode: mode,
                isBinary: true
            )
        )
    }

    public func annotatePDF(
        path: String,
        mark: String = "Viewed by Claude",
        intent: AccessIntent? = nil,
        expectedBeforeHash: String? = nil,
        writeMode: String? = nil
    ) async throws -> WriteResult {
        let readIntent = intent ?? AccessIntent(summary: "Read PDF bytes to apply a governed annotation.", details: nil)
        let original = try await readGovernedBytes(
            path: path,
            toolName: "annotate_pdf",
            intent: readIntent,
            maxBytes: Self.maxPDFAnnotationBytes
        )
        let ext = (original.canonicalPath as NSString).pathExtension.lowercased()
        guard ext == "pdf" else {
            throw ManifoldMCPError.invalidPath("annotate_pdf only accepts .pdf paths")
        }
        if let expectedBeforeHash = expectedBeforeHash?.trimmingCharacters(in: .whitespacesAndNewlines),
           !expectedBeforeHash.isEmpty {
            let currentHash = Self.sha256Hex(original.data)
            guard currentHash == expectedBeforeHash else {
                throw ManifoldMCPError.invalidPath("Hash mismatch for \(original.canonicalPath). Expected \(expectedBeforeHash.prefix(12)), current \(currentHash.prefix(12)). Re-read the file before writing.")
            }
        }
        guard original.data.starts(with: Data([0x25, 0x50, 0x44, 0x46])) else {
            throw ManifoldMCPError.invalidPath("annotate_pdf refused a file that does not start with a PDF header")
        }
        guard let document = PDFDocument(data: original.data) else {
            throw ManifoldMCPError.invalidPath("annotate_pdf can only modify readable PDF documents")
        }
        guard document.pageCount <= Self.maxPDFAnnotationPages else {
            throw ManifoldMCPError.invalidPath("annotate_pdf refused a PDF with \(document.pageCount) pages; limit is \(Self.maxPDFAnnotationPages)")
        }
        guard let page = document.page(at: 0) else {
            throw ManifoldMCPError.invalidPath("annotate_pdf cannot modify an empty PDF")
        }

        let pageBounds = page.bounds(for: .mediaBox)
        let annotationBounds = CGRect(
            x: max(pageBounds.minX + 24, pageBounds.maxX - 176),
            y: pageBounds.minY + 24,
            width: 152,
            height: 24
        )
        let annotation = PDFAnnotation(bounds: annotationBounds, forType: .freeText, withProperties: nil)
        annotation.contents = String(mark.prefix(80))
        annotation.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        annotation.fontColor = .systemBlue
        annotation.color = NSColor.systemBlue.withAlphaComponent(0.08)
        page.addAnnotation(annotation)

        guard let updatedData = document.dataRepresentation() else {
            throw ManifoldMCPError.invalidPath("annotate_pdf could not serialize the modified PDF")
        }

        let mode = writeMode.flatMap(GovernedWriteMode.init(rawValue:)) ?? .direct
        return try await writeBytes(
            path: original.canonicalPath,
            options: GovernedWriteOptions(
                toolName: "annotate_pdf",
                data: updatedData,
                mimeType: "application/pdf",
                intent: intent,
                expectedBeforeHash: expectedBeforeHash,
                writeMode: mode,
                isBinary: true
            )
        )
    }

    private func writeBytes(path: String, options: GovernedWriteOptions) async throws -> WriteResult {
        let data = options.data
        await logToolCall(
            tool: options.toolName,
            arguments: [
                "path": path,
                "bytes": "\(data.count)",
                "mime_type": options.mimeType ?? "",
                "write_mode": options.writeMode.rawValue,
            ]
        )
        let cleaned = cleanPath(path)
        let validatedIntent = try await validatedAccessIntent(for: options.toolName, provided: options.intent)

        guard !cleaned.hasPrefix("_emails/") else {
            throw ManifoldMCPError.invalidPath("Cannot write to email files (read-only)")
        }

        let accessContext: AccessContext
        do {
            accessContext = try await resolveAccessForWrite(cleanedPath: cleaned)
        } catch {
            let denied = deniedDecisionContext(for: error)
            _ = await recordAccessDecision(
                toolName: options.toolName,
                resourcePath: cleaned,
                action: "write",
                allowed: false,
                reason: denied.reason,
                accessMode: denied.accessMode,
                intent: validatedIntent
            )
            throw error
        }

        let access: ResolvedMounts
        let writeID: String
        let writeSource: String
        let writeGrantID: String?
        let writeTarget: ResolvedWriteTarget

        switch accessContext {
        case .standing(let policy, let sources):
            let standing = try await resolveStandingWrite(
                cleanedPath: cleaned,
                policy: policy,
                sources: sources,
                options: options,
                intent: validatedIntent
            )
            switch standing {
            case .ready(let resolvedAccess, let resolvedWriteID, let resolvedWriteSource, let resolvedWriteGrantID, let target):
                access = resolvedAccess
                writeID = resolvedWriteID
                writeSource = resolvedWriteSource
                writeGrantID = resolvedWriteGrantID
                writeTarget = target
            case .escalation(let result):
                return result
            }

        case .workBlock(let grant, let grantSources, _):
            if Self.isDraftWorkspaceGrant(grant) {
                let resolved = try await resolveTrackedWrite(
                    cleanedPath: cleaned,
                    grant: grant,
                    grantSources: grantSources,
                    toolName: options.toolName,
                    intent: validatedIntent
                )
                access = resolved.access
                writeID = grant.grantID
                writeSource = "mcp"
                writeGrantID = grant.grantID
                writeTarget = resolved.target
            } else {
                let resolved = try await resolveSessionGatewayWrite(
                    cleanedPath: cleaned,
                    grant: grant,
                    grantSources: grantSources,
                    toolName: options.toolName,
                    intent: validatedIntent
                )
                access = resolved.access
                writeID = grant.grantID
                writeSource = "mcp_session_gateway"
                writeGrantID = grant.grantID
                writeTarget = resolved.target
            }

        case .legacyGrant(let grant, let grantSources):
            let resolved = try await resolveTrackedWrite(
                cleanedPath: cleaned,
                grant: grant,
                grantSources: grantSources,
                toolName: options.toolName,
                intent: validatedIntent
            )
            access = resolved.access
            writeID = grant.grantID
            writeSource = "mcp"
            writeGrantID = grant.grantID
            writeTarget = resolved.target
        }

        let effectiveWriteSource = (!access.isStanding && Self.isDraftWorkspaceGrant(access.grant)) ? "mcp_draft_workspace" : writeSource
        let targetMount = writeTarget.mount
        let resolvedPath = writeTarget.relativePath
        let targetIdentity = writeTarget.identity
        let canonicalPath = writeTarget.canonicalPath
        let existed = targetIdentity.exists

        let existingData: Data?
        if existed {
            existingData = try ScopedFileAccess.readData(
                relativePath: resolvedPath,
                rootPath: targetMount.mountPath
            ).data
        } else {
            existingData = nil
        }
        let observedBeforeHash = existingData.map(Self.sha256Hex)
        if let expectedBeforeHash = options.expectedBeforeHash?.trimmingCharacters(in: .whitespacesAndNewlines),
           !expectedBeforeHash.isEmpty {
            guard existingData != nil else {
                throw ManifoldMCPError.invalidPath("expected_before_hash was provided, but \(canonicalPath) does not exist")
            }
            guard observedBeforeHash == expectedBeforeHash else {
                throw ManifoldMCPError.invalidPath("Hash mismatch for \(canonicalPath). Expected \(expectedBeforeHash.prefix(12)), current \((observedBeforeHash ?? "").prefix(12)). Re-read the file before writing.")
            }
        }

        try await enforceFileWriteRules(
            target: writeTarget,
            options: options,
            runID: writeID
        )

        if access.usesOriginalSources,
           let existingData,
           try await snapshotStore.latestHash(runID: writeID, filePath: canonicalPath) == nil {
            try await snapshotStore.recordBaseline(
                runID: writeID,
                workspaceID: targetMount.sourceID,
                filePath: canonicalPath,
                data: existingData
            )
        }
        try await revalidateWriteAccessBeforeMutation(
            access: access,
            target: writeTarget
        )
        try verifyWritePreconditionStillMatches(
            target: writeTarget,
            existed: existed,
            observedBeforeHash: observedBeforeHash
        )
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

        let snapshot: SnapshotWriteResult
        do {
            if let grant = access.grant {
                try await artifactIndex.upsertFile(
                    grantID: grant.grantID,
                    mount: ArtifactMount(sourceID: targetMount.sourceID, mountName: targetMount.mountName, mountPath: targetMount.mountPath),
                    relativePath: resolvedPath,
                    fileURL: writtenIdentity.fileURL
                )
            }

            snapshot = try await snapshotStore.recordModification(
                runID: writeID,
                workspaceID: targetMount.sourceID,
                filePath: canonicalPath,
                newData: data,
                source: effectiveWriteSource
            )
        } catch {
            rollbackWriteAfterVersioningFailure(
                target: writeTarget,
                existed: existed,
                existingData: existingData
            )
            throw error
        }
        if let writeGrantID,
           let block = try await workBlockStore?.activeBlock(for: targetApp),
           block.grantID == writeGrantID {
            try? await refreshWorkBlockCounts(blockID: block.id, runID: writeGrantID)
        }

        var writeMetadata = mergedMetadata([
            "mount": targetMount.mountName,
            "bytes": "\(data.count)",
            "snapshot_id": "\(snapshot.id)",
            "access_mode": access.usesOriginalSources ? effectiveWriteSource : "tracked_run",
            "tool": options.toolName,
            "write_mode": options.writeMode.rawValue,
            "mime_type": options.mimeType ?? "",
            "is_binary": options.isBinary ? "true" : "false",
        ])
        if let expectedBeforeHash = options.expectedBeforeHash, !expectedBeforeHash.isEmpty {
            writeMetadata["expected_before_hash"] = expectedBeforeHash
        }
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
        return .written(
            message: writeSuccessMessage(
                byteCount: data.count,
                canonicalPath: canonicalPath,
                snapshotID: snapshot.id,
                existed: existed,
                directOriginalWrite: access.usesOriginalSources,
                writeSource: effectiveWriteSource
            ),
            path: canonicalPath
        )
    }

    private func enforceFileWriteRules(
        target: ResolvedWriteTarget,
        options: GovernedWriteOptions,
        runID: String
    ) async throws {
        guard let ruleStore else { return }
        let rules: [RuleRecord]
        do {
            rules = try await ruleStore.rules(scope: .file)
        } catch {
            logger.error("Rule gate: failed to load file write rules — \(String(describing: error), privacy: .public)")
            return
        }
        guard !rules.isEmpty else { return }

        let fileProbe = Self.makeWriteFileProbe(
            canonicalPath: target.canonicalPath,
            data: options.data,
            isBinary: options.isBinary
        )
        let agentProbe = AgentProbe(
            agent: targetApp,
            tool: .write,
            payloadBytes: Int64(options.data.count)
        )
        let decision = RuleEngine().evaluate(
            .fileWrite(path: target.canonicalPath),
            against: rules,
            agent: targetApp,
            context: RuleEvalContext(fileProbe: fileProbe, agentProbe: agentProbe)
        )

        switch decision.action {
        case .deny:
            if let ruleID = decision.matchedRuleID {
                await ruleStore.recordMatch(id: ruleID)
            }
            try? await auditStore.log(
                action: .toolCall,
                runID: runID,
                workspaceID: target.mount.sourceID,
                agent: agentName,
                filePath: target.canonicalPath,
                metadata: mergedMetadata([
                    "tool": options.toolName,
                    "rule_scope": "file",
                    "rule_request": "file_write",
                    "rule_decision": "deny",
                    "matched_rule_id": decision.matchedRuleID ?? "",
                    "matched_rule_name": decision.matchedRuleName ?? "",
                    "bytes": "\(options.data.count)",
                ])
            )
            throw ManifoldMCPError.ruleDenied(
                ruleName: decision.matchedRuleName ?? "write rule",
                explanation: decision.explanation
            )

        case .warn, .redact, .summarize, .downgrade, .log:
            if let ruleID = decision.matchedRuleID {
                await ruleStore.recordMatch(id: ruleID)
            }
            try? await auditStore.log(
                action: .toolCall,
                runID: runID,
                workspaceID: target.mount.sourceID,
                agent: agentName,
                filePath: target.canonicalPath,
                metadata: mergedMetadata([
                    "tool": options.toolName,
                    "rule_scope": "file",
                    "rule_request": "file_write",
                    "rule_decision": decision.action.rawValue,
                    "matched_rule_id": decision.matchedRuleID ?? "",
                    "matched_rule_name": decision.matchedRuleName ?? "",
                    "bytes": "\(options.data.count)",
                ])
            )

        case .allow:
            break
        }
    }

    private func revalidateWriteAccessBeforeMutation(
        access: ResolvedMounts,
        target: ResolvedWriteTarget
    ) async throws {
        if access.usesOriginalSources {
            let freshGrant: GrantRecord?
            if let grant = access.grant {
                guard let activeGrant = try await grantStore.grant(id: grant.grantID),
                      activeGrant.isActive else {
                    throw ManifoldMCPError.noActiveSession
                }
                freshGrant = activeGrant
            } else {
                freshGrant = nil
            }

            let policy: AgentAccessPolicy?
            if let policyStore {
                policy = try await policyStore.policy(for: targetApp)
                if policy?.isPaused == true {
                    throw ManifoldMCPError.accessPaused
                }
            } else {
                policy = nil
            }

            if let freshGrant, freshGrant.explicitSelection {
                let scopes = try await grantFileScopes(for: freshGrant)
                let scopesForSource = scopes.filter { $0.sourceID == target.mount.sourceID }
                guard !scopesForSource.isEmpty,
                      FileSelectionScope.allows(target.relativePath, in: scopesForSource) else {
                    throw ManifoldMCPError.fileNotFound(target.canonicalPath)
                }
            } else if let policy {
                guard policy.allowedSourceIDs.contains(target.mount.sourceID) else {
                    throw ManifoldMCPError.invalidPath("The source for \(target.canonicalPath) is no longer shared with \(targetApp.rawValue). Re-list files before writing.")
                }
            }

            guard let source = try await grantStore.source(id: target.mount.sourceID),
                  source.isAccessible else {
                throw ManifoldMCPError.fileNotFound(target.canonicalPath)
            }

            let currentMounts = [
                GrantMount(
                    sourceID: source.sourceID,
                    mountName: target.mount.mountName,
                    mountPath: source.originalRootPath
                )
            ]
            let currentTarget = try resolveWriteTarget(
                target.canonicalPath,
                in: currentMounts,
                requireMountPrefix: true
            )
            guard currentTarget.mount.sourceID == target.mount.sourceID,
                  currentTarget.mount.mountPath == target.mount.mountPath,
                  currentTarget.relativePath == target.relativePath else {
                throw ManifoldMCPError.invalidPath("The source mapping for \(target.canonicalPath) changed while the write was in progress. Re-list files before writing.")
            }

            if let policy, freshGrant?.explicitSelection != true {
                let resolver = try await standingFileVisibilityResolver(for: policy)
                let visibility = resolver.evaluate(
                    sourceID: target.mount.sourceID,
                    relativePath: target.relativePath,
                    defaultVisible: policy.allowedSourceIDs.contains(target.mount.sourceID)
                )
                guard visibility.isVisible else {
                    throw ManifoldMCPError.fileNotFound(target.canonicalPath)
                }
            }
        } else if let grant = access.grant {
            guard let freshGrant = try await grantStore.grant(id: grant.grantID),
                  freshGrant.isActive else {
                throw ManifoldMCPError.noActiveSession
            }
            if let source = try await grantStore.source(id: target.mount.sourceID),
               !source.isAccessible {
                throw ManifoldMCPError.fileNotFound(target.canonicalPath)
            }
        }
    }

    private func verifyWritePreconditionStillMatches(
        target: ResolvedWriteTarget,
        existed: Bool,
        observedBeforeHash: String?
    ) throws {
        if existed {
            do {
                let currentData = try ScopedFileAccess.readData(
                    relativePath: target.relativePath,
                    rootPath: target.mount.mountPath
                ).data
                let currentHash = Self.sha256Hex(currentData)
                guard currentHash == observedBeforeHash else {
                    throw ManifoldMCPError.invalidPath("The governed file changed while the write was being prepared. Re-read \(target.canonicalPath) before writing.")
                }
            } catch let error as ManifoldMCPError {
                throw error
            } catch let error as ManifoldError {
                throw ManifoldMCPError.invalidPath(error.localizedDescription)
            }
        } else {
            do {
                let currentIdentity = try ScopedFileAccess.resolve(
                    relativePath: target.relativePath,
                    rootPath: target.mount.mountPath,
                    allowMissingLeaf: true
                )
                guard !currentIdentity.exists else {
                    throw ManifoldMCPError.invalidPath("\(target.canonicalPath) was created while the write was being prepared. Re-read the folder before writing.")
                }
            } catch let error as ManifoldMCPError {
                throw error
            } catch let error as ManifoldError {
                throw ManifoldMCPError.invalidPath(error.localizedDescription)
            }
        }
    }

    private func rollbackWriteAfterVersioningFailure(
        target: ResolvedWriteTarget,
        existed: Bool,
        existingData: Data?
    ) {
        do {
            if existed, let existingData {
                _ = try ScopedFileAccess.writeDataAtomically(
                    existingData,
                    relativePath: target.relativePath,
                    rootPath: target.mount.mountPath
                )
            } else {
                let identity = try ScopedFileAccess.resolve(
                    relativePath: target.relativePath,
                    rootPath: target.mount.mountPath,
                    allowMissingLeaf: true
                )
                if FileManager.default.fileExists(atPath: identity.fileURL.path) {
                    try FileManager.default.removeItem(at: identity.fileURL)
                }
            }
        } catch {
            logger.error("Failed to roll back governed write after versioning failure for \(target.canonicalPath, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private nonisolated static func makeWriteFileProbe(
        canonicalPath: String,
        data: Data,
        isBinary: Bool
    ) -> FileProbe {
        FileProbe(
            path: canonicalPath,
            sizeBytes: { Int64(data.count) },
            modifiedAt: { Date() },
            isHidden: {
                URL(fileURLWithPath: canonicalPath).lastPathComponent.hasPrefix(".")
            },
            isBinary: {
                isBinary || data.prefix(512).contains(0)
            },
            isGitignored: { false },
            containsSecret: {
                Self.containsSecret(in: data)
            }
        )
    }

    private nonisolated static func containsSecret(in data: Data) -> Bool {
        let prefix = Data(data.prefix(64 * 1024))
        guard let text = String(data: prefix, encoding: .utf8) else { return false }
        let needles = [
            "AKIA",
            "-----BEGIN PRIVATE KEY-----",
            "-----BEGIN RSA PRIVATE KEY-----",
            "-----BEGIN OPENSSH PRIVATE KEY-----",
            "ghp_",
            "ghs_",
            "xoxb-",
            "xoxp-",
        ]
        if needles.contains(where: { text.contains($0) }) { return true }
        return text.range(
            of: #"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#,
            options: .regularExpression
        ) != nil
    }

    private nonisolated static func isDraftWorkspaceGrant(_ grant: GrantRecord?) -> Bool {
        grant?.summaryFraming == "Manifold draft workspace for governed AI file writes."
    }

    private func resolveAccessForWrite(cleanedPath: String) async throws -> AccessContext {
        if let session = try await activeSessionAccessForWrite() {
            return session
        }
        if let standing = try await directStandingAccessForWrite(cleanedPath: cleanedPath) {
            return standing
        }
        return try await resolveAccess()
    }

    private func activeSessionAccessForWrite() async throws -> AccessContext? {
        guard let policyStore,
              let wbStore = workBlockStore,
              let block = try await wbStore.activeBlock(for: targetApp),
              let grant = try await grantStore.grant(id: block.grantID),
              !Self.isDraftWorkspaceGrant(grant) else {
            return nil
        }
        let policy = try await policyStore.policy(for: targetApp)
        if policy.isPaused {
            throw ManifoldMCPError.accessPaused
        }
        let grantSources = try await scopedGrantSources(grant: grant, policy: policy)
        return .workBlock(grant: grant, grantSources: grantSources, block: block)
    }

    /// Normal governed writes should land in the original shared folder,
    /// even if a previous draft session is still active. Only
    /// source-level shared folders are writable in standing mode; explicit
    /// file overrides stay read-only unless a draft workspace is the only
    /// available access path.
    private func directStandingAccessForWrite(cleanedPath: String) async throws -> AccessContext? {
        guard let policyStore else { return nil }
        let policy = try await policyStore.policy(for: targetApp)
        if policy.isPaused {
            throw ManifoldMCPError.accessPaused
        }
        guard !policy.allowedSourceIDs.isEmpty else {
            return nil
        }

        let allSources = try await grantStore.activeSources()
        let allowedSources = allSources.filter { policy.allowedSourceIDs.contains($0.sourceID) }
        guard !allowedSources.isEmpty else { return nil }

        let mounts = standingMounts(sources: allowedSources)
        if resolveMountAndPath(cleanedPath, in: mounts) != nil {
            return .standing(policy: policy, sources: allowedSources)
        }

        if let first = cleanedPath.split(separator: "/", maxSplits: 1).first {
            let firstComponent = String(first)
            let allMountNames = Set(allSources.map(\.canonicalMountName))
            let allowedMountNames = Set(mounts.map(\.mountName))
            if allMountNames.contains(firstComponent), !allowedMountNames.contains(firstComponent) {
                return nil
            }
        }

        if mounts.count == 1 {
            return .standing(policy: policy, sources: allowedSources)
        }

        let existingMatches = mounts.filter { mount in
            guard let url = try? validatePath(cleanedPath, rootPath: mount.mountPath) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
        return existingMatches.count == 1 ? .standing(policy: policy, sources: allowedSources) : nil
    }

    private func refreshWorkBlockCounts(blockID: String, runID: String) async throws {
        guard let workBlockStore else { return }
        let paths = try await snapshotStore.modifiedFiles(runID: runID)
        var modified = 0
        var created = 0
        for path in paths {
            if try await snapshotStore.baselineHash(runID: runID, filePath: path) == nil {
                created += 1
            } else {
                modified += 1
            }
        }
        try await workBlockStore.updateCounts(id: blockID, modifiedFiles: modified, newFiles: created)
    }

    private nonisolated func writeSuccessMessage(
        byteCount: Int,
        canonicalPath: String,
        snapshotID: Int,
        existed: Bool,
        directOriginalWrite: Bool,
        writeSource: String
    ) -> String {
        let action = existed ? "Updated" : "Created"
        if directOriginalWrite {
            return "\(action) \(canonicalPath) in the original folder (\(byteCount) bytes). Manifold recorded snapshot #\(snapshotID) for version history."
        }
        let workspaceKind = writeSource == "mcp_draft_workspace" ? "draft workspace" : "workspace"
        return "\(action) \(canonicalPath) in the Manifold \(workspaceKind) (\(byteCount) bytes). The original folder is unchanged until the user applies the workspace. Manifold recorded snapshot #\(snapshotID)."
    }

    private func resolveStandingWrite(
        cleanedPath: String,
        policy: AgentAccessPolicy,
        sources: [SourceRecord],
        options: GovernedWriteOptions,
        intent: AccessIntent?
    ) async throws -> StandingWriteResolution {
        let mounts = standingMounts(sources: sources)
        let target = try resolveWriteTarget(cleanedPath, in: mounts, requireMountPrefix: true)
        let visibilityResolver = try await standingFileVisibilityResolver(for: policy)
        let visibility = visibilityResolver.evaluate(
            sourceID: target.mount.sourceID,
            relativePath: target.relativePath,
            defaultVisible: policy.allowedSourceIDs.contains(target.mount.sourceID)
        )
        guard visibility.isVisible else {
            _ = await recordAccessDecision(
                toolName: options.toolName,
                resourcePath: target.canonicalPath,
                action: "write",
                allowed: false,
                reason: "standing_access",
                accessMode: "standing",
                policySnapshot: policySnapshot(for: policy),
                intent: intent
            )
            throw ManifoldMCPError.fileNotFound(target.canonicalPath)
        }
        guard policy.allowedSourceIDs.contains(target.mount.sourceID) else {
            _ = await recordAccessDecision(
                toolName: options.toolName,
                resourcePath: target.canonicalPath,
                action: "write",
                allowed: false,
                reason: "standing_access",
                accessMode: "standing",
                policySnapshot: policySnapshot(for: policy),
                intent: intent
            )
            throw ManifoldMCPError.invalidPath("Standing writes require the folder to remain in default scope. Explicit file overrides are read-only until a tracked session starts.")
        }

        if options.writeMode == .draftWorkspace {
            return try await resolveDraftWrite(
                draftPath: target.relativePath,
                sourceID: target.mount.sourceID,
                toolName: options.toolName,
                policy: policy,
                intent: intent
            )
        }

        let accessDecisionID = await recordAccessDecision(
            toolName: options.toolName,
            resourcePath: target.canonicalPath,
            action: "write",
            allowed: true,
            reason: "standing_access",
            accessMode: StandingWriteMode.automatic.rawValue,
            policySnapshot: policySnapshot(for: policy),
            intent: intent
        )
        return .ready(
            access: ResolvedMounts(
                mounts: mounts,
                grantID: nil,
                grant: nil,
                isStanding: true,
                usesOriginalSources: true,
                decisionID: accessDecisionID,
                standingPolicy: policy,
                standingResolver: visibilityResolver,
                fileScopes: nil
            ),
            writeID: "standing-write:\(target.mount.sourceID)",
            writeSource: StandingWriteMode.automatic.rawValue,
            writeGrantID: nil,
            target: target
        )
    }

    private func resolveTrackedWrite(
        cleanedPath: String,
        grant: GrantRecord,
        grantSources: [GrantSourceRecord],
        toolName: String,
        intent: AccessIntent?
    ) async throws -> (access: ResolvedMounts, target: ResolvedWriteTarget) {
        let accessDecisionID = await recordAccessDecision(
            toolName: toolName,
            resourcePath: cleanedPath,
            action: "write",
            allowed: true,
            reason: "work_block",
            accessMode: "tracked_run",
            intent: intent
        )
        let access = ResolvedMounts(
            mounts: grantMounts(grant: grant, sources: grantSources),
            grantID: grant.grantID,
            grant: grant,
            isStanding: false,
            usesOriginalSources: false,
            decisionID: accessDecisionID,
            standingPolicy: nil,
            standingResolver: nil,
            fileScopes: nil
        )
        let target = try resolveWriteTarget(cleanedPath, in: access.mounts)
        try await assertWritableScope(relativePath: target.relativePath, mount: target.mount, grant: grant)
        return (access, target)
    }

    private func resolveSessionGatewayWrite(
        cleanedPath: String,
        grant: GrantRecord,
        grantSources: [GrantSourceRecord],
        toolName: String,
        intent: AccessIntent?
    ) async throws -> (access: ResolvedMounts, target: ResolvedWriteTarget) {
        let policy = try await policyStore?.policy(for: targetApp)
        let resolver: FileVisibilityResolver?
        if let policy, !grant.explicitSelection {
            resolver = try await standingFileVisibilityResolver(for: policy)
        } else {
            resolver = nil
        }
        let scopes = grant.explicitSelection ? try await grantFileScopes(for: grant) : nil
        let accessDecisionID = await recordAccessDecision(
            toolName: toolName,
            resourcePath: cleanedPath,
            action: "write",
            allowed: true,
            reason: "session_gateway",
            accessMode: "session_gateway",
            policySnapshot: "{\"grant_id\":\"\(grant.grantID)\"}",
            intent: intent
        )
        let access = ResolvedMounts(
            mounts: try await originalMounts(sources: grantSources),
            grantID: grant.grantID,
            grant: grant,
            isStanding: false,
            usesOriginalSources: true,
            decisionID: accessDecisionID,
            standingPolicy: grant.explicitSelection ? nil : policy,
            standingResolver: resolver,
            fileScopes: scopes
        )
        let target = try resolveWriteTarget(cleanedPath, in: access.mounts, requireMountPrefix: true)
        try assertFileVisible(
            relativePath: target.relativePath,
            mount: target.mount,
            access: access,
            originalPath: cleanedPath
        )
        return (access, target)
    }

    private func resolveDraftWrite(
        draftPath: String,
        sourceID: String,
        toolName: String,
        policy: AgentAccessPolicy,
        intent: AccessIntent?
    ) async throws -> StandingWriteResolution {
        let draft = try await ensureDraftWorkBlock(sourceID: sourceID)
        let resolved = try await resolveTrackedWrite(
            cleanedPath: draftPath,
            grant: draft.grant,
            grantSources: draft.sources,
            toolName: toolName,
            intent: intent
        )
        let target = resolved.target
        _ = await recordAccessDecision(
            toolName: toolName,
            resourcePath: target.canonicalPath,
            action: "write",
            allowed: true,
            reason: "standing_access",
            accessMode: GovernedWriteMode.draftWorkspace.rawValue,
            policySnapshot: policySnapshot(for: policy),
            intent: intent
        )
        return .ready(
            access: resolved.access,
            writeID: draft.grant.grantID,
            writeSource: "mcp_draft_workspace",
            writeGrantID: draft.grant.grantID,
            target: target
        )
    }

    private func ensureDraftWorkBlock(sourceID: String) async throws -> DraftWorkBlock {
        if let block = try await workBlockStore?.activeBlock(for: targetApp),
           let grant = try await grantStore.grant(id: block.grantID),
           Self.isDraftWorkspaceGrant(grant),
           block.sourceIDs.contains(sourceID) {
            return DraftWorkBlock(grant: grant, sources: try await grantStore.grantSources(grantID: grant.grantID))
        }

        guard let source = try await grantStore.source(id: sourceID), !source.isRemoved else {
            throw ManifoldMCPError.fileNotFound(sourceID)
        }

        let grant = try await grantStore.startGrant(
            targetApp: targetApp,
            profileID: profileID,
            sourceIDs: [sourceID],
            materializationRoot: Self.materializationRoot(grantID: "").path,
            emailSensitivity: "strict",
            summaryFraming: "Manifold draft workspace for governed AI file writes.",
            explicitSelection: false,
            noteCaptureMode: .off
        )
        let actualRoot = Self.materializationRoot(grantID: grant.grantID)
        try await grantStore.updateMaterializationRoot(grantID: grant.grantID, root: actualRoot.path)
        let updatedGrant = try await grantStore.grant(id: grant.grantID) ?? grant
        let grantSources = try await grantStore.grantSources(grantID: grant.grantID)
        let mountInputs = grantSources.compactMap { grantSource -> MaterializationEngine.MaterializationSource? in
            guard grantSource.sourceID == sourceID else { return nil }
            return MaterializationEngine.MaterializationSource(
                source: source,
                mountName: grantSource.mountName
            )
        }
        let results = try MaterializationEngine.materialize(
            grantID: grant.grantID,
            sources: mountInputs,
            materializationRoot: actualRoot.path
        )
        for result in results {
            try await grantStore.setBaselineHash(
                grantID: grant.grantID,
                sourceID: result.sourceID,
                hash: result.manifestHash
            )
            try await baselineSnapshotMount(
                grantID: grant.grantID,
                sourceID: result.sourceID,
                mountName: result.mountName,
                mountPath: result.mountPath
            )
        }
        try await artifactIndex.ensureGrantIndexed(
            grantID: grant.grantID,
            materializationRoot: actualRoot.path,
            mounts: results.map {
                ArtifactMount(sourceID: $0.sourceID, mountName: $0.mountName, mountPath: $0.mountPath)
            }
        )
        _ = try await workBlockStore?.startBlock(
            agent: targetApp,
            grantID: grant.grantID,
            sourceIDs: [sourceID]
        )
        try? await auditStore.log(
            action: .runStart,
            runID: grant.grantID,
            agent: agentName,
            metadata: [
                "grant_id": grant.grantID,
                "write_mode": GovernedWriteMode.draftWorkspace.rawValue,
                "source_id": sourceID,
            ],
            grantID: grant.grantID
        )
        return DraftWorkBlock(grant: updatedGrant, sources: grantSources)
    }

    private func readGovernedBytes(
        path: String,
        toolName: String,
        intent: AccessIntent?,
        maxBytes: Int? = nil
    ) async throws -> (data: Data, canonicalPath: String) {
        let cleaned = cleanPath(path)
        let validatedIntent = try await validatedAccessIntent(for: toolName, provided: intent)
        let access = try await resolveAccessMounts(toolName: toolName, action: "read", resourcePath: cleaned, intent: validatedIntent)
        let target = try resolveWriteTarget(cleaned, in: access.mounts)
        try assertFileVisible(
            relativePath: target.relativePath,
            mount: target.mount,
            access: access,
            originalPath: cleaned
        )
        guard target.identity.exists else {
            throw ManifoldMCPError.fileNotFound(target.canonicalPath)
        }
        if let maxBytes,
           let size = try? target.identity.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maxBytes {
            throw ManifoldMCPError.invalidPath("\(toolName) refused \(target.canonicalPath) because it is \(size) bytes; limit is \(maxBytes) bytes")
        }
        let data = try ScopedFileAccess.readData(
            relativePath: target.relativePath,
            rootPath: target.mount.mountPath
        ).data
        await recordExposure(
            toolName: toolName,
            resourcePath: target.canonicalPath,
            data: data,
            exposureType: "file_bytes",
            decisionID: access.decisionID,
            intent: validatedIntent
        )
        return (data, target.canonicalPath)
    }

    private func standingWriteContextJSON(
        target: ResolvedWriteTarget,
        options: GovernedWriteOptions
    ) -> String? {
        let object: [String: String] = [
            "path": target.canonicalPath,
            "source_id": target.mount.sourceID,
            "mount_name": target.mount.mountName,
            "relative_path": target.relativePath,
            "tool": options.toolName,
            "bytes": "\(options.data.count)",
            "mime_type": options.mimeType ?? "",
            "write_mode": options.writeMode.rawValue,
            "is_binary": options.isBinary ? "true" : "false",
            "intent_summary": options.intent?.summary ?? "",
            "expected_before_hash": options.expectedBeforeHash ?? "",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func baselineSnapshotMount(
        grantID: String,
        sourceID: String,
        mountName: String,
        mountPath: String
    ) async throws {
        let root = URL(fileURLWithPath: mountPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relative = Self.relativePath(for: url, base: root)
            guard !relative.hasPrefix(".manifold-") else { continue }
            let canonical = "\(mountName)/\(relative)"
            let data = try Data(contentsOf: url)
            try await snapshotStore.recordBaseline(
                runID: grantID,
                workspaceID: sourceID,
                filePath: canonical,
                data: data
            )
        }
    }

    private static func materializationRoot(grantID: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Manifold/materializations/\(grantID)/workspace")
    }

    private static func relativePath(for url: URL, base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(basePath + "/") else { return url.lastPathComponent }
        return String(filePath.dropFirst(basePath.count + 1))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public func searchFiles(query: String, intent: AccessIntent? = nil) async throws -> [(path: String, source: String, matches: [String])] {
        await logToolCall(tool: "search_files", arguments: ["query": query])
        let validatedIntent = try await validatedAccessIntent(for: "search_files", provided: intent)
        let resolved = try await resolveAccessMounts(toolName: "search_files", action: "search", intent: validatedIntent)
        let results: [(path: String, source: String, matches: [String])]

        // Standing access and normal sessions grep through live governed folders.
        if resolved.usesOriginalSources {
            results = try searchFilesInOriginals(
                query: query,
                mounts: resolved.mounts,
                policy: resolved.standingPolicy,
                resolver: resolved.standingResolver,
                fileScopes: resolved.fileScopes
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
        resolver: FileVisibilityResolver? = nil,
        fileScopes: [FileSelectionScope]? = nil
    ) throws -> [(path: String, source: String, matches: [String])] {
        let fm = FileManager.default
        let queryLower = query.lowercased()
        var results: [(path: String, source: String, matches: [String])] = []

        for mount in mounts {
            let rootURL = URL(fileURLWithPath: mount.mountPath).standardizedFileURL
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let basePath = rootURL.path + "/"
            while let fileURL = enumerator.nextObject() as? URL {
                let filePath = fileURL.standardizedFileURL.path
                guard filePath.hasPrefix(basePath) else { continue }
                let relativePath = String(filePath.dropFirst(basePath.count))

                let firstComponent = relativePath.split(separator: "/").first.map(String.init) ?? relativePath
                let skip = [".git", "node_modules", ".build", "Build", "DerivedData",
                            "Pods", "__pycache__", ".DS_Store"]
                if skip.contains(firstComponent) {
                    if fileURL.hasDirectoryPath { enumerator.skipDescendants() }
                    continue
                }

                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true else { continue }

                if let fileScopes {
                    let scopesForSource = fileScopes.filter { $0.sourceID == mount.sourceID }
                    guard !scopesForSource.isEmpty,
                          FileSelectionScope.allows(relativePath, in: scopesForSource) else {
                        continue
                    }
                }

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
            try assertFileVisible(relativePath: relPath, mount: mount, access: access, originalPath: cleaned)
        } else {
            let (mount, relPath) = try resolveBarePath(cleaned, in: mounts)
            mountPath = mount.mountPath
            mountName = mount.mountName
            resolvedPath = relPath
            try assertFileVisible(relativePath: relPath, mount: mount, access: access, originalPath: cleaned)
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
        try assertFileVisible(relativePath: relPath, mount: mount, access: access, originalPath: cleaned)

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
        try assertFileVisible(relativePath: relPath, mount: mount, access: access, originalPath: cleaned)

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
        try assertFileVisible(relativePath: resolved.relativePath, mount: resolved.mount, access: access, originalPath: cleaned)

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
        try assertFileVisible(relativePath: resolved.relativePath, mount: resolved.mount, access: access, originalPath: cleaned)

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

        if access.usesOriginalSources {
            let payload = try await standingStructuredSearchPayload(
                query: query,
                limit: limit,
                access: access,
                intent: validatedIntent
            )
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? "[]"
        }

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
                    "retrieval": [
                        "mode": hit.retrievalMode,
                        "chunk_id": (hit.chunkID as Any?) ?? NSNull(),
                        "content_hash": (hit.contentHash as Any?) ?? NSNull(),
                        "context": (hit.context as Any?) ?? NSNull(),
                    ],
                ]
            )
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let json = String(data: data, encoding: .utf8) ?? "[]"
        return json
    }

    private func standingStructuredSearchPayload(
        query: String,
        limit: Int,
        access: ResolvedMounts,
        intent: AccessIntent?
    ) async throws -> [[String: Any]] {
        let normalizedLimit = max(1, min(limit, 50))
        var payload: [[String: Any]] = []

        let fileResults = try searchFilesInOriginals(
            query: query,
            mounts: access.mounts,
            policy: access.standingPolicy,
            resolver: access.standingResolver,
            fileScopes: access.fileScopes
        )
        for result in fileResults where payload.count < normalizedLimit {
            var deliveredPreview: [String] = []
            for snippet in result.matches {
                do {
                    let deliveredSnippet = try await applyPrivacyPreflight(
                        toolName: "search_structured",
                        resourcePath: result.path,
                        text: snippet,
                        decisionID: access.decisionID,
                        grantID: access.grantID,
                        contentKind: .structuredResult
                    )
                    deliveredPreview.append(deliveredSnippet)
                    await recordExposure(
                        toolName: "search_structured",
                        resourcePath: result.path,
                        text: deliveredSnippet,
                        exposureType: "snippet",
                        decisionID: access.decisionID,
                        intent: intent
                    )
                } catch {
                    continue
                }
            }
            guard !deliveredPreview.isEmpty else { continue }
            payload.append([
                "kind": ArtifactKind.file.rawValue,
                "path": result.path,
                "source": result.source,
                "score": 0,
                "preview": deliveredPreview,
                "selection": selectionJSON(nil),
                "retrieval": [
                    "mode": "standing_file_search",
                    "chunk_id": NSNull(),
                    "content_hash": NSNull(),
                    "context": NSNull(),
                ],
            ])
        }

        if payload.count < normalizedLimit, access.standingPolicy != nil || access.grant != nil {
            let emailResults = try emailStore.searchEmailMessages(freeText: query, limit: normalizedLimit)
            for email in emailResults where payload.count < normalizedLimit {
                if let grant = access.grant {
                    guard try await isEmailAccessible(email: email, grant: grant) else { continue }
                } else if let policy = access.standingPolicy {
                    guard try await isEmailAccessible(email: email, policy: policy) else { continue }
                } else {
                    continue
                }
                let preview = [email.sender, email.subject, email.preview ?? ""]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                do {
                    let deliveredPreview = try await applyPrivacyPreflight(
                        toolName: "search_structured",
                        resourcePath: email.emailID,
                        text: preview,
                        decisionID: access.decisionID,
                        grantID: access.grantID,
                        contentKind: .email
                    )
                    payload.append([
                        "kind": ArtifactKind.email.rawValue,
                        "path": email.emailID,
                        "source": email.senderDomain ?? "email",
                        "score": 0,
                        "preview": [deliveredPreview],
                        "selection": selectionJSON(nil),
                        "retrieval": [
                            "mode": "standing_email_search",
                            "chunk_id": NSNull(),
                            "content_hash": NSNull(),
                            "context": NSNull(),
                        ],
                    ])
                    await recordExposure(
                        toolName: "search_structured",
                        resourcePath: email.emailID,
                        text: deliveredPreview,
                        exposureType: "email_preview",
                        decisionID: access.decisionID,
                        intent: intent
                    )
                } catch {
                    continue
                }
            }
        }

        return payload
    }

    // MARK: - Changes

    public func listChanges() async throws -> [ChangeInfo] {
        await logToolCall(tool: "list_changes")
        let access = try await resolveAccessMounts(toolName: "list_changes", action: "list")
        let grantID = access.grantID
        let scopedContext: AccessContext?
        if let grant = access.grant {
            let grantSources = access.mounts.map {
                GrantSourceRecord(grantID: grant.grantID, sourceID: $0.sourceID, mountName: $0.mountName)
            }
            scopedContext = .legacyGrant(grant: grant, grantSources: grantSources)
        } else if access.isStanding {
            var sources: [SourceRecord] = []
            for mount in access.mounts {
                if let source = try await grantStore.source(id: mount.sourceID) {
                    sources.append(source)
                }
            }
            scopedContext = .standing(policy: access.standingPolicy ?? AgentAccessPolicy(agent: targetApp), sources: sources)
        } else {
            scopedContext = nil
        }
        let entries = try await auditStore.recentEntries(limit: 50)
        let changes = entries
            .filter { entry in
                if let grantID {
                    return entry.grantID == grantID
                }
                guard let scopedContext, let path = entry.filePath else {
                    return false
                }
                return isResourcePath(path, inScopeOf: scopedContext)
            }
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

    // MARK: - Email Tools (reads from governed local mail archive)

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

        try await enforceEmailReadRules(email: email, grantID: grantID)

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
                    canonicalBlobCID: email.canonicalBlobCID,
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
    func persistExecResult(
        _ result: ExecRunResult,
        toolName: String,
        resourcePath: String?,
        decisionID: String?
    ) async -> ExecRunResult {
        let record = try? await execRunStore?.save(result: result)
        if let record {
            _ = try? await ledgerStore?.append(
                entryType: .execRun,
                subjectTable: "exec_runs",
                subjectID: record.runID,
                payload: Self.canonicalJSON(record),
                metadata: ["status": record.status, "tool": toolName]
            )
        }
        let exposureText = result.output ?? result.reason
        await recordExposure(
            toolName: toolName,
            resourcePath: resourcePath,
            text: exposureText,
            exposureType: "exec_result",
            decisionID: decisionID
        )
        return result
    }

    func executeExecSteps(_ steps: [[String: Any]]) async throws -> String {
        var output: [String] = []
        for (index, step) in steps.prefix(20).enumerated() {
            guard let op = (step["op"] as? String)?.lowercased() else {
                output.append("Step \(index + 1): refused missing op")
                continue
            }
            let limit = Self.intValue(step["limit"]) ?? 10
            let text: String
            switch op {
            case "recall_memory":
                text = try await recallMemory(query: Self.stringValue(step["query"]), limit: limit)
            case "reuse_prior_context":
                text = try await reusePriorContext(
                    query: Self.stringValue(step["query"]),
                    path: Self.stringValue(step["path"]),
                    limit: limit
                )
            case "was_exposed_before":
                text = try await wasExposedBefore(
                    contentHash: Self.stringValue(step["content_hash"]),
                    path: Self.stringValue(step["path"]),
                    limit: limit
                )
            case "what_changed_since":
                text = try await whatChangedSince(path: Self.stringValue(step["path"]), limit: limit)
            case "search_structured":
                guard let query = Self.stringValue(step["query"]) else {
                    text = "Step \(index + 1): refused search_structured without query"
                    break
                }
                text = try await searchStructured(query: query, limit: limit, intent: nil)
            case "query_graph":
                text = try await queryGraph(query: Self.stringValue(step["query"]) ?? "", limit: limit)
            case "list_skills":
                text = try await listSkills(limit: limit)
            case "tool_cost_report":
                text = try await toolCostReport(limit: limit)
            case "verify_ledger_entry":
                text = try await verifyLedgerEntry(entryID: Self.stringValue(step["entry_id"]))
            default:
                text = "Step \(index + 1): refused unsupported op \(op)"
            }
            output.append("Step \(index + 1) \(op)\n\(Self.clipped(text, maxCharacters: 4_000))")
        }
        if steps.count > 20 {
            output.append("Plan truncated after 20 steps.")
        }
        return output.joined(separator: "\n\n")
    }

    static func isSupportedExecLanguage(_ language: String?) -> Bool {
        guard let language, !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        return ["json", "plan", "manifoldexec", "manifoldexec-json", "status"].contains(language.lowercased())
    }

    static func execSteps(from json: String) throws -> [[String: Any]] {
        guard let data = json.data(using: .utf8) else {
            throw ManifoldError.materialization("Plan is not valid UTF-8.")
        }
        let object = try JSONSerialization.jsonObject(with: data)
        if let steps = object as? [[String: Any]] {
            return steps
        }
        guard let dictionary = object as? [String: Any] else {
            throw ManifoldError.materialization("Plan must be a JSON object or array.")
        }
        if dictionary["op"] is String {
            return [dictionary]
        }
        if let steps = dictionary["steps"] as? [[String: Any]] {
            return steps
        }
        if let exec = dictionary["exec"] as? [String: Any],
           let steps = exec["steps"] as? [[String: Any]] {
            return steps
        }
        throw ManifoldError.materialization("Plan must include a steps array.")
    }

    static func staticExecRefusal(for steps: [[String: Any]]) -> ExecRunResult? {
        let deniedOps: Set<String> = [
            "shell", "bash", "sh", "zsh", "python", "javascript", "node",
            "curl", "fetch", "network", "http", "read_file", "read_email",
            "write_file", "write_binary_file", "annotate_pdf", "send_email", "save_memory_note", "forget_memory", "save_skill", "run_code",
        ]
        let ops = steps.compactMap { ($0["op"] as? String)?.lowercased() }
        if let denied = ops.first(where: deniedOps.contains) {
            return ExecRunResult(
                status: .refused,
                reason: "ManifoldExec refused op \(denied). Exec is read-oriented and has no raw filesystem, shell, network, or state-changing primitives.",
                suggestedAlternative: "Use governed MCP tools directly for state-changing actions so approval, provenance, and drift checks remain explicit."
            )
        }
        if steps.count > 50 {
            return ExecRunResult(
                status: .needsApproval,
                reason: "ManifoldExec plans over 50 steps require explicit approval.",
                suggestedAlternative: "Split the plan into smaller scoped runs."
            )
        }
        return nil
    }

    static func ruleOfTwoTriggered(in json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        let flags = Self.flattenedBooleans(object)
        let untrusted = flags["untrusted_input"] == true || flags["untrusted"] == true
        let sensitive = flags["sensitive_data"] == true || flags["sensitive"] == true
        let stateChanging = flags["state_changing"] == true || flags["state_changing_action"] == true
        return untrusted && sensitive && stateChanging
    }

    static func flattenedBooleans(_ value: Any) -> [String: Bool] {
        var result: [String: Bool] = [:]
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if let bool = child as? Bool {
                    result[key] = bool
                }
                result.merge(flattenedBooleans(child)) { current, _ in current }
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.merge(flattenedBooleans(child)) { current, _ in current }
            }
        }
        return result
    }

    func isResourcePath(_ path: String, inScopeOf context: AccessContext) -> Bool {
        let lower = cleanPath(path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        return scopeLabels(in: context).contains { label in
            let scoped = cleanPath(label)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
            return !scoped.isEmpty && (lower == scoped || lower.hasPrefix(scoped + "/"))
        }
    }

    func isExposure(_ exposure: ExposureRecord, inScopeOf context: AccessContext) -> Bool {
        if exposure.exposureType.hasPrefix("email") {
            return true
        }
        guard let resourcePath = exposure.resourcePath else {
            return false
        }
        return isResourcePath(resourcePath, inScopeOf: context)
    }

    func expireDerivedMemoryIfNeeded() async throws {
        if let memoryStore {
            _ = try await memoryStore.expireDerivedMemory()
        }
    }

    func canAccessMemory(_ item: MemoryItem, in context: AccessContext) -> Bool {
        if let currentGrantID = grantID(in: context),
           item.contributingGrantIDs.contains(currentGrantID) {
            return true
        }

        let lineageSources = Set(item.contributingSourceIDs)
        return !lineageSources.isEmpty && lineageSources.isSubset(of: sourceIDs(in: context))
    }

    func canAccessValueHandle(_ handle: ValueHandle, in context: AccessContext) -> Bool {
        if let handleGrantID = handle.grantID {
            return handleGrantID == grantID(in: context)
        }

        let lineageSources = Set(handle.lineage.filter { $0.kind == "source" }.map(\.id))
        return !lineageSources.isEmpty && lineageSources.isSubset(of: sourceIDs(in: context))
    }

    func scopeLabels(in context: AccessContext) -> [String] {
        switch context {
        case .standing(_, let sources):
            return sources.flatMap {
                [
                    $0.sourceID,
                    $0.displayName,
                    $0.canonicalMountName,
                ]
            }
        case .workBlock(_, let grantSources, _), .legacyGrant(_, let grantSources):
            return grantSources.flatMap { [$0.sourceID, $0.mountName] }
        }
    }

    static func clipped(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        return String(text.prefix(maxCharacters)) + "\n[truncated]"
    }

    static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let string = value as? String { return Int(string) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    func sourceIDs(in context: AccessContext) -> Set<String> {
        switch context {
        case .standing(_, let sources):
            return Set(sources.map(\.sourceID))
        case .workBlock(_, let grantSources, _), .legacyGrant(_, let grantSources):
            return Set(grantSources.map(\.sourceID))
        }
    }

    func grantID(in context: AccessContext) -> String? {
        switch context {
        case .standing:
            return nil
        case .workBlock(let grant, _, _), .legacyGrant(let grant, _):
            return grant.grantID
        }
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
