import Foundation
import ManifoldKit

@main
struct ManifoldCLI {
    static func main() async throws {
        let args = CommandLine.arguments.dropFirst()
        guard let command = args.first else {
            printUsage()
            return
        }

        switch command {
        case "init":
            try await handleInit(Array(args.dropFirst()))
        case "grant":
            try await handleGrant(Array(args.dropFirst()))
        case "end-access":
            try await handleEndAccess(Array(args.dropFirst()))
        case "refresh":
            try await handleRefresh(Array(args.dropFirst()))
        case "watch":
            try await handleWatch(Array(args.dropFirst()))
        case "restore":
            try await handleRestore(Array(args.dropFirst()))
        case "log":
            try await handleLog(Array(args.dropFirst()))
        case "promote":
            try handlePromote(Array(args.dropFirst()))
        default:
            print("Unknown command: \(command)")
            printUsage()
        }
    }

    static func printUsage() {
        print("""
        manifold-cli — Manifold workspace management

        Commands:
          init <profile-id> <source-paths...>
                Create or sync a managed workspace for a profile
          grant <profile-id>
                Start an access run (Grant to Claude)
          end-access <run-id>
                End an access run
          refresh <profile-id>
                Re-sync sources and start a new run (Refresh and Continue)
          watch <profile-id>
                Watch a workspace for changes (Ctrl+C to stop)
          log <run-id>
                Show snapshot timeline for a run
          restore <run-id> <file-path>
                Restore a file to its previous version
          promote <workspace-path> <file> <dest>
                Copy a workspace file to a destination
        """)
    }

    // MARK: - Commands

    static func handleInit(_ args: [String]) async throws {
        guard args.count >= 2 else {
            print("Usage: manifold-cli init <profile-id> <source-paths...>")
            return
        }

        let profileID = args[0]
        let sourcePaths = Array(args.dropFirst()).map { URL(fileURLWithPath: $0) }

        let storeURL = manifoldStoreURL()
        let workspacesURL = manifoldWorkspacesURL()

        // Create managed workspace
        var workspace = ManagedWorkspace(profileID: profileID, agent: "cowork", baseURL: workspacesURL)
        try workspace.ensureDirectory()

        // Sync sources
        let synced = try workspace.syncSources(sourcePaths)
        workspace.lastSyncedAt = Date()

        print("Workspace created: \(workspace.rootPath)")
        print("Workspace ID: \(workspace.workspaceID)")
        print("Synced \(synced.count) files")
        print("\nPoint Cowork at: \(workspace.rootPath)")
        print("Then run: manifold-cli grant \(profileID)")
    }

    static func handleGrant(_ args: [String]) async throws {
        guard let profileID = args.first else {
            print("Usage: manifold-cli grant <profile-id>")
            return
        }

        let storeURL = manifoldStoreURL()
        let contentStore = try ContentStore(rootURL: storeURL)
        let db = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)
        let leaseManager = try WorkspaceLeaseManager(db: db, snapshotStore: snapshotStore)

        // Find or create workspace for this profile
        let workspacesURL = manifoldWorkspacesURL()
        let workspace = ManagedWorkspace(profileID: profileID, agent: "cowork", baseURL: workspacesURL)
        try workspace.ensureDirectory()

        // Register workspace
        try await leaseManager.registerWorkspace(workspace)

        // Start a new run
        let runID = try await leaseManager.startRun(
            workspaceID: workspace.workspaceID,
            agent: "cowork",
            trigger: .userGrant
        )

        // Baseline snapshot
        let files = try workspace.allFiles()
        print("Starting access run: \(runID)")
        print("Taking baseline snapshot of \(files.count) files...")

        for fileURL in files {
            guard let relativePath = workspace.relativePath(for: fileURL) else { continue }
            let data = try Data(contentsOf: fileURL)
            try await snapshotStore.recordBaseline(
                runID: runID,
                workspaceID: workspace.workspaceID,
                filePath: relativePath,
                data: data
            )
        }

