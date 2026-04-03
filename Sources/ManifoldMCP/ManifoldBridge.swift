import Foundation
import ManifoldKit

/// Core logic layer between MCP protocol and ManifoldKit stores.
/// Reads rules from the shared SQLite database. Enforces access control.
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

    // MARK: - Active Run Resolution

    private func resolveActiveRun() async throws -> (workspaceID: String, runID: String, rootPath: String) {
        let rows = try db.queryAll("SELECT workspace_id, root_path FROM workspaces WHERE status = 'active' LIMIT 1")
        guard let ws = rows.first, let wsID = ws["workspace_id"], let rootPath = ws["root_path"] else {
            throw ManifoldMCPError.noActiveRun
        }
        guard let run = try await leaseManager.activeRun(workspaceID: wsID) else {
            throw ManifoldMCPError.noActiveRun
        }
        return (wsID, run.runID, rootPath)
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

    // MARK: - Tools

    public func getStatus() async -> StatusResult {
        do {
            let (wsID, runID, rootPath) = try await resolveActiveRun()
            let root = URL(fileURLWithPath: rootPath)
            let files = (try? enumerateFiles(in: root)) ?? []
            let emailCount = (try? await emailFilter.sharedEmails().count) ?? 0
            return StatusResult(
                active: true,
                runID: runID,
                workspaceID: wsID,
                fileCount: files.count,
                emailCount: emailCount,
                message: "Access granted. \(files.count) files, \(emailCount) emails available."
            )
        } catch {
            return StatusResult(
                active: false, runID: nil, workspaceID: nil,
                fileCount: 0, emailCount: 0,
                message: "No active access run. Open Manifold and click 'Grant to Claude' first."
            )
        }
    }

    public func listFiles() async throws -> [String] {
        let (_, _, rootPath) = try await resolveActiveRun()
        let root = URL(fileURLWithPath: rootPath)
        let files = try enumerateFiles(in: root)
        return files.compactMap { url in
            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
            return rel.hasPrefix("_emails/") ? nil : rel
        }.sorted()
    }

    public func readFile(path: String) async throws -> String {
        let (wsID, runID, rootPath) = try await resolveActiveRun()
        let fileURL = try validatePath(path, rootPath: rootPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ManifoldMCPError.fileNotFound(path)
        }
        let data = try Data(contentsOf: fileURL)

        // Audit the read
        try? await auditStore.log(
            action: .fileRead,
            runID: runID,
            workspaceID: wsID,
            filePath: path
        )

        if let text = String(data: data, encoding: .utf8) {
            return text
        } else {
            return "<binary file, \(data.count) bytes>"
        }
    }

    public func writeFile(path: String, content: String) async throws -> String {
        let (wsID, runID, rootPath) = try await resolveActiveRun()
        guard !path.hasPrefix("_emails/") else {
            throw ManifoldMCPError.invalidPath("Cannot write to email files (read-only)")
        }
        let fileURL = try validatePath(path, rootPath: rootPath)
        let data = content.data(using: .utf8) ?? Data()
        let existed = FileManager.default.fileExists(atPath: fileURL.path)

        // Create parent directories
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Write
        try data.write(to: fileURL, options: .atomic)

        // Snapshot
        if existed {
            try await snapshotStore.recordModification(
                runID: runID, workspaceID: wsID,
                filePath: path, newData: data, source: "mcp"
            )
        } else {
            try await snapshotStore.recordCreation(
                runID: runID, workspaceID: wsID,
                filePath: path, data: data
            )
        }

        // Audit
        try? await auditStore.log(
            action: existed ? .fileModified : .fileCreated,
            runID: runID, workspaceID: wsID,
            filePath: path
        )

        return "Wrote \(data.count) bytes to \(path)"
    }

    public func searchFiles(query: String) async throws -> [(path: String, matches: [String])] {
        let (_, _, rootPath) = try await resolveActiveRun()
        let root = URL(fileURLWithPath: rootPath)
        let files = try enumerateFiles(in: root)
        var results: [(path: String, matches: [String])] = []

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
                results.append((rel, Array(matching)))
            }
            if results.count >= 50 { break }
        }
        return results
    }

    public func listEmails() async throws -> [EmailSummary] {
        let _ = try await resolveActiveRun()
        let shared = try await emailFilter.sharedEmails()
        return shared.map {
            EmailSummary(id: $0.messageID, from: $0.sender, subject: $0.subject, date: $0.dateReceived)
        }
    }

    public func readEmail(id: String) async throws -> String {
        let (wsID, runID, _) = try await resolveActiveRun()
        let shared = try await emailFilter.sharedEmails()
        guard let email = shared.first(where: { $0.messageID == id }) else {
            throw ManifoldMCPError.fileNotFound("Email not found or not shared: \(id)")
        }

        try? await auditStore.log(
            action: .fileRead, runID: runID, workspaceID: wsID,
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
        let (_, runID, _) = try await resolveActiveRun()
        let timeline = try await snapshotStore.runTimeline(runID: runID)
        return timeline
            .filter { !$0.isBaseline }
            .prefix(50)
            .map { record in
                let changeType: String
                if record.isDelete { changeType = "deleted" }
                else if record.beforeHash == nil { changeType = "created" }
                else if record.source == "manifold-restore" { changeType = "restored" }
                else { changeType = "modified" }
                return ChangeEntry(timestamp: record.timestamp, path: record.filePath, type: changeType, source: record.source)
            }
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

public struct StatusResult: Sendable {
    public let active: Bool
    public let runID: String?
    public let workspaceID: String?
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
    public let type: String
    public let source: String
}

public enum ManifoldMCPError: Error, LocalizedError {
    case noActiveRun
    case invalidPath(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .noActiveRun: return "No active access run. Open Manifold and click 'Grant to Claude' first."
        case .invalidPath(let msg): return "Invalid path: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        }
    }
}
