import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "grants")

/// Manages the content boundary lifecycle: sources, grants, and their relationships.
/// Sources are persistent pointers to user-approved folders.
/// Grants are time-bounded sessions that materialize source content for a specific agent.
public actor GrantStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    // MARK: - Sources

    /// Register a new source folder. Returns the source ID.
    @discardableResult
    public func addSource(displayName: String, rootPath: String) throws -> String {
        let sourceID = "src-\(UUID().uuidString.prefix(8).lowercased())"
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute("""
            INSERT INTO sources (source_id, display_name, original_root_path, status, created_at, updated_at)
            VALUES (?, ?, ?, 'idle', ?, ?)
        """, params: [sourceID, displayName, rootPath, now, now])
        logger.info("Added source \(sourceID): \(displayName)")
        return sourceID
    }

    /// Sources currently available to share with agents.
    public func activeSources() throws -> [SourceRecord] {
        let rows = try db.queryAll(
            "SELECT * FROM sources WHERE status IN ('idle', 'active') ORDER BY updated_at DESC"
        )
        return rows.compactMap { SourceRecord(row: $0) }
    }

    /// All sources including removed, for admin/debug views.
    public func allSources() throws -> [SourceRecord] {
        let rows = try db.queryAll("SELECT * FROM sources ORDER BY updated_at DESC")
        return rows.compactMap { SourceRecord(row: $0) }
    }

    /// Get a single source by ID.
    public func source(id: String) throws -> SourceRecord? {
        let rows = try db.queryAll(
            "SELECT * FROM sources WHERE source_id = ? LIMIT 1",
            params: [id]
        )
        return rows.first.flatMap { SourceRecord(row: $0) }
    }

    /// Get a source by its original root path.
    public func source(byPath path: String) throws -> SourceRecord? {
        let rows = try db.queryAll(
            "SELECT * FROM sources WHERE original_root_path = ? LIMIT 1",
            params: [path]
        )
        return rows.first.flatMap { SourceRecord(row: $0) }
    }

    /// Update source status: idle, active, paused, removed.
    public func updateSourceStatus(sourceID: String, status: String) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            "UPDATE sources SET status = ?, updated_at = ? WHERE source_id = ?",
            params: [status, now, sourceID]
        )
    }

    /// Soft-remove a source (sets status to "removed"). Does not delete data.
    public func removeSource(sourceID: String) throws {
        try updateSourceStatus(sourceID: sourceID, status: "removed")
        logger.info("Removed source \(sourceID)")
    }

    /// Pause a source (hidden from MCP, visible in dashboard).
    public func pauseSource(sourceID: String) throws {
        try updateSourceStatus(sourceID: sourceID, status: "paused")
    }

    /// Resume a paused source.
    public func resumeSource(sourceID: String) throws {
        try updateSourceStatus(sourceID: sourceID, status: "idle")
    }

    // MARK: - Grants

    /// Start a new grant for a target app. Ends any existing active grant for the same target/profile.
    /// Returns the new grant ID.
    @discardableResult
    public func startGrant(
        targetApp: TargetApp,
        profileID: String,
        sourceIDs: [String],
        materializationRoot: String,
        inactivityTimeout: TimeInterval = 3600,
        refreshOfGrantID: String? = nil,
        emailSensitivity: String = "moderate",
        summaryFraming: String? = nil,
        explicitSelection: Bool = false,
        noteCaptureMode: SessionNoteCaptureMode = .off
    ) throws -> GrantRecord {
        // End existing active grant for this target/profile
        try endActiveGrant(targetApp: targetApp, profileID: profileID, reason: .timedOut)

        let grantID = "grant-\(UUID().uuidString.prefix(8).lowercased())"
        let now = ISO8601DateFormatter.shared.string(from: Date())
        let deadline = ISO8601DateFormatter.shared.string(
            from: Date().addingTimeInterval(inactivityTimeout)
        )

        var linkedSources: [(String, SourceRecord)] = []
        for sourceID in sourceIDs {
            if let source = try source(id: sourceID) {
                linkedSources.append((sourceID, source))
            }
        }
        let mountNames = Self.uniqueMountNames(for: linkedSources.map(\.1))

        try db.transaction {
            try db.execute("""
                INSERT INTO grants (grant_id, target_app, profile_id, status, started_at,
                    materialization_root, inactivity_deadline, refresh_of_grant_id,
                    email_sensitivity, summary_framing, explicit_selection, note_capture_mode)
                VALUES (?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?)
            """, params: [
                grantID, targetApp.rawValue, profileID, now,
                materializationRoot, deadline, refreshOfGrantID,
                emailSensitivity, summaryFraming, explicitSelection ? "1" : "0",
                noteCaptureMode.rawValue,
            ])

            // Link sources to this grant
            for (sourceID, source) in linkedSources {
                let mountName = mountNames[sourceID] ?? URL(fileURLWithPath: source.originalRootPath).lastPathComponent
                try db.execute("""
                    INSERT INTO grant_sources (grant_id, source_id, mount_name)
                    VALUES (?, ?, ?)
                """, params: [grantID, sourceID, mountName])
            }

            // Mark linked sources as active
            for sourceID in sourceIDs {
                try db.execute(
                    "UPDATE sources SET status = 'active', updated_at = ? WHERE source_id = ? AND status != 'removed'",
                    params: [now, sourceID]
                )
            }
        }

        logger.info("Started grant \(grantID) for \(targetApp.rawValue) with \(sourceIDs.count) sources")
        guard let created = try grant(id: grantID) else {
            throw ManifoldError.database("Grant \(grantID) not found after insert")
        }
        return created
    }

    /// Get a single grant by ID.
    public func grant(id: String) throws -> GrantRecord? {
        let rows = try db.queryAll(
            "SELECT * FROM grants WHERE grant_id = ? LIMIT 1",
            params: [id]
        )
        return rows.first.flatMap { GrantRecord(row: $0) }
    }

    /// Get the current active grant for a target app/profile, if any.
    public func activeGrant(targetApp: TargetApp, profileID: String) throws -> GrantRecord? {
        let rows = try db.queryAll("""
            SELECT * FROM grants
            WHERE target_app = ? AND profile_id = ? AND status = 'active'
            ORDER BY started_at DESC LIMIT 1
        """, params: [targetApp.rawValue, profileID])
        return rows.first.flatMap { GrantRecord(row: $0) }
    }

    /// End a specific grant.
    public func endGrant(grantID: String, reason: GrantStatus = .ended) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            "UPDATE grants SET status = ?, ended_at = ? WHERE grant_id = ? AND status = 'active'",
            params: [reason.rawValue, now, grantID]
        )

        // Reset linked sources back to idle (if no other active grants reference them)
        let linkedSources = try grantSources(grantID: grantID)
        for gs in linkedSources {
            let otherActive = try db.queryScalar("""
                SELECT COUNT(*) FROM grant_sources gs
                JOIN grants g ON g.grant_id = gs.grant_id
                WHERE gs.source_id = ? AND g.status = 'active' AND g.grant_id != ?
            """, params: [gs.sourceID, grantID])
            if otherActive == "0" || otherActive == nil {
                try db.execute(
                    "UPDATE sources SET status = 'idle', updated_at = ? WHERE source_id = ? AND status = 'active'",
                    params: [now, gs.sourceID]
                )
            }
        }

        logger.info("Ended grant \(grantID) (\(reason.rawValue))")
    }

    /// End the active grant for a specific target/profile.
    func endActiveGrant(targetApp: TargetApp, profileID: String, reason: GrantStatus = .ended) throws {
        if let active = try activeGrant(targetApp: targetApp, profileID: profileID) {
            try endGrant(grantID: active.grantID, reason: reason)
        }
    }

    /// Refresh inactivity deadline for an active grant.
    public func touchGrant(grantID: String, timeout: TimeInterval = 3600) throws {
        let deadline = ISO8601DateFormatter.shared.string(
            from: Date().addingTimeInterval(timeout)
        )
        try db.execute(
            "UPDATE grants SET inactivity_deadline = ? WHERE grant_id = ? AND status = 'active'",
            params: [deadline, grantID]
        )
    }

    /// Find and end grants past their inactivity deadline.
    public func expireStaleGrants() throws -> Int {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        let stale = try db.queryAll("""
            SELECT grant_id FROM grants
            WHERE status = 'active' AND inactivity_deadline IS NOT NULL AND inactivity_deadline < ?
        """, params: [now])

        for row in stale {
            guard let grantID = row["grant_id"] else { continue }
            try endGrant(grantID: grantID, reason: .timedOut)
        }
        if !stale.isEmpty {
            logger.info("Expired \(stale.count) stale grants")
        }
        return stale.count
    }

    /// All grants, most recent first.
    public func allGrants(limit: Int = 50) throws -> [GrantRecord] {
        let rows = try db.queryAll(
            "SELECT * FROM grants ORDER BY started_at DESC LIMIT ?",
            params: ["\(limit)"]
        )
        return rows.compactMap { GrantRecord(row: $0) }
    }

    // MARK: - Grant ↔ Source Links

    /// Get all source links for a grant.
    public func grantSources(grantID: String) throws -> [GrantSourceRecord] {
        let rows = try db.queryAll(
            "SELECT * FROM grant_sources WHERE grant_id = ?",
            params: [grantID]
        )
        return rows.compactMap { GrantSourceRecord(row: $0) }
    }

    public func replaceGrantFileScopes(grantID: String, scopes: [FileSelectionScope]) throws {
        try db.transaction {
            try db.execute(
                "DELETE FROM grant_file_scopes WHERE grant_id = ?",
                params: [grantID]
            )
            for scope in scopes {
                try db.execute(
                    """
                    INSERT INTO grant_file_scopes (
                        grant_id, source_id, relative_path, is_directory
                    ) VALUES (?, ?, ?, ?)
                    """,
                    params: [
                        grantID,
                        scope.sourceID,
                        scope.normalizedRelativePath,
                        scope.isDirectory ? "1" : "0",
                    ]
                )
            }
        }
    }

    public func grantFileScopes(grantID: String) throws -> [GrantFileScopeRecord] {
        let rows = try db.queryAll(
            """
            SELECT * FROM grant_file_scopes
            WHERE grant_id = ?
            ORDER BY source_id ASC, relative_path ASC
            """,
            params: [grantID]
        )
        return rows.compactMap { GrantFileScopeRecord(row: $0) }
    }

    /// Update the materialization root path for a grant (e.g. after resolving the actual grant ID).
    public func updateMaterializationRoot(grantID: String, root: String) throws {
        try db.execute(
            "UPDATE grants SET materialization_root = ? WHERE grant_id = ?",
            params: [root, grantID]
        )
    }

    /// Set the baseline manifest hash for a grant-source link (after materialization).
    public func setBaselineHash(grantID: String, sourceID: String, hash: String) throws {
        try db.execute("""
            UPDATE grant_sources SET baseline_manifest_hash = ?
            WHERE grant_id = ? AND source_id = ?
        """, params: [hash, grantID, sourceID])
    }

    // MARK: - Promotions

    /// Record a promotion result (write-back from materialized to original).
    @discardableResult
    public func recordPromotion(
        grantID: String,
        sourceID: String,
        relativePath: String,
        result: PromotionResult,
        originalBeforeHash: String? = nil,
        promotedHash: String? = nil,
        conflictReason: String? = nil
    ) throws -> String {
        let promotionID = "promo-\(UUID().uuidString.prefix(8).lowercased())"
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute("""
            INSERT INTO promotions (promotion_id, grant_id, source_id, relative_path,
                result, original_before_hash, promoted_hash, conflict_reason, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, params: [
            promotionID, grantID, sourceID, relativePath,
            result.rawValue, originalBeforeHash, promotedHash, conflictReason, now,
        ])
        return promotionID
    }

    /// Get all promotions for a grant.
    public func promotions(grantID: String) throws -> [PromotionRecord] {
        let rows = try db.queryAll(
            "SELECT * FROM promotions WHERE grant_id = ? ORDER BY created_at ASC",
            params: [grantID]
        )
        return rows.compactMap { PromotionRecord(row: $0) }
    }

    // MARK: - Session Summaries

    /// Store a session summary after a grant ends.
    @discardableResult
    public func saveSummary(
        grantID: String,
        targetApp: TargetApp,
        startedAt: String,
        endedAt: String,
        markdown: String,
        jsonHash: String? = nil,
        kind: SessionSummaryKind = .summary,
        origin: SessionSummaryOrigin = .system
    ) throws -> String {
        let summaryID = "sum-\(UUID().uuidString.prefix(8).lowercased())"
        try db.execute("""
            INSERT INTO session_summaries (summary_id, grant_id, target_app,
                started_at, ended_at, summary_markdown, summary_json_hash, summary_kind, summary_origin)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, params: [
            summaryID, grantID, targetApp.rawValue,
            startedAt, endedAt, markdown, jsonHash, kind.rawValue, origin.rawValue,
        ])
        return summaryID
    }

    /// Get all session summaries, most recent first.
    public func allSummaries(limit: Int = 20) throws -> [SessionSummaryRecord] {
        let rows = try db.queryAll(
            "SELECT * FROM session_summaries ORDER BY ended_at DESC LIMIT ?",
            params: ["\(limit)"]
        )
        return rows.compactMap { SessionSummaryRecord(row: $0) }
    }

    /// Get summaries for a specific grant.
    public func summaries(grantID: String) throws -> [SessionSummaryRecord] {
        let rows = try db.queryAll(
            "SELECT * FROM session_summaries WHERE grant_id = ? ORDER BY ended_at DESC",
            params: [grantID]
        )
        return rows.compactMap { SessionSummaryRecord(row: $0) }
    }

    public func summaries(grantID: String, kind: SessionSummaryKind) throws -> [SessionSummaryRecord] {
        let rows = try db.queryAll(
            """
            SELECT * FROM session_summaries
            WHERE grant_id = ? AND summary_kind = ?
            ORDER BY ended_at DESC
            """,
            params: [grantID, kind.rawValue]
        )
        return rows.compactMap { SessionSummaryRecord(row: $0) }
    }

    private static func uniqueMountNames(for sources: [SourceRecord]) -> [String: String] {
        var result: [String: String] = [:]
        var used: Set<String> = []

        for source in sources {
            let base = sanitizedMountName(for: source)
            var candidate = base
            var suffix = 2
            while used.contains(candidate) {
                candidate = "\(base)-\(suffix)"
                suffix += 1
            }
            used.insert(candidate)
            result[source.sourceID] = candidate
        }

        return result
    }

    private static func sanitizedMountName(for source: SourceRecord) -> String {
        let base = URL(fileURLWithPath: source.originalRootPath).lastPathComponent
        let sanitized = base
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? source.sourceID : sanitized
    }
}
