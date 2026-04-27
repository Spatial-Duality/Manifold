// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import os

private let ledgerLogger = Logger(subsystem: "com.spatialduality.manifold", category: "ledger")

public actor LedgerStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) throws {
        self.db = db
        try Self.ensureSchema(db)
    }

    public static func ensureSchema(_ db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS ledger_entries (
                entry_id TEXT PRIMARY KEY,
                sequence INTEGER NOT NULL UNIQUE,
                timestamp REAL NOT NULL,
                entry_type TEXT NOT NULL,
                subject_table TEXT,
                subject_id TEXT,
                previous_hash TEXT,
                payload_hash TEXT NOT NULL,
                entry_hash TEXT NOT NULL,
                metadata_json TEXT
            )
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_ledger_entry_type ON ledger_entries(entry_type)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_ledger_subject ON ledger_entries(subject_table, subject_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_ledger_timestamp ON ledger_entries(timestamp)")
    }

    @discardableResult
    public func append(
        entryType: LedgerEntryType,
        subjectTable: String? = nil,
        subjectID: String? = nil,
        payload: String,
        metadata: [String: String] = [:]
    ) throws -> LedgerEntry {
        let nextSequence = (Int(try db.queryScalar("SELECT COALESCE(MAX(sequence), 0) FROM ledger_entries") ?? "0") ?? 0) + 1
        let previousHash = try db.queryScalar(
            "SELECT entry_hash FROM ledger_entries ORDER BY sequence DESC LIMIT 1"
        )?.nilIfEmpty
        let timestamp = Date().timeIntervalSince1970
        let timestampString = Self.stableTimestamp(timestamp)
        let payloadHash = Self.sha256(payload)
        let metadataJSON = try Self.jsonString(metadata)
        let entryHash = Self.entryHash(
            sequence: nextSequence,
            timestamp: timestampString,
            entryType: entryType.rawValue,
            subjectTable: subjectTable,
            subjectID: subjectID,
            previousHash: previousHash,
            payloadHash: payloadHash,
            metadataJSON: metadataJSON
        )
        let entry = LedgerEntry(
            entryID: "ledger-\(UUID().uuidString.prefix(12).lowercased())",
            sequence: nextSequence,
            timestamp: timestamp,
            entryType: entryType.rawValue,
            subjectTable: subjectTable,
            subjectID: subjectID,
            previousHash: previousHash,
            payloadHash: payloadHash,
            entryHash: entryHash,
            metadataJSON: metadataJSON
        )
        try db.execute("""
            INSERT INTO ledger_entries (
                entry_id, sequence, timestamp, entry_type, subject_table, subject_id,
                previous_hash, payload_hash, entry_hash, metadata_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, params: [
            entry.entryID,
            "\(entry.sequence)",
            timestampString,
            entry.entryType,
            entry.subjectTable,
            entry.subjectID,
            entry.previousHash,
            entry.payloadHash,
            entry.entryHash,
            entry.metadataJSON,
        ])
        return entry
    }

    public func entry(id: String) throws -> LedgerEntry? {
        let rows = try db.queryAll(
            "SELECT * FROM ledger_entries WHERE entry_id = ? LIMIT 1",
            params: [id]
        )
        return rows.first.flatMap(Self.entry(from:))
    }

    public func entries(subjectTable: String, subjectID: String, limit: Int = 20) throws -> [LedgerEntry] {
        let rows = try db.queryAll("""
            SELECT * FROM ledger_entries
            WHERE subject_table = ? AND subject_id = ?
            ORDER BY sequence DESC
            LIMIT ?
        """, params: [subjectTable, subjectID, "\(limit)"])
        return rows.compactMap(Self.entry(from:))
    }

    public func recent(limit: Int = 20) throws -> [LedgerEntry] {
        let rows = try db.queryAll(
            "SELECT * FROM ledger_entries ORDER BY sequence DESC LIMIT ?",
            params: ["\(limit)"]
        )
        return rows.compactMap(Self.entry(from:))
    }

    public func verifyChain() throws -> LedgerVerificationResult {
        let entries = try db.queryAll("""
            SELECT *, printf('%.6f', timestamp) AS timestamp_material
            FROM ledger_entries
            ORDER BY sequence ASC
        """)
            .compactMap { row -> (entry: LedgerEntry, timestampMaterial: String)? in
                guard let entry = Self.entry(from: row) else { return nil }
                return (entry, row["timestamp_material"] ?? Self.stableTimestamp(entry.timestamp))
            }
        var previousHash: String?
        var legacyEntryCount = 0
        for (entry, timestampMaterial) in entries {
            if entry.previousHash != previousHash {
                return LedgerVerificationResult(
                    verified: false,
                    checkedEntries: entries.count,
                    firstBrokenEntryID: entry.entryID,
                    message: "Ledger chain is broken before entry \(entry.entryID)."
                )
            }
            let expectedHash = Self.entryHash(
                sequence: entry.sequence,
                timestamp: timestampMaterial,
                entryType: entry.entryType,
                subjectTable: entry.subjectTable,
                subjectID: entry.subjectID,
                previousHash: entry.previousHash,
                payloadHash: entry.payloadHash,
                metadataJSON: entry.metadataJSON
            )
            if expectedHash != entry.entryHash {
                let legacyHash = Self.legacyEntryHash(
                    sequence: entry.sequence,
                    entryType: entry.entryType,
                    subjectTable: entry.subjectTable,
                    subjectID: entry.subjectID,
                    previousHash: entry.previousHash,
                    payloadHash: entry.payloadHash,
                    metadataJSON: entry.metadataJSON
                )
                if legacyHash == entry.entryHash {
                    legacyEntryCount += 1
                } else {
                    return LedgerVerificationResult(
                        verified: false,
                        checkedEntries: entries.count,
                        firstBrokenEntryID: entry.entryID,
                        message: "Ledger entry \(entry.entryID) hash does not match its stored hash material."
                    )
                }
            }
            previousHash = entry.entryHash
        }
        let message: String
        if entries.isEmpty {
            message = "Ledger is empty."
        } else if legacyEntryCount > 0 {
            message = "Ledger chain verified; \(legacyEntryCount) legacy entr\(legacyEntryCount == 1 ? "y is" : "ies are") not timestamp-covered."
        } else {
            message = "Ledger chain verified."
        }
        return LedgerVerificationResult(
            verified: true,
            checkedEntries: entries.count,
            firstBrokenEntryID: nil,
            message: message
        )
    }

    private static func entry(from row: [String: String]) -> LedgerEntry? {
        guard let entryID = row["entry_id"],
              let sequenceRaw = row["sequence"],
              let sequence = Int(sequenceRaw),
              let timestampRaw = row["timestamp"],
              let timestamp = Double(timestampRaw),
              let entryType = row["entry_type"],
              let payloadHash = row["payload_hash"],
              let entryHash = row["entry_hash"] else {
            ledgerLogger.warning("Failed to decode ledger entry row")
            return nil
        }
        return LedgerEntry(
            entryID: entryID,
            sequence: sequence,
            timestamp: timestamp,
            entryType: entryType,
            subjectTable: row["subject_table"]?.nilIfEmpty,
            subjectID: row["subject_id"]?.nilIfEmpty,
            previousHash: row["previous_hash"]?.nilIfEmpty,
            payloadHash: payloadHash,
            entryHash: entryHash,
            metadataJSON: row["metadata_json"]?.nilIfEmpty
        )
    }

    static func sha256(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func entryHash(
        sequence: Int,
        timestamp: String,
        entryType: String,
        subjectTable: String?,
        subjectID: String?,
        previousHash: String?,
        payloadHash: String,
        metadataJSON: String?
    ) -> String {
        sha256([
            "\(sequence)",
            timestamp,
            entryType,
            subjectTable ?? "",
            subjectID ?? "",
            previousHash ?? "",
            payloadHash,
            metadataJSON ?? "",
        ].joined(separator: "|"))
    }

    private static func legacyEntryHash(
        sequence: Int,
        entryType: String,
        subjectTable: String?,
        subjectID: String?,
        previousHash: String?,
        payloadHash: String,
        metadataJSON: String?
    ) -> String {
        sha256([
            "\(sequence)",
            entryType,
            subjectTable ?? "",
            subjectID ?? "",
            previousHash ?? "",
            payloadHash,
            metadataJSON ?? "",
        ].joined(separator: "|"))
    }

    private static func stableTimestamp(_ timestamp: Double) -> String {
        String(format: "%.6f", timestamp)
    }

    static func jsonString(_ dictionary: [String: String]) throws -> String? {
        guard !dictionary.isEmpty else { return nil }
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)
    }
}
