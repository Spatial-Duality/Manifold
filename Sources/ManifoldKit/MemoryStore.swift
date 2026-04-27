// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let memoryLogger = Logger(subsystem: "com.spatialduality.manifold", category: "memory")

public actor MemoryStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) throws {
        self.db = db
        try Self.ensureSchema(db)
    }

    public static func ensureSchema(_ db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS memory_items (
                memory_id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                status TEXT NOT NULL,
                origin TEXT NOT NULL DEFAULT 'agent_derived',
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                contributing_source_ids_json TEXT NOT NULL,
                contributing_grant_ids_json TEXT NOT NULL,
                contributing_exposure_ids_json TEXT NOT NULL,
                contributing_content_hashes_json TEXT NOT NULL,
                created_session_id TEXT,
                expires_at REAL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
        """)
        try addColumnIfMissing(db, table: "memory_items", column: "origin", sql: "ALTER TABLE memory_items ADD COLUMN origin TEXT NOT NULL DEFAULT 'agent_derived'")
        try addColumnIfMissing(db, table: "memory_items", column: "expires_at", sql: "ALTER TABLE memory_items ADD COLUMN expires_at REAL")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_memory_kind_status ON memory_items(kind, status)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_memory_updated ON memory_items(updated_at)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_memory_origin_status_expires ON memory_items(origin, status, expires_at)")
        try db.execute("""
            CREATE TABLE IF NOT EXISTS memory_settings (
                settings_id TEXT PRIMARY KEY,
                amnesiac_mode INTEGER NOT NULL DEFAULT 0,
                derived_retention_days INTEGER NOT NULL DEFAULT 90,
                updated_at TEXT NOT NULL
            )
        """)
    }

    @discardableResult
    public func save(
        kind: MemoryKind,
        title: String,
        body: String,
        origin: MemoryOrigin = .agentDerived,
        contributingSourceIDs: [String] = [],
        contributingGrantIDs: [String] = [],
        contributingExposureIDs: [String] = [],
        contributingContentHashes: [String] = [],
        createdSessionID: String? = nil,
        expiresAt: Double? = nil
    ) throws -> MemoryItem {
        let now = Date().timeIntervalSince1970
        let item = MemoryItem(
            kind: kind,
            origin: origin,
            title: title,
            body: body,
            contributingSourceIDs: contributingSourceIDs.sorted(),
            contributingGrantIDs: contributingGrantIDs.sorted(),
            contributingExposureIDs: contributingExposureIDs.sorted(),
            contributingContentHashes: contributingContentHashes.sorted(),
            createdSessionID: createdSessionID,
            expiresAt: expiresAt,
            createdAt: now,
            updatedAt: now
        )
        try db.execute("""
            INSERT INTO memory_items (
                memory_id, kind, status, origin, title, body,
                contributing_source_ids_json, contributing_grant_ids_json,
                contributing_exposure_ids_json, contributing_content_hashes_json,
                created_session_id, expires_at, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, params: [
            item.memoryID,
            item.kind,
            item.status,
            item.origin,
            item.title,
            item.body,
            try StoreJSON.encode(item.contributingSourceIDs),
            try StoreJSON.encode(item.contributingGrantIDs),
            try StoreJSON.encode(item.contributingExposureIDs),
            try StoreJSON.encode(item.contributingContentHashes),
            item.createdSessionID,
            item.expiresAt.map { "\($0)" },
            "\(item.createdAt)",
            "\(item.updatedAt)",
        ])
        return item
    }

    public func settings() throws -> MemorySettings {
        let rows = try db.queryAll(
            "SELECT * FROM memory_settings WHERE settings_id = ? LIMIT 1",
            params: ["memory-settings"]
        )
        if let row = rows.first, let settings = Self.settings(from: row) {
            return settings
        }
        let defaults = MemorySettings()
        try upsertSettings(defaults)
        return defaults
    }

    public func upsertSettings(_ settings: MemorySettings) throws {
        let normalized = MemorySettings(
            settingsID: settings.settingsID,
            amnesiacMode: settings.amnesiacMode,
            derivedRetentionDays: max(1, min(settings.derivedRetentionDays, 365)),
            updatedAt: ISO8601DateFormatter.shared.string(from: Date())
        )
        try db.execute("""
            INSERT INTO memory_settings (
                settings_id, amnesiac_mode, derived_retention_days, updated_at
            ) VALUES (?, ?, ?, ?)
            ON CONFLICT(settings_id) DO UPDATE SET
                amnesiac_mode = excluded.amnesiac_mode,
                derived_retention_days = excluded.derived_retention_days,
                updated_at = excluded.updated_at
        """, params: [
            normalized.settingsID,
            normalized.amnesiacMode ? "1" : "0",
            "\(normalized.derivedRetentionDays)",
            normalized.updatedAt,
        ])
    }

    public func memory(id: String) throws -> MemoryItem? {
        let rows = try db.queryAll(
            "SELECT * FROM memory_items WHERE memory_id = ? LIMIT 1",
            params: [id]
        )
        return rows.first.flatMap(Self.item(from:))
    }

    @discardableResult
    public func expireDerivedMemory(now: Double = Date().timeIntervalSince1970) throws -> Int {
        let candidates = try list(limit: 10_000, includeDeleted: false)
            .filter { item in
                item.status == MemoryStatus.active.rawValue
                    && item.origin == MemoryOrigin.agentDerived.rawValue
                    && item.expiresAt.map { $0 <= now } == true
            }
        for item in candidates {
            try updateStatus(memoryID: item.memoryID, status: .expiredByRetention)
        }
        return candidates.count
    }

    public func recall(query: String? = nil, allowedSourceIDs: Set<String>? = nil, limit: Int = 10) throws -> [MemoryItem] {
        let normalizedLimit = max(1, min(limit, 100))
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQuery = !(trimmedQuery?.isEmpty ?? true)

        // The lineage scope filter pushes the strict-subset check into SQL via
        // `json_each`. A memory passes when its contributing_source_ids_json is
        // empty (no lineage) OR every element in it is in allowedSourceIDs.
        // When allowedSourceIDs is nil we emit no scope predicate at all.
        var scopeClause = ""
        var scopeParams: [String?] = []
        if let allowedSourceIDs {
            if allowedSourceIDs.isEmpty {
                scopeClause = " AND contributing_source_ids_json = '[]'"
            } else {
                let placeholders = allowedSourceIDs.map { _ in "?" }.joined(separator: ", ")
                scopeClause = """
                 AND (contributing_source_ids_json = '[]' OR NOT EXISTS (
                    SELECT 1 FROM json_each(contributing_source_ids_json)
                    WHERE value NOT IN (\(placeholders))
                ))
                """
                scopeParams = allowedSourceIDs.sorted().map { $0 as String? }
            }
        }

        let baseSelect = "SELECT * FROM memory_items WHERE status = ?"
        let queryClause = hasQuery ? " AND (title LIKE ? OR body LIKE ?)" : ""
        let suffix = " ORDER BY updated_at DESC LIMIT ?"

        var params: [String?] = [MemoryStatus.active.rawValue]
        if hasQuery, let trimmedQuery {
            let pattern = "%\(trimmedQuery)%"
            params.append(pattern)
            params.append(pattern)
        }
        params.append(contentsOf: scopeParams)
        params.append("\(normalizedLimit)")

        let rows = try db.queryAll(baseSelect + queryClause + scopeClause + suffix, params: params)
        return rows.compactMap(Self.item(from:))
    }

    public func list(limit: Int = 50, includeDeleted: Bool = false) throws -> [MemoryItem] {
        let rows: [[String: String]]
        if includeDeleted {
            rows = try db.queryAll(
                "SELECT * FROM memory_items ORDER BY updated_at DESC LIMIT ?",
                params: ["\(limit)"]
            )
        } else {
            rows = try db.queryAll("""
                SELECT * FROM memory_items
                WHERE status != ?
                ORDER BY updated_at DESC
                LIMIT ?
            """, params: [MemoryStatus.deletedByUser.rawValue, "\(limit)"])
        }
        return rows.compactMap(Self.item(from:))
    }

    public func sourceSummaries() throws -> [MemorySourceSummary] {
        let items = try list(limit: 10_000, includeDeleted: true)
        var counts: [String: (active: Int, tombstoned: Int, deleted: Int)] = [:]
        for item in items {
            for sourceID in item.contributingSourceIDs {
                var current = counts[sourceID, default: (0, 0, 0)]
                switch MemoryStatus(rawValue: item.status) {
                case .active:
                    current.active += 1
                case .tombstonedByRevocation, .hiddenByScope, .expiredByRetention:
                    current.tombstoned += 1
                case .deletedByUser:
                    current.deleted += 1
                case .none:
                    break
                }
                counts[sourceID] = current
            }
        }
        return counts.keys.sorted().map { sourceID in
            let count = counts[sourceID] ?? (0, 0, 0)
            return MemorySourceSummary(
                sourceID: sourceID,
                activeCount: count.active,
                tombstonedCount: count.tombstoned,
                deletedCount: count.deleted
            )
        }
    }

    @discardableResult
    public func forget(memoryID: String) throws -> Bool {
        guard try memory(id: memoryID) != nil else { return false }
        try updateStatus(memoryID: memoryID, status: .deletedByUser)
        return true
    }

    @discardableResult
    public func tombstoneMemories(contributingSourceID sourceID: String) throws -> Int {
        let candidates = try list(limit: 10_000, includeDeleted: false)
            .filter { $0.status == MemoryStatus.active.rawValue && $0.contributingSourceIDs.contains(sourceID) }
        for item in candidates {
            try updateStatus(memoryID: item.memoryID, status: .tombstonedByRevocation)
        }
        return candidates.count
    }

    public func updateStatus(memoryID: String, status: MemoryStatus) throws {
        try db.execute(
            "UPDATE memory_items SET status = ?, updated_at = ? WHERE memory_id = ?",
            params: [status.rawValue, "\(Date().timeIntervalSince1970)", memoryID]
        )
    }

    private static func settings(from row: [String: String]) -> MemorySettings? {
        guard let settingsID = row["settings_id"],
              let retentionRaw = row["derived_retention_days"],
              let retentionDays = Int(retentionRaw),
              let updatedAt = row["updated_at"] else {
            memoryLogger.warning("Failed to decode memory settings row")
            return nil
        }
        return MemorySettings(
            settingsID: settingsID,
            amnesiacMode: row["amnesiac_mode"] == "1",
            derivedRetentionDays: retentionDays,
            updatedAt: updatedAt
        )
    }

    private static func item(from row: [String: String]) -> MemoryItem? {
        guard let memoryID = row["memory_id"],
              let kindRaw = row["kind"],
              let kind = MemoryKind(rawValue: kindRaw),
              let statusRaw = row["status"],
              let status = MemoryStatus(rawValue: statusRaw),
              let title = row["title"],
              let body = row["body"],
              let createdRaw = row["created_at"],
              let createdAt = Double(createdRaw),
              let updatedRaw = row["updated_at"],
              let updatedAt = Double(updatedRaw) else {
            memoryLogger.warning("Failed to decode memory row")
            return nil
        }
        return MemoryItem(
            memoryID: memoryID,
            kind: kind,
            status: status,
            origin: MemoryOrigin(rawValue: row["origin"] ?? "") ?? .agentDerived,
            title: title,
            body: body,
            contributingSourceIDs: StoreJSON.decodeArray(row["contributing_source_ids_json"]),
            contributingGrantIDs: StoreJSON.decodeArray(row["contributing_grant_ids_json"]),
            contributingExposureIDs: StoreJSON.decodeArray(row["contributing_exposure_ids_json"]),
            contributingContentHashes: StoreJSON.decodeArray(row["contributing_content_hashes_json"]),
            createdSessionID: row["created_session_id"]?.nilIfEmpty,
            expiresAt: row["expires_at"].flatMap(Double.init),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

}
