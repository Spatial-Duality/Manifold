// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// User-selectable behavior for sensitive-content detection on file reads.
///
/// ┌──────┬───────────────────────────────────────────────────────────────┐
/// │ Mode │ Behavior at file-read time                                    │
/// ├──────┼───────────────────────────────────────────────────────────────┤
/// │ off  │ No findings scan. Return content unconditionally.            │
/// │ warn │ Scan, return content, flag findings in the exposure record.  │
/// │ block│ Scan, deny if findings unless an explicit grant-level         │
/// │      │ override has been recorded for that (grant, source, path).   │
/// └──────┴───────────────────────────────────────────────────────────────┘
public enum FilterMode: String, Codable, Sendable, CaseIterable {
    case off
    case warn
    case block
}

/// Outcome of evaluating a file read against the active filter mode.
///
/// `findings` is opaque to this layer — the FindingsProvider that produces
/// them is plugged in by `ManifoldBridge` at enforcement time. This type
/// carries the count + a coarse summary so the UI can render the inspector
/// audit section without re-querying.
public enum FilterDecision: Sendable, Equatable {
    case allow
    case allowWithWarning(findings: FilterFindingsSummary)
    case deny(findings: FilterFindingsSummary, canOverride: Bool)
}

/// Coarse summary of sensitive-content findings for a single file read.
/// Counts are denormalized here to keep the runtime decision cheap.
public struct FilterFindingsSummary: Codable, Sendable, Hashable {
    public let totalCount: Int
    public let secretCount: Int
    public let piiCount: Int
    public let financialCount: Int

    public init(
        totalCount: Int,
        secretCount: Int = 0,
        piiCount: Int = 0,
        financialCount: Int = 0
    ) {
        self.totalCount = totalCount
        self.secretCount = secretCount
        self.piiCount = piiCount
        self.financialCount = financialCount
    }

    public static let empty = FilterFindingsSummary(totalCount: 0)
    public var isEmpty: Bool { totalCount == 0 }
}

/// Per-(grant, source, relative path) "override and share" decision recorded
/// when the user explicitly approves sharing a file flagged by Block mode.
/// The override is grant-scoped — when the grant ends, the row stays for the
/// audit trail but no longer affects future grants.
public struct FilterModeOverrideRecord: Sendable, Hashable, Codable {
    public let grantID: String
    public let agent: TargetApp
    public let sourceID: String
    public let relativePath: String
    public let approvedAt: String

    public init(
        grantID: String,
        agent: TargetApp,
        sourceID: String,
        relativePath: String,
        approvedAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.grantID = grantID
        self.agent = agent
        self.sourceID = sourceID
        self.relativePath = relativePath
        self.approvedAt = approvedAt
    }
}
