// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let fabricationLogger = Logger(subsystem: "com.spatialduality.manifold", category: "fabrication")

public actor FabricationFindingStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) throws {
        self.db = db
        try Self.ensureSchema(db)
    }

    public static func ensureSchema(_ db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS fabrication_findings (
                finding_id TEXT PRIMARY KEY,
                session_id TEXT,
                claim_text TEXT NOT NULL,
                status TEXT NOT NULL,
                evidence_json TEXT NOT NULL,
                created_at REAL NOT NULL
            )
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_fabrication_session ON fabrication_findings(session_id)")
    }

    @discardableResult
    public func save(
        sessionID: String?,
        claimText: String,
        status: String,
        evidence: [String: String]
    ) throws -> FabricationFinding {
        let finding = FabricationFinding(
            sessionID: sessionID,
            claimText: claimText,
            status: status,
            evidenceJSON: try Self.jsonString(evidence)
        )
        try db.execute("""
            INSERT INTO fabrication_findings (
                finding_id, session_id, claim_text, status, evidence_json, created_at
            ) VALUES (?, ?, ?, ?, ?, ?)
        """, params: [
            finding.findingID,
            finding.sessionID,
            finding.claimText,
            finding.status,
            finding.evidenceJSON,
            "\(finding.createdAt)",
        ])
        return finding
    }

    public func recent(limit: Int = 50) throws -> [FabricationFinding] {
        let rows = try db.queryAll(
            "SELECT * FROM fabrication_findings ORDER BY created_at DESC LIMIT ?",
            params: ["\(max(1, min(limit, 500)))"]
        )
        return rows.compactMap(Self.finding(from:))
    }

    private static func finding(from row: [String: String]) -> FabricationFinding? {
        guard let findingID = row["finding_id"],
              let claimText = row["claim_text"],
              let status = row["status"],
              let evidenceJSON = row["evidence_json"],
              let createdRaw = row["created_at"],
              let createdAt = Double(createdRaw) else {
            fabricationLogger.warning("Failed to decode fabrication finding row")
            return nil
        }
        return FabricationFinding(
            findingID: findingID,
            sessionID: row["session_id"]?.nilIfEmpty,
            claimText: claimText,
            status: status,
            evidenceJSON: evidenceJSON,
            createdAt: createdAt
        )
    }

    private static func jsonString(_ dictionary: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
