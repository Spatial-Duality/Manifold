import Testing
import Foundation
@testable import ManifoldKit

@Suite("PromoteEngine")
struct PromoteEngineTests {
    func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-promote-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    /// Set up a source dir, materialize it, then return (originalDir, mountDir) for modification.
    func setupMaterialized(tempDir: URL) throws -> (URL, URL) {
        let fm = FileManager.default
        let sourceDir = tempDir.appendingPathComponent("original")
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("original content A".utf8).write(to: sourceDir.appendingPathComponent("file_a.txt"))
        try Data("original content B".utf8).write(to: sourceDir.appendingPathComponent("file_b.txt"))

        let matRoot = tempDir.appendingPathComponent("workspace")
        let source = SourceRecord(row: [
            "source_id": "src-1", "display_name": "Test",
            "original_root_path": sourceDir.path,
            "status": "active", "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z",
        ])!

        _ = try MaterializationEngine.materialize(
            grantID: "grant-1",
            sources: [(source: source, mountName: "Test")],
            materializationRoot: matRoot.path
        )

        let mountDir = matRoot.appendingPathComponent("Test")
        return (sourceDir, mountDir)
    }

    @Test("Unchanged files are skipped")
    func skipsUnchanged() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let (sourceDir, mountDir) = try setupMaterialized(tempDir: tempDir)

        let summary = try PromoteEngine.promote(
            sourceID: "src-1", mountName: "Test",
            mountURL: mountDir, originalURL: sourceDir
        )

