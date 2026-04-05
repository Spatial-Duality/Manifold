import Foundation
import ManifoldKit

/// Core logic layer between MCP protocol and ManifoldKit stores.
/// Global access model: any registered workspace is accessible. No "run" required.
public actor ManifoldBridge {
    private let db: DatabaseConnection
    private let contentStore: ContentStore
    private let snapshotStore: SnapshotStore
    private let leaseManager: WorkspaceLeaseManager
    private let auditStore: AuditStore
    private let emailFilter: EmailFilter

    public init(
        db: DatabaseConnection,
        contentStore: ContentStore,
        snapshotStore: SnapshotStore,
        leaseManager: WorkspaceLeaseManager,
        auditStore: AuditStore,
        emailFilter: EmailFilter
    ) {
        self.db = db
        self.contentStore = contentStore
        self.snapshotStore = snapshotStore
        self.leaseManager = leaseManager
        self.auditStore = auditStore
        self.emailFilter = emailFilter
    }

    // MARK: - Workspace Resolution (Global Access)

    /// Returns all registered workspaces with their status.
    private func allWorkspaces() throws -> [WorkspaceInfo] {
        let rows = try db.queryAll("SELECT workspace_id, root_path, agent, status, created_at FROM workspaces")
        return rows.compactMap { row in
            guard let wsID = row["workspace_id"],
                  let rootPath = row["root_path"],
                  let agent = row["agent"],
                  let status = row["status"] ?? .some("idle"),
                  let createdAt = row["created_at"] else { return nil }
            return WorkspaceInfo(workspaceID: wsID, rootPath: rootPath, agent: agent, status: status, createdAt: createdAt)
        }
    }

    /// Returns only active (non-archived) workspaces. Use this for all agent-facing tools.
    private func activeWorkspaces() throws -> [WorkspaceInfo] {
        try allWorkspaces().filter(\.isActive)
    }

    /// Ensure at least one active workspace exists. Gives a clear error if all are paused.
    private func requireActiveWorkspaces() throws -> [WorkspaceInfo] {
        let all = try allWorkspaces()
        let active = all.filter(\.isActive)
        if active.isEmpty {
            if all.isEmpty {
                throw ManifoldMCPError.noSources
            } else {
                throw ManifoldMCPError.allSourcesPaused
            }
        }
        return active
    }

    /// Ensure at least one active workspace exists.
    private func requireWorkspaces() throws -> [WorkspaceInfo] {
        try requireActiveWorkspaces()
    }

    // MARK: - Path Safety

    /// Cleans a relative path: strips leading "./", collapses double slashes,
    /// and removes trailing slashes.
    private func cleanPath(_ path: String) -> String {
        var cleaned = path
        // Strip leading "./"
        while cleaned.hasPrefix("./") {
            cleaned = String(cleaned.dropFirst(2))
        }
        // Collapse double slashes
        while cleaned.contains("//") {
            cleaned = cleaned.replacingOccurrences(of: "//", with: "/")
        }
        // Strip trailing slash
        while cleaned.hasSuffix("/") && cleaned.count > 1 {
            cleaned = String(cleaned.dropLast())
        }
        return cleaned
    }

    /// Resolves a path that may include the source folder name as a prefix.
    /// e.g. if workspaces = ["/Users/x/current"], path = "current/file.md"
    /// returns (workspace for "current", "file.md") instead of treating
    /// "current" as a subdirectory.
    private func resolveWorkspaceAndPath(
        _ path: String,
        in workspaces: [WorkspaceInfo]
    ) -> (workspace: WorkspaceInfo, relativePath: String)? {
        let cleaned = cleanPath(path)
        let components = cleaned.split(separator: "/", maxSplits: 1)

        // Check if the first component matches a workspace folder name
        if components.count >= 2 {
            let prefix = String(components[0])
            let rest = String(components[1])
            if let ws = workspaces.first(where: { $0.folderName == prefix }) {
                return (ws, rest)
            }
        }
        return nil
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
            let workspaces = try allWorkspaces()
            guard !workspaces.isEmpty else {
                return StatusResult(
                    active: false, sources: [], pausedSources: [], fileCount: 0, emailCount: 0,
                    message: "No sources configured. Open Manifold and add a folder."
                )
            }

            var totalFiles = 0
            var sourceDetails: [SourceDetail] = []

            for ws in workspaces {
                let root = URL(fileURLWithPath: ws.rootPath)
                let fileCount: Int
                if ws.isActive {
                    fileCount = (try? enumerateFiles(in: root).count) ?? 0
                    totalFiles += fileCount
                } else {
                    fileCount = 0
                }
                sourceDetails.append(SourceDetail(
                    name: ws.folderName,
                    status: ws.isActive ? "active" : "paused",
                    fileCount: fileCount
                ))
            }

            let activeCount = sourceDetails.filter { $0.status == "active" }.count
            let pausedCount = sourceDetails.filter { $0.status == "paused" }.count
            let emailCount = (try? await emailFilter.sharedEmails().count) ?? 0

            let sourceSummary = sourceDetails.map { "\($0.name) (\($0.status))" }.joined(separator: ", ")
            var message = "Manifold active. \(workspaces.count) source(s): \(sourceSummary). \(totalFiles) files"
            if pausedCount > 0 {
                message += " (\(pausedCount) source\(pausedCount == 1 ? "" : "s") paused, not accessible)"
            }
            message += ", \(emailCount) emails available."

            return StatusResult(
                active: activeCount > 0,
                sources: sourceDetails.filter { $0.status == "active" }.map(\.name),
                pausedSources: sourceDetails.filter { $0.status == "paused" }.map(\.name),
                fileCount: totalFiles,
                emailCount: emailCount,
                message: message
            )
        } catch {
            return StatusResult(
                active: false, sources: [], pausedSources: [], fileCount: 0, emailCount: 0,
                message: "Error: \(error.localizedDescription)"
            )
        }
    }

    public func listFiles() async throws -> [FileInfo] {
        await logToolCall(tool: "list_files")
        let workspaces = try requireWorkspaces()
        var allFiles: [FileInfo] = []

        for ws in workspaces {
            let root = URL(fileURLWithPath: ws.rootPath)
            let sourceName = root.lastPathComponent
            let files = try enumerateFiles(in: root)

            for file in files {
                let rel = file.path.replacingOccurrences(of: root.path + "/", with: "")
                guard !rel.hasPrefix("_emails/") else { continue }

                let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
                let size = (attrs?[.size] as? Int) ?? 0
                let modified = (attrs?[.modificationDate] as? Date).map { ISO8601DateFormatter().string(from: $0) } ?? ""

                allFiles.append(FileInfo(
                    path: rel,
                    sourceName: sourceName,
                    sourceAddedAt: ws.createdAt,
                    sizeBytes: size,
                    lastModified: modified
                ))
            }
        }
        return allFiles.sorted { $0.path < $1.path }
    }

    public func readFile(path: String) async throws -> String {
        await logToolCall(tool: "read_file", arguments: ["path": path])
        let workspaces = try requireWorkspaces()
        let cleaned = cleanPath(path)

        // Smart resolve: if path starts with a source folder name, try that workspace first
        if let match = resolveWorkspaceAndPath(cleaned, in: workspaces) {
            do {
                return try await readFileFrom(
                    resolvedPath: match.relativePath, workspace: match.workspace
                )
            } catch { /* fall through to normal resolution */ }
        }

        // Fall back: try each workspace with the cleaned path
        for ws in workspaces {
            do {
                return try await readFileFrom(resolvedPath: cleaned, workspace: ws)
            } catch is ManifoldMCPError {
                continue
            }
        }
        throw ManifoldMCPError.fileNotFound(path)
    }

    private func readFileFrom(resolvedPath: String, workspace ws: WorkspaceInfo) async throws -> String {
        let fileURL = try validatePath(resolvedPath, rootPath: ws.rootPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ManifoldMCPError.fileNotFound(resolvedPath)
        }
        let data = try Data(contentsOf: fileURL)

        try? await auditStore.log(
            action: .fileRead,
            workspaceID: ws.workspaceID,
            agent: "cowork",
            filePath: resolvedPath
        )
        ManifoldNotification.post(ManifoldNotification.fileAccessed, userInfo: [
            "path": resolvedPath, "action": "read", "agent": "cowork"
        ])

        if let text = String(data: data, encoding: .utf8) {
            return text
        } else {
            return "<binary file, \(data.count) bytes>"
        }
    }

    public func writeFile(path: String, content: String) async throws -> String {
        await logToolCall(tool: "write_file", arguments: ["path": path, "content_length": "\(content.count)"])
        let workspaces = try requireWorkspaces()
        let cleaned = cleanPath(path)
        guard !cleaned.hasPrefix("_emails/") else {
            throw ManifoldMCPError.invalidPath("Cannot write to email files (read-only)")
        }

        // Smart resolve: if path starts with a source folder name, strip it
        let ws: WorkspaceInfo
        let resolvedPath: String
        if let match = resolveWorkspaceAndPath(cleaned, in: workspaces) {
            ws = match.workspace
            resolvedPath = match.relativePath
        } else {
            ws = workspaces[0]
            resolvedPath = cleaned
        }
        let fileURL = try validatePath(resolvedPath, rootPath: ws.rootPath)
        let data = content.data(using: .utf8) ?? Data()
        let existed = FileManager.default.fileExists(atPath: fileURL.path)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)

        // Auto-create a run for snapshotting if none exists
        var runID: String
        if let active = try? await leaseManager.activeRun(workspaceID: ws.workspaceID) {
            runID = active.runID
        } else {
            runID = try await leaseManager.startRun(workspaceID: ws.workspaceID, agent: "cowork", trigger: .autoResume)
        }

        if existed {
            try await snapshotStore.recordModification(
                runID: runID, workspaceID: ws.workspaceID,
                filePath: resolvedPath, newData: data, source: "mcp"
            )
        } else {
            try await snapshotStore.recordCreation(
                runID: runID, workspaceID: ws.workspaceID,
                filePath: resolvedPath, data: data
            )
        }

        try? await auditStore.log(
            action: existed ? .fileModified : .fileCreated,
            workspaceID: ws.workspaceID,
            agent: "cowork",
            filePath: resolvedPath
        )
        ManifoldNotification.post(ManifoldNotification.dataChanged)

        return "Wrote \(data.count) bytes to \(resolvedPath) in \(ws.folderName)"
    }

    public func searchFiles(query: String) async throws -> [(path: String, source: String, matches: [String])] {
        await logToolCall(tool: "search_files", arguments: ["query": query])
        let workspaces = try requireWorkspaces()
        var results: [(path: String, source: String, matches: [String])] = []

        for ws in workspaces {
            let root = URL(fileURLWithPath: ws.rootPath)
            let sourceName = root.lastPathComponent
            let files = try enumerateFiles(in: root)

            for file in files {
                let rel = file.path.replacingOccurrences(of: root.path + "/", with: "")
                guard !rel.hasPrefix("_emails/") else { continue }
                guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }

                let lines = content.components(separatedBy: "\n")
                let matching = lines.enumerated()
                    .filter { $0.element.localizedCaseInsensitiveContains(query) }
                    .prefix(5)
                    .map { "\($0.offset + 1): \($0.element.prefix(200))" }

                if !matching.isEmpty {
                    results.append((rel, sourceName, Array(matching)))
                }
                if results.count >= 50 { break }
            }
        }
        return results
    }

    // MARK: - Binary File Tools

    /// Get detailed info about a file (MIME type, size, is binary, archive contents if zip).
    public func fileInfo(path: String) async throws -> FileMetadata {
        await logToolCall(tool: "file_info", arguments: ["path": path])
        let workspaces = try requireWorkspaces()
        let cleaned = cleanPath(path)

        // Build resolution order: smart match first, then all workspaces
        var searchOrder: [(ws: WorkspaceInfo, resolvedPath: String)] = []
        if let match = resolveWorkspaceAndPath(cleaned, in: workspaces) {
            searchOrder.append((match.workspace, match.relativePath))
        }
        for ws in workspaces {
            searchOrder.append((ws, cleaned))
        }

        for entry in searchOrder {
            let fileURL = try? validatePath(entry.resolvedPath, rootPath: entry.ws.rootPath)
            guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            let ws = entry.ws

            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let size = (attrs[.size] as? Int) ?? 0
            let modified = (attrs[.modificationDate] as? Date).map { ISO8601DateFormatter().string(from: $0) } ?? ""
            let ext = fileURL.pathExtension.lowercased()

            let isBinary = ["zip", "pdf", "png", "jpg", "jpeg", "gif", "webp", "mp4", "mov",
                            "mp3", "wav", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
                            "ttf", "otf", "woff", "woff2", "epub"].contains(ext)

            var archiveContents: [String]?
            if ext == "zip" {
                archiveContents = listZipContents(at: fileURL)
            }

            return FileMetadata(
                path: path,
                sourceName: URL(fileURLWithPath: ws.rootPath).lastPathComponent,
                sizeBytes: size,
                lastModified: modified,
                fileExtension: ext,
                isBinary: isBinary,
                archiveContents: archiveContents
            )
        }
        throw ManifoldMCPError.fileNotFound(path)
    }

    /// List contents of a zip archive without extracting.
    public func listArchive(path: String) async throws -> [String] {
        await logToolCall(tool: "list_archive", arguments: ["path": path])
        let workspaces = try requireWorkspaces()

        for ws in workspaces {
            let fileURL = try? validatePath(path, rootPath: ws.rootPath)
            guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            guard let contents = listZipContents(at: fileURL) else {
                throw ManifoldMCPError.invalidPath("Not a valid zip archive: \(path)")
            }
            return contents
        }
        throw ManifoldMCPError.fileNotFound(path)
    }

    /// Extract a single file from a zip archive and return its text content.
    public func extractFile(archivePath: String, filePath: String) async throws -> String {
        await logToolCall(tool: "extract_file", arguments: ["archive": archivePath, "file": filePath])
        let workspaces = try requireWorkspaces()

        for ws in workspaces {
            let archiveURL = try? validatePath(archivePath, rootPath: ws.rootPath)
            guard let archiveURL, FileManager.default.fileExists(atPath: archiveURL.path) else { continue }

            // Extract to temp directory
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

            // Audit
            try? await auditStore.log(
                action: .fileRead,
                agent: "cowork",
                filePath: "\(archivePath)/\(filePath)"
            )

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

        // Parse unzip -l output: skip header lines, extract filenames
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
            // Format: size date time filename
            let components = trimmed.split(separator: " ", maxSplits: 3)
            guard components.count >= 4 else { continue }
            let filename = String(components[3])
            guard !filename.hasSuffix("/") else { continue } // skip directories
            files.append(filename)
        }
        return files.isEmpty ? nil : files
    }

    // MARK: - Email Tools

    public func listEmails() async throws -> [EmailSummary] {
        await logToolCall(tool: "list_emails")
        _ = try requireWorkspaces()
        let shared = try await emailFilter.sharedEmails()
        return shared.map {
            EmailSummary(id: $0.messageID, from: $0.sender, subject: $0.subject, date: $0.dateReceived)
        }
    }

    public func readEmail(id: String) async throws -> String {
        await logToolCall(tool: "read_email", arguments: ["id": id])
        _ = try requireWorkspaces()
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
        let workspaces = try requireWorkspaces()
        var allChanges: [ChangeEntry] = []

        for ws in workspaces {
            let timeline = try await snapshotStore.workspaceTimeline(workspaceID: ws.workspaceID)
            let changes = timeline
                .filter { !$0.isBaseline }
                .prefix(25)
                .map { record in
                    let changeType: String
                    if record.isDelete { changeType = "deleted" }
                    else if record.beforeHash == nil { changeType = "created" }
                    else if record.source == "manifold-restore" { changeType = "restored" }
                    else { changeType = "modified" }
                    return ChangeEntry(
                        timestamp: record.timestamp,
                        path: record.filePath,
                        source: URL(fileURLWithPath: ws.rootPath).lastPathComponent,
                        type: changeType,
                        agent: record.source
                    )
                }
            allChanges.append(contentsOf: changes)
        }
        return allChanges.sorted { $0.timestamp > $1.timestamp }.prefix(50).map { $0 }
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

struct WorkspaceInfo: Sendable {
    let workspaceID: String
    let rootPath: String
    let agent: String
    let status: String
    let createdAt: String

    var folderName: String {
        URL(fileURLWithPath: rootPath).lastPathComponent
    }
    var isActive: Bool {
        status == "idle" || status == "active"
    }
}

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

public enum ManifoldMCPError: Error, LocalizedError {
    case noSources
    case allSourcesPaused
    case invalidPath(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .noSources: return "No sources configured. Open Manifold and add a folder."
        case .allSourcesPaused: return "All sources are paused. Open Manifold and resume at least one source to grant access."
        case .invalidPath(let msg): return "Invalid path: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        }
    }

    public var isPathError: Bool {
        if case .invalidPath = self { return true }
        return false
    }
}
