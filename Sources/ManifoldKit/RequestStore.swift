import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "requests")

/// Manages access request queue — agents requesting resources outside their policy.
public actor RequestStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    public func pendingRequests(for agent: TargetApp? = nil) throws -> [AccessRequest] {
        let sql: String
        let params: [String?]
        if let agent {
            sql = "SELECT * FROM access_requests WHERE status = 'pending' AND agent = ? ORDER BY requested_at DESC"
            params = [agent.rawValue]
        } else {
            sql = "SELECT * FROM access_requests WHERE status = 'pending' ORDER BY requested_at DESC"
            params = []
        }
        let rows = try db.queryAll(sql, params: params)
        return rows.compactMap { row in
            guard let id = row["request_id"],
                  let agentRaw = row["agent"],
                  let agent = TargetApp(rawValue: agentRaw),
                  let path = row["resource_path"],
                  let name = row["resource_name"],
                  let requestedAt = row["requested_at"],
                  let statusRaw = row["status"],
                  let status = AccessRequestStatus(rawValue: statusRaw) else { return nil }
            return AccessRequest(id: id, agent: agent, resourcePath: path, resourceName: name, requestedAt: requestedAt, status: status)
        }
    }

    public func addRequest(_ request: AccessRequest) throws {
        // Rate-limit: skip duplicates within 5 minutes
        let existing = try db.queryScalar("""
            SELECT COUNT(*) FROM access_requests
            WHERE agent = ? AND resource_path = ? AND status = 'pending'
        """, params: [request.agent.rawValue, request.resourcePath])
        guard existing == "0" || existing == nil else { return }

        try db.execute("""
            INSERT INTO access_requests (request_id, agent, resource_path, resource_name, requested_at, status)
            VALUES (?, ?, ?, ?, ?, ?)
        """, params: [request.id, request.agent.rawValue, request.resourcePath, request.resourceName, request.requestedAt, request.status.rawValue])
        logger.info("Access request \(request.id) from \(request.agent.rawValue) for \(request.resourceName)")
    }

    public func denyRequest(_ id: String) throws {
        try db.execute("UPDATE access_requests SET status = 'denied' WHERE request_id = ?", params: [id])
    }

    public func approveRequest(_ id: String) throws {
        try db.execute("UPDATE access_requests SET status = 'approved' WHERE request_id = ?", params: [id])
    }

    public func expireStaleRequests(olderThanMinutes: Int = 30) throws -> Int {
        let cutoff = Date().addingTimeInterval(-Double(olderThanMinutes * 60))
        let cutoffStr = ISO8601DateFormatter.shared.string(from: cutoff)
        try db.execute("""
            UPDATE access_requests SET status = 'expired'
            WHERE status = 'pending' AND requested_at < ?
        """, params: [cutoffStr])
        return 0
    }
}
