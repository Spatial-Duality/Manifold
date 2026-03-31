import Testing
import Foundation
@testable import ManifoldKit

@Suite("WorkspaceGenerator")
struct WorkspaceGeneratorTests {
    func makeTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Generate workspace from source directory")
    func generateFromDirectory() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        // Create source files
        let sourceDir = tempDir.appendingPathComponent("source/project")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "main content".data(using: .utf8)!.write(to: sourceDir.appendingPathComponent("main.swift"))
        try "test content".data(using: .utf8)!.write(to: sourceDir.appendingPathComponent("test.swift"))

        // Generate workspace using old API (still useful for Codex)
        let workspacesDir = tempDir.appendingPathComponent("workspaces")
        let generator = WorkspaceGenerator(baseURL: workspacesDir)
        let workspace = try generator.generate(agent: "cowork", sourcePaths: [sourceDir])

        #expect(workspace.agent == "cowork")
        #expect(workspace.sessionID.hasPrefix("cowork-"))

        let files = try workspace.allFiles()
        #expect(files.count == 2)

        let mainContent = try String(contentsOf: workspace.url.appendingPathComponent("project/main.swift"), encoding: .utf8)
        #expect(mainContent == "main content")
    }

    @Test("Generate workspace with email files as read-only")
    func generateWithEmails() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let emailDir = tempDir.appendingPathComponent("emails")
        try FileManager.default.createDirectory(at: emailDir, withIntermediateDirectories: true)
        let emailFile = emailDir.appendingPathComponent("client-thread.md")
        try "From: client@example.com\nSubject: Requirements\n\nHere are the requirements...".data(using: .utf8)!.write(to: emailFile)

        let sourceFile = tempDir.appendingPathComponent("code.swift")
        try "let x = 1".data(using: .utf8)!.write(to: sourceFile)

        let workspacesDir = tempDir.appendingPathComponent("workspaces")
        let generator = WorkspaceGenerator(baseURL: workspacesDir)
        let workspace = try generator.generate(
            agent: "cowork",
            sourcePaths: [sourceFile],
            emailFiles: [emailFile]
        )

        let emailDest = workspace.url.appendingPathComponent("_emails/client-thread.md")
        #expect(FileManager.default.fileExists(atPath: emailDest.path))

        let attrs = try FileManager.default.attributesOfItem(atPath: emailDest.path)
        let perms = attrs[.posixPermissions] as? Int
        #expect(perms == 0o444)
    }

    @Test("Workspace relative path computation")
    func relativePath() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let sourceFile = tempDir.appendingPathComponent("file.txt")
        try "data".data(using: .utf8)!.write(to: sourceFile)

        let generator = WorkspaceGenerator(baseURL: tempDir.appendingPathComponent("ws"))
        let workspace = try generator.generate(agent: "codex", sourcePaths: [sourceFile])

        let fileURL = workspace.url.appendingPathComponent("file.txt")
        let relative = workspace.relativePath(for: fileURL)
        #expect(relative == "file.txt")
    }

    @Test("Workspace cleanup keeps only N most recent")
    func cleanup_workspaces() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let sourceFile = tempDir.appendingPathComponent("f.txt")
        try "x".data(using: .utf8)!.write(to: sourceFile)

        let generator = WorkspaceGenerator(baseURL: tempDir.appendingPathComponent("ws"))

        for _ in 0..<5 {
            _ = try generator.generate(agent: "cowork", sourcePaths: [sourceFile])
            Thread.sleep(forTimeInterval: 0.01)
        }

        let before = try generator.listWorkspaces()
        #expect(before.count == 5)

        try generator.cleanup(keepLast: 2)

        let after = try generator.listWorkspaces()
        #expect(after.count == 2)
    }
}

@Suite("ManagedWorkspace")
struct ManagedWorkspaceTests {
    func makeTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Stable workspace syncs sources")
    func syncSources() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        // Create source
        let sourceDir = tempDir.appendingPathComponent("source/project")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "hello".data(using: .utf8)!.write(to: sourceDir.appendingPathComponent("main.swift"))

        // Create managed workspace
        let ws = ManagedWorkspace(profileID: "profile-1", agent: "cowork", baseURL: tempDir.appendingPathComponent("workspaces"))
        try ws.ensureDirectory()
        let synced = try ws.syncSources([sourceDir])

        #expect(synced.count == 1)
        #expect(synced[0] == "project/main.swift")

        let content = try String(contentsOf: ws.rootURL.appendingPathComponent("project/main.swift"), encoding: .utf8)
        #expect(content == "hello")
    }

    @Test("Sync overwrites existing files")
    func syncOverwrites() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let sourceFile = tempDir.appendingPathComponent("data.txt")
        try "version 1".data(using: .utf8)!.write(to: sourceFile)

        let ws = ManagedWorkspace(profileID: "profile-2", agent: "cowork", baseURL: tempDir.appendingPathComponent("workspaces"))
        try ws.ensureDirectory()
        try ws.syncSources([sourceFile])

        // Modify source
        try "version 2".data(using: .utf8)!.write(to: sourceFile)
        try ws.syncSources([sourceFile])

        let content = try String(contentsOf: ws.rootURL.appendingPathComponent("data.txt"), encoding: .utf8)
        #expect(content == "version 2")
    }

    @Test("Sync emails as read-only")
    func syncEmails() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let emailFile = tempDir.appendingPathComponent("thread.md")
        try "From: alice\nHi".data(using: .utf8)!.write(to: emailFile)

        let ws = ManagedWorkspace(profileID: "profile-3", agent: "cowork", baseURL: tempDir.appendingPathComponent("workspaces"))
        try ws.ensureDirectory()
        try ws.syncEmails([emailFile])

        let dest = ws.emailsURL.appendingPathComponent("thread.md")
        #expect(FileManager.default.fileExists(atPath: dest.path))

        let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
        let perms = attrs[.posixPermissions] as? Int
        #expect(perms == 0o444)
    }

    @Test("Relative path computation")
    func relativePath() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let ws = ManagedWorkspace(profileID: "profile-4", agent: "cowork", baseURL: tempDir.appendingPathComponent("workspaces"))
        try ws.ensureDirectory()
        try "x".data(using: .utf8)!.write(to: ws.rootURL.appendingPathComponent("test.txt"))

        let fileURL = ws.rootURL.appendingPathComponent("test.txt")
        let relative = ws.relativePath(for: fileURL)
        #expect(relative == "test.txt")
    }
}
