import SwiftUI
import Foundation
import UserNotifications
import CommonCrypto
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "store")

// MARK: - Navigation

enum SidebarItem: String, Hashable, CaseIterable {
    case home
    case files
    case emails
    case history
    case sources
}

// MARK: - Store

@Observable
@MainActor
class ManifoldStore {
    // Navigation
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
    let email: EmailModel
    let history: HistoryModel
    let storage: StorageModel
    let setup: SetupModel

    var menuBarIcon: String { isConnected ? "shield.checkered.fill" : "shield.checkered" }

    // Internal
    private var auditStore: AuditStore?
    private var emailFilter: EmailFilter?
    private(set) var snapshotStore: SnapshotStore?
    private(set) var contentStore: ContentStore?
    private var leaseManager: WorkspaceLeaseManager?
    private(set) var grantStore: GrantStore?
    private var db: DatabaseConnection?
    private var pollTimer: Timer?
    private var notificationObservers: [NSObjectProtocol] = []

    // MARK: - Init

    init() {
        session = SessionModel()
        email = EmailModel()
        history = HistoryModel()
        storage = StorageModel()
        setup = SetupModel()

        Task {
            await initStores()
            setupNotificationObservers()
            requestNotificationPermission()
        }
    }

    private func initStores() async {
        do {
            let storeURL = Self.storeURL
            try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
            let contentStore = try ContentStore(rootURL: storeURL)
            self.contentStore = contentStore
            let connection = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
            self.db = connection

            let migrator = try DatabaseMigrator(db: connection)
            try migrator.migrate()

            let auditStore = try AuditStore(db: connection)
            let snapshotStore = try SnapshotStore(db: connection, contentStore: contentStore)
            let emailFilter = try EmailFilter(db: connection)
            let leaseManager = try WorkspaceLeaseManager(db: connection, snapshotStore: snapshotStore)
            let grantStore = GrantStore(db: connection)

            self.auditStore = auditStore
            self.snapshotStore = snapshotStore
            self.emailFilter = emailFilter
            self.leaseManager = leaseManager
            self.grantStore = grantStore

            // Re-create sub-models with actual stores
            reinjectStores(
                auditStore: auditStore,
                contentStore: contentStore,
                snapshotStore: snapshotStore,
                emailFilter: emailFilter,
                grantStore: grantStore,
                db: connection
            )

            setup.checkMCPInstalled()
            setup.checkAgentConfigs()
            await refresh()

            // Background maintenance
            _ = try? await snapshotStore.pruneByAge(days: 30)
            _ = try? await snapshotStore.pruneByFileCount(maxPerFile: 50)
            _ = try? await contentStore.garbageCollect()

            pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refresh() }
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
        emailFilter: EmailFilter,
        grantStore: GrantStore,
        db: DatabaseConnection
    ) {
        session.configure(grantStore: grantStore, snapshotStore: snapshotStore, contentStore: contentStore, auditStore: auditStore, emailFilter: emailFilter)
        email.configure(emailFilter: emailFilter, grantStore: grantStore, contentStore: contentStore)
        history.configure(auditStore: auditStore, snapshotStore: snapshotStore, contentStore: contentStore)
        storage.configure(snapshotStore: snapshotStore, contentStore: contentStore, db: db)
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
    func enumerateSourceFiles() async -> [SourceFile] {
        let fm = FileManager.default
        var result: [SourceFile] = []
        let activeSrcs = sources.filter { $0.isAccessible && !$0.isRemoved }
        let tracked = Set(storage.allTrackedFiles)

        for source in activeSrcs {
            let root = URL(fileURLWithPath: source.originalRootPath)
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }
                let path = url.path
                let hasVersions = tracked.contains(path)
                var file = SourceFile(
                    name: url.lastPathComponent,
                    path: path,
                    relativePath: path.replacingOccurrences(of: source.originalRootPath + "/", with: ""),
                    sourceName: source.displayName,
                    sourceID: source.sourceID,
                    fileExtension: url.pathExtension.lowercased(),
                    sizeBytes: values.fileSize ?? 0,
                    modifiedDate: values.contentModificationDate ?? Date.distantPast,
                    isGrantedToClaude: true
                )
                if hasVersions {
                    let fileHist = await storage.fileHistory(filePath: path)
                    file.versionCount = fileHist.count
                    file.hasAIActivity = fileHist.contains { $0.source == "agent" || $0.source == "mcp" }
                }
                result.append(file)
            }
        }
        return result
    }

    /// Enumerate files from grant materialization mounts. Only works during active session.
    func enumerateAllFiles() -> [SourceFile] {
        let fm = FileManager.default
        var result: [SourceFile] = []
        let mounts = session.currentGrantMounts()

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
                let relativePath = session.canonicalPath(for: url, base: root, mountName: mount.mountName)
                guard !relativePath.hasPrefix("\(mount.mountName)/_emails/") else { continue }
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
                guard !relativePath.hasPrefix("\(mount.mountName)/_emails/") else { continue }
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
        await session.startSession(
            targetApp: targetApp,
            selectedEmailIDs: email.selectedEmailIDsForNextSession,
            onError: { [weak self] msg in self?.lastError = msg }
        )
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
        await email.reclassifyEmails()
        await email.loadCachedEmails()
        await email.loadMailboxes()
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
    var cachedEmails: [CachedEmail] { email.cachedEmails }
    var emailRules: [EmailRule] { email.emailRules }
    var emailClassification: EmailClassificationResult? { email.emailClassification }
    var selectedEmailIDsForNextSession: Set<String> {
        get { email.selectedEmailIDsForNextSession }
        set { email.selectedEmailIDsForNextSession = newValue }
    }
    var allTrackedFiles: [String] { storage.allTrackedFiles }
    var storageUsed: Int64 { storage.storageUsed }
    var blobCount: Int { storage.blobCount }
    var mcpInstalled: Bool { setup.mcpInstalled }
    var installError: String? {
        get { setup.installError }
        set { setup.installError = newValue }
    }
    var claudeDesktopConfigured: Bool { setup.claudeDesktopConfigured }
    var codexConfigured: Bool { setup.codexConfigured }
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
    var mailAccessStatus: MailAccessStatus? { email.mailAccessStatus }
    var mailboxes: [MailboxInfo] { email.mailboxes }
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

    func checkMCPInstalled() { setup.checkMCPInstalled() }
    func checkAgentConfigs() { setup.checkAgentConfigs() }
    func installMCP() { setup.installMCP() }

    func loadEmailRules() async { await email.loadEmailRules() }
    func addEmailRule(type: RuleType, pattern: String, category: String) async { await email.addEmailRule(type: type, pattern: pattern, category: category) }
    func removeEmailRule(id: Int) async { await email.removeEmailRule(id: id) }
    func overrideEmailToShared(messageID: String) async { await email.overrideEmailToShared(messageID: messageID) }
    func hideEmail(messageID: String) async { await email.hideEmail(messageID: messageID) }
    func reclassifyEmails() async { await email.reclassifyEmails() }
    func loadCachedEmails() async { await email.loadCachedEmails() }
    func toggleEmailSelection(messageID: String) { email.toggleEmailSelection(messageID: messageID) }
    func checkMailAccess() async { await email.checkMailAccess() }
    func loadMailboxes() async { await email.loadMailboxes() }
    func fetchAndCacheEmails(account: String, mailbox: String) async { await email.fetchAndCacheEmails(account: account, mailbox: mailbox) }

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
