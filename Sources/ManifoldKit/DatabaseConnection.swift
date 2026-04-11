import Foundation
import SQLite3
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "database")

/// Minimal SQLite wrapper. All operations are synchronous — callers use actor isolation.
public final class DatabaseConnection: @unchecked Sendable {
    private var handle: OpaquePointer?

    public init(url: URL) throws {
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
    }

    /// Prepared statement cache — avoids recompiling identical SQL on every call.
    /// sqlite.org: "sqlite3_prepare_v2() is a significant consumer of CPU time."
    private var stmtCache: [String: OpaquePointer] = [:]

    deinit {
        // Finalize all cached statements before closing
        for (_, stmt) in stmtCache {
            sqlite3_finalize(stmt)
        }
        stmtCache.removeAll()
        sqlite3_close(handle)
    }

    private func cachedStmt(_ sql: String) throws -> OpaquePointer {
        if let cached = stmtCache[sql] {
            sqlite3_reset(cached)
            sqlite3_clear_bindings(cached)
            return cached
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ManifoldError.database(errorMessage)
        }
        // Only cache deterministic queries (not PRAGMA, not CREATE)
        let upper = sql.trimmingCharacters(in: .whitespaces).uppercased()
        if upper.hasPrefix("SELECT") || upper.hasPrefix("INSERT") || upper.hasPrefix("UPDATE") || upper.hasPrefix("DELETE") {
            stmtCache[sql] = stmt
        }
        return stmt!
    }

    /// Execute a SQL statement with optional string parameters.
    /// Pass nil for SQL NULL values (important for optional foreign key columns).
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

    /// Query a single scalar value (first column of first row).
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

    /// Query all rows as [String: String] dictionaries.
    /// queryAll does NOT use the statement cache because the cursor remains
    /// open during row iteration, which would conflict with concurrent queries.
    public func queryAll(_ sql: String, params: [String?] = []) throws -> [[String: String]] {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &s, nil) == SQLITE_OK else {
            throw ManifoldError.database(errorMessage)
        }
        let stmt = s!
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

    /// Run a block inside a transaction. Rolls back on error.
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

    /// Run an integrity check on the database.
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
}
