import Foundation

/// A stable workspace directory tied to an access profile.
/// One workspace per profile — Cowork points at the same folder across restarts.
/// Files are copied in on sync, not generated fresh each time.
public struct ManagedWorkspace: Sendable, Codable {
    public let workspaceID: String
    public let profileID: String
    public let agent: String
    public let rootPath: String
    public let createdAt: Date
    public var lastSyncedAt: Date?
    public var currentRunID: String?
    public var status: Status

    public enum Status: String, Sendable, Codable {
        case active    // Has a current run, agent may be working
        case idle      // No active run, workspace exists on disk
        case archived  // Workspace preserved but no longer in use
    }

    public var rootURL: URL { URL(fileURLWithPath: rootPath) }
    public var emailsURL: URL { rootURL.appendingPathComponent("_emails") }

    public init(profileID: String, agent: String, baseURL: URL) {
        self.workspaceID = UUID().uuidString.prefix(8).lowercased().description
        self.profileID = profileID
        self.agent = agent
        self.rootPath = baseURL
            .appendingPathComponent("profiles")
            .appendingPathComponent(profileID)
            .path
        self.createdAt = Date()
        self.lastSyncedAt = nil
        self.currentRunID = nil
        self.status = .idle
    }

    /// Ensure the workspace directory exists on disk.
    public func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: emailsURL,
            withIntermediateDirectories: true
        )
    }

    /// Sync source files into the workspace. Copies from sources, overwriting existing.
    /// Returns the list of files synced (relative paths).
    @discardableResult
    public func syncSources(_ sourcePaths: [URL]) throws -> [String] {
        let fm = FileManager.default
        var synced: [String] = []

        for source in sourcePaths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                let dirName = source.lastPathComponent
                let destDir = rootURL.appendingPathComponent(dirName)
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

                let resolvedSource = source.resolvingSymlinksInPath()
                guard let enumerator = fm.enumerator(
                    at: resolvedSource,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                while let fileURL = enumerator.nextObject() as? URL {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    guard resourceValues.isRegularFile == true else { continue }

                    let resolvedFile = fileURL.resolvingSymlinksInPath()
                    let sourcePrefix = resolvedSource.path.hasSuffix("/") ? resolvedSource.path : resolvedSource.path + "/"
                    let relativePath = resolvedFile.path.replacingOccurrences(of: sourcePrefix, with: "")
                    let destFile = destDir.appendingPathComponent(relativePath)

                    try fm.createDirectory(at: destFile.deletingLastPathComponent(), withIntermediateDirectories: true)

                    // Overwrite if exists
                    if fm.fileExists(atPath: destFile.path) {
                        try fm.removeItem(at: destFile)
                    }
                    try fm.copyItem(at: fileURL, to: destFile)

                    synced.append(dirName + "/" + relativePath)
                }
            } else {
                let dest = rootURL.appendingPathComponent(source.lastPathComponent)
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: source, to: dest)
                synced.append(source.lastPathComponent)
            }
        }

        return synced
    }

    /// Sync email files into the _emails/ subdirectory as read-only.
    public func syncEmails(_ emailFiles: [URL]) throws {
        let fm = FileManager.default
        for emailFile in emailFiles {
            let dest = emailsURL.appendingPathComponent(emailFile.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: emailFile, to: dest)
            try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: dest.path)
        }
    }

    /// Get all file URLs in the workspace (recursively).
    public func allFiles() throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues.isRegularFile == true {
                files.append(fileURL)
            }
        }
        return files
    }

    /// Get the relative path of a file URL within this workspace.
    public func relativePath(for fileURL: URL) -> String? {
        let filePath = fileURL.standardizedFileURL.path
        let basePath = rootURL.standardizedFileURL.path + "/"
        guard filePath.hasPrefix(basePath) else { return nil }
        return String(filePath.dropFirst(basePath.count))
    }
}