        #expect(summary.applied.isEmpty)
        #expect(summary.conflicts.isEmpty)
        #expect(summary.newFiles.isEmpty)
        #expect(summary.skipped == 2)
    }

    @Test("Agent modification applied when original unchanged")
    func appliesCleanChange() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let (sourceDir, mountDir) = try setupMaterialized(tempDir: tempDir)

        // Agent modifies file_a in the workspace
        try Data("modified by agent".utf8).write(to: mountDir.appendingPathComponent("file_a.txt"))

        let summary = try PromoteEngine.promote(
            sourceID: "src-1", mountName: "Test",
            mountURL: mountDir, originalURL: sourceDir
        )

        #expect(summary.applied.count == 1)
        #expect(summary.applied[0].relativePath == "file_a.txt")
        #expect(summary.conflicts.isEmpty)
        #expect(summary.skipped == 1) // file_b unchanged

        // Original should now have the agent's content
        let promoted = try String(contentsOf: sourceDir.appendingPathComponent("file_a.txt"), encoding: .utf8)
        #expect(promoted == "modified by agent")
    }

    @Test("Conflict detected when original changed since baseline")
    func detectsConflict() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let (sourceDir, mountDir) = try setupMaterialized(tempDir: tempDir)

        // Agent modifies file_a in workspace
        try Data("agent version".utf8).write(to: mountDir.appendingPathComponent("file_a.txt"))

        // Someone else also modifies file_a in the original
        try Data("external edit".utf8).write(to: sourceDir.appendingPathComponent("file_a.txt"))

        let summary = try PromoteEngine.promote(
            sourceID: "src-1", mountName: "Test",
            mountURL: mountDir, originalURL: sourceDir
        )

        #expect(summary.conflicts.count == 1)
        #expect(summary.conflicts[0].relativePath == "file_a.txt")
        #expect(summary.conflicts[0].conflictReason != nil)
        #expect(summary.applied.isEmpty)

        // Original should NOT have been overwritten
        let original = try String(contentsOf: sourceDir.appendingPathComponent("file_a.txt"), encoding: .utf8)
        #expect(original == "external edit")
    }

    @Test("New file created by agent is promoted")
    func promotesNewFile() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let (sourceDir, mountDir) = try setupMaterialized(tempDir: tempDir)

        // Agent creates a new file
        try Data("new file content".utf8).write(to: mountDir.appendingPathComponent("new_file.txt"))

        let summary = try PromoteEngine.promote(
            sourceID: "src-1", mountName: "Test",
            mountURL: mountDir, originalURL: sourceDir
        )

        #expect(summary.newFiles.count == 1)
        #expect(summary.newFiles[0].relativePath == "new_file.txt")
        #expect(summary.skipped == 2)

        // New file should exist in original
        let promoted = try String(contentsOf: sourceDir.appendingPathComponent("new_file.txt"), encoding: .utf8)
        #expect(promoted == "new file content")
    }

    @Test("New file in subdirectory creates parent dirs")
    func newFileInSubdir() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let (sourceDir, mountDir) = try setupMaterialized(tempDir: tempDir)

        // Agent creates nested file
        let subdir = mountDir.appendingPathComponent("src/new")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: subdir.appendingPathComponent("deep.swift"))

        let summary = try PromoteEngine.promote(
            sourceID: "src-1", mountName: "Test",
            mountURL: mountDir, originalURL: sourceDir
        )

        #expect(summary.newFiles.count == 1)
        let promoted = try String(
            contentsOf: sourceDir.appendingPathComponent("src/new/deep.swift"),
            encoding: .utf8
        )
        #expect(promoted == "nested")
    }

    @Test("Dry run reports counts without modifying files")
    func dryRun() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let (sourceDir, mountDir) = try setupMaterialized(tempDir: tempDir)

        // Agent modifies one file, creates one new
        try Data("changed".utf8).write(to: mountDir.appendingPathComponent("file_a.txt"))
        try Data("brand new".utf8).write(to: mountDir.appendingPathComponent("new.txt"))

        let (applied, conflicts, skipped, newFiles) = try PromoteEngine.dryRun(
            mountURL: mountDir, originalURL: sourceDir
        )

        #expect(applied == 1)
        #expect(conflicts == 0)
        #expect(skipped == 1)
        #expect(newFiles == 1)

        // Original file_a should be unchanged (dry run)
        let original = try String(contentsOf: sourceDir.appendingPathComponent("file_a.txt"), encoding: .utf8)
        #expect(original == "original content A")
    }

    @Test("Mixed scenario: apply, conflict, skip, new")
    func mixedScenario() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let fm = FileManager.default
        let sourceDir = tempDir.appendingPathComponent("original")
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("unchanged".utf8).write(to: sourceDir.appendingPathComponent("skip.txt"))
        try Data("will be cleanly modified".utf8).write(to: sourceDir.appendingPathComponent("clean.txt"))
        try Data("will conflict".utf8).write(to: sourceDir.appendingPathComponent("conflict.txt"))

        let matRoot = tempDir.appendingPathComponent("workspace")
        let source = SourceRecord(row: [
            "source_id": "src-1", "display_name": "Test",
            "original_root_path": sourceDir.path,
            "status": "active", "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z",
        ])!

        _ = try MaterializationEngine.materialize(
            grantID: "grant-1",
            sources: [(source: source, mountName: "Test")],
            materializationRoot: matRoot.path
        )

        let mountDir = matRoot.appendingPathComponent("Test")

        // Agent modifies clean.txt and conflict.txt, creates new.txt, leaves skip.txt
        try Data("agent cleaned".utf8).write(to: mountDir.appendingPathComponent("clean.txt"))
        try Data("agent conflict".utf8).write(to: mountDir.appendingPathComponent("conflict.txt"))
        try Data("agent new".utf8).write(to: mountDir.appendingPathComponent("new.txt"))

        // External edit to conflict.txt
        try Data("external conflict".utf8).write(to: sourceDir.appendingPathComponent("conflict.txt"))

        let summary = try PromoteEngine.promote(
            sourceID: "src-1", mountName: "Test",
            mountURL: mountDir, originalURL: sourceDir
        )

        #expect(summary.applied.count == 1)
        #expect(summary.applied[0].relativePath == "clean.txt")
        #expect(summary.conflicts.count == 1)
        #expect(summary.conflicts[0].relativePath == "conflict.txt")
        #expect(summary.skipped == 1) // skip.txt
        #expect(summary.newFiles.count == 1)
        #expect(summary.newFiles[0].relativePath == "new.txt")

        // Verify file states
        let cleanContent = try String(contentsOf: sourceDir.appendingPathComponent("clean.txt"), encoding: .utf8)
        #expect(cleanContent == "agent cleaned")

        let conflictContent = try String(contentsOf: sourceDir.appendingPathComponent("conflict.txt"), encoding: .utf8)
        #expect(conflictContent == "external conflict") // NOT overwritten
    }

    @Test("Missing baseline manifest throws error")
    func missingManifest() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let emptyMount = tempDir.appendingPathComponent("empty-mount")
        try FileManager.default.createDirectory(at: emptyMount, withIntermediateDirectories: true)

        #expect(throws: ManifoldError.self) {
            _ = try PromoteEngine.promote(
                sourceID: "src-1", mountName: "Test",
                mountURL: emptyMount, originalURL: tempDir
            )
        }
    }
}
