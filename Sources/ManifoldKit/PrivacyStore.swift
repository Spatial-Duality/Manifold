// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import os

private let privacyLogger = Logger(subsystem: "com.spatialduality.manifold", category: "privacy-store")

public actor PrivacyStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    public func settings(defaultStoragePath: String) throws -> PrivacyPreflightSettings {
        let rows = try db.queryAll(
            "SELECT * FROM privacy_preflight_settings WHERE id = 'privacy-preflight' LIMIT 1"
        )
        if let row = rows.first, let settings = Self.settings(from: row) {
            return settings
        }

        let settings = PrivacyPreflightSettings(storagePath: defaultStoragePath)
        try upsertSettings(settings)
        return settings
    }

    public func upsertSettings(_ settings: PrivacyPreflightSettings) throws {
        let updated = PrivacyPreflightSettings(
            id: settings.id,
            isEnabled: settings.isEnabled,
            selectedBackend: settings.selectedBackend,
            installState: settings.installState,
            modelVersion: settings.modelVersion,
            storagePath: settings.storagePath,
            installedAt: settings.installedAt,
            cacheEnabled: settings.cacheEnabled,
            unloadOnMemoryPressure: settings.unloadOnMemoryPressure,
            updatedAt: ISO8601DateFormatter.shared.string(from: Date())
        )
        try db.execute(
            """
            INSERT INTO privacy_preflight_settings (
                id, is_enabled, selected_backend, install_state, model_version,
                storage_path, installed_at, cache_enabled, unload_on_memory_pressure, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                is_enabled = excluded.is_enabled,
                selected_backend = excluded.selected_backend,
                install_state = excluded.install_state,
                model_version = excluded.model_version,
                storage_path = excluded.storage_path,
                installed_at = excluded.installed_at,
                cache_enabled = excluded.cache_enabled,
                unload_on_memory_pressure = excluded.unload_on_memory_pressure,
                updated_at = excluded.updated_at
            """,
            params: [
                updated.id,
                updated.isEnabled ? "1" : "0",
                updated.selectedBackend.rawValue,
                updated.installState.rawValue,
                updated.modelVersion,
                updated.storagePath,
                updated.installedAt,
                updated.cacheEnabled ? "1" : "0",
                updated.unloadOnMemoryPressure ? "1" : "0",
                updated.updatedAt,
            ]
        )
    }

    public func policy(for agent: TargetApp) throws -> AgentPrivacyPolicy {
        let rows = try db.queryAll(
            "SELECT * FROM agent_privacy_policies WHERE agent = ? LIMIT 1",
            params: [agent.rawValue]
        )
        if let row = rows.first, let policy = Self.policy(from: row) {
            return policy
        }

        let policy = AgentPrivacyPolicy(agent: agent)
        try upsertPolicy(policy)
        return policy
    }

    public func upsertPolicy(_ policy: AgentPrivacyPolicy) throws {
        let updated = AgentPrivacyPolicy(
            id: policy.id,
            agent: policy.agent,
            textHandling: policy.textHandling,
            codeHandling: policy.codeHandling,
            secretHandling: policy.secretHandling,
            enabledCategories: policy.enabledCategories,
            updatedAt: ISO8601DateFormatter.shared.string(from: Date())
        )
        try db.execute(
            """
            INSERT INTO agent_privacy_policies (
                policy_id, agent, text_handling, code_handling, secret_handling,
                enabled_categories_json, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(agent) DO UPDATE SET
                policy_id = excluded.policy_id,
                text_handling = excluded.text_handling,
                code_handling = excluded.code_handling,
                secret_handling = excluded.secret_handling,
                enabled_categories_json = excluded.enabled_categories_json,
                updated_at = excluded.updated_at
            """,
            params: [
                updated.id,
                updated.agent.rawValue,
                updated.textHandling.rawValue,
                updated.codeHandling.rawValue,
                updated.secretHandling.rawValue,
                Self.encode(updated.enabledCategories.sorted(by: { $0.rawValue < $1.rawValue })),
                updated.updatedAt,
            ]
        )
    }

    public func cachedResult(
        inputHash: String,
        backend: PrivacyBackendKind,
        modelVersion: String,
        operatingPoint: String,
        categories: [PrivacyCategory],
        contentKind: PrivacyContentKind
    ) throws -> PrivacyScanResult? {
        let rows = try db.queryAll(
            """
            SELECT * FROM privacy_scan_cache
            WHERE input_hash = ? AND backend = ? AND model_version = ?
              AND operating_point = ? AND category_set_json = ? AND content_kind = ?
            LIMIT 1
            """,
            params: [
                inputHash,
                backend.rawValue,
                modelVersion,
                operatingPoint,
                Self.encode(categories.sorted(by: { $0.rawValue < $1.rawValue })),
                contentKind.rawValue,
            ]
        )
        return rows.first.flatMap(Self.cachedResult(from:))
    }

    public func cache(
        _ result: PrivacyScanResult,
        inputHash: String,
        operatingPoint: String,
        categories: [PrivacyCategory],
        contentKind: PrivacyContentKind
    ) throws {
        try db.execute(
            """
            INSERT OR REPLACE INTO privacy_scan_cache (
                input_hash, backend, model_version, operating_point, category_set_json,
                content_kind, spans_json, redacted_text, findings_summary, elapsed_ms, cached_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            params: [
                inputHash,
                result.backend.rawValue,
                result.modelVersion,
                operatingPoint,
                Self.encode(categories.sorted(by: { $0.rawValue < $1.rawValue })),
                contentKind.rawValue,
                Self.encode(result.spans),
                result.redactedText,
                result.findingsSummary,
                "\(result.elapsedMs)",
                ISO8601DateFormatter.shared.string(from: Date()),
            ]
        )
    }

    @discardableResult
    public func clearCache() throws -> Int {
        let count = Int(try db.queryScalar("SELECT COUNT(*) FROM privacy_scan_cache") ?? "0") ?? 0
        try db.execute("DELETE FROM privacy_scan_cache")
        return count
    }

    public func cacheEntryCount() throws -> Int {
        Int(try db.queryScalar("SELECT COUNT(*) FROM privacy_scan_cache") ?? "0") ?? 0
    }

    public func recordEvent(_ event: PrivacyScanEventRecord) throws {
        try db.execute(
            """
            INSERT INTO privacy_scan_events (
                id, access_decision_id, agent, tool_name, resource_path, backend,
                model_version, content_kind, input_hash, delivered_hash, outcome,
                findings_summary, findings_count, matched_categories_json, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            params: [
                event.id,
                event.accessDecisionID,
                event.agent.rawValue,
                event.toolName,
                event.resourcePath,
                event.backend.rawValue,
                event.modelVersion,
                event.contentKind.rawValue,
                event.inputHash,
                event.deliveredHash,
                event.outcome.rawValue,
                event.findingsSummary,
                "\(event.findingsCount)",
                Self.encode(event.matchedCategories),
                event.createdAt,
            ]
        )
    }

    public func approvalOverride(
        agent: TargetApp,
        resourceKey: String,
        inputHash: String,
        contentKind: PrivacyContentKind
    ) throws -> PrivacyApprovalDecision? {
        let rows = try db.queryAll(
            """
            SELECT * FROM privacy_approval_overrides
            WHERE agent = ? AND resource_key = ? AND input_hash = ? AND content_kind = ?
            ORDER BY created_at ASC
            LIMIT 1
            """,
            params: [agent.rawValue, resourceKey, inputHash, contentKind.rawValue]
        )
        guard let row = rows.first,
              let decisionRaw = row["decision"],
              let decision = PrivacyApprovalDecision(rawValue: decisionRaw),
              let id = row["id"] else {
            return nil
        }
        try db.execute("DELETE FROM privacy_approval_overrides WHERE id = ?", params: [id])
        return decision
    }

    public func saveApprovalOverride(
        agent: TargetApp,
        resourceKey: String,
        inputHash: String,
        contentKind: PrivacyContentKind,
        decision: PrivacyApprovalDecision
    ) throws {
        try db.execute(
            """
            INSERT INTO privacy_approval_overrides (
                id, agent, resource_key, input_hash, content_kind, decision, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            params: [
                UUID().uuidString,
                agent.rawValue,
                resourceKey,
                inputHash,
                contentKind.rawValue,
                decision.rawValue,
                ISO8601DateFormatter.shared.string(from: Date()),
            ]
        )
    }

    public func identities(enabledOnly: Bool = false) throws -> [PrivacyIdentityRecord] {
        let query = enabledOnly
            ? "SELECT * FROM privacy_identity_registry WHERE is_enabled = 1 ORDER BY display_name ASC"
            : "SELECT * FROM privacy_identity_registry ORDER BY display_name ASC"
        let rows = try db.queryAll(query)
        var decoded: [PrivacyIdentityRecord] = []
        for row in rows {
            if let identity = try identity(from: row) {
                decoded.append(identity)
            }
        }
        return decoded
    }

    public func upsertIdentity(_ identity: PrivacyIdentityRecord) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        let normalizedHash = identity.normalizedHash ?? Self.normalizedHash(kind: identity.kind, value: identity.value)
        try db.execute(
            """
            INSERT INTO privacy_identity_registry (
                identity_id, kind, display_name, value_ciphertext, normalized_hash,
                matching_mode, is_enabled, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(identity_id) DO UPDATE SET
                kind = excluded.kind,
                display_name = excluded.display_name,
                value_ciphertext = excluded.value_ciphertext,
                normalized_hash = excluded.normalized_hash,
                matching_mode = excluded.matching_mode,
                is_enabled = excluded.is_enabled,
                updated_at = excluded.updated_at
            """,
            params: [
                identity.id,
                identity.kind.rawValue,
                identity.displayName,
                try cipherText(for: identity.value),
                normalizedHash,
                identity.matchingMode.rawValue,
                identity.isEnabled ? "1" : "0",
                identity.createdAt,
                now,
            ]
        )
    }

    public func deleteIdentity(id: String) throws {
        try db.execute("DELETE FROM privacy_identity_registry WHERE identity_id = ?", params: [id])
    }

    public func identitySuggestions(
        status: PrivacySuggestionStatus? = nil
    ) throws -> [PrivacyIdentitySuggestion] {
        let rows: [[String: String]]
        if let status {
            rows = try db.queryAll(
                "SELECT * FROM privacy_identity_suggestions WHERE status = ? ORDER BY confidence DESC, created_at ASC",
                params: [status.rawValue]
            )
        } else {
            rows = try db.queryAll(
                "SELECT * FROM privacy_identity_suggestions ORDER BY status ASC, confidence DESC, created_at ASC"
            )
        }
        var decoded: [PrivacyIdentitySuggestion] = []
        for row in rows {
            if let suggestion = try identitySuggestion(from: row) {
                decoded.append(suggestion)
            }
        }
        return decoded
    }

    public func upsertIdentitySuggestion(_ suggestion: PrivacyIdentitySuggestion) throws {
        try db.execute(
            """
            INSERT INTO privacy_identity_suggestions (
                suggestion_id, kind, display_name, value_ciphertext, normalized_hash,
                source_kind, source_ref, confidence, status, created_at, reviewed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(suggestion_id) DO UPDATE SET
                kind = excluded.kind,
                display_name = excluded.display_name,
                value_ciphertext = excluded.value_ciphertext,
                normalized_hash = excluded.normalized_hash,
                source_kind = excluded.source_kind,
                source_ref = excluded.source_ref,
                confidence = excluded.confidence,
                status = excluded.status,
                reviewed_at = excluded.reviewed_at
            """,
            params: [
                suggestion.id,
                suggestion.kind.rawValue,
                suggestion.displayName,
                try cipherText(for: suggestion.value),
                suggestion.normalizedHash ?? Self.normalizedHash(kind: suggestion.kind, value: suggestion.value),
                suggestion.sourceKind.rawValue,
                suggestion.sourceRef,
                "\(suggestion.confidence)",
                suggestion.status.rawValue,
                suggestion.createdAt,
                suggestion.reviewedAt,
            ]
        )
    }

    public func updateIdentitySuggestionStatus(
        id: String,
        status: PrivacySuggestionStatus
    ) throws {
        try db.execute(
            """
            UPDATE privacy_identity_suggestions
            SET status = ?, reviewed_at = ?
            WHERE suggestion_id = ?
            """,
            params: [status.rawValue, ISO8601DateFormatter.shared.string(from: Date()), id]
        )
    }

    public func orgAllowlistEntries(enabledOnly: Bool = false) throws -> [PrivacyOrgAllowEntry] {
        let query = enabledOnly
            ? "SELECT * FROM privacy_org_allowlist WHERE is_enabled = 1 ORDER BY pattern ASC"
            : "SELECT * FROM privacy_org_allowlist ORDER BY pattern ASC"
        let rows = try db.queryAll(query)
        return rows.compactMap(Self.orgAllowEntry(from:))
    }

    public func upsertOrgAllowEntry(_ entry: PrivacyOrgAllowEntry) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            """
            INSERT INTO privacy_org_allowlist (
                allow_id, kind, pattern, match_mode, source, is_enabled, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(allow_id) DO UPDATE SET
                kind = excluded.kind,
                pattern = excluded.pattern,
                match_mode = excluded.match_mode,
                source = excluded.source,
                is_enabled = excluded.is_enabled,
                updated_at = excluded.updated_at
            """,
            params: [
                entry.id,
                entry.kind.rawValue,
                entry.pattern,
                entry.matchMode.rawValue,
                entry.source,
                entry.isEnabled ? "1" : "0",
                entry.createdAt,
                now,
            ]
        )
    }

    public func deleteOrgAllowEntry(id: String) throws {
        try db.execute("DELETE FROM privacy_org_allowlist WHERE allow_id = ?", params: [id])
    }

    public func contentIndexRecord(id: String) throws -> PrivacyIndexRecord? {
        let rows = try db.queryAll(
            "SELECT * FROM privacy_content_index WHERE content_id = ? LIMIT 1",
            params: [id]
        )
        return rows.first.flatMap(Self.contentIndexRecord(from:))
    }

    public func upsertContentIndexRecord(_ record: PrivacyIndexRecord) throws {
        try db.execute(
            """
            INSERT INTO privacy_content_index (
                content_id, subject_kind, source_id, relative_path, email_id, attachment_id,
                parent_content_id, display_name, mime_type, extractor, extract_status, scan_status,
                content_hash, backend, model_version, contains_sensitive, contains_my_info,
                contains_third_party_private, contains_secret, contains_org_only, severity,
                matched_categories_json, matched_identity_ids_json, matched_allow_ids_json,
                redacted_preview, findings_summary, span_count, last_scanned_at, updated_at, last_error
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(content_id) DO UPDATE SET
                subject_kind = excluded.subject_kind,
                source_id = excluded.source_id,
                relative_path = excluded.relative_path,
                email_id = excluded.email_id,
                attachment_id = excluded.attachment_id,
                parent_content_id = excluded.parent_content_id,
                display_name = excluded.display_name,
                mime_type = excluded.mime_type,
                extractor = excluded.extractor,
                extract_status = excluded.extract_status,
                scan_status = excluded.scan_status,
                content_hash = excluded.content_hash,
                backend = excluded.backend,
                model_version = excluded.model_version,
                contains_sensitive = excluded.contains_sensitive,
                contains_my_info = excluded.contains_my_info,
                contains_third_party_private = excluded.contains_third_party_private,
                contains_secret = excluded.contains_secret,
                contains_org_only = excluded.contains_org_only,
                severity = excluded.severity,
                matched_categories_json = excluded.matched_categories_json,
                matched_identity_ids_json = excluded.matched_identity_ids_json,
                matched_allow_ids_json = excluded.matched_allow_ids_json,
                redacted_preview = excluded.redacted_preview,
                findings_summary = excluded.findings_summary,
                span_count = excluded.span_count,
                last_scanned_at = excluded.last_scanned_at,
                updated_at = excluded.updated_at,
                last_error = excluded.last_error
            """,
            params: [
                record.id,
                record.subjectKind.rawValue,
                record.sourceID,
                record.relativePath,
                record.emailID,
                record.attachmentID,
                record.parentContentID,
                record.displayName,
                record.mimeType,
                record.extractor,
                record.extractStatus.rawValue,
                record.scanStatus.rawValue,
                record.contentHash,
                record.backend?.rawValue,
                record.modelVersion,
                record.containsSensitive ? "1" : "0",
                record.containsMyInfo ? "1" : "0",
                record.containsThirdPartyPrivate ? "1" : "0",
                record.containsSecret ? "1" : "0",
                record.containsOrgOnly ? "1" : "0",
                record.severity.rawValue,
                Self.encode(record.matchedCategories),
                Self.encode(record.matchedIdentityIDs),
                Self.encode(record.matchedAllowIDs),
                record.redactedPreview,
                record.findingsSummary,
                "\(record.spanCount)",
                record.lastScannedAt,
                record.updatedAt,
                record.lastError,
            ]
        )
    }

    public func listContentIndex(
        scope: PrivacyIndexScope = PrivacyIndexScope(),
        filter: PrivacyIndexFilter = PrivacyIndexFilter(),
        limit: Int = 500
    ) throws -> [PrivacyIndexRecord] {
        var whereClauses: [String] = []
        var params: [String?] = []

        if let kinds = scope.subjectKinds, !kinds.isEmpty {
            let placeholders = kinds.map { _ in "?" }.joined(separator: ",")
            whereClauses.append("subject_kind IN (\(placeholders))")
            params.append(contentsOf: kinds.map(\.rawValue))
        }
        if let sourceID = scope.sourceID {
            whereClauses.append("source_id = ?")
            params.append(sourceID)
        }
        if let emailID = scope.emailID {
            whereClauses.append("email_id = ?")
            params.append(emailID)
        }
        if let attachmentID = scope.attachmentID {
            whereClauses.append("attachment_id = ?")
            params.append(attachmentID)
        }

        appendBooleanFilter(filter.containsSensitive, column: "contains_sensitive", to: &whereClauses, params: &params)
        appendBooleanFilter(filter.containsMyInfo, column: "contains_my_info", to: &whereClauses, params: &params)
        appendBooleanFilter(filter.containsSecret, column: "contains_secret", to: &whereClauses, params: &params)
        appendBooleanFilter(filter.containsThirdPartyPrivate, column: "contains_third_party_private", to: &whereClauses, params: &params)
        appendBooleanFilter(filter.containsOrgOnly, column: "contains_org_only", to: &whereClauses, params: &params)

        if let severity = filter.severity {
            whereClauses.append("severity = ?")
            params.append(severity.rawValue)
        }
        if let categories = filter.categories, !categories.isEmpty {
            for category in categories {
                whereClauses.append("matched_categories_json LIKE ?")
                params.append("%\"\(category.rawValue)\"%")
            }
        }

        let whereSQL = whereClauses.isEmpty ? "" : "WHERE " + whereClauses.joined(separator: " AND ")
        params.append("\(limit)")
        let rows = try db.queryAll(
            """
            SELECT * FROM privacy_content_index
            \(whereSQL)
            ORDER BY
                CASE severity
                    WHEN 'critical' THEN 4
                    WHEN 'high' THEN 3
                    WHEN 'medium' THEN 2
                    WHEN 'low' THEN 1
                    ELSE 0
                END DESC,
                updated_at DESC
            LIMIT ?
            """,
            params: params
        )
        return rows.compactMap(Self.contentIndexRecord(from:))
    }

    public func deleteContentIndex(contentID: String) throws {
        try db.transaction {
            try db.execute("DELETE FROM privacy_detected_spans WHERE content_id = ?", params: [contentID])
            try db.execute("DELETE FROM privacy_index_jobs WHERE content_id = ?", params: [contentID])
            try db.execute("DELETE FROM privacy_content_index WHERE content_id = ?", params: [contentID])
        }
    }

    public func markContentIndexStale(contentID: String, error: String? = nil) throws {
        try db.execute(
            """
            UPDATE privacy_content_index
            SET scan_status = ?, updated_at = ?, last_error = ?
            WHERE content_id = ?
            """,
            params: [
                PrivacyIndexStatus.stale.rawValue,
                ISO8601DateFormatter.shared.string(from: Date()),
                error,
                contentID,
            ]
        )
    }

    public func replaceSpans(for contentID: String, spans: [PrivacySpanRecord]) throws {
        try db.transaction {
            try db.execute("DELETE FROM privacy_detected_spans WHERE content_id = ?", params: [contentID])
            for span in spans {
                try db.execute(
                    """
                    INSERT INTO privacy_detected_spans (
                        span_id, content_id, category, start_utf16, end_utf16, confidence,
                        source, placeholder, text_hash, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    params: [
                        span.id,
                        span.contentID,
                        span.category.rawValue,
                        "\(span.startUTF16)",
                        "\(span.endUTF16)",
                        span.confidence.map { String($0) },
                        span.source.rawValue,
                        span.placeholder,
                        span.textHash,
                        span.createdAt,
                    ]
                )
            }
        }
    }

    public func spans(for contentID: String) throws -> [PrivacySpanRecord] {
        try db.queryAll(
            "SELECT * FROM privacy_detected_spans WHERE content_id = ? ORDER BY start_utf16 ASC",
            params: [contentID]
        ).compactMap(Self.spanRecord(from:))
    }

    @discardableResult
    public func enqueueIndexJob(_ job: PrivacyIndexJobRecord) throws -> String {
        let existing = try db.queryAll(
            """
            SELECT * FROM privacy_index_jobs
            WHERE content_id = ? AND status IN (?, ?)
            ORDER BY
                CASE status WHEN 'running' THEN 0 ELSE 1 END,
                priority ASC,
                scheduled_at ASC
            LIMIT 1
            """,
            params: [job.contentID, PrivacyIndexJobStatus.running.rawValue, PrivacyIndexJobStatus.queued.rawValue]
        ).first

        if let existing,
           let existingID = existing["job_id"],
           let existingPriorityRaw = existing["priority"],
           let existingPriority = Int(existingPriorityRaw),
           existing["status"] == PrivacyIndexJobStatus.queued.rawValue {
            try db.execute(
                """
                UPDATE privacy_index_jobs
                SET reason = ?, priority = ?, scheduled_at = ?, last_error = NULL
                WHERE job_id = ?
                """,
                params: [
                    job.reason,
                    "\(min(existingPriority, job.priority))",
                    ISO8601DateFormatter.shared.string(from: Date()),
                    existingID,
                ]
            )
            return existingID
        }

        try db.execute(
            """
            INSERT INTO privacy_index_jobs (
                job_id, content_id, reason, priority, status, attempt_count,
                scheduled_at, started_at, finished_at, last_error
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            params: [
                job.id,
                job.contentID,
                job.reason,
                "\(job.priority)",
                job.status.rawValue,
                "\(job.attemptCount)",
                job.scheduledAt,
                job.startedAt,
                job.finishedAt,
                job.lastError,
            ]
        )
        return job.id
    }

    public func pendingIndexJobs(limit: Int) throws -> [PrivacyIndexJobRecord] {
        let rows = try db.queryAll(
            """
            SELECT * FROM privacy_index_jobs
            WHERE status = ?
            ORDER BY priority ASC, scheduled_at ASC
            LIMIT ?
            """,
            params: [PrivacyIndexJobStatus.queued.rawValue, "\(limit)"]
        )
        return rows.compactMap(Self.indexJobRecord(from:))
    }

    public func markIndexJobsRunning(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let now = ISO8601DateFormatter.shared.string(from: Date())
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        try db.execute(
            """
            UPDATE privacy_index_jobs
            SET status = ?, started_at = ?, attempt_count = attempt_count + 1, last_error = NULL
            WHERE job_id IN (\(placeholders))
            """,
            params: [PrivacyIndexJobStatus.running.rawValue, now] + ids
        )
    }

    public func markIndexJobCompleted(id: String) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            """
            UPDATE privacy_index_jobs
            SET status = ?, finished_at = ?, last_error = NULL
            WHERE job_id = ?
            """,
            params: [PrivacyIndexJobStatus.completed.rawValue, now, id]
        )
    }

    public func markIndexJobFailed(id: String, error: String) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            """
            UPDATE privacy_index_jobs
            SET status = ?, finished_at = ?, last_error = ?
            WHERE job_id = ?
            """,
            params: [PrivacyIndexJobStatus.failed.rawValue, now, error, id]
        )
    }

    public func deleteIndexJobs(for contentIDs: [String]) throws {
        guard !contentIDs.isEmpty else { return }
        let placeholders = contentIDs.map { _ in "?" }.joined(separator: ",")
        try db.execute(
            "DELETE FROM privacy_index_jobs WHERE content_id IN (\(placeholders))",
            params: contentIDs
        )
    }

    public func indexRuntimeCounters() throws -> (queued: Int, running: Int, failed: Int, indexed: Int, stale: Int) {
        (
            Int(try db.queryScalar("SELECT COUNT(*) FROM privacy_index_jobs WHERE status = '\(PrivacyIndexJobStatus.queued.rawValue)'") ?? "0") ?? 0,
            Int(try db.queryScalar("SELECT COUNT(*) FROM privacy_index_jobs WHERE status = '\(PrivacyIndexJobStatus.running.rawValue)'") ?? "0") ?? 0,
            Int(try db.queryScalar("SELECT COUNT(*) FROM privacy_index_jobs WHERE status = '\(PrivacyIndexJobStatus.failed.rawValue)'") ?? "0") ?? 0,
            Int(try db.queryScalar("SELECT COUNT(*) FROM privacy_content_index") ?? "0") ?? 0,
            Int(try db.queryScalar("SELECT COUNT(*) FROM privacy_content_index WHERE scan_status = '\(PrivacyIndexStatus.stale.rawValue)'") ?? "0") ?? 0
        )
    }

    public func acceptedIdentityCount() throws -> Int {
        Int(try db.queryScalar("SELECT COUNT(*) FROM privacy_identity_registry WHERE is_enabled = 1") ?? "0") ?? 0
    }

    private func identity(from row: [String: String]) throws -> PrivacyIdentityRecord? {
        guard let id = row["identity_id"],
              let kindRaw = row["kind"],
              let kind = PrivacyIdentityKind(rawValue: kindRaw),
              let displayName = row["display_name"],
              let cipherText = row["value_ciphertext"],
              let value = plainText(from: cipherText),
              let normalizedHash = row["normalized_hash"],
              let matchingModeRaw = row["matching_mode"],
              let matchingMode = PrivacyMatchMode(rawValue: matchingModeRaw),
              let createdAt = row["created_at"],
              let updatedAt = row["updated_at"] else {
            privacyLogger.error("Failed to decode privacy identity row")
            return nil
        }

        return PrivacyIdentityRecord(
            id: id,
            kind: kind,
            displayName: displayName,
            value: value,
            normalizedHash: normalizedHash,
            matchingMode: matchingMode,
            isEnabled: row["is_enabled"] != "0",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func identitySuggestion(from row: [String: String]) throws -> PrivacyIdentitySuggestion? {
        guard let id = row["suggestion_id"],
              let kindRaw = row["kind"],
              let kind = PrivacyIdentityKind(rawValue: kindRaw),
              let displayName = row["display_name"],
              let cipherText = row["value_ciphertext"],
              let value = plainText(from: cipherText),
              let normalizedHash = row["normalized_hash"],
              let sourceKindRaw = row["source_kind"],
              let sourceKind = PrivacySuggestionSourceKind(rawValue: sourceKindRaw),
              let confidenceRaw = row["confidence"],
              let confidence = Double(confidenceRaw),
              let statusRaw = row["status"],
              let status = PrivacySuggestionStatus(rawValue: statusRaw),
              let createdAt = row["created_at"] else {
            privacyLogger.error("Failed to decode privacy identity suggestion row")
            return nil
        }

        return PrivacyIdentitySuggestion(
            id: id,
            kind: kind,
            displayName: displayName,
            value: value,
            normalizedHash: normalizedHash,
            sourceKind: sourceKind,
            sourceRef: row["source_ref"]?.nilIfEmpty,
            confidence: confidence,
            status: status,
            createdAt: createdAt,
            reviewedAt: row["reviewed_at"]?.nilIfEmpty
        )
    }

    private static func settings(from row: [String: String]) -> PrivacyPreflightSettings? {
        guard let id = row["id"],
              let backendRaw = row["selected_backend"],
              let backend = PrivacyBackendKind.fromStoredRawValue(backendRaw),
              let installRaw = row["install_state"],
              let installState = PrivacyInstallState(rawValue: installRaw),
              let updatedAt = row["updated_at"] else {
            privacyLogger.error("Failed to decode privacy settings row")
            return nil
        }
        return PrivacyPreflightSettings(
            id: id,
            isEnabled: row["is_enabled"] == "1",
            selectedBackend: backend,
            installState: installState,
            modelVersion: row["model_version"]?.nilIfEmpty,
            storagePath: row["storage_path"]?.nilIfEmpty,
            installedAt: row["installed_at"]?.nilIfEmpty,
            cacheEnabled: row["cache_enabled"] != "0",
            unloadOnMemoryPressure: row["unload_on_memory_pressure"] != "0",
            updatedAt: updatedAt
        )
    }

    private static func policy(from row: [String: String]) -> AgentPrivacyPolicy? {
        guard let id = row["policy_id"],
              let agentRaw = row["agent"],
              let agent = TargetApp(rawValue: agentRaw),
              let textHandlingRaw = row["text_handling"],
              let textHandling = PrivacyHandlingMode(rawValue: textHandlingRaw),
              let codeHandlingRaw = row["code_handling"],
              let codeHandling = PrivacyHandlingMode(rawValue: codeHandlingRaw),
              let secretHandlingRaw = row["secret_handling"],
              let secretHandling = PrivacySecretHandling(rawValue: secretHandlingRaw),
              let updatedAt = row["updated_at"] else {
            privacyLogger.error("Failed to decode agent privacy policy row")
            return nil
        }
        let categories: [PrivacyCategory] = decode(row["enabled_categories_json"]) ?? PrivacyCategory.allCases
        return AgentPrivacyPolicy(
            id: id,
            agent: agent,
            textHandling: textHandling,
            codeHandling: codeHandling,
            secretHandling: secretHandling,
            enabledCategories: Set(categories),
            updatedAt: updatedAt
        )
    }

    private static func cachedResult(from row: [String: String]) -> PrivacyScanResult? {
        guard let backendRaw = row["backend"],
              let backend = PrivacyBackendKind.fromStoredRawValue(backendRaw),
              let modelVersion = row["model_version"],
              let redactedText = row["redacted_text"],
              let findingsSummary = row["findings_summary"],
              let elapsedRaw = row["elapsed_ms"],
              let elapsedMs = Int(elapsedRaw) else {
            privacyLogger.error("Failed to decode privacy cache row")
            return nil
        }
        let spans: [DetectedSpan] = decode(row["spans_json"]) ?? []
        return PrivacyScanResult(
            spans: spans,
            redactedText: redactedText,
            findingsSummary: findingsSummary,
            backend: backend,
            modelVersion: modelVersion,
            elapsedMs: elapsedMs,
            cacheHit: true
        )
    }

    private static func orgAllowEntry(from row: [String: String]) -> PrivacyOrgAllowEntry? {
        guard let id = row["allow_id"],
              let kindRaw = row["kind"],
              let kind = PrivacyOrgAllowKind(rawValue: kindRaw),
              let pattern = row["pattern"],
              let matchModeRaw = row["match_mode"],
              let matchMode = PrivacyMatchMode(rawValue: matchModeRaw),
              let source = row["source"],
              let createdAt = row["created_at"],
              let updatedAt = row["updated_at"] else {
            privacyLogger.error("Failed to decode privacy org allowlist row")
            return nil
        }

        return PrivacyOrgAllowEntry(
            id: id,
            kind: kind,
            pattern: pattern,
            matchMode: matchMode,
            source: source,
            isEnabled: row["is_enabled"] != "0",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func contentIndexRecord(from row: [String: String]) -> PrivacyIndexRecord? {
        guard let id = row["content_id"],
              let subjectKindRaw = row["subject_kind"],
              let subjectKind = PrivacyIndexedContentKind(rawValue: subjectKindRaw),
              let displayName = row["display_name"],
              let extractStatusRaw = row["extract_status"],
              let extractStatus = PrivacyExtractStatus(rawValue: extractStatusRaw),
              let scanStatusRaw = row["scan_status"],
              let scanStatus = PrivacyIndexStatus(rawValue: scanStatusRaw),
              let severityRaw = row["severity"],
              let severity = PrivacySeverity(rawValue: severityRaw),
              let findingsSummary = row["findings_summary"],
              let spanCountRaw = row["span_count"],
              let spanCount = Int(spanCountRaw),
              let updatedAt = row["updated_at"] else {
            privacyLogger.error("Failed to decode privacy content index row")
            return nil
        }

        return PrivacyIndexRecord(
            id: id,
            subjectKind: subjectKind,
            sourceID: row["source_id"]?.nilIfEmpty,
            relativePath: row["relative_path"]?.nilIfEmpty,
            emailID: row["email_id"]?.nilIfEmpty,
            attachmentID: row["attachment_id"]?.nilIfEmpty,
            parentContentID: row["parent_content_id"]?.nilIfEmpty,
            displayName: displayName,
            mimeType: row["mime_type"]?.nilIfEmpty,
            extractor: row["extractor"]?.nilIfEmpty,
            extractStatus: extractStatus,
            scanStatus: scanStatus,
            contentHash: row["content_hash"]?.nilIfEmpty,
            backend: row["backend"].flatMap(PrivacyBackendKind.fromStoredRawValue),
            modelVersion: row["model_version"]?.nilIfEmpty,
            containsSensitive: row["contains_sensitive"] == "1",
            containsMyInfo: row["contains_my_info"] == "1",
            containsThirdPartyPrivate: row["contains_third_party_private"] == "1",
            containsSecret: row["contains_secret"] == "1",
            containsOrgOnly: row["contains_org_only"] == "1",
            severity: severity,
            matchedCategories: decode(row["matched_categories_json"]) ?? [],
            matchedIdentityIDs: decode(row["matched_identity_ids_json"]) ?? [],
            matchedAllowIDs: decode(row["matched_allow_ids_json"]) ?? [],
            redactedPreview: row["redacted_preview"]?.nilIfEmpty,
            findingsSummary: findingsSummary,
            spanCount: spanCount,
            lastScannedAt: row["last_scanned_at"]?.nilIfEmpty,
            updatedAt: updatedAt,
            lastError: row["last_error"]?.nilIfEmpty
        )
    }

    private static func spanRecord(from row: [String: String]) -> PrivacySpanRecord? {
        guard let id = row["span_id"],
              let contentID = row["content_id"],
              let categoryRaw = row["category"],
              let category = PrivacyCategory(rawValue: categoryRaw),
              let startRaw = row["start_utf16"],
              let startUTF16 = Int(startRaw),
              let endRaw = row["end_utf16"],
              let endUTF16 = Int(endRaw),
              let sourceRaw = row["source"],
              let source = PrivacySpanSource(rawValue: sourceRaw),
              let createdAt = row["created_at"] else {
            privacyLogger.error("Failed to decode privacy span row")
            return nil
        }

        return PrivacySpanRecord(
            id: id,
            contentID: contentID,
            category: category,
            startUTF16: startUTF16,
            endUTF16: endUTF16,
            confidence: row["confidence"].flatMap(Double.init),
            source: source,
            placeholder: row["placeholder"]?.nilIfEmpty,
            textHash: row["text_hash"]?.nilIfEmpty,
            createdAt: createdAt
        )
    }

    private static func indexJobRecord(from row: [String: String]) -> PrivacyIndexJobRecord? {
        guard let id = row["job_id"],
              let contentID = row["content_id"],
              let reason = row["reason"],
              let priorityRaw = row["priority"],
              let priority = Int(priorityRaw),
              let statusRaw = row["status"],
              let status = PrivacyIndexJobStatus(rawValue: statusRaw),
              let attemptsRaw = row["attempt_count"],
              let attemptCount = Int(attemptsRaw),
              let scheduledAt = row["scheduled_at"] else {
            privacyLogger.error("Failed to decode privacy job row")
            return nil
        }

        return PrivacyIndexJobRecord(
            id: id,
            contentID: contentID,
            reason: reason,
            priority: priority,
            status: status,
            attemptCount: attemptCount,
            scheduledAt: scheduledAt,
            startedAt: row["started_at"]?.nilIfEmpty,
            finishedAt: row["finished_at"]?.nilIfEmpty,
            lastError: row["last_error"]?.nilIfEmpty
        )
    }

    private func appendBooleanFilter(
        _ value: Bool?,
        column: String,
        to whereClauses: inout [String],
        params: inout [String?]
    ) {
        guard let value else { return }
        whereClauses.append("\(column) = ?")
        params.append(value ? "1" : "0")
    }

    private func cipherText(for plaintext: String) throws -> String {
        let encrypted = try ProtectedStorageCrypto.encrypt(Data(plaintext.utf8))
        return encrypted.base64EncodedString()
    }

    private func plainText(from raw: String) -> String? {
        if let data = Data(base64Encoded: raw),
           let decrypted = try? ProtectedStorageCrypto.decrypt(data) {
            return String(data: decrypted, encoding: .utf8)
        }
        return raw
    }

    private static func normalizedHash(kind: PrivacyIdentityKind, value: String) -> String {
        let normalized = normalizedValue(kind: kind, value: value)
        return SHA256.hash(data: Data(normalized.utf8)).hexString
    }

    private static func normalizedValue(kind: PrivacyIdentityKind, value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .email, .url:
            return trimmed.lowercased()
        case .phone:
            return trimmed.filter(\.isNumber)
        case .accountNumber:
            return trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
        case .personName, .address, .secret:
            return trimmed
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return string
    }

    private static func decode<T: Decodable>(_ raw: String?) -> T? {
        guard let raw, !raw.isEmpty, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
