// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum FileVisibilityOverrideDecision: String, Codable, Sendable {
    case allow
    case deny
}

public struct FileVisibilityOverrideRecord: Sendable, Hashable, Identifiable, Codable {
    public var id: String {
        "\(agent.rawValue):\(sourceID):\(relativePath):\(isDirectory ? "dir" : "file")"
    }

    public let agent: TargetApp
    public let sourceID: String
    public let relativePath: String
    public let isDirectory: Bool
    public let decision: FileVisibilityOverrideDecision
    public let updatedAt: String

    public init(
        agent: TargetApp,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool,
        decision: FileVisibilityOverrideDecision,
        updatedAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.agent = agent
        self.sourceID = sourceID
        self.relativePath = FileSelectionScope(
            sourceID: sourceID,
            relativePath: relativePath,
            isDirectory: isDirectory
        ).normalizedRelativePath
        self.isDirectory = isDirectory
        self.decision = decision
        self.updatedAt = updatedAt
    }

    init?(row: [String: String]) {
        guard let agentRaw = row["agent"],
              let agent = TargetApp(rawValue: agentRaw),
              let sourceID = row["source_id"],
              let relativePath = row["relative_path"],
              let decisionRaw = row["decision"],
              let decision = FileVisibilityOverrideDecision(rawValue: decisionRaw),
              let updatedAt = row["updated_at"] else {
            return nil
        }

        self.init(
            agent: agent,
            sourceID: sourceID,
            relativePath: relativePath,
            isDirectory: row["is_directory"] == "1",
            decision: decision,
            updatedAt: updatedAt
        )
    }
}

public enum FileVisibilityEvaluationOrigin: String, Sendable {
    case explicitAllow
    case explicitDeny
    case inheritedAllow
    case inheritedHidden
}

public struct FileVisibilityEvaluation: Sendable, Hashable {
    public let isVisible: Bool
    public let origin: FileVisibilityEvaluationOrigin

    public init(isVisible: Bool, origin: FileVisibilityEvaluationOrigin) {
        self.isVisible = isVisible
        self.origin = origin
    }
}

public struct FileVisibilityResolver: Sendable {
    private let overridesBySource: [String: [FileVisibilityOverrideRecord]]
    private let overrideSignatures: [String]

    public init(overrides: [FileVisibilityOverrideRecord]) {
        self.overrideSignatures = overrides
            .map { "\($0.id):\($0.decision.rawValue):\($0.updatedAt)" }
            .sorted()
        self.overridesBySource = Dictionary(grouping: overrides, by: \.sourceID).mapValues { records in
            records.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return !lhs.isDirectory
                }
                let lhsDepth = lhs.relativePath.split(separator: "/").count
                let rhsDepth = rhs.relativePath.split(separator: "/").count
                if lhsDepth != rhsDepth {
                    return lhsDepth > rhsDepth
                }
                return lhs.relativePath < rhs.relativePath
            }
        }
    }

    public var sourceIDsWithAllowOverrides: Set<String> {
        Set(
            overridesBySource.compactMap { sourceID, records in
                records.contains(where: { $0.decision == .allow }) ? sourceID : nil
            }
        )
    }

    public var cacheKey: String {
        overrideSignatures.joined(separator: "|")
    }

    public func evaluate(sourceID: String, relativePath: String, defaultVisible: Bool) -> FileVisibilityEvaluation {
        let normalizedPath = FileSelectionScope(
            sourceID: sourceID,
            relativePath: relativePath,
            isDirectory: false
        ).normalizedRelativePath

        if let override = matchingOverride(sourceID: sourceID, normalizedPath: normalizedPath) {
            switch override.decision {
            case .allow:
                return FileVisibilityEvaluation(isVisible: true, origin: .explicitAllow)
            case .deny:
                return FileVisibilityEvaluation(isVisible: false, origin: .explicitDeny)
            }
        }

        return FileVisibilityEvaluation(
            isVisible: defaultVisible,
            origin: defaultVisible ? .inheritedAllow : .inheritedHidden
        )
    }

    private func matchingOverride(sourceID: String, normalizedPath: String) -> FileVisibilityOverrideRecord? {
        guard let candidates = overridesBySource[sourceID] else { return nil }
        return candidates.first { record in
            if record.isDirectory {
                if record.relativePath.isEmpty {
                    return true
                }
                return normalizedPath == record.relativePath
                    || normalizedPath.hasPrefix(record.relativePath + "/")
            }
            return normalizedPath == record.relativePath
        }
    }
}

