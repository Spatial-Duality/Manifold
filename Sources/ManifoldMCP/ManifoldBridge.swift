import Foundation
import ManifoldKit

/// Core logic layer between MCP protocol and ManifoldKit stores.
/// Grant-only access: all file I/O routes through the materialized workspace.
/// No active grant = no file access (fail-closed).
public actor ManifoldBridge {
    private let db: DatabaseConnection
    private let auditStore: AuditStore
    private let contentStore: ContentStore
    private let grantStore: GrantStore
    private let emailStore: EmailStore
    private let snapshotStore: SnapshotStore

    public init(
        db: DatabaseConnection,
        auditStore: AuditStore,
        contentStore: ContentStore,
        grantStore: GrantStore,
        emailStore: EmailStore,
        snapshotStore: SnapshotStore
    ) {
        self.db = db
        self.auditStore = auditStore
        self.contentStore = contentStore
        self.grantStore = grantStore
        self.emailStore = emailStore
        self.snapshotStore = snapshotStore
    }

    private static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "ico", "webp",
        "pdf", "zip", "gz", "tar", "rar", "7z",
        "exe", "dll", "dylib", "so", "a", "o",
        "mp3", "mp4", "wav", "avi", "mov", "mkv",
        "sqlite", "db", "bin", "dat",
    ]

    // MARK: - Grant Resolution

    /// Resolve the active grant or throw. Fail-closed: no grant = no access.
    private func requireGrant(targetApp: TargetApp = .cowork, profileID: String = "default") async throws -> (GrantRecord, [GrantSourceRecord]) {
        guard let grant = try await grantStore.activeGrant(targetApp: targetApp, profileID: profileID) else {
            let sources = try await grantStore.activeSources()
            if sources.isEmpty {
                throw ManifoldMCPError.noSources
            }
            throw ManifoldMCPError.noActiveSession
        }
        let grantSources = try await grantStore.grantSources(grantID: grant.grantID)
        try await grantStore.touchGrant(grantID: grant.grantID)
        return (grant, grantSources)
    }

    /// Get mount directories for a grant, including source IDs.
    private func grantMounts(grant: GrantRecord, sources: [GrantSourceRecord]) -> [GrantMount] {
        sources.map { gs in
            let path = URL(fileURLWithPath: grant.materializationRoot)
                .appendingPathComponent(gs.mountName).path
            return GrantMount(sourceID: gs.sourceID, mountName: gs.mountName, mountPath: path)
        }
    }

    private struct GrantMount {
        let sourceID: String
        let mountName: String
        let mountPath: String
    }

    // MARK: - Path Safety

    private func cleanPath(_ path: String) -> String {
        var cleaned = path
        while cleaned.hasPrefix("./") { cleaned = String(cleaned.dropFirst(2)) }
        while cleaned.contains("//") { cleaned = cleaned.replacingOccurrences(of: "//", with: "/") }
        while cleaned.hasSuffix("/") && cleaned.count > 1 { cleaned = String(cleaned.dropLast()) }
        return cleaned
    }

    private func validatePath(_ path: String, rootPath: String) throws -> URL {
        let cleaned = cleanPath(path)
        guard !cleaned.hasPrefix("/") else { throw ManifoldMCPError.invalidPath("Absolute paths not allowed") }
        guard !cleaned.contains("..") else { throw ManifoldMCPError.invalidPath("Path traversal not allowed") }
        let root = URL(fileURLWithPath: rootPath)
        let resolved = root.appendingPathComponent(cleaned).standardizedFileURL
        guard resolved.path.hasPrefix(root.standardizedFileURL.path) else {
            throw ManifoldMCPError.invalidPath("Path escapes workspace boundary")
        }
        return resolved
    }

    /// Resolve a cleaned path to a specific mount. Returns nil if no mount prefix matches.
    private func resolveMountAndPath(_ path: String, in mounts: [GrantMount]) -> (GrantMount, String)? {
        for mount in mounts {
            if path.hasPrefix(mount.mountName + "/") {
                let relPath = String(path.dropFirst(mount.mountName.count + 1))
                return (mount, relPath)
            }
        }
        return nil
    }

    /// Resolve bare path to a single unambiguous mount. Throws if ambiguous.
    private func resolveBarePath(_ path: String, in mounts: [GrantMount]) throws -> (GrantMount, String) {
        var matches: [(mount: GrantMount, url: URL)] = []
        for mount in mounts {
            if let url = try? validatePath(path, rootPath: mount.mountPath),
               FileManager.default.fileExists(atPath: url.path) {
                matches.append((mount, url))
            }
        }
        switch matches.count {
        case 0:
            throw ManifoldMCPError.fileNotFound(path)
        case 1:
            return (matches[0].mount, path)
        default:
            let names = matches.map(\.mount.mountName).joined(separator: ", ")
            throw ManifoldMCPError.invalidPath("Ambiguous path '\(path)' exists in multiple sources: \(names). Use mount-prefixed path (e.g. '\(matches[0].mount.mountName)/\(path)').")
        }
    }

    // MARK: - Tool Audit

    private func logToolCall(tool: String, arguments: [String: Any] = [:]) async {
        let argsJSON = arguments.isEmpty ? "{}" : (arguments.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
        try? await auditStore.log(
            action: .toolCall,
            agent: "cowork",
            metadata: ["tool": tool, "arguments": argsJSON]
        )
        ManifoldNotification.post(ManifoldNotification.dataChanged)
    }

    // MARK: - Tools

    public func getStatus() async -> StatusResult {
        await logToolCall(tool: "get_status")
        do {
            let (grant, grantSources) = try await requireGrant()
            let mounts = grantMounts(grant: grant, sources: grantSources)
            var totalFiles = 0

            for mount in mounts {
                let mountURL = URL(fileURLWithPath: mount.mountPath)
                let fileCount = (try? enumerateFiles(in: mountURL).count) ?? 0
                totalFiles += fileCount
            }
            let emailCount = (try? emailStore.emailMessageCount()) ?? 0
            let sourceNames = mounts.map(\.mountName).joined(separator: ", ")
            let message = "Manifold active (grant \(grant.grantID.prefix(12))...). \(mounts.count) source(s): \(sourceNames). \(totalFiles) files, \(emailCount) emails backed up."

            return StatusResult(
                active: true,
                grantID: grant.grantID,
                sources: mounts.map(\.mountName),
                pausedSources: [],
                fileCount: totalFiles,
                emailCount: emailCount,
                message: message
            )
        } catch ManifoldMCPError.noActiveSession {
            let sources = (try? await grantStore.activeSources()) ?? []
            let paused = sources.filter(\.isPaused)
            let active = sources.filter(\.isAccessible)
            return StatusResult(
                active: false,
                grantID: nil,
                sources: active.map(\.displayName),
                pausedSources: paused.map(\.displayName),
                fileCount: 0,
                emailCount: 0,
                message: "No active session. \(active.count) source(s) configured. Start a session in Manifold to grant access."
            )
        } catch {
            return StatusResult(
                active: false, grantID: nil, sources: [], pausedSources: [], fileCount: 0, emailCount: 0,
                message: "Error: \(error.localizedDescription)"
            )
        }
    }

    public func listFiles() async throws -> [FileInfo] {
        await logToolCall(tool: "list_files")
        let (grant, grantSources) = try await requireGrant()
        let mounts = grantMounts(grant: grant, sources: grantSources)
        var allFiles: [FileInfo] = []

        for mount in mounts {
            let mountURL = URL(fileURLWithPath: mount.mountPath)
            let files = try enumerateFiles(in: mountURL)

            for file in files {
                let rel = relativePath(file: file, base: mountURL)
                guard !rel.hasPrefix("_emails/") else { continue }
                guard !rel.hasPrefix(".manifold-") else { continue }

                let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
                let size = (attrs?[.size] as? Int) ?? 0
                let modified = (attrs?[.modificationDate] as? Date).map { ISO8601DateFormatter().string(from: $0) } ?? ""

                allFiles.append(FileInfo(
                    path: rel,
                    sourceName: mount.mountName,
                    sourceAddedAt: grant.startedAt,
                    sizeBytes: size,
                    lastModified: modified
                ))
            }
        }
        return allFiles.sorted { $0.path < $1.path }
    }

    // MARK: - Read File (P1 FIX: reject ambiguous bare paths)

    public func readFile(path: String) async throws -> String {
        await logToolCall(tool: "read_file", arguments: ["path": path])
        let (grant, grantSources) = try await requireGrant()
        let mounts = grantMounts(grant: grant, sources: grantSources)
        let cleaned = cleanPath(path)

        // Try mount-prefixed resolution first (e.g. "MyProject/src/main.swift")
        if let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) {
            return try await readFromMount(relativePath: relPath, mountPath: mount.mountPath, mountName: mount.mountName, grantID: grant.grantID)
        }

        // Bare path: resolve unambiguously or reject
        let (mount, relPath) = try resolveBarePath(cleaned, in: mounts)
        return try await readFromMount(relativePath: relPath, mountPath: mount.mountPath, mountName: mount.mountName, grantID: grant.grantID)
    }

    private func readFromMount(relativePath: String, mountPath: String, mountName: String, grantID: String) async throws -> String {
        let fileURL = try validatePath(relativePath, rootPath: mountPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ManifoldMCPError.fileNotFound(relativePath)
        }
        let data = try Data(contentsOf: fileURL)
        let canonicalPath = "\(mountName)/\(relativePath)"

        try? await auditStore.log(
            action: .fileRead,
            agent: "cowork",
            filePath: canonicalPath,
            metadata: ["grant_id": grantID, "mount": mountName],
            grantID: grantID
        )
        ManifoldNotification.post(ManifoldNotification.fileAccessed, userInfo: [
            "path": canonicalPath, "action": "read", "agent": "cowork"
        ])

        if let text = String(data: data, encoding: .utf8) {
            return text
        } else {
            return "<binary file, \(data.count) bytes>"
        }
    }

    // MARK: - Write File (P1 FIX: record snapshots, use canonical paths, reject ambiguous)

    public func writeFile(path: String, content: String) async throws -> String {
        await logToolCall(tool: "write_file", arguments: ["path": path, "content_length": "\(content.count)"])
        let (grant, grantSources) = try await requireGrant()
        let mounts = grantMounts(grant: grant, sources: grantSources)
        let cleaned = cleanPath(path)

        guard !cleaned.hasPrefix("_emails/") else {
            throw ManifoldMCPError.invalidPath("Cannot write to email files (read-only)")
        }

        let data = content.data(using: .utf8) ?? Data()

        // Resolve mount deterministically
        let resolved: GrantMount
        let resolvedPath: String
        if let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) {
            resolved = mount
            resolvedPath = relPath
        } else if mounts.count == 1, let first = mounts.first {
            resolved = first
            resolvedPath = cleaned
        } else if mounts.count > 1 {
            let (mount, relPath) = try resolveBarePath(cleaned, in: mounts)
            resolved = mount
            resolvedPath = relPath
        } else {
            throw ManifoldMCPError.noSources
        }

        let fileURL = try validatePath(resolvedPath, rootPath: resolved.mountPath)
        let canonicalPath = "\(resolved.mountName)/\(resolvedPath)"

        // Snapshot BEFORE writing (capture previous state)
        let existed = FileManager.default.fileExists(atPath: fileURL.path)
        if existed {
            let beforeData = try Data(contentsOf: fileURL)
            try await snapshotStore.recordModification(
                runID: grant.grantID,
                workspaceID: resolved.sourceID,
                filePath: canonicalPath,
                newData: beforeData,
                source: "mcp"
            )
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)

        // Snapshot AFTER writing (capture new state)
        try await snapshotStore.recordModification(
            runID: grant.grantID,
            workspaceID: resolved.sourceID,
            filePath: canonicalPath,
            newData: data,
            source: "mcp"
        )

        try? await auditStore.log(
            action: existed ? .fileModified : .fileCreated,
            runID: grant.grantID,
            workspaceID: resolved.sourceID,
            agent: "cowork",
            filePath: canonicalPath,
            metadata: ["grant_id": grant.grantID, "mount": resolved.mountName, "bytes": "\(data.count)"],
            grantID: grant.grantID
        )
        ManifoldNotification.post(ManifoldNotification.dataChanged)

        return "Wrote \(data.count) bytes to \(canonicalPath)"
    }

    public func searchFiles(query: String) async throws -> [(path: String, source: String, matches: [String])] {
        await logToolCall(tool: "search_files", arguments: ["query": query])
        let (grant, grantSources) = try await requireGrant()
        let mounts = grantMounts(grant: grant, sources: grantSources)
        return try searchInDirectories(mounts.map { (name: $0.mountName, path: $0.mountPath) }, query: query)
    }

    private func searchInDirectories(_ dirs: [(name: String, path: String)], query: String) throws -> [(path: String, source: String, matches: [String])] {
        var results: [(path: String, source: String, matches: [String])] = []
        for dir in dirs {
            let root = URL(fileURLWithPath: dir.path)
            let files = try enumerateFiles(in: root)

            for file in files {
                let rel = relativePath(file: file, base: root)
                guard !rel.hasPrefix("_emails/") else { continue }
                guard !rel.hasPrefix(".manifold-") else { continue }

                guard let data = try? Data(contentsOf: file),
                      let text = String(data: data, encoding: .utf8) else { continue }

                let matchingLines = text.components(separatedBy: "\n")
                    .filter { $0.localizedCaseInsensitiveContains(query) }
                    .prefix(5)
                    .map { String($0.prefix(200)) }

                if !matchingLines.isEmpty {
                    results.append((path: "\(dir.name)/\(rel)", source: dir.name, matches: Array(matchingLines)))
                }
            }
        }
        return results
    }

    // MARK: - File Info

    public func fileInfo(path: String) async throws -> FileInfoDetail {
        await logToolCall(tool: "file_info", arguments: ["path": path])
        let (grant, grantSources) = try await requireGrant()
        let mounts = grantMounts(grant: grant, sources: grantSources)
        let cleaned = cleanPath(path)

        let mountPath: String
        let mountName: String
        let resolvedPath: String

        if let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) {
            mountPath = mount.mountPath
            mountName = mount.mountName
            resolvedPath = relPath
        } else {
            let (mount, relPath) = try resolveBarePath(cleaned, in: mounts)
            mountPath = mount.mountPath
            mountName = mount.mountName
            resolvedPath = relPath
        }

        let fileURL = try validatePath(resolvedPath, rootPath: mountPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ManifoldMCPError.fileNotFound(cleaned)
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs[.size] as? Int) ?? 0
        let modified = (attrs[.modificationDate] as? Date).map { ISO8601DateFormatter().string(from: $0) } ?? ""
        let ext = fileURL.pathExtension
        let isBinary = Self.binaryExtensions.contains(ext.lowercased())

        var archiveContents: [String]? = nil
        if ext.lowercased() == "zip" {
            archiveContents = listZipContents(atPath: fileURL.path)
        }

        return FileInfoDetail(
            path: "\(mountName)/\(resolvedPath)",
            sourceName: mountName,
            sizeBytes: size,
            fileExtension: ext,
            isBinary: isBinary,
            lastModified: modified,
            archiveContents: archiveContents
        )
    }

    // MARK: - Archive Listing

    public func listArchive(path: String) async throws -> [String] {
        await logToolCall(tool: "list_archive", arguments: ["path": path])
        let (grant, grantSources) = try await requireGrant()
        let mounts = grantMounts(grant: grant, sources: grantSources)
        let cleaned = cleanPath(path)

        guard let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) else {
            throw ManifoldMCPError.fileNotFound(path)
        }

        let archiveURL = try validatePath(relPath, rootPath: mount.mountPath)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ManifoldMCPError.fileNotFound(path)
        }

        guard let contents = listZipContents(atPath: archiveURL.path) else {
            throw ManifoldMCPError.invalidPath("Not a valid zip archive or archive is empty")
        }
        return contents
    }

    // MARK: - Extract File

    public func extractFile(archivePath: String, filePath: String) async throws -> String {
        await logToolCall(tool: "extract_file", arguments: ["archive": archivePath, "file": filePath])
        let (grant, grantSources) = try await requireGrant()
        let mounts = grantMounts(grant: grant, sources: grantSources)
        let cleaned = cleanPath(archivePath)

        // Resolve mount for the archive
        guard let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) else {
            throw ManifoldMCPError.fileNotFound(archivePath)
        }

        let archiveURL = try validatePath(relPath, rootPath: mount.mountPath)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ManifoldMCPError.fileNotFound(archivePath)
        }

        // Size check: 50MB limit
        let attrs = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
        let archiveSize = (attrs[.size] as? Int64) ?? 0
        guard archiveSize <= 50_000_000 else {
            throw ManifoldMCPError.invalidPath("Archive exceeds 50MB extraction limit")
        }

        let archiveContents = listZipContents(atPath: archiveURL.path)
        guard let targetEntry = archiveContents?.first(where: { $0 == filePath }) else {
            let available = (archiveContents ?? []).prefix(20).joined(separator: "\n")
            throw ManifoldMCPError.fileNotFound("'\(filePath)' not found in archive. Available files:\n\(available)")
        }

        return try extractFromZip(archivePath: archiveURL.path, entryPath: targetEntry)
    }

    // MARK: - Changes

    public func listChanges() async throws -> [ChangeInfo] {
        await logToolCall(tool: "list_changes")
        let (grant, _) = try await requireGrant()
        let entries = try await auditStore.recentEntries(limit: 50)
        return entries
            .filter { $0.grantID == grant.grantID }
            .map { entry in
                ChangeInfo(
                    action: entry.action,
                    path: entry.filePath,
                    agent: entry.agent,
                    timestamp: entry.timestamp
                )
            }
    }

    // MARK: - Zip Helpers

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

    private func extractFromZip(archivePath: String, entryPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archivePath, entryPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ManifoldMCPError.fileNotFound("Failed to extract '\(entryPath)' from archive")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: data, encoding: .utf8) {
            return text
        } else {
            return "<binary content, \(data.count) bytes>"
        }
    }

    // MARK: - File Enumeration

    private func enumerateFiles(in directory: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  vals.isRegularFile == true else { continue }
            files.append(url)
        }
        return files
    }

    private func relativePath(file: URL, base: URL) -> String {
        let filePath = file.standardizedFileURL.path
        let basePath = base.standardizedFileURL.path + "/"
        if filePath.hasPrefix(basePath) {
            return String(filePath.dropFirst(basePath.count))
        }
        return file.lastPathComponent
    }

    // MARK: - Sessions

    public func listSessions(limit: Int) async throws -> [SessionSummary] {
        await logToolCall(tool: "list_sessions", arguments: ["limit": "\(limit)"])
        let grants = try await grantStore.allGrants(limit: limit)
        let ended = grants.filter { $0.endedAt != nil }
        var results: [SessionSummary] = []
        for grant in ended {
            let summaries = (try? await grantStore.summaries(grantID: grant.grantID)) ?? []
            let preview = summaries.first?.summaryMarkdown.prefix(200).description ?? "No summary"
            results.append(SessionSummary(
                grantID: grant.grantID,
                targetApp: grant.targetApp,
                startedAt: grant.startedAt,
                endedAt: grant.endedAt ?? "",
                summaryPreview: preview
            ))
        }
        return results
    }

    public func getSession(grantID: String) async throws -> SessionDetail {
        await logToolCall(tool: "get_session", arguments: ["grant_id": grantID])
        let grants = try await grantStore.allGrants(limit: 100)
        guard let grant = grants.first(where: { $0.grantID == grantID }) else {
            throw ManifoldMCPError.fileNotFound("Session not found: \(grantID)")
        }
        let grantSources = try await grantStore.grantSources(grantID: grantID)
        let summaries = try await grantStore.summaries(grantID: grantID)
        let entries = try await auditStore.recentEntries(limit: 200)
        let grantEntries = entries.filter { $0.grantID == grantID }
        let filesModified = Set(grantEntries.compactMap(\.filePath)).sorted()

        return SessionDetail(
            grantID: grantID,
            targetApp: grant.targetApp,
            status: grant.status,
            startedAt: grant.startedAt,
            endedAt: grant.endedAt,
            sources: grantSources.map(\.mountName),
            summaryMarkdown: summaries.first?.summaryMarkdown,
            filesApplied: filesModified,
            filesConflicted: [],
            totalPromotions: filesModified.count
        )
    }

    public func saveSessionNote(note: String) async throws -> String {
        await logToolCall(tool: "save_session_note", arguments: ["note_length": "\(note.count)"])
        let (grant, _) = try await requireGrant()
        let now = ISO8601DateFormatter().string(from: Date())

        _ = try await grantStore.saveSummary(
            grantID: grant.grantID,
            targetApp: TargetApp(rawValue: grant.targetApp) ?? .cowork,
            startedAt: grant.startedAt,
            endedAt: now,
            markdown: note
        )
        return "Session note saved for grant \(grant.grantID.prefix(12))..."
    }

    // MARK: - Email Tools (reads from .eml-backed email index)

    /// Check if a single email is accessible under the given sensitivity filter.
    private func isEmailAccessible(email: EmailMessageRecord, filter: EmailSensitivityFilter) throws -> Bool {
        if filter.level == .strict {
            return try emailStore.isEmailShared(emailID: email.emailID)
        }
        return filter.isVisible(email: email)
    }

    public func listEmails() async throws -> [EmailSummary] {
        await logToolCall(tool: "list_emails")
        let (grant, _) = try await requireGrant()

        let filter = EmailSensitivityFilter(rawValue: grant.emailSensitivity)

        let emails: [EmailMessageRecord]
        if filter.level == .strict {
            emails = try emailStore.sharedEmails(limit: 200)
        } else {
            let all = try emailStore.allEmailMessages(limit: 200)
            emails = all.filter { filter.isVisible(email: $0) }
        }

        return emails.map {
            EmailSummary(id: $0.emailID, from: $0.sender, subject: $0.subject, date: $0.receivedAt)
        }
    }

    public func readEmail(id: String) async throws -> String {
        await logToolCall(tool: "read_email", arguments: ["id": id])
        let (grant, _) = try await requireGrant()

        let filter = EmailSensitivityFilter(rawValue: grant.emailSensitivity)

        guard let email = try emailStore.emailMessage(id: id) else {
            throw ManifoldMCPError.fileNotFound("Email not found: \(id)")
        }

        guard try isEmailAccessible(email: email, filter: filter) else {
            throw ManifoldMCPError.fileNotFound("Email not accessible with current sensitivity settings")
        }

        // Read from .eml file on disk
        if let emlPath = email.emlPath,
           FileManager.default.fileExists(atPath: emlPath),
           let content = try? String(contentsOfFile: emlPath, encoding: .utf8) {
            try? await auditStore.log(
                action: .fileRead,
                runID: grant.grantID,
                agent: "cowork",
                filePath: emlPath,
                metadata: ["type": "email", "messageID": id, "grant_id": grant.grantID],
                grantID: grant.grantID
            )
            return content
        }

        // Fallback: return metadata summary
        try? await auditStore.log(
            action: .fileRead,
            runID: grant.grantID,
            agent: "cowork",
            metadata: ["type": "email", "messageID": id, "grant_id": grant.grantID],
            grantID: grant.grantID
        )

        return """
        From: \(email.sender)
        To: \(email.recipients)
        Subject: \(email.subject)
        Date: \(email.receivedAt)

        \(email.preview ?? "(no preview available)")
        """
    }
}

