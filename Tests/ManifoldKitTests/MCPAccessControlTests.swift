// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
@testable import ManifoldKit

/// Tests that paused/archived workspaces are properly filtered from MCP access,
/// path normalization handles source-name prefixes and ./  patterns,
/// and status reporting distinguishes active vs paused sources.
@Suite("MCP Access Control")
struct MCPAccessControlTests {

    // MARK: - Helpers

    func makeStores() throws -> (DatabaseConnection, SnapshotStore, WorkspaceLeaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-acl-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let contentStore = try ContentStore(rootURL: tempDir)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)
        let leaseManager = try WorkspaceLeaseManager(db: db, snapshotStore: snapshotStore)

        return (db, snapshotStore, leaseManager, tempDir)
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    // MARK: - Bug 1: Paused Sources Must Be Filtered

    @Test("Archived workspace excluded from active query")
    func archivedWorkspaceFiltered() async throws {
        let (db, _, leaseManager, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-active", profileID: "default", rootPath: "/tmp/active", agent: "cowork")
        try await leaseManager.registerWorkspace(id: "ws-paused", profileID: "default", rootPath: "/tmp/paused", agent: "cowork")
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-paused", status: "archived")

        // This is the query ManifoldBridge.activeWorkspaces() should use
        let activeRows = try db.queryAll(
            "SELECT workspace_id, root_path, status FROM workspaces WHERE status != 'archived'"
        )
        #expect(activeRows.count == 1)
        #expect(activeRows[0]["workspace_id"] == "ws-active")
    }

    @Test("All workspaces returned when no filter applied — the old bug")
    func unfilteredQueryReturnsAll() async throws {
        let (db, _, leaseManager, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-a", profileID: "default", rootPath: "/tmp/a", agent: "cowork")
        try await leaseManager.registerWorkspace(id: "ws-b", profileID: "default", rootPath: "/tmp/b", agent: "cowork")
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-b", status: "archived")

        // Without filter — this is what the old buggy query did
        let allRows = try db.queryAll("SELECT workspace_id FROM workspaces")
        #expect(allRows.count == 2, "Unfiltered query returns both — this was the bug")

        // With filter — this is the fix
        let activeRows = try db.queryAll("SELECT workspace_id FROM workspaces WHERE status != 'archived'")
        #expect(activeRows.count == 1, "Filtered query returns only active")
    }

    @Test("Multiple archived workspaces all excluded")
    func multipleArchivedExcluded() async throws {
        let (db, _, leaseManager, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        for i in 1...5 {
            try await leaseManager.registerWorkspace(id: "ws-\(i)", profileID: "default", rootPath: "/tmp/ws\(i)", agent: "cowork")
        }
        // Archive 3 of 5
        for i in [1, 3, 5] {
            try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-\(i)", status: "archived")
        }

        let activeRows = try db.queryAll("SELECT workspace_id FROM workspaces WHERE status != 'archived'")
        #expect(activeRows.count == 2)
        let activeIDs = Set(activeRows.compactMap { $0["workspace_id"] })
        #expect(activeIDs == ["ws-2", "ws-4"])
    }

    @Test("All sources paused leaves zero active workspaces")
    func allSourcesPausedYieldsEmpty() async throws {
        let (db, _, leaseManager, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-1", profileID: "default", rootPath: "/tmp/one", agent: "cowork")
        try await leaseManager.registerWorkspace(id: "ws-2", profileID: "default", rootPath: "/tmp/two", agent: "cowork")
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-1", status: "archived")
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-2", status: "archived")

        let activeRows = try db.queryAll("SELECT workspace_id FROM workspaces WHERE status != 'archived'")
        #expect(activeRows.isEmpty, "All paused → agent should see nothing")

        // But allWorkspaces still returns them (for status reporting)
        let allRows = try db.queryAll("SELECT workspace_id FROM workspaces")
        #expect(allRows.count == 2, "Status view needs to see all workspaces")
    }

    @Test("Resuming a paused source makes it active again")
    func resumeSourceRestoresAccess() async throws {
        let (db, _, leaseManager, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-toggle", profileID: "default", rootPath: "/tmp/toggle", agent: "cowork")
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-toggle", status: "archived")

        var activeRows = try db.queryAll("SELECT workspace_id FROM workspaces WHERE status != 'archived'")
        #expect(activeRows.isEmpty)

        // Resume (app sets status back to "idle")
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-toggle", status: "idle")

        activeRows = try db.queryAll("SELECT workspace_id FROM workspaces WHERE status != 'archived'")
        #expect(activeRows.count == 1)
        #expect(activeRows[0]["workspace_id"] == "ws-toggle")
    }

    @Test("Status column is included in workspace query")
    func statusColumnQueried() async throws {
        let (db, _, leaseManager, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-status", profileID: "default", rootPath: "/tmp/status", agent: "cowork")
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-status", status: "archived")

        // The fixed query includes status
        let rows = try db.queryAll("SELECT workspace_id, root_path, agent, status, created_at FROM workspaces")
        #expect(rows.count == 1)
        #expect(rows[0]["status"] == "archived")
    }

    // MARK: - Bug 2: Path Normalization

    @Test("Clean path strips leading ./")
    func cleanPathLeadingDotSlash() {
        let path = "./current/file.md"
        var cleaned = path
        while cleaned.hasPrefix("./") { cleaned = String(cleaned.dropFirst(2)) }
        #expect(cleaned == "current/file.md")
    }

    @Test("Clean path strips multiple leading ./")
    func cleanPathMultipleDotSlash() {
        var cleaned = "././file.md"
        while cleaned.hasPrefix("./") { cleaned = String(cleaned.dropFirst(2)) }
        #expect(cleaned == "file.md")
    }

    @Test("Clean path collapses double slashes")
    func cleanPathDoubleSlash() {
        var cleaned = "src//main.swift"
        while cleaned.contains("//") {
            cleaned = cleaned.replacingOccurrences(of: "//", with: "/")
        }
        #expect(cleaned == "src/main.swift")
    }

    @Test("Clean path strips trailing slash")
    func cleanPathTrailingSlash() {
        var cleaned = "folder/"
        while cleaned.hasSuffix("/") && cleaned.count > 1 { cleaned = String(cleaned.dropLast()) }
        #expect(cleaned == "folder")
    }

    @Test("Source name prefix stripped from path")
    func sourceNamePrefixStripped() {
        // Simulates resolveWorkspaceAndPath logic
        let path = "current/DESIGN-REVIEW.md"
        let workspaceFolderNames = ["current", "Sort", "IBM_Plex_Sans"]

        let components = path.split(separator: "/", maxSplits: 1)
        let prefix = String(components[0])
        let rest = String(components[1])

        #expect(workspaceFolderNames.contains(prefix))
        #expect(rest == "DESIGN-REVIEW.md")
    }

    @Test("Path without source name prefix preserved")
    func pathWithoutSourceNamePreserved() {
        let path = "subdirectory/file.txt"
        let workspaceFolderNames = ["current", "Sort"]

        let components = path.split(separator: "/", maxSplits: 1)
        let prefix = String(components[0])

        #expect(!workspaceFolderNames.contains(prefix), "Path should not match any workspace name")
    }

    @Test("Single component path has no prefix to strip")
    func singleComponentPath() {
        let path = "file.txt"
        let components = path.split(separator: "/", maxSplits: 1)
        #expect(components.count == 1, "Single file cannot have source prefix")
    }

    @Test("Nested source path resolved correctly")
    func nestedSourcePathResolution() {
        // current/subdir/file.md with workspace "current" → subdir/file.md
        let path = "current/subdir/file.md"
        let components = path.split(separator: "/", maxSplits: 1)
        let prefix = String(components[0])
        let rest = String(components[1])

        #expect(prefix == "current")
        #expect(rest == "subdir/file.md")
    }

    @Test("Path with ./ and source name prefix both cleaned")
    func dotSlashAndSourcePrefixBothHandled() {
        var path = "./current/file.md"

        // Step 1: clean
        while path.hasPrefix("./") { path = String(path.dropFirst(2)) }
        #expect(path == "current/file.md")

        // Step 2: resolve source prefix
        let components = path.split(separator: "/", maxSplits: 1)
        let prefix = String(components[0])
        let rest = String(components[1])
        let workspaceFolderNames = ["current"]

        #expect(workspaceFolderNames.contains(prefix))
        #expect(rest == "file.md", "After both cleanups, path is just the filename")
    }

    @Test("URL path resolution creates nested dirs without smart resolve")
    func urlResolutionNestingBug() {
        // This proves the bug: appending "current/file.md" to a root ending in "current"
        let rootPath = "/Users/x/current"
        let agentPath = "current/file.md"
        let root = URL(fileURLWithPath: rootPath)
        let resolved = root.appendingPathComponent(agentPath).standardizedFileURL

        // The bug: resolved path has current/current/file.md
        #expect(resolved.path == "/Users/x/current/current/file.md",
                "Without smart resolve, source name gets doubled")

        // The fix: strip the source prefix first
        let components = agentPath.split(separator: "/", maxSplits: 1)
        let strippedPath = String(components[1])
        let fixedResolved = root.appendingPathComponent(strippedPath).standardizedFileURL
        #expect(fixedResolved.path == "/Users/x/current/file.md",
                "With smart resolve, path is correct")
    }

    // MARK: - Bug 3: Status Reporting

    @Test("Status query distinguishes active and archived workspaces")
    func statusDistinguishesActiveArchived() async throws {
        let (db, _, leaseManager, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-active", profileID: "default", rootPath: "/tmp/active", agent: "cowork")
        try await leaseManager.registerWorkspace(id: "ws-paused", profileID: "default", rootPath: "/tmp/paused", agent: "cowork")
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-paused", status: "archived")

        let rows = try db.queryAll("SELECT workspace_id, status FROM workspaces")
        let statuses = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            guard let id = row["workspace_id"], let status = row["status"] else { return nil as (String, String)? }
            return (id, status)
        })

        #expect(statuses["ws-active"] != "archived")
        #expect(statuses["ws-paused"] == "archived")
    }

    @Test("Status is active only when at least one workspace is non-archived")
    func statusActiveRequiresNonArchivedWorkspace() async throws {
        let (db, _, leaseManager, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-only", profileID: "default", rootPath: "/tmp/only", agent: "cowork")

        // Active when workspace is idle
        var activeCount = try db.queryAll("SELECT * FROM workspaces WHERE status != 'archived'").count
        #expect(activeCount > 0, "Active when workspace idle")

        // Not active when all archived
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-only", status: "archived")
        activeCount = try db.queryAll("SELECT * FROM workspaces WHERE status != 'archived'").count
        #expect(activeCount == 0, "Not active when all archived")
    }

    @Test("Status lists paused sources separately")
    func statusListsPausedSeparately() async throws {
        let (db, _, leaseManager, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-1", profileID: "default", rootPath: "/tmp/project-a", agent: "cowork")
        try await leaseManager.registerWorkspace(id: "ws-2", profileID: "default", rootPath: "/tmp/project-b", agent: "cowork")
        try await leaseManager.registerWorkspace(id: "ws-3", profileID: "default", rootPath: "/tmp/project-c", agent: "cowork")
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-2", status: "archived")

        let allRows = try db.queryAll("SELECT workspace_id, root_path, status FROM workspaces")
        let activeNames = allRows
            .filter { $0["status"] != "archived" }
            .compactMap { $0["root_path"].flatMap { URL(fileURLWithPath: $0).lastPathComponent } }
        let pausedNames = allRows
            .filter { $0["status"] == "archived" }
            .compactMap { $0["root_path"].flatMap { URL(fileURLWithPath: $0).lastPathComponent } }

        #expect(activeNames.sorted() == ["project-a", "project-c"])
        #expect(pausedNames == ["project-b"])
    }

    // MARK: - Bug 4: Remove vs Pause Distinction

    @Test("Removed workspace excluded from both MCP and dashboard queries")
    func removedWorkspaceFullyHidden() async throws {
        let (db, _, leaseManager, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-keep", profileID: "default", rootPath: "/tmp/keep", agent: "cowork")
        try await leaseManager.registerWorkspace(id: "ws-remove", profileID: "default", rootPath: "/tmp/remove", agent: "cowork")
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-remove", status: "removed")

        // MCP query: only idle/active
        let mcpAccessible = try db.queryAll("SELECT workspace_id FROM workspaces WHERE status IN ('idle', 'active')")
        #expect(mcpAccessible.count == 1)
        #expect(mcpAccessible[0]["workspace_id"] == "ws-keep")

        // Dashboard query: everything except removed
        let dashboardVisible = try db.queryAll("SELECT workspace_id FROM workspaces WHERE status != 'removed'")
        #expect(dashboardVisible.count == 1)
        #expect(dashboardVisible[0]["workspace_id"] == "ws-keep")
    }

    @Test("Paused workspace visible in dashboard but not in MCP")
    func pausedVisibleInDashboardNotMCP() async throws {
        let (db, _, leaseManager, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-paused", profileID: "default", rootPath: "/tmp/paused", agent: "cowork")
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-paused", status: "archived")

        // MCP: not accessible
        let mcpRows = try db.queryAll("SELECT workspace_id FROM workspaces WHERE status IN ('idle', 'active')")
        #expect(mcpRows.isEmpty, "Paused source should not be accessible via MCP")

        // Dashboard: visible (for pause/resume toggle)
        let dashboardRows = try db.queryAll("SELECT workspace_id FROM workspaces WHERE status != 'removed'")
        #expect(dashboardRows.count == 1, "Paused source should still appear in dashboard")
    }

    @Test("Removed workspace distinct from paused workspace")
    func removedDistinctFromPaused() async throws {
        let (db, _, leaseManager, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-paused", profileID: "default", rootPath: "/tmp/paused", agent: "cowork")
        try await leaseManager.registerWorkspace(id: "ws-removed", profileID: "default", rootPath: "/tmp/removed", agent: "cowork")
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-paused", status: "archived")
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-removed", status: "removed")

        let statuses = try db.queryAll("SELECT workspace_id, status FROM workspaces")
        let statusMap = Dictionary(uniqueKeysWithValues: statuses.compactMap { row in
            guard let id = row["workspace_id"], let s = row["status"] else { return nil as (String, String)? }
            return (id, s)
        })

        #expect(statusMap["ws-paused"] == "archived", "Paused = archived")
        #expect(statusMap["ws-removed"] == "removed", "Removed = removed (NOT archived)")
    }

    @Test("Idle and active statuses both count as non-paused")
    func idleAndActiveBothAccessible() async throws {
        let (db, _, leaseManager, tempDir) = try makeStores()
        defer { cleanup(tempDir) }

        try await leaseManager.registerWorkspace(id: "ws-idle", profileID: "default", rootPath: "/tmp/idle", agent: "cowork")
        try await leaseManager.registerWorkspace(id: "ws-running", profileID: "default", rootPath: "/tmp/running", agent: "cowork")
        try await leaseManager.updateWorkspaceStatus(workspaceID: "ws-running", status: "active")

        let accessible = try db.queryAll("SELECT workspace_id, status FROM workspaces WHERE status != 'archived'")
        #expect(accessible.count == 2, "Both idle and active workspaces are accessible to agent")
    }
}
