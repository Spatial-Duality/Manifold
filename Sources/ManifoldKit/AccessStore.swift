// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Full materialized state of one Focus (named access preset). Carries
/// scope, email scope, per-Focus per-file overrides, and the settings the
/// new grant should be started with. Returned by `loadPreset`; rebuilt by
/// `savePreset` on every save so callers always see canonical state.
public struct AccessPresetSnapshot: Sendable {
    public let preset: AccessPresetRecord
    public let fileScopes: [FileSelectionScope]
    public let emailIDs: [String]
    public let overrides: [FileVisibilityOverrideRecord]

    public init(
        preset: AccessPresetRecord,
        fileScopes: [FileSelectionScope],
        emailIDs: [String],
        overrides: [FileVisibilityOverrideRecord] = []
    ) {
        self.preset = preset
        self.fileScopes = fileScopes
        self.emailIDs = emailIDs
        self.overrides = overrides
    }
}

public actor AccessStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    public func allPresets() throws -> [AccessPresetRecord] {
        let rows = try db.queryAll(
            "SELECT * FROM access_presets ORDER BY updated_at DESC, name ASC"
        )
        return rows.compactMap { AccessPresetRecord(row: $0) }
    }

    /// Presets visible to a specific agent — either scoped to that agent or
    /// unscoped (legacy presets with NULL `target_app`). Used to populate
    /// the SESSIONS sidebar section per agent.
    public func templatesForAgent(_ agent: TargetApp) throws -> [AccessPresetRecord] {
        let rows = try db.queryAll(
            """
            SELECT * FROM access_presets
            WHERE target_app = ? OR target_app IS NULL OR target_app = ''
            ORDER BY updated_at DESC, name ASC
            """,
            params: [agent.rawValue]
        )
        return rows.compactMap { AccessPresetRecord(row: $0) }
    }

    public func loadPreset(id: String) throws -> AccessPresetSnapshot? {
        let rows = try db.queryAll(
            "SELECT * FROM access_presets WHERE preset_id = ? LIMIT 1",
            params: [id]
        )
        guard let preset = rows.first.flatMap({ AccessPresetRecord(row: $0) }) else {
            return nil
        }

        // Snapshot returns the UNION of scope/email/override rows
        // regardless of agent column. Useful for "what does this Focus
        // contain" displays. The activation pipeline uses
        // `fileScopes(presetID:agent:)` and `presetOverrides(presetID:agent:)`
        // to get per-agent filtered rows.
        let fileScopeRows = try db.queryAll(
            """
            SELECT source_id, relative_path, is_directory
            FROM access_preset_file_scopes
            WHERE preset_id = ?
            ORDER BY source_id ASC, relative_path ASC
            """,
            params: [id]
        )
        let fileScopes = fileScopeRows.compactMap { row -> FileSelectionScope? in
            guard let sourceID = row["source_id"],
                  let relativePath = row["relative_path"] else {
                return nil
            }
            return FileSelectionScope(
                sourceID: sourceID,
                relativePath: relativePath,
                isDirectory: row["is_directory"] == "1"
            )
        }

        let emailRows = try db.queryAll(
            """
            SELECT email_id
            FROM access_preset_emails
            WHERE preset_id = ?
            ORDER BY email_id ASC
            """,
            params: [id]
        )
        let emailIDs = emailRows.compactMap { $0["email_id"] }

        let overrides = try presetOverrides(presetID: id, agent: preset.targetApp ?? .cowork)
        return AccessPresetSnapshot(
            preset: preset,
            fileScopes: fileScopes,
            emailIDs: emailIDs,
            overrides: overrides
        )
    }

    /// Per-agent file scopes for activation. Returns rows where
    /// `agent=''` (mirror-mode rows that apply to every activated agent)
    /// PLUS rows where `agent` matches the requested agent. Mirror-mode
    /// presets see only the empty-agent rows; separate-sharing presets
    /// see only their per-agent rows.
    public func fileScopes(presetID: String, agent: TargetApp) throws -> [FileSelectionScope] {
        let rows = try db.queryAll(
            """
            SELECT source_id, relative_path, is_directory
            FROM access_preset_file_scopes
            WHERE preset_id = ? AND (agent = '' OR agent = ?)
            ORDER BY source_id ASC, relative_path ASC
            """,
            params: [presetID, agent.rawValue]
        )
        return rows.compactMap { row in
            guard let sourceID = row["source_id"],
                  let relativePath = row["relative_path"] else {
                return nil
            }
            return FileSelectionScope(
                sourceID: sourceID,
                relativePath: relativePath,
                isDirectory: row["is_directory"] == "1"
            )
        }
    }

    /// Per-agent email IDs for activation, same agent='' OR agent=target
    /// semantics as `fileScopes(presetID:agent:)`.
    public func emailIDs(presetID: String, agent: TargetApp) throws -> [String] {
        let rows = try db.queryAll(
            """
            SELECT email_id FROM access_preset_emails
            WHERE preset_id = ? AND (agent = '' OR agent = ?)
            ORDER BY email_id ASC
            """,
            params: [presetID, agent.rawValue]
        )
        return rows.compactMap { $0["email_id"] }
    }

    /// Insert or update a preset with full state. Frequent calls with the
    /// same `id` are safe — the implementation deletes-and-reinserts the
    /// scope / email / override children inside a single transaction.
    ///
    /// `mirrorToBoth=true` (default) writes scope + email rows with
    /// agent='' (= "applies to both AIs"). Pass `mirrorToBoth=false`
    /// alongside the per-agent overload of `updatePresetFileScopesByAgent`
    /// to manage per-agent rows explicitly. The simple path here writes
    /// agent='' for everything — fine for mirror-mode Focuses and the
    /// initial create flow.
    @discardableResult
    public func savePreset(
        id: String? = nil,
        name: String,
        targetApp: TargetApp? = nil,
        fileScopes: [FileSelectionScope],
        emailIDs: [String],
        requestDetailLevel: AccessRecordingLevel? = nil,
        noteCaptureMode: SessionNoteCaptureMode? = nil,
        allowFileMemory: Bool = false,
        summaryFraming: String? = nil,
        emailSensitivity: EmailSensitivityLevel? = nil,
        mirrorToBoth: Bool = true,
        isBuiltIn: Bool = false,
        overrides: [FileVisibilityOverrideRecord] = []
    ) throws -> AccessPresetRecord {
        let presetID = id ?? "preset-\(UUID().uuidString.prefix(8).lowercased())"
        let now = ISO8601DateFormatter.shared.string(from: Date())
        let targetAppValue = targetApp?.rawValue ?? ""
        let requestDetail = requestDetailLevel?.rawValue ?? ""
        let noteCapture = noteCaptureMode?.rawValue ?? ""
        let summary = summaryFraming ?? ""
        let sensitivity = emailSensitivity?.rawValue ?? ""
        let mirrorValue = mirrorToBoth ? "1" : "0"
        let builtInValue = isBuiltIn ? "1" : "0"

        try db.transaction {
            if id == nil {
                try db.execute(
                    """
                    INSERT INTO access_presets (
                        preset_id, name, target_app,
                        request_detail_level, note_capture_mode, allow_file_memory,
                        summary_framing, email_sensitivity,
                        is_default_at_launch,
                        mirror_to_both, is_built_in,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)
                    """,
                    params: [
                        presetID, name, targetAppValue,
                        requestDetail, noteCapture, allowFileMemory ? "1" : "0",
                        summary, sensitivity,
                        mirrorValue, builtInValue,
                        now, now,
                    ]
                )
            } else {
                // Settings columns are written every UPDATE so the saved row
                // always matches the active Focus state. is_default_at_launch
                // is intentionally NOT touched here — set it via
                // setDefaultAtLaunch(presetID:for:) which enforces the ≤1
                // invariant per target_app.
                try db.execute(
                    """
                    UPDATE access_presets SET
                        name = ?, target_app = ?,
                        request_detail_level = ?, note_capture_mode = ?, allow_file_memory = ?,
                        summary_framing = ?, email_sensitivity = ?,
                        mirror_to_both = ?, is_built_in = ?,
                        updated_at = ?
                    WHERE preset_id = ?
                    """,
                    params: [
                        name, targetAppValue,
                        requestDetail, noteCapture, allowFileMemory ? "1" : "0",
                        summary, sensitivity,
                        mirrorValue, builtInValue,
                        now, presetID,
                    ]
                )
                try db.execute(
                    "DELETE FROM access_preset_file_scopes WHERE preset_id = ?",
                    params: [presetID]
                )
                try db.execute(
                    "DELETE FROM access_preset_emails WHERE preset_id = ?",
                    params: [presetID]
                )
                try db.execute(
                    "DELETE FROM access_preset_overrides WHERE preset_id = ?",
                    params: [presetID]
                )
            }

            // Mirror-mode write path: agent='' so the activation pipeline
            // copies the same scope onto each agent it activates. Per-agent
            // rows (mirror_to_both=false) are written via the dedicated
            // updatePresetFileScopesByAgent / setPresetOverride(agent:)
            // overloads, not this method.
            for scope in fileScopes {
                try db.execute(
                    """
                    INSERT INTO access_preset_file_scopes (
                        preset_id, source_id, relative_path, is_directory, agent
                    ) VALUES (?, ?, ?, ?, '')
                    """,
                    params: [presetID, scope.sourceID, scope.normalizedRelativePath, scope.isDirectory ? "1" : "0"]
                )
            }

            for emailID in Set(emailIDs) {
                try db.execute(
                    """
                    INSERT INTO access_preset_emails (preset_id, email_id, agent)
                    VALUES (?, ?, '')
                    """,
                    params: [presetID, emailID]
                )
            }

            for override in overrides {
                try db.execute(
                    """
                    INSERT OR REPLACE INTO access_preset_overrides (
                        preset_id, source_id, relative_path, is_directory, decision, agent
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    params: [
                        presetID,
                        override.sourceID,
                        override.relativePath,
                        override.isDirectory ? "1" : "0",
                        override.decision.rawValue,
                        override.agent.rawValue,
                    ]
                )
            }
        }

        let rows = try db.queryAll(
            "SELECT * FROM access_presets WHERE preset_id = ? LIMIT 1",
            params: [presetID]
        )
        guard let preset = rows.first.flatMap({ AccessPresetRecord(row: $0) }) else {
            throw ManifoldError.database("Preset \(presetID) not found after save")
        }
        return preset
    }

    /// Patch the mirror_to_both flag on a Focus without touching scope
    /// or settings. Hot path for the "Separate sharing" toggle.
    @discardableResult
    public func updatePresetMirror(presetID: String, mirrorToBoth: Bool) throws -> AccessPresetRecord {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            """
            UPDATE access_presets SET mirror_to_both = ?, updated_at = ?
            WHERE preset_id = ?
            """,
            params: [mirrorToBoth ? "1" : "0", now, presetID]
        )
        let rows = try db.queryAll(
            "SELECT * FROM access_presets WHERE preset_id = ? LIMIT 1",
            params: [presetID]
        )
        guard let preset = rows.first.flatMap({ AccessPresetRecord(row: $0) }) else {
            throw ManifoldError.database("Preset \(presetID) not found after mirror patch")
        }
        return preset
    }

    /// Patch target_app on a Focus. Used by the Apply-to picker.
    @discardableResult
    public func updatePresetTargetApp(presetID: String, targetApp: TargetApp?) throws -> AccessPresetRecord {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            """
            UPDATE access_presets SET target_app = ?, updated_at = ?
            WHERE preset_id = ?
            """,
            params: [targetApp?.rawValue ?? "", now, presetID]
        )
        let rows = try db.queryAll(
            "SELECT * FROM access_presets WHERE preset_id = ? LIMIT 1",
            params: [presetID]
        )
        guard let preset = rows.first.flatMap({ AccessPresetRecord(row: $0) }) else {
            throw ManifoldError.database("Preset \(presetID) not found after target_app patch")
        }
        return preset
    }

    /// Settings-only patch. Cheap path the auto-save fan-out hits on every
    /// edit of memory / detail / note-capture etc. while a Focus is active
    /// — avoids the full delete-and-reinsert of `savePreset`.
    @discardableResult
    public func updatePresetSettings(
        presetID: String,
        requestDetailLevel: AccessRecordingLevel?,
        noteCaptureMode: SessionNoteCaptureMode?,
        allowFileMemory: Bool,
        summaryFraming: String?,
        emailSensitivity: EmailSensitivityLevel?
    ) throws -> AccessPresetRecord {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.execute(
            """
            UPDATE access_presets SET
                request_detail_level = ?, note_capture_mode = ?, allow_file_memory = ?,
                summary_framing = ?, email_sensitivity = ?,
                updated_at = ?
            WHERE preset_id = ?
            """,
            params: [
                requestDetailLevel?.rawValue ?? "",
                noteCaptureMode?.rawValue ?? "",
                allowFileMemory ? "1" : "0",
                summaryFraming ?? "",
                emailSensitivity?.rawValue ?? "",
                now,
                presetID,
            ]
        )
        let rows = try db.queryAll(
            "SELECT * FROM access_presets WHERE preset_id = ? LIMIT 1",
            params: [presetID]
        )
        guard let preset = rows.first.flatMap({ AccessPresetRecord(row: $0) }) else {
            throw ManifoldError.database("Preset \(presetID) not found after settings update")
        }
        return preset
    }

    /// Replace the file scope list for an existing preset in one
    /// transaction. `agent: nil` writes mirror-mode rows (agent=''),
    /// replacing only the existing mirror-mode rows for this preset.
    /// Pass an explicit agent to write that agent's rows only,
    /// preserving the other agent's rows. This is the primary write
    /// path for the auto-save fan-out (mirror mode) and the
    /// separate-sharing matrix UI (per-agent).
    public func updatePresetFileScopes(
        presetID: String,
        fileScopes: [FileSelectionScope],
        agent: TargetApp? = nil
    ) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        let agentValue = agent?.rawValue ?? ""
        try db.transaction {
            try db.execute(
                """
                DELETE FROM access_preset_file_scopes
                WHERE preset_id = ? AND agent = ?
                """,
                params: [presetID, agentValue]
            )
            for scope in fileScopes {
                try db.execute(
                    """
                    INSERT INTO access_preset_file_scopes (
                        preset_id, source_id, relative_path, is_directory, agent
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    params: [presetID, scope.sourceID, scope.normalizedRelativePath, scope.isDirectory ? "1" : "0", agentValue]
                )
            }
            try db.execute(
                "UPDATE access_presets SET updated_at = ? WHERE preset_id = ?",
                params: [now, presetID]
            )
        }
    }

    // MARK: - Per-preset overrides

    /// Read the per-Focus per-file overrides for a preset. The `agent` is
    /// stamped onto the returned records (the table itself doesn't store
    /// it because overrides are scoped to the preset's `target_app`); this
    /// keeps `FileVisibilityOverrideRecord` interchangeable with the
    /// agent-keyed versions in `FileVisibilityOverrideStore`.
    /// Read overrides for a preset filtered to one agent. Rows with
    /// `agent=''` (mirror-mode) match every agent; rows with explicit
    /// `agent='cowork'|'codex'` match only that agent. The returned
    /// records are stamped with the requested agent so the runtime can
    /// pass them through `FileVisibilityOverrideStore.setManyOverrides`
    /// without re-keying.
    public func presetOverrides(presetID: String, agent: TargetApp) throws -> [FileVisibilityOverrideRecord] {
        let rows = try db.queryAll(
            """
            SELECT source_id, relative_path, is_directory, decision
            FROM access_preset_overrides
            WHERE preset_id = ? AND (agent = '' OR agent = ?)
            ORDER BY source_id ASC, relative_path ASC
            """,
            params: [presetID, agent.rawValue]
        )
        return rows.compactMap { row -> FileVisibilityOverrideRecord? in
            guard let sourceID = row["source_id"],
                  let relativePath = row["relative_path"],
                  let decisionRaw = row["decision"],
                  let decision = FileVisibilityOverrideDecision(rawValue: decisionRaw) else {
                return nil
            }
            return FileVisibilityOverrideRecord(
                agent: agent,
                sourceID: sourceID,
                relativePath: relativePath,
                isDirectory: row["is_directory"] == "1",
                decision: decision
            )
        }
    }

    /// Full-replace the per-Focus override set in one transaction. Mirrors
    /// `FileVisibilityOverrideStore.setManyOverrides` semantics.
    ///
    /// Each record's `agent` field is honored when writing — `agent=''`
    /// to match the FileVisibilityOverrideRecord init lets you write
    /// "applies to both" rows; explicit agents write per-agent rows.
    /// To preserve existing call sites that don't think about per-agent
    /// scope, the default `mirrorMode` parameter writes everything with
    /// agent='' (matches v43 behavior).
    public func savePresetOverrides(
        presetID: String,
        overrides: [FileVisibilityOverrideRecord],
        mirrorMode: Bool = true
    ) throws {
        try db.transaction {
            try db.execute(
                "DELETE FROM access_preset_overrides WHERE preset_id = ?",
                params: [presetID]
            )
            for override in overrides {
                let agentValue = mirrorMode ? "" : override.agent.rawValue
                try db.execute(
                    """
                    INSERT OR REPLACE INTO access_preset_overrides (
                        preset_id, source_id, relative_path, is_directory, decision, agent
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    params: [
                        presetID,
                        override.sourceID,
                        override.relativePath,
                        override.isDirectory ? "1" : "0",
                        override.decision.rawValue,
                        agentValue,
                    ]
                )
            }
            let now = ISO8601DateFormatter.shared.string(from: Date())
            try db.execute(
                "UPDATE access_presets SET updated_at = ? WHERE preset_id = ?",
                params: [now, presetID]
            )
        }
    }

    /// Patch one override into a Focus's record. `agent: nil` writes a
    /// mirror-mode row (agent=''); passing an agent writes a per-agent
    /// row. The unique key is (preset, source, path, isDir) so an
    /// agent='' row and an agent='cowork' row are *different* rows; the
    /// caller is responsible for picking the right one.
    public func setPresetOverride(
        presetID: String,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool,
        decision: FileVisibilityOverrideDecision,
        agent: TargetApp? = nil
    ) throws {
        let agentValue = agent?.rawValue ?? ""
        try db.execute(
            """
            INSERT OR REPLACE INTO access_preset_overrides (
                preset_id, source_id, relative_path, is_directory, decision, agent
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            params: [presetID, sourceID, relativePath, isDirectory ? "1" : "0", decision.rawValue, agentValue]
        )
    }

    /// Remove one override from a Focus's record. `agent: nil` removes
    /// the mirror-mode row only; passing an agent removes that agent's
    /// row only.
    public func clearPresetOverride(
        presetID: String,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool,
        agent: TargetApp? = nil
    ) throws {
        let agentValue = agent?.rawValue ?? ""
        try db.execute(
            """
            DELETE FROM access_preset_overrides
            WHERE preset_id = ? AND source_id = ? AND relative_path = ?
              AND is_directory = ? AND agent = ?
            """,
            params: [presetID, sourceID, relativePath, isDirectory ? "1" : "0", agentValue]
        )
    }

    // MARK: - Default-at-launch

    /// Mark a preset as the default-at-launch for its target agent. Pass
    /// `nil` to clear the existing default for that agent. Enforces the
    /// invariant that at most one preset per `target_app` may carry the
    /// flag, by clearing all sibling flags inside a single transaction.
    public func setDefaultAtLaunch(presetID: String?, for agent: TargetApp) throws {
        try db.transaction {
            // Clear any existing default for this agent (or any default
            // when the new value is nil — same path).
            try db.execute(
                """
                UPDATE access_presets SET is_default_at_launch = 0
                WHERE is_default_at_launch = 1 AND (target_app = ? OR target_app IS NULL OR target_app = '')
                """,
                params: [agent.rawValue]
            )
            if let presetID {
                try db.execute(
                    """
                    UPDATE access_presets SET is_default_at_launch = 1
                    WHERE preset_id = ?
                    """,
                    params: [presetID]
                )
            }
        }
    }

    /// Look up the preset (if any) flagged as default-at-launch for an
    /// agent. Used by the runtime startup path to decide whether to
    /// auto-activate a Focus.
    public func defaultPresetForLaunch(agent: TargetApp) throws -> AccessPresetRecord? {
        let rows = try db.queryAll(
            """
            SELECT * FROM access_presets
            WHERE is_default_at_launch = 1
              AND (target_app = ? OR target_app IS NULL OR target_app = '')
            LIMIT 1
            """,
            params: [agent.rawValue]
        )
        return rows.first.flatMap { AccessPresetRecord(row: $0) }
    }

    public func deletePreset(id: String) throws {
        // Built-in Focuses (Default, Locked Down) cannot be deleted by
        // the user — only renamed. The runtime re-seeds them on next
        // launch anyway, so deletion would be cosmetic at best and
        // confusing at worst.
        let rows = try db.queryAll(
            "SELECT is_built_in FROM access_presets WHERE preset_id = ? LIMIT 1",
            params: [id]
        )
        if let row = rows.first, row["is_built_in"] == "1" {
            throw ManifoldError.invalidState("Cannot delete a built-in Focus")
        }
        try db.transaction {
            // Children clean up via ON DELETE CASCADE for access_preset_overrides;
            // the older two children predate cascade and we delete explicitly.
            try db.execute("DELETE FROM access_preset_file_scopes WHERE preset_id = ?", params: [id])
            try db.execute("DELETE FROM access_preset_emails WHERE preset_id = ?", params: [id])
            try db.execute("DELETE FROM access_preset_overrides WHERE preset_id = ?", params: [id])
            try db.execute("DELETE FROM access_presets WHERE preset_id = ?", params: [id])
        }
    }
}
