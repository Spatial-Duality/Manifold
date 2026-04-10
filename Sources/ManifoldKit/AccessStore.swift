import Foundation

public struct AccessPresetSnapshot: Sendable {
    public let preset: AccessPresetRecord
    public let fileScopes: [FileSelectionScope]
    public let emailIDs: [String]

    public init(
        preset: AccessPresetRecord,
        fileScopes: [FileSelectionScope],
        emailIDs: [String]
    ) {
        self.preset = preset
        self.fileScopes = fileScopes
        self.emailIDs = emailIDs
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

    public func loadPreset(id: String) throws -> AccessPresetSnapshot? {
        let rows = try db.queryAll(
            "SELECT * FROM access_presets WHERE preset_id = ? LIMIT 1",
            params: [id]
        )
        guard let preset = rows.first.flatMap({ AccessPresetRecord(row: $0) }) else {
            return nil
        }

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
        return AccessPresetSnapshot(preset: preset, fileScopes: fileScopes, emailIDs: emailIDs)
    }

    @discardableResult
    public func savePreset(
        id: String? = nil,
        name: String,
        fileScopes: [FileSelectionScope],
        emailIDs: [String]
    ) throws -> AccessPresetRecord {
        let presetID = id ?? "preset-\(UUID().uuidString.prefix(8).lowercased())"
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try db.transaction {
            if id == nil {
                try db.execute(
                    """
                    INSERT INTO access_presets (preset_id, name, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    params: [presetID, name, now, now]
                )
            } else {
                try db.execute(
                    """
                    UPDATE access_presets SET name = ?, updated_at = ?
                    WHERE preset_id = ?
                    """,
                    params: [name, now, presetID]
                )
                try db.execute(
                    "DELETE FROM access_preset_file_scopes WHERE preset_id = ?",
                    params: [presetID]
                )
                try db.execute(
                    "DELETE FROM access_preset_emails WHERE preset_id = ?",
                    params: [presetID]
                )
            }

            for scope in fileScopes {
                try db.execute(
                    """
                    INSERT INTO access_preset_file_scopes (
                        preset_id, source_id, relative_path, is_directory
                    ) VALUES (?, ?, ?, ?)
                    """,
                    params: [presetID, scope.sourceID, scope.normalizedRelativePath, scope.isDirectory ? "1" : "0"]
                )
            }

            for emailID in Set(emailIDs) {
                try db.execute(
                    """
                    INSERT INTO access_preset_emails (preset_id, email_id)
                    VALUES (?, ?)
                    """,
                    params: [presetID, emailID]
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

    public func deletePreset(id: String) throws {
        try db.transaction {
            try db.execute("DELETE FROM access_preset_file_scopes WHERE preset_id = ?", params: [id])
            try db.execute("DELETE FROM access_preset_emails WHERE preset_id = ?", params: [id])
            try db.execute("DELETE FROM access_presets WHERE preset_id = ?", params: [id])
        }
    }
}
