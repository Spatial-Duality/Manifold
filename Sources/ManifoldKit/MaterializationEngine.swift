import Foundation
import CryptoKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "materialization")

/// Copies source files into a managed workspace for a grant.
/// Each source is mounted under `<materialization_root>/<mount_name>/`.
/// A baseline manifest (`.manifold-baseline.json`) records the SHA-256 hash of
/// every file at copy time, enabling drift detection during promotion.
public struct MaterializationEngine: Sendable {

    /// Result of materializing a single source into a grant workspace.
    public struct MountResult: Sendable {
        public let sourceID: String
        public let mountName: String
        public let mountPath: String
        public let fileCount: Int
        public let totalBytes: Int64
        /// SHA-256 of the baseline manifest JSON (stored on grant_sources.baseline_manifest_hash)
        public let manifestHash: String
    }

    /// Materialize all sources for a grant into the workspace directory.
    /// Returns one MountResult per source.
    public static func materialize(
        grantID: String,
        sources: [(source: SourceRecord, mountName: String)],
        materializationRoot: String
    ) throws -> [MountResult] {
        let fm = FileManager.default
        let workspaceURL = URL(fileURLWithPath: materializationRoot)

        try fm.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        var results: [MountResult] = []

        for (source, mountName) in sources {
            let mountURL = workspaceURL.appendingPathComponent(mountName)
            let sourceURL = URL(fileURLWithPath: source.originalRootPath)

            guard fm.fileExists(atPath: sourceURL.path) else {
                logger.warning("Source path missing, skipping: \(source.originalRootPath)")
                continue
            }

            let result = try materializeSource(
                sourceID: source.sourceID,
                mountName: mountName,
                sourceURL: sourceURL,
                mountURL: mountURL
            )
            results.append(result)
        }

        logger.info("Materialized \(results.count) sources for grant \(grantID)")
        return results
    }

    /// Compute the baseline manifest for an already-materialized mount directory.
    /// Returns `{relative_path: sha256_hash}` as a sorted dictionary.
    public static func computeManifest(mountURL: URL) throws -> [String: String] {
        let fm = FileManager.default
        let resolvedMount = mountURL.resolvingSymlinksInPath()
        guard let enumerator = fm.enumerator(
            at: resolvedMount,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        let basePath = resolvedMount.path + "/"
        var manifest: [String: String] = [:]
        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.lastPathComponent == ".manifold-baseline.json" { continue }

            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }

            let resolved = fileURL.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(basePath) else { continue }
            let relativePath = String(resolved.path.dropFirst(basePath.count))

            let data = try Data(contentsOf: fileURL)
            let hash = SHA256.hash(data: data).hexString
            manifest[relativePath] = hash
        }

        return manifest
    }

    /// Hash of the manifest itself (for quick change detection).
    public static func hashManifest(_ manifest: [String: String]) -> String {
        let sorted = manifest.sorted { $0.key < $1.key }
        let canonical = sorted.map { "\($0.key):\($0.value)" }.joined(separator: "\n")
        let data = Data(canonical.utf8)
        return SHA256.hash(data: data).hexString
    }

    // MARK: - Private

    private static func materializeSource(
        sourceID: String,
        mountName: String,
        sourceURL: URL,
        mountURL: URL
    ) throws -> MountResult {
        let fm = FileManager.default

        // Clean existing mount if present (fresh copy)
        if fm.fileExists(atPath: mountURL.path) {
            try fm.removeItem(at: mountURL)
        }
        try fm.createDirectory(at: mountURL, withIntermediateDirectories: true)

        // Copy files (skip hidden files and common noise)
        var fileCount = 0
        var totalBytes: Int64 = 0

        let resolvedSource = sourceURL.resolvingSymlinksInPath()
        guard let enumerator = fm.enumerator(
            at: resolvedSource,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ManifoldError.materialization("Cannot enumerate source: \(sourceURL.path)")
        }

        let sourceBasePath = resolvedSource.path + "/"
        while let fileURL = enumerator.nextObject() as? URL {
            let resolved = fileURL.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(sourceBasePath) else { continue }
            let relativePath = String(resolved.path.dropFirst(sourceBasePath.count))

            // Skip noise directories
            if shouldSkip(relativePath: relativePath) {
                if fileURL.hasDirectoryPath { enumerator.skipDescendants() }
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                // It's a directory — create it in mount
                let destDir = mountURL.appendingPathComponent(relativePath)
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                continue
            }

            let destURL = mountURL.appendingPathComponent(relativePath)
            let destDir = destURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: destDir.path) {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            }
            try fm.copyItem(at: fileURL, to: destURL)

            fileCount += 1
            totalBytes += Int64(values.fileSize ?? 0)
        }

        // Build and write baseline manifest
        let manifest = try computeManifest(mountURL: mountURL)
        let manifestHash = hashManifest(manifest)

        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        let manifestURL = mountURL.appendingPathComponent(".manifold-baseline.json")
        try manifestData.write(to: manifestURL, options: .atomic)

        logger.info("Materialized \(mountName): \(fileCount) files, \(totalBytes) bytes")

        return MountResult(
            sourceID: sourceID,
            mountName: mountName,
            mountPath: mountURL.path,
            fileCount: fileCount,
            totalBytes: totalBytes,
            manifestHash: manifestHash
        )
    }

    /// Directories to skip during materialization (build artifacts, dependencies, VCS).
    private static func shouldSkip(relativePath: String) -> Bool {
        let noiseDirectories = [
            ".git", ".svn", ".hg",
            "node_modules", ".build", "Build", "DerivedData",
            "Pods", ".cocoapods",
            "__pycache__", ".venv", "venv",
            ".DS_Store",
        ]
        let firstComponent = relativePath.split(separator: "/").first.map(String.init) ?? relativePath
        return noiseDirectories.contains(firstComponent)
    }
}
