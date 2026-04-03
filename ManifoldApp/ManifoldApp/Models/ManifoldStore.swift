import SwiftUI
import Foundation
import ManifoldKit

/// Central store for the MCP Dashboard. Reads from the shared SQLite database.
/// The MCP server writes audit entries. This app reads them and displays live activity.
@MainActor
class ManifoldStore: ObservableObject {
    // MARK: - Published state

    @Published var activityEntries: [AuditEntry] = []
    @Published var approvedSources: [String] = []
    @Published var isConnected = false
    @Published var connectedAgent: String?
    @Published var mcpInstalled = false

    // MARK: - Stores

    private var auditStore: AuditStore?
    private var emailFilter: EmailFilter?
    private var db: DatabaseConnection?
    private var pollTimer: Timer?

    var connectionIcon: String {
        isConnected ? "circle.fill" : "circle"
    }

    // MARK: - Init

    init() {
        Task { await initStores() }
    }

    private func initStores() async {
        do {
            let storeURL = Self.storeURL()
            try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
            let connection = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
            self.db = connection
            self.auditStore = try AuditStore(db: connection)
            self.emailFilter = try EmailFilter(db: connection)

            // Check if MCP binary exists
            checkMCPInstalled()

            // Load initial data
            await refresh()

            // Poll for new activity every 2 seconds
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refresh()
                }
            }
        } catch {
            print("Failed to init stores: \(error)")
        }
    }

    // MARK: - Refresh

    func refresh() async {
        guard let auditStore = auditStore else { return }

        // Load recent activity
        activityEntries = (try? await auditStore.recentEntries(limit: 100)) ?? []

        // Check connection status (look for recent mcp_connection event)
        let recent = activityEntries.first(where: { $0.action == "mcp_connection" })
        if let recent = recent, let ts = ISO8601DateFormatter().date(from: recent.timestamp) {
            isConnected = Date().timeIntervalSince(ts) < 300 // Connected in last 5 min
            connectedAgent = recent.agent ?? "Claude"
        } else {
            isConnected = false
            connectedAgent = nil
        }

        // Load approved sources from workspaces table
        if let db = db {
            let rows = (try? db.queryAll("SELECT root_path FROM workspaces")) ?? []
            approvedSources = rows.compactMap { $0["root_path"] }
        }
    }

    // MARK: - Source Management

    func addSource(path: String) {
        if !approvedSources.contains(path) {
            approvedSources.append(path)
            Task {
                try? await auditStore?.log(action: .sourceAdded, metadata: ["path": path])
            }
        }
    }

    func removeSource(path: String) {
        approvedSources.removeAll { $0 == path }
        Task {
            try? await auditStore?.log(action: .sourceRemoved, metadata: ["path": path])
        }
    }

    func addSourceFromPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select files or folders for AI agents to access"

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            addSource(path: url.path)
        }
    }

    // MARK: - MCP Install

    func checkMCPInstalled() {
        let binaryPath = Self.mcpBinaryPath()
        mcpInstalled = FileManager.default.fileExists(atPath: binaryPath)
    }

    func installMCP() {
        let binaryPath = Self.mcpBinaryPath()
        let writer = ConfigWriter(binaryPath: binaryPath)
        do {
            try writer.installAll()
            checkMCPInstalled()
        } catch {
            print("MCP install failed: \(error)")
        }
    }

    // MARK: - Paths

    static func storeURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Manifold/store")
    }

    static func mcpBinaryPath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Manifold/bin/manifold-mcp").path
    }
}
