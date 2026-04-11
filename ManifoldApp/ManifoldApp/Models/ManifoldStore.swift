import SwiftUI
import Foundation
import UserNotifications
import CommonCrypto
import os
import ManifoldKit

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "store")

// MARK: - Navigation

/// Top-level tabs in v4.1: Overview, Files, Emails.
/// History is demoted to Activity drawer. Sources is merged into Files tab.
enum AppTab: String, Hashable, CaseIterable {
    case overview
    case files
    case emails
}

/// Legacy sidebar items — kept during transition for views that still reference them.
enum SidebarItem: String, Hashable, CaseIterable {
    case home
    case files
    case emails
    case history
    case sources
}

// MARK: - Agent Focus

/// Which agent's access to display in Files/Emails tables.
enum AgentFocus: String, Hashable, CaseIterable {
    case claude
    case codex
    case compare

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .compare: "both agents"
        }
    }
}

// MARK: - Store

@Observable
@MainActor
class ManifoldStore {
    // Navigation — v4.1 top-level tabs
    var selectedTab: AppTab = .overview
    var agentFocus: AgentFocus = .claude

    // Global sheet/drawer state
    var showReviewSheet = false
    var showActivityDrawer = false
    var reviewSheetTrigger: ReviewAccessChange?

    // Legacy navigation (kept during transition)
    var selectedSidebarItem: SidebarItem? = .home
    var inspectedFilePath: String?

    // Connection
    var isConnected = false
    var connectedAgent: String?

    // Sources
    var sources: [SourceRecord] = []
    var approvedSources: [String] { sources.filter(\.isAccessible).map(\.originalRootPath) }

    // Errors
    var lastError: String?

    // Sub-models
    let session: SessionModel
    let history: HistoryModel
    let storage: StorageModel
    let setup: SetupModel
    let emailAccounts: EmailAccountModel
    let policy: PolicyModel
    let integrationHealth = IntegrationHealthModel()

    var menuBarIcon: String { isConnected ? "shield.checkered.fill" : "shield.checkered" }

    // Internal
    private var auditStore: AuditStore?
    private(set) var snapshotStore: SnapshotStore?
    private(set) var contentStore: ContentStore?
    private var leaseManager: WorkspaceLeaseManager?
    private(set) var grantStore: GrantStore?
    private(set) var emailStore: EmailStore?
    private(set) var artifactIndex: ArtifactIndex?
    private var db: DatabaseConnection?
    private var pollTimer: Timer?
    private var notificationObservers: [NSObjectProtocol] = []
    private var syncEngine: EmailSyncEngine?

    // MARK: - Init

    init() {
        session = SessionModel()
        history = HistoryModel()
        storage = StorageModel()
        setup = SetupModel()
        emailAccounts = EmailAccountModel()
        policy = PolicyModel()

        integrationHealth.store = self

        Task {
            await initStores()
            if db == nil {
                lastError = "Failed to initialize database. Try restarting Manifold."
            }
            setupNotificationObservers()
            requestNotificationPermission()
            await integrationHealth.checkAll()
        }
    }

