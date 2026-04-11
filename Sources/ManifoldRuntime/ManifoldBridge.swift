import Foundation
import CryptoKit
import ManifoldKit
import os

/// Core logic layer between MCP protocol and ManifoldKit stores.
/// Dual-path access: standing access via PolicyStore, work block via grant materialization.
/// Fail-closed: no policy and no grant = no access.
public actor ManifoldBridge {
    private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "runtime")
    private let db: DatabaseConnection
    private let auditStore: AuditStore
    private let contentStore: ContentStore
    private let grantStore: GrantStore
    private let emailStore: EmailStore
    private let snapshotStore: SnapshotStore
    private let artifactIndex: ArtifactIndex
    private let policyStore: PolicyStore?
    private let workBlockStore: WorkBlockStore?
    private let approvalQueue: ApprovalQueue?
    private let exposureStore: ExposureStore?
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
        workBlockStore: WorkBlockStore? = nil,
        approvalQueue: ApprovalQueue? = nil,
        exposureStore: ExposureStore? = nil,
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
        self.workBlockStore = workBlockStore
        self.approvalQueue = approvalQueue
        self.exposureStore = exposureStore
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
            "is_paused": policy.isPaused,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) else {
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
            case .noSources, .fileNotFound, .invalidPath:
                return DecisionContext(reason: "policy_denied", accessMode: "unknown", policySnapshot: nil)
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
        policySnapshot: String? = nil
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
            policySnapshot: policySnapshot
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
        decisionID: String?
    ) async {
        guard decisionID != nil else { return }
        await recordExposure(
            toolName: toolName,
            resourcePath: resourcePath,
            data: Data(text.utf8),
            exposureType: exposureType,
            decisionID: decisionID
        )
    }

    private func recordExposure(
        toolName: String,
        resourcePath: String?,
        data: Data,
        exposureType: String,
        decisionID: String?
    ) async {
        guard let exposureStore, let decisionID else { return }
        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        let exposure = ExposureRecord(
            connectionID: runtimeContext.connectionID,
            agent: agentName,
            toolName: toolName,
            resourcePath: resourcePath,
            byteCount: data.count,
            contentHash: hash,
            exposureType: exposureType,
            accessDecisionID: decisionID
        )
        do {
            try await exposureStore.recordExposure(exposure)
        } catch {
            logger.error("Failed to record exposure: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func resolveAccessForTool(
        toolName: String,
        action: String,
        resourcePath: String? = nil
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
                policySnapshot: decision.policySnapshot
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
                accessMode: decision.accessMode
            )
            throw error
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

            // Standing access — check if any sources are allowed
            if policy.allowedSourceIDs.isEmpty && policy.allowedEmailDomains.isEmpty {
                throw ManifoldMCPError.noAccessConfigured
            }

            // Resolve allowed source records
            let allSources = try await grantStore.allSources()
            let allowedSources = allSources.filter { policy.allowedSourceIDs.contains($0.sourceID) }
            return .standing(policy: policy, sources: allowedSources)
        }

        // Path 2: Legacy grant-only (PolicyStore not injected)
        return try await legacyRequireGrant()
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
        resourcePath: String? = nil
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
                policySnapshot: "{\"grant_id\":\"\(grant.grantID)\"}"
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
                accessMode: decision.accessMode
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
    }

    /// Resolve access and return mounts suitable for file operations.
    /// Handles standing access (original paths) and grant access (materialized paths).
    private func resolveAccessMounts(
        toolName: String,
        action: String,
        resourcePath: String? = nil
    ) async throws -> ResolvedMounts {
        let (context, decisionID) = try await resolveAccessForTool(
            toolName: toolName,
            action: action,
            resourcePath: resourcePath
        )
        switch context {
        case .standing(_, let sources):
            return ResolvedMounts(
                mounts: standingMounts(sources: sources),
                grantID: nil,
                grant: nil,
                isStanding: true,
                decisionID: decisionID
            )
        case .workBlock(let grant, let grantSources, _):
            return ResolvedMounts(
                mounts: grantMounts(grant: grant, sources: grantSources),
                grantID: grant.grantID,
                grant: grant,
                isStanding: false,
                decisionID: decisionID
            )
        case .legacyGrant(let grant, let grantSources):
            return ResolvedMounts(
                mounts: grantMounts(grant: grant, sources: grantSources),
                grantID: grant.grantID,
                grant: grant,
                isStanding: false,
                decisionID: decisionID
            )
        }
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

    private func ensureIndexed(grant: GrantRecord, mounts: [GrantMount]) async throws {
        try await artifactIndex.ensureGrantIndexed(
            grantID: grant.grantID,
            materializationRoot: grant.materializationRoot,
            mounts: artifactMounts(from: mounts)
        )

        let emails = try accessibleEmails(grant: grant, limit: 1_000)
        let attachments = try emailStore.emailAttachments(emailIDs: emails.map(\.emailID))
        try await artifactIndex.syncEmails(
            grantID: grant.grantID,
            emails: emails,
            attachments: attachments
        )

        let summaries = try await grantStore.summaries(grantID: grant.grantID)
        try await artifactIndex.syncSessionSummaries(grantID: grant.grantID, summaries: summaries)
    }

    private func accessibleEmails(grant: GrantRecord, limit: Int) throws -> [EmailMessageRecord] {
        if grant.explicitSelection {
            return try emailStore.grantEmails(grantID: grant.grantID, limit: limit)
        }
        let filter = EmailSensitivityFilter(rawValue: grant.emailSensitivity)
        if filter.level == .strict {
            return try emailStore.sharedEmails(limit: limit)
        }
        return try emailStore.allEmailMessages(limit: limit).filter { filter.isVisible(email: $0) }
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
        let cleaned = cleanPath(path)
        guard !cleaned.hasPrefix("/") else { throw ManifoldMCPError.invalidPath("Absolute paths not allowed") }
        guard !cleaned.contains("..") else { throw ManifoldMCPError.invalidPath("Path traversal not allowed") }
        let root = URL(fileURLWithPath: rootPath)
        let resolved = root.appendingPathComponent(cleaned).standardizedFileURL
        guard resolved.path.hasPrefix(root.standardizedFileURL.path) else {
            throw ManifoldMCPError.invalidPath("Path escapes workspace boundary")
        }
        return resolved
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

    public func getStatus() async -> StatusResult {
        await logToolCall(tool: "get_status")
        do {
            let (context, decisionID) = try await resolveAccessForTool(toolName: "get_status", action: "read")
            switch context {
            case .standing(let policy, let sources):
                let sourceNames = sources.map(\.displayName).joined(separator: ", ")
                // Use cached file list for count (avoids full enumeration on every getStatus)
                let mounts = standingMounts(sources: sources)
                let totalFiles = (try? listFilesFromOriginals(mounts: mounts).count) ?? 0
                let emailCount = policy.allowedEmailDomains.count > 0 ? (try? emailStore.emailMessageCount()) ?? 0 : 0
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
                let emailCount = (try? accessibleEmails(grant: grant, limit: 5_000).count) ?? 0
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
                let emailCount = (try? accessibleEmails(grant: grant, limit: 5_000).count) ?? 0
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

    public func listFiles() async throws -> [FileInfo] {
        await logToolCall(tool: "list_files")
        let resolved = try await resolveAccessMounts(toolName: "list_files", action: "list")
        let files: [FileInfo]

        // Standing access: enumerate files from original source paths
        if resolved.isStanding {
            files = try listFilesFromOriginals(mounts: resolved.mounts)
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
        await recordExposure(toolName: "list_files", resourcePath: nil, text: serialized, exposureType: "snippet", decisionID: resolved.decisionID)
        return files
    }

    // MARK: - File Enumeration Cache

    private var fileListCache: (entries: [FileInfo], timestamp: Date, mountPaths: Set<String>)?
    private let fileListCacheTTL: TimeInterval = 10

    /// List files from original source paths with 10-second TTL cache.
    /// Avoids re-enumerating 5,000+ files on every list_files MCP call.
    private func listFilesFromOriginals(mounts: [GrantMount]) throws -> [FileInfo] {
        let currentPaths = Set(mounts.map(\.mountPath))
        if let cache = fileListCache,
           Date().timeIntervalSince(cache.timestamp) < fileListCacheTTL,
           cache.mountPaths == currentPaths {
            return cache.entries
        }
        let files = try enumerateOriginalFiles(mounts: mounts)
        fileListCache = (files, Date(), currentPaths)
        return files
    }

    /// Actual file enumeration — only called when cache is stale or mount set changed.
    private func enumerateOriginalFiles(mounts: [GrantMount]) throws -> [FileInfo] {
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

    public func readFile(path: String) async throws -> String {
        await logToolCall(tool: "read_file", arguments: ["path": path])
        let resolved = try await resolveAccessMounts(toolName: "read_file", action: "read", resourcePath: path)
        let mounts = resolved.mounts
        let cleaned = cleanPath(path)

        // For grant-based access, ensure indexed
        if let grant = resolved.grant {
            try await ensureIndexed(grant: grant, mounts: mounts)
        }

        let grantID = resolved.grantID ?? "standing"

        // Try mount-prefixed resolution first (e.g. "MyProject/src/main.swift")
        if let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) {
            return try await readFromMount(
                relativePath: relPath,
                mountPath: mount.mountPath,
                mountName: mount.mountName,
                grantID: grantID,
                decisionID: resolved.decisionID
            )
        }

        // Bare path: resolve unambiguously or reject
        let (mount, relPath) = try resolveBarePath(cleaned, in: mounts)
        return try await readFromMount(
            relativePath: relPath,
            mountPath: mount.mountPath,
            mountName: mount.mountName,
            grantID: grantID,
            decisionID: resolved.decisionID
        )
    }

    private func readFromMount(
        relativePath: String,
        mountPath: String,
        mountName: String,
        grantID: String,
        decisionID: String?
    ) async throws -> String {
        let fileURL = try validatePath(relativePath, rootPath: mountPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ManifoldMCPError.fileNotFound(relativePath)
        }
        let canonicalPath = "\(mountName)/\(relativePath)"
        let artifact = try await artifactIndex.artifact(grantID: grantID, canonicalPath: canonicalPath)
        let read = try ContextEngine.read(
            fileURL: fileURL,
            selection: artifact?.selection
        )

        try? await auditStore.log(
            action: .fileRead,
            agent: agentName,
            filePath: canonicalPath,
            metadata: mergedMetadata([
                "grant_id": grantID,
                "mount": mountName,
                "bytes": "\(read.bytesRead)",
                "truncated": read.truncated ? "true" : "false",
            ]),
            grantID: grantID
        )
        await recordExposure(toolName: "read_file", resourcePath: canonicalPath, text: read.text, exposureType: "full_file", decisionID: decisionID)
        return read.text
    }

    // MARK: - Write File (P1 FIX: record snapshots, use canonical paths, reject ambiguous)

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

        if case .standing(let policy, _) = accessContext {
            _ = try? await approvalQueue?.submit(
                connectionID: runtimeContext.connectionID,
                agent: agentName,
                path: cleaned,
                action: "write"
            )
            _ = await recordAccessDecision(
                toolName: "write_file",
                resourcePath: cleaned,
                action: "write",
                allowed: false,
                reason: "standing_access",
                accessMode: "standing",
                policySnapshot: policySnapshot(for: policy)
            )
            return .escalationRequired(
                message: "Always-on access is read-only. Start a tracked run to edit files.",
                path: cleaned
            )
        }

        let accessDecisionID = await recordAccessDecision(
            toolName: "write_file",
            resourcePath: cleaned,
            action: "write",
            allowed: true,
            reason: "work_block",
            accessMode: "tracked_run"
        )

        let access: ResolvedMounts
        switch accessContext {
        case .workBlock(let grant, let grantSources, _):
            access = ResolvedMounts(
                mounts: grantMounts(grant: grant, sources: grantSources),
                grantID: grant.grantID,
                grant: grant,
                isStanding: false,
                decisionID: accessDecisionID
            )
        case .legacyGrant(let grant, let grantSources):
            access = ResolvedMounts(
                mounts: grantMounts(grant: grant, sources: grantSources),
                grantID: grant.grantID,
                grant: grant,
                isStanding: false,
                decisionID: accessDecisionID
            )
        case .standing:
            throw ManifoldMCPError.noActiveSession
        }

        let mounts = access.mounts
        let data = content.data(using: .utf8) ?? Data()
        let writeID = access.grantID ?? "standing"

        // Resolve mount deterministically
        let targetMount: GrantMount
        let resolvedPath: String
        if let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) {
            targetMount = mount
            resolvedPath = relPath
        } else if mounts.count == 1, let first = mounts.first {
            targetMount = first
            resolvedPath = cleaned
        } else if mounts.count > 1 {
            let (mount, relPath) = try resolveBarePath(cleaned, in: mounts)
            targetMount = mount
            resolvedPath = relPath
        } else {
            throw ManifoldMCPError.noSources
        }

        let fileURL = try validatePath(resolvedPath, rootPath: targetMount.mountPath)
        if let grant = access.grant {
            try await assertWritableScope(relativePath: resolvedPath, mount: targetMount, grant: grant)
        }
        let canonicalPath = "\(targetMount.mountName)/\(resolvedPath)"

        let existed = FileManager.default.fileExists(atPath: fileURL.path)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)

        if let grant = access.grant {
            try await artifactIndex.upsertFile(
                grantID: grant.grantID,
                mount: ArtifactMount(sourceID: targetMount.sourceID, mountName: targetMount.mountName, mountPath: targetMount.mountPath),
                relativePath: resolvedPath,
                fileURL: fileURL
            )
        }

        let snapshot = try await snapshotStore.recordModification(
            runID: writeID,
            workspaceID: targetMount.sourceID,
            filePath: canonicalPath,
            newData: data,
            source: "mcp"
        )

        try? await auditStore.log(
            action: existed ? .fileModified : .fileCreated,
            runID: writeID,
            workspaceID: targetMount.sourceID,
            agent: agentName,
            filePath: canonicalPath,
            beforeHash: snapshot.beforeHash,
            afterHash: snapshot.afterHash,
            metadata: mergedMetadata([
                "grant_id": writeID,
                "mount": targetMount.mountName,
                "bytes": "\(data.count)",
                "snapshot_id": "\(snapshot.id)",
            ]),
            grantID: writeID
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

    public func searchFiles(query: String) async throws -> [(path: String, source: String, matches: [String])] {
        await logToolCall(tool: "search_files", arguments: ["query": query])
        let resolved = try await resolveAccessMounts(toolName: "search_files", action: "search")
        let results: [(path: String, source: String, matches: [String])]

        // Standing access: grep through original source files
        if resolved.isStanding {
            results = try searchFilesInOriginals(query: query, mounts: resolved.mounts)
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
        for result in results {
            for snippet in result.matches {
                await recordExposure(
                    toolName: "search_files",
                    resourcePath: result.path,
                    text: snippet,
                    exposureType: "snippet",
                    decisionID: resolved.decisionID
                )
            }
        }
        return results
    }

    /// Search files directly in original source paths (standing access).
    private func searchFilesInOriginals(query: String, mounts: [GrantMount]) throws -> [(path: String, source: String, matches: [String])] {
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

    public func fileInfo(path: String) async throws -> FileInfoDetail {
        await logToolCall(tool: "file_info", arguments: ["path": path])
        let access = try await resolveAccessMounts(toolName: "file_info", action: "read", resourcePath: path)
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
        await recordExposure(toolName: "file_info", resourcePath: canonicalPath, text: detailString, exposureType: "snippet", decisionID: access.decisionID)
        return detail
    }

    // MARK: - Archive Listing

    public func listArchive(path: String) async throws -> [String] {
        await logToolCall(tool: "list_archive", arguments: ["path": path])
        let access = try await resolveAccessMounts(toolName: "list_archive", action: "read", resourcePath: path)
        let mounts = access.mounts
        if let grant = access.grant {
            try await ensureIndexed(grant: grant, mounts: mounts)
        }
        let cleaned = cleanPath(path)

        guard let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) else {
            throw ManifoldMCPError.fileNotFound(path)
        }

        let archiveURL = try validatePath(relPath, rootPath: mount.mountPath)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ManifoldMCPError.fileNotFound(path)
        }

        let canonicalPath = "\(mount.mountName)/\(relPath)"
        let grantID = access.grantID ?? "standing"
        let indexedEntries = try await artifactIndex.archiveEntries(grantID: grantID, canonicalPath: canonicalPath)
        if !indexedEntries.isEmpty {
            await recordExposure(toolName: "list_archive", resourcePath: canonicalPath, text: indexedEntries.joined(separator: "\n"), exposureType: "snippet", decisionID: access.decisionID)
            return indexedEntries
        }

        guard let contents = listZipContents(atPath: archiveURL.path) else {
            throw ManifoldMCPError.invalidPath("Not a valid zip archive or archive is empty")
        }
        await recordExposure(toolName: "list_archive", resourcePath: canonicalPath, text: contents.joined(separator: "\n"), exposureType: "snippet", decisionID: access.decisionID)
        return contents
    }

    // MARK: - Extract File

    public func extractFile(archivePath: String, filePath: String) async throws -> String {
        await logToolCall(tool: "extract_file", arguments: ["archive": archivePath, "file": filePath])
        let access = try await resolveAccessMounts(toolName: "extract_file", action: "read", resourcePath: archivePath)
        let mounts = access.mounts
        let cleaned = cleanPath(archivePath)

        // Resolve mount for the archive
        guard let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) else {
            throw ManifoldMCPError.fileNotFound(archivePath)
        }

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
        await recordExposure(toolName: "extract_file", resourcePath: "\(archivePath)#\(targetEntry)", text: content, exposureType: "full_file", decisionID: access.decisionID)
        return content
    }

    public func readRange(path: String, startLine: Int, endLine: Int) async throws -> String {
        await logToolCall(
            tool: "read_range",
            arguments: ["path": path, "start_line": "\(startLine)", "end_line": "\(endLine)"]
        )
        guard startLine > 0, endLine >= startLine else {
            throw ManifoldMCPError.invalidPath("Line range must be positive and end_line must be >= start_line")
        }

        let access = try await resolveAccessMounts(toolName: "read_range", action: "read", resourcePath: path)
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

        let fileURL = try validatePath(resolved.relativePath, rootPath: resolved.mount.mountPath)
        let read = try ContextEngine.read(
            fileURL: fileURL,
            selection: ArtifactSelection(lineStart: startLine, lineEnd: endLine)
        )
        let canonicalPath = "\(resolved.mount.mountName)/\(resolved.relativePath)"

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

        await recordExposure(toolName: "read_range", resourcePath: canonicalPath, text: read.text, exposureType: "range", decisionID: access.decisionID)
        return read.text
    }

    public func diffFile(path: String) async throws -> String {
        await logToolCall(tool: "diff_file", arguments: ["path": path])
        let access = try await resolveAccessMounts(toolName: "diff_file", action: "read", resourcePath: path)
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

        await recordExposure(toolName: "diff_file", resourcePath: canonicalPath, text: rendered, exposureType: "diff", decisionID: access.decisionID)
        return rendered
    }

    public func searchStructured(query: String, limit: Int = 10) async throws -> String {
        await logToolCall(tool: "search_structured", arguments: ["query": query, "limit": "\(limit)"])
        let access = try await resolveAccessMounts(toolName: "search_structured", action: "search")
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
        let payload: [[String: Any]] = hits.map { hit in
            [
                "kind": hit.handle.kind.rawValue,
                "path": hit.handle.path,
                "source": hit.handle.mountName,
                "score": hit.score,
                "preview": hit.preview,
                "selection": selectionJSON(hit.selection),
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let json = String(data: data, encoding: .utf8) ?? "[]"
        for hit in hits {
            for snippet in hit.preview {
                await recordExposure(
                    toolName: "search_structured",
                    resourcePath: hit.handle.path,
                    text: snippet,
                    exposureType: "snippet",
                    decisionID: access.decisionID
                )
            }
        }
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

    /// Check if a single email is accessible under the given sensitivity filter.
    private func isEmailAccessible(email: EmailMessageRecord, grant: GrantRecord) throws -> Bool {
        if grant.explicitSelection {
            return try emailStore.isEmailInGrant(grantID: grant.grantID, emailID: email.emailID)
        }
        let filter = EmailSensitivityFilter(rawValue: grant.emailSensitivity)
        if filter.level == .strict {
            return try emailStore.isEmailShared(emailID: email.emailID)
        }
        return filter.isVisible(email: email)
    }

    public func listEmails() async throws -> [EmailSummary] {
        await logToolCall(tool: "list_emails")
        let (grant, _, decisionID) = try await requireGrantForTool(toolName: "list_emails", action: "list")
        let emails = try accessibleEmails(grant: grant, limit: 200)
        let summaries = emails.map {
            EmailSummary(id: $0.emailID, from: $0.sender, subject: $0.subject, date: $0.receivedAt)
        }
        for summary in summaries {
            await recordExposure(
                toolName: "list_emails",
                resourcePath: summary.id,
                text: "\(summary.from)\n\(summary.subject)\n\(summary.date)",
                exposureType: "email_preview",
                decisionID: decisionID
            )
        }
        return summaries
    }

    public func readEmail(id: String) async throws -> String {
        await logToolCall(tool: "read_email", arguments: ["id": id])
        let (grant, _, decisionID) = try await requireGrantForTool(toolName: "read_email", action: "read", resourcePath: id)

        guard let email = try emailStore.emailMessage(id: id) else {
            throw ManifoldMCPError.fileNotFound("Email not found: \(id)")
        }

        guard try isEmailAccessible(email: email, grant: grant) else {
            throw ManifoldMCPError.fileNotFound("Email not accessible with current sensitivity settings")
        }

        // Read from .eml file on disk
        if let emlPath = email.emlPath,
           FileManager.default.fileExists(atPath: emlPath),
           let content = try? String(contentsOfFile: emlPath, encoding: .utf8) {
            try? await auditStore.log(
                action: .fileRead,
                runID: grant.grantID,
                agent: agentName,
                filePath: emlPath,
                metadata: mergedMetadata([
                    "type": "email",
                    "messageID": id,
                    "grant_id": grant.grantID,
                ]),
                grantID: grant.grantID
            )
            await recordExposure(toolName: "read_email", resourcePath: id, text: content, exposureType: "email_body", decisionID: decisionID)
            return content
        }

        // Fallback: return metadata summary
        try? await auditStore.log(
            action: .fileRead,
            runID: grant.grantID,
            agent: agentName,
            metadata: mergedMetadata([
                "type": "email",
                "messageID": id,
                "grant_id": grant.grantID,
            ]),
            grantID: grant.grantID
        )

        let preview = """
        From: \(email.sender)
        To: \(email.recipients)
        Subject: \(email.subject)
        Date: \(email.receivedAt)

        \(email.preview ?? "(no preview available)")
        """
        await recordExposure(toolName: "read_email", resourcePath: id, text: preview, exposureType: "email_preview", decisionID: decisionID)
        return preview
    }
}
