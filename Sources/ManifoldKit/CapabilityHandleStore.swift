// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let capabilityLogger = Logger(subsystem: "com.spatialduality.manifold", category: "capabilities")

public actor CapabilityHandleStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) throws {
        self.db = db
        try Self.ensureSchema(db)
    }

    public static func ensureSchema(_ db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS value_handles (
                handle_id TEXT PRIMARY KEY,
                origin TEXT NOT NULL,
                sensitivity TEXT NOT NULL,
                trust_level TEXT NOT NULL,
                allowed_sinks_json TEXT NOT NULL,
                grant_id TEXT,
                lineage_json TEXT NOT NULL,
                created_at REAL NOT NULL
            )
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_value_handles_grant ON value_handles(grant_id)")
    }

    @discardableResult
    public func save(_ handle: ValueHandle) throws -> ValueHandle {
        try db.execute("""
            INSERT INTO value_handles (
                handle_id, origin, sensitivity, trust_level, allowed_sinks_json,
                grant_id, lineage_json, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, params: [
            handle.handleID,
            handle.origin,
            handle.sensitivity,
            handle.trustLevel,
            try Self.jsonString(handle.allowedSinks),
            handle.grantID,
            try Self.jsonString(handle.lineage),
            "\(handle.createdAt)",
        ])
        return handle
    }

    public func handle(id: String) throws -> ValueHandle? {
        let rows = try db.queryAll(
            "SELECT * FROM value_handles WHERE handle_id = ? LIMIT 1",
            params: [id]
        )
        return rows.first.flatMap(Self.handle(from:))
    }

    public func list(limit: Int = 50) throws -> [ValueHandle] {
        let rows = try db.queryAll(
            "SELECT * FROM value_handles ORDER BY created_at DESC LIMIT ?",
            params: ["\(max(1, min(limit, 500)))"]
        )
        return rows.compactMap(Self.handle(from:))
    }

    public func checkFlow(
        handleID: String,
        sink: String,
        untrustedInput: Bool = false,
        stateChangingAction: Bool = false
    ) throws -> CapabilityFlowResult {
        guard let handle = try handle(id: handleID) else {
            return CapabilityFlowResult(
                allowed: false,
                reason: "No value handle found for \(handleID).",
                handleID: handleID,
                sink: sink
            )
        }

        return checkFlow(
            handle: handle,
            sink: sink,
            untrustedInput: untrustedInput,
            stateChangingAction: stateChangingAction
        )
    }

    public func checkFlow(
        handle: ValueHandle,
        sink: String,
        untrustedInput: Bool = false,
        stateChangingAction: Bool = false
    ) -> CapabilityFlowResult {
        let sinkAllowed = handle.allowedSinks.contains("*") || handle.allowedSinks.contains(sink)
        guard sinkAllowed else {
            return CapabilityFlowResult(
                allowed: false,
                reason: "Sink \(sink) is not authorized by handle \(handle.handleID).",
                handleID: handle.handleID,
                sink: sink
            )
        }

        let sensitive = Self.isSensitive(handle.sensitivity)
        let untrusted = untrustedInput || handle.trustLevel == "untrusted"
        if sensitive && untrusted && stateChangingAction {
            return CapabilityFlowResult(
                allowed: false,
                reason: "Rule of Two blocked combining untrusted input, sensitive data, and a state-changing sink.",
                handleID: handle.handleID,
                sink: sink,
                ruleOfTwoTriggered: true
            )
        }

        return CapabilityFlowResult(
            allowed: true,
            reason: "Capability flow allowed.",
            handleID: handle.handleID,
            sink: sink
        )
    }

    private static func handle(from row: [String: String]) -> ValueHandle? {
        guard let handleID = row["handle_id"],
              let origin = row["origin"],
              let sensitivity = row["sensitivity"],
              let trustLevel = row["trust_level"],
              let createdRaw = row["created_at"],
              let createdAt = Double(createdRaw) else {
            capabilityLogger.warning("Failed to decode value handle row")
            return nil
        }
        return ValueHandle(
            handleID: handleID,
            origin: origin,
            sensitivity: sensitivity,
            trustLevel: trustLevel,
            allowedSinks: decode([String].self, from: row["allowed_sinks_json"]) ?? [],
            grantID: row["grant_id"]?.nilIfEmpty,
            lineage: decode([LineageRef].self, from: row["lineage_json"]) ?? [],
            createdAt: createdAt
        )
    }

    private static func isSensitive(_ sensitivity: String) -> Bool {
        ["secret", "high", "restricted", "sensitive", "private"].contains(sensitivity.lowercased())
    }

    private static func jsonString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "null"
    }

    private static func decode<T: Decodable>(_ type: T.Type, from raw: String?) -> T? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
