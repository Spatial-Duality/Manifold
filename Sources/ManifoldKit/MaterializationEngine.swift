// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CryptoKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "materialization")

/// Copies source files into a managed workspace for a grant.
/// Each source is mounted under `<materialization_root>/<mount_name>/`.
/// A baseline manifest (`.manifold-baseline.json`) records the SHA-256 hash of
/// every file at copy time, enabling drift detection during promotion.
public struct MaterializationEngine: Sendable {
    public struct MaterializationSource: Sendable {
        public let source: SourceRecord
        public let mountName: String
        public let selectedScopes: [FileSelectionScope]

        public init(
            source: SourceRecord,
            mountName: String,
            selectedScopes: [FileSelectionScope] = []
        ) {
            self.source = source
            self.mountName = mountName
            self.selectedScopes = selectedScopes
        }
    }

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

    // MARK: - Size Estimation

    /// Result of estimating source size before materialization.
    public struct SizeEstimate: Sendable {
        public let fileCount: Int
        public let totalBytes: Int64
    }

    /// Per-source size estimate for preview display.
    public struct SourceSizeEstimate: Sendable {
        public let sourceID: String
        public let displayName: String
        public let fileCount: Int
        public let totalBytes: Int64
    }

    /// Size thresholds for materialization safety.
    public static let warnThreshold: Int64 = 5_368_709_120    // 5 GB
    public static let blockThreshold: Int64 = 53_687_091_200  // 50 GB

    /// Estimate file count and total size of sources without copying.
    /// Respects `.manifoldignore` files at each source root.
    public static func estimateSize(
        sources: [(source: SourceRecord, mountName: String)]
    ) throws -> SizeEstimate {
        try estimateSize(
            sources: sources.map {
                MaterializationSource(source: $0.source, mountName: $0.mountName)
            }
        )
    }

