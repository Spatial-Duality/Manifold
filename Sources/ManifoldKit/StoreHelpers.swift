// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Shared helpers for ManifoldKit stores.
///
/// Each store under `Sources/ManifoldKit` was independently re-implementing
/// schema column-add checks and JSON encode/decode. Centralizing keeps
/// behavior consistent and lets future stores opt in without copy-paste.

/// Adds a column to `table` only if it does not already exist.
///
/// Reads `PRAGMA table_info(table)` and runs `sql` (an `ALTER TABLE ... ADD
/// COLUMN ...` statement) only when `column` is missing. Idempotent.
public func addColumnIfMissing(
    _ db: DatabaseConnection,
    table: String,
    column: String,
    sql: String
) throws {
    let columns = try db.queryAll("PRAGMA table_info(\(table))")
    if !columns.contains(where: { $0["name"] == column }) {
        try db.execute(sql)
    }
}

/// JSON encode/decode helpers for store value-type round-tripping.
///
/// Stores persist arrays and dictionaries as TEXT columns. These helpers
/// keep encoder configuration consistent (sorted keys for determinism) and
/// provide a single point for failure handling.
public enum StoreJSON {
    /// Encodes `value` as a JSON string with sorted keys. Returns "null" on
    /// encoding failure rather than throwing, matching the pattern individual
    /// stores were already using.
    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "null"
    }

    /// Encodes a `[String: String]` dictionary as JSON, returning `nil` for
    /// empty dictionaries (matches LedgerStore's optional-metadata convention).
    public static func encode(metadata dictionary: [String: String]) throws -> String? {
        guard !dictionary.isEmpty else { return nil }
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)
    }

    /// Decodes a JSON string into `T`. Returns `nil` on missing input or
    /// malformed payload, matching the lenient pattern stores were using.
    public static func decode<T: Decodable>(_ type: T.Type, from raw: String?) -> T? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Decodes a JSON string array, returning `[]` on missing input or
    /// malformed payload. Matches MemoryStore's prior decodeArray helper.
    public static func decodeArray(_ raw: String?) -> [String] {
        decode([String].self, from: raw) ?? []
    }
}
