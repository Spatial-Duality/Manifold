// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - Provenance

public struct LineageRef: Sendable, Hashable, Codable {
    public let kind: String
    public let id: String
    public let contentHash: String?

    public init(kind: String, id: String, contentHash: String? = nil) {
        self.kind = kind
        self.id = id
        self.contentHash = contentHash
    }
}

public struct ProvenanceRecord: Sendable, Identifiable, Codable {
    public var id: String { provenanceID }
    public let provenanceID: String
    public let sourceIDs: [String]
    public let grantID: String?
    public let auditEntryID: String?
    public let exposureID: String?
    public let contentHash: String?
    public let derivationParents: [LineageRef]
    public let createdAt: Double

    public init(
        provenanceID: String = "prov-\(UUID().uuidString.prefix(12).lowercased())",
        sourceIDs: [String] = [],
        grantID: String? = nil,
        auditEntryID: String? = nil,
        exposureID: String? = nil,
        contentHash: String? = nil,
        derivationParents: [LineageRef] = [],
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.provenanceID = provenanceID
        self.sourceIDs = sourceIDs
        self.grantID = grantID
        self.auditEntryID = auditEntryID
        self.exposureID = exposureID
        self.contentHash = contentHash
        self.derivationParents = derivationParents
        self.createdAt = createdAt
    }
}

public enum LedgerEntryType: String, Sendable, Codable, CaseIterable {
    case accessDecision = "access_decision"
    case exposure
    case toolMetric = "tool_metric"
    case memoryItem = "memory_item"
    case memoryChange = "memory_change"
    case valueHandle = "value_handle"
    case execRun = "exec_run"
    case skill
    case graph
    case fabricationFinding = "fabrication_finding"
    case mcpFailure = "mcp_failure"
}

public struct LedgerEntry: Sendable, Identifiable, Codable {
    public var id: String { entryID }
    public let entryID: String
    public let sequence: Int
    public let timestamp: Double
    public let entryType: String
    public let subjectTable: String?
    public let subjectID: String?
    public let previousHash: String?
    public let payloadHash: String
    public let entryHash: String
    public let metadataJSON: String?

    public init(
        entryID: String,
        sequence: Int,
        timestamp: Double,
        entryType: String,
        subjectTable: String?,
        subjectID: String?,
        previousHash: String?,
        payloadHash: String,
        entryHash: String,
        metadataJSON: String?
    ) {
        self.entryID = entryID
        self.sequence = sequence
        self.timestamp = timestamp
        self.entryType = entryType
        self.subjectTable = subjectTable
        self.subjectID = subjectID
        self.previousHash = previousHash
        self.payloadHash = payloadHash
        self.entryHash = entryHash
        self.metadataJSON = metadataJSON
    }
}

public struct LedgerVerificationResult: Sendable, Codable {
    public let verified: Bool
    public let checkedEntries: Int
    public let firstBrokenEntryID: String?
    public let message: String

    public init(verified: Bool, checkedEntries: Int, firstBrokenEntryID: String?, message: String) {
        self.verified = verified
        self.checkedEntries = checkedEntries
        self.firstBrokenEntryID = firstBrokenEntryID
        self.message = message
    }
}

// MARK: - Tool Costs

public struct ToolMetricContext: Sendable, Codable {
    public let exposureID: String?
    public let grantID: String?
    public let sessionID: String?
    public let effectiveAccess: EffectiveAccessMetadata?

    public init(
        exposureID: String? = nil,
        grantID: String? = nil,
        sessionID: String? = nil,
        effectiveAccess: EffectiveAccessMetadata? = nil
    ) {
        self.exposureID = exposureID
        self.grantID = grantID
        self.sessionID = sessionID
        self.effectiveAccess = effectiveAccess
    }
}

public struct ToolCallMetric: Sendable, Identifiable, Codable {
    public var id: String { metricID }
    public let metricID: String
    public let connectionID: String
    public let agent: String
    public let toolName: String
    public let durationMS: Double
    public let outputBytes: Int
    public let truncated: Bool
    public let isError: Bool
    public let requestID: String?
    public let errorClassification: String?
    public let errorBoundary: String?
    public let errorPhase: String?
    public let isRetryable: Bool?
    public let runtimeGeneration: Int
    public let metadataJSON: String?
    public let exposureID: String?
    public let grantID: String?
    public let sessionID: String?
    public let timestamp: Double

