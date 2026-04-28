// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

/// Aggregated inspector data for a single file row.
///
/// Five sections render in the unified Access inspector and each maps to a
/// runtime store (LedgerStore, CapabilityHandleStore, ExposureStore,
/// MemoryStore, ToolMetricsStore). They're fetched together so the
/// inspector can render in one paint after a row click.
///
/// ┌─────────────────────────────────────────────────────────────────┐
/// │ InspectorContext                                                │
/// ├──────────────────────┬──────────────────────────────────────────┤
/// │ ledger               │ LedgerStore.verifyChain(forFile:)        │
/// │ findings             │ CapabilityHandleStore.findingsForFile    │
/// │ exposures            │ ExposureStore.exposureCounts(forFile:)   │
/// │ memory               │ MemoryStore.factsAboutFile(...)          │
/// │ toolMetrics          │ ToolMetricsStore.invocationsTouchingFile │
/// └──────────────────────┴──────────────────────────────────────────┘
public struct InspectorContext: Codable, Sendable, Hashable {
    public let fileID: InspectorFileID
    public let ledger: LedgerVerificationSection
    public let findings: FilterFindingsSummary
    public let exposures: ExposureSection
    public let memory: MemoryLineageSection
    public let toolMetrics: ToolMetricsSection
    public let fetchedAt: Date

    public init(
        fileID: InspectorFileID,
        ledger: LedgerVerificationSection = .unknown,
        findings: FilterFindingsSummary = .empty,
        exposures: ExposureSection = .empty,
        memory: MemoryLineageSection = .empty,
        toolMetrics: ToolMetricsSection = .empty,
        fetchedAt: Date = Date()
    ) {
        self.fileID = fileID
        self.ledger = ledger
        self.findings = findings
        self.exposures = exposures
        self.memory = memory
        self.toolMetrics = toolMetrics
        self.fetchedAt = fetchedAt
    }
}

/// Stable identity for a file in the unified Access surface. Source ID +
/// relative path is the only unambiguous key — paths alone collide across
/// sources (two folders with /README.md), and runtime artifact IDs aren't
/// stable across re-materializations.
public struct InspectorFileID: Codable, Sendable, Hashable {
    public let sourceID: String
    public let relativePath: String

    public init(sourceID: String, relativePath: String) {
        self.sourceID = sourceID
        self.relativePath = relativePath
    }
}

// MARK: - Sections

public enum LedgerVerificationSection: Codable, Sendable, Hashable {
    /// Section hasn't been queried yet.
    case unknown
    /// Ledger chain verified — N entries chained, all hashes match.
    case verified(entryCount: Int)
    /// Some entries are not timestamp-covered (legacy rows).
    case partial(entryCount: Int, legacyCount: Int)
    /// Verification failed — chain is broken or tampered.
    case failed(reason: String)
}

public struct ExposureSection: Codable, Sendable, Hashable {
    /// Per-agent read counts for the file. Order matches connection order
    /// so the UI can render a stable mini-chart.
    public let perAgent: [AgentExposure]
    public let totalBytes: Int64

    public init(perAgent: [AgentExposure], totalBytes: Int64) {
        self.perAgent = perAgent
        self.totalBytes = totalBytes
    }

    public static let empty = ExposureSection(perAgent: [], totalBytes: 0)
}

public struct AgentExposure: Codable, Sendable, Hashable {
    public let agent: TargetApp
    public let readCount: Int
    public let writeCount: Int
    public let lastTouched: String? // ISO8601 timestamp, optional

    public init(agent: TargetApp, readCount: Int, writeCount: Int, lastTouched: String? = nil) {
        self.agent = agent
        self.readCount = readCount
        self.writeCount = writeCount
        self.lastTouched = lastTouched
    }
}

public struct MemoryLineageSection: Codable, Sendable, Hashable {
    /// Number of memory items derived from this file.
    public let factCount: Int
    public let lastUpdated: String? // ISO8601, optional

    public init(factCount: Int, lastUpdated: String? = nil) {
        self.factCount = factCount
        self.lastUpdated = lastUpdated
    }

    public static let empty = MemoryLineageSection(factCount: 0)
    public var isEmpty: Bool { factCount == 0 }
}

public struct ToolMetricsSection: Codable, Sendable, Hashable {
    public let invocationCount: Int
    public let totalDurationMS: Int
    public let totalOutputBytes: Int64

    public init(invocationCount: Int, totalDurationMS: Int, totalOutputBytes: Int64) {
        self.invocationCount = invocationCount
        self.totalDurationMS = totalDurationMS
        self.totalOutputBytes = totalOutputBytes
    }

    public static let empty = ToolMetricsSection(
        invocationCount: 0, totalDurationMS: 0, totalOutputBytes: 0
    )
    public var isEmpty: Bool { invocationCount == 0 }
}