    private func initStores() async {
        do {
            let storeURL = Self.storeURL
            try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
            let connection = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
            self.db = connection

            let migrator = try DatabaseMigrator(db: connection)
            try migrator.migrate()

            // ContentStore shares the DB connection (avoids duplicate handles)
            let contentStore = try ContentStore(rootURL: storeURL, db: connection)
            self.contentStore = contentStore

            let auditStore = try AuditStore(db: connection)
            let snapshotStore = try SnapshotStore(db: connection, contentStore: contentStore)
            let leaseManager = try WorkspaceLeaseManager(db: connection, snapshotStore: snapshotStore)
            let grantStore = GrantStore(db: connection)
            let emailStore = EmailStore(db: connection)
            let artifactIndex = try ArtifactIndex(db: connection)

            self.auditStore = auditStore
            self.snapshotStore = snapshotStore
            self.leaseManager = leaseManager
            self.grantStore = grantStore
            self.emailStore = emailStore
            self.artifactIndex = artifactIndex

            // Initialize v4.1 standing access stores
            let policyStore = PolicyStore(db: connection)
            let workBlockStore = WorkBlockStore(db: connection)
            policy.configure(policyStore: policyStore, workBlockStore: workBlockStore, grantStore: grantStore)

            // Initialize email sync engine
            let syncEngine = EmailSyncEngine(emailStore: emailStore)
            self.syncEngine = syncEngine

            // Re-create sub-models with actual stores
            reinjectStores(
                auditStore: auditStore,
                contentStore: contentStore,
                snapshotStore: snapshotStore,
                grantStore: grantStore,
                emailStore: emailStore,
                artifactIndex: artifactIndex,
                db: connection,
                syncEngine: syncEngine
            )

            await refresh()

            // Background maintenance
            _ = try? await snapshotStore.pruneByAge(days: 30)
            _ = try? await snapshotStore.pruneByFileCount(maxPerFile: 50)
            _ = try? await contentStore.garbageCollect()

            // Clean up materialization directories from ended or crashed sessions
            let gs = grantStore
            Task.detached { await SessionModel.cleanupOrphanedMaterializations(grantStore: gs) }

            // Slow background timer for stale grant expiration only (60s instead of 5s)
            pollTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
                Task { [weak self] in await self?.expireStaleGrants() }
            }
        } catch {
            logger.error("Failed to init stores: \(error.localizedDescription)")
        }
    }

    /// Inject kit stores into sub-models after async init completes.
    private func reinjectStores(
        auditStore: AuditStore,
        contentStore: ContentStore,
        snapshotStore: SnapshotStore,
        grantStore: GrantStore,
        emailStore: EmailStore,
        artifactIndex: ArtifactIndex,
        db: DatabaseConnection,
        syncEngine: EmailSyncEngine
    ) {
        session.configure(
            grantStore: grantStore,
            snapshotStore: snapshotStore,
            contentStore: contentStore,
            auditStore: auditStore,
            emailStore: emailStore,
            artifactIndex: artifactIndex
        )
        history.configure(
            auditStore: auditStore,
            snapshotStore: snapshotStore,
            contentStore: contentStore,
            artifactIndex: artifactIndex
        )
        storage.configure(snapshotStore: snapshotStore, contentStore: contentStore, db: db)
        emailAccounts.configure(emailStore: emailStore, syncEngine: syncEngine)

        // Register existing email accounts with the sync engine
        Task { await emailAccounts.registerAllAccounts() }
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
            Task { @MainActor in self?.debouncedRefresh() }
        }
        notificationObservers = [connected, disconnected, denied, dataChanged]
    }

    /// Check and expire stale grants (called from 60s background timer).
    private func expireStaleGrants() async {
        guard let grantStore else { return }
        _ = try? await grantStore.expireStaleGrants()
    }

    /// Debounced refresh — coalesces rapid dataChanged notifications into a single refresh.
    /// Prevents redundant DB queries when multiple writes happen in quick succession.
    private var refreshDebounceTask: Task<Void, Never>?
    private func debouncedRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await refresh()
        }
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
        do {
            history.activityEntries = try await auditStore.recentEntries(limit: 100)
            lastError = nil
        } catch {
            logger.error("Failed to load activity: \(error.localizedDescription)")
            lastError = "Unable to load activity data"
            history.activityEntries = []
        }
        if !isConnected {
            if let recent = history.activityEntries.first(where: { $0.action == "mcp_connection" }),
               let ts = ISO8601DateFormatter().date(from: recent.timestamp) {
                isConnected = Date().timeIntervalSince(ts) < 300
                connectedAgent = recent.agent ?? "Claude"
            }
        }
        if let expired = try? await grantStore?.expireStaleGrants(), expired > 0 {
            logger.info("Expired \(expired) stale grant(s)")
        }
        await loadSources()
        await session.refreshGrantState()
    }

    // MARK: - Sources

    func addSource(path: String) {
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        Task {
            do {
                if try await grantStore?.source(byPath: path) == nil {
                    try await grantStore?.addSource(displayName: folderName, rootPath: path)
                }
                try? await auditStore?.log(action: .sourceAdded, filePath: path, metadata: ["folder": folderName])
            } catch {
                logger.error("Failed to register source \(folderName): \(error.localizedDescription)")
                lastError = "Failed to add \(folderName)"
            }
            await loadSources()
        }
    }

    func removeSource(path: String) {
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        Task {
            do {
                if let source = try await grantStore?.source(byPath: path) {
                    try await grantStore?.removeSource(sourceID: source.sourceID)
                }
                try? await auditStore?.log(action: .sourceRemoved, filePath: path, metadata: ["folder": folderName])
            } catch {
                logger.error("Failed to remove source \(folderName): \(error.localizedDescription)")
                lastError = "Failed to remove \(folderName)"
            }
            await loadSources()
            await refresh()
        }
    }

    func pauseSource(sourceID: String) async {
        do { try await grantStore?.pauseSource(sourceID: sourceID) }
        catch { logger.error("Failed to pause source: \(error.localizedDescription)"); lastError = "Failed to pause source" }
        await loadSources()
        await refresh()
    }

    func resumeSource(sourceID: String) async {
        do { try await grantStore?.resumeSource(sourceID: sourceID) }
        catch { logger.error("Failed to resume source: \(error.localizedDescription)"); lastError = "Failed to resume source" }
        await loadSources()
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

    func removeSources(paths: Set<String>) {
        for path in paths { removeSource(path: path) }
    }

    func loadSources() async {
        do { sources = try await grantStore?.allSources() ?? [] }
        catch { logger.error("Failed to load sources: \(error.localizedDescription)"); sources = [] }
    }

    // MARK: - File Enumeration

    /// Enumerate files from active source original paths. Works without an active session.
    /// File walking runs off the main actor to avoid UI hitches.
    func enumerateSourceFiles() async -> [SourceFile] {
        let activeSrcs = sources.filter { $0.isAccessible && !$0.isRemoved }
        return await Task.detached(priority: .userInitiated) {
            Self.walkSourceFiles(sources: activeSrcs)
        }.value
    }

    /// Pure file-system walk — no actor isolation, no UI thread.
    private nonisolated static func walkSourceFiles(sources: [SourceRecord]) -> [SourceFile] {
        let fm = FileManager.default
        var result: [SourceFile] = []

        for source in sources {
            let root = URL(fileURLWithPath: source.originalRootPath)
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let basePath = root.path + "/"
            while let url = enumerator.nextObject() as? URL {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }
                let path = url.path
                guard path.hasPrefix(basePath) else { continue }
                let relativePath = String(path.dropFirst(basePath.count))

                // Skip noise
                let first = relativePath.split(separator: "/").first.map(String.init) ?? relativePath
                let skip = [".git", "node_modules", ".build", "Build", "DerivedData",
                            "Pods", "__pycache__", ".DS_Store"]
                if skip.contains(first) {
                    if url.hasDirectoryPath { enumerator.skipDescendants() }
                    continue
                }

                result.append(SourceFile(
                    name: url.lastPathComponent,
                    path: path,
                    relativePath: relativePath,
                    sourceName: source.displayName,
                    sourceID: source.sourceID,
                    fileExtension: url.pathExtension.lowercased(),
                    sizeBytes: values.fileSize ?? 0,
                    modifiedDate: values.contentModificationDate ?? Date.distantPast,
                    isGrantedToClaude: true
                ))
            }
        }
        return result
    }

    /// Enumerate files from grant materialization mounts. Only works during active session.
    /// File walking runs off the main actor.
    func enumerateAllFiles() async -> [SourceFile] {
        let mounts = session.currentGrantMounts()
        return await Task.detached(priority: .userInitiated) { [session] in
            let fm = FileManager.default
            var result: [SourceFile] = []

            for mount in mounts {
                let root = URL(fileURLWithPath: mount.mountPath)
                guard let enumerator = fm.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                while let url = enumerator.nextObject() as? URL {
                    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                          values.isRegularFile == true else { continue }
                    let relativePath = await session.canonicalPath(for: url, base: root, mountName: mount.mountName)
                    guard !relativePath.hasPrefix("\(mount.mountName)/.manifold-") else { continue }
                    result.append(SourceFile(
                        name: url.lastPathComponent,
                        path: url.path,
                        relativePath: relativePath,
                        sourceName: mount.mountName,
                        sourceID: mount.sourceID,
                        fileExtension: url.pathExtension.lowercased(),
                        sizeBytes: values.fileSize ?? 0,
                        modifiedDate: values.contentModificationDate ?? Date.distantPast,
                        isGrantedToClaude: true
                    ))
                }
            }
            return result
        }.value
    }

    /// Search file contents across all sources.
    func searchFileContents(query: String, includeArchived: Bool = false) -> [SearchResult] {
        let fm = FileManager.default
        var results: [SearchResult] = []
        let mounts = session.currentGrantMounts()

        for mount in mounts {
            let root = URL(fileURLWithPath: mount.mountPath)
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true,
                      let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let relativePath = session.canonicalPath(for: url, base: root, mountName: mount.mountName)
                guard !relativePath.hasPrefix("\(mount.mountName)/.manifold-") else { continue }

                let lines = content.components(separatedBy: "\n")
                let matches = Array(lines.enumerated().lazy
                    .filter { $0.element.localizedCaseInsensitiveContains(query) }
                    .prefix(5)
                    .map { SearchMatch(lineNumber: $0.offset + 1, lineText: String($0.element.prefix(200))) })

                if !matches.isEmpty {
                    results.append(SearchResult(
                        fileName: url.lastPathComponent,
                        filePath: url.path,
                        sourceName: mount.mountName,
                        isGranted: true,
                        canonicalPath: relativePath,
                        matches: Array(matches)
                    ))
                }
                if results.count >= 100 { return results }
            }
        }
        return results
    }

    // MARK: - Delegated Session Operations

    func startSession(targetApp: TargetApp = .cowork) async {
        if session.isPreviewing {
            // User confirmed the preview, proceed with actual materialization
            session.preview = nil
            session.previewError = nil
            await session.startSession(
                targetApp: targetApp,
                onError: { [weak self] msg in self?.lastError = msg }
            )
        } else {
            // Clear any prior error, show preview
            session.previewError = nil
            await session.computePreview(targetApp: targetApp)
        }
        await refresh()
    }

    func endSession() async {
        await session.endSession(
            onError: { [weak self] msg in self?.lastError = msg },
            onConflict: { [weak self] count in self?.lastError = "\(count) conflict(s) during promote. Check activity for details." }
        )
        await refresh()
        session.lastCompletedSession = history.sessions.first(where: { $0.id == session.activeGrant?.grantID })
    }

    // MARK: - Delegated Restore

    func restoreFile(snapshotID: Int, filePath: String) async -> Bool {
        let result = await session.restoreFile(snapshotID: snapshotID, filePath: filePath)
        if result { await refresh() }
        return result
    }

    func revertFile(event: SessionEvent) async -> RevertResult {
        let result = await history.revertFile(
            event: event,
            activeGrant: session.activeGrant,
            resolveGrantFilePath: { [weak self] path in self?.session.resolveGrantFilePath(path) }
        )
        if case .success = result { await refresh() }
        return result
    }

    func forceRevertFile(event: SessionEvent) async -> RevertResult {
        let result = await history.forceRevertFile(
            event: event,
            activeGrant: session.activeGrant,
            resolveGrantFilePath: { [weak self] path in self?.session.resolveGrantFilePath(path) }
        )
        if case .success = result { await refresh() }
        return result
    }

    // MARK: - Full Load

    func loadSummary() async {
        await loadSources()
        await session.refreshGrantState()
        await storage.loadStorageStats()
        await storage.loadTrackedFiles()
        await history.loadSessions()
    }

    // MARK: - Convenience Accessors (backward compat)

    var activeGrant: GrantRecord? { session.activeGrant }
    var activeGrantSources: [GrantSourceRecord] { session.activeGrantSources }
    var hasActiveSession: Bool { session.hasActiveSession }
    var activityEntries: [AuditEntry] { history.activityEntries }
    var sessions: [Session] { history.sessions }
    var selectedSession: Session? {
        get { history.selectedSession }
        set { history.selectedSession = newValue }
    }
    var sessionEvents: [SessionEvent] { history.sessionEvents }
    var showSessionGrouping: Bool {
        get { history.showSessionGrouping }
        set { history.showSessionGrouping = newValue }
    }
    var allTrackedFiles: [String] { storage.allTrackedFiles }
    var storageUsed: Int64 { storage.storageUsed }
    var blobCount: Int { storage.blobCount }
    var mcpInstalled: Bool { integrationHealth.claude.mcpConfigured == .installed }
    var installError: String? {
        get { integrationHealth.claude.errorDetail }
        set { integrationHealth.claude.errorDetail = newValue }
    }
    var claudeDesktopConfigured: Bool { integrationHealth.claude.mcpConfigured == .installed }
    var codexConfigured: Bool { integrationHealth.codex.mcpAdded == .installed }
    var launchAtLogin: Bool {
        get { setup.launchAtLogin }
        set { setup.launchAtLogin = newValue }
    }
    var notifyOnSessionEnd: Bool {
        get { setup.notifyOnSessionEnd }
        set { setup.notifyOnSessionEnd = newValue }
    }
    var notifyOnAccessDenied: Bool {
        get { setup.notifyOnAccessDenied }
        set { setup.notifyOnAccessDenied = newValue }
    }
    var hasCompletedOnboarding: Bool {
        get { setup.hasCompletedOnboarding }
        set { setup.hasCompletedOnboarding = newValue }
    }
    var lastCompletedSession: Session? {
        get { session.lastCompletedSession }
        set { session.lastCompletedSession = newValue }
    }
    var selectedPreset: DomainPreset? {
        get { session.selectedPreset }
        set { session.selectedPreset = newValue }
    }

    // MARK: - Delegated Methods (backward compat)

    func fileHistory(filePath: String) async -> [SnapshotRecord] { await storage.fileHistory(filePath: filePath) }
    func snapshotData(hash: String) async -> Data? { await storage.snapshotData(hash: hash) }
    func runGarbageCollection() async -> Int { await storage.runGarbageCollection() }
    func pruneOldRuns() async -> Int { await storage.pruneOldRuns() }
    func runIntegrityCheck() async -> Bool { await storage.runIntegrityCheck() }
    func loadTrackedFiles() async { await storage.loadTrackedFiles() }
    func loadStorageStats() async { await storage.loadStorageStats() }

    func checkMCPInstalled() { Task { await integrationHealth.checkClaude() } }
    func checkAgentConfigs() { Task { await integrationHealth.checkAll() } }
    func installMCP() {
        do {
            let destPath = Self.mcpBinaryPath
            let destURL = URL(fileURLWithPath: destPath)
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let bundled = Bundle.main.url(forResource: "manifold-mcp", withExtension: nil) {
                if FileManager.default.fileExists(atPath: destPath) { try FileManager.default.removeItem(at: destURL) }
                try FileManager.default.copyItem(at: bundled, to: destURL)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)
            }
            try ConfigWriter(binaryPath: destPath).installAll()
            Task { await integrationHealth.checkAll(force: true) }
        } catch {
            integrationHealth.claude.errorDetail = error.localizedDescription
        }
    }

    func loadSessions() async { await history.loadSessions() }
    func loadSessionEvents(sessionID: String) async { await history.loadSessionEvents(sessionID: sessionID) }
    func selectSession(_ session: Session?) async { await history.selectSession(session) }
    func sessionSummary(session: Session, events: [SessionEvent]) -> String { history.sessionSummary(session: session, events: events) }

    func refreshGrantState() async { await session.refreshGrantState() }

    // MARK: - Static

    static var storeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Manifold/store")
    }
    static var mcpBinaryPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Manifold/bin/manifold-mcp").path
    }
}
