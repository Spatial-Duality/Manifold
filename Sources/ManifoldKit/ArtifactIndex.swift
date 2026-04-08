import Foundation
import CryptoKit

public struct ArtifactMount: Sendable, Hashable {
    public let sourceID: String
    public let mountName: String
    public let mountPath: String

    public init(sourceID: String, mountName: String, mountPath: String) {
        self.sourceID = sourceID
        self.mountName = mountName
        self.mountPath = mountPath
    }
}

public enum ArtifactKind: String, Sendable, Hashable {
    case file = "file"
    case directory = "directory"
    case archiveEntry = "archive_entry"
    case email = "email"
    case emailAttachment = "email_attachment"
    case sessionSummary = "session_summary"
}

public struct ArtifactSelection: Sendable, Hashable, Codable {
    public let lineStart: Int?
    public let lineEnd: Int?
    public let byteStart: Int?
    public let byteEnd: Int?
    public let childEntry: String?

    public init(
        lineStart: Int? = nil,
        lineEnd: Int? = nil,
        byteStart: Int? = nil,
        byteEnd: Int? = nil,
        childEntry: String? = nil
    ) {
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.byteStart = byteStart
        self.byteEnd = byteEnd
        self.childEntry = childEntry
    }
}

public struct ArtifactHandle: Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: ArtifactKind
    public let sourceID: String
    public let mountName: String
    public let path: String
    public let absolutePath: String
    public let hash: String?
    public let sizeBytes: Int
    public let tokenEstimate: Int
    public let lineCount: Int
    public let parentPath: String?
    public let selection: ArtifactSelection?
    public let lastModified: String
    public let fileExtension: String
    public let isBinary: Bool
    public let preview: String?

    public init(
        id: String,
        kind: ArtifactKind,
        sourceID: String,
        mountName: String,
        path: String,
        absolutePath: String,
        hash: String?,
        sizeBytes: Int,
        tokenEstimate: Int,
        lineCount: Int,
        parentPath: String?,
        selection: ArtifactSelection?,
        lastModified: String,
        fileExtension: String,
        isBinary: Bool,
        preview: String?
    ) {
        self.id = id
        self.kind = kind
        self.sourceID = sourceID
        self.mountName = mountName
        self.path = path
        self.absolutePath = absolutePath
        self.hash = hash
        self.sizeBytes = sizeBytes
        self.tokenEstimate = tokenEstimate
        self.lineCount = lineCount
        self.parentPath = parentPath
        self.selection = selection
        self.lastModified = lastModified
        self.fileExtension = fileExtension
        self.isBinary = isBinary
        self.preview = preview
    }

    init?(row: [String: String], selection: ArtifactSelection? = nil) {
        guard let id = row["artifact_id"],
              let kindRaw = row["kind"],
              let kind = ArtifactKind(rawValue: kindRaw),
              let sourceID = row["source_id"],
              let mountName = row["mount_name"],
              let path = row["canonical_path"],
              let absolutePath = row["absolute_path"] else {
            return nil
        }
        self.id = id
        self.kind = kind
        self.sourceID = sourceID
        self.mountName = mountName
        self.path = path
        self.absolutePath = absolutePath
        self.hash = row["content_hash"]?.nilIfEmpty
        self.sizeBytes = Int(row["size_bytes"] ?? "0") ?? 0
        self.tokenEstimate = Int(row["token_estimate"] ?? "0") ?? 0
        self.lineCount = Int(row["line_count"] ?? "0") ?? 0
        self.parentPath = row["parent_path"]?.nilIfEmpty
        self.selection = selection
        self.lastModified = row["last_modified"] ?? ""
        self.fileExtension = row["file_extension"] ?? ""
        self.isBinary = row["is_binary"] == "1"
        self.preview = row["preview"]?.nilIfEmpty
    }

    public func withSelection(_ selection: ArtifactSelection?) -> ArtifactHandle {
        ArtifactHandle(
            id: id,
            kind: kind,
            sourceID: sourceID,
            mountName: mountName,
            path: path,
            absolutePath: absolutePath,
            hash: hash,
            sizeBytes: sizeBytes,
            tokenEstimate: tokenEstimate,
            lineCount: lineCount,
            parentPath: parentPath,
            selection: selection,
            lastModified: lastModified,
            fileExtension: fileExtension,
            isBinary: isBinary,
            preview: preview
        )
    }
}

