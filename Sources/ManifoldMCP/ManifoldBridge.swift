import Foundation
import ManifoldKit

/// Core logic layer between MCP protocol and ManifoldKit stores.
/// Grant-only access: all file I/O routes through the materialized workspace.
/// No active grant = no file access (fail-closed).
public actor ManifoldBridge {
    private let db: DatabaseConnection
    private let auditStore: AuditStore
    private let emailFilter: EmailFilter
    private let grantStore: GrantStore

    public init(
        db: DatabaseConnection,
        auditStore: AuditStore,
        emailFilter: EmailFilter,
        grantStore: GrantStore
    ) {
        self.db = db
        self.auditStore = auditStore
        self.emailFilter = emailFilter
        self.grantStore = grantStore
    }

    // MARK: - Grant Resolution

    /// Resolve the active grant or throw. Fail-closed: no grant = no access.
    private func requireGrant(targetApp: TargetApp = .cowork, profileID: String = "default") async throws -> (GrantRecord, [GrantSourceRecord]) {
        guard let grant = try await grantStore.activeGrant(targetApp: targetApp, profileID: profileID) else {
            // Check if sources exist but just no session
            let sources = try await grantStore.activeSources()
            if sources.isEmpty {
                throw ManifoldMCPError.noSources
            }
            throw ManifoldMCPError.noActiveSession
        }
        let grantSources = try await grantStore.grantSources(grantID: grant.grantID)
        // Touch the grant to reset inactivity timer
        try await grantStore.touchGrant(grantID: grant.grantID)
        return (grant, grantSources)
    }

    /// Get mount directories for a grant.
    private func grantMounts(grant: GrantRecord, sources: [GrantSourceRecord]) -> [(mountName: String, mountPath: String)] {
        sources.map { gs in
            let path = URL(fileURLWithPath: grant.materializationRoot)
                .appendingPathComponent(gs.mountName).path
            return (mountName: gs.mountName, mountPath: path)
        }
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
            let emailCount = (try? await emailFilter.sharedEmails().count) ?? 0
            let sourceNames = mounts.map(\.mountName).joined(separator: ", ")
            let message = "Manifold active (grant \(grant.grantID.prefix(12))...). \(mounts.count) source(s): \(sourceNames). \(totalFiles) files, \(emailCount) emails."

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
            // Report sources but no session
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

    public func readFile(path: String) async throws -> String {
        await logToolCall(tool: "read_file", arguments: ["path": path])
        let (grant, grantSources) = try await requireGrant()
        let mounts = grantMounts(grant: grant, sources: grantSources)
        let cleaned = cleanPath(path)

        // Try mount-prefixed resolution first (e.g. "MyProject/src/main.swift")
        if let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) {
            return try await readFromMount(relativePath: relPath, mountPath: mount.mountPath, mountName: mount.mountName, grantID: grant.grantID)
        }

        // Fall back: try each mount with the raw path
        for mount in mounts {
            do {
                return try await readFromMount(relativePath: cleaned, mountPath: mount.mountPath, mountName: mount.mountName, grantID: grant.grantID)
            } catch is ManifoldMCPError { continue }
        }
        throw ManifoldMCPError.fileNotFound(path)
    }

    private func readFromMount(relativePath: String, mountPath: String, mountName: String, grantID: String) async throws -> String {
        let fileURL = try validatePath(relativePath, rootPath: mountPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ManifoldMCPError.fileNotFound(relativePath)
        }
        let data = try Data(contentsOf: fileURL)

        try? await auditStore.log(
            action: .fileRead,
            agent: "cowork",
            filePath: relativePath,
            metadata: ["grant_id": grantID, "mount": mountName]
        )
        ManifoldNotification.post(ManifoldNotification.fileAccessed, userInfo: [
            "path": relativePath, "action": "read", "agent": "cowork"
        ])

        if let text = String(data: data, encoding: .utf8) {
            return text
        } else {
            return "<binary file, \(data.count) bytes>"
        }
    }

    public func writeFile(path: String, content: String) async throws -> String {
        await logToolCall(tool: "write_file", arguments: ["path": path, "content_length": "\(content.count)"])
        let (grant, grantSources) = try await requireGrant()
        let mounts = grantMounts(grant: grant, sources: grantSources)
        let cleaned = cleanPath(path)

        guard !cleaned.hasPrefix("_emails/") else {
            throw ManifoldMCPError.invalidPath("Cannot write to email files (read-only)")
        }

        let data = content.data(using: .utf8) ?? Data()

        // Resolve which mount to write to
        let mountPath: String
        let mountName: String
        let resolvedPath: String
        if let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) {
            mountPath = mount.mountPath
            mountName = mount.mountName
            resolvedPath = relPath
        } else if let first = mounts.first {
            mountPath = first.mountPath
            mountName = first.mountName
            resolvedPath = cleaned
        } else {
            throw ManifoldMCPError.noSources
        }

        let fileURL = try validatePath(resolvedPath, rootPath: mountPath)
        let existed = FileManager.default.fileExists(atPath: fileURL.path)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)

        try? await auditStore.log(
            action: existed ? .fileModified : .fileCreated,
            agent: "cowork",
            filePath: resolvedPath,
            metadata: ["grant_id": grant.grantID, "mount": mountName]
        )
        ManifoldNotification.post(ManifoldNotification.dataChanged)

        return "Wrote \(data.count) bytes to \(resolvedPath) in \(mountName)"
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
                guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }

                let lines = content.components(separatedBy: "\n")
                let matching = lines.enumerated()
                    .filter { $0.element.localizedCaseInsensitiveContains(query) }
                    .prefix(5)
                    .map { "\($0.offset + 1): \($0.element.prefix(200))" }

                if !matching.isEmpty {
                    results.append((rel, dir.name, Array(matching)))
                }
                if results.count >= 50 { break }
            }
        }
        return results
    }

    // MARK: - Binary File Tools

    public func fileInfo(path: String) async throws -> FileMetadata {
        await logToolCall(tool: "file_info", arguments: ["path": path])
        let (grant, grantSources) = try await requireGrant()
        let mounts = grantMounts(grant: grant, sources: grantSources)
        let cleaned = cleanPath(path)

        var searchDirs: [(name: String, rootPath: String, resolvedPath: String)] = []
        if let (mount, relPath) = resolveMountAndPath(cleaned, in: mounts) {
            searchDirs.append((mount.mountName, mount.mountPath, relPath))
        }
        for mount in mounts { searchDirs.append((mount.mountName, mount.mountPath, cleaned)) }

        for entry in searchDirs {
            let fileURL = try? validatePath(entry.resolvedPath, rootPath: entry.rootPath)
            guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let size = (attrs[.size] as? Int) ?? 0
            let modified = (attrs[.modificationDate] as? Date).map { ISO8601DateFormatter().string(from: $0) } ?? ""
            let ext = fileURL.pathExtension.lowercased()

            let isBinary = ["zip", "pdf", "png", "jpg", "jpeg", "gif", "webp", "mp4", "mov",
                            "mp3", "wav", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
                            "ttf", "otf", "woff", "woff2", "epub"].contains(ext)

            var archiveContents: [String]?
            if ext == "zip" { archiveContents = listZipContents(at: fileURL) }

            return FileMetadata(
                path: path, sourceName: entry.name, sizeBytes: size,
                lastModified: modified, fileExtension: ext,
                isBinary: isBinary, archiveContents: archiveContents
            )
        }
        throw ManifoldMCPError.fileNotFound(path)
    }

    public func listArchive(path: String) async throws -> [String] {
        await logToolCall(tool: "list_archive", arguments: ["path": path])
        let (grant, grantSources) = try await requireGrant()
        let mounts = grantMounts(grant: grant, sources: grantSources)

        for mount in mounts {
            let fileURL = try? validatePath(path, rootPath: mount.mountPath)
            guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            guard let contents = listZipContents(at: fileURL) else {
                throw ManifoldMCPError.invalidPath("Not a valid zip archive: \(path)")
            }
            return contents
        }
        throw ManifoldMCPError.fileNotFound(path)
    }

    public func extractFile(archivePath: String, filePath: String) async throws -> String {
        await logToolCall(tool: "extract_file", arguments: ["archive": archivePath, "file": filePath])
        let (grant, grantSources) = try await requireGrant()
        let mounts = grantMounts(grant: grant, sources: grantSources)

        for mount in mounts {
            let archiveURL = try? validatePath(archivePath, rootPath: mount.mountPath)
            guard let archiveURL, FileManager.default.fileExists(atPath: archiveURL.path) else { continue }

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("manifold-extract-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", "-q", archiveURL.path, filePath, "-d", tempDir.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()

            let extractedURL = tempDir.appendingPathComponent(filePath)
            guard FileManager.default.fileExists(atPath: extractedURL.path) else {
                throw ManifoldMCPError.fileNotFound("'\(filePath)' not found in archive '\(archivePath)'")
            }

            let data = try Data(contentsOf: extractedURL)
            try? await auditStore.log(action: .fileRead, agent: "cowork", filePath: "\(archivePath)/\(filePath)")

            if let text = String(data: data, encoding: .utf8) {
                return text
            } else {
                return "<binary file, \(data.count) bytes>"
            }
        }
        throw ManifoldMCPError.fileNotFound(archivePath)
    }

    // MARK: - Zip Helpers

    private func listZipContents(at url: URL) -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-l", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        let lines = output.components(separatedBy: "\n")
        var files: [String] = []
        var started = false
        for line in lines {
            if line.contains("--------") {
                started = !started
                continue
            }
            guard started else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let components = trimmed.split(separator: " ", maxSplits: 3)
            guard components.count >= 4 else { continue }
            let filename = String(components[3])
            guard !filename.hasSuffix("/") else { continue }
            files.append(filename)
        }
        return files.isEmpty ? nil : files
    }

    // MARK: - Email Tools

    public func listEmails() async throws -> [EmailSummary] {
        await logToolCall(tool: "list_emails")
        _ = try await requireGrant()
        let shared = try await emailFilter.sharedEmails()
        return shared.map {
            EmailSummary(id: $0.messageID, from: $0.sender, subject: $0.subject, date: $0.dateReceived)
        }
    }

    public func readEmail(id: String) async throws -> String {
        await logToolCall(tool: "read_email", arguments: ["id": id])
        _ = try await requireGrant()
        let shared = try await emailFilter.sharedEmails()
        guard let email = shared.first(where: { $0.messageID == id }) else {
            throw ManifoldMCPError.fileNotFound("Email not found or not shared: \(id)")
        }

        try? await auditStore.log(
            action: .fileRead,
            agent: "cowork",
            metadata: ["type": "email", "messageID": id]
        )

        return """
        From: \(email.sender)
        Subject: \(email.subject)
        Date: \(email.dateReceived)

        \(email.bodyPreview ?? "(no preview available)")
        """
    }

    public func listChanges() async throws -> [ChangeEntry] {
        await logToolCall(tool: "list_changes")
        let (grant, _) = try await requireGrant()

        let entries = try await auditStore.recentEntries(limit: 50)
        return entries
            .filter { $0.metadata?.contains(grant.grantID) == true }
            .compactMap { entry -> ChangeEntry? in
                guard let filePath = entry.filePath else { return nil }
                let changeType: String
                switch entry.action {
                case "file_created": changeType = "created"
                case "file_modified": changeType = "modified"
                default: return nil
                }
                return ChangeEntry(
                    timestamp: entry.timestamp,
                    path: filePath,
                    source: "grant",
                    type: changeType,
                    agent: entry.agent ?? "cowork"
                )
            }
    }

    // MARK: - Session Memory

    /// List past session summaries.
    public func listSessions(limit: Int = 20) async throws -> [SessionInfo] {
        await logToolCall(tool: "list_sessions")
        let summaries = try await grantStore.allSummaries(limit: limit)
        return summaries.map { s in
            SessionInfo(
                grantID: s.grantID,
                targetApp: s.targetApp,
                startedAt: s.startedAt,
                endedAt: s.endedAt,
                summaryPreview: String(s.summaryMarkdown.prefix(200))
            )
        }
    }

    /// Get full session detail: summary + promotions.
    public func getSession(grantID: String) async throws -> SessionDetail {
        await logToolCall(tool: "get_session", arguments: ["grant_id": grantID])

        let grant = try await grantStore.grant(id: grantID)
        let summaries = try await grantStore.summaries(grantID: grantID)
        let promotions = try await grantStore.promotions(grantID: grantID)
        let grantSources = try await grantStore.grantSources(grantID: grantID)

        let sourceNames = grantSources.map(\.mountName)
        let applied = promotions.filter { $0.result == "applied" }
        let conflicts = promotions.filter { $0.result == "conflict" }

        return SessionDetail(
            grantID: grantID,
            targetApp: grant?.targetApp ?? "unknown",
            status: grant?.status ?? "unknown",
            startedAt: grant?.startedAt ?? "",
            endedAt: grant?.endedAt,
            sources: sourceNames,
            summaryMarkdown: summaries.first?.summaryMarkdown,
            filesApplied: applied.map(\.relativePath),
            filesConflicted: conflicts.map(\.relativePath),
            totalPromotions: promotions.count
        )
    }

    /// Save a session note/summary for the current active grant.
    public func saveSessionNote(note: String) async throws -> String {
        await logToolCall(tool: "save_session_note")

        guard let grant = try await grantStore.activeGrant(targetApp: .cowork, profileID: "default") else {
            throw ManifoldMCPError.noActiveSession
        }

        let now = ISO8601DateFormatter().string(from: Date())
        try await grantStore.saveSummary(
            grantID: grant.grantID,
            targetApp: .cowork,
            startedAt: grant.startedAt,
            endedAt: now,
            markdown: note
        )

        return "Session note saved for grant \(grant.grantID.prefix(12))..."
    }

    /// Auto-generate a session summary from grant activity.
    public func generateSessionSummary(grantID: String) async throws -> String {
        let grant = try await grantStore.grant(id: grantID)
        let promotions = try await grantStore.promotions(grantID: grantID)
        let grantSources = try await grantStore.grantSources(grantID: grantID)

        let applied = promotions.filter { $0.result == "applied" }
        let conflicts = promotions.filter { $0.result == "conflict" }
        let newFiles = promotions.filter { $0.result == "new_file" }

        var lines: [String] = []
        lines.append("# Session Summary")
        lines.append("")
        lines.append("- **Grant:** \(grantID.prefix(12))...")
        lines.append("- **Target:** \(grant?.targetApp ?? "unknown")")
        lines.append("- **Started:** \(grant?.startedAt ?? "unknown")")
        if let ended = grant?.endedAt {
            lines.append("- **Ended:** \(ended)")
        }
        lines.append("- **Sources:** \(grantSources.map(\.mountName).joined(separator: ", "))")
        lines.append("")

        if !applied.isEmpty {
            lines.append("## Files Modified (\(applied.count))")
            for p in applied { lines.append("- `\(p.relativePath)`") }
            lines.append("")
        }

        if !newFiles.isEmpty {
            lines.append("## Files Created (\(newFiles.count))")
            for p in newFiles { lines.append("- `\(p.relativePath)`") }
            lines.append("")
        }

        if !conflicts.isEmpty {
            lines.append("## Conflicts (\(conflicts.count))")
            for p in conflicts {
                lines.append("- `\(p.relativePath)` — \(p.conflictReason ?? "original changed during session")")
            }
            lines.append("")
        }

        if promotions.isEmpty {
            lines.append("_No file changes recorded._")
        }

        let markdown = lines.joined(separator: "\n")

        let now = ISO8601DateFormatter().string(from: Date())
        try await grantStore.saveSummary(
            grantID: grantID,
            targetApp: TargetApp(rawValue: grant?.targetApp ?? "cowork") ?? .cowork,
            startedAt: grant?.startedAt ?? now,
            endedAt: grant?.endedAt ?? now,
            markdown: markdown
        )

        return markdown
    }

    // MARK: - Grant Path Resolution

    private func resolveMountAndPath(
        _ path: String,
        in mounts: [(mountName: String, mountPath: String)]
    ) -> (mount: (mountName: String, mountPath: String), relativePath: String)? {
        let components = path.split(separator: "/", maxSplits: 1)
        guard components.count >= 2 else { return nil }
        let prefix = String(components[0])
        let rest = String(components[1])
        if let mount = mounts.first(where: { $0.mountName == prefix }) {
            return (mount, rest)
        }
        return nil
    }

    /// Safe relative path computation using resolved symlinks.
    private func relativePath(file: URL, base: URL) -> String {
        let resolvedFile = file.resolvingSymlinksInPath().path
        let resolvedBase = base.resolvingSymlinksInPath().path + "/"
        if resolvedFile.hasPrefix(resolvedBase) {
            return String(resolvedFile.dropFirst(resolvedBase.count))
        }
        return file.path.replacingOccurrences(of: base.path + "/", with: "")
    }

    // MARK: - Helpers

    private func enumerateFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true { files.append(url) }
        }
        return files
    }
}

