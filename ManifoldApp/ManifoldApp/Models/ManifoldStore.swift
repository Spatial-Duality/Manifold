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
    var approvedSources: [String] { sources.filter(\.isAccessible).map(\.originalRootPath) }

    // Emails
    var emailRules: [EmailRule] = []
    var cachedEmails: [CachedEmail] = []
    var emailClassification: EmailClassificationResult?
    var mailAccessStatus: MailAccessStatus?
    var mailboxes: [MailboxInfo] = []
    var selectedEmailIDsForNextSession: Set<String> = []

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
        // Expire stale grants (agents that disconnected without ending session)
        if let expired = try? await grantStore?.expireStaleGrants(), expired > 0 {
            logger.info("Expired \(expired) stale grant(s)")
        }
        await loadSources()
        await refreshGrantState()
    }

    // MARK: - Sources

    func addSource(path: String) {
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        Task {
            do {
                if try await grantStore?.source(byPath: path) == nil {
                    try await grantStore?.addSource(displayName: folderName, rootPath: path)
                }
                do {
                    try await auditStore?.log(action: .sourceAdded, filePath: path, metadata: ["folder": folderName])
                } catch {
                    logger.warning("Failed to log source addition: \(error.localizedDescription)")
                }
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
                do {
                    try await auditStore?.log(action: .sourceRemoved, filePath: path, metadata: ["folder": folderName])
                } catch {
                    logger.warning("Failed to log source removal: \(error.localizedDescription)")
                }
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
        let mounts = currentGrantMounts()

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
                let relativePath = canonicalPath(for: url, base: root, mountName: mount.mountName)
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
        let mounts = currentGrantMounts()

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
                let relativePath = canonicalPath(for: url, base: root, mountName: mount.mountName)
                guard !relativePath.hasPrefix("\(mount.mountName)/_emails/") else { continue }
                guard !relativePath.hasPrefix("\(mount.mountName)/.manifold-") else { continue }

                let lines = content.components(separatedBy: "\n")
                let matches = lines.enumerated()
                    .filter { $0.element.localizedCaseInsensitiveContains(query) }
                    .prefix(5)
                    .map { SearchMatch(lineNumber: $0.offset + 1, lineText: String($0.element.prefix(200))) }

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

    func loadSources() async {
        do {
            sources = try await grantStore?.allSources() ?? []
        } catch {
            logger.error("Failed to load sources: \(error.localizedDescription)")
            sources = []
        }
    }

    // MARK: - Grant Lifecycle

    /// Start a new session: creates a grant, materializes sources, sets baseline hashes.
    func startSession(targetApp: TargetApp = .cowork) async {
        guard let grantStore, let snapshotStore else { return }
        do {
            let activeSources = try await grantStore.activeSources()
            let emailIDs = Array(selectedEmailIDsForNextSession).sorted()
            guard !activeSources.isEmpty || !emailIDs.isEmpty else {
                lastError = "Select at least one folder or shared email before starting a session."
                return
            }

            let sourceIDs = activeSources.map(\.sourceID)
            let grant = try await grantStore.startGrant(
                targetApp: targetApp,
                profileID: "default",
                sourceIDs: sourceIDs,
                emailIDs: emailIDs,
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

                try await baselineSnapshotMount(
                    grantID: grant.grantID,
                    sourceID: result.sourceID,
                    mountName: result.mountName,
                    mountPath: result.mountPath,
                    snapshotStore: snapshotStore
                )
            }

            if !emailIDs.isEmpty {
                let emails = try await grantStore.grantEmailMessages(grantID: grant.grantID)
                let attachments = try await materializeGrantEmails(
                    grantID: grant.grantID,
                    grantRoot: actualRoot,
                    emails: emails
                )
                try await grantStore.attachEmailsToGrant(grantID: grant.grantID, emails: attachments)
            }

            // Update local state
            activeGrant = try await grantStore.grant(id: grant.grantID)
            activeGrantSources = try await grantStore.grantSources(grantID: grant.grantID)
            do {
                try await auditStore?.log(
                    action: .runStart,
                    runID: grant.grantID,
                    agent: targetApp.rawValue,
                    metadata: ["grant_id": grant.grantID, "email_count": "\(emailIDs.count)"],
                    grantID: grant.grantID
                )
            } catch {
                logger.warning("Failed to log session start: \(error.localizedDescription)")
            }
            logger.info("Session started: \(grant.grantID) with \(results.count) sources and \(emailIDs.count) emails")
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
            let activeSrcs = try await grantStore.allSources()
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
                    let canonical = "\(gs.mountName)/\(file.relativePath)"
                    try await grantStore.recordPromotion(
                        grantID: grant.grantID, sourceID: gs.sourceID,
                        relativePath: canonical, result: file.result,
                        originalBeforeHash: file.originalBeforeHash,
                        promotedHash: file.promotedHash
                    )
                    do {
                        try await auditStore?.log(
                            action: .promote,
                            runID: grant.grantID,
                            workspaceID: gs.sourceID,
                            agent: grant.targetApp,
                            filePath: canonical,
                            beforeHash: file.originalBeforeHash,
                            afterHash: file.promotedHash,
                            metadata: ["grant_id": grant.grantID, "mount": gs.mountName, "result": file.result.rawValue],
                            grantID: grant.grantID
                        )
                    } catch {
                        logger.warning("Failed to log promotion for \(canonical): \(error.localizedDescription)")
                    }
                }
                for file in summary.conflicts {
                    let canonical = "\(gs.mountName)/\(file.relativePath)"
                    try await grantStore.recordPromotion(
                        grantID: grant.grantID, sourceID: gs.sourceID,
                        relativePath: canonical, result: .conflict,
                        originalBeforeHash: file.originalBeforeHash,
                        promotedHash: file.promotedHash,
                        conflictReason: file.conflictReason
                    )
                    do {
                        try await auditStore?.log(
                            action: .promote,
                            runID: grant.grantID,
                            workspaceID: gs.sourceID,
                            agent: grant.targetApp,
                            filePath: canonical,
                            beforeHash: file.originalBeforeHash,
                            afterHash: file.promotedHash,
                            metadata: [
                                "grant_id": grant.grantID,
                                "mount": gs.mountName,
                                "result": PromotionResult.conflict.rawValue,
                                "conflict_reason": file.conflictReason ?? "conflict",
                            ],
                            grantID: grant.grantID
                        )
                    } catch {
                        logger.warning("Failed to log conflict for \(canonical): \(error.localizedDescription)")
                    }
                }

                if !summary.conflicts.isEmpty {
                    lastError = "\(summary.conflicts.count) conflict(s) during promote. Check activity for details."
                }
            }

            // Auto-generate session summary
            do {
                try await generateSessionSummary(grantID: grant.grantID)
            } catch {
                logger.warning("Failed to generate session summary: \(error.localizedDescription)")
            }

            try await grantStore.endGrant(grantID: grant.grantID)
            do {
                try await auditStore?.log(action: .runEnd, runID: grant.grantID, metadata: ["grant_id": grant.grantID], grantID: grant.grantID)
            } catch {
                logger.warning("Failed to log session end: \(error.localizedDescription)")
            }
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
        let grantEmails = try await grantStore.grantEmailMessages(grantID: grantID)

        let created = promotions.filter { $0.result == "applied" && $0.originalBeforeHash == nil }
        let applied = promotions.filter { $0.result == "applied" && $0.originalBeforeHash != nil }
        let conflicts = promotions.filter { $0.result == "conflict" }

        var lines: [String] = []
        lines.append("# Session Summary")
        lines.append("")
        lines.append("- **Grant:** \(grantID.prefix(12))...")
        lines.append("- **Sources:** \(grantSources.map(\.mountName).joined(separator: ", "))")
        lines.append("- **Selected Emails:** \(grantEmails.count)")
        if !grantEmails.isEmpty {
            lines.append("")
            lines.append("## Emails")
            for email in grantEmails.prefix(10) {
                lines.append("- `\(email.emailID)` — \(email.subject)")
            }
        }
        if !applied.isEmpty {
            lines.append("")
            lines.append("## Files Modified (\(applied.count))")
            for p in applied { lines.append("- `\(p.relativePath)`") }
        }
        if !created.isEmpty {
            lines.append("")
            lines.append("## Files Created (\(created.count))")
            for p in created { lines.append("- `\(p.relativePath)`") }
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
        guard let emailFilter, let grantStore else { return }
        let emails: [RenderedEmail]
        do { emails = try mailConnector.fetchMessages(account: account, mailbox: mailbox, limit: 100) } catch { return }
        var fetched: [(id: String, email: RenderedEmail)] = []
        for email in emails {
            guard let messageID = try? await emailFilter.cacheEmail(email, account: account, mailbox: mailbox) else { continue }
            var normalized = email
            normalized.messageID = messageID
            fetched.append((messageID, normalized))
        }
        await reclassifyEmails()
        await loadCachedEmails()

        let statusByID = Dictionary(uniqueKeysWithValues: cachedEmails.map { ($0.messageID, $0) })
        for fetchedEmail in fetched {
            let preview = String(fetchedEmail.email.body.prefix(200))
            let contentHash: String?
            if let contentStore {
                contentHash = try? await contentStore.ingest(data: Data(fetchedEmail.email.toMarkdown().utf8))
            } else {
                contentHash = nil
            }
            let cached = statusByID[fetchedEmail.id]
            try? await grantStore.upsertEmailMessage(
                emailID: fetchedEmail.id,
                account: account,
                mailbox: mailbox,
                sender: fetchedEmail.email.from,
                recipients: fetchedEmail.email.to,
                subject: fetchedEmail.email.subject,
                receivedAt: fetchedEmail.email.date,
                preview: preview,
                classificationStatus: cached?.status ?? "pending",
                hiddenReason: cached?.hiddenReason,
                contentHash: contentHash
            )
        }
    }
    func loadEmailRules() async {
        do { emailRules = try await emailFilter?.globalRules() ?? [] }
        catch { logger.error("Failed to load email rules: \(error.localizedDescription)"); emailRules = [] }
    }
    func addEmailRule(type: RuleType, pattern: String, category: String) async {
        do {
            try await emailFilter?.addGlobalRule(type: type, pattern: pattern, category: category)
        } catch {
            logger.warning("Failed to add email rule: \(error.localizedDescription)")
            lastError = "Failed to add email rule"
        }
        await loadEmailRules(); await reclassifyEmails()
    }
    func removeEmailRule(id: Int) async {
        do {
            try await emailFilter?.removeRule(id: id)
        } catch {
            logger.warning("Failed to remove email rule: \(error.localizedDescription)")
        }
        await loadEmailRules(); await reclassifyEmails()
    }
    func overrideEmailToShared(messageID: String) async {
        do {
            try await emailFilter?.overrideToShared(messageID: messageID)
        } catch {
            logger.warning("Failed to share email: \(error.localizedDescription)")
            lastError = "Failed to share email"
        }
        await loadCachedEmails()
    }
    func hideEmail(messageID: String) async {
        do {
            try await emailFilter?.hideEmail(messageID: messageID, reason: "User hidden")
        } catch {
            logger.warning("Failed to hide email: \(error.localizedDescription)")
        }
        selectedEmailIDsForNextSession.remove(messageID)
        await loadCachedEmails()
    }
    func reclassifyEmails() async {
        do { emailClassification = try await emailFilter?.classifyAll() }
        catch { logger.warning("Failed to reclassify emails: \(error.localizedDescription)"); emailClassification = nil }
        await loadCachedEmails()
    }
    func loadCachedEmails() async {
        do { cachedEmails = try await emailFilter?.allCachedEmails() ?? [] }
        catch { logger.warning("Failed to load cached emails: \(error.localizedDescription)"); cachedEmails = [] }
        let sharedIDs = Set(cachedEmails.filter(\.isShared).map(\.messageID))
        selectedEmailIDsForNextSession = selectedEmailIDsForNextSession.intersection(sharedIDs)
        await syncGrantEmailMetadataFromCache()
    }

    func toggleEmailSelection(messageID: String) {
        guard let email = cachedEmails.first(where: { $0.messageID == messageID }), email.isShared else { return }
        if selectedEmailIDsForNextSession.contains(messageID) {
            selectedEmailIDsForNextSession.remove(messageID)
        } else {
            selectedEmailIDsForNextSession.insert(messageID)
        }
    }

    private func syncGrantEmailMetadataFromCache() async {
        guard let grantStore else { return }
        for email in cachedEmails {
            let existing = try? await grantStore.emailMessage(id: email.messageID)
            try? await grantStore.upsertEmailMessage(
                emailID: email.messageID,
                account: email.account,
                mailbox: email.mailbox,
                sender: email.sender,
                recipients: existing?.recipients ?? "",
                subject: email.subject,
                receivedAt: email.dateReceived,
                preview: email.bodyPreview,
                classificationStatus: email.status,
                hiddenReason: email.hiddenReason,
                contentHash: existing?.contentHash
            )
        }
    }

    // MARK: - Versions

    func loadTrackedFiles() async {
        do { allTrackedFiles = try await snapshotStore?.allTrackedFiles() ?? [] }
        catch { logger.error("Failed to load tracked files: \(error.localizedDescription)"); allTrackedFiles = [] }
    }
    func loadStorageStats() async {
        do { storageUsed = try await contentStore?.totalSize() ?? 0 }
        catch { logger.warning("Failed to load storage size: \(error.localizedDescription)"); storageUsed = 0 }
        do { blobCount = try await contentStore?.blobCount() ?? 0 }
        catch { logger.warning("Failed to load blob count: \(error.localizedDescription)"); blobCount = 0 }
    }
    func fileHistory(filePath: String) async -> [SnapshotRecord] {
        (try? await snapshotStore?.fileHistory(filePath: filePath)) ?? []
    }
    func snapshotData(hash: String) async -> Data? { try? await contentStore?.retrieve(hash: hash) }
    func restoreFile(snapshotID: Int, filePath: String) async -> Bool {
        guard let grant = activeGrant,
              let snapshotStore,
              let resolved = resolveGrantFilePath(filePath),
              let data = try? await snapshotStore.dataForRestore(snapshotID: snapshotID) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: resolved.fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: resolved.fileURL, options: .atomic)
            try await snapshotStore.recordRestore(
                runID: grant.grantID,
                workspaceID: resolved.mount.sourceID,
                filePath: filePath,
                restoredData: data
            )
            let afterHash = try await snapshotStore.latestHash(runID: grant.grantID, filePath: filePath)
            try? await auditStore?.log(
                action: .restore,
                runID: grant.grantID,
                workspaceID: resolved.mount.sourceID,
                filePath: filePath,
                afterHash: afterHash,
                metadata: ["snapshot_id": "\(snapshotID)", "mount": resolved.mount.mountName]
            )
            await refresh()
            return true
        } catch { return false }
    }

    private func currentGrantMounts() -> [GrantMount] {
        guard let grant = activeGrant else { return [] }
        return activeGrantSources.map { source in
            GrantMount(
                sourceID: source.sourceID,
                mountName: source.mountName,
                mountPath: URL(fileURLWithPath: grant.materializationRoot)
                    .appendingPathComponent(source.mountName)
                    .path
            )
        }
    }

    private func canonicalPath(for url: URL, base: URL, mountName: String) -> String {
        let basePath = base.standardizedFileURL.path + "/"
        let standardized = url.standardizedFileURL.path
        let relative: String
        if standardized.hasPrefix(basePath) {
            relative = String(standardized.dropFirst(basePath.count))
        } else {
            relative = url.lastPathComponent
        }
        return "\(mountName)/\(relative)"
    }

    private func resolveGrantFilePath(_ canonicalPath: String) -> ResolvedGrantPath? {
        let mounts = currentGrantMounts()
        let cleaned = canonicalPath
            .replacingOccurrences(of: "//", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let components = cleaned.split(separator: "/", maxSplits: 1)
        if components.count >= 2,
           let mount = mounts.first(where: { $0.mountName == String(components[0]) }) {
            let relativePath = String(components[1])
            let fileURL = URL(fileURLWithPath: mount.mountPath)
                .appendingPathComponent(relativePath)
                .standardizedFileURL
            guard fileURL.path.hasPrefix(URL(fileURLWithPath: mount.mountPath).standardizedFileURL.path) else {
                return nil
            }
            return ResolvedGrantPath(mount: mount, relativePath: relativePath, fileURL: fileURL)
        }

        if mounts.count == 1, let mount = mounts.first {
            let fileURL = URL(fileURLWithPath: mount.mountPath)
                .appendingPathComponent(cleaned)
                .standardizedFileURL
            guard fileURL.path.hasPrefix(URL(fileURLWithPath: mount.mountPath).standardizedFileURL.path) else {
                return nil
            }
            return ResolvedGrantPath(mount: mount, relativePath: cleaned, fileURL: fileURL)
        }

        return nil
    }

    private func baselineSnapshotMount(
        grantID: String,
        sourceID: String,
        mountName: String,
        mountPath: String,
        snapshotStore: SnapshotStore
    ) async throws {
        let root = URL(fileURLWithPath: mountPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let canonical = canonicalPath(for: url, base: root, mountName: mountName)
            guard !canonical.hasPrefix("\(mountName)/_emails/") else { continue }
            guard !canonical.hasPrefix("\(mountName)/.manifold-") else { continue }
            let data = try Data(contentsOf: url)
            try await snapshotStore.recordBaseline(
                runID: grantID,
                workspaceID: sourceID,
                filePath: canonical,
                data: data
            )
        }
    }

    private func materializeGrantEmails(
        grantID: String,
        grantRoot: URL,
        emails: [GrantEmailMessageRecord]
    ) async throws -> [(emailID: String, materializedPath: String)] {
        let emailsRoot = grantRoot.appendingPathComponent("_emails")
        try FileManager.default.createDirectory(at: emailsRoot, withIntermediateDirectories: true)

        var attachments: [(emailID: String, materializedPath: String)] = []
        var usedPaths: Set<String> = []

        for email in emails {
            let fileName = uniqueEmailFileName(for: email, usedPaths: usedPaths)
            usedPaths.insert(fileName)
            let relativePath = "_emails/\(fileName)"
            let targetURL = grantRoot.appendingPathComponent(relativePath)

            let content: String
            if let contentHash = email.contentHash,
               let data = try await contentStore?.retrieve(hash: contentHash),
               let markdown = String(data: data, encoding: .utf8) {
                content = markdown
            } else {
                content = """
                ---
                from: \(email.sender)
                to: \(email.recipients)
                date: \(email.receivedAt)
                subject: \(email.subject)
                message-id: \(email.emailID)
                ---

                # \(email.subject)

                \(email.preview ?? "")
                """
            }

            try content.write(to: targetURL, atomically: true, encoding: .utf8)
            attachments.append((email.emailID, relativePath))
        }

        return attachments
    }

    private func uniqueEmailFileName(for email: GrantEmailMessageRecord, usedPaths: Set<String>) -> String {
        let dateSlug = email.receivedAt.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "-", options: .regularExpression)
        let subjectSlug = email.subject
            .replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let base = "\(dateSlug)-\(subjectSlug.prefix(40))-\(email.emailID.prefix(8)).md"
        if !usedPaths.contains(base) {
            return base
        }

        var index = 2
        while usedPaths.contains("\(base.dropLast(3))-\(index).md") {
            index += 1
        }
        return "\(base.dropLast(3))-\(index).md"
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
        guard let grant = activeGrant else { return .error("Start a session before reverting files.") }
        guard let snapshotStore, let beforeHash = event.beforeHash else { return .blobPruned }
        guard let filePath = event.filePath, let resolved = resolveGrantFilePath(filePath) else {
            return .error("No file path")
        }

        // 1. Check blob exists
        guard let blobData = try? await contentStore?.retrieve(hash: beforeHash) else {
            return .blobPruned
        }

        // 2. Check content drift
        if FileManager.default.fileExists(atPath: resolved.fileURL.path) {
            if let afterHash = event.afterHash,
               let currentData = try? Data(contentsOf: resolved.fileURL) {
                let currentHash = currentData.sha256Hex
                if currentHash != afterHash {
                    return .contentDrift
                }
            }
        }

        // 3. Write the reverted content
        do {
            try FileManager.default.createDirectory(
                at: resolved.fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try blobData.write(to: resolved.fileURL, options: .atomic)
            try await snapshotStore.recordRestore(
                runID: grant.grantID,
                workspaceID: resolved.mount.sourceID,
                filePath: filePath,
                restoredData: blobData
            )
            let afterHash = try await snapshotStore.latestHash(runID: grant.grantID, filePath: filePath)

            try? await auditStore?.log(
                action: .restore,
                runID: grant.grantID,
                workspaceID: resolved.mount.sourceID,
                filePath: filePath,
                beforeHash: event.afterHash,
                afterHash: afterHash,
                metadata: ["reverted_from": event.afterHash ?? "unknown", "mount": resolved.mount.mountName]
            )

            await refresh()
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Force revert even when content has drifted.
    func forceRevertFile(event: SessionEvent) async -> RevertResult {
        guard let grant = activeGrant else { return .error("Start a session before reverting files.") }
        guard let snapshotStore, let beforeHash = event.beforeHash, let filePath = event.filePath else { return .blobPruned }
        guard let blobData = try? await contentStore?.retrieve(hash: beforeHash) else { return .blobPruned }
        guard let resolved = resolveGrantFilePath(filePath) else { return .error("No sources configured") }

        do {
            try FileManager.default.createDirectory(
                at: resolved.fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try blobData.write(to: resolved.fileURL, options: .atomic)
            try await snapshotStore.recordRestore(
                runID: grant.grantID,
                workspaceID: resolved.mount.sourceID,
                filePath: filePath,
                restoredData: blobData
            )
            let afterHash = try await snapshotStore.latestHash(runID: grant.grantID, filePath: filePath)
            try? await auditStore?.log(
                action: .restore,
                runID: grant.grantID,
                workspaceID: resolved.mount.sourceID,
                filePath: filePath,
                beforeHash: event.afterHash,
                afterHash: afterHash,
                metadata: [
                    "reverted_from": event.afterHash ?? "unknown",
                    "forced": "true",
                    "mount": resolved.mount.mountName,
                ]
            )
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
        await loadStorageStats(); await loadTrackedFiles(); await reclassifyEmails(); await loadCachedEmails(); await loadMailboxes()
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
    let canonicalPath: String
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

private struct ResolvedGrantPath {
    let mount: GrantMount
    let relativePath: String
    let fileURL: URL
}