// MARK: - Result Types

public struct StatusResult: Sendable {
    public let active: Bool
    public let grantID: String?
    public let sources: [String]
    public let pausedSources: [String]
    public let fileCount: Int
    public let emailCount: Int
    public let message: String
}

public struct FileInfo: Sendable {
    public let path: String
    public let sourceName: String
    public let sourceAddedAt: String
    public let sizeBytes: Int
    public let lastModified: String
}

public struct ChangeInfo: Sendable {
    public let action: String
    public let path: String?
    public let agent: String?
    public let timestamp: String
}

public struct FileInfoDetail: Sendable {
    public let path: String
    public let sourceName: String
    public let sizeBytes: Int
    public let fileExtension: String
    public let isBinary: Bool
    public let lastModified: String
    public let archiveContents: [String]?
}

public struct SessionSummary: Sendable {
    public let grantID: String
    public let targetApp: String
    public let startedAt: String
    public let endedAt: String
    public let summaryPreview: String
}

public struct SessionDetail: Sendable {
    public let grantID: String
    public let targetApp: String
    public let status: String
    public let startedAt: String
    public let endedAt: String?
    public let sources: [String]
    public let summaryMarkdown: String?
    public let filesApplied: [String]
    public let filesConflicted: [String]
    public let totalPromotions: Int
}

public struct EmailSummary: Sendable {
    public let id: String
    public let from: String
    public let subject: String
    public let date: String
}

public enum ManifoldMCPError: Error, LocalizedError {
    case noActiveSession
    case noSources
    case fileNotFound(String)
    case invalidPath(String)

    public var errorDescription: String? {
        switch self {
        case .noActiveSession: "No active session"
        case .noSources: "No sources configured"
        case .fileNotFound(let path): "File not found: \(path)"
        case .invalidPath(let msg): "Invalid path: \(msg)"
        }
    }
}
