import Foundation
import SQLite3

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
        // Foreign keys
        try execute("PRAGMA foreign_keys=ON")
    }

    deinit {
        sqlite3_close(handle)
    }

    /// Execute a SQL statement with optional string parameters.
    public func execute(_ sql: String, params: [String] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ManifoldError.database(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        for (i, param) in params.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), (param as NSString).utf8String, -1, nil)
        }

        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw ManifoldError.database(errorMessage)
        }
    }

    /// Query a single scalar value (first column of first row).
    public func queryScalar(_ sql: String, params: [String] = []) throws -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ManifoldError.database(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        for (i, param) in params.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), (param as NSString).utf8String, -1, nil)
        }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cStr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cStr)
    }

    /// Query all rows as [String: String] dictionaries.
    public func queryAll(_ sql: String, params: [String] = []) throws -> [[String: String]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ManifoldError.database(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        for (i, param) in params.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), (param as NSString).utf8String, -1, nil)
        }

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
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Run an integrity check on the database.
    public func integrityCheck() throws -> Bool {
        let result = try queryScalar("PRAGMA integrity_check")
        return result == "ok"
    }

    private var errorMessage: String {
        handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }
}
