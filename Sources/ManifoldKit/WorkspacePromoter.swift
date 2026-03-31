import Foundation

/// Handles promoting agent modifications back to original source locations.
/// Two modes: per-file promote and bulk promote.
public struct WorkspacePromoter: Sendable {
    public init() {}

    /// Promote a single file from workspace back to its original source location.
    /// Returns the destination URL.
    @discardableResult
    public func promoteFile(workspaceFileURL: URL, to destinationURL: URL) throws -> URL {
        // Create parent directory if needed
        let parentDir = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        // If destination exists, replace it
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: workspaceFileURL, to: destinationURL)
        return destinationURL
    }

    /// Promote all modified files in a workspace back to their original source locations.
    /// Uses the workspace's fileMap to determine source paths.
    /// Returns a list of (workspacePath, sourcePath) pairs that were promoted.
    public func promoteAll(
        workspace: Workspace,
        modifiedPaths: [String]
    ) throws -> [(workspace: String, source: URL)] {
        var promoted: [(String, URL)] = []

        for path in modifiedPaths {
            guard let sourceURL = workspace.fileMap[path] else { continue }
            let workspaceFileURL = workspace.url.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: workspaceFileURL.path) else { continue }

            try promoteFile(workspaceFileURL: workspaceFileURL, to: sourceURL)
            promoted.append((path, sourceURL))
        }

        return promoted
    }
}
