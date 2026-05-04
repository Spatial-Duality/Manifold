// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "scope-mirror")

// MARK: - ScopeMirrorPlan

/// Diff between two agents' file-scope state, computed before any writes
/// happen. The UI renders this in a confirmation sheet so the user sees
/// exactly what will change before clicking Apply.
///
/// Designed to round-trip cleanly through XPC — Codable, value-typed, and
/// ordered fields so the diff renders deterministically.
public struct ScopeMirrorPlan: Sendable, Codable, Equatable {
    public let sourceAgent: TargetApp
    public let targetAgent: TargetApp

    /// Source IDs that the source agent has and the target agent doesn't —
    /// these will be inserted into the target's `allowed_source_ids`.
    public let sourceIDsToAdd: [String]

    /// Source IDs that the target agent has and the source agent doesn't —
    /// these will be removed from the target's `allowed_source_ids`. The
    /// associated file-visibility overrides are also dropped (matching the
    /// behavior of `revokeSourceScope`).
    public let sourceIDsToRemove: [String]

    /// Per-file overrides present on the source agent that need to land on
    /// the target agent (either because the target doesn't have them at all
    /// or has a different decision for the same path).
    public let overridesToWrite: [FileVisibilityOverrideRecord]

    /// Per-file overrides on the target agent that don't exist on the source
    /// agent — these will be cleared so the target ends up with exactly the
    /// source's set.
    public let overridesToClear: [FileVisibilityOverrideRecord]

    public var hasChanges: Bool {
        !sourceIDsToAdd.isEmpty
            || !sourceIDsToRemove.isEmpty
            || !overridesToWrite.isEmpty
            || !overridesToClear.isEmpty
    }

    public init(
        sourceAgent: TargetApp,
        targetAgent: TargetApp,
        sourceIDsToAdd: [String],
        sourceIDsToRemove: [String],
        overridesToWrite: [FileVisibilityOverrideRecord],
        overridesToClear: [FileVisibilityOverrideRecord]
    ) {
        self.sourceAgent = sourceAgent
        self.targetAgent = targetAgent
        self.sourceIDsToAdd = sourceIDsToAdd
        self.sourceIDsToRemove = sourceIDsToRemove
        self.overridesToWrite = overridesToWrite
        self.overridesToClear = overridesToClear
    }
}

// MARK: - ScopeMirror

