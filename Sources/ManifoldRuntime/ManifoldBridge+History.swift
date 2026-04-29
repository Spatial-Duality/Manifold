// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

/// History, ledger, exposure-lookup, knowledge-graph, claim-verification,
/// and tool-cost MCP tools.
///
/// These read-shaped tools surface durable, scope-filtered evidence:
/// - `get_file_history_context`, `get_session_context` reconstruct context
///   for the calling agent's view.
/// - `was_exposed_before` and `what_changed_since` look up scoped exposure
///   records and audit entries.
/// - `verify_ledger_entry` exposes the tamper-evident hash chain.
/// - `query_graph` joins memory, skills, exposures, and graph nodes.
/// - `verify_claimed_actions` grades structured claims against scoped
///   exposure ground truth via `ClaimEvidence`.
/// - `tool_cost_report` and `latestToolMetricContext` cover metrics surfaces.
extension ManifoldBridge {
    public func fileHistoryContext(filePath: String, limit: Int = 20) async throws -> FileHistoryContext {
        await logToolCall(tool: "get_file_history_context", arguments: ["file_path": filePath, "limit": limit])
        let (accessContext, decisionID) = try await resolveAccessForTool(
            toolName: "get_file_history_context",
            action: "read",
            resourcePath: filePath
        )
        guard isResourcePath(filePath, inScopeOf: accessContext) else {
            throw ManifoldMCPError.fileNotFound(filePath)
        }
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

    public func latestToolMetricContext(toolName: String) async -> ToolMetricContext {
        let exposure: ExposureRecord?
        if let exposureStore {
            exposure = try? await exposureStore.latestExposure(connectionID: runtimeContext.connectionID, toolName: toolName)
        } else {
            exposure = nil
        }
        let grantID = try? await grantStore.activeGrant(targetApp: targetApp, profileID: profileID)?.grantID
        let sessionID: String?
        if let grantID {
            sessionID = (try? await auditStore.entriesByGrant(grantID: grantID, limit: 1).first?.sessionID) ?? nil
        } else {
            sessionID = nil
        }
        return ToolMetricContext(exposureID: exposure?.id, grantID: grantID, sessionID: sessionID)
    }

    public func toolCostReport(limit: Int = 100) async throws -> String {
        let (_, decisionID) = try await resolveAccessForTool(toolName: "tool_cost_report", action: "read")
        let report = try await ToolMetricsStore(db: db).report(limit: limit)
        let calls = report.callsByTool
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
        let text = """
        Tool cost report
        Calls: \(report.totalCalls)
        Output bytes: \(report.totalOutputBytes)
        Average duration: \(String(format: "%.1f", report.averageDurationMS)) ms
        Calls by tool: \(calls.isEmpty ? "none" : calls)
        """
        await recordExposure(toolName: "tool_cost_report", resourcePath: nil, text: text, exposureType: "metrics", decisionID: decisionID)
        return text
    }

    public func verifyLedgerEntry(entryID: String? = nil) async throws -> String {
        let (_, decisionID) = try await resolveAccessForTool(toolName: "verify_ledger_entry", action: "read", resourcePath: entryID)
        guard let ledgerStore else {
            return "Ledger store unavailable."
        }
        if let entryID, !entryID.isEmpty {
            guard let entry = try await ledgerStore.entry(id: entryID) else {
                return "No ledger entry found for \(entryID)."
            }
            let text = """
            Ledger entry \(entry.entryID)
            Sequence: \(entry.sequence)
            Type: \(entry.entryType)
            Subject: \(entry.subjectTable ?? "none")/\(entry.subjectID ?? "none")
            Previous hash: \(entry.previousHash ?? "genesis")
            Payload hash: \(entry.payloadHash)
            Entry hash: \(entry.entryHash)
            """
            await recordExposure(toolName: "verify_ledger_entry", resourcePath: entryID, text: text, exposureType: "ledger", decisionID: decisionID)
            return text
        }
        let verification = try await ledgerStore.verifyChain()
        let recent = try await ledgerStore.recent(limit: 10)
            .map { "#\($0.sequence) \($0.entryType) \($0.subjectTable ?? "-")/\($0.subjectID ?? "-") \(String($0.entryHash.prefix(12)))" }
            .joined(separator: "\n")
        let text = """
        \(verification.message)
        Checked entries: \(verification.checkedEntries)
        Recent entries:
        \(recent.isEmpty ? "none" : recent)
        """
        await recordExposure(toolName: "verify_ledger_entry", resourcePath: nil, text: text, exposureType: "ledger", decisionID: decisionID)
        return text
    }

    public func wasExposedBefore(contentHash: String? = nil, path: String? = nil, limit: Int = 10) async throws -> String {
        let (_, decisionID) = try await resolveAccessForTool(
            toolName: "was_exposed_before",
            action: "history",
            resourcePath: path ?? contentHash
        )
        guard let exposureStore else {
            return "Exposure store unavailable."
        }
        let exposures: [ExposureRecord]
        if let contentHash, !contentHash.isEmpty {
            exposures = try await exposureStore.exposures(contentHash: contentHash, limit: limit)
        } else if let path, !path.isEmpty {
            exposures = try await exposureStore.exposures(resourcePath: path, limit: limit)
        } else {
            throw ManifoldMCPError.invalidPath("Provide content_hash or path.")
        }
        let rows = exposures.map {
            "- \($0.id) \($0.toolName) \($0.exposureType) \(String($0.contentHash.prefix(12))) \(ISO8601DateFormatter.shared.string(from: Date(timeIntervalSince1970: $0.timestamp)))"
        }.joined(separator: "\n")
        let text = exposures.isEmpty ? "No prior exposure found." : "Prior exposures:\n\(rows)"
        await recordExposure(toolName: "was_exposed_before", resourcePath: path ?? contentHash, text: text, exposureType: "history_lookup", decisionID: decisionID)
        return text
    }

    public func whatChangedSince(path: String? = nil, limit: Int = 20) async throws -> String {
        let (context, decisionID) = try await resolveAccessForTool(toolName: "what_changed_since", action: "history", resourcePath: path)
        let activeGrantID = grantID(in: context)
        if let path, !path.isEmpty, !isResourcePath(path, inScopeOf: context) {
            throw ManifoldMCPError.fileNotFound(path)
        }
        let entries = try await auditStore.recentEntries(limit: max(limit * 4, 50))
            .filter { entry in
                if let activeGrantID, entry.grantID != activeGrantID {
                    return false
                }
                if activeGrantID == nil {
                    guard let entryPath = entry.filePath else { return false }
                    guard isResourcePath(entryPath, inScopeOf: context) else { return false }
                }
                guard let path, !path.isEmpty else { return true }
                return entry.filePath == path
            }
            .prefix(limit)
        let changeText = entries.isEmpty
            ? "No recent changes recorded for the current session scope."
            : entries.map { "- [\($0.timestamp)] \($0.action) \($0.filePath ?? "") grant=\($0.grantID ?? "none")" }.joined(separator: "\n")

        var sourceText = "No active grant source manifests."
        if let activeGrantID {
            let grantSources = try await grantStore.grantSources(grantID: activeGrantID)
            sourceText = grantSources.isEmpty
                ? "No active grant source manifests."
                : grantSources
                    .map { "- \($0.mountName) source=\($0.sourceID) baseline=\($0.baselineManifestHash ?? "none")" }
                    .joined(separator: "\n")
        }

        var exposureText = "Provide a path to compare prior exposures."
        if let path, !path.isEmpty, let exposureStore {
            let exposures = (try? await exposureStore.exposures(resourcePath: path, limit: min(limit, 10))) ?? []
            exposureText = exposures.isEmpty
                ? "No prior exposures recorded for \(path)."
                : exposures
                    .map { "- \($0.toolName) \(String($0.contentHash.prefix(12))) \(ISO8601DateFormatter.shared.string(from: Date(timeIntervalSince1970: $0.timestamp)))" }
                    .joined(separator: "\n")

            if let activeGrantID,
               let current = try? await artifactIndex.artifact(grantID: activeGrantID, canonicalPath: path),
               let currentHash = current.hash,
               let priorHash = exposures.first?.contentHash {
                let status = currentHash == priorHash ? "unchanged_since_last_exposure" : "changed_since_last_exposure"
                exposureText += "\nCurrent hash: \(String(currentHash.prefix(12))) (\(status))"
            }
        }

        var summaryText = "No session summaries for the current grant."
        if let activeGrantID {
            let summaries = (try? await grantStore.summaries(grantID: activeGrantID)) ?? []
            summaryText = summaries.isEmpty
                ? "No session summaries for the current grant."
                : summaries
                    .prefix(5)
                    .map { "- \($0.summaryKind) \(String($0.summaryID.prefix(12))) hash=\($0.summaryJSONHash ?? "none")" }
                    .joined(separator: "\n")
        }

        let text = """
        Changes
        \(changeText)

        Source manifests
        \(sourceText)

        Prior exposures
        \(exposureText)

        Session summaries
        \(summaryText)
        """
        await recordExposure(toolName: "what_changed_since", resourcePath: path, text: text, exposureType: "history_context", decisionID: decisionID)
        return text
    }

    public func queryGraph(query: String, limit: Int = 10) async throws -> String {
        let (context, decisionID) = try await resolveAccessForTool(toolName: "query_graph", action: "graph", resourcePath: query)
        try await expireDerivedMemoryIfNeeded()
        let memories = (try? await memoryStore?.recall(query: query, allowedSourceIDs: sourceIDs(in: context), limit: limit)) ?? []
        let graphNodes = (try? await knowledgeGraphStore?.query(query, allowedSourceIDs: sourceIDs(in: context), limit: limit)) ?? []
        let skills = ((try? await skillStore?.list(limit: 100)) ?? [])
            .filter { skill in
                query.isEmpty || skill.name.localizedCaseInsensitiveContains(query) || skill.manifestJSON.localizedCaseInsensitiveContains(query)
            }
            .prefix(limit)
        let exposures = ((try? await exposureStore?.recentExposures(limit: 200)) ?? [])
            .filter { exposure in
                guard let resourcePath = exposure.resourcePath else { return false }
                return isResourcePath(resourcePath, inScopeOf: context)
                    && (query.isEmpty || resourcePath.localizedCaseInsensitiveContains(query) || exposure.toolName.localizedCaseInsensitiveContains(query))
            }
            .prefix(limit)

        var sections: [String] = []
        if !graphNodes.isEmpty {
            sections.append("Graph nodes\n" + graphNodes.map { "- \($0.kind):\($0.nodeID) \($0.label)" }.joined(separator: "\n"))
        }
        if !memories.isEmpty {
            sections.append("Memory nodes\n" + memories.map { "- memory:\($0.memoryID) \($0.title)" }.joined(separator: "\n"))
        }
        if !skills.isEmpty {
            sections.append("Skill nodes\n" + skills.map { "- skill:\($0.skillID) \($0.name) manifest=\(String($0.manifestHash.prefix(12)))" }.joined(separator: "\n"))
        }
        if !exposures.isEmpty {
            sections.append("Exposure nodes\n" + exposures.map { "- exposure:\($0.id) \($0.toolName) \($0.resourcePath ?? "-") hash=\(String($0.contentHash.prefix(12)))" }.joined(separator: "\n"))
        }
        let text = sections.isEmpty ? "No scoped graph result matched the query." : sections.joined(separator: "\n\n")
        try await ledgerStore?.append(
            entryType: .graph,
            subjectTable: "knowledge_graph_nodes",
            subjectID: query.isEmpty ? "query" : query,
            payload: text,
            metadata: ["query": String(query.prefix(120))]
        )
        await recordExposure(toolName: "query_graph", resourcePath: query, text: text, exposureType: "graph", decisionID: decisionID)
        return text
    }

    public func verifyClaimedActions(claimsJSON: String, sessionID: String? = nil) async throws -> String {
        let (context, decisionID) = try await resolveAccessForTool(toolName: "verify_claimed_actions", action: "verify", resourcePath: sessionID)
        let claims = ClaimEvidence.parse(json: claimsJSON)
        guard !claims.isEmpty else {
            return "No claims parsed. Provide a JSON array of strings or objects with tool_name/resource_path/content_hash."
        }
        let scopedExposures = ((try? await exposureStore?.exposures(connectionID: runtimeContext.connectionID, limit: 500)) ?? [])
            .filter { isExposure($0, inScopeOf: context) }
        var rows: [String] = []
        for claim in claims {
            let evidence = ClaimEvidence.evidence(for: claim, exposures: scopedExposures)
            let status = evidence["status"] ?? "unverified"
            let finding = try await fabricationFindingStore?.save(
                sessionID: sessionID,
                claimText: claim.text,
                status: status,
                evidence: evidence
            )
            if let finding {
                try await ledgerStore?.append(
                    entryType: .fabricationFinding,
                    subjectTable: "fabrication_findings",
                    subjectID: finding.findingID,
                    payload: Self.canonicalJSON(finding),
                    metadata: ["status": status]
                )
            }
            rows.append("- \(status): \(claim.text) \(evidence["evidence"] ?? "")")
        }
        let text = "Claim verification\n" + rows.joined(separator: "\n")
        await recordExposure(toolName: "verify_claimed_actions", resourcePath: sessionID, text: text, exposureType: "fabrication_check", decisionID: decisionID)
        return text
    }
}
