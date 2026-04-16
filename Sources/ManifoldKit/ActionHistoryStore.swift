// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ActionHistoryStore — append-only log of user-initiated mutations, each
// paired with the JSON payload needed to reverse it. Underpins universal
// undo (⌘Z) for grant/revoke/override actions performed in the app. Not
// a redo buffer yet: `undone_at` is set when an action is reversed, and
// further undo skips already-undone rows.
//
// The store is deliberately opaque about payload shape — it records
// JSON strings, and callers (ManifoldRuntime's undo handler) interpret
// them per `kind`. That keeps this file small and lets new undoable
// verbs be added without schema changes.

import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "action-history")

public struct ActionRecord: Sendable, Equatable {
    public let actionID: String
    public let kind: String
    public let payloadJSON: String
    public let inverseJSON: String
    public let summary: String
    public let createdAt: String
    public let undoneAt: String?

    public init(
        actionID: String,
        kind: String,
        payloadJSON: String,
        inverseJSON: String,
        summary: String,
        createdAt: String,
        undoneAt: String?
    ) {
        self.actionID = actionID
        self.kind = kind
        self.payloadJSON = payloadJSON
        self.inverseJSON = inverseJSON
        self.summary = summary
        self.createdAt = createdAt
        self.undoneAt = undoneAt
    }
}

public actor ActionHistoryStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    /// Append a user-initiated mutation and its inverse. Callers build
    /// the inverse by capturing prior state *before* applying the forward
    /// mutation. Returns the new action ID.
    @discardableResult
    public func append(
        kind: String,
        payloadJSON: String,
        inverseJSON: String,
        summary: String
    ) throws -> String {
        let actionID = "act-\(UUID().uuidString.prefix(8).lowercased())"
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            """
            INSERT INTO action_history
                (action_id, kind, payload_json, inverse_json, summary, created_at, undone_at)
            VALUES (?, ?, ?, ?, ?, ?, NULL)
            """,
            params: [actionID, kind, payloadJSON, inverseJSON, summary, now]
        )
        logger.debug("Appended action \(actionID, privacy: .public) kind=\(kind, privacy: .public)")
        return actionID
    }

    /// Return the most recent action that has not already been undone.
    /// Nil when the stack is empty.
    public func peekUndoable() throws -> ActionRecord? {
        let rows = try db.queryAll(
            """
            SELECT action_id, kind, payload_json, inverse_json, summary, created_at, undone_at
              FROM action_history
             WHERE undone_at IS NULL
             ORDER BY created_at DESC
             LIMIT 1
            """
        )
        guard let row = rows.first else { return nil }
        return record(from: row)
    }

    /// Mark the given action as undone. Does not delete — the row stays
    /// for history/audit, but subsequent undos skip it.
    public func markUndone(actionID: String) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            "UPDATE action_history SET undone_at = ? WHERE action_id = ?",
            params: [now, actionID]
        )
    }

    /// Recent entries (both undone and live). Useful for activity surfaces.
    public func recent(limit: Int = 20) throws -> [ActionRecord] {
        let rows = try db.queryAll(
            """
            SELECT action_id, kind, payload_json, inverse_json, summary, created_at, undone_at
              FROM action_history
             ORDER BY created_at DESC
             LIMIT ?
            """,
            params: ["\(limit)"]
        )
        return rows.compactMap { record(from: $0) }
    }

    private func record(from row: [String: String]) -> ActionRecord? {
        guard let actionID = row["action_id"],
              let kind = row["kind"],
              let payloadJSON = row["payload_json"],
              let inverseJSON = row["inverse_json"],
              let summary = row["summary"],
              let createdAt = row["created_at"] else {
            return nil
        }
        return ActionRecord(
            actionID: actionID,
            kind: kind,
            payloadJSON: payloadJSON,
            inverseJSON: inverseJSON,
            summary: summary,
            createdAt: createdAt,
            undoneAt: row["undone_at"]
        )
    }
}
