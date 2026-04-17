// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let ruleLogger = Logger(subsystem: "com.spatialduality.manifold", category: "rules")

/// Persists the unified rule catalog across all three scopes (file, email, agent).
///
/// This store is the source of truth for the forthcoming cross-scope rule engine.
/// It deliberately coexists with the legacy email rule tables (`email_domain_rules`,
/// `email_contact_rules`, `email_keyword_rules`, `email_shield_states`) during
/// migration — `EmailPolicyEngine` will be re-pointed at this store in a follow-up.
public actor RuleStore {
    private let db: DatabaseConnection
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(db: DatabaseConnection) {
        self.db = db
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Fetch

    public func allRules() throws -> [RuleRecord] {
        let rows = try db.queryAll(
            """
            SELECT * FROM rule_records
            ORDER BY scope ASC, order_index ASC, created_at ASC
            """
        )
        return try rows.compactMap { try decode(row: $0) }
    }

    public func rules(scope: RuleScope) throws -> [RuleRecord] {
        let rows = try db.queryAll(
            """
            SELECT * FROM rule_records WHERE scope = ?
            ORDER BY order_index ASC, created_at ASC
            """,
            params: [scope.rawValue]
        )
        return try rows.compactMap { try decode(row: $0) }
    }

    public func rule(id: String) throws -> RuleRecord? {
        let rows = try db.queryAll(
            "SELECT * FROM rule_records WHERE rule_id = ? LIMIT 1",
            params: [id]
        )
        guard let row = rows.first else { return nil }
        return try decode(row: row)
    }

    // MARK: - Mutate

    public func upsert(_ rule: RuleRecord) throws {
        try RuleValidator.validate(rule)
        let encoded = try encode(rule: rule)
        try db.execute(
            """
            INSERT INTO rule_records (
                rule_id, name, explanation, scope, action, matcher_json,
                agents_json, window_json, source, enabled, order_index,
                created_at, updated_at, last_matched_at, match_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(rule_id) DO UPDATE SET
                name = excluded.name,
                explanation = excluded.explanation,
                scope = excluded.scope,
                action = excluded.action,
                matcher_json = excluded.matcher_json,
                agents_json = excluded.agents_json,
                window_json = excluded.window_json,
                source = excluded.source,
                enabled = excluded.enabled,
                order_index = excluded.order_index,
                updated_at = excluded.updated_at
            """,
            params: encoded
        )
        ruleLogger.info("Upserted rule \(rule.id) (\(rule.scope.rawValue), \(rule.action.rawValue))")
    }

    public func delete(id: String) throws {
        guard let rule = try rule(id: id) else { return }
        guard rule.source.isMutable else {
            throw RuleValidationError.seededRuleImmutable
        }
        try db.execute("DELETE FROM rule_records WHERE rule_id = ?", params: [id])
        ruleLogger.info("Deleted rule \(id)")
    }

    public func setEnabled(id: String, enabled: Bool) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            "UPDATE rule_records SET enabled = ?, updated_at = ? WHERE rule_id = ?",
            params: [enabled ? "1" : "0", now, id]
        )
    }

    /// Replaces the ordering within a scope. `ids` lists the new ordering; unlisted rules
    /// of the scope keep their relative order appended at the end.
    public func reorder(scope: RuleScope, ids: [String]) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.transaction {
            for (index, id) in ids.enumerated() {
                try db.execute(
                    "UPDATE rule_records SET order_index = ?, updated_at = ? WHERE rule_id = ? AND scope = ?",
                    params: ["\(index)", now, id, scope.rawValue]
                )
            }
        }
    }

    /// Records a successful match for audit / UI sparkline. Best-effort; never throws on failure.
    public func recordMatch(id: String, at date: Date = Date()) {
        let iso = ISO8601DateFormatter.shared.string(from: date)
        do {
            try db.execute(
                """
                UPDATE rule_records
                SET last_matched_at = ?, match_count = match_count + 1
                WHERE rule_id = ?
                """,
                params: [iso, id]
            )
        } catch {
            ruleLogger.error("Failed to record match for rule \(id): \(String(describing: error))")
        }
    }

    // MARK: - Seeding

    /// Idempotent — inserts every rule in `seeds` that isn't already present by rule_id.
    /// Caller should invoke at app/runtime startup.
    public func seedIfNeeded(_ seeds: [RuleRecord]) throws {
        for seed in seeds where try rule(id: seed.id) == nil {
            try upsert(seed)
        }
    }

    // MARK: - Coding

    private func encode(rule: RuleRecord) throws -> [String] {
        let matcherData = try encoder.encode(rule.matcher)
        let matcherJSON = String(data: matcherData, encoding: .utf8) ?? "{}"
        let agentsData = try encoder.encode(rule.agents.map(\.rawValue).sorted())
        let agentsJSON = String(data: agentsData, encoding: .utf8) ?? "[]"
        let windowData = try encoder.encode(rule.window)
        let windowJSON = String(data: windowData, encoding: .utf8) ?? "{\"kind\":\"always\"}"
        return [
            rule.id,
            rule.name,
            rule.explanation,
            rule.scope.rawValue,
            rule.action.rawValue,
            matcherJSON,
            agentsJSON,
            windowJSON,
            rule.source.rawValue,
            rule.enabled ? "1" : "0",
            "\(rule.orderIndex)",
            rule.createdAt,
            rule.updatedAt,
            rule.lastMatchedAt ?? "",
            "\(rule.matchCount)",
        ]
    }

    private func decode(row: [String: String]) throws -> RuleRecord? {
        guard let id = row["rule_id"],
              let name = row["name"],
              let scopeRaw = row["scope"], let scope = RuleScope(rawValue: scopeRaw),
              let actionRaw = row["action"], let action = RuleAction(rawValue: actionRaw),
              let matcherJSON = row["matcher_json"],
              let matcherData = matcherJSON.data(using: .utf8),
              let agentsJSON = row["agents_json"],
              let agentsData = agentsJSON.data(using: .utf8),
              let windowJSON = row["window_json"],
              let windowData = windowJSON.data(using: .utf8),
              let sourceRaw = row["source"], let source = RuleSource(rawValue: sourceRaw),
              let createdAt = row["created_at"],
              let updatedAt = row["updated_at"] else {
            ruleLogger.warning("Failed to parse RuleRecord row (missing fields)")
            return nil
        }
        let matcher = try decoder.decode(RuleMatcher.self, from: matcherData)
        let agentRaws = try decoder.decode([String].self, from: agentsData)
        let agents = Set(agentRaws.compactMap(TargetApp.init(rawValue:)))
        let window = try decoder.decode(RuleWindow.self, from: windowData)

        let enabled = row["enabled"] == "1"
        let orderIndex = Int(row["order_index"] ?? "0") ?? 0
        let lastMatched = row["last_matched_at"]
        let lastMatchedNormalized: String? = (lastMatched?.isEmpty == false) ? lastMatched : nil
        let matchCount = Int(row["match_count"] ?? "0") ?? 0

        return RuleRecord(
            id: id,
            name: name,
            explanation: row["explanation"] ?? "",
            scope: scope,
            matcher: matcher,
            action: action,
            agents: agents,
            window: window,
            source: source,
            enabled: enabled,
            orderIndex: orderIndex,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastMatchedAt: lastMatchedNormalized,
            matchCount: matchCount
        )
    }
}
