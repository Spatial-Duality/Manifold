import SwiftUI
import Foundation
import UserNotifications
import ManifoldKit

/// Central app state. Wired to ManifoldKit for real workspace management.
@MainActor
class AppState: ObservableObject {
    enum SidebarItem: String, CaseIterable, Identifiable {
        case files = "Files"
        case emails = "Emails"
        case profiles = "Profiles"
        case activity = "Activity"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .files: return "folder"
            case .emails: return "envelope"
            case .profiles: return "person.2"
            case .activity: return "clock.arrow.circlepath"
            }
        }

        var section: String {
            switch self {
            case .files, .emails: return "Sources"
            case .profiles: return "Setup"
            case .activity: return "Monitor"
            }
        }
    }

    enum AgentStatus: Equatable {
        case inactive
        case active(agent: String, runID: String)
        case warning(message: String)

        static func == (lhs: AgentStatus, rhs: AgentStatus) -> Bool {
            switch (lhs, rhs) {
            case (.inactive, .inactive): return true
            case (.active(let a1, let r1), .active(let a2, let r2)): return a1 == a2 && r1 == r2
            case (.warning(let m1), .warning(let m2)): return m1 == m2
            default: return false
            }
        }
    }

    @Published var selectedSidebar: SidebarItem = .files
    @Published var agentStatus: AgentStatus = .inactive
    @Published var sources: [SourceItem] = []
    @Published var activityEntries: [ActivityEntry] = []
    @Published var currentRunID: String?
    @Published var currentWorkspaceID: String?
    @Published var currentWorkspacePath: String?
    @Published var isGranting = false
    @Published var hasCompletedOnboarding: Bool

    // ManifoldKit stores
    private var contentStore: ContentStore?
    private var snapshotStore: SnapshotStore?
    private var leaseManager: WorkspaceLeaseManager?
    private var auditStore: AuditStore?
    private var watcher: FSEventsWatcher?
    private var emailFilter: EmailFilter?

    // Email state
    @Published var cachedEmails: [CachedEmail] = []
    @Published var emailClassification: EmailClassificationResult?

    var menuBarIcon: String {
        switch agentStatus {
        case .inactive: return "circle"
        case .active: return "circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        }
    }

    var hasActiveRun: Bool {
        if case .active = agentStatus { return true }
        return false
    }

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        Task { await initStores() }
    }

    private func initStores() async {
        do {
            let storeURL = Self.manifoldStoreURL()
            contentStore = try ContentStore(rootURL: storeURL)
            let db = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
            snapshotStore = try SnapshotStore(db: db, contentStore: contentStore!)
            leaseManager = try WorkspaceLeaseManager(db: db, snapshotStore: snapshotStore!)
            auditStore = try AuditStore(db: db)
            emailFilter = try EmailFilter(db: db)
        } catch {
            print("Failed to initialize ManifoldKit stores: \(error)")
        }
    }

    // MARK: - Source Management

    func addFileSources() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select files or folders for agents to access"

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let fileCount = isDir ? countFiles(in: url) : 1
            let source = SourceItem(
                id: UUID(),
                path: url.path,
                url: url,
                type: isDir ? .directory : .file,
                fileCount: fileCount,
                status: .synced,
                isSensitive: isSensitivePath(url.path)
            )
            if !sources.contains(where: { $0.path == source.path }) {
                sources.append(source)
                Task {
                    try? await auditStore?.log(action: .sourceAdded, metadata: ["path": source.path])
                }
            }
        }
    }

    func removeSource(_ source: SourceItem) {
        sources.removeAll { $0.id == source.id }
        Task {
            try? await auditStore?.log(action: .sourceRemoved, metadata: ["path": source.path])
        }
    }

    // MARK: - Apple Mail

    @Published var mailError: String?
    @Published var mailboxes: [MailboxInfo] = []
    @Published var isLoadingMail = false

    func connectAppleMail() async {
        isLoadingMail = true
        mailError = nil

        let connector = AppleMailConnector()
        do {
            let status = try connector.checkAccess()
            guard status == .available else {
                mailError = "Mail.app is not running. Please open Mail first."
                isLoadingMail = false
                return
            }
            mailboxes = try connector.listMailboxes()
        } catch {
            mailError = error.localizedDescription
        }
        isLoadingMail = false
    }

    func addMailbox(_ mailbox: MailboxInfo, since: Date? = nil) async {
        isLoadingMail = true
        let connector = AppleMailConnector()
        do {
            let emails = try connector.fetchMessages(
                account: mailbox.account,
                mailbox: mailbox.name,
                since: since ?? Calendar.current.date(byAdding: .day, value: -30, to: Date()),
                limit: 100
            )

            // Render emails to a temp directory, then add as source
            let emailDir = Self.manifoldStoreURL()
                .appendingPathComponent("emails")
                .appendingPathComponent(mailbox.name.replacingOccurrences(of: " ", with: "-").lowercased())
            let urls = try connector.renderToDirectory(emails: emails, directory: emailDir)

            let source = SourceItem(
                id: UUID(),
                path: emailDir.path,
                url: emailDir,
                type: .email,
                fileCount: urls.count,
                status: .synced,
                isSensitive: false
            )
            if !sources.contains(where: { $0.path == source.path }) {
                sources.append(source)
                try? await auditStore?.log(action: .sourceAdded, metadata: [
                    "path": source.path,
                    "type": "email",
                    "account": mailbox.account,
                    "mailbox": mailbox.name,
                    "count": "\(urls.count)"
                ])
            }
        } catch {
            mailError = error.localizedDescription
        }
        isLoadingMail = false
    }

    // MARK: - Email Permission Dashboard

    /// Connect to Apple Mail and fetch + classify all emails in background.
    func connectAndFetchEmails() async {
        isLoadingMail = true
        mailError = nil

        let connector = AppleMailConnector()
        do {
            let status = try connector.checkAccess()
            guard status == .available else {
                mailError = "Mail.app is not running. Please open Mail first."
                isLoadingMail = false
                return
            }

            let mailboxes = try connector.listMailboxes()
            guard let emailFilter = emailFilter else { isLoadingMail = false; return }

            // Fetch from all mailboxes (last 30 days, cached)
            for mailbox in mailboxes {
                let emails = try connector.fetchMessages(
                    account: mailbox.account,
                    mailbox: mailbox.name,
                    since: Calendar.current.date(byAdding: .day, value: -30, to: Date()),
                    limit: 200
                )
                for email in emails {
                    try await emailFilter.cacheEmail(email, account: mailbox.account, mailbox: mailbox.name)
                }
            }

            // Classify all
            emailClassification = try await emailFilter.classifyAll()
            cachedEmails = try await emailFilter.allCachedEmails()
        } catch {
            mailError = error.localizedDescription
        }
        isLoadingMail = false
    }

    /// Refresh email cache from Mail.app.
    func refreshEmails() async {
        guard let emailFilter = emailFilter else { return }
        try? await emailFilter.clearCache()
        await connectAndFetchEmails()
    }

    /// Override an auto-hidden email to shared.
    func overrideEmailToShared(_ email: CachedEmail) async {
        guard let emailFilter = emailFilter else { return }
        try? await emailFilter.overrideToShared(messageID: email.messageID)
        cachedEmails = (try? await emailFilter.allCachedEmails()) ?? cachedEmails
        emailClassification = try? await emailFilter.classifyAll()
    }

    /// Manually hide an email.
    func hideEmail(_ email: CachedEmail) async {
        guard let emailFilter = emailFilter else { return }
        try? await emailFilter.hideEmail(messageID: email.messageID)
        cachedEmails = (try? await emailFilter.allCachedEmails()) ?? cachedEmails
        emailClassification = try? await emailFilter.classifyAll()
    }

    // MARK: - Access Runs (wired to ManifoldKit)

    func grantAccess() async {
        guard !isGranting, !sources.isEmpty else { return }
        isGranting = true

        do {
            // Workspace lives at ~/Manifold/Workspace/ — the folder you give to Cowork
            let workspaceURL = Self.coworkFolder
            let profileID = "default"
            let workspace = ManagedWorkspace(profileID: profileID, agent: "cowork", baseURL: Self.manifoldWorkspacesURL())
            try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

            // Sync selected files into the workspace
            let fileSources = sources.filter { $0.type != .email }.map { $0.url }
            for source in fileSources {
                try syncSource(source, into: workspaceURL)
            }

            // Sync shared emails
            if let emailFilter = emailFilter {
                let shared = try await emailFilter.sharedEmails()
                if !shared.isEmpty {
                    let emailsDir = workspaceURL.appendingPathComponent("_emails")
                    try FileManager.default.createDirectory(at: emailsDir, withIntermediateDirectories: true)
                    let connector = AppleMailConnector()
                    // Re-render shared emails into workspace
                    for email in shared {
                        let rendered = RenderedEmail(
                            messageID: email.messageID,
                            from: email.sender,
                            subject: email.subject,
                            body: email.bodyPreview ?? ""
                        )
                        let md = rendered.toMarkdown()
                        let fileName = rendered.safeFileName
                        let fileURL = emailsDir.appendingPathComponent(fileName)
                        try md.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
                        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: fileURL.path)
                    }
                }
            }

            guard let leaseManager = leaseManager, let snapshotStore = snapshotStore else {
                isGranting = false
                return
            }

            try await leaseManager.registerWorkspace(workspace)
            let runID = try await leaseManager.startRun(
                workspaceID: workspace.workspaceID,
                agent: "cowork",
                trigger: .userGrant
            )

            // Baseline snapshot of everything in ~/Manifold/Workspace/
            let files = try enumerateFiles(in: workspaceURL)
            for fileURL in files {
                let relativePath = fileURL.path.replacingOccurrences(of: workspaceURL.path + "/", with: "")
                guard !relativePath.isEmpty else { continue }
                let data = try Data(contentsOf: fileURL)
                try await snapshotStore.recordBaseline(
                    runID: runID,
                    workspaceID: workspace.workspaceID,
                    filePath: relativePath,
                    data: data
                )
            }

            try await leaseManager.markBaselineComplete(runID: runID)
            try await auditStore?.log(
                action: .runStart,
                runID: runID,
                workspaceID: workspace.workspaceID,
                agent: "cowork"
            )

            currentRunID = runID
            currentWorkspaceID = workspace.workspaceID
            currentWorkspacePath = workspaceURL.path
            agentStatus = .active(agent: "Cowork", runID: runID)

            // Start watching ~/Manifold/Workspace/
            startWatching(path: workspaceURL.path, workspaceID: workspace.workspaceID, runID: runID)

            // Copy path to clipboard so user can paste into Cowork
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(workspaceURL.path, forType: .string)

            // Reveal in Finder
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workspaceURL.path)

            // Open Claude Desktop
            openClaudeDesktop()

        } catch {
            print("Grant failed: \(error)")
            agentStatus = .warning(message: "Grant failed")
        }

        isGranting = false
    }

    func endAccess() async {
        guard let runID = currentRunID else { return }
        isGranting = true

        do {
            try await leaseManager?.endRun(runID: runID)
            try await auditStore?.log(
                action: .runEnd,
                runID: runID,
                workspaceID: currentWorkspaceID,
                agent: "cowork"
            )
        } catch {
            print("End access failed: \(error)")
        }

        watcher?.stop()
        watcher = nil
        currentRunID = nil
        agentStatus = .inactive
        isGranting = false
    }

    func refreshAccess() async {
        await endAccess()
        await grantAccess()
    }

    // MARK: - FSEvents Watcher

    private func startWatching(path rootPath: String, workspaceID wsID: String, runID: String) {
        watcher?.stop()

        watcher = FSEventsWatcher(paths: [rootPath]) { [weak self] event in
            Task { @MainActor in
                guard let self = self, let snapshotStore = self.snapshotStore else { return }

                let relativePath = event.path.replacingOccurrences(
                    of: rootPath + "/",
                    with: ""
                )
                let activeRunID = self.currentRunID ?? "unscoped"

                do {
                    switch event.changeType {
                    case .created:
                        let data = try Data(contentsOf: URL(fileURLWithPath: event.path))
                        try await snapshotStore.recordCreation(
                            runID: activeRunID, workspaceID: wsID,
                            filePath: relativePath, data: data
                        )
                    case .modified:
                        let data = try Data(contentsOf: URL(fileURLWithPath: event.path))
                        try await snapshotStore.recordModification(
                            runID: activeRunID, workspaceID: wsID,
                            filePath: relativePath, newData: data
                        )
                    case .deleted:
                        try await snapshotStore.recordDeletion(
                            runID: activeRunID, workspaceID: wsID,
                            filePath: relativePath
                        )
                    case .renamed:
                        break
                    }

                    let entry = ActivityEntry(
                        id: UUID(),
                        timestamp: Date(),
                        runID: activeRunID,
                        agent: "Cowork",
                        filePath: relativePath,
                        changeType: ActivityEntry.ChangeType(from: event.changeType),
                        isSensitive: self.isSensitivePath(event.path)
                    )
                    self.activityEntries.insert(entry, at: 0)

                    // macOS notification for sensitive files
                    if entry.isSensitive {
                        self.sendSensitiveFileNotification(entry: entry)
                    }
                } catch {
                    print("Error recording change: \(error)")
                }
            }
        }
        watcher?.start()
    }

    // MARK: - Open Claude Desktop

    func openClaudeDesktop() {
        // Try to open Claude Desktop app by bundle ID
        let claudeBundleIDs = [
            "com.anthropic.claudefordesktop",
            "com.anthropic.claude"
        ]
        for bundleID in claudeBundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
        // Fallback: try by app name
        let appPaths = [
            "/Applications/Claude.app",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/Claude.app"
        ]
        for path in appPaths {
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
    }

    // MARK: - Session Replay

    @Published var completedRuns: [RunRecord] = []

    func loadCompletedRuns() async {
        guard let leaseManager = leaseManager, let workspaceID = currentWorkspaceID else { return }
        completedRuns = (try? await leaseManager.runs(workspaceID: workspaceID).filter { !$0.isActive }) ?? []
    }

    func loadSessionReplay(runID: String) async -> [ActivityEntry] {
        guard let snapshotStore = snapshotStore else { return [] }
        do {
            let records = try await snapshotStore.runTimeline(runID: runID)
            return records.reversed().compactMap { record in
                guard !record.isBaseline else { return nil }
                let changeType: ActivityEntry.ChangeType
                if record.isDelete { changeType = .deleted }
                else if record.beforeHash == nil { changeType = .created }
                else if record.source == "manifold-restore" { changeType = .restored }
                else { changeType = .modified }

                return ActivityEntry(
                    id: UUID(),
                    timestamp: ISO8601DateFormatter().date(from: record.timestamp) ?? Date(),
                    runID: record.runID,
                    agent: "Cowork",
                    filePath: record.filePath,
                    changeType: changeType,
                    isSensitive: isSensitivePath(record.filePath)
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Notifications

    private func sendSensitiveFileNotification(entry: ActivityEntry) {
        // Only works in a proper .app bundle, not bare executable
        guard Bundle.main.bundleIdentifier != nil else { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Sensitive file modified"
            content.body = "Agent \(entry.agent) modified \(entry.filePath)"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Diffs

    func loadDiff(for entry: ActivityEntry) async -> [ManifoldKit.DiffLine] {
        guard let snapshotStore = snapshotStore else { return [] }
        guard let runID = currentRunID ?? Optional(entry.runID) else { return [] }

        do {
            let history = try await snapshotStore.history(runID: runID, filePath: entry.filePath)
            guard history.count >= 2 else { return [] }

            // Find the two most recent versions
            let current = history.last!
            let previous = history[history.count - 2]

            guard let currentHash = current.afterHash,
                  let previousHash = previous.afterHash else { return [] }

            guard let currentData = try await contentStore?.retrieve(hash: currentHash),
                  let previousData = try await contentStore?.retrieve(hash: previousHash) else { return [] }

            let engine = DiffEngine()
            return engine.diff(beforeData: previousData, afterData: currentData) ?? []
        } catch {
            return []
        }
    }

    // MARK: - Restore

    func restoreEntry(_ entry: ActivityEntry) async {
        guard let snapshotStore = snapshotStore,
              let workspacePath = currentWorkspacePath else { return }

        do {
            let history = try await snapshotStore.history(runID: entry.runID, filePath: entry.filePath)
            guard history.count >= 2 else { return }

            let previous = history[history.count - 2]
            guard let data = try await snapshotStore.dataForRestore(snapshotID: previous.id) else { return }

            // Write restored content to workspace file
            let fileURL = URL(fileURLWithPath: workspacePath).appendingPathComponent(entry.filePath)
            try data.write(to: fileURL, options: .atomic)

            // Record the restore
            if let wsID = currentWorkspaceID {
                try await snapshotStore.recordRestore(
                    runID: entry.runID,
                    workspaceID: wsID,
                    filePath: entry.filePath,
                    restoredData: data
                )
            }

            let restoreEntry = ActivityEntry(
                id: UUID(),
                timestamp: Date(),
                runID: entry.runID,
                agent: "Manifold",
                filePath: entry.filePath,
                changeType: .restored,
                isSensitive: false
            )
            activityEntries.insert(restoreEntry, at: 0)

            try? await auditStore?.log(
                action: .restore,
                runID: entry.runID,
                workspaceID: currentWorkspaceID,
                filePath: entry.filePath
            )
        } catch {
            print("Restore failed: \(error)")
        }
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    // MARK: - Sensitivity Detection (basic filename matching)

    private func isSensitivePath(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        let sensitiveNames: Set<String> = [".env", ".env.local", ".env.production", "id_rsa", "id_ed25519", ".gitconfig"]
        let sensitiveExtensions: Set<String> = ["pem", "key", "p12", "pfx"]

        if sensitiveNames.contains(name) { return true }
        if let ext = name.split(separator: ".").last, sensitiveExtensions.contains(String(ext)) { return true }
        if name.hasPrefix(".env") { return true }

        return false
    }

    // MARK: - File Operations

    /// Copy a source file or directory into the workspace
    private func syncSource(_ source: URL, into workspace: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDir) else { return }

        if isDir.boolValue {
            let dirName = source.lastPathComponent
            let dest = workspace.appendingPathComponent(dirName)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: source, to: dest)
        } else {
            let dest = workspace.appendingPathComponent(source.lastPathComponent)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: source, to: dest)
        }
    }

    /// Enumerate all files in a directory recursively
    private func enumerateFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true { files.append(url) }
        }
        return files
    }

    // MARK: - Helpers

    private func countFiles(in url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        while let fileURL = enumerator.nextObject() as? URL {
            let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            if isFile { count += 1 }
        }
        return count
    }

    static func manifoldStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Manifold/store")
    }

    static func manifoldWorkspacesURL() -> URL {
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Manifold")
    }

    /// The ONE folder to give to Cowork. ~/Manifold/Workspace/
    /// Simple. Memorable. Set it once in Cowork's folder picker.
    static var coworkFolder: URL {
        manifoldWorkspacesURL().appendingPathComponent("Workspace")
    }

    static var coworkFolderPath: String {
        coworkFolder.path
    }
}

// MARK: - Data Models

struct SourceItem: Identifiable {
    let id: UUID
    let path: String
    let url: URL
    let type: SourceType
    var fileCount: Int
    var status: SyncStatus
    var isSensitive: Bool

    enum SourceType { case file, directory, email }
    enum SyncStatus: String { case synced = "Synced", syncing = "Syncing", error = "Error" }

    var icon: String {
        switch type {
        case .file: return "doc"
        case .directory: return "folder"
        case .email: return "envelope"
        }
    }

    var displayName: String {
        if path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) {
            return "~" + path.dropFirst(FileManager.default.homeDirectoryForCurrentUser.path.count)
        }
        return path
    }
}

struct ActivityEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let runID: String
    let agent: String
    let filePath: String
    let changeType: ChangeType
    let isSensitive: Bool

    enum ChangeType: String {
        case created = "Created"
        case modified = "Modified"
        case deleted = "Deleted"
        case restored = "Restored"

        init(from fsChangeType: ManifoldKit.ChangeType) {
            switch fsChangeType {
            case .created: self = .created
            case .modified: self = .modified
            case .deleted: self = .deleted
            case .renamed: self = .modified
            }
        }
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: timestamp).lowercased()
    }

    var fileName: String {
        (filePath as NSString).lastPathComponent
    }
}
