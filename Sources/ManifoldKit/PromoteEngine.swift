import Foundation
import CryptoKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "promote")

/// Writes agent changes from a materialized workspace back to the original source folders.
/// Uses three-way hash comparison to detect conflicts:
///   - baseline: hash at materialization time
///   - original: current hash of the original file
///   - materialized: current hash in the agent workspace
///
/// Outcomes per file:
///   - applied: baseline == original (no external change), materialized differs → safe overwrite
///   - conflict: baseline != original (someone else changed the file) → skip, record reason
///   - skipped: baseline == materialized (agent didn't change it) → nothing to do
///   - new_file: no baseline (agent created it) → copy to original
///   - deleted: agent deleted the file → flag but don't delete original (user decides)
public struct PromoteEngine: Sendable {

    public struct FileResult: Sendable {
        public let relativePath: String
        public let result: PromotionResult
        public let originalBeforeHash: String?
        public let promotedHash: String?
        public let conflictReason: String?
    }

    public struct PromotionSummary: Sendable {
        public let sourceID: String
        public let mountName: String
        public let applied: [FileResult]
        public let conflicts: [FileResult]
        public let skipped: Int
        public let newFiles: [FileResult]
    }

    /// Promote changes from a materialized mount back to its original source.
    /// Does NOT modify the database — caller (GrantStore) records PromotionRecords.
    public static func promote(
        sourceID: String,
        mountName: String,
        mountURL: URL,
        originalURL: URL
    ) throws -> PromotionSummary {
        let fm = FileManager.default

        // Load baseline manifest
        let baselineURL = mountURL.appendingPathComponent(".manifold-baseline.json")
        guard fm.fileExists(atPath: baselineURL.path) else {
            throw ManifoldError.materialization("No baseline manifest at \(baselineURL.path)")
        }
        let baselineData = try Data(contentsOf: baselineURL)
        guard let baseline = try JSONSerialization.jsonObject(with: baselineData) as? [String: String] else {
            throw ManifoldError.materialization("Invalid baseline manifest format")
        }

        // Compute current state of materialized files
        let materialized = try MaterializationEngine.computeManifest(mountURL: mountURL)

        // Compute current state of original files
        let originals = try computeOriginalHashes(originalURL: originalURL, paths: Array(baseline.keys) + Array(materialized.keys))

        var applied: [FileResult] = []
        var conflicts: [FileResult] = []
        var skipped = 0
        var newFiles: [FileResult] = []

        // Check every file in the materialized workspace
        for (path, matHash) in materialized {
            let baseHash = baseline[path]
            let origHash = originals[path]

            if let baseHash {
                // File existed at baseline
                if baseHash == matHash {
                    // Agent didn't change it
                    skipped += 1
                    continue
                }

                // Agent changed the file
                if origHash == baseHash {
                    // Original unchanged since baseline → safe to promote
                    let matFileURL = mountURL.appendingPathComponent(path)
                    let origFileURL = originalURL.appendingPathComponent(path)
                    try copyFile(from: matFileURL, to: origFileURL)

                    applied.append(FileResult(
                        relativePath: path,
                        result: .applied,
                        originalBeforeHash: origHash,
                        promotedHash: matHash,
                        conflictReason: nil
                    ))
                } else {
                    // Original changed since baseline → conflict
                    let reason: String
                    if origHash == nil {
                        reason = "Original file was deleted since baseline"
                    } else {
                        reason = "Original changed since baseline (original: \(origHash!.prefix(8))..., baseline: \(baseHash.prefix(8))...)"
                    }
                    conflicts.append(FileResult(
                        relativePath: path,
                        result: .conflict,
                        originalBeforeHash: origHash,
                        promotedHash: matHash,
                        conflictReason: reason
                    ))
                }
            } else {
                // New file created by agent (no baseline)
                let matFileURL = mountURL.appendingPathComponent(path)
                let origFileURL = originalURL.appendingPathComponent(path)
                try copyFile(from: matFileURL, to: origFileURL)

                newFiles.append(FileResult(
                    relativePath: path,
                    result: .applied,
                    originalBeforeHash: nil,
                    promotedHash: matHash,
                    conflictReason: nil
                ))
            }
        }

        // Check for files that were in baseline but not in materialized (agent deleted them)
        // We don't auto-delete originals. Just log it.
        for (path, _) in baseline where materialized[path] == nil {
            logger.info("Agent removed \(path) from workspace (original preserved)")
        }

        logger.info("Promote \(mountName): \(applied.count) applied, \(conflicts.count) conflicts, \(skipped) skipped, \(newFiles.count) new")

        return PromotionSummary(
            sourceID: sourceID,
            mountName: mountName,
            applied: applied,
            conflicts: conflicts,
            skipped: skipped,
            newFiles: newFiles
        )
    }

    /// Dry-run: compute what would happen without writing anything.
    public static func dryRun(
        mountURL: URL,
        originalURL: URL
    ) throws -> (applied: Int, conflicts: Int, skipped: Int, newFiles: Int) {
        let fm = FileManager.default

        let baselineURL = mountURL.appendingPathComponent(".manifold-baseline.json")
        guard fm.fileExists(atPath: baselineURL.path) else {
            return (0, 0, 0, 0)
        }
        let baselineData = try Data(contentsOf: baselineURL)
        guard let baseline = try JSONSerialization.jsonObject(with: baselineData) as? [String: String] else {
            return (0, 0, 0, 0)
        }

        let materialized = try MaterializationEngine.computeManifest(mountURL: mountURL)
        let originals = try computeOriginalHashes(originalURL: originalURL, paths: Array(baseline.keys) + Array(materialized.keys))

        var applied = 0, conflicts = 0, skipped = 0, newFiles = 0

        for (path, matHash) in materialized {
            let baseHash = baseline[path]
            let origHash = originals[path]

            if let baseHash {
                if baseHash == matHash { skipped += 1 }
                else if origHash == baseHash { applied += 1 }
                else { conflicts += 1 }
            } else {
                newFiles += 1
            }
        }

        return (applied, conflicts, skipped, newFiles)
    }

    // MARK: - Private

    /// Compute SHA-256 hashes for a set of paths relative to the original root.
    /// Only hashes files that exist on disk. Missing files get nil (excluded from result).
    private static func computeOriginalHashes(
        originalURL: URL,
        paths: some Collection<String>
    ) throws -> [String: String] {
        let fm = FileManager.default
        var hashes: [String: String] = [:]
        let uniquePaths = Set(paths)

        for path in uniquePaths {
            let fileURL = originalURL.appendingPathComponent(path)
            guard fm.fileExists(atPath: fileURL.path) else { continue }
            let data = try Data(contentsOf: fileURL)
            hashes[path] = SHA256.hash(data: data).hexString
        }

        return hashes
    }

    /// Copy a single file, creating parent directories as needed.
    private static func copyFile(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let parentDir = destination.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }
}
