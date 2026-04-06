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
        case "status":
            try await handleStatus()
        case "log":
            try await handleLog(Array(args.dropFirst()))
        case "sources":
            try await handleSources()
        case "install":
            try handleInstall()
        default:
            print("Unknown command: \(command)")
            printUsage()
        }
    }

    static func printUsage() {
        print("""
        manifold-cli — Manifold MCP administration

        Commands:
          status     Show connection status and stats
          log        Show recent MCP activity
          sources    List approved sources
          install    Install MCP server into Claude Desktop and Codex configs
        """)
    }

    static func handleStatus() async throws {
        let storeURL = manifoldStoreURL()
        let db = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
        let auditStore = try AuditStore(db: db)

        let recent = try await auditStore.recentEntries(limit: 1)
        let connected = recent.first(where: { $0.action == "mcp_connection" })

        if let conn = connected {
            print("Status: Connected (last seen: \(conn.timestamp))")
        } else {
            print("Status: No recent MCP connections")
        }

        let entries = try await auditStore.recentEntries(limit: 50)
        let reads = entries.filter { $0.action == "file_read" }.count
        let writes = entries.filter { $0.action == "file_modified" || $0.action == "file_created" }.count
        print("Recent activity: \(reads) reads, \(writes) writes")
    }

    static func handleLog(_ args: [String]) async throws {
        let limit = Int(args.first ?? "20") ?? 20
        let storeURL = manifoldStoreURL()
        let db = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
        let auditStore = try AuditStore(db: db)

        let entries = try await auditStore.recentEntries(limit: limit)
        for entry in entries.reversed() {
            let path = entry.filePath ?? ""
            print("[\(entry.timestamp)] \(entry.action) \(path)")
        }
    }

    static func handleSources() async throws {
        let storeURL = manifoldStoreURL()
        let db = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
        let grantStore = GrantStore(db: db)
        let sources = try await grantStore.allSources()
        if sources.isEmpty {
            print("No approved sources. Use the Manifold app to add sources.")
        } else {
            for source in sources {
                let status = source.isAccessible ? "active" : source.isPaused ? "paused" : source.status
                print("\(source.originalRootPath) [\(status)]")
            }
        }
    }

    static func handleInstall() throws {
        let binaryPath = ProcessInfo.processInfo.environment["MANIFOLD_MCP_PATH"]
            ?? "\(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].path)/Manifold/bin/manifold-mcp"
        let writer = ConfigWriter(binaryPath: binaryPath)
        try writer.installAll()
        print("MCP server installed. Restart Claude Desktop to connect.")
    }

    static func manifoldStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Manifold/store")
    }
}
