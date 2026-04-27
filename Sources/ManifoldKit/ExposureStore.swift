// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let exposureLogger = Logger(subsystem: "com.spatialduality.manifold", category: "exposure")

/// Persists access decisions and exposure records for governed activity.
public actor ExposureStore {
    private let db: DatabaseConnection

    /// Creates a store backed by the shared Manifold database.
    public init(db: DatabaseConnection) {
        self.db = db
    }

    /// Persists one access decision.
    public func recordDecision(_ decision: AccessDecision) throws {
        try db.execute(
            """
            INSERT INTO access_decisions (
                id, connection_id, agent, tool_name, resource_path, action,
                allowed, reason, access_mode, timestamp, policy_snapshot, client_identity,
                intent_summary, intent_details
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            params: [
                decision.id,
                decision.connectionID,
                decision.agent,
                decision.toolName,
                decision.resourcePath,
                decision.action,
                decision.allowed ? "1" : "0",
                decision.reason,
                decision.accessMode,
                String(decision.timestamp),
                decision.policySnapshot,
                decision.clientIdentity,
                decision.intentSummary,
                decision.intentDetails,
            ]
        )
    }

    /// Persists one exposure record.
    public func recordExposure(_ exposure: ExposureRecord) throws {
        try db.execute(
            """
            INSERT INTO exposure_records (
                id, connection_id, agent, tool_name, resource_path, byte_count,
                content_hash, exposure_type, timestamp, access_decision_id,
                payload_preview, payload_preview_truncated, client_identity,
                intent_summary, intent_details
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            params: [
                exposure.id,
                exposure.connectionID,
                exposure.agent,
                exposure.toolName,
                exposure.resourcePath,
                String(exposure.byteCount),
                exposure.contentHash,
                exposure.exposureType,
                String(exposure.timestamp),
                exposure.accessDecisionID,
                exposure.payloadPreview,
                exposure.payloadPreviewTruncated ? "1" : "0",
                exposure.clientIdentity,
                exposure.intentSummary,
                exposure.intentDetails,
            ]
        )
    }

    /// Returns recent access decisions for one runtime connection.
    public func decisions(connectionID: String, limit: Int) throws -> [AccessDecision] {
        let rows = try db.queryAll(
            """
            SELECT * FROM access_decisions
            WHERE connection_id = ?
            ORDER BY timestamp DESC
            LIMIT ?
            """,
            params: [connectionID, String(limit)]
        )
        return rows.compactMap(Self.decision(from:))
    }

    /// Returns recent exposure records for one runtime connection.
    public func exposures(connectionID: String, limit: Int) throws -> [ExposureRecord] {
        let rows = try db.queryAll(
            """
            SELECT * FROM exposure_records
            WHERE connection_id = ?
            ORDER BY timestamp DESC
            LIMIT ?
            """,
            params: [connectionID, String(limit)]
        )
        return rows.compactMap(Self.exposure(from:))
    }

    /// Returns recent exposure records for one governed resource path.
    public func exposures(resourcePath: String, limit: Int) throws -> [ExposureRecord] {
        let rows = try db.queryAll(
            """
            SELECT * FROM exposure_records
            WHERE resource_path = ?
            ORDER BY timestamp DESC
            LIMIT ?
            """,
            params: [resourcePath, String(limit)]
        )
        return rows.compactMap(Self.exposure(from:))
    }

    /// Returns recent exposure records for one content hash. This is the core
    /// primitive that lets later sessions avoid rereading bytes they already saw.
    public func exposures(contentHash: String, limit: Int) throws -> [ExposureRecord] {
        let rows = try db.queryAll(
            """
            SELECT * FROM exposure_records
            WHERE content_hash = ?
            ORDER BY timestamp DESC
            LIMIT ?
            """,
            params: [contentHash, String(limit)]
        )
        return rows.compactMap(Self.exposure(from:))
    }

    /// Returns recent exposure records across the governed history.
    public func recentExposures(limit: Int) throws -> [ExposureRecord] {
        let rows = try db.queryAll(
            """
            SELECT * FROM exposure_records
            ORDER BY timestamp DESC
            LIMIT ?
            """,
            params: [String(limit)]
        )
        return rows.compactMap(Self.exposure(from:))
    }

    public func latestExposure(resourcePath: String) throws -> ExposureRecord? {
        try exposures(resourcePath: resourcePath, limit: 1).first
    }

    public func latestExposure(connectionID: String, toolName: String) throws -> ExposureRecord? {
        let rows = try db.queryAll(
            """
            SELECT * FROM exposure_records
            WHERE connection_id = ? AND tool_name = ?
            ORDER BY timestamp DESC
            LIMIT 1
            """,
            params: [connectionID, toolName]
        )
        return rows.first.flatMap(Self.exposure(from:))
    }

    public func wasExposedBefore(contentHash: String, before timestamp: Double? = nil) throws -> Bool {
        var sql = "SELECT COUNT(*) FROM exposure_records WHERE content_hash = ?"
        var params: [String?] = [contentHash]
        if let timestamp {
            sql += " AND timestamp < ?"
            params.append(String(timestamp))
        }
        return (Int(try db.queryScalar(sql, params: params) ?? "0") ?? 0) > 0
    }

    /// Returns aggregate exposure counts for one runtime connection.
    public func totalExposure(connectionID: String) throws -> (fileCount: Int, totalBytes: Int) {
        let fileCount = Int(
            try db.queryScalar(
                """
                SELECT COUNT(DISTINCT resource_path) FROM exposure_records
                WHERE connection_id = ? AND resource_path IS NOT NULL AND resource_path != ''
                """,
                params: [connectionID]
            ) ?? "0"
        ) ?? 0
        let totalBytes = Int(
            try db.queryScalar(
                "SELECT COALESCE(SUM(byte_count), 0) FROM exposure_records WHERE connection_id = ?",
                params: [connectionID]
            ) ?? "0"
        ) ?? 0
        return (fileCount, totalBytes)
    }

    /// Returns a human-readable explanation of the most recent matching access decision.
    public func explainDecision(connectionID: String, path: String, action: String) throws -> String {
        let rows = try db.queryAll(
            """
            SELECT * FROM access_decisions
            WHERE connection_id = ? AND action = ? AND (resource_path = ? OR resource_path IS NULL)
            ORDER BY timestamp DESC
            LIMIT 1
            """,
            params: [connectionID, action, path]
        )
        guard let decision = rows.compactMap(Self.decision(from:)).first else {
            return "No recorded access decision for \(action) on \(path)."
        }

        let formatter = ISO8601DateFormatter.shared
        let timestamp = formatter.string(from: Date(timeIntervalSince1970: decision.timestamp))
        let disposition = decision.allowed ? "allowed" : "denied"
        let scope = decision.resourcePath ?? path
        var message = "\(decision.toolName) \(disposition) \(action) access to \(scope) via \(decision.accessMode) at \(timestamp) because \(decision.reason)."
        if let policySnapshot = decision.policySnapshot, !policySnapshot.isEmpty {
            message += " Policy snapshot: \(policySnapshot)"
        }
        return message
    }

    private static func decision(from row: [String: String]) -> AccessDecision? {
        guard let id = row["id"],
              let connectionID = row["connection_id"],
              let agent = row["agent"],
              let toolName = row["tool_name"],
              let action = row["action"],
              let allowedRaw = row["allowed"],
              let reason = row["reason"],
              let accessMode = row["access_mode"],
              let timestampRaw = row["timestamp"],
              let timestamp = Double(timestampRaw) else {
            exposureLogger.error("Failed to decode access decision row")
            return nil
        }
        return AccessDecision(
            id: id,
            connectionID: connectionID,
            agent: agent,
            toolName: toolName,
            resourcePath: row["resource_path"]?.nilIfEmpty,
            action: action,
            allowed: allowedRaw == "1",
            reason: reason,
            accessMode: accessMode,
            timestamp: timestamp,
            policySnapshot: row["policy_snapshot"]?.nilIfEmpty,
            clientIdentity: row["client_identity"]?.nilIfEmpty,
            intentSummary: row["intent_summary"]?.nilIfEmpty,
            intentDetails: row["intent_details"]?.nilIfEmpty
        )
    }

    private static func exposure(from row: [String: String]) -> ExposureRecord? {
        guard let id = row["id"],
              let connectionID = row["connection_id"],
              let agent = row["agent"],
              let toolName = row["tool_name"],
              let byteCountRaw = row["byte_count"],
              let byteCount = Int(byteCountRaw),
              let contentHash = row["content_hash"],
              let exposureType = row["exposure_type"],
              let timestampRaw = row["timestamp"],
              let timestamp = Double(timestampRaw),
              let accessDecisionID = row["access_decision_id"] else {
            exposureLogger.error("Failed to decode exposure row")
            return nil
        }
        return ExposureRecord(
            id: id,
            connectionID: connectionID,
            agent: agent,
            toolName: toolName,
            resourcePath: row["resource_path"]?.nilIfEmpty,
            byteCount: byteCount,
            contentHash: contentHash,
            exposureType: exposureType,
            timestamp: timestamp,
            accessDecisionID: accessDecisionID,
            payloadPreview: row["payload_preview"]?.nilIfEmpty,
            payloadPreviewTruncated: row["payload_preview_truncated"] == "1",
            clientIdentity: row["client_identity"]?.nilIfEmpty,
            intentSummary: row["intent_summary"]?.nilIfEmpty,
            intentDetails: row["intent_details"]?.nilIfEmpty
        )
    }
}