    public init(
        metricID: String = "metric-\(UUID().uuidString.prefix(12).lowercased())",
        connectionID: String,
        agent: String,
        toolName: String,
        durationMS: Double,
        outputBytes: Int,
        truncated: Bool,
        isError: Bool,
        requestID: String? = nil,
        errorClassification: String? = nil,
        errorBoundary: String? = nil,
        errorPhase: String? = nil,
        isRetryable: Bool? = nil,
        runtimeGeneration: Int = 0,
        metadataJSON: String? = nil,
        exposureID: String? = nil,
        grantID: String? = nil,
        sessionID: String? = nil,
        timestamp: Double = Date().timeIntervalSince1970
    ) {
        self.metricID = metricID
        self.connectionID = connectionID
        self.agent = agent
        self.toolName = toolName
        self.durationMS = durationMS
        self.outputBytes = outputBytes
        self.truncated = truncated
        self.isError = isError
        self.requestID = requestID
        self.errorClassification = errorClassification
        self.errorBoundary = errorBoundary
        self.errorPhase = errorPhase
        self.isRetryable = isRetryable
        self.runtimeGeneration = runtimeGeneration
        self.metadataJSON = metadataJSON
        self.exposureID = exposureID
        self.grantID = grantID
        self.sessionID = sessionID
        self.timestamp = timestamp
    }
}

public struct ToolCostReport: Sendable, Codable {
    public let totalCalls: Int
    public let totalOutputBytes: Int
    public let averageDurationMS: Double
    public let callsByTool: [String: Int]
    public let recent: [ToolCallMetric]

    public init(
        totalCalls: Int,
        totalOutputBytes: Int,
        averageDurationMS: Double,
        callsByTool: [String: Int],
        recent: [ToolCallMetric]
    ) {
        self.totalCalls = totalCalls
        self.totalOutputBytes = totalOutputBytes
        self.averageDurationMS = averageDurationMS
        self.callsByTool = callsByTool
        self.recent = recent
    }
}

// MARK: - Owned Memory

public enum MemoryKind: String, Sendable, Codable, CaseIterable {
    case summary
    case decision
    case evidence
    case staleRisk = "stale_risk"
    case routine
    case sourceSchema = "source_schema"
    case note
}

public enum MemoryStatus: String, Sendable, Codable, CaseIterable {
    case active
    case hiddenByScope = "hidden_by_scope"
    case tombstonedByRevocation = "tombstoned_by_revocation"
    case expiredByRetention = "expired_by_retention"
    case deletedByUser = "deleted_by_user"
}

public enum MemoryOrigin: String, Sendable, Codable, CaseIterable {
    case agentDerived = "agent_derived"
    case userAuthored = "user_authored"
    case system
}

public struct MemorySettings: Sendable, Identifiable, Codable {
    public var id: String { settingsID }
    public let settingsID: String
    public var amnesiacMode: Bool
    public var derivedRetentionDays: Int
    public var updatedAt: String

    public init(
        settingsID: String = "memory-settings",
        amnesiacMode: Bool = false,
        derivedRetentionDays: Int = 90,
        updatedAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.settingsID = settingsID
        self.amnesiacMode = amnesiacMode
        self.derivedRetentionDays = derivedRetentionDays
        self.updatedAt = updatedAt
    }
}

public struct MemoryItem: Sendable, Identifiable, Codable {
    public var id: String { memoryID }
    public let memoryID: String
    public let kind: String
    public let status: String
    public let origin: String
    public let title: String
    public let body: String
    public let contributingSourceIDs: [String]
    public let contributingGrantIDs: [String]
    public let contributingExposureIDs: [String]
    public let contributingContentHashes: [String]
    public let createdSessionID: String?
    public let expiresAt: Double?
    public let createdAt: Double
    public let updatedAt: Double

