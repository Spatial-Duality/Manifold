// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import os

private let approvalQueueLogger = Logger(subsystem: "com.spatialduality.manifold", category: "approval-queue")

public actor ApprovalQueue {
    public struct PendingRequest: Sendable {
        public enum Kind: String, Sendable {
            case standingWrite = "standing_write"
            case privacyExposure = "privacy_exposure"
        }

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
        public let kind: Kind
        public let sourceID: String?
        public let mountName: String?
        public let relativePath: String?
        public let contextJSON: String?
        public let requestedAt: Double
        public let status: Status
        public let resolutionAction: String?

        public init(
            id: String,
            connectionID: String,
            agent: String,
            path: String,
            action: String,
            kind: Kind,
            sourceID: String?,
            mountName: String?,
            relativePath: String?,
            contextJSON: String?,
            requestedAt: Double,
            status: Status,
            resolutionAction: String?
        ) {
            self.id = id
            self.connectionID = connectionID
            self.agent = agent
            self.path = path
            self.action = action
            self.kind = kind
            self.sourceID = sourceID
            self.mountName = mountName
            self.relativePath = relativePath
            self.contextJSON = contextJSON
            self.requestedAt = requestedAt
            self.status = status
            self.resolutionAction = resolutionAction
        }
    }

    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    @discardableResult
    public func submit(
        connectionID: String,
        agent: String,
        path: String,
        action: String,
        kind: PendingRequest.Kind = .standingWrite,
        sourceID: String? = nil,
        mountName: String? = nil,
        relativePath: String? = nil,
        contextJSON: String? = nil
    ) throws -> PendingRequest {
        if kind == .privacyExposure,
           let existing = try pending().first(where: {
               $0.kind == .privacyExposure
                   && $0.agent == agent
                   && $0.path == path
                   && $0.contextJSON == contextJSON
           }) {
            return existing
        }
        let request = PendingRequest(
            id: UUID().uuidString,
            connectionID: connectionID,
            agent: agent,
            path: path,
            action: action,
            kind: kind,
            sourceID: sourceID,
            mountName: mountName,
            relativePath: relativePath,
            contextJSON: contextJSON,
            requestedAt: Date().timeIntervalSince1970,
            status: .pending,
            resolutionAction: nil
        )
        try db.execute(
            """
            INSERT INTO approval_requests (
                id, connection_id, agent, path, action, request_kind,
                source_id, mount_name, relative_path, context_json, requested_at, status, resolution_action
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            params: [
                request.id,
                request.connectionID,
                request.agent,
                request.path,
                request.action,
                request.kind.rawValue,
                request.sourceID,
                request.mountName,
                request.relativePath,
                request.contextJSON,
                String(request.requestedAt),
                request.status.rawValue,
                request.resolutionAction,
            ]
        )
        approvalQueueLogger.info("Queued approval request \(request.id, privacy: .public) for \(path, privacy: .public)")
        return request
    }

    public func approve(id: String, resolutionAction: String? = nil) throws {
        try update(id: id, status: .approved, resolutionAction: resolutionAction)
    }

    public func deny(id: String) throws {
        try update(id: id, status: .denied, resolutionAction: "deny")
    }

    @discardableResult
    public func denyPending(sourceID: String, agent: TargetApp? = nil, resolutionAction: String = "source_revoked") throws -> Int {
        let now = String(Date().timeIntervalSince1970)
        if let agent {
            try db.execute(
                """
                UPDATE approval_requests
                SET status = 'denied', resolved_at = ?, resolution_action = ?
                WHERE status = 'pending' AND source_id = ? AND agent = ?
                """,
                params: [now, resolutionAction, sourceID, agent.rawValue]
            )
        } else {
            try db.execute(
                """
                UPDATE approval_requests
                SET status = 'denied', resolved_at = ?, resolution_action = ?
                WHERE status = 'pending' AND source_id = ?
                """,
                params: [now, resolutionAction, sourceID]
            )
        }
        return Int(
            try db.queryScalar(
                "SELECT changes()"
            ) ?? "0"
        ) ?? 0
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

    public func request(id: String) throws -> PendingRequest? {
        let rows = try db.queryAll(
            """
            SELECT * FROM approval_requests
            WHERE id = ?
            LIMIT 1
            """,
            params: [id]
        )
        return rows.first.flatMap(Self.request(from:))
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

    private func update(id: String, status: PendingRequest.Status, resolutionAction: String?) throws {
        try db.execute(
            """
            UPDATE approval_requests
            SET status = ?, resolved_at = ?, resolution_action = ?
            WHERE id = ?
            """,
            params: [status.rawValue, String(Date().timeIntervalSince1970), resolutionAction, id]
        )
    }

    private static func request(from row: [String: String]) -> PendingRequest? {
        guard let id = row["id"],
              let connectionID = row["connection_id"],
              let agent = row["agent"],
              let path = row["path"],
              let action = row["action"],
              let kind = PendingRequest.Kind(rawValue: row["request_kind"] ?? PendingRequest.Kind.standingWrite.rawValue),
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
            kind: kind,
            sourceID: row["source_id"],
            mountName: row["mount_name"],
            relativePath: row["relative_path"],
            contextJSON: row["context_json"],
            requestedAt: requestedAt,
            status: status,
            resolutionAction: row["resolution_action"]
        )
    }
}