    /// Estimate file count and total size of sources without copying.
    /// When scopes are provided, only selected files and directories are counted.
    public static func estimateSize(
        sources: [MaterializationSource]
    ) throws -> SizeEstimate {
        let fm = FileManager.default
        var totalBytes: Int64 = 0
        var fileCount = 0

        for input in sources {
            let source = input.source
            let sourceURL = URL(fileURLWithPath: source.effectiveRootPath)
            let resolvedSource = sourceURL.resolvingSymlinksInPath()
            let ignoreMatcher = GlobMatcher.load(from: sourceURL.appendingPathComponent(".manifoldignore"))
            let scopes = normalizedScopes(input.selectedScopes, for: source.sourceID)

            guard let enumerator = fm.enumerator(
                at: resolvedSource,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let sourceBasePath = resolvedSource.path + "/"
            while let fileURL = enumerator.nextObject() as? URL {
                // Use standardizedFileURL (resolves . and .. without stat syscalls)
                // instead of resolvingSymlinksInPath (calls realpath → N stat calls per path component)
                let standardized = fileURL.standardizedFileURL
                guard standardized.path.hasPrefix(sourceBasePath) else { continue }
                let relativePath = String(standardized.path.dropFirst(sourceBasePath.count))
                let isDirectory = fileURL.hasDirectoryPath
                if ScopedFileAccess.isBlockedGovernedEntry(at: fileURL) {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }

                if shouldSkip(relativePath: relativePath) {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }

                if ignoreMatcher.shouldExclude(relativePath: relativePath, isDirectory: isDirectory) {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }

                if isDirectory, !shouldTraverseDirectory(relativePath: relativePath, scopes: scopes) {
                    enumerator.skipDescendants()
                    continue
                }

                if !shouldInclude(relativePath: relativePath, isDirectory: isDirectory, scopes: scopes) {
                    continue
                }

                guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                totalBytes += Int64(values.fileSize ?? 0)
                fileCount += 1
            }
        }

        return SizeEstimate(fileCount: fileCount, totalBytes: totalBytes)
    }

    /// Per-source size estimates for session preview.
    public static func estimateSizePerSource(
        sources: [(source: SourceRecord, mountName: String)]
    ) throws -> [SourceSizeEstimate] {
        try estimateSizePerSource(
            sources: sources.map {
                MaterializationSource(source: $0.source, mountName: $0.mountName)
            }
        )
    }

    /// Per-source size estimates for session preview.
    public static func estimateSizePerSource(
        sources: [MaterializationSource]
    ) throws -> [SourceSizeEstimate] {
        try sources.map { input in
            let est = try estimateSize(
                sources: [
                    MaterializationSource(
                        source: input.source,
                        mountName: input.mountName,
                        selectedScopes: input.selectedScopes
                    )
                ]
            )
            return SourceSizeEstimate(
                sourceID: input.source.sourceID,
                displayName: input.source.displayName,
                fileCount: est.fileCount,
                totalBytes: est.totalBytes
            )
        }
    }

    /// Materialize all sources for a grant into the workspace directory.
    /// Returns one MountResult per source.
    public static func materialize(
        grantID: String,
        sources: [(source: SourceRecord, mountName: String)],
        materializationRoot: String
    ) throws -> [MountResult] {
        try materialize(
            grantID: grantID,
            sources: sources.map {
                MaterializationSource(source: $0.source, mountName: $0.mountName)
            },
            materializationRoot: materializationRoot
        )
    }

    /// Materialize all sources for a grant into the workspace directory.
    /// Returns one MountResult per source.
    public static func materialize(
        grantID: String,
        sources: [MaterializationSource],
        materializationRoot: String
    ) throws -> [MountResult] {
        let fm = FileManager.default
        let workspaceURL = URL(fileURLWithPath: materializationRoot)

        try LocalFileProtection.ensureDirectory(at: workspaceURL)

        // Size guard: estimate total before copying
        let estimate = try estimateSize(sources: sources)
        if estimate.totalBytes > blockThreshold {
            let gb = Double(estimate.totalBytes) / (1024 * 1024 * 1024)
            throw ManifoldError.materialization(
                "Source size (\(String(format: "%.1f", gb)) GB) exceeds 50 GB limit. Remove large sources or split into smaller sets."
            )
        }
        if estimate.totalBytes > warnThreshold {
            let gb = Double(estimate.totalBytes) / (1024 * 1024 * 1024)
            logger.warning("Large materialization: \(String(format: "%.1f", gb)) GB. Consider reducing source scope.")
        }

        var results: [MountResult] = []

        for input in sources {
            let source = input.source
            let mountName = input.mountName
            let mountURL = workspaceURL.appendingPathComponent(mountName)
            let sourceURL = URL(fileURLWithPath: source.effectiveRootPath)

            guard fm.fileExists(atPath: sourceURL.path) else {
                logger.warning("Source path missing, skipping: \(source.effectiveRootPath)")
                continue
            }

            let result = try materializeSource(
                sourceID: source.sourceID,
                mountName: mountName,
                sourceURL: sourceURL,
                mountURL: mountURL,
                selectedScopes: input.selectedScopes
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
            if ScopedFileAccess.isBlockedGovernedEntry(at: fileURL) { continue }

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
        mountURL: URL,
        selectedScopes: [FileSelectionScope]
    ) throws -> MountResult {
        let fm = FileManager.default

        // Clean existing mount if present (fresh copy)
        if fm.fileExists(atPath: mountURL.path) {
            try fm.removeItem(at: mountURL)
        }
        try LocalFileProtection.ensureDirectory(at: mountURL)

        // Copy files (skip hidden files, common noise, and .manifoldignore patterns)
        var fileCount = 0
        var totalBytes: Int64 = 0

        let resolvedSource = sourceURL.resolvingSymlinksInPath()
        let ignoreMatcher = GlobMatcher.load(from: sourceURL.appendingPathComponent(".manifoldignore"))
        let scopes = normalizedScopes(selectedScopes, for: sourceID)

        guard let enumerator = fm.enumerator(
            at: resolvedSource,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ManifoldError.materialization("Cannot enumerate source: \(sourceURL.path)")
        }

        let sourceBasePath = resolvedSource.path + "/"
        do {
            while let fileURL = enumerator.nextObject() as? URL {
                // Use standardizedFileURL (resolves . and .. without stat syscalls)
                // instead of resolvingSymlinksInPath (calls realpath → N stat calls per path component)
                let standardized = fileURL.standardizedFileURL
                guard standardized.path.hasPrefix(sourceBasePath) else { continue }
                let relativePath = String(standardized.path.dropFirst(sourceBasePath.count))
                let isDirectory = fileURL.hasDirectoryPath
                if ScopedFileAccess.isBlockedGovernedEntry(at: fileURL) {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }

                // Skip noise directories
                if shouldSkip(relativePath: relativePath) {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }

                // Skip .manifoldignore patterns
                if ignoreMatcher.shouldExclude(relativePath: relativePath, isDirectory: isDirectory) {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }

                if isDirectory, !shouldTraverseDirectory(relativePath: relativePath, scopes: scopes) {
                    enumerator.skipDescendants()
                    continue
                }

                if !shouldInclude(relativePath: relativePath, isDirectory: isDirectory, scopes: scopes) {
                    continue
                }

                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true else {
                    if isDirectory {
                        let destDir = mountURL.appendingPathComponent(relativePath)
                        try LocalFileProtection.ensureDirectory(at: destDir)
                    }
                    continue
                }

                let destURL = mountURL.appendingPathComponent(relativePath)
                let destDir = destURL.deletingLastPathComponent()
                if !fm.fileExists(atPath: destDir.path) {
                    try LocalFileProtection.ensureDirectory(at: destDir)
                }
                try LocalFileProtection.copyOwnerOnlyItem(at: fileURL, to: destURL)

                fileCount += 1
                totalBytes += Int64(values.fileSize ?? 0)
            }
        } catch {
            // Clean up partial mount to avoid leaving orphaned files
            try? fm.removeItem(at: mountURL)
            logger.error("Materialization failed for \(mountName), cleaned partial mount: \(error.localizedDescription)")
            throw error
        }

        // Build and write baseline manifest
        let manifest = try computeManifest(mountURL: mountURL)
        let manifestHash = hashManifest(manifest)

        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        let manifestURL = mountURL.appendingPathComponent(".manifold-baseline.json")
        try LocalFileProtection.writeOwnerOnly(manifestData, to: manifestURL)

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

    private static func normalizedScopes(_ scopes: [FileSelectionScope], for sourceID: String) -> [FileSelectionScope] {
        scopes
            .filter { $0.sourceID == sourceID }
            .map {
                FileSelectionScope(
                    sourceID: $0.sourceID,
                    relativePath: normalizedRelativePath($0.relativePath),
                    isDirectory: $0.isDirectory
                )
            }
    }

    private static func normalizedRelativePath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\\\", with: "/")
            .replacingOccurrences(of: "//", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func shouldTraverseDirectory(relativePath: String, scopes: [FileSelectionScope]) -> Bool {
        guard !scopes.isEmpty else { return true }
        let candidate = normalizedRelativePath(relativePath)
        return scopes.contains { scope in
            let scopePath = scope.normalizedRelativePath
            return candidate.isEmpty
                || scopePath == candidate
                || scopePath.hasPrefix(candidate + "/")
                || candidate.hasPrefix(scopePath + "/")
        }
    }

    private static func shouldInclude(relativePath: String, isDirectory: Bool, scopes: [FileSelectionScope]) -> Bool {
        guard !scopes.isEmpty else { return true }
        let candidate = normalizedRelativePath(relativePath)
        return scopes.contains { scope in
            let scopePath = scope.normalizedRelativePath
            if scope.isDirectory {
                if scopePath.isEmpty { return true }
                return candidate == scopePath || candidate.hasPrefix(scopePath + "/")
            }
            return !isDirectory && candidate == scopePath
        }
    }
}
