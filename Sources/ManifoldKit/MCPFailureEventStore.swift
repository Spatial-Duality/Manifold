// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let mcpFailureLogger = Logger(subsystem: "com.spatialduality.manifold", category: "mcp-failures")

public protocol MCPFailureEventRecording: Sendable {
    func record(_ event: MCPFailureEvent) async throws
}

/// Minimal write-only facade for processes that only need to durably append
/// failure events. This keeps the MCP helper from depending on read/query
/// methods of the full failure store.
public actor MCPFailureEventWriter: MCPFailureEventRecording {
    private let store: MCPFailureEventStore

    public init(db: DatabaseConnection) throws {
        self.store = try MCPFailureEventStore(db: db)
    }

    public func record(_ event: MCPFailureEvent) async throws {
        try await store.record(event)
    }
}

public actor MCPFailureEventStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) throws {
        self.db = db
        try Self.ensureSchema(db)
    }

    public static func ensureSchema(_ db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS mcp_failure_events (
                event_id TEXT PRIMARY KEY,
                request_id TEXT NOT NULL,
                agent TEXT NOT NULL,
                client_name TEXT,
                tool_name TEXT,
                boundary TEXT NOT NULL,
                phase TEXT NOT NULL,
                classification TEXT NOT NULL,
                is_retryable INTEGER NOT NULL DEFAULT 0,
                redacted_message TEXT NOT NULL,
                connection_id TEXT,
                runtime_generation INTEGER NOT NULL DEFAULT 0,
                grant_id TEXT,
                focus_id TEXT,
                work_block_id TEXT,
                source_ids_json TEXT NOT NULL DEFAULT '[]',
                duration_ms REAL,
                timestamp REAL NOT NULL
            )
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_mcp_failures_request ON mcp_failure_events(request_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_mcp_failures_tool ON mcp_failure_events(tool_name)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_mcp_failures_timestamp ON mcp_failure_events(timestamp)")
    }

    public func record(_ event: MCPFailureEvent) throws {
        let sourceIDsData = try JSONEncoder().encode(event.sourceIDs)
        let sourceIDsJSON = String(data: sourceIDsData, encoding: .utf8) ?? "[]"
        try db.execute("""
            INSERT INTO mcp_failure_events (
                event_id, request_id, agent, client_name, tool_name, boundary, phase,
                classification, is_retryable, redacted_message, connection_id,
                runtime_generation, grant_id, focus_id, work_block_id, source_ids_json,
                duration_ms, timestamp
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, params: [
            event.eventID,
            event.requestID,
            event.agent,
            event.clientName,
            event.toolName,
            event.boundary.rawValue,
            event.phase.rawValue,
            event.classification.rawValue,
            event.isRetryable ? "1" : "0",
            event.redactedMessage,
            event.connectionID,
            "\(event.runtimeGeneration)",
            event.grantID,
            event.focusID,
            event.workBlockID,
            sourceIDsJSON,
            event.durationMS.map { "\($0)" },
            "\(event.timestamp)",
        ])
    }

    public func recent(limit: Int = 100) throws -> [MCPFailureEvent] {
        let rows = try db.queryAll(
            "SELECT * FROM mcp_failure_events ORDER BY timestamp DESC LIMIT ?",
            params: ["\(limit)"]
        )
        return rows.compactMap(Self.event(from:))
    }

    private static func event(from row: [String: String]) -> MCPFailureEvent? {
        guard let eventID = row["event_id"],
              let requestID = row["request_id"],
              let agent = row["agent"],
              let boundaryRaw = row["boundary"],
              let boundary = MCPFailureBoundary(rawValue: boundaryRaw),
              let phaseRaw = row["phase"],
              let phase = MCPFailurePhase(rawValue: phaseRaw),
              let classificationRaw = row["classification"],
              let classification = MCPFailureClassification(rawValue: classificationRaw),
              let message = row["redacted_message"],
              let generationRaw = row["runtime_generation"],
              let runtimeGeneration = Int(generationRaw),
              let timestampRaw = row["timestamp"],
              let timestamp = Double(timestampRaw) else {
            mcpFailureLogger.warning("Failed to decode MCP failure event row")
            return nil
        }
        let sourceIDs = row["source_ids_json"]
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        return MCPFailureEvent(
            eventID: eventID,
            requestID: requestID,
            agent: agent,
            clientName: row["client_name"]?.nilIfEmpty,
            toolName: row["tool_name"]?.nilIfEmpty,
            boundary: boundary,
            phase: phase,
            classification: classification,
            isRetryable: row["is_retryable"] == "1",
            redactedMessage: message,
            connectionID: row["connection_id"]?.nilIfEmpty,
            runtimeGeneration: runtimeGeneration,
            grantID: row["grant_id"]?.nilIfEmpty,
            focusID: row["focus_id"]?.nilIfEmpty,
            workBlockID: row["work_block_id"]?.nilIfEmpty,
            sourceIDs: sourceIDs,
            durationMS: row["duration_ms"].flatMap(Double.init),
            timestamp: timestamp
        )
    }
}
