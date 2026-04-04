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

    /// Returns all registered workspaces. No active run required.
    private func allWorkspaces() throws -> [WorkspaceInfo] {
        let rows = try db.queryAll("SELECT workspace_id, root_path, agent, created_at FROM workspaces")
        return rows.compactMap { row in
            guard let wsID = row["workspace_id"],
                  let rootPath = row["root_path"],
                  let agent = row["agent"],
                  let createdAt = row["created_at"] else { return nil }
            return WorkspaceInfo(workspaceID: wsID, rootPath: rootPath, agent: agent, createdAt: createdAt)
        }
    }

    /// Ensure at least one workspace exists.
    private func requireWorkspaces() throws -> [WorkspaceInfo] {
        let workspaces = try allWorkspaces()
        guard !workspaces.isEmpty else {
            throw ManifoldMCPError.noSources
        }
        return workspaces
    }

    // MARK: - Path Safety

    private func validatePath(_ path: String, rootPath: String) throws -> URL {
        guard !path.hasPrefix("/") else { throw ManifoldMCPError.invalidPath("Absolute paths not allowed") }
        guard !path.contains("..") else { throw ManifoldMCPError.invalidPath("Path traversal not allowed") }
        let root = URL(fileURLWithPath: rootPath)
        let resolved = root.appendingPathComponent(path).standardizedFileURL
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
                    active: false, sources: [], fileCount: 0, emailCount: 0,
                    message: "No sources configured. Open Manifold and add a folder."
                )
            }
            var totalFiles = 0
            var sourceNames: [String] = []
            for ws in workspaces {
                let root = URL(fileURLWithPath: ws.rootPath)
                let files = (try? enumerateFiles(in: root)) ?? []
                totalFiles += files.count
                sourceNames.append(URL(fileURLWithPath: ws.rootPath).lastPathComponent)
            }
            let emailCount = (try? await emailFilter.sharedEmails().count) ?? 0
            return StatusResult(
                active: true,
                sources: sourceNames,
                fileCount: totalFiles,
                emailCount: emailCount,
                message: "Manifold active. \(workspaces.count) source(s): \(sourceNames.joined(separator: ", ")). \(totalFiles) files, \(emailCount) emails available."
            )
        } catch {
            return StatusResult(
                active: false, sources: [], fileCount: 0, emailCount: 0,
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

        // Try each workspace to find the file
        for ws in workspaces {
            do {
                let fileURL = try validatePath(path, rootPath: ws.rootPath)
                guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
                let data = try Data(contentsOf: fileURL)

                try? await auditStore.log(
                    action: .fileRead,
                    workspaceID: ws.workspaceID,
                    agent: "cowork",
                    filePath: path
                )
                ManifoldNotification.post(ManifoldNotification.fileAccessed, userInfo: [
                    "path": path, "action": "read", "agent": "cowork"
                ])

                if let text = String(data: data, encoding: .utf8) {
                    return text
                } else {
                    return "<binary file, \(data.count) bytes>"
                }
            } catch is ManifoldMCPError {
                continue
            }
        }
        throw ManifoldMCPError.fileNotFound(path)
    }

    public func writeFile(path: String, content: String) async throws -> String {
        await logToolCall(tool: "write_file", arguments: ["path": path, "content_length": "\(content.count)"])
        let workspaces = try requireWorkspaces()
        guard !path.hasPrefix("_emails/") else {
            throw ManifoldMCPError.invalidPath("Cannot write to email files (read-only)")
        }

        // Use first workspace that can resolve the path
        let ws = workspaces[0]
        let fileURL = try validatePath(path, rootPath: ws.rootPath)
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
                filePath: path, newData: data, source: "mcp"
            )
        } else {
            try await snapshotStore.recordCreation(
                runID: runID, workspaceID: ws.workspaceID,
                filePath: path, data: data
            )
        }

        try? await auditStore.log(
            action: existed ? .fileModified : .fileCreated,
            workspaceID: ws.workspaceID,
            agent: "cowork",
            filePath: path
        )
        ManifoldNotification.post(ManifoldNotification.dataChanged)

        return "Wrote \(data.count) bytes to \(path) in \(URL(fileURLWithPath: ws.rootPath).lastPathComponent)"
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
    let createdAt: String
}

public struct FileInfo: Sendable {
    public let path: String
    public let sourceName: String
    public let sourceAddedAt: String
    public let sizeBytes: Int
    public let lastModified: String
}

public struct StatusResult: Sendable {
    public let active: Bool
    public let sources: [String]
    public let fileCount: Int
    public let emailCount: Int
    public let message: String
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
    case invalidPath(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .noSources: return "No sources configured. Open Manifold and add a folder."
        case .invalidPath(let msg): return "Invalid path: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        }
    }

    public var isPathError: Bool {
        if case .invalidPath = self { return true }
        return false
    }
}
