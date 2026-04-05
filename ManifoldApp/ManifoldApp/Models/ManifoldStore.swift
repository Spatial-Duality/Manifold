import SwiftUI
import Foundation
import UserNotifications
import os
import ManifoldKit

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "store")

// MARK: - Navigation

enum SidebarItem: Hashable {
    case dashboard
    case activity
    case versions
}

// MARK: - Store

@Observable
@MainActor
class ManifoldStore {
    // Navigation
    var selectedSidebarItem: SidebarItem? = .dashboard
    var inspectedFilePath: String?

    // Connection
    var isConnected = false
    var connectedAgent: String?

    // Activity
    var activityEntries: [AuditEntry] = []

    // Sources
    var approvedSources: [String] = []
    var workspaces: [WorkspaceRecord] = []

    // Emails
    var emailRules: [EmailRule] = []
    var cachedEmails: [CachedEmail] = []
    var emailClassification: EmailClassificationResult?
    var mailAccessStatus: MailAccessStatus?
    var mailboxes: [MailboxInfo] = []

    // Versions
    var allTrackedFiles: [String] = []
    var storageUsed: Int64 = 0
    var blobCount: Int = 0

    // Setup
    var mcpInstalled = false
    var installError: String?
    var claudeDesktopConfigured = false
    var codexConfigured = false