        try await leaseManager.markBaselineComplete(runID: runID)
        print("Baseline complete. Access granted.")
        print("Run ID: \(runID)")
        print("\nClaude can now work in: \(workspace.rootPath)")
        print("When done: manifold-cli end-access \(runID)")
    }

    static func handleEndAccess(_ args: [String]) async throws {
        guard let runID = args.first else {
            print("Usage: manifold-cli end-access <run-id>")
            return
        }

        let storeURL = manifoldStoreURL()
        let contentStore = try ContentStore(rootURL: storeURL)
        let db = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)
        let leaseManager = try WorkspaceLeaseManager(db: db, snapshotStore: snapshotStore)

        try await leaseManager.endRun(runID: runID)
        print("Access ended for run: \(runID)")
    }

    static func handleRefresh(_ args: [String]) async throws {
        // Refresh = re-sync sources + start new run
        // For now, delegates to grant (sources are already on disk)
        print("Refresh: re-syncing sources and starting new run...")
        try await handleGrant(args)
    }

    static func handleWatch(_ args: [String]) async throws {
        guard let profileID = args.first else {
            print("Usage: manifold-cli watch <profile-id>")
            return
        }

        let storeURL = manifoldStoreURL()
        let contentStore = try ContentStore(rootURL: storeURL)
        let db = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)
        let leaseManager = try WorkspaceLeaseManager(db: db, snapshotStore: snapshotStore)

        let workspacesURL = manifoldWorkspacesURL()
        let workspace = ManagedWorkspace(profileID: profileID, agent: "cowork", baseURL: workspacesURL)
        let path = workspace.rootPath

        print("Watching \(path) for changes...")
        print("Press Ctrl+C to stop.\n")

        let watcher = FSEventsWatcher(paths: [path]) { event in
            Task {
                do {
                    let activeRun = try await leaseManager.activeRun(workspaceID: workspace.workspaceID)
                    let runID = activeRun?.runID ?? "unscoped"

                    if runID == "unscoped" {
                        print("⚠ Change detected outside an access run")
                    }

                    let relativePath = event.path.replacingOccurrences(
                        of: workspace.rootURL.path + "/",
                        with: ""
                    )
                    let timestamp = ISO8601DateFormatter().string(from: Date())

                    switch event.changeType {
                    case .created:
                        let data = try Data(contentsOf: URL(fileURLWithPath: event.path))
                        try await snapshotStore.recordCreation(
                            runID: runID,
                            workspaceID: workspace.workspaceID,
                            filePath: relativePath,
                            data: data
                        )
                        print("[\(timestamp)] CREATED: \(relativePath) (run: \(runID))")
                    case .modified:
                        let data = try Data(contentsOf: URL(fileURLWithPath: event.path))
                        try await snapshotStore.recordModification(
                            runID: runID,
                            workspaceID: workspace.workspaceID,
                            filePath: relativePath,
                            newData: data
                        )
                        print("[\(timestamp)] MODIFIED: \(relativePath) (run: \(runID))")
                    case .deleted:
                        try await snapshotStore.recordDeletion(
                            runID: runID,
                            workspaceID: workspace.workspaceID,
                            filePath: relativePath
                        )
                        print("[\(timestamp)] DELETED: \(relativePath) (run: \(runID))")
                    case .renamed:
                        print("[\(timestamp)] RENAMED: \(relativePath)")
                    }
                } catch {
                    print("ERROR recording change for \(event.path): \(error)")
                }
            }
        }

        watcher.start()

        signal(SIGINT) { _ in
            print("\nStopping watcher...")
            exit(0)
        }
        while true {
            try await Task.sleep(for: .seconds(60))
        }
    }

    static func handleLog(_ args: [String]) async throws {
        guard let runID = args.first else {
            print("Usage: manifold-cli log <run-id>")
            return
        }

        let storeURL = manifoldStoreURL()
        let contentStore = try ContentStore(rootURL: storeURL)
        let db = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)

        let timeline = try await snapshotStore.runTimeline(runID: runID)

        if timeline.isEmpty {
            print("No snapshots found for run: \(runID)")
            return
        }

        print("Run: \(runID)")
        print("Snapshots: \(timeline.count)\n")

        for record in timeline.reversed() {
            let prefix: String
            if record.isBaseline {
                prefix = "BASELINE"
            } else if record.isDelete {
                prefix = "DELETED "
            } else if record.source == "manifold-restore" {
                prefix = "RESTORE "
            } else {
                prefix = record.beforeHash == nil ? "CREATED " : "MODIFIED"
            }

            let hashPreview = record.afterHash.map { String($0.prefix(8)) } ?? "--------"
            print("  [\(record.timestamp)] \(prefix) \(record.filePath) (\(hashPreview)...)")
        }
    }

    static func handleRestore(_ args: [String]) async throws {
        guard args.count >= 2 else {
            print("Usage: manifold-cli restore <run-id> <file-path>")
            return
        }

        let runID = args[0]
        let filePath = args[1]

        let storeURL = manifoldStoreURL()
        let contentStore = try ContentStore(rootURL: storeURL)
        let db = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)

        let history = try await snapshotStore.history(runID: runID, filePath: filePath)
        guard history.count >= 2 else {
            print("No previous version to restore (only \(history.count) snapshot(s)).")
            return
        }

        let previousSnapshot = history[history.count - 2]
        guard let data = try await snapshotStore.dataForRestore(snapshotID: previousSnapshot.id) else {
            print("Could not retrieve snapshot data.")
            return
        }

        // Find the workspace for this run
        guard let wsID = try db.queryScalar(
            "SELECT workspace_id FROM runs WHERE run_id = ?",
            params: [runID]
        ) else {
            print("Could not find workspace for run.")
            return
        }
        guard let wsPath = try db.queryScalar(
            "SELECT root_path FROM workspaces WHERE workspace_id = ?",
            params: [wsID]
        ) else {
            print("Could not find workspace path.")
            return
        }

        let fileURL = URL(fileURLWithPath: wsPath).appendingPathComponent(filePath)
        try data.write(to: fileURL, options: .atomic)

        try await snapshotStore.recordRestore(
            runID: runID,
            workspaceID: wsID,
            filePath: filePath,
            restoredData: data
        )

        let hashPreview = previousSnapshot.afterHash.map { String($0.prefix(8)) } ?? "unknown"
        print("Restored \(filePath) to version \(hashPreview)... from \(previousSnapshot.timestamp)")
    }

    static func handlePromote(_ args: [String]) throws {
        guard args.count >= 3 else {
            print("Usage: manifold-cli promote <workspace-path> <file> <dest>")
            return
        }

        let sourceURL = URL(fileURLWithPath: args[0]).appendingPathComponent(args[1])
        let destURL = URL(fileURLWithPath: args[2])

        let promoter = WorkspacePromoter()
        try promoter.promoteFile(workspaceFileURL: sourceURL, to: destURL)
        print("Promoted \(args[1]) -> \(args[2])")
    }

    // MARK: - Paths

    static func manifoldStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Manifold/store")
    }

    static func manifoldWorkspacesURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Manifold/workspaces")
    }
}
