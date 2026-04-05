import Foundation
import os
import ManifoldKit

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "mcp")

@main
struct ManifoldMCPServer {
    static func main() async throws {
        // Handle --install flag
        if CommandLine.arguments.contains("--install") {
            let binaryPath = CommandLine.arguments[0]
            let writer = ConfigWriter(binaryPath: binaryPath)
            try writer.installAll()
            fputs("Manifold MCP server installed. Restart Claude Desktop to connect.\n", stderr)
            logger.info("MCP server installed via --install flag")
            return
        }

        // Initialize ManifoldKit stores (same database as the SwiftUI app)
        let storeURL = manifoldStoreURL()
        try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)

        let contentStore = try ContentStore(rootURL: storeURL)
        let db = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))

        // Run pending schema migrations before initializing stores
        let migrator = try DatabaseMigrator(db: db)
        let migrated = try migrator.migrate()
        if migrated > 0 {
            logger.info("Applied \(migrated) database migration(s)")
        }

        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)
        let leaseManager = try WorkspaceLeaseManager(db: db, snapshotStore: snapshotStore)
        let auditStore = try AuditStore(db: db)
        let emailFilter = try EmailFilter(db: db)

        // Log MCP connection and notify the app
        try? await auditStore.log(action: .mcpConnection, metadata: ["event": "connected"])
        ManifoldNotification.post(ManifoldNotification.agentConnected, userInfo: ["agent": "cowork"])

        // Create bridge
        let bridge = ManifoldBridge(
            db: db,
            contentStore: contentStore,
            snapshotStore: snapshotStore,
            leaseManager: leaseManager,
            auditStore: auditStore,
            emailFilter: emailFilter
        )

        // Create MCP server
        let server = MCPServer(name: "manifold", version: "0.2.0")

        // Register tools
        server.registerTools(ToolHandlers.allTools()) { name, arguments in
            let result = await ToolHandlers.handle(name: name, arguments: arguments.value, bridge: bridge)
            return JSONDict(result)
        }

        // Register resources
        server.registerResources([
            MCPResource(name: "Manifold Status", uri: "manifold://status", description: "Current access status"),
            MCPResource(name: "Approved Files", uri: "manifold://files", description: "List of files in workspace"),
            MCPResource(name: "Shared Emails", uri: "manifold://emails", description: "Emails available to agent"),
        ]) { uri in
            switch uri {
            case "manifold://status":
                let status = await bridge.getStatus()
                return status.message
            case "manifold://files":
                let files = (try? await bridge.listFiles()) ?? []
                return files.map { "[\($0.sourceName)] \($0.path)" }.joined(separator: "\n")
            case "manifold://emails":
                let emails = (try? await bridge.listEmails()) ?? []
                return emails.map { "[\($0.id)] \($0.from) — \($0.subject)" }.joined(separator: "\n")
            default:
                return ""
            }
        }

        // Start stdio transport (blocks until stdin closes)
        defer {
            ManifoldNotification.post(ManifoldNotification.agentDisconnected, userInfo: ["agent": "cowork"])
        }
        try await server.start()
    }

    static func manifoldStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Manifold/store")
    }
}
