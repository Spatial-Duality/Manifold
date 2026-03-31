import Foundation

/// Creates and manages Manifold workspace directories.
/// Copies files from sources into a managed directory that agents can read/write.
/// Original source files are never modified by agents.
public struct WorkspaceGenerator: Sendable {
    private let baseURL: URL

    /// Root directory for all workspaces.
    /// Default: ~/Library/Application Support/Manifold/workspaces/
    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Generate a new workspace for an agent session.
    /// Copies all files from source paths into the workspace directory.
    /// Returns the workspace URL and session ID.
    public func generate(
        agent: String,
        sourcePaths: [URL],
        emailFiles: [URL] = []
    ) throws -> Workspace {
        let sessionID = "\(agent)-\(UUID().uuidString.prefix(8).lowercased())"
        let workspaceURL = baseURL.appendingPathComponent(sessionID)

        // Create workspace directory
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        // Copy source files into workspace, preserving relative structure
        var fileMap: [String: URL] = [:] // relative path -> source URL
        for sourcePath in sourcePaths {
            try copySource(sourcePath, into: workspaceURL, fileMap: &fileMap)
        }

        // Copy email files into _emails/ subdirectory as read-only
        if !emailFiles.isEmpty {
            let emailsDir = workspaceURL.appendingPathComponent("_emails")
            try FileManager.default.createDirectory(at: emailsDir, withIntermediateDirectories: true)

            for emailFile in emailFiles {
                let dest = emailsDir.appendingPathComponent(emailFile.lastPathComponent)
                try FileManager.default.copyItem(at: emailFile, to: dest)
                // Set read-only permissions
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o444],
                    ofItemAtPath: dest.path
                )
            }
        }

        return Workspace(
            sessionID: sessionID,
            url: workspaceURL,
            agent: agent,
            fileMap: fileMap,
            createdAt: Date()
        )
    }

    /// List all existing workspace directories.
    public func listWorkspaces() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return [] }
        let contents = try FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
    }

    /// Remove a workspace directory.
    public func removeWorkspace(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    /// Clean up old workspaces, keeping the most recent N per agent prefix.
    public func cleanup(keepLast: Int = 10) throws {
        let workspaces = try listWorkspaces()
        // Group by agent prefix (everything before the first dash + UUID)
        var byAgent: [String: [URL]] = [:]
        for ws in workspaces {
            let name = ws.lastPathComponent
            let agent = name.components(separatedBy: "-").first ?? name
            byAgent[agent, default: []].append(ws)
        }

        for (_, urls) in byAgent {
            // Sort by creation date (newest first)
            let sorted = urls.sorted { a, b in
                let aDate = (try? FileManager.default.attributesOfItem(atPath: a.path)[.creationDate] as? Date) ?? .distantPast
                let bDate = (try? FileManager.default.attributesOfItem(atPath: b.path)[.creationDate] as? Date) ?? .distantPast
                return aDate > bDate
            }
            // Remove excess
            for url in sorted.dropFirst(keepLast) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Private

    private func copySource(_ source: URL, into workspace: URL, fileMap: inout [String: URL]) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDir) else {
            throw ManifoldError.fileNotFound(source.path)
        }

        if isDir.boolValue {
            // Copy directory contents recursively
            let dirName = source.lastPathComponent
            let destDir = workspace.appendingPathComponent(dirName)
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

            // Resolve symlinks for reliable path prefix stripping (/var vs /private/var)
            let resolvedSource = source.resolvingSymlinksInPath()

            let enumerator = FileManager.default.enumerator(
                at: resolvedSource,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            while let fileURL = enumerator?.nextObject() as? URL {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard resourceValues.isRegularFile == true else { continue }

                // Compute relative path from source directory
                let resolvedFile = fileURL.resolvingSymlinksInPath()
                let sourcePrefix = resolvedSource.path.hasSuffix("/") ? resolvedSource.path : resolvedSource.path + "/"
                let relativePath = resolvedFile.path.replacingOccurrences(of: sourcePrefix, with: "")
                let destFile = destDir.appendingPathComponent(relativePath)

                // Create parent directories
                try FileManager.default.createDirectory(
                    at: destFile.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                // Copy the file
                try FileManager.default.copyItem(at: fileURL, to: destFile)
                let workspaceRelative = dirName + "/" + relativePath
                fileMap[workspaceRelative] = fileURL
            }
        } else {
            // Single file — copy directly into workspace root
            let dest = workspace.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: dest)
            fileMap[source.lastPathComponent] = source
        }
    }
}

// MARK: - Workspace

/// Represents an active workspace directory for an agent session.
public struct Workspace: Sendable {
    public let sessionID: String
    public let url: URL
    public let agent: String
    /// Map of relative workspace paths to their original source URLs.
    public let fileMap: [String: URL]
    public let createdAt: Date

    /// Get all file URLs in the workspace (recursively).
    public func allFiles() throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
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
        let basePath = url.standardizedFileURL.path + "/"
        guard filePath.hasPrefix(basePath) else { return nil }
        return String(filePath.dropFirst(basePath.count))
    }
}