    public init(
        memoryID: String = "mem-\(UUID().uuidString.prefix(12).lowercased())",
        kind: MemoryKind,
        status: MemoryStatus = .active,
        origin: MemoryOrigin = .agentDerived,
        title: String,
        body: String,
        contributingSourceIDs: [String] = [],
        contributingGrantIDs: [String] = [],
        contributingExposureIDs: [String] = [],
        contributingContentHashes: [String] = [],
        createdSessionID: String? = nil,
        expiresAt: Double? = nil,
        createdAt: Double = Date().timeIntervalSince1970,
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.memoryID = memoryID
        self.kind = kind.rawValue
        self.status = status.rawValue
        self.origin = origin.rawValue
        self.title = title
        self.body = body
        self.contributingSourceIDs = contributingSourceIDs
        self.contributingGrantIDs = contributingGrantIDs
        self.contributingExposureIDs = contributingExposureIDs
        self.contributingContentHashes = contributingContentHashes
        self.createdSessionID = createdSessionID
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MemorySourceSummary: Sendable, Identifiable, Codable {
    public var id: String { sourceID }
    public let sourceID: String
    public let activeCount: Int
    public let tombstonedCount: Int
    public let deletedCount: Int

    public init(sourceID: String, activeCount: Int, tombstonedCount: Int, deletedCount: Int) {
        self.sourceID = sourceID
        self.activeCount = activeCount
        self.tombstonedCount = tombstonedCount
        self.deletedCount = deletedCount
    }
}

// MARK: - Capability Handles / Future Surfaces

public struct ValueHandle: Sendable, Identifiable, Codable {
    public var id: String { handleID }
    public let handleID: String
    public let origin: String
    public let sensitivity: String
    public let trustLevel: String
    public let allowedSinks: [String]
    public let grantID: String?
    public let lineage: [LineageRef]
    public let createdAt: Double

    public init(
        handleID: String = "handle-\(UUID().uuidString.prefix(12).lowercased())",
        origin: String,
        sensitivity: String,
        trustLevel: String,
        allowedSinks: [String],
        grantID: String?,
        lineage: [LineageRef],
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.handleID = handleID
        self.origin = origin
        self.sensitivity = sensitivity
        self.trustLevel = trustLevel
        self.allowedSinks = allowedSinks
        self.grantID = grantID
        self.lineage = lineage
        self.createdAt = createdAt
    }
}

public struct CapabilityFlowResult: Sendable, Codable {
    public let allowed: Bool
    public let reason: String
    public let handleID: String?
    public let sink: String
    public let ruleOfTwoTriggered: Bool

    public init(
        allowed: Bool,
        reason: String,
        handleID: String? = nil,
        sink: String,
        ruleOfTwoTriggered: Bool = false
    ) {
        self.allowed = allowed
        self.reason = reason
        self.handleID = handleID
        self.sink = sink
        self.ruleOfTwoTriggered = ruleOfTwoTriggered
    }
}

public enum ExecRunStatus: String, Sendable, Codable {
    case refused
    case needsApproval = "needs_approval"
    case completed
    case failed
}

public struct ExecRunResult: Sendable, Codable {
    public let status: String
    public let reason: String
    public let suggestedAlternative: String?
    public let output: String?

    public init(status: ExecRunStatus, reason: String, suggestedAlternative: String? = nil, output: String? = nil) {
        self.status = status.rawValue
        self.reason = reason
        self.suggestedAlternative = suggestedAlternative
        self.output = output
    }
}

public struct ExecRunRecord: Sendable, Identifiable, Codable {
    public var id: String { runID }
    public let runID: String
    public let status: String
    public let reason: String
    public let suggestedAlternative: String?
    public let outputPreview: String?
    public let createdAt: Double

    public init(
        runID: String = "exec-\(UUID().uuidString.prefix(12).lowercased())",
        status: String,
        reason: String,
        suggestedAlternative: String? = nil,
        outputPreview: String? = nil,
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.runID = runID
        self.status = status
        self.reason = reason
        self.suggestedAlternative = suggestedAlternative
        self.outputPreview = outputPreview
        self.createdAt = createdAt
    }
}

public struct SkillRecord: Sendable, Identifiable, Codable {
    public var id: String { skillID }
    public let skillID: String
    public let name: String
    public let manifestHash: String
    public let manifestJSON: String
    public let createdAt: Double
    public let updatedAt: Double

    public init(
        skillID: String = "skill-\(UUID().uuidString.prefix(12).lowercased())",
        name: String,
        manifestHash: String,
        manifestJSON: String,
        createdAt: Double = Date().timeIntervalSince1970,
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.skillID = skillID
        self.name = name
        self.manifestHash = manifestHash
        self.manifestJSON = manifestJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct KnowledgeGraphNode: Sendable, Identifiable, Codable {
    public var id: String { nodeID }
    public let nodeID: String
    public let kind: String
    public let label: String
    public let lineage: [LineageRef]
    public let createdAt: Double
    public let updatedAt: Double

    public init(
        nodeID: String = "node-\(UUID().uuidString.prefix(12).lowercased())",
        kind: String,
        label: String,
        lineage: [LineageRef] = [],
        createdAt: Double = Date().timeIntervalSince1970,
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.nodeID = nodeID
        self.kind = kind
        self.label = label
        self.lineage = lineage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct KnowledgeGraphEdge: Sendable, Identifiable, Codable {
    public var id: String { edgeID }
    public let edgeID: String
    public let fromNodeID: String
    public let toNodeID: String
    public let relation: String
    public let lineage: [LineageRef]
    public let createdAt: Double

    public init(
        edgeID: String = "edge-\(UUID().uuidString.prefix(12).lowercased())",
        fromNodeID: String,
        toNodeID: String,
        relation: String,
        lineage: [LineageRef] = [],
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.edgeID = edgeID
        self.fromNodeID = fromNodeID
        self.toNodeID = toNodeID
        self.relation = relation
        self.lineage = lineage
        self.createdAt = createdAt
    }
}

public struct FabricationFinding: Sendable, Identifiable, Codable {
    public var id: String { findingID }
    public let findingID: String
    public let sessionID: String?
    public let claimText: String
    public let status: String
    public let evidenceJSON: String
    public let createdAt: Double

    public init(
        findingID: String = "finding-\(UUID().uuidString.prefix(12).lowercased())",
        sessionID: String? = nil,
        claimText: String,
        status: String,
        evidenceJSON: String,
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.findingID = findingID
        self.sessionID = sessionID
        self.claimText = claimText
        self.status = status
        self.evidenceJSON = evidenceJSON
        self.createdAt = createdAt
    }
}
