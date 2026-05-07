// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let toolMetricsLogger = Logger(subsystem: "com.spatialduality.manifold", category: "tool-metrics")

public actor ToolMetricsStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) throws {
        self.db = db
        try Self.ensureSchema(db)
    }

    public static func ensureSchema(_ db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS tool_call_metrics (
                metric_id TEXT PRIMARY KEY,
                connection_id TEXT NOT NULL,
                agent TEXT NOT NULL,
                tool_name TEXT NOT NULL,
                duration_ms REAL NOT NULL,
                output_bytes INTEGER NOT NULL,
                truncated INTEGER NOT NULL DEFAULT 0,
                is_error INTEGER NOT NULL DEFAULT 0,
                request_id TEXT,
                error_classification TEXT,
                error_boundary TEXT,
                error_phase TEXT,
                is_retryable INTEGER,
                runtime_generation INTEGER NOT NULL DEFAULT 0,
                metadata_json TEXT,
                exposure_id TEXT,
                grant_id TEXT,
                session_id TEXT,
                timestamp REAL NOT NULL
            )
        """)
        try addColumnIfMissing(db, table: "tool_call_metrics", column: "request_id", definition: "TEXT")
        try addColumnIfMissing(db, table: "tool_call_metrics", column: "error_classification", definition: "TEXT")
        try addColumnIfMissing(db, table: "tool_call_metrics", column: "error_boundary", definition: "TEXT")
        try addColumnIfMissing(db, table: "tool_call_metrics", column: "error_phase", definition: "TEXT")
        try addColumnIfMissing(db, table: "tool_call_metrics", column: "is_retryable", definition: "INTEGER")
        try addColumnIfMissing(db, table: "tool_call_metrics", column: "runtime_generation", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfMissing(db, table: "tool_call_metrics", column: "metadata_json", definition: "TEXT")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_tool_metrics_connection ON tool_call_metrics(connection_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_tool_metrics_request ON tool_call_metrics(request_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_tool_metrics_tool ON tool_call_metrics(tool_name)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_tool_metrics_timestamp ON tool_call_metrics(timestamp)")
    }

    public func record(_ metric: ToolCallMetric) throws {
        try db.execute("""
            INSERT INTO tool_call_metrics (
                metric_id, connection_id, agent, tool_name, duration_ms, output_bytes,
                truncated, is_error, request_id, error_classification, error_boundary,
                error_phase, is_retryable, runtime_generation, metadata_json,
                exposure_id, grant_id, session_id, timestamp
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, params: [
            metric.metricID,
            metric.connectionID,
            metric.agent,
            metric.toolName,
            "\(metric.durationMS)",
            "\(metric.outputBytes)",
            metric.truncated ? "1" : "0",
            metric.isError ? "1" : "0",
            metric.requestID,
            metric.errorClassification,
            metric.errorBoundary,
            metric.errorPhase,
            metric.isRetryable.map { $0 ? "1" : "0" },
            "\(metric.runtimeGeneration)",
            metric.metadataJSON,
            metric.exposureID,
            metric.grantID,
            metric.sessionID,
            "\(metric.timestamp)",
        ])
    }

    public func recent(limit: Int = 50) throws -> [ToolCallMetric] {
        let rows = try db.queryAll(
            "SELECT * FROM tool_call_metrics ORDER BY timestamp DESC LIMIT ?",
            params: ["\(limit)"]
        )
        return rows.compactMap(Self.metric(from:))
    }

    public func report(limit: Int = 200) throws -> ToolCostReport {
        let metrics = try recent(limit: limit)
        let totalCalls = metrics.count
        let totalBytes = metrics.reduce(0) { $0 + $1.outputBytes }
        let totalDuration = metrics.reduce(0.0) { $0 + $1.durationMS }
        let callsByTool = metrics.reduce(into: [String: Int]()) { counts, metric in
            counts[metric.toolName, default: 0] += 1
        }
        return ToolCostReport(
            totalCalls: totalCalls,
            totalOutputBytes: totalBytes,
            averageDurationMS: totalCalls == 0 ? 0 : totalDuration / Double(totalCalls),
            callsByTool: callsByTool,
            recent: metrics
        )
    }

    private static func metric(from row: [String: String]) -> ToolCallMetric? {
        guard let metricID = row["metric_id"],
              let connectionID = row["connection_id"],
              let agent = row["agent"],
              let toolName = row["tool_name"],
              let durationRaw = row["duration_ms"],
              let durationMS = Double(durationRaw),
              let bytesRaw = row["output_bytes"],
              let outputBytes = Int(bytesRaw),
              let timestampRaw = row["timestamp"],
              let timestamp = Double(timestampRaw) else {
            toolMetricsLogger.warning("Failed to decode tool metric row")
            return nil
        }
        return ToolCallMetric(
            metricID: metricID,
            connectionID: connectionID,
            agent: agent,
            toolName: toolName,
            durationMS: durationMS,
            outputBytes: outputBytes,
            truncated: row["truncated"] == "1",
            isError: row["is_error"] == "1",
            requestID: row["request_id"]?.nilIfEmpty,
            errorClassification: row["error_classification"]?.nilIfEmpty,
            errorBoundary: row["error_boundary"]?.nilIfEmpty,
            errorPhase: row["error_phase"]?.nilIfEmpty,
            isRetryable: row["is_retryable"].map { $0 == "1" },
            runtimeGeneration: row["runtime_generation"].flatMap(Int.init) ?? 0,
            metadataJSON: row["metadata_json"]?.nilIfEmpty,
            exposureID: row["exposure_id"]?.nilIfEmpty,
            grantID: row["grant_id"]?.nilIfEmpty,
            sessionID: row["session_id"]?.nilIfEmpty,
            timestamp: timestamp
        )
    }

    private static func addColumnIfMissing(
        _ db: DatabaseConnection,
        table: String,
        column: String,
        definition: String
    ) throws {
        let columns = try db.queryAll("PRAGMA table_info(\(table))")
        guard !columns.contains(where: { $0["name"] == column }) else { return }
        try db.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }
}