public actor FileVisibilityOverrideStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    public func overrides(agent: TargetApp) throws -> [FileVisibilityOverrideRecord] {
        let rows = try db.queryAll(
            """
            SELECT agent, source_id, relative_path, is_directory, decision, updated_at
            FROM file_visibility_overrides
            WHERE agent = ?
            ORDER BY source_id ASC, relative_path ASC
            """,
            params: [agent.rawValue]
        )
        return rows.compactMap(FileVisibilityOverrideRecord.init(row:))
    }

    public func resolver(agent: TargetApp) throws -> FileVisibilityResolver {
        FileVisibilityResolver(overrides: try overrides(agent: agent))
    }

    public func setOverride(
        agent: TargetApp,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool,
        decision: FileVisibilityOverrideDecision
    ) throws {
        let normalizedPath = FileSelectionScope(
            sourceID: sourceID,
            relativePath: relativePath,
            isDirectory: isDirectory
        ).normalizedRelativePath
        try db.execute(
            """
            INSERT OR REPLACE INTO file_visibility_overrides (
                agent, source_id, relative_path, is_directory, decision, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            params: [
                agent.rawValue,
                sourceID,
                normalizedPath,
                isDirectory ? "1" : "0",
                decision.rawValue,
                ISO8601DateFormatter.shared.string(from: Date()),
            ]
        )
    }

    /// Apply a batch of overrides in a single transaction. Required by the
    /// bulk-action bar in the unified Access surface — looping per-file would
    /// run N round-trips and N statement prepares per click.
    ///
    /// Empty input is a no-op. Mixed allow/deny in one batch is supported.
    /// Atomicity: if any row fails, the whole batch rolls back.
    public func setManyOverrides(_ overrides: [FileVisibilityOverrideRecord]) throws {
        guard !overrides.isEmpty else { return }
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.transaction {
            for override in overrides {
                let normalizedPath = FileSelectionScope(
                    sourceID: override.sourceID,
                    relativePath: override.relativePath,
                    isDirectory: override.isDirectory
                ).normalizedRelativePath
                try db.execute(
                    """
                    INSERT OR REPLACE INTO file_visibility_overrides (
                        agent, source_id, relative_path, is_directory, decision, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    params: [
                        override.agent.rawValue,
                        override.sourceID,
                        normalizedPath,
                        override.isDirectory ? "1" : "0",
                        override.decision.rawValue,
                        now,
                    ]
                )
            }
        }
    }

    public func clearOverride(
        agent: TargetApp,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool
    ) throws {
        let normalizedPath = FileSelectionScope(
            sourceID: sourceID,
            relativePath: relativePath,
            isDirectory: isDirectory
        ).normalizedRelativePath
        try db.execute(
            """
            DELETE FROM file_visibility_overrides
            WHERE agent = ? AND source_id = ? AND relative_path = ? AND is_directory = ?
            """,
            params: [agent.rawValue, sourceID, normalizedPath, isDirectory ? "1" : "0"]
        )
    }

    public func clearOverrides(agent: TargetApp, sourceID: String) throws {
        try db.execute(
            "DELETE FROM file_visibility_overrides WHERE agent = ? AND source_id = ?",
            params: [agent.rawValue, sourceID]
        )
    }

    public func clearOverrides(sourceID: String) throws {
        try db.execute(
            "DELETE FROM file_visibility_overrides WHERE source_id = ?",
            params: [sourceID]
        )
    }

    /// Wipe every override for one agent. Used by the Focus activation
    /// pipeline to swap an agent's override set in one shot before
    /// repopulating from the new Focus's saved overrides.
    public func clearAllOverrides(agent: TargetApp) throws {
        try db.execute(
            "DELETE FROM file_visibility_overrides WHERE agent = ?",
            params: [agent.rawValue]
        )
    }
}
