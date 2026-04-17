// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("ScopedFileAccess")
struct ScopedFileAccessTests {
    func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-scoped-file-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Resolve rejects symlinked files inside the governed root")
    func resolveRejectsSymlinkedFile() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let root = tempDir.appendingPathComponent("root")
        let outside = tempDir.appendingPathComponent("outside/secret.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked.txt"),
            withDestinationURL: outside
        )

        do {
            _ = try ScopedFileAccess.resolve(relativePath: "linked.txt", rootURL: root)
            Issue.record("Expected symlinked governed file to be rejected")
        } catch let error as ManifoldError {
            if case .workspaceError(let message) = error {
                #expect(message.contains("Symlinks are not allowed"))
            } else {
                Issue.record("Expected workspaceError, got \(error)")
            }
        }
    }

    @Test("Resolve rejects symlinked directories inside the governed root")
    func resolveRejectsSymlinkedDirectory() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let root = tempDir.appendingPathComponent("root")
        let outsideDir = tempDir.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outsideDir.appendingPathComponent("secret.txt"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked-dir"),
            withDestinationURL: outsideDir
        )

        do {
            _ = try ScopedFileAccess.resolve(relativePath: "linked-dir/secret.txt", rootURL: root)
            Issue.record("Expected symlinked directory to be rejected")
        } catch let error as ManifoldError {
            if case .workspaceError(let message) = error {
                #expect(message.contains("Symlinks are not allowed"))
            } else {
                Issue.record("Expected workspaceError, got \(error)")
            }
        }
    }

    @Test("Resolve rejects hard-linked governed files")
    func resolveRejectsHardLinkedFile() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let root = tempDir.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("original.txt")
        let linked = root.appendingPathComponent("linked.txt")
        try Data("same inode".utf8).write(to: original)
        try FileManager.default.linkItem(at: original, to: linked)

        do {
            _ = try ScopedFileAccess.resolve(relativePath: "linked.txt", rootURL: root)
            Issue.record("Expected hard-linked governed file to be rejected")
        } catch let error as ManifoldError {
            if case .workspaceError(let message) = error {
                #expect(message.contains("Hard-linked files are not allowed"))
            } else {
                Issue.record("Expected workspaceError, got \(error)")
            }
        }
    }

    @Test("Atomic writes secure created files and directories")
    func writeDataAtomicallySecuresOutput() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let root = tempDir.appendingPathComponent("root")
        try LocalFileProtection.ensureDirectory(at: root)

        let written = try ScopedFileAccess.writeDataAtomically(
            Data("hello".utf8),
            relativePath: "nested/note.txt",
            rootPath: root.path
        )

        #expect(written.exists)
        #expect(written.relativePath == "nested/note.txt")
        #expect(try Data(contentsOf: written.fileURL) == Data("hello".utf8))
        #expect(try LocalFileProtection.posixPermissions(at: written.fileURL) == LocalFileProtection.fileMode)
        #expect(try LocalFileProtection.posixPermissions(at: written.fileURL.deletingLastPathComponent()) == LocalFileProtection.directoryMode)
    }
}
