// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct FinderTaggedItemRecord: Sendable, Hashable, Codable {
    public let sourceID: String
    public let originalPath: String
    public let fileIdentity: String?
    public let isDirectory: Bool
    public let tagName: String
    public let taggedAt: String

    public init(
        sourceID: String,
        originalPath: String,
        fileIdentity: String?,
        isDirectory: Bool,
        tagName: String,
        taggedAt: String = ISO8601DateFormatter.shared.string(from: Date())
    ) {
        self.sourceID = sourceID
        self.originalPath = originalPath
        self.fileIdentity = fileIdentity
        self.isDirectory = isDirectory
        self.tagName = tagName
        self.taggedAt = taggedAt
    }

    init?(row: [String: String]) {
        guard let sourceID = row["source_id"],
              let originalPath = row["original_path"],
              let tagName = row["tag_name"],
              let taggedAt = row["tagged_at"] else {
            return nil
        }
        self.sourceID = sourceID
        self.originalPath = originalPath
        self.fileIdentity = row["file_identity"]
        self.isDirectory = row["is_directory"] == "1"
        self.tagName = tagName
        self.taggedAt = taggedAt
    }
}

public actor FinderTagLedgerStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) throws {
        self.db = db
        try Self.ensureSchema(db)
    }

    public static func ensureSchema(_ db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS finder_tagged_items (
                source_id TEXT NOT NULL,
                original_path TEXT NOT NULL,
                file_identity TEXT,
                is_directory INTEGER NOT NULL,
                tag_name TEXT NOT NULL,
                tagged_at TEXT NOT NULL,
                PRIMARY KEY(source_id, original_path, tag_name)
            )
        """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_finder_tagged_items_source
            ON finder_tagged_items(source_id, tag_name)
        """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_finder_tagged_items_identity
            ON finder_tagged_items(file_identity, tag_name)
        """)
    }

    public func record(_ records: [FinderTaggedItemRecord]) throws {
        guard !records.isEmpty else { return }
        try db.transaction {
            for record in records {
                try db.execute(
                    """
                    INSERT OR REPLACE INTO finder_tagged_items (
                        source_id, original_path, file_identity, is_directory, tag_name, tagged_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    params: [
                        record.sourceID,
                        record.originalPath,
                        record.fileIdentity,
                        record.isDirectory ? "1" : "0",
                        record.tagName,
                        record.taggedAt,
                    ]
                )
            }
        }
    }

    public func records(sourceID: String) throws -> [FinderTaggedItemRecord] {
        let rows = try db.queryAll(
            """
            SELECT source_id, original_path, file_identity, is_directory, tag_name, tagged_at
            FROM finder_tagged_items
            WHERE source_id = ?
            ORDER BY original_path ASC
            """,
            params: [sourceID]
        )
        return rows.compactMap(FinderTaggedItemRecord.init(row:))
    }

    public func sourceHasTaggedRoot(sourceID: String, rootPath: String) throws -> Bool {
        let standardizedPath = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        let count = try db.queryScalar(
            """
            SELECT COUNT(*) FROM finder_tagged_items
            WHERE source_id = ? AND original_path = ? AND is_directory = 1
            """,
            params: [sourceID, standardizedPath]
        )
        return (Int(count ?? "0") ?? 0) > 0
    }

    public func removeRecords(sourceID: String) throws {
        try db.execute("DELETE FROM finder_tagged_items WHERE source_id = ?", params: [sourceID])
    }

    public func hasOtherOwner(
        fileIdentity: String?,
        path: String,
        tagName: String,
        excluding sourceID: String
    ) throws -> Bool {
        if let fileIdentity, !fileIdentity.isEmpty {
            let count = try db.queryScalar(
                """
                SELECT COUNT(*) FROM finder_tagged_items
                WHERE file_identity = ? AND tag_name = ? AND source_id != ?
                """,
                params: [fileIdentity, tagName, sourceID]
            )
            if (Int(count ?? "0") ?? 0) > 0 { return true }
        }
        let pathCount = try db.queryScalar(
            """
            SELECT COUNT(*) FROM finder_tagged_items
            WHERE original_path = ? AND tag_name = ? AND source_id != ?
            """,
            params: [path, tagName, sourceID]
        )
        return (Int(pathCount ?? "0") ?? 0) > 0
    }
}
