// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

public struct ScopedFileIdentity: Sendable, Hashable {
    public let rootURL: URL
    public let fileURL: URL
    public let relativePath: String
    public let exists: Bool
    public let isDirectory: Bool
    public let fileIdentity: String?
    public let hardLinkCount: UInt64
}

public enum ScopedFileAccess: Sendable {
    public static func cleanRelativePath(_ path: String) -> String {
        var cleaned = path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix("./") {
            cleaned = String(cleaned.dropFirst(2))
        }
        while cleaned.contains("//") {
            cleaned = cleaned.replacingOccurrences(of: "//", with: "/")
        }
        while cleaned.hasSuffix("/") && cleaned.count > 1 {
            cleaned = String(cleaned.dropLast())
        }
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public static func resolve(
        relativePath: String,
        rootPath: String,
        allowMissingLeaf: Bool = false
    ) throws -> ScopedFileIdentity {
        try resolve(relativePath: relativePath, rootURL: URL(fileURLWithPath: rootPath), allowMissingLeaf: allowMissingLeaf)
    }

    public static func resolve(
        relativePath: String,
        rootURL: URL,
        allowMissingLeaf: Bool = false
    ) throws -> ScopedFileIdentity {
        let cleaned = cleanRelativePath(relativePath)
        guard !cleaned.isEmpty else {
            throw ManifoldError.workspaceError("Path is empty")
        }
        guard !cleaned.hasPrefix("/") else {
            throw ManifoldError.workspaceError("Absolute paths are not allowed")
        }

        let components = cleaned.split(separator: "/").map(String.init)
        guard !components.contains("..") else {
            throw ManifoldError.workspaceError("Path traversal is not allowed")
        }

        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        var current = resolvedRoot
        var exists = false
        var isDirectory = false
        var fileIdentity: String?
        var hardLinkCount: UInt64 = 0
        let fm = FileManager.default

        for (index, component) in components.enumerated() {
            current.appendPathComponent(component, isDirectory: false)
            let isLast = index == components.count - 1

            guard fm.fileExists(atPath: current.path) else {
                if allowMissingLeaf {
                    let candidate = resolvedRoot.appendingPathComponent(cleaned).standardizedFileURL
                    try assertWithinRoot(candidate, resolvedRoot: resolvedRoot)
                    return ScopedFileIdentity(
                        rootURL: resolvedRoot,
                        fileURL: candidate,
                        relativePath: cleaned,
                        exists: false,
                        isDirectory: false,
                        fileIdentity: nil,
                        hardLinkCount: 0
                    )
                }
                throw ManifoldError.fileNotFound(cleaned)
            }

            let state = try fileState(atPath: current.path)
            if state.isSymbolicLink {
                throw ManifoldError.workspaceError("Symlinks are not allowed in governed paths")
            }

            if isLast {
                exists = true
                isDirectory = state.isDirectory
                fileIdentity = state.identity
                hardLinkCount = state.hardLinkCount
                if state.isRegularFile && state.hardLinkCount > 1 {
                    throw ManifoldError.workspaceError("Hard-linked files are not allowed in governed paths")
                }
            } else if !state.isDirectory {
                throw ManifoldError.workspaceError("Non-directory path component escapes the governed root")
            }
        }

        let resolvedFile = resolvedRoot.appendingPathComponent(cleaned).standardizedFileURL
        try assertWithinRoot(resolvedFile, resolvedRoot: resolvedRoot)
        return ScopedFileIdentity(
            rootURL: resolvedRoot,
            fileURL: resolvedFile,
            relativePath: cleaned,
            exists: exists,
            isDirectory: isDirectory,
            fileIdentity: fileIdentity,
            hardLinkCount: hardLinkCount
        )
    }

    public static func readData(
        relativePath: String,
        rootPath: String
    ) throws -> (identity: ScopedFileIdentity, data: Data) {
        let identity = try resolve(relativePath: relativePath, rootPath: rootPath)
        let beforeIdentity = identity.fileIdentity
        let data = try Data(contentsOf: identity.fileURL, options: [.mappedIfSafe])
        if let beforeIdentity,
           let afterIdentity = try? fileState(atPath: identity.fileURL.path).identity,
           afterIdentity != beforeIdentity {
            throw ManifoldError.workspaceError("The governed file changed while it was being read")
        }
        return (identity, data)
    }

    public static func writeDataAtomically(
        _ data: Data,
        relativePath: String,
        rootPath: String
    ) throws -> ScopedFileIdentity {
        let identity = try resolve(relativePath: relativePath, rootPath: rootPath, allowMissingLeaf: true)
        let originalIdentity = identity.exists ? identity.fileIdentity : nil
        let parentURL = identity.fileURL.deletingLastPathComponent()
        try LocalFileProtection.ensureDirectory(at: parentURL)

        let tempURL = parentURL.appendingPathComponent(".manifold-\(UUID().uuidString)")
        try LocalFileProtection.writeOwnerOnly(data, to: tempURL, options: [])

        if let originalIdentity,
           let currentIdentity = try? resolve(relativePath: relativePath, rootPath: rootPath).fileIdentity,
           currentIdentity != originalIdentity {
            try? FileManager.default.removeItem(at: tempURL)
            throw ManifoldError.workspaceError("The governed file changed while it was being written")
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: identity.fileURL.path) {
            _ = try fm.replaceItemAt(identity.fileURL, withItemAt: tempURL)
        } else {
            try fm.moveItem(at: tempURL, to: identity.fileURL)
        }
        try LocalFileProtection.secureFile(at: identity.fileURL)
        return try resolve(relativePath: relativePath, rootPath: rootPath)
    }

    public static func isBlockedGovernedEntry(at url: URL) -> Bool {
        guard let state = try? fileState(atPath: url.path) else { return true }
        if state.isSymbolicLink {
            return true
        }
        return state.isRegularFile && state.hardLinkCount > 1
    }

    private static func assertWithinRoot(_ url: URL, resolvedRoot: URL) throws {
        let rootPath = resolvedRoot.path
        let candidate = url.path
        guard candidate == rootPath || candidate.hasPrefix(rootPath + "/") else {
            throw ManifoldError.workspaceError("Path escapes the governed root")
        }
    }

    private static func fileState(atPath path: String) throws -> POSIXFileState {
        var statBuffer = stat()
        guard lstat(path, &statBuffer) == 0 else {
            let message = String(cString: strerror(errno))
            throw ManifoldError.workspaceError("Failed to inspect \(path): \(message)")
        }
        let type = statBuffer.st_mode & S_IFMT
        return POSIXFileState(
            isDirectory: type == S_IFDIR,
            isRegularFile: type == S_IFREG,
            isSymbolicLink: type == S_IFLNK,
            hardLinkCount: UInt64(statBuffer.st_nlink),
            identity: "\(statBuffer.st_dev):\(statBuffer.st_ino)"
        )
    }

    private struct POSIXFileState {
        let isDirectory: Bool
        let isRegularFile: Bool
        let isSymbolicLink: Bool
        let hardLinkCount: UInt64
        let identity: String
    }
}
