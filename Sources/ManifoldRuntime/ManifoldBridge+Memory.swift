// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

/// User-owned memory MCP tools (`reuse_prior_context`, `recall_memory`,
/// `save_memory_note`, `list_memory_sources`, `forget_memory`).
///
/// All scope checks honor the calling bridge's grant: an agent only sees memory
/// whose contributing sources are entirely within the active session scope.
/// Cross-agent visibility happens because two bridges over the same source
/// share scope, not because scope is bypassed.
extension ManifoldBridge {
    public func reusePriorContext(query: String? = nil, path: String? = nil, limit: Int = 8) async throws -> String {
        let (context, decisionID) = try await resolveAccessForTool(
            toolName: "reuse_prior_context",
            action: "history",
            resourcePath: path ?? query
        )
        try await expireDerivedMemoryIfNeeded()
        let allowedSourceIDs = sourceIDs(in: context)
        let memories = (try? await memoryStore?.recall(query: query, allowedSourceIDs: allowedSourceIDs, limit: limit)) ?? []
        let exposures: [ExposureRecord]
        if let path, !path.isEmpty {
            exposures = (try? await exposureStore?.exposures(resourcePath: path, limit: limit)) ?? []
        } else if let hash = memories.first?.contributingContentHashes.first {
            exposures = (try? await exposureStore?.exposures(contentHash: hash, limit: limit)) ?? []
        } else {
            exposures = []
        }
        let memoryText = memories.map { "- [\($0.memoryID)] \($0.title): \($0.body)" }.joined(separator: "\n")
        let exposureText = exposures.map { "- [\($0.id)] \($0.toolName) \(String($0.contentHash.prefix(12))) \($0.payloadPreview ?? "")" }.joined(separator: "\n")
        let text = """
        Reusable context
        Memory:
        \(memoryText.isEmpty ? "none" : memoryText)

        Prior exposures:
        \(exposureText.isEmpty ? "none" : exposureText)
        """
        await recordExposure(toolName: "reuse_prior_context", resourcePath: path ?? query, text: text, exposureType: "history_context", decisionID: decisionID)
        return text
    }

    public func recallMemory(query: String? = nil, limit: Int = 10) async throws -> String {
        let (context, decisionID) = try await resolveAccessForTool(toolName: "recall_memory", action: "memory", resourcePath: query)
        guard let memoryStore else {
            return "Memory store unavailable."
        }
        try await expireDerivedMemoryIfNeeded()
        let items = try await memoryStore.recall(query: query, allowedSourceIDs: sourceIDs(in: context), limit: limit)
        let text = items.isEmpty
            ? "No memory matched the current session scope."
            : items.map { "- [\($0.memoryID)] \($0.kind) \(String($0.title.prefix(120))): \($0.body)" }.joined(separator: "\n")
        await recordExposure(toolName: "recall_memory", resourcePath: query, text: text, exposureType: "memory", decisionID: decisionID)
        return text
    }

    public func saveMemoryNote(title: String, body: String, kind: MemoryKind = .note) async throws -> String {
        let (context, decisionID) = try await resolveAccessForTool(toolName: "save_memory_note", action: "memory_write", resourcePath: title)
        guard let memoryStore else {
            return "Memory store unavailable."
        }
        let settings = try await memoryStore.settings()
        if settings.amnesiacMode {
            try await ledgerStore?.append(
                entryType: .memoryChange,
                subjectTable: "memory_settings",
                subjectID: settings.settingsID,
                payload: "amnesiac_mode:not_saved:\(title)",
                metadata: ["status": "not_saved", "reason": "amnesiac_mode"]
            )
            let text = "Memory not saved because amnesiac mode is enabled."
            await recordExposure(toolName: "save_memory_note", resourcePath: title, text: text, exposureType: "memory_policy", decisionID: decisionID)
            return text
        }
        let sourceIDs = Array(sourceIDs(in: context)).sorted()
        let grantID = grantID(in: context)
        let expiresAt = Date().timeIntervalSince1970 + Double(settings.derivedRetentionDays) * 86_400
        let item = try await memoryStore.save(
            kind: kind,
            title: title,
            body: body,
            origin: .agentDerived,
            contributingSourceIDs: sourceIDs,
            contributingGrantIDs: grantID.map { [$0] } ?? [],
            createdSessionID: nil,
            expiresAt: expiresAt
        )
        try await ledgerStore?.append(
            entryType: .memoryItem,
            subjectTable: "memory_items",
            subjectID: item.memoryID,
            payload: Self.canonicalJSON(item),
            metadata: ["kind": item.kind, "status": item.status]
        )
        let text = "Saved memory \(item.memoryID) with \(sourceIDs.count) source lineage item(s)."
        await recordExposure(toolName: "save_memory_note", resourcePath: item.memoryID, text: text, exposureType: "memory", decisionID: decisionID)
        return text
    }

    public func listMemorySources() async throws -> String {
        let (context, decisionID) = try await resolveAccessForTool(toolName: "list_memory_sources", action: "memory")
        guard let memoryStore else {
            return "Memory store unavailable."
        }
        try await expireDerivedMemoryIfNeeded()
        let allowed = sourceIDs(in: context)
        let summaries = try await memoryStore.sourceSummaries()
            .filter { allowed.contains($0.sourceID) }
        let text = summaries.isEmpty
            ? "No memory is available for the current session scope."
            : summaries.map { "- \($0.sourceID): active \($0.activeCount), tombstoned \($0.tombstonedCount), deleted \($0.deletedCount)" }.joined(separator: "\n")
        await recordExposure(toolName: "list_memory_sources", resourcePath: nil, text: text, exposureType: "memory", decisionID: decisionID)
        return text
    }

    public func forgetMemory(memoryID: String) async throws -> String {
        let (context, decisionID) = try await resolveAccessForTool(toolName: "forget_memory", action: "memory_delete", resourcePath: memoryID)
        guard let memoryStore else {
            return "Memory store unavailable."
        }
        guard let item = try await memoryStore.memory(id: memoryID),
              canAccessMemory(item, in: context) else {
            let text = "Memory is unavailable in the current session scope."
            await recordExposure(toolName: "forget_memory", resourcePath: memoryID, text: text, exposureType: "memory", decisionID: decisionID)
            return text
        }
        try await memoryStore.forget(memoryID: memoryID)
        try await ledgerStore?.append(
            entryType: .memoryChange,
            subjectTable: "memory_items",
            subjectID: memoryID,
            payload: "forget:\(memoryID)",
            metadata: ["status": MemoryStatus.deletedByUser.rawValue]
        )
        let text = "Memory \(memoryID) marked deleted by user."
        await recordExposure(toolName: "forget_memory", resourcePath: memoryID, text: text, exposureType: "memory", decisionID: decisionID)
        return text
    }
}
