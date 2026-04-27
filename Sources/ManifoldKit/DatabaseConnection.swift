// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SQLite3
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "database")

/// Minimal SQLite wrapper.
///
/// ## Concurrency model
///
/// Multiple actors in the runtime (LedgerStore, MemoryStore,
/// CapabilityHandleStore, KnowledgeGraphStore, etc.) share a single
/// `DatabaseConnection` per `ManifoldRuntime`. Each actor's isolation
/// serializes calls *within* that actor, but actors do not serialize
/// across each other. Concurrent calls from different actors can land
/// on the same connection at the same time.
///
/// The `@unchecked Sendable` claim is justified by **`SQLITE_OPEN_FULLMUTEX`**
/// in `init` (the SERIALIZED threading mode in SQLite parlance): the C
/// library puts a mutex around the connection so concurrent calls from
/// any thread are safe. See https://sqlite.org/threadsafe.html.
///
/// What this rules out:
/// - **Adding mutable Swift state** (caches, buffers) to this class
///   without an explicit lock. Swift `Dictionary`/`Array` mutation is
///   not protected by SQLite's mutex.
/// - Using a different open mode (`SQLITE_OPEN_NOMUTEX`) without
///   reworking the surrounding actors.
///
/// All public operations are synchronous so actors can call them inside
/// their isolated bodies without `await`.
public final class DatabaseConnection: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let url: URL

    /// Creates a SQLite connection and applies the runtime PRAGMA defaults Manifold expects.
    public init(url: URL) throws {
        self.url = url
        try LocalFileProtection.ensureDirectory(at: url.deletingLastPathComponent())
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard status == SQLITE_OK else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw ManifoldError.database("Failed to open database: \(msg)")
        }

        // WAL mode for crash resilience and concurrent reads
        try execute("PRAGMA journal_mode=WAL")
        // NORMAL sync in WAL mode: safe on process crash, last txn may be lost on power loss
        // sqlite.org: "With synchronous=NORMAL in WAL mode, data is safe if the OS crashes"
        try execute("PRAGMA synchronous=NORMAL")
        // 8MB page cache (default 2MB is small for heavy query workloads)
        try execute("PRAGMA cache_size=-8000")
        // Foreign keys
        try execute("PRAGMA foreign_keys=ON")
        // Run SQLite's query planner optimizer on open
        try execute("PRAGMA optimize")
        try secureDatabaseFiles()
    }

    deinit {
        sqlite3_close(handle)
    }

    /// Executes a SQL statement with optional string parameters.
    /// Pass `nil` values for SQL `NULL`.
    public func execute(_ sql: String, params: [String?] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ManifoldError.database(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        bindParams(stmt, params)

        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw ManifoldError.database(errorMessage)
        }
    }

    /// Returns the first column of the first row, or `nil` when the query has no rows.
    public func queryScalar(_ sql: String, params: [String?] = []) throws -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ManifoldError.database(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        bindParams(stmt, params)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cStr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cStr)
    }

    /// Returns all rows as `[String: String]` dictionaries.
    /// `queryAll` does not use the statement cache because the cursor stays open during row iteration.
    public func queryAll(_ sql: String, params: [String?] = []) throws -> [[String: String]] {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &s, nil) == SQLITE_OK else {
            throw ManifoldError.database(errorMessage)
        }
        guard let stmt = s else {
            throw ManifoldError.database("SQLite prepared a nil statement for query: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }

        bindParams(stmt, params)

        var rows: [[String: String]] = []
        let colCount = sqlite3_column_count(stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: String] = [:]
            for col in 0..<colCount {
                let name = String(cString: sqlite3_column_name(stmt, col))
                if let cStr = sqlite3_column_text(stmt, col) {
                    row[name] = String(cString: cStr)
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// Runs a block inside a transaction and rolls back on error.
    public func transaction(_ block: () throws -> Void) throws {
        try execute("BEGIN TRANSACTION")
        do {
            try block()
            try execute("COMMIT")
        } catch {
            do { try execute("ROLLBACK") }
            catch { logger.error("ROLLBACK failed: \(error.localizedDescription)") }
            throw error
        }
    }

    /// Returns `true` when SQLite reports the database integrity check as `ok`.
    public func integrityCheck() throws -> Bool {
        let result = try queryScalar("PRAGMA integrity_check")
        return result == "ok"
    }

    /// Bind string parameters to a prepared statement.
    /// Uses withCString + SQLITE_TRANSIENT instead of NSString bridging
    /// to avoid Foundation allocation overhead per bind.
    private func bindParams(_ stmt: OpaquePointer?, _ params: [String?]) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, param) in params.enumerated() {
            if let param {
                _ = param.withCString { cStr in
                    sqlite3_bind_text(stmt, Int32(i + 1), cStr, -1, transient)
                }
            } else {
                sqlite3_bind_null(stmt, Int32(i + 1))
            }
        }
    }

    private var errorMessage: String {
        handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }

    private func secureDatabaseFiles() throws {
        try LocalFileProtection.secureFile(at: url)
        try? LocalFileProtection.secureFile(at: URL(fileURLWithPath: url.path + "-wal"))
        try? LocalFileProtection.secureFile(at: URL(fileURLWithPath: url.path + "-shm"))
    }
}