public struct SearchHit: Sendable, Hashable {
    public let handle: ArtifactHandle
    public let preview: [String]
    public let score: Double
    public let selection: ArtifactSelection?

    public init(handle: ArtifactHandle, preview: [String], score: Double, selection: ArtifactSelection?) {
        self.handle = handle
        self.preview = preview
        self.score = score
        self.selection = selection
    }
}

private struct IndexedSearchCandidate: Sendable {
    let handle: ArtifactHandle
    let snippet: String?
    let score: Double
}

public actor ArtifactIndex {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) throws {
        self.db = db
        try db.execute("""
            CREATE TABLE IF NOT EXISTS artifact_index_state (
                grant_id TEXT PRIMARY KEY,
                materialization_root TEXT NOT NULL,
                indexed_at TEXT NOT NULL
            )
        """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS artifact_index (
                artifact_id TEXT PRIMARY KEY,
                grant_id TEXT NOT NULL,
                source_id TEXT NOT NULL,
                mount_name TEXT NOT NULL,
                kind TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                canonical_path TEXT NOT NULL,
                absolute_path TEXT NOT NULL,
                parent_path TEXT NOT NULL DEFAULT '',
                file_extension TEXT,
                size_bytes INTEGER NOT NULL DEFAULT 0,
                line_count INTEGER NOT NULL DEFAULT 0,
                token_estimate INTEGER NOT NULL DEFAULT 0,
                is_binary INTEGER NOT NULL DEFAULT 0,
                last_modified TEXT,
                content_hash TEXT,
                preview TEXT
            )
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_artifact_grant_kind ON artifact_index(grant_id, kind)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_artifact_canonical ON artifact_index(grant_id, canonical_path)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_artifact_parent ON artifact_index(grant_id, parent_path)")
        try db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS artifact_search USING fts5(
                artifact_id UNINDEXED,
                grant_id UNINDEXED,
                canonical_path,
                content,
                tokenize='unicode61 remove_diacritics 2'
            )
        """)
    }

    public func ensureGrantIndexed(
        grantID: String,
        materializationRoot: String,
        mounts: [ArtifactMount]
    ) throws {
        let existing = try db.queryAll(
            "SELECT materialization_root FROM artifact_index_state WHERE grant_id = ? LIMIT 1",
            params: [grantID]
        ).first

        if existing?["materialization_root"] == materializationRoot {
            return
        }

        try rebuildGrantIndex(grantID: grantID, materializationRoot: materializationRoot, mounts: mounts)
    }

    public func listFiles(grantID: String) throws -> [ArtifactHandle] {
        let rows = try db.queryAll("""
            SELECT artifact_id, kind, source_id, mount_name, canonical_path, absolute_path,
                   content_hash, size_bytes, token_estimate, line_count, parent_path,
                   last_modified, file_extension, is_binary, preview
            FROM artifact_index
            WHERE grant_id = ? AND kind = ?
            ORDER BY canonical_path ASC
        """, params: [grantID, ArtifactKind.file.rawValue])
        return rows.compactMap { ArtifactHandle(row: $0) }
    }

    public func fileCount(grantID: String) throws -> Int {
        let result = try db.queryScalar(
            "SELECT COUNT(*) FROM artifact_index WHERE grant_id = ? AND kind = ?",
            params: [grantID, ArtifactKind.file.rawValue]
        )
        return Int(result ?? "0") ?? 0
    }

    public func artifact(grantID: String, canonicalPath: String) throws -> ArtifactHandle? {
        let rows = try db.queryAll("""
            SELECT artifact_id, kind, source_id, mount_name, canonical_path, absolute_path,
                   content_hash, size_bytes, token_estimate, line_count, parent_path,
                   last_modified, file_extension, is_binary, preview
            FROM artifact_index
            WHERE grant_id = ? AND canonical_path = ?
            ORDER BY kind = 'file' DESC, canonical_path ASC
            LIMIT 1
        """, params: [grantID, canonicalPath])
        if let row = rows.first {
            return ArtifactHandle(row: row)
        }
        return nil
    }

    public func archiveEntries(grantID: String, canonicalPath: String) throws -> [String] {
        let rows = try db.queryAll("""
            SELECT canonical_path
            FROM artifact_index
            WHERE grant_id = ? AND kind = ? AND parent_path = ?
            ORDER BY canonical_path ASC
        """, params: [grantID, ArtifactKind.archiveEntry.rawValue, canonicalPath])

        return rows.compactMap { row in
            row["canonical_path"]?.components(separatedBy: "::").last
        }
    }

    public func search(
        grantID: String,
        query: String,
        limit: Int = 20,
        kinds: [ArtifactKind] = [.file]
    ) throws -> [SearchHit] {
        let normalizedLimit = max(1, min(limit, 50))
        let candidates = try searchCandidates(
            grantID: grantID,
            query: query,
            limit: normalizedLimit,
            kinds: kinds
        )

        return candidates.compactMap { candidate in
            var preview = candidate.snippet.map { [$0] } ?? []
            var selection: ArtifactSelection?

            if candidate.handle.kind == .file {
                let matches = ContextEngine.searchMatches(
                    query: query,
                    fileURL: URL(fileURLWithPath: candidate.handle.absolutePath)
                )
                if let firstMatch = matches.first {
                    selection = ArtifactSelection(lineStart: firstMatch.lineNumber, lineEnd: firstMatch.lineNumber)
                    preview = matches.map(\.text)
                }
            }

            if preview.isEmpty, let fallback = candidate.handle.preview {
                preview = [fallback]
            }

            return SearchHit(
                handle: candidate.handle.withSelection(selection),
                preview: preview,
                score: candidate.score,
                selection: selection
            )
        }
    }

    public func syncEmails(
        grantID: String,
        emails: [EmailMessageRecord],
        attachments: [EmailAttachmentRecord]
    ) throws {
        try deleteArtifacts(grantID: grantID, kinds: [.email, .emailAttachment])

        let attachmentsByEmailID = Dictionary(grouping: attachments, by: \.emailID)
        for email in emails {
            let canonicalPath = "_emails/\(email.emailID)"
            let searchContent = [
                email.sender,
                email.senderEmail,
                email.senderDomain,
                email.recipients,
                email.cc,
                email.subject,
                email.preview,
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            try upsertSyntheticEntry(
                grantID: grantID,
                sourceID: email.accountID,
                mountName: "_emails",
                kind: .email,
                canonicalPath: canonicalPath,
                absolutePath: email.emlPath ?? canonicalPath,
                parentPath: "_emails",
                fileExtension: email.emlPath.flatMap { URL(fileURLWithPath: $0).pathExtension }.nilIfEmpty ?? "eml",
                sizeBytes: email.sizeBytes,
                lineCount: 0,
                tokenEstimate: ContextEngine.estimateTokens(forText: searchContent),
                isBinary: false,
                lastModified: email.receivedAt,
                contentHash: nil,
                preview: email.preview ?? email.subject,
                searchContent: searchContent
            )

            for attachment in attachmentsByEmailID[email.emailID] ?? [] {
                let canonicalAttachmentPath = "\(canonicalPath)/attachments/\(attachment.filename)"
                let preview = "\(attachment.filename) (\(attachment.mimeType))"
                try upsertSyntheticEntry(
                    grantID: grantID,
                    sourceID: email.accountID,
                    mountName: "_emails",
                    kind: .emailAttachment,
                    canonicalPath: canonicalAttachmentPath,
                    absolutePath: canonicalAttachmentPath,
                    parentPath: canonicalPath,
                    fileExtension: URL(fileURLWithPath: attachment.filename).pathExtension,
                    sizeBytes: attachment.sizeBytes,
                    lineCount: 0,
                    tokenEstimate: max(1, attachment.sizeBytes / 4),
                    isBinary: true,
                    lastModified: email.receivedAt,
                    contentHash: attachment.contentHash,
                    preview: preview,
                    searchContent: [attachment.filename, attachment.mimeType, email.subject].joined(separator: "\n")
                )
            }
        }
    }

    public func syncSessionSummaries(
        grantID: String,
        summaries: [SessionSummaryRecord]
    ) throws {
        try deleteArtifacts(grantID: grantID, kinds: [.sessionSummary])

        for summary in summaries {
            let canonicalPath = "_sessions/\(summary.summaryID).md"
            try upsertSyntheticEntry(
                grantID: grantID,
                sourceID: summary.grantID,
                mountName: "_sessions",
                kind: .sessionSummary,
                canonicalPath: canonicalPath,
                absolutePath: canonicalPath,
                parentPath: "_sessions",
                fileExtension: "md",
                sizeBytes: summary.summaryMarkdown.utf8.count,
                lineCount: ContextEngine.lineCount(for: summary.summaryMarkdown),
                tokenEstimate: ContextEngine.estimateTokens(forText: summary.summaryMarkdown),
                isBinary: false,
                lastModified: summary.endedAt,
                contentHash: summary.summaryJSONHash,
                preview: ContextEngine.preview(text: summary.summaryMarkdown, maxLines: 2, maxCharacters: 240).nilIfEmpty,
                searchContent: summary.summaryMarkdown
            )
        }
    }

    public func upsertFile(
        grantID: String,
        mount: ArtifactMount,
        relativePath: String,
        fileURL: URL
    ) throws {
        let canonicalPath = "\(mount.mountName)/\(relativePath)"
        let parentPath = URL(fileURLWithPath: relativePath).deletingLastPathComponent().path
        if !parentPath.isEmpty, parentPath != "." {
            try upsertDirectory(
                grantID: grantID,
                mount: mount,
                relativePath: parentPath,
                absolutePath: fileURL.deletingLastPathComponent().path,
                modifiedAt: nil
            )
        }

        let payload = try indexedPayload(for: fileURL, canonicalPath: canonicalPath)
        try upsertEntry(
            grantID: grantID,
            mount: mount,
            kind: .file,
            relativePath: relativePath,
            canonicalPath: canonicalPath,
            absolutePath: fileURL.path,
            parentPath: parentPath == "." ? "" : "\(mount.mountName)/\(parentPath)",
            fileExtension: fileURL.pathExtension,
            sizeBytes: payload.sizeBytes,
            lineCount: payload.lineCount,
            tokenEstimate: payload.tokenEstimate,
            isBinary: payload.isBinary,
            lastModified: payload.lastModified,
            contentHash: payload.contentHash,
            preview: payload.preview,
            searchContent: payload.searchContent
        )

        if fileURL.pathExtension.lowercased() == "zip" {
            try refreshArchiveEntries(
                grantID: grantID,
                mount: mount,
                canonicalArchivePath: canonicalPath,
                archiveURL: fileURL
            )
        } else {
            try deleteArchiveEntries(grantID: grantID, parentPath: canonicalPath)
        }
    }

    private func deleteArtifacts(grantID: String, kinds: [ArtifactKind]) throws {
        guard !kinds.isEmpty else { return }
        let placeholders = kinds.map { _ in "?" }.joined(separator: ",")
        let kindParams = kinds.map { Optional($0.rawValue) }
        let artifactRows = try db.queryAll("""
            SELECT artifact_id
            FROM artifact_index
            WHERE grant_id = ? AND kind IN (\(placeholders))
        """, params: [grantID as String?] + kindParams)

        try db.transaction {
            for row in artifactRows {
                guard let artifactID = row["artifact_id"] else { continue }
                try db.execute(
                    "DELETE FROM artifact_search WHERE artifact_id = ? AND grant_id = ?",
                    params: [artifactID, grantID]
                )
            }
            try db.execute("""
                DELETE FROM artifact_index
                WHERE grant_id = ? AND kind IN (\(placeholders))
            """, params: [grantID as String?] + kindParams)
        }
    }

    private func rebuildGrantIndex(
        grantID: String,
        materializationRoot: String,
        mounts: [ArtifactMount]
    ) throws {
        try db.transaction {
            try db.execute("DELETE FROM artifact_index WHERE grant_id = ?", params: [grantID])
            try db.execute("DELETE FROM artifact_search WHERE grant_id = ?", params: [grantID])
            try db.execute("DELETE FROM artifact_index_state WHERE grant_id = ?", params: [grantID])
        }

        for mount in mounts {
            try indexMount(grantID: grantID, mount: mount)
        }

        let now = ISO8601DateFormatter().string(from: Date())
        try db.execute("""
            INSERT INTO artifact_index_state (grant_id, materialization_root, indexed_at)
            VALUES (?, ?, ?)
        """, params: [grantID, materializationRoot, now])
    }

    private func indexMount(grantID: String, mount: ArtifactMount) throws {
        let root = URL(fileURLWithPath: mount.mountPath)
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let url = enumerator.nextObject() as? URL {
            let relativePath = relativePath(for: url, base: root)
            if shouldSkip(relativePath: relativePath) {
                if url.hasDirectoryPath {
                    enumerator.skipDescendants()
                }
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey])
            let modifiedAt = values?.contentModificationDate.map { ISO8601DateFormatter().string(from: $0) }

            if values?.isDirectory == true {
                try upsertDirectory(
                    grantID: grantID,
                    mount: mount,
                    relativePath: relativePath,
                    absolutePath: url.path,
                    modifiedAt: modifiedAt
                )
                continue
            }

            guard values?.isRegularFile == true else { continue }
            try upsertFile(grantID: grantID, mount: mount, relativePath: relativePath, fileURL: url)
        }
    }

    private func upsertDirectory(
        grantID: String,
        mount: ArtifactMount,
        relativePath: String,
        absolutePath: String,
        modifiedAt: String?
    ) throws {
        let canonicalPath = "\(mount.mountName)/\(relativePath)"
        let parent = URL(fileURLWithPath: relativePath).deletingLastPathComponent().path

        try upsertEntry(
            grantID: grantID,
            mount: mount,
            kind: .directory,
            relativePath: relativePath,
            canonicalPath: canonicalPath,
            absolutePath: absolutePath,
            parentPath: parent == "." ? "" : "\(mount.mountName)/\(parent)",
            fileExtension: "",
            sizeBytes: 0,
            lineCount: 0,
            tokenEstimate: 0,
            isBinary: false,
            lastModified: modifiedAt ?? "",
            contentHash: nil,
            preview: nil,
            searchContent: nil
        )
    }

    private func upsertSyntheticEntry(
        grantID: String,
        sourceID: String,
        mountName: String,
        kind: ArtifactKind,
        canonicalPath: String,
        absolutePath: String,
        parentPath: String,
        fileExtension: String,
        sizeBytes: Int,
        lineCount: Int,
        tokenEstimate: Int,
        isBinary: Bool,
        lastModified: String,
        contentHash: String?,
        preview: String?,
        searchContent: String?
    ) throws {
        try upsertEntry(
            grantID: grantID,
            mount: ArtifactMount(sourceID: sourceID, mountName: mountName, mountPath: ""),
            kind: kind,
            relativePath: canonicalPath,
            canonicalPath: canonicalPath,
            absolutePath: absolutePath,
            parentPath: parentPath,
            fileExtension: fileExtension,
            sizeBytes: sizeBytes,
            lineCount: lineCount,
            tokenEstimate: tokenEstimate,
            isBinary: isBinary,
            lastModified: lastModified,
            contentHash: contentHash,
            preview: preview,
            searchContent: searchContent
        )
    }

    private func upsertEntry(
        grantID: String,
        mount: ArtifactMount,
        kind: ArtifactKind,
        relativePath: String,
        canonicalPath: String,
        absolutePath: String,
        parentPath: String,
        fileExtension: String,
        sizeBytes: Int,
        lineCount: Int,
        tokenEstimate: Int,
        isBinary: Bool,
        lastModified: String,
        contentHash: String?,
        preview: String?,
        searchContent: String?
    ) throws {
        let artifactID = artifactID(
            grantID: grantID,
            kind: kind,
            canonicalPath: canonicalPath,
            parentPath: parentPath
        )

        try db.transaction {
            try db.execute("""
                INSERT OR REPLACE INTO artifact_index (
                    artifact_id, grant_id, source_id, mount_name, kind, relative_path,
                    canonical_path, absolute_path, parent_path, file_extension, size_bytes,
                    line_count, token_estimate, is_binary, last_modified, content_hash, preview
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, params: [
                artifactID,
                grantID,
                mount.sourceID,
                mount.mountName,
                kind.rawValue,
                relativePath,
                canonicalPath,
                absolutePath,
                parentPath,
                fileExtension,
                "\(sizeBytes)",
                "\(lineCount)",
                "\(tokenEstimate)",
                isBinary ? "1" : "0",
                lastModified,
                contentHash,
                preview,
            ])

            try db.execute(
                "DELETE FROM artifact_search WHERE artifact_id = ? AND grant_id = ?",
                params: [artifactID, grantID]
            )
            try db.execute("""
                INSERT INTO artifact_search (artifact_id, grant_id, canonical_path, content)
                VALUES (?, ?, ?, ?)
            """, params: [artifactID, grantID, canonicalPath, searchContent ?? preview ?? ""])
        }
    }

    private func refreshArchiveEntries(
        grantID: String,
        mount: ArtifactMount,
        canonicalArchivePath: String,
        archiveURL: URL
    ) throws {
        try deleteArchiveEntries(grantID: grantID, parentPath: canonicalArchivePath)

        guard let entries = listZipContents(atPath: archiveURL.path) else { return }
        for entry in entries {
            let canonicalPath = "\(canonicalArchivePath)::\(entry)"
            try upsertEntry(
                grantID: grantID,
                mount: mount,
                kind: .archiveEntry,
                relativePath: entry,
                canonicalPath: canonicalPath,
                absolutePath: archiveURL.path,
                parentPath: canonicalArchivePath,
                fileExtension: URL(fileURLWithPath: entry).pathExtension,
                sizeBytes: 0,
                lineCount: 0,
                tokenEstimate: 0,
                isBinary: false,
                lastModified: "",
                contentHash: nil,
                preview: entry,
                searchContent: entry
            )
        }
    }

    private func deleteArchiveEntries(grantID: String, parentPath: String) throws {
        let rows = try db.queryAll("""
            SELECT artifact_id FROM artifact_index
            WHERE grant_id = ? AND kind = ? AND parent_path = ?
        """, params: [grantID, ArtifactKind.archiveEntry.rawValue, parentPath])

        try db.transaction {
            for row in rows {
                guard let artifactID = row["artifact_id"] else { continue }
                try db.execute(
                    "DELETE FROM artifact_search WHERE artifact_id = ? AND grant_id = ?",
                    params: [artifactID, grantID]
                )
            }
            try db.execute("""
                DELETE FROM artifact_index
                WHERE grant_id = ? AND kind = ? AND parent_path = ?
            """, params: [grantID, ArtifactKind.archiveEntry.rawValue, parentPath])
        }
    }

    private func searchCandidates(
        grantID: String,
        query: String,
        limit: Int,
        kinds: [ArtifactKind]
    ) throws -> [IndexedSearchCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKinds = Array(Set(kinds))
        guard !trimmed.isEmpty, !normalizedKinds.isEmpty else { return [] }

        if let ftsCandidates = try? ftsCandidates(
            grantID: grantID,
            query: trimmed,
            limit: limit,
            kinds: normalizedKinds
        ),
           !ftsCandidates.isEmpty {
            return ftsCandidates
        }

        return try likeCandidates(
            grantID: grantID,
            query: trimmed,
            limit: limit,
            kinds: normalizedKinds
        )
    }

    private func ftsCandidates(
        grantID: String,
        query: String,
        limit: Int,
        kinds: [ArtifactKind]
    ) throws -> [IndexedSearchCandidate] {
        let kindPlaceholders = kinds.map { _ in "?" }.joined(separator: ",")
        let kindParams = kinds.map { Optional($0.rawValue) }
        let rows = try db.queryAll("""
            SELECT ai.artifact_id, ai.kind, ai.source_id, ai.mount_name, ai.canonical_path, ai.absolute_path,
                   ai.content_hash, ai.size_bytes, ai.token_estimate, ai.line_count, ai.parent_path,
                   ai.last_modified, ai.file_extension, ai.is_binary, ai.preview,
                   snippet(artifact_search, 3, '[', ']', '...', 10) AS snippet,
                   bm25(artifact_search) AS score
            FROM artifact_search
            JOIN artifact_index ai ON ai.artifact_id = artifact_search.artifact_id
            WHERE artifact_search MATCH ? AND ai.grant_id = ? AND ai.kind IN (\(kindPlaceholders))
            ORDER BY score ASC
            LIMIT ?
        """, params: [quotedFTSQuery(query) as String?, grantID as String?] + kindParams + ["\(limit)" as String?])

        return rows.compactMap { row in
            guard let handle = ArtifactHandle(row: row) else { return nil }
            let score = Double(row["score"] ?? "0") ?? 0
            return IndexedSearchCandidate(handle: handle, snippet: row["snippet"]?.nilIfEmpty, score: score)
        }
    }

    private func likeCandidates(
        grantID: String,
        query: String,
        limit: Int,
        kinds: [ArtifactKind]
    ) throws -> [IndexedSearchCandidate] {
        let pattern = "%\(query.lowercased())%"
        let kindPlaceholders = kinds.map { _ in "?" }.joined(separator: ",")
        let kindParams = kinds.map { Optional($0.rawValue) }
        let rows = try db.queryAll("""
            SELECT artifact_id, kind, source_id, mount_name, canonical_path, absolute_path,
                   content_hash, size_bytes, token_estimate, line_count, parent_path,
                   last_modified, file_extension, is_binary, preview
            FROM artifact_index
            WHERE grant_id = ? AND kind IN (\(kindPlaceholders))
              AND (LOWER(canonical_path) LIKE ? OR LOWER(COALESCE(preview, '')) LIKE ?)
            ORDER BY canonical_path ASC
            LIMIT ?
        """, params: [grantID as String?] + kindParams + [pattern as String?, pattern as String?, "\(limit)" as String?])

        return rows.compactMap { row in
            guard let handle = ArtifactHandle(row: row) else { return nil }
            return IndexedSearchCandidate(handle: handle, snippet: handle.preview, score: 0)
        }
    }

    private func indexedPayload(for fileURL: URL, canonicalPath: String) throws -> (
        sizeBytes: Int,
        lineCount: Int,
        tokenEstimate: Int,
        isBinary: Bool,
        lastModified: String,
        contentHash: String?,
        preview: String?,
        searchContent: String?
    ) {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let sizeBytes = values.fileSize ?? 0
        let lastModified = values.contentModificationDate.map { ISO8601DateFormatter().string(from: $0) } ?? ""
        let fileExtension = fileURL.pathExtension.lowercased()
        let binary = ContextEngine.isBinary(fileExtension: fileExtension, fileURL: fileURL)

        guard !binary else {
            return (sizeBytes, 0, max(1, sizeBytes / 4), true, lastModified, nil, nil, nil)
        }

        if sizeBytes > 256_000 {
            let previewData = try readPrefix(of: fileURL, maxBytes: 8_192)
            let previewText = String(data: previewData, encoding: .utf8) ?? ""
            return (
                sizeBytes,
                0,
                max(1, sizeBytes / 4),
                false,
                lastModified,
                nil,
                ContextEngine.preview(text: previewText, maxLines: 2, maxCharacters: 240).nilIfEmpty,
                nil
            )
        }

        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let contentHash = SHA256.hash(data: data).hexString
        guard let text = String(data: data, encoding: .utf8) else {
            return (sizeBytes, 0, max(1, sizeBytes / 4), true, lastModified, contentHash, nil, nil)
        }

        let lineCount = ContextEngine.lineCount(for: text)
        let preview = ContextEngine.preview(text: text, maxLines: 2, maxCharacters: 240)
        let indexedContent = text.count > 64_000 ? String(text.prefix(64_000)) : text

        return (
            sizeBytes,
            lineCount,
            ContextEngine.estimateTokens(forText: text),
            false,
            lastModified,
            contentHash,
            preview.nilIfEmpty,
            indexedContent
        )
    }

    private func artifactID(
        grantID: String,
        kind: ArtifactKind,
        canonicalPath: String,
        parentPath: String
    ) -> String {
        let seed = "\(grantID)|\(kind.rawValue)|\(canonicalPath)|\(parentPath)"
        return "art-\(SHA256.hash(data: Data(seed.utf8)).hexString.prefix(24))"
    }

    private func relativePath(for url: URL, base: URL) -> String {
        let basePath = base.standardizedFileURL.path + "/"
        let absolutePath = url.standardizedFileURL.path
        if absolutePath.hasPrefix(basePath) {
            return String(absolutePath.dropFirst(basePath.count))
        }
        return url.lastPathComponent
    }

    private func shouldSkip(relativePath: String) -> Bool {
        relativePath.hasPrefix("_emails/") || relativePath.hasPrefix(".manifold-")
    }

    private func quotedFTSQuery(_ query: String) -> String {
        query
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                token
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "'", with: "")
                    + "*"
            }
            .joined(separator: " ")
    }

    private func listZipContents(atPath path: String) -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let files = trimmed.components(separatedBy: "\n").filter { !$0.hasSuffix("/") }
        return files.isEmpty ? nil : files
    }

    private func readPrefix(of fileURL: URL, maxBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        return try handle.read(upToCount: maxBytes) ?? Data()
    }
}
