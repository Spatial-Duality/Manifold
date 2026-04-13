// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CryptoKit
import SQLite3

/// Content-addressed blob store. Files stored by SHA-256 hash with 2-char prefix sharding.
/// Blobs are immutable once written. Deletion only through explicit garbage collection.
public actor ContentStore {
    private let rootURL: URL
    private let blobsURL: URL
    private let db: DatabaseConnection

    /// Initialize with a shared DatabaseConnection (avoids duplicate DB handles).
    public init(rootURL: URL, db: DatabaseConnection) throws {
        self.rootURL = rootURL
        self.blobsURL = rootURL.appendingPathComponent("blobs")
        try FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)
        self.db = db
        try Self.ensureTables(db: db)
    }

    /// Legacy: opens its own DB connection (kept for backward compatibility in tests).
    public init(rootURL: URL) throws {
        self.rootURL = rootURL
        self.blobsURL = rootURL.appendingPathComponent("blobs")
        try FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)

        let dbURL = rootURL.appendingPathComponent("manifold.db")
        self.db = try DatabaseConnection(url: dbURL)
        try Self.ensureTables(db: db)

        // Set schema version if not present
        let version = try db.queryScalar("SELECT value FROM manifold_meta WHERE key = 'schema_version'")
        if version == nil {
            try db.execute("INSERT INTO manifold_meta (key, value) VALUES ('schema_version', '1')")
            try db.execute("INSERT INTO manifold_meta (key, value) VALUES ('created_at', '\(ISO8601DateFormatter.shared.string(from: Date()))')")
        }
    }

    /// Ingest file content into the store. Returns the SHA-256 hash.
    /// If the blob already exists (same hash), no disk write occurs.
    public func ingest(data: Data) throws -> String {
        let hash = SHA256.hash(data: data).hexString
        let blobURL = blobURL(for: hash)

        if FileManager.default.fileExists(atPath: blobURL.path) {
            return hash
        }

        // Create shard directory (first 2 chars of hash)
        let shardURL = blobsURL.appendingPathComponent(String(hash.prefix(2)))
        try FileManager.default.createDirectory(at: shardURL, withIntermediateDirectories: true)

        // Write blob atomically
        try data.write(to: blobURL, options: .atomic)

        // Record metadata
        try db.execute("""
            INSERT OR IGNORE INTO content_meta (hash, size_bytes, ingested_at, ref_count)
            VALUES (?, ?, ?, 0)
        """, params: [hash, "\(data.count)", ISO8601DateFormatter.shared.string(from: Date())])

        return hash
    }

    /// Ingest a file from disk by URL. Returns the SHA-256 hash.
    /// Uses streaming SHA-256 (64KB chunks) to avoid loading the entire file into memory.
    /// For a 50MB file, peak memory is 64KB instead of 50MB.
    public func ingest(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        var totalSize = 0
        while true {
            let chunk = handle.readData(ofLength: 65536)
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            totalSize += chunk.count
        }
        let hash = hasher.finalize().hexString
        let blobURL = blobURL(for: hash)

        if FileManager.default.fileExists(atPath: blobURL.path) {
            return hash
        }

        // Create shard directory
        let shardURL = blobsURL.appendingPathComponent(String(hash.prefix(2)))
        try FileManager.default.createDirectory(at: shardURL, withIntermediateDirectories: true)

        // Copy file to blob store instead of writing Data
        try FileManager.default.copyItem(at: fileURL, to: blobURL)

        // Record metadata
        try db.execute("""
            INSERT OR IGNORE INTO content_meta (hash, size_bytes, ingested_at, ref_count)
            VALUES (?, ?, ?, 0)
        """, params: [hash, "\(totalSize)", ISO8601DateFormatter.shared.string(from: Date())])

        return hash
    }

    /// Retrieve blob data by hash. Returns nil if not found.
    public func retrieve(hash: String) throws -> Data? {
        let url = blobURL(for: hash)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// Check if a blob exists in the store.
    public func exists(hash: String) -> Bool {
        FileManager.default.fileExists(atPath: blobURL(for: hash).path)
    }

    /// Increment ref_count for a blob hash (called when a snapshot references it).
    public func incrementRef(hash: String) throws {
        try db.execute("UPDATE content_meta SET ref_count = ref_count + 1 WHERE hash = ?", params: [hash])
    }

    /// Decrement ref_count for a blob hash (called when a snapshot is pruned).
    public func decrementRef(hash: String) throws {
        try db.execute("UPDATE content_meta SET ref_count = ref_count - 1 WHERE hash = ?", params: [hash])
    }

    /// Remove blobs with ref_count <= 0. Returns the number of blobs removed.
    /// SAFETY: Do not call while any access run is active. Active runs may be
    /// ingesting blobs that haven't had ref_count incremented yet.
    @discardableResult
    public func garbageCollect() throws -> Int {
        let orphans = try db.queryAll("SELECT hash FROM content_meta WHERE ref_count <= 0")
        var removed = 0
        for row in orphans {
            guard let hash = row["hash"] else { continue }
            let url = blobURL(for: hash)
            do {
                try FileManager.default.removeItem(at: url)
                try db.execute("DELETE FROM content_meta WHERE hash = ?", params: [hash])
                removed += 1
            } catch {
                // Log but don't fail the entire GC run
                continue
            }
        }
        return removed
    }

    /// Total size of all blobs in bytes.
    public func totalSize() throws -> Int64 {
        let result = try db.queryScalar("SELECT COALESCE(SUM(size_bytes), 0) FROM content_meta")
        return Int64(result ?? "0") ?? 0
    }

    /// Number of blobs in the store.
    public func blobCount() throws -> Int {
        let result = try db.queryScalar("SELECT COUNT(*) FROM content_meta")
        return Int(result ?? "0") ?? 0
    }

    // MARK: - Table Setup

    private static func ensureTables(db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS manifold_meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
        """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS content_meta (
                hash TEXT PRIMARY KEY,
                size_bytes INTEGER NOT NULL,
                ingested_at TEXT NOT NULL,
                ref_count INTEGER DEFAULT 0
            )
        """)
    }

    // MARK: - Private

    private func blobURL(for hash: String) -> URL {
        let shard = String(hash.prefix(2))
        return blobsURL.appendingPathComponent(shard).appendingPathComponent(hash)
    }
}

// MARK: - SHA256 Hex Extension

extension SHA256Digest {
    /// Pre-allocated hex string — avoids 32 intermediate String allocations.
    var hexString: String {
        let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)
        var chars = [UInt8](repeating: 0, count: 64) // SHA-256 = 32 bytes = 64 hex chars
        for (i, byte) in enumerated() {
            chars[i &* 2] = hexDigits[Int(byte >> 4)]
            chars[i &* 2 &+ 1] = hexDigits[Int(byte & 0x0F)]
        }
        guard let string = String(bytes: chars, encoding: .ascii) else {
            preconditionFailure("Failed to convert SHA-256 digest into ASCII hex")
        }
        return string
    }
}
