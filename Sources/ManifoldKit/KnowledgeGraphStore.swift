// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let graphLogger = Logger(subsystem: "com.spatialduality.manifold", category: "knowledge-graph")

public actor KnowledgeGraphStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) throws {
        self.db = db
        try Self.ensureSchema(db)
    }

    public static func ensureSchema(_ db: DatabaseConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS knowledge_graph_nodes (
                node_id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                label TEXT NOT NULL,
                lineage_json TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_graph_nodes_kind ON knowledge_graph_nodes(kind)")

        try db.execute("""
            CREATE TABLE IF NOT EXISTS knowledge_graph_edges (
                edge_id TEXT PRIMARY KEY,
                from_node_id TEXT NOT NULL,
                to_node_id TEXT NOT NULL,
                relation TEXT NOT NULL,
                lineage_json TEXT NOT NULL,
                created_at REAL NOT NULL
            )
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_graph_edges_from ON knowledge_graph_edges(from_node_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_graph_edges_to ON knowledge_graph_edges(to_node_id)")
    }

    @discardableResult
    public func upsertNode(kind: String, label: String, lineage: [LineageRef] = []) throws -> KnowledgeGraphNode {
        let existing = try db.queryAll(
            "SELECT * FROM knowledge_graph_nodes WHERE kind = ? AND label = ? LIMIT 1",
            params: [kind, label]
        ).first.flatMap(Self.node(from:))
        let now = Date().timeIntervalSince1970
        let node = KnowledgeGraphNode(
            nodeID: existing?.nodeID ?? "node-\(UUID().uuidString.prefix(12).lowercased())",
            kind: kind,
            label: label,
            lineage: lineage,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        try db.execute("""
            INSERT INTO knowledge_graph_nodes (
                node_id, kind, label, lineage_json, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(node_id) DO UPDATE SET
                label = excluded.label,
                lineage_json = excluded.lineage_json,
                updated_at = excluded.updated_at
        """, params: [
            node.nodeID,
            node.kind,
            node.label,
            try Self.jsonString(node.lineage),
            "\(node.createdAt)",
            "\(node.updatedAt)",
        ])
        return node
    }

    @discardableResult
    public func link(from: String, to: String, relation: String, lineage: [LineageRef] = []) throws -> KnowledgeGraphEdge {
        let edge = KnowledgeGraphEdge(fromNodeID: from, toNodeID: to, relation: relation, lineage: lineage)
        try db.execute("""
            INSERT INTO knowledge_graph_edges (
                edge_id, from_node_id, to_node_id, relation, lineage_json, created_at
            ) VALUES (?, ?, ?, ?, ?, ?)
        """, params: [
            edge.edgeID,
            edge.fromNodeID,
            edge.toNodeID,
            edge.relation,
            try Self.jsonString(edge.lineage),
            "\(edge.createdAt)",
        ])
        return edge
    }

    public func query(_ query: String, allowedSourceIDs: Set<String>? = nil, limit: Int = 20) throws -> [KnowledgeGraphNode] {
        let normalizedLimit = max(1, min(limit, 100))
        let rows: [[String: String]]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            rows = try db.queryAll(
                "SELECT * FROM knowledge_graph_nodes ORDER BY updated_at DESC LIMIT ?",
                params: ["\(normalizedLimit * 4)"]
            )
        } else {
            rows = try db.queryAll("""
                SELECT * FROM knowledge_graph_nodes
                WHERE label LIKE ? OR kind LIKE ?
                ORDER BY updated_at DESC
                LIMIT ?
            """, params: ["%\(trimmed)%", "%\(trimmed)%", "\(normalizedLimit * 4)"])
        }

        return rows.compactMap(Self.node(from:))
            .filter { node in
                guard let allowedSourceIDs else { return true }
                let lineageSources = Set(node.lineage.filter { $0.kind == "source" }.map(\.id))
                return lineageSources.isEmpty || lineageSources.isSubset(of: allowedSourceIDs)
            }
            .prefix(normalizedLimit)
            .map { $0 }
    }

    private static func node(from row: [String: String]) -> KnowledgeGraphNode? {
        guard let nodeID = row["node_id"],
              let kind = row["kind"],
              let label = row["label"],
              let createdRaw = row["created_at"],
              let createdAt = Double(createdRaw),
              let updatedRaw = row["updated_at"],
              let updatedAt = Double(updatedRaw) else {
            graphLogger.warning("Failed to decode graph node row")
            return nil
        }
        return KnowledgeGraphNode(
            nodeID: nodeID,
            kind: kind,
            label: label,
            lineage: decode([LineageRef].self, from: row["lineage_json"]) ?? [],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func jsonString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "null"
    }

    private static func decode<T: Decodable>(_ type: T.Type, from raw: String?) -> T? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