// MARK: - Types

public struct FileInfo: Sendable {
    public let path: String
    public let sourceName: String
    public let sourceAddedAt: String
    public let sizeBytes: Int
    public let lastModified: String
}

public struct SourceDetail: Sendable {
    public let name: String
    public let status: String
    public let fileCount: Int
}

public struct StatusResult: Sendable {
    public let active: Bool
    public let grantID: String?
    public let sources: [String]
    public let pausedSources: [String]
    public let fileCount: Int
    public let emailCount: Int
    public let message: String
}

public struct FileMetadata: Sendable {
    public let path: String
    public let sourceName: String
    public let sizeBytes: Int
    public let lastModified: String
    public let fileExtension: String
    public let isBinary: Bool
    public let archiveContents: [String]?
}

public struct EmailSummary: Sendable {
    public let id: String
    public let from: String
    public let subject: String
    public let date: String
}

public struct ChangeEntry: Sendable {
    public let timestamp: String
    public let path: String
    public let source: String
    public let type: String
    public let agent: String
}

public struct SessionInfo: Sendable {
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

public enum ManifoldMCPError: Error, LocalizedError {
    case noSources
    case allSourcesPaused
    case noActiveSession
    case invalidPath(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .noSources: return "No sources configured. Open Manifold and add a folder."
        case .allSourcesPaused: return "All sources are paused. Open Manifold and resume at least one source to grant access."
        case .noActiveSession: return "No active session. Start a session in Manifold first."
        case .invalidPath(let msg): return "Invalid path: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        }
    }

    public var isPathError: Bool {
        if case .invalidPath = self { return true }
        return false
    }
}
