import SwiftUI
import Foundation
import UserNotifications
import CommonCrypto
import os
import ManifoldKit

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "store")

// MARK: - Navigation

enum SidebarItem: Hashable {
    case dashboard
    case files
    case activity
    case email
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

    // Sessions
    var sessions: [Session] = []
    var selectedSession: Session?
    var sessionEvents: [SessionEvent] = []
    var showSessionGrouping: Bool = true

    // Sources
    var approvedSources: [String] = []
    // workspaces removed — source management now uses GrantStore.sources

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

    // Errors
    var lastError: String?

    // Setup
    var mcpInstalled = false
    var installError: String?
    var claudeDesktopConfigured = false
    var codexConfigured = false

    // Onboarding
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "manifold.onboarding.completed") }
    }

    // Grant lifecycle
    var activeGrant: GrantRecord?
    var activeGrantSources: [GrantSourceRecord] = []
    var sources: [SourceRecord] = []

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

            // Run pending schema migrations before initializing stores
            let migrator = try DatabaseMigrator(db: connection)
            try migrator.migrate()

            self.auditStore = try AuditStore(db: connection)
            self.snapshotStore = try SnapshotStore(db: connection, contentStore: contentStore)
            self.emailFilter = try EmailFilter(db: connection)
            self.leaseManager = try WorkspaceLeaseManager(db: connection, snapshotStore: self.snapshotStore!)
            self.grantStore = GrantStore(db: connection)
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
        do {
            activityEntries = try await auditStore.recentEntries(limit: 100)
            lastError = nil
        } catch {
            logger.error("Failed to load activity: \(error.localizedDescription)")
            lastError = "Unable to load activity data"
            activityEntries = []
        }
        if !isConnected {
            if let recent = activityEntries.first(where: { $0.action == "mcp_connection" }),
               let ts = ISO8601DateFormatter().date(from: recent.timestamp) {
                isConnected = Date().timeIntervalSince(ts) < 300
                connectedAgent = recent.agent ?? "Claude"
            }
        }
        await loadSources()
    }

    // MARK: - Sources

    func addSource(path: String) {
        guard !approvedSources.contains(path) else { return }
        approvedSources.append(path)
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
        approvedSources.removeAll { $0 == path }
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
        do {
            try await grantStore?.pauseSource(sourceID: sourceID)
        } catch {
            logger.error("Failed to pause source: \(error.localizedDescription)")
            lastError = "Failed to pause source"
        }
        await loadSources()
        await refresh()
    }

    func resumeSource(sourceID: String) async {
        do {
            try await grantStore?.resumeSource(sourceID: sourceID)
        } catch {
            logger.error("Failed to resume source: \(error.localizedDescription)")
            lastError = "Failed to resume source"
        }
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

    /// Remove multiple sources at once.
    func removeSources(paths: Set<String>) {
        for path in paths { removeSource(path: path) }
    }

    /// Enumerate all files across all active sources. Returns flat list with metadata.
    func enumerateAllFiles() -> [SourceFile] {
        let fm = FileManager.default
        var result: [SourceFile] = []
        let activeSources = sources.filter(\.isAccessible)

        for source in activeSources {
            let root = URL(fileURLWithPath: source.originalRootPath)
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }
                let relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")
                result.append(SourceFile(
                    name: url.lastPathComponent,
                    path: url.path,
                    relativePath: relativePath,
                    sourceName: source.displayName,
                    sourceID: source.sourceID,
                    fileExtension: url.pathExtension.lowercased(),
                    sizeBytes: values.fileSize ?? 0,
                    modifiedDate: values.contentModificationDate ?? Date.distantPast,
                    isGrantedToClaude: source.isAccessible
                ))
            }
        }
        return result
    }

    /// Search file contents across all sources.
    func searchFileContents(query: String, includeArchived: Bool = false) -> [SearchResult] {
        let fm = FileManager.default
        let relevantSources = includeArchived ? sources : sources.filter(\.isAccessible)
        var results: [SearchResult] = []

        for source in relevantSources {
            let root = URL(fileURLWithPath: source.originalRootPath)
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true,
                      let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

                let lines = content.components(separatedBy: "\n")
                let matches = lines.enumerated()
                    .filter { $0.element.localizedCaseInsensitiveContains(query) }
                    .prefix(5)
                    .map { SearchMatch(lineNumber: $0.offset + 1, lineText: String($0.element.prefix(200))) }

                if !matches.isEmpty {
                    results.append(SearchResult(
                        fileName: url.lastPathComponent,
                        filePath: url.path,
                        sourceName: source.displayName,
                        isGranted: source.isAccessible,
                        matches: Array(matches)
                    ))
                }
                if results.count >= 100 { return results }
            }
        }
        return results
    }

    func loadSources() async {
        do {
            sources = try await grantStore?.activeSources() ?? []
            approvedSources = sources.filter(\.isAccessible).map(\.originalRootPath)
        } catch {
            logger.error("Failed to load sources: \(error.localizedDescription)")
            sources = []
        }
    }

    // MARK: - Grant Lifecycle

    /// Start a new session: creates a grant, materializes sources, sets baseline hashes.
    func startSession(targetApp: TargetApp = .cowork) async {
        guard let grantStore else { return }
        do {
            let activeSources = try await grantStore.activeSources()
            guard !activeSources.isEmpty else {
                lastError = "No active sources. Add a folder first."
                return
            }

            let sourceIDs = activeSources.map(\.sourceID)
            let matRoot = Self.materializationRoot(grantID: "pending")
            let grant = try await grantStore.startGrant(
                targetApp: targetApp,
                profileID: "default",
                sourceIDs: sourceIDs,
                materializationRoot: Self.materializationRoot(grantID: "").path
            )

            // Update materialization root with actual grant ID
            let actualRoot = Self.materializationRoot(grantID: grant.grantID)
            try await grantStore.updateMaterializationRoot(grantID: grant.grantID, root: actualRoot.path)

            // Materialize
            let grantSources = try await grantStore.grantSources(grantID: grant.grantID)
            let mountInputs = grantSources.compactMap { gs -> (source: SourceRecord, mountName: String)? in
                guard let source = activeSources.first(where: { $0.sourceID == gs.sourceID }) else { return nil }
                return (source: source, mountName: gs.mountName)
            }

            let results = try MaterializationEngine.materialize(
                grantID: grant.grantID,
                sources: mountInputs,
                materializationRoot: actualRoot.path
            )

            // Store baseline hashes
            for result in results {
                try await grantStore.setBaselineHash(
                    grantID: grant.grantID,
                    sourceID: result.sourceID,
                    hash: result.manifestHash
                )
            }

            // Update local state
            activeGrant = try await grantStore.grant(id: grant.grantID)
            activeGrantSources = grantSources
            try? await auditStore?.log(action: .runStart, agent: targetApp.rawValue, metadata: ["grant_id": grant.grantID])
            logger.info("Session started: \(grant.grantID) with \(results.count) sources")
        } catch {
            logger.error("Failed to start session: \(error.localizedDescription)")
            lastError = "Failed to start session: \(error.localizedDescription)"
        }
        await refresh()
    }

    /// End the current session: promotes changes, ends grant.
    func endSession() async {
        guard let grantStore, let grant = activeGrant else { return }
        do {
            // Promote changes back to originals
            let grantSources = try await grantStore.grantSources(grantID: grant.grantID)
            let activeSrcs = try await grantStore.activeSources() + (try await grantStore.allSources())
            let matRoot = URL(fileURLWithPath: grant.materializationRoot)

            for gs in grantSources {
                guard let source = activeSrcs.first(where: { $0.sourceID == gs.sourceID }) else { continue }
                let mountURL = matRoot.appendingPathComponent(gs.mountName)
                let originalURL = URL(fileURLWithPath: source.originalRootPath)

                guard FileManager.default.fileExists(atPath: mountURL.path) else { continue }

                let summary = try PromoteEngine.promote(
                    sourceID: gs.sourceID,
                    mountName: gs.mountName,
                    mountURL: mountURL,
                    originalURL: originalURL
                )

                // Record promotions
                for file in summary.applied + summary.newFiles {
                    try await grantStore.recordPromotion(
                        grantID: grant.grantID, sourceID: gs.sourceID,
                        relativePath: file.relativePath, result: file.result,
                        originalBeforeHash: file.originalBeforeHash,
                        promotedHash: file.promotedHash
                    )
                }
                for file in summary.conflicts {
                    try await grantStore.recordPromotion(
                        grantID: grant.grantID, sourceID: gs.sourceID,
                        relativePath: file.relativePath, result: .conflict,
                        originalBeforeHash: file.originalBeforeHash,
                        promotedHash: file.promotedHash,
                        conflictReason: file.conflictReason
                    )
                }

                if !summary.conflicts.isEmpty {
                    lastError = "\(summary.conflicts.count) conflict(s) during promote. Check activity for details."
                }
            }

            // Auto-generate session summary
            try? await generateSessionSummary(grantID: grant.grantID)

            try await grantStore.endGrant(grantID: grant.grantID)
            try? await auditStore?.log(action: .runEnd, metadata: ["grant_id": grant.grantID])
            activeGrant = nil
            activeGrantSources = []
            logger.info("Session ended: \(grant.grantID)")
        } catch {
            logger.error("Failed to end session: \(error.localizedDescription)")
            lastError = "Failed to end session: \(error.localizedDescription)"
        }
        await refresh()
    }

    /// Refresh grant state from database.
    func refreshGrantState() async {
        guard let grantStore else { return }
        do {
            activeGrant = try await grantStore.activeGrant(targetApp: .cowork, profileID: "default")
            if let grant = activeGrant {
                activeGrantSources = try await grantStore.grantSources(grantID: grant.grantID)
            } else {
                activeGrantSources = []
            }
        } catch {
            logger.error("Failed to refresh grant state: \(error.localizedDescription)")
        }
    }

    var hasActiveSession: Bool { activeGrant?.isActive == true }

    /// Generate and store a Markdown session summary from grant promotions.
    private func generateSessionSummary(grantID: String) async throws {
        guard let grantStore else { return }
        let grant = try await grantStore.grant(id: grantID)
        let promotions = try await grantStore.promotions(grantID: grantID)
        let grantSources = try await grantStore.grantSources(grantID: grantID)

        let applied = promotions.filter { $0.result == "applied" }
        let conflicts = promotions.filter { $0.result == "conflict" }

        var lines: [String] = []
        lines.append("# Session Summary")
        lines.append("")
        lines.append("- **Grant:** \(grantID.prefix(12))...")
        lines.append("- **Sources:** \(grantSources.map(\.mountName).joined(separator: ", "))")
        if !applied.isEmpty {
            lines.append("")
            lines.append("## Files Modified (\(applied.count))")
            for p in applied { lines.append("- `\(p.relativePath)`") }
        }
        if !conflicts.isEmpty {
            lines.append("")
            lines.append("## Conflicts (\(conflicts.count))")
            for p in conflicts { lines.append("- `\(p.relativePath)` — \(p.conflictReason ?? "original changed")") }
        }
        if promotions.isEmpty {
            lines.append("\n_No file changes recorded._")
        }

        let now = ISO8601DateFormatter().string(from: Date())
        try await grantStore.saveSummary(
            grantID: grantID,
            targetApp: TargetApp(rawValue: grant?.targetApp ?? "cowork") ?? .cowork,
            startedAt: grant?.startedAt ?? now,
            endedAt: grant?.endedAt ?? now,
            markdown: lines.joined(separator: "\n")
        )
    }

    static func materializationRoot(grantID: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Manifold/materializations/\(grantID)/workspace")
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
    func loadEmailRules() async {
        do { emailRules = try await emailFilter?.globalRules() ?? [] }
        catch { logger.error("Failed to load email rules: \(error.localizedDescription)"); emailRules = [] }
    }
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

    func loadTrackedFiles() async {
        do { allTrackedFiles = try await snapshotStore?.allTrackedFiles() ?? [] }
        catch { logger.error("Failed to load tracked files: \(error.localizedDescription)"); allTrackedFiles = [] }
    }
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

    // MARK: - Sessions

    func loadSessions() async {
        do {
            sessions = try await auditStore?.recentSessions(limit: 20) ?? []
        } catch {
            logger.error("Failed to load sessions: \(error.localizedDescription)")
            lastError = "Unable to load session history"
            sessions = []
        }
    }

    func loadSessionEvents(sessionID: String) async {
        do {
            sessionEvents = try await auditStore?.sessionEvents(sessionID: sessionID) ?? []
        } catch {
            logger.error("Failed to load session events: \(error.localizedDescription)")
            sessionEvents = []
        }
    }

    func selectSession(_ session: Session?) async {
        selectedSession = session
        if let session {
            await loadSessionEvents(sessionID: session.id)
        } else {
            sessionEvents = []
        }
    }

    /// Revert a file to the state before a specific write event.
    func revertFile(event: SessionEvent) async -> RevertResult {
        guard let beforeHash = event.beforeHash else { return .blobPruned }
        guard let filePath = event.filePath else { return .error("No file path") }

        // 1. Check blob exists
        guard let blobData = try? await contentStore?.retrieve(hash: beforeHash) else {
            return .blobPruned
        }

        // 2. Find the full path via sources
        let activeSources = sources.filter(\.isAccessible)
        var fullPath: String?
        for source in activeSources {
            let candidate = URL(fileURLWithPath: source.originalRootPath).appendingPathComponent(filePath).path
            if FileManager.default.fileExists(atPath: candidate) {
                fullPath = candidate
                break
            }
            if fullPath == nil { fullPath = candidate }
        }
        guard let targetPath = fullPath else { return .error("No sources configured") }

        // 3. Check content drift
        if FileManager.default.fileExists(atPath: targetPath) {
            if let afterHash = event.afterHash,
               let currentData = try? Data(contentsOf: URL(fileURLWithPath: targetPath)) {
                let currentHash = currentData.sha256Hex
                if currentHash != afterHash {
                    return .contentDrift
                }
            }
        } else {
            // File was deleted — we'll recreate it
        }

        // 4. Write the reverted content
        do {
            let targetURL = URL(fileURLWithPath: targetPath)
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try blobData.write(to: targetURL, options: .atomic)

            // 5. Log the revert
            try? await auditStore?.log(action: .restore, filePath: filePath, metadata: ["reverted_from": event.afterHash ?? "unknown"])

            await refresh()
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Force revert even when content has drifted.
    func forceRevertFile(event: SessionEvent) async -> RevertResult {
        guard let beforeHash = event.beforeHash, let filePath = event.filePath else { return .blobPruned }
        guard let blobData = try? await contentStore?.retrieve(hash: beforeHash) else { return .blobPruned }

        let activeSources = sources.filter(\.isAccessible)
        guard let source = activeSources.first else { return .error("No sources configured") }
        let targetPath = URL(fileURLWithPath: source.originalRootPath).appendingPathComponent(filePath).path

        do {
            let targetURL = URL(fileURLWithPath: targetPath)
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try blobData.write(to: targetURL, options: .atomic)
            try? await auditStore?.log(action: .restore, filePath: filePath, metadata: ["reverted_from": event.afterHash ?? "unknown", "forced": "true"])
            await refresh()
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Generate a Markdown summary of a session.
    func sessionSummary(session: Session, events: [SessionEvent]) -> String {
        let formatter = ISO8601DateFormatter()
        let startDate = formatter.date(from: session.startTime)
        let endDate = formatter.date(from: session.endTime)

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .medium
        timeFormatter.timeStyle = .short

        let startStr = startDate.map { timeFormatter.string(from: $0) } ?? session.startTime
        let duration: String
        if let s = startDate, let e = endDate {
            let mins = Int(e.timeIntervalSince(s) / 60)
            duration = mins < 1 ? "< 1 minute" : "\(mins) minutes"
        } else {
            duration = "unknown"
        }

        let eventTimeFormatter = DateFormatter()
        eventTimeFormatter.timeStyle = .short

        var lines = [
            "# Session: \(session.agent) — \(startStr)",
            "Duration: \(duration) | \(session.readCount) reads, \(session.writeCount) writes, \(session.searchCount) searches",
            "",
            "## Timeline"
        ]

        for event in events {
            let time = formatter.date(from: event.timestamp).map { eventTimeFormatter.string(from: $0) } ?? event.timestamp
            let path = event.filePath ?? event.action
            let detail: String
            switch event.action {
            case "file_read": detail = "Read \(path)"
            case "file_modified": detail = "Modified \(path)"
            case "file_created": detail = "Created \(path)"
            case "tool_call": detail = "Tool call: \(path)"
            default: detail = "\(event.action) \(path)"
            }
            lines.append("- \(time) — \(detail)")
        }

        return lines.joined(separator: "\n")
    }

    func loadSummary() async {
        await loadSources(); await refreshGrantState()
        await loadStorageStats(); await loadTrackedFiles(); await reclassifyEmails()
        await loadSessions()
    }

    static func storeURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Manifold/store")
    }
    static func mcpBinaryPath() -> String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Manifold/bin/manifold-mcp").path
    }
}

// MARK: - File Browser Types

struct SourceFile: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let path: String
    let relativePath: String
    let sourceName: String
    let sourceID: String
    let fileExtension: String
    let sizeBytes: Int
    let modifiedDate: Date
    let isGrantedToClaude: Bool
}

struct SearchResult: Identifiable, Sendable {
    let id = UUID()
    let fileName: String
    let filePath: String
    let sourceName: String
    let isGranted: Bool
    let matches: [SearchMatch]
}

struct SearchMatch: Identifiable, Sendable {
    let id = UUID()
    let lineNumber: Int
    let lineText: String
}

// MARK: - Revert

enum RevertResult {
    case success
    case blobPruned
    case contentDrift
    case error(String)
}

extension Data {
    var sha256Hex: String {
        let hash = withUnsafeBytes { bytes -> [UInt8] in
            var hash = [UInt8](repeating: 0, count: 32)
            CC_SHA256(bytes.baseAddress, CC_LONG(count), &hash)
            return hash
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
