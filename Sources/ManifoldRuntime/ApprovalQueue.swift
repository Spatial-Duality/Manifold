// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import os

private let approvalQueueLogger = Logger(subsystem: "com.spatialduality.manifold", category: "approval-queue")

public actor ApprovalQueue {
    public struct PendingRequest: Sendable {
        public enum Status: String, Sendable {
            case pending
            case approved
            case denied
            case expired
        }

        public let id: String
        public let connectionID: String
        public let agent: String
        public let path: String
        public let action: String
        public let requestedAt: Double
        public let status: Status

        public init(
            id: String,
            connectionID: String,
            agent: String,
            path: String,
            action: String,
            requestedAt: Double,
            status: Status
        ) {
            self.id = id
            self.connectionID = connectionID
            self.agent = agent
            self.path = path
            self.action = action
            self.requestedAt = requestedAt
            self.status = status
        }
    }

    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    @discardableResult
    public func submit(connectionID: String, agent: String, path: String, action: String) throws -> PendingRequest {
        let request = PendingRequest(
            id: UUID().uuidString,
            connectionID: connectionID,
            agent: agent,
            path: path,
            action: action,
            requestedAt: Date().timeIntervalSince1970,
            status: .pending
        )
        try db.execute(
            """
            INSERT INTO approval_requests (
                id, connection_id, agent, path, action, requested_at, status
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            params: [
                request.id,
                request.connectionID,
                request.agent,
                request.path,
                request.action,
                String(request.requestedAt),
                request.status.rawValue,
            ]
        )
        approvalQueueLogger.info("Queued approval request \(request.id, privacy: .public) for \(path, privacy: .public)")
        return request
    }

    public func approve(id: String) throws {
        try update(id: id, status: .approved)
    }

    public func deny(id: String) throws {
        try update(id: id, status: .denied)
    }

    public func pending() throws -> [PendingRequest] {
        let rows = try db.queryAll(
            """
            SELECT * FROM approval_requests
            WHERE status = 'pending'
            ORDER BY requested_at ASC
            """
        )
        return rows.compactMap(Self.request(from:))
    }

    @discardableResult
    public func expire(olderThan seconds: TimeInterval) throws -> Int {
        let cutoff = Date().timeIntervalSince1970 - seconds
        try db.execute(
            """
            UPDATE approval_requests
            SET status = 'expired', resolved_at = ?
            WHERE status = 'pending' AND requested_at < ?
            """,
            params: [String(Date().timeIntervalSince1970), String(cutoff)]
        )
        let count = Int(
            try db.queryScalar(
                "SELECT COUNT(*) FROM approval_requests WHERE status = 'expired' AND resolved_at >= ?",
                params: [String(cutoff)]
            ) ?? "0"
        ) ?? 0
        if count > 0 {
            approvalQueueLogger.info("Expired \(count) approval request(s)")
        }
        return count
    }

    private func update(id: String, status: PendingRequest.Status) throws {
        try db.execute(
            """
            UPDATE approval_requests
            SET status = ?, resolved_at = ?
            WHERE id = ?
            """,
            params: [status.rawValue, String(Date().timeIntervalSince1970), id]
        )
    }

    private static func request(from row: [String: String]) -> PendingRequest? {
        guard let id = row["id"],
              let connectionID = row["connection_id"],
              let agent = row["agent"],
              let path = row["path"],
              let action = row["action"],
              let requestedAtRaw = row["requested_at"],
              let requestedAt = Double(requestedAtRaw),
              let statusRaw = row["status"],
              let status = PendingRequest.Status(rawValue: statusRaw) else {
            approvalQueueLogger.error("Failed to decode approval request row")
            return nil
        }
        return PendingRequest(
            id: id,
            connectionID: connectionID,
            agent: agent,
            path: path,
            action: action,
            requestedAt: requestedAt,
            status: status
        )
    }
}
