import Foundation
import MCP
import ManifoldKit

@main
struct ManifoldMCPServer {
    static func main() async throws {
        // Handle --install flag
        if CommandLine.arguments.contains("--install") {
            let binaryPath = CommandLine.arguments[0]
            let writer = ConfigWriter(binaryPath: binaryPath)
            try writer.installAll()
            fputs("Manifold MCP server installed. Restart Claude Desktop to connect.\n", stderr)
            return
        }

        // Initialize ManifoldKit stores (same database as the SwiftUI app)
        let storeURL = manifoldStoreURL()
        try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)

        let contentStore = try ContentStore(rootURL: storeURL)
        let db = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)
        let leaseManager = try WorkspaceLeaseManager(db: db, snapshotStore: snapshotStore)
        let auditStore = try AuditStore(db: db)
        let emailFilter = try EmailFilter(db: db)

        // Log MCP connection
        try? await auditStore.log(action: .mcpConnection, metadata: ["event": "connected"])

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
        let server = Server(
            name: "manifold",
            version: "0.2.0",
            capabilities: .init(
                resources: .init(listChanged: true),
                tools: .init(listChanged: false)
            )
        )

        // Register handlers (Server is an actor, need await)
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: ToolHandlers.allTools())
        }

        await server.withMethodHandler(CallTool.self) { params in
            await ToolHandlers.handle(
                name: params.name,
                arguments: params.arguments,
                bridge: bridge
            )
        }

        await server.withMethodHandler(ListResources.self) { _ in
            ListResources.Result(resources: [
                Resource(name: "Manifold Status", uri: "manifold://status", description: "Current access status"),
                Resource(name: "Approved Files", uri: "manifold://files", description: "List of files in workspace"),
                Resource(name: "Shared Emails", uri: "manifold://emails", description: "Emails available to agent"),
            ])
        }

        await server.withMethodHandler(ReadResource.self) { params in
            switch params.uri {
            case "manifold://status":
                let status = await bridge.getStatus()
                return ReadResource.Result(contents: [.text(status.message, uri: "manifold://status")])
            case "manifold://files":
                let files = (try? await bridge.listFiles()) ?? []
                return ReadResource.Result(contents: [.text(files.joined(separator: "\n"), uri: "manifold://files")])
            case "manifold://emails":
                let emails = (try? await bridge.listEmails()) ?? []
                let text = emails.map { "[\($0.id)] \($0.from) — \($0.subject)" }.joined(separator: "\n")
                return ReadResource.Result(contents: [.text(text, uri: "manifold://emails")])
            default:
                return ReadResource.Result(contents: [])
            }
        }

        // Start stdio transport (blocks until stdin closes)
        let transport = StdioTransport()
        try await server.start(transport: transport)
    }

    static func manifoldStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Manifold/store")
    }
}