    // Onboarding
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "manifold.onboarding.completed") }
    }

    // Internal
    private var auditStore: AuditStore?
    private var emailFilter: EmailFilter?
    private(set) var snapshotStore: SnapshotStore?
    private(set) var contentStore: ContentStore?
    private var leaseManager: WorkspaceLeaseManager?
    private var db: DatabaseConnection?
    private var pollTimer: Timer?
    private var notificationObservers: [NSObjectProtocol] = []
    private var runTimers: [String: Timer] = [:]
    private let mailConnector = AppleMailConnector()

    var menuBarIcon: String { isConnected ? "shield.checkered.fill" : "shield.checkered" }

    // MARK: - Init

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "manifold.onboarding.completed")
        Task {
            await initStores()
            setupNotificationObservers()
            requestNotificationPermission()
        }
    }

    private func initStores() async {
        do {
            let storeURL = Self.storeURL()
            try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
            let contentStore = try ContentStore(rootURL: storeURL)
            self.contentStore = contentStore
            let connection = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
            self.db = connection
            self.auditStore = try AuditStore(db: connection)
            self.snapshotStore = try SnapshotStore(db: connection, contentStore: contentStore)
            self.emailFilter = try EmailFilter(db: connection)
            self.leaseManager = try WorkspaceLeaseManager(db: connection, snapshotStore: self.snapshotStore!)
            checkMCPInstalled(); checkAgentConfigs()
            await refresh()
            _ = try? await self.snapshotStore?.pruneByAge(days: 30)
            _ = try? await self.snapshotStore?.pruneByFileCount(maxPerFile: 50)
            _ = try? await self.contentStore?.garbageCollect()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refresh() }
            }
        } catch {
            logger.error("Failed to init stores: \(error.localizedDescription)")
        }
    }

    // MARK: - Notifications

    private func setupNotificationObservers() {
        let connected = ManifoldNotification.observe(ManifoldNotification.agentConnected) { [weak self] info in
            Task { @MainActor in self?.isConnected = true; self?.connectedAgent = info["agent"] ?? "Claude"; await self?.refresh() }
        }
        let disconnected = ManifoldNotification.observe(ManifoldNotification.agentDisconnected) { [weak self] _ in
            Task { @MainActor in self?.isConnected = false; self?.connectedAgent = nil }
        }
        let denied = ManifoldNotification.observe(ManifoldNotification.accessDenied) { [weak self] info in
            Task { @MainActor in self?.showAccessDeniedNotification(info: info) }
        }
        let dataChanged = ManifoldNotification.observe(ManifoldNotification.dataChanged) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        notificationObservers = [connected, disconnected, denied, dataChanged]
    }

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func showAccessDeniedNotification(info: [String: String]) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Access Denied"
        content.body = "\(info["agent"] ?? "Agent") tried to \(info["action"] ?? "access") \(info["path"] ?? "unknown")"
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "manifold-denied-\(UUID().uuidString.prefix(8))", content: content, trigger: nil)
        )
    }

    // MARK: - Refresh

    func refresh() async {
        guard let auditStore else { return }
        activityEntries = (try? await auditStore.recentEntries(limit: 100)) ?? []
        if !isConnected {
            if let recent = activityEntries.first(where: { $0.action == "mcp_connection" }),
               let ts = ISO8601DateFormatter().date(from: recent.timestamp) {
                isConnected = Date().timeIntervalSince(ts) < 300
                connectedAgent = recent.agent ?? "Claude"
            }
        }
        if let db {
            approvedSources = (try? db.queryAll("SELECT root_path FROM workspaces WHERE status != 'archived'"))?.compactMap { $0["root_path"] } ?? []
        }
    }

    // MARK: - Sources

    func addSource(path: String) {
        guard !approvedSources.contains(path) else { return }
        approvedSources.append(path)
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        Task {
            let wsID = "ws-\(UUID().uuidString.prefix(8).lowercased())"
            try? await leaseManager?.registerWorkspace(id: wsID, profileID: "default", rootPath: path, agent: "cowork")
            try? await auditStore?.log(action: .sourceAdded, filePath: path, metadata: ["folder": folderName])
            await loadWorkspaces()
        }
    }

    func removeSource(path: String) {
        approvedSources.removeAll { $0 == path }
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        Task {
            // Archive the workspace instead of deleting
            if let ws = workspaces.first(where: { $0.rootPath == path }) {
                try? await leaseManager?.updateWorkspaceStatus(workspaceID: ws.workspaceID, status: "archived")
            }
            try? await auditStore?.log(action: .sourceRemoved, filePath: path, metadata: ["folder": folderName])
            await loadWorkspaces()
        }
    }

    func pauseSource(workspaceID: String) async {
        try? await leaseManager?.updateWorkspaceStatus(workspaceID: workspaceID, status: "archived")
        await loadWorkspaces()
        await refresh()
    }

    func resumeSource(workspaceID: String) async {
        try? await leaseManager?.updateWorkspaceStatus(workspaceID: workspaceID, status: "idle")
        await loadWorkspaces()
        await refresh()
    }

    func addSourceFromPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select folders for AI agents to access"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addSource(path: url.path) }
    }

    func loadWorkspaces() async {
        workspaces = (try? await leaseManager?.allWorkspaces()) ?? []
    }

    func activeRunForWorkspace(_ workspaceID: String) async -> RunRecord? {
        try? await leaseManager?.activeRun(workspaceID: workspaceID)
    }

    func runsForWorkspace(_ workspaceID: String) async -> [RunRecord] {
        (try? await leaseManager?.runs(workspaceID: workspaceID)) ?? []
    }

    func startRun(workspaceID: String, agent: String) async {
        _ = try? await leaseManager?.startRun(workspaceID: workspaceID, agent: agent, trigger: .userGrant)
        try? await auditStore?.log(action: .runStart, workspaceID: workspaceID, agent: agent)
        await loadWorkspaces(); await refresh()
    }

    func endRun(runID: String) async {
        try? await leaseManager?.endRun(runID: runID)
        try? await auditStore?.log(action: .runEnd)
        runTimers[runID]?.invalidate(); runTimers.removeValue(forKey: runID)
        await loadWorkspaces(); await refresh()
    }

    // MARK: - Emails

    func checkMailAccess() async {
        do { mailAccessStatus = try mailConnector.checkAccess() }
        catch { mailAccessStatus = .accessDenied }
    }
    func loadMailboxes() async {
        do { mailboxes = try mailConnector.listMailboxes() } catch { mailboxes = [] }
    }
    func fetchAndCacheEmails(account: String, mailbox: String) async {
        guard let emailFilter else { return }
        let emails: [RenderedEmail]
        do { emails = try mailConnector.fetchMessages(account: account, mailbox: mailbox, limit: 100) } catch { return }
        for email in emails { try? await emailFilter.cacheEmail(email, account: account, mailbox: mailbox) }
        await reclassifyEmails(); await loadCachedEmails()
    }
    func loadEmailRules() async { emailRules = (try? await emailFilter?.globalRules()) ?? [] }
    func addEmailRule(type: RuleType, pattern: String, category: String) async {
        try? await emailFilter?.addGlobalRule(type: type, pattern: pattern, category: category)
        await loadEmailRules(); await reclassifyEmails()
    }
    func removeEmailRule(id: Int) async {
        try? await emailFilter?.removeRule(id: id); await loadEmailRules(); await reclassifyEmails()
    }
    func overrideEmailToShared(messageID: String) async {
        try? await emailFilter?.overrideToShared(messageID: messageID); await loadCachedEmails()
    }
    func hideEmail(messageID: String) async {
        try? await emailFilter?.hideEmail(messageID: messageID, reason: "User hidden"); await loadCachedEmails()
    }
    func reclassifyEmails() async { emailClassification = try? await emailFilter?.classifyAll() }
    func loadCachedEmails() async { cachedEmails = (try? await emailFilter?.allCachedEmails()) ?? [] }

    // MARK: - Versions

    func loadTrackedFiles() async { allTrackedFiles = (try? await snapshotStore?.allTrackedFiles()) ?? [] }
    func loadStorageStats() async {
        storageUsed = (try? await contentStore?.totalSize()) ?? 0
        blobCount = (try? await contentStore?.blobCount()) ?? 0
    }
    func fileHistory(filePath: String) async -> [SnapshotRecord] {
        (try? await snapshotStore?.fileHistory(filePath: filePath)) ?? []
    }
    func snapshotData(hash: String) async -> Data? { try? await contentStore?.retrieve(hash: hash) }
    func restoreFile(snapshotID: Int, filePath: String, toDirectory: String) async -> Bool {
        guard let data = try? await snapshotStore?.dataForRestore(snapshotID: snapshotID) else { return false }
        let fullPath = URL(fileURLWithPath: toDirectory).appendingPathComponent(filePath)
        do {
            try FileManager.default.createDirectory(at: fullPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fullPath, options: .atomic)
            try? await auditStore?.log(action: .restore, filePath: filePath, metadata: ["snapshot_id": "\(snapshotID)"])
            return true
        } catch { return false }
    }

    // MARK: - Setup

    func checkMCPInstalled() { mcpInstalled = FileManager.default.fileExists(atPath: Self.mcpBinaryPath()) }
    func checkAgentConfigs() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        claudeDesktopConfigured = FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json").path)
        codexConfigured = FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex/config.toml").path)
    }
    func installMCP() {
        installError = nil
        do {
            let destPath = Self.mcpBinaryPath()
            let destURL = URL(fileURLWithPath: destPath)
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let bundled = Bundle.main.url(forResource: "manifold-mcp", withExtension: nil) {
                if FileManager.default.fileExists(atPath: destPath) { try FileManager.default.removeItem(at: destURL) }
                try FileManager.default.copyItem(at: bundled, to: destURL)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)
            } else if !FileManager.default.fileExists(atPath: destPath) {
                let debugBin = URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent(".build/debug/manifold-mcp")
                if FileManager.default.fileExists(atPath: debugBin.path) {
                    try FileManager.default.copyItem(at: debugBin, to: destURL)
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)
                } else { installError = "MCP binary not found. Run: swift build --product manifold-mcp"; return }
            }
            try ConfigWriter(binaryPath: destPath).installAll()
            checkMCPInstalled(); checkAgentConfigs()
        } catch { installError = "Install failed: \(error.localizedDescription)" }
    }
    func runGarbageCollection() async -> Int { (try? await contentStore?.garbageCollect()) ?? 0 }
    func pruneOldRuns() async -> Int { (try? await snapshotStore?.pruneOldRuns(keepLast: 10)) ?? 0 }
    func runIntegrityCheck() async -> Bool { (try? db?.integrityCheck()) ?? false }

    func loadSummary() async {
        await loadWorkspaces(); await loadStorageStats(); await loadTrackedFiles(); await reclassifyEmails()
    }

    static func storeURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Manifold/store")
    }
    static func mcpBinaryPath() -> String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Manifold/bin/manifold-mcp").path
    }
}
