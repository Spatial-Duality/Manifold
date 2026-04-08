import Testing
import Foundation
@testable import ManifoldKit

@Suite("MaterializationEngine")
struct MaterializationEngineTests {
    func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-mat-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    /// Create a fake source directory with some files.
    func createSourceTree(at url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.appendingPathComponent("src"), withIntermediateDirectories: true)
        try Data("func main() {}".utf8).write(to: url.appendingPathComponent("src/main.swift"))
        try Data("# README".utf8).write(to: url.appendingPathComponent("README.md"))
        try fm.createDirectory(at: url.appendingPathComponent("tests"), withIntermediateDirectories: true)
        try Data("func testA() {}".utf8).write(to: url.appendingPathComponent("tests/test_a.swift"))
    }

    @Test("Materializes source files into mount directory")
    func basicMaterialization() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let sourceDir = tempDir.appendingPathComponent("original")
        try createSourceTree(at: sourceDir)

        let matRoot = tempDir.appendingPathComponent("workspace")
        let source = SourceRecord(row: [
            "source_id": "src-1",
            "display_name": "MyProject",
            "original_root_path": sourceDir.path,
            "status": "active",
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z",
        ])!

        let results = try MaterializationEngine.materialize(
            grantID: "grant-1",
            sources: [(source: source, mountName: "MyProject")],
            materializationRoot: matRoot.path
        )

        #expect(results.count == 1)
        #expect(results[0].fileCount == 3)
        #expect(results[0].mountName == "MyProject")

        // Verify files were copied
        let fm = FileManager.default
        let mountPath = matRoot.appendingPathComponent("MyProject")
        #expect(fm.fileExists(atPath: mountPath.appendingPathComponent("src/main.swift").path))
        #expect(fm.fileExists(atPath: mountPath.appendingPathComponent("README.md").path))
        #expect(fm.fileExists(atPath: mountPath.appendingPathComponent("tests/test_a.swift").path))
    }

    @Test("Baseline manifest contains all file hashes")
    func baselineManifest() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let sourceDir = tempDir.appendingPathComponent("original")
        try createSourceTree(at: sourceDir)

        let matRoot = tempDir.appendingPathComponent("workspace")
        let source = SourceRecord(row: [
            "source_id": "src-1",
            "display_name": "Test",
            "original_root_path": sourceDir.path,
            "status": "active",
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z",
        ])!

        let results = try MaterializationEngine.materialize(
            grantID: "grant-1",
            sources: [(source: source, mountName: "Test")],
            materializationRoot: matRoot.path
        )

        // Baseline manifest file should exist
        let mountPath = matRoot.appendingPathComponent("Test")
        let manifestURL = mountPath.appendingPathComponent(".manifold-baseline.json")
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))

        // Parse manifest
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONSerialization.jsonObject(with: data) as! [String: String]
        #expect(manifest.count == 3)
        #expect(manifest["src/main.swift"] != nil)
        #expect(manifest["README.md"] != nil)
        #expect(manifest["tests/test_a.swift"] != nil)

        // Manifest hash should be non-empty
        #expect(!results[0].manifestHash.isEmpty)
    }

    @Test("Skips .git and node_modules directories")
    func skipsNoiseDirectories() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let sourceDir = tempDir.appendingPathComponent("original")
        let fm = FileManager.default
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("main".utf8).write(to: sourceDir.appendingPathComponent("main.swift"))
        try fm.createDirectory(at: sourceDir.appendingPathComponent(".git/objects"), withIntermediateDirectories: true)
        try Data("gitobj".utf8).write(to: sourceDir.appendingPathComponent(".git/objects/abc"))
        try fm.createDirectory(at: sourceDir.appendingPathComponent("node_modules/pkg"), withIntermediateDirectories: true)
        try Data("pkg".utf8).write(to: sourceDir.appendingPathComponent("node_modules/pkg/index.js"))

        let matRoot = tempDir.appendingPathComponent("workspace")
        let source = SourceRecord(row: [
            "source_id": "src-1",
            "display_name": "Test",
            "original_root_path": sourceDir.path,
            "status": "active",
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z",
        ])!

        let results = try MaterializationEngine.materialize(
            grantID: "grant-1",
            sources: [(source: source, mountName: "Test")],
            materializationRoot: matRoot.path
        )

        #expect(results[0].fileCount == 1)
        let mountPath = matRoot.appendingPathComponent("Test")
        #expect(!fm.fileExists(atPath: mountPath.appendingPathComponent("node_modules").path))
    }

    @Test("Manifest hash is deterministic")
    func deterministicHash() throws {
        let manifest1 = ["b.swift": "hash_b", "a.swift": "hash_a"]
        let manifest2 = ["a.swift": "hash_a", "b.swift": "hash_b"]
        let hash1 = MaterializationEngine.hashManifest(manifest1)
        let hash2 = MaterializationEngine.hashManifest(manifest2)
        #expect(hash1 == hash2)
    }

    @Test("Handles missing source gracefully")
    func missingSource() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let source = SourceRecord(row: [
            "source_id": "src-missing",
            "display_name": "Gone",
            "original_root_path": "/nonexistent/path/that/doesnt/exist",
            "status": "active",
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z",
        ])!

        let matRoot = tempDir.appendingPathComponent("workspace")
        let results = try MaterializationEngine.materialize(
            grantID: "grant-1",
            sources: [(source: source, mountName: "Gone")],
            materializationRoot: matRoot.path
        )

        #expect(results.isEmpty)
    }

    @Test("Multiple sources materialize into separate mounts")
    func multipleSources() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let source1Dir = tempDir.appendingPathComponent("project-a")
        try FileManager.default.createDirectory(at: source1Dir, withIntermediateDirectories: true)
        try Data("file a".utf8).write(to: source1Dir.appendingPathComponent("a.txt"))

        let source2Dir = tempDir.appendingPathComponent("project-b")
        try FileManager.default.createDirectory(at: source2Dir, withIntermediateDirectories: true)
        try Data("file b".utf8).write(to: source2Dir.appendingPathComponent("b.txt"))

        let s1 = SourceRecord(row: [
            "source_id": "src-a", "display_name": "A",
            "original_root_path": source1Dir.path,
            "status": "active", "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z",
        ])!
        let s2 = SourceRecord(row: [
            "source_id": "src-b", "display_name": "B",
            "original_root_path": source2Dir.path,
            "status": "active", "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z",
        ])!

        let matRoot = tempDir.appendingPathComponent("workspace")
        let results = try MaterializationEngine.materialize(
            grantID: "grant-1",
            sources: [(source: s1, mountName: "project-a"), (source: s2, mountName: "project-b")],
            materializationRoot: matRoot.path
        )

        #expect(results.count == 2)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: matRoot.appendingPathComponent("project-a/a.txt").path))
        #expect(fm.fileExists(atPath: matRoot.appendingPathComponent("project-b/b.txt").path))
    }

    @Test("estimateSize returns correct fileCount and totalBytes")
    func estimateSizeBasic() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let sourceDir = tempDir.appendingPathComponent("source")
        try createSourceTree(at: sourceDir)

        let source = SourceRecord(row: [
            "source_id": "src-est",
            "display_name": "EstimateTest",
            "original_root_path": sourceDir.path,
            "status": "active",
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z",
        ])!

        let estimate = try MaterializationEngine.estimateSize(
            sources: [(source: source, mountName: "EstimateTest")]
        )

        // createSourceTree writes 3 files: src/main.swift, README.md, tests/test_a.swift
        #expect(estimate.fileCount == 3)

        let expectedBytes: Int64 =
            Int64("func main() {}".utf8.count) +
            Int64("# README".utf8.count) +
            Int64("func testA() {}".utf8.count)
        #expect(estimate.totalBytes == expectedBytes)
    }

    @Test("estimateSizePerSource returns per-source estimates")
    func estimateSizePerSource() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let source1Dir = tempDir.appendingPathComponent("alpha")
        try FileManager.default.createDirectory(at: source1Dir, withIntermediateDirectories: true)
        try Data("aaa".utf8).write(to: source1Dir.appendingPathComponent("a.txt"))

        let source2Dir = tempDir.appendingPathComponent("beta")
        try FileManager.default.createDirectory(at: source2Dir, withIntermediateDirectories: true)
        try Data("bbbb".utf8).write(to: source2Dir.appendingPathComponent("b1.txt"))
        try Data("cc".utf8).write(to: source2Dir.appendingPathComponent("b2.txt"))

        let s1 = SourceRecord(row: [
            "source_id": "src-a", "display_name": "Alpha",
            "original_root_path": source1Dir.path,
            "status": "active", "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z",
        ])!
        let s2 = SourceRecord(row: [
            "source_id": "src-b", "display_name": "Beta",
            "original_root_path": source2Dir.path,
            "status": "active", "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z",
        ])!

        let perSource = try MaterializationEngine.estimateSizePerSource(
            sources: [(source: s1, mountName: "alpha"), (source: s2, mountName: "beta")]
        )

        #expect(perSource.count == 2)

        let alpha = perSource.first { $0.sourceID == "src-a" }!
        #expect(alpha.displayName == "Alpha")
        #expect(alpha.fileCount == 1)
        #expect(alpha.totalBytes == 3) // "aaa"

        let beta = perSource.first { $0.sourceID == "src-b" }!
        #expect(beta.displayName == "Beta")
        #expect(beta.fileCount == 2)
        #expect(beta.totalBytes == 6) // "bbbb" + "cc"
    }

    @Test("estimateSize respects .manifoldignore patterns")
    func estimateSizeRespectsIgnore() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let sourceDir = tempDir.appendingPathComponent("ignored-source")
        let fm = FileManager.default
        try fm.createDirectory(at: sourceDir.appendingPathComponent("logs"), withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: sourceDir.appendingPathComponent("main.swift"))
        try Data("also keep".utf8).write(to: sourceDir.appendingPathComponent("util.swift"))
        try Data("log data".utf8).write(to: sourceDir.appendingPathComponent("logs/debug.log"))
        try Data("tmp stuff".utf8).write(to: sourceDir.appendingPathComponent("scratch.tmp"))

        // Write a .manifoldignore that excludes *.log and *.tmp files
        try Data("*.log\n*.tmp\n".utf8).write(to: sourceDir.appendingPathComponent(".manifoldignore"))

        let source = SourceRecord(row: [
            "source_id": "src-ign",
            "display_name": "IgnoreTest",
            "original_root_path": sourceDir.path,
            "status": "active",
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z",
        ])!

        let estimate = try MaterializationEngine.estimateSize(
            sources: [(source: source, mountName: "IgnoreTest")]
        )

        // Only main.swift and util.swift should be counted (logs/debug.log and scratch.tmp excluded)
        #expect(estimate.fileCount == 2)

        let expectedBytes: Int64 =
            Int64("keep me".utf8.count) +
            Int64("also keep".utf8.count)
        #expect(estimate.totalBytes == expectedBytes)
    }
}