/// Mirrors one agent's file-scope state onto another agent.
///
/// What gets mirrored:
///   - `AgentAccessPolicy.allowedSourceIDs` (the standing source set)
///   - `file_visibility_overrides` rows (per-file allow/deny decisions)
///
/// What is intentionally NOT mirrored:
///   - Standing write approvals — these are user-confirmed grants for one
///     specific assistant; mirroring would silently expand write authority.
///   - `is_paused` — leaves the target agent's own pause state alone.
///   - Email policy (domains, sensitivity, rules) — different surface;
///     v1 is files-only, matching the user-visible "files in scope" model.
///   - Temporary reveals — ephemeral by design.
///
/// Apply is idempotent: running mirror twice in a row leaves the target in
/// the same state as running it once. Re-running after a partial failure is
/// safe.
public enum ScopeMirror {
    /// Compute the diff that would bring `targetAgent` into alignment with
    /// `sourceAgent`. No side effects. Cheap enough to call on every change
    /// to either side; the UI uses it as a live preview.
    public static func preview(
        from sourceAgent: TargetApp,
        to targetAgent: TargetApp,
        policyStore: PolicyStore,
        overrideStore: FileVisibilityOverrideStore
    ) async throws -> ScopeMirrorPlan {
        guard sourceAgent != targetAgent else {
            return ScopeMirrorPlan(
                sourceAgent: sourceAgent,
                targetAgent: targetAgent,
                sourceIDsToAdd: [],
                sourceIDsToRemove: [],
                overridesToWrite: [],
                overridesToClear: []
            )
        }

        let sourcePolicy = try await policyStore.policy(for: sourceAgent)
        let targetPolicy = try await policyStore.policy(for: targetAgent)

        let sourceIDsToAdd = sourcePolicy.allowedSourceIDs
            .subtracting(targetPolicy.allowedSourceIDs)
            .sorted()
        let sourceIDsToRemove = targetPolicy.allowedSourceIDs
            .subtracting(sourcePolicy.allowedSourceIDs)
            .sorted()

        let sourceOverrides = try await overrideStore.overrides(agent: sourceAgent)
        let targetOverrides = try await overrideStore.overrides(agent: targetAgent)

        // Key by (sourceID, relativePath, isDirectory) — the natural primary
        // key for file_visibility_overrides ignoring `agent`. Decision is
        // the value being copied across.
        struct OverrideKey: Hashable {
            let sourceID: String
            let relativePath: String
            let isDirectory: Bool
        }

        func key(_ record: FileVisibilityOverrideRecord) -> OverrideKey {
            OverrideKey(sourceID: record.sourceID, relativePath: record.relativePath, isDirectory: record.isDirectory)
        }

        let sourceByKey = Dictionary(uniqueKeysWithValues: sourceOverrides.map { (key($0), $0) })
        let targetByKey = Dictionary(uniqueKeysWithValues: targetOverrides.map { (key($0), $0) })

        // Write any source override whose decision differs from (or is
        // missing on) the target — re-stamped with the target agent.
        var overridesToWrite: [FileVisibilityOverrideRecord] = []
        for (k, sourceRecord) in sourceByKey {
            let targetRecord = targetByKey[k]
            if targetRecord?.decision != sourceRecord.decision {
                overridesToWrite.append(
                    FileVisibilityOverrideRecord(
                        agent: targetAgent,
                        sourceID: sourceRecord.sourceID,
                        relativePath: sourceRecord.relativePath,
                        isDirectory: sourceRecord.isDirectory,
                        decision: sourceRecord.decision
                    )
                )
            }
        }
        overridesToWrite.sort { lhs, rhs in
            if lhs.sourceID != rhs.sourceID { return lhs.sourceID < rhs.sourceID }
            if lhs.relativePath != rhs.relativePath { return lhs.relativePath < rhs.relativePath }
            return !lhs.isDirectory && rhs.isDirectory
        }

        // Clear any target override that has no counterpart on the source.
        var overridesToClear: [FileVisibilityOverrideRecord] = []
        for (k, targetRecord) in targetByKey where sourceByKey[k] == nil {
            overridesToClear.append(targetRecord)
        }
        overridesToClear.sort { lhs, rhs in
            if lhs.sourceID != rhs.sourceID { return lhs.sourceID < rhs.sourceID }
            if lhs.relativePath != rhs.relativePath { return lhs.relativePath < rhs.relativePath }
            return !lhs.isDirectory && rhs.isDirectory
        }

        return ScopeMirrorPlan(
            sourceAgent: sourceAgent,
            targetAgent: targetAgent,
            sourceIDsToAdd: sourceIDsToAdd,
            sourceIDsToRemove: sourceIDsToRemove,
            overridesToWrite: overridesToWrite,
            overridesToClear: overridesToClear
        )
    }

    /// Apply a previously-computed plan. The order matters:
    ///
    ///   1. Remove sources we're dropping. This also fans out and clears
    ///      every override under those sources for the target — matching
    ///      the behavior of revoking a source via the normal UI.
    ///   2. Add new sources to the target's standing policy.
    ///   3. Write override differences (allow/deny mismatches).
    ///   4. Clear leftover overrides that exist only on the target.
    ///
    /// There's no cross-store transaction available, but each mutation is
    /// individually durable. If the apply is interrupted, re-running it
    /// computes a smaller plan that catches up — the operation is
    /// re-runnable by design.
    public static func apply(
        _ plan: ScopeMirrorPlan,
        policyStore: PolicyStore,
        overrideStore: FileVisibilityOverrideStore
    ) async throws {
        guard plan.sourceAgent != plan.targetAgent else { return }
        guard plan.hasChanges else { return }

        for sourceID in plan.sourceIDsToRemove {
            try await policyStore.removeSource(sourceID, from: plan.targetAgent)
            try await overrideStore.clearOverrides(agent: plan.targetAgent, sourceID: sourceID)
        }

        for sourceID in plan.sourceIDsToAdd {
            try await policyStore.addSource(sourceID, to: plan.targetAgent)
        }

        if !plan.overridesToWrite.isEmpty {
            try await overrideStore.setManyOverrides(plan.overridesToWrite)
        }

        for record in plan.overridesToClear {
            try await overrideStore.clearOverride(
                agent: plan.targetAgent,
                sourceID: record.sourceID,
                relativePath: record.relativePath,
                isDirectory: record.isDirectory
            )
        }

        logger.info(
            """
            Mirrored scope from \(plan.sourceAgent.rawValue) → \(plan.targetAgent.rawValue): \
            +\(plan.sourceIDsToAdd.count) sources, -\(plan.sourceIDsToRemove.count) sources, \
            \(plan.overridesToWrite.count) overrides written, \(plan.overridesToClear.count) overrides cleared
            """
        )
    }
}
