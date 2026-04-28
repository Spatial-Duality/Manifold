// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftUI
import UserNotifications
import os
import ManifoldKit
import ManifoldXPC

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "store")

@Observable
@MainActor
final class ManifoldStore {
    var isConnected = false
    var isRuntimeConnected = false
    var connectedAgent: String?
    var connectedAgents: [String] = []
    var runtimeLaunchError: String?
    var dataControlSummary: DataControlSummary?

    /// Whether Claude (cowork) has an active MCP bridge connection to the runtime.
    var isClaudeConnected: Bool { connectedAgents.contains(TargetApp.cowork.rawValue) }
    /// Whether Codex has an active MCP bridge connection to the runtime.
    var isCodexConnected: Bool { connectedAgents.contains(TargetApp.codex.rawValue) }

    var sources: [SourceRecord] = []
    var approvedSources: [String] { sources.filter(\.isAccessible).map(\.originalRootPath) }

    var lastError: String?

    let session: SessionModel
    let activity: ActivityModel
    let storage: StorageModel
    let setup: SetupModel
    let mailAccounts: MailAccountsModel
    let mailReview: MailReviewModel
    let governance: GovernanceModel
    let rules: RulesModel
    let personalDataOS: PersonalDataOSModel
    let integrationHealth: IntegrationHealthModel
    let diagnostics: DiagnosticsModel
    let updater: UpdaterModel?

    let runtime: any RuntimeClientProtocol
    private var connectionMonitorTask: Task<Void, Never>?
    private var didAttemptAgentRestart = false

    var menuBarIcon: String {
        guard isRuntimeConnected else { return "shield.slash" }
        if dataControlSummary?.pendingApprovalCount ?? governance.pendingApprovals.count > 0 {
            return "hand.raised.fill"
        }
        if dataControlSummary?.activeWorkBlock != nil || activeSession != nil {
            return "checkmark.shield.fill"
        }
        if dataControlSummary?.agents.allSatisfy(\.isPaused) == true {
            return "pause.circle.fill"
        }
        return "checkmark.shield.fill"
    }

    init(
        runtime: any RuntimeClientProtocol = AppRuntimeClient(),
        integrationHealth: IntegrationHealthModel = IntegrationHealthModel(),
        startServices: Bool = true
    ) {
        self.runtime = runtime
        self.integrationHealth = integrationHealth
        session = SessionModel()
        activity = ActivityModel()
        storage = StorageModel()
        setup = SetupModel()
        mailAccounts = MailAccountsModel()
        mailReview = MailReviewModel()
        governance = GovernanceModel()
        rules = RulesModel()
        personalDataOS = PersonalDataOSModel()
        diagnostics = DiagnosticsModel()
        // Sparkle is only meaningful when the bundle has a feed URL and a
        // public EdDSA key — i.e. an official build. In source builds where
        // SPARKLE_PUBLIC_ED_KEY is empty, instantiating the controller would
        // log a fault every time. Keep `updater` nil there; Help -> Check
        // for Updates and the consent toggle no-op cleanly.
        // Sparkle is only meaningful when the bundle has a public EdDSA key
        // — i.e. an official build. In source builds where the key is empty
        // we skip the controller entirely; Help -> Check for Updates and the
        // consent toggle no-op cleanly.
        if startServices, Self.sparkleConfigured() {
            updater = UpdaterModel(diagnostics: diagnostics)
        } else {
            updater = nil
        }

        session.configure(client: runtime)
        activity.configure(client: runtime)
        storage.configure(client: runtime)
        mailAccounts.configure(client: runtime)
        mailReview.configure(mailAccounts: mailAccounts)
        governance.configure(client: runtime)
        rules.configure(client: runtime)
        personalDataOS.configure(client: runtime)

        integrationHealth.store = self

        if startServices {
            // Diagnostics: record launch + detect any unexpected exit of the
            // previous agent run before we start the new one.
            diagnostics.record(.appLaunch)
            diagnostics.checkAgentExitState()

            // Sparkle: thread the agent shutdown into the updater so the
            // app/agent versions never go out of sync across an auto-update.
            updater?.agentShutdown = { [weak self] in self?.unregisterAgent() }

            registerAgent()
            requestNotificationPermission()
            startConnectionMonitor()
            startUpdaterConsentBridge()

            Task {
                await refreshAll(force: true)
                await integrationHealth.checkAll()
            }
        }
    }

    /// Mirror the diagnostics consent toggle to Sparkle's automatic-check
    /// preference. Polled rather than KVO'd because @Observable doesn't
    /// expose Combine publishers and the toggle changes at human cadence.
    private func startUpdaterConsentBridge() {
        guard let updater else { return }
        var lastSeen = diagnostics.updateChecksEnabled
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let current = self.diagnostics.updateChecksEnabled
                if current != lastSeen {
                    lastSeen = current
                    updater.applyAutomaticCheckPreference(current)
                }
            }
        }
    }

    /// True when the bundle has both a feed URL and a populated public key,
    /// i.e. an official notarized build that can verify update signatures.
    /// Source builds with an empty `SUPublicEDKey` skip Sparkle entirely.
    private static func sparkleConfigured() -> Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        return !key.isEmpty && !feed.isEmpty
    }

    func refresh() async {
        await refreshAll(force: true)
    }

    func refreshAll(force: Bool = false) async {
        let pingResult = await runtime.ping()
        isRuntimeConnected = pingResult.ok
        isConnected = pingResult.ok

        guard pingResult.ok else {
            connectedAgent = nil
            connectedAgents = []
            dataControlSummary = nil
            if force {
                lastError = runtimeLaunchError ?? "Unable to connect to the Manifold runtime."
            }
            return
        }

        runtimeLaunchError = nil

        // XPC version check: auto-restart agent on mismatch (once per app launch)
        let appVersion = Bundle.main.shortVersionString
        if let agentVersion = pingResult.agentVersion, agentVersion != appVersion, !didAttemptAgentRestart {
            didAttemptAgentRestart = true
            logger.notice("Agent version \(agentVersion) != app version \(appVersion). Restarting agent.")
            diagnostics.record(.versionMismatchRestart(appVersion: appVersion, runtimeVersion: agentVersion))
            unregisterAgent()
            registerAgent()
            try? await Task.sleep(for: .seconds(1))
            let retry = await runtime.ping()
            isRuntimeConnected = retry.ok
            isConnected = retry.ok
            guard retry.ok else {
                lastError = runtimeLaunchError ?? "Unable to reconnect to the Manifold runtime after restarting it."
                return
            }
        }

        do {
            let dashboard = try await runtime.dashboardState()
            sources = dashboard.sources
            governance.claudePolicy = dashboard.claudePolicy
            governance.codexPolicy = dashboard.codexPolicy
            governance.claudeEmailGovernance = dashboard.claudeEmailGovernance
            governance.codexEmailGovernance = dashboard.codexEmailGovernance
            governance.activeSessionRecord = dashboard.activeSession
            governance.claudeCoverage = dashboard.agentCoverages.first { $0.agent == TargetApp.cowork.rawValue }
            governance.codexCoverage = dashboard.agentCoverages.first { $0.agent == TargetApp.codex.rawValue }
            governance.coverageEvents = dashboard.coverageEvents
            connectedAgents = dashboard.connectedAgents
            // Derive connectedAgent from actual runtime data, not heuristics
            connectedAgent = dashboard.connectedAgents.first
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to refresh dashboard: \(error.localizedDescription)")
        }

        do {
            governance.pendingApprovals = try await runtime.listPendingApprovals()
        } catch {
            governance.pendingApprovals = []
            logger.error("Failed to load pending approvals: \(error.localizedDescription)")
        }

        do {
            dataControlSummary = try await runtime.dataControlSummary()
        } catch {
            dataControlSummary = nil
            logger.error("Failed to load data control summary: \(error.localizedDescription)")
        }

        await governance.loadPrivacyDiscovery()

        consumePendingFinderRequest()

        await activity.loadActivity()
        await activity.loadSessions()
        await session.refreshGrantState()
        await storage.loadStorageStats()
        await storage.loadTrackedFiles()
        await personalDataOS.loadOverview()
        await mailAccounts.loadAccounts()
        await rules.load()
    }

    private func startConnectionMonitor() {
        connectionMonitorTask?.cancel()
        connectionMonitorTask = Task { [weak self] in
            var ticks = 0
            var previousConnected = false
            while let self, !Task.isCancelled {
                let pingResult = await self.runtime.ping()
                let connected = pingResult.ok
                await MainActor.run {
                    self.isRuntimeConnected = connected
                    self.isConnected = connected
                    if !connected {
                        self.connectedAgent = nil
                        self.connectedAgents = []
                        if self.lastError == nil, let runtimeLaunchError = self.runtimeLaunchError {
                            self.lastError = runtimeLaunchError
                        }
                    }
                }

                ticks += 1
                if connected && (!previousConnected || ticks % 6 == 0) {
                    await self.refreshAll()
                }
                previousConnected = connected
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func consumePendingFinderRequest() {
        let requestURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Manifold/finder-sync-request.json")
        guard let data = try? Data(contentsOf: requestURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paths = payload["paths"] as? [String] else {
            return
        }

        for path in paths {
            if !sources.contains(where: { $0.originalRootPath == path }) {
                addSource(path: path)
            }
        }
        try? FileManager.default.removeItem(at: requestURL)
    }

    func addSource(path: String) {
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        Task {
            guard isRuntimeConnected else {
                lastError = "Cannot add \"\(folderName)\" — runtime is not connected. Check that ManifoldAgent is running."
                return
            }
            do {
                _ = try await runtime.addSource(path: path, displayName: folderName)
                await loadSources()
            } catch {
                logger.error("Failed to add source \(folderName): \(error.localizedDescription)")
                lastError = "Failed to add \"\(folderName)\": \(error.localizedDescription)"
            }
        }
    }

    func removeSource(path: String) {
        Task {
            do {
                guard let source = sources.first(where: { $0.originalRootPath == path }) else { return }
                try await runtime.removeSource(sourceID: source.sourceID)
                await loadSources()
                await refreshAll()
            } catch {
                logger.error("Failed to remove source: \(error.localizedDescription)")
                lastError = "Failed to remove source"
            }
        }
    }

    func pauseSource(sourceID: String) async {
        do {
            try await runtime.pauseSource(sourceID: sourceID)
            await loadSources()
            await refreshAll()
        } catch {
            lastError = "Failed to pause source"
        }
    }

    func resumeSource(sourceID: String) async {
        do {
            try await runtime.resumeSource(sourceID: sourceID)
            await loadSources()
            await refreshAll()
        } catch {
            lastError = "Failed to resume source"
        }
    }

    @discardableResult
    func addSourceFromPicker() -> Bool {
        let paths = chooseSourcePathsFromPicker()
        for path in paths { addSource(path: path) }
        return !paths.isEmpty
    }

    @discardableResult
    func addFilesFromPicker() -> Bool {
        let filePaths = chooseFilePathsFromPicker()
        guard !filePaths.isEmpty else { return false }

        let existingPaths = Set(sources.map(\.originalRootPath))
        let parentPaths = Set(
            filePaths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        )

        for path in parentPaths where !existingPaths.contains(path) {
            addSource(path: path)
        }
        return true
    }

    func chooseSourcePathsFromPicker() -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select folders to protect through Manifold"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return [] }
        return panel.urls.map(\.path)
    }

    func chooseFilePathsFromPicker() -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Select files to manage through Manifold"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return [] }
        return panel.urls.map(\.path)
    }

    func removeSources(paths: Set<String>) {
        for path in paths { removeSource(path: path) }
    }

    func loadSources() async {
        do {
            sources = try await runtime.listSources()
        } catch {
            logger.error("Failed to load sources: \(error.localizedDescription)")
        }
    }

    func enumerateSourceFiles() async -> [SourceFile] {
        let activeSources = sources.filter { $0.isAccessible && !$0.isRemoved }
        return await Task.detached(priority: .userInitiated) {
            Self.walkSourceFiles(sources: activeSources)
        }.value
    }

    func enumerateSourceFilesProgressively(batchSize: Int = 200) -> AsyncStream<[SourceFile]> {
        let activeSources = sources.filter { $0.isAccessible && !$0.isRemoved }
        return AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await Self.streamSourceFiles(
                    sources: activeSources,
                    batchSize: max(batchSize, 1)
                ) { batch in
                    continuation.yield(batch)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private nonisolated static func streamSourceFiles(
        sources: [SourceRecord],
        batchSize: Int,
        yield: @escaping @Sendable ([SourceFile]) async -> Void
    ) async {
        let fm = FileManager.default
        var batch: [SourceFile] = []

        for source in sources {
            guard !Task.isCancelled else { return }
            let root = URL(fileURLWithPath: source.originalRootPath)
            var didEmitSourceFile = false
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                batch.append(contentsOf: fixtureSourceFilesIfNeeded(for: source))
                continue
            }

            let basePath = root.path + "/"
            while let url = enumerator.nextObject() as? URL {
                guard !Task.isCancelled else { return }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }
                let path = url.path
                guard path.hasPrefix(basePath) else { continue }
                let relativePath = String(path.dropFirst(basePath.count))

                let first = relativePath.split(separator: "/").first.map(String.init) ?? relativePath
                let skip = [".git", "node_modules", ".build", "Build", "DerivedData", "Pods", "__pycache__", ".DS_Store"]
                if skip.contains(first) {
                    if url.hasDirectoryPath { enumerator.skipDescendants() }
                    continue
                }

                batch.append(
                    SourceFile(
                        name: url.lastPathComponent,
                        path: path,
                        relativePath: relativePath,
                        sourceName: source.displayName,
                        sourceID: source.sourceID,
                        fileExtension: url.pathExtension.lowercased(),
                        sizeBytes: values.fileSize ?? 0,
                        modifiedDate: values.contentModificationDate ?? .distantPast,
                        isGrantedToClaude: true
                    )
                )
                didEmitSourceFile = true

                if batch.count >= batchSize {
                    await yield(batch)
                    batch.removeAll(keepingCapacity: true)
                }
            }

            if !didEmitSourceFile {
                batch.append(contentsOf: fixtureSourceFilesIfNeeded(for: source))
            }
        }

        if !batch.isEmpty {
            await yield(batch)
        }
    }

    private nonisolated static func walkSourceFiles(sources: [SourceRecord]) -> [SourceFile] {
        let fm = FileManager.default
        var result: [SourceFile] = []

        for source in sources {
            guard !Task.isCancelled else { return result }
            let root = URL(fileURLWithPath: source.originalRootPath)
            var didAppendSourceFile = false
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                result.append(contentsOf: fixtureSourceFilesIfNeeded(for: source))
                continue
            }

            let basePath = root.path + "/"
            while let url = enumerator.nextObject() as? URL {
                guard !Task.isCancelled else { return result }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }
                let path = url.path
                guard path.hasPrefix(basePath) else { continue }
                let relativePath = String(path.dropFirst(basePath.count))

                let first = relativePath.split(separator: "/").first.map(String.init) ?? relativePath
                let skip = [".git", "node_modules", ".build", "Build", "DerivedData", "Pods", "__pycache__", ".DS_Store"]
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
                    modifiedDate: values.contentModificationDate ?? .distantPast,
                    isGrantedToClaude: true
                ))
                didAppendSourceFile = true
            }

            if !didAppendSourceFile {
                result.append(contentsOf: fixtureSourceFilesIfNeeded(for: source))
            }
        }

        return result
    }

    private nonisolated static func fixtureSourceFilesIfNeeded(for source: SourceRecord) -> [SourceFile] {
        guard ProcessInfo.processInfo.environment[AppTestEnvironment.runtimeModeKey] == "fixture" else {
            return []
        }

        let relativePaths: [String]
        switch source.sourceID {
        case "src-shared":
            relativePaths = ["worklog.md", "Docs/ReleaseNotes.md", "archive.bin"]
        case "src-claude":
            relativePaths = ["marker.txt"]
        default:
            relativePaths = []
        }

        let root = URL(fileURLWithPath: source.originalRootPath, isDirectory: true)
        return relativePaths.map { relativePath in
            let url = root.appendingPathComponent(relativePath)
            return SourceFile(
                name: url.lastPathComponent,
                path: url.path,
                relativePath: relativePath,
                sourceName: source.displayName,
                sourceID: source.sourceID,
                fileExtension: url.pathExtension.lowercased(),
                sizeBytes: 0,
                modifiedDate: Date(),
                isGrantedToClaude: true
            )
        }
    }

    func enumerateAllFiles() async -> [SourceFile] {
        let mounts = session.currentGrantMounts()
        return await Task.detached(priority: .userInitiated) { [session] in
            let fm = FileManager.default
            var result: [SourceFile] = []

            for mount in mounts {
                guard !Task.isCancelled else { return result }
                let root = URL(fileURLWithPath: mount.mountPath)
                guard let enumerator = fm.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                while let url = enumerator.nextObject() as? URL {
                    guard !Task.isCancelled else { return result }
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
                        modifiedDate: values.contentModificationDate ?? .distantPast,
                        isGrantedToClaude: true
                    ))
                }
            }

            return result
        }.value
    }

    func searchFileContents(query: String, includeArchived: Bool = false) async -> [SearchResult] {
        let mounts = session.currentGrantMounts()
        let capturedSession = session
        return await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var results: [SearchResult] = []

            for mount in mounts {
                let root = URL(fileURLWithPath: mount.mountPath)
                guard let enumerator = fm.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                while let url = enumerator.nextObject() as? URL {
                    guard !Task.isCancelled else { return results }
                    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                          values.isRegularFile == true,
                          let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                    let relativePath = await capturedSession.canonicalPath(for: url, base: root, mountName: mount.mountName)
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
        }.value
    }

    func startSession(targetApp: TargetApp = .cowork) async {
        var draft = SessionDraft()
        draft.agents = [targetApp]
        try? await startProtectedRun(draft: draft)
    }

    func endSession() async {
        await session.endSession(
            onError: { [weak self] message in self?.lastError = message },
            onConflict: { [weak self] count in self?.lastError = "\(count) conflict(s) during promote. Check activity for details." }
        )
        await refreshAll()
        session.lastCompletedSession = activity.sessions.first(where: { $0.id == session.activeGrant?.grantID })
    }

    func restoreFile(snapshotID: Int, filePath: String) async -> RestoreSnapshotResult {
        let result = await session.restoreFile(snapshotID: snapshotID, filePath: filePath)
        if result.isSuccess { await refreshAll() }
        return result
    }

    func revertFile(event: SessionEvent) async -> RevertResult {
        let result = await activity.revertFile(event: event, activeGrant: session.activeGrant)
        if case .success = result { await refreshAll() }
        return result
    }

    func forceRevertFile(event: SessionEvent) async -> RevertResult {
        let result = await activity.forceRevertFile(event: event, activeGrant: session.activeGrant)
        if case .success = result { await refreshAll() }
        return result
    }

    func loadSummary() async {
        await refreshAll(force: true)
    }

    var activeGrant: GrantRecord? { session.activeGrant }
    var activeGrantSources: [GrantSourceRecord] { session.activeGrantSources }
    var hasActiveSession: Bool { session.hasActiveSession }
    var activityEntries: [AuditEntry] { activity.activityEntries }
    var sessions: [Session] { activity.sessions }
    var selectedSession: Session? {
        get { activity.selectedSession }
        set { activity.selectedSession = newValue }
    }
    var sessionEvents: [SessionEvent] { activity.sessionEvents }
    var showSessionGrouping: Bool {
        get { activity.showSessionGrouping }
        set { activity.showSessionGrouping = newValue }
    }
    var allTrackedFiles: [String] { storage.allTrackedFiles }
    var storageUsed: Int64 { storage.storageUsed }
    var mcpInstalled: Bool {
        integrationHealth.claude.mcpConfigured.isPassingCheck
            || integrationHealth.claude.claudeCodeConfigured.isPassingCheck
            || integrationHealth.codex.mcpAdded.isPassingCheck
    }
    var installError: String? {
        get { integrationHealth.claude.errorDetail }
        set { integrationHealth.claude.errorDetail = newValue }
    }
    var claudeDesktopConfigured: Bool { integrationHealth.claude.mcpConfigured.isPassingCheck }
    var claudeCodeConfigured: Bool { integrationHealth.claude.claudeCodeConfigured.isPassingCheck }
    var codexConfigured: Bool { integrationHealth.codex.mcpAdded.isPassingCheck }
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

    func fileHistory(filePath: String) async -> [SnapshotRecord] { await storage.fileHistory(filePath: filePath) }
    func snapshotData(hash: String) async -> Data? { await storage.snapshotData(hash: hash) }
    func runGarbageCollection() async -> Int { await storage.runGarbageCollection() }
    func runIntegrityCheck() async -> Bool { await storage.runIntegrityCheck() }
    func loadTrackedFiles() async { await storage.loadTrackedFiles() }
    func loadStorageStats() async { await storage.loadStorageStats() }

    func installMCP() {
        do {
            let destinationPath = Self.mcpBinaryPath
            let destinationURL = URL(fileURLWithPath: destinationPath)
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let bundled = Bundle.main.url(forResource: "manifold-mcp", withExtension: nil) {
                if FileManager.default.fileExists(atPath: destinationPath) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: bundled, to: destinationURL)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationPath)
            }
            try ConfigWriter(binaryPath: destinationPath).installAll()
            Task { await integrationHealth.checkAll(force: true) }
        } catch {
            integrationHealth.claude.errorDetail = error.localizedDescription
        }
    }

    func loadSessions() async { await activity.loadSessions() }
    func loadSessionEvents(sessionID: String) async { await activity.loadSessionEvents(sessionID: sessionID) }
    func selectSession(_ session: Session?) async { await activity.selectSession(session) }
    func sessionSummary(session: Session, events: [SessionEvent]) -> String { activity.sessionSummary(session: session, events: events) }
    func refreshGrantState() async { await session.refreshGrantState() }

    func fileVisibilityOverrides(agent: TargetApp) async -> [FileVisibilityOverrideRecord] {
        do {
            return try await runtime.fileVisibilityOverrides(agent: agent)
        } catch {
            logger.error("Failed to load file visibility overrides: \(error.localizedDescription)")
            return []
        }
    }

    func setFileVisibilityOverride(
        agent: TargetApp,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool = false,
        decision: FileVisibilityOverrideDecision
    ) async {
        do {
            try await runtime.setFileVisibilityOverride(
                agent: agent,
                sourceID: sourceID,
                relativePath: relativePath,
                isDirectory: isDirectory,
                decision: decision
            )
        } catch {
            logger.error("Failed to persist file visibility override: \(error.localizedDescription)")
            lastError = "Couldn't update file visibility: \(error.localizedDescription)"
        }
    }

    func clearFileVisibilityOverride(
        agent: TargetApp,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool = false
    ) async {
        do {
            try await runtime.clearFileVisibilityOverride(
                agent: agent,
                sourceID: sourceID,
                relativePath: relativePath,
                isDirectory: isDirectory
            )
        } catch {
            logger.error("Failed to clear file visibility override: \(error.localizedDescription)")
            lastError = "Couldn't reset file visibility: \(error.localizedDescription)"
        }
    }

    func sourceIsInDefaultScope(_ sourceID: String, for agent: TargetApp) -> Bool {
        governance.policy(for: agent)?.allowedSourceIDs.contains(sourceID) == true
    }

    /// Toggle a source's membership in an agent's default scope. Rolls back
    /// the optimistic local mutation if the XPC round-trip fails, so UI
    /// state never silently diverges from runtime truth.
    func setSourceScope(sourceID: String, agent: TargetApp, inScope: Bool) async {
        let currently = sourceIsInDefaultScope(sourceID, for: agent)
        guard currently != inScope else { return }

        mutateScope(agent: agent, sourceID: sourceID, inScope: inScope)

        do {
            if inScope {
                try await runtime.addSource(sourceID, to: agent)
            } else {
                try await runtime.removeSource(sourceID, from: agent)
            }
        } catch {
            logger.error("Failed to update scope for source \(sourceID, privacy: .public) agent \(agent.rawValue, privacy: .public): \(error.localizedDescription)")
            lastError = "Couldn't update sharing: \(error.localizedDescription)"
            mutateScope(agent: agent, sourceID: sourceID, inScope: !inScope)
        }
    }

    private func mutateScope(agent: TargetApp, sourceID: String, inScope: Bool) {
        // Read-modify-write the WHOLE policy struct rather than mutating
        // allowedSourceIDs through optional chaining. @Observable doesn't
        // reliably fire on deep mutations through `?.` on a value-type
        // property — the setter only sees the inner Set change, not the
        // outer claudePolicy / codexPolicy property write that the
        // observation framework wraps. Without the explicit assign-back,
        // FoldersMatrixView's scopeByAgent computed var keeps the stale
        // value and the user sees the checkbox refuse to unselect.
        switch agent {
        case .cowork:
            if var policy = governance.claudePolicy {
                if inScope { policy.allowedSourceIDs.insert(sourceID) }
                else       { policy.allowedSourceIDs.remove(sourceID) }
                governance.claudePolicy = policy
            }
        case .codex:
            if var policy = governance.codexPolicy {
                if inScope { policy.allowedSourceIDs.insert(sourceID) }
                else       { policy.allowedSourceIDs.remove(sourceID) }
                governance.codexPolicy = policy
            }
        }
    }

    func quitManifold() {
        unregisterAgent()
        NSApplication.shared.terminate(nil)
    }

    func registerAgent() {
        diagnostics.record(.runtimeRegistrationAttempted)

        let bundledAgent = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/ManifoldAgent")
        guard FileManager.default.isExecutableFile(atPath: bundledAgent.path) else {
            runtimeLaunchError = "ManifoldAgent is missing from the app bundle, so the runtime cannot start."
            lastError = runtimeLaunchError
            logger.warning("ManifoldAgent not found at \(bundledAgent.path, privacy: .public)")
            diagnostics.record(.runtimeRegistrationFailedHelperMissing)
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: Self.launchAgentPlistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: Self.launchAgentPlist(executablePath: bundledAgent.path),
                format: .xml,
                options: 0
            )
            try data.write(to: Self.launchAgentPlistURL, options: .atomic)

            _ = try? Self.runLaunchctl(arguments: ["bootout", "gui/\(getuid())/\(Self.agentLabel)"])
            let bootstrap = try Self.runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", Self.launchAgentPlistURL.path])
            if bootstrap.exitCode != 0 {
                diagnostics.record(.runtimeRegistrationFailedLaunchctlBootstrap(code: bootstrap.exitCode))
                throw RuntimeRegistrationError(
                    message: bootstrap.output.nilIfEmpty
                    ?? "launchctl bootstrap exited with status \(bootstrap.exitCode)."
                )
            }

            logger.info("ManifoldAgent registered via launchd")
            Task { await verifyRuntimeLaunch() }
        } catch {
            let detail = (error as? RuntimeRegistrationError)?.message ?? error.localizedDescription
            runtimeLaunchError = "Failed to register the Manifold runtime: \(detail)"
            lastError = runtimeLaunchError
            logger.error("Failed to register ManifoldAgent via launchd: \(detail, privacy: .public)")
        }
    }

    func unregisterAgent() {
        _ = try? Self.runLaunchctl(arguments: ["bootout", "gui/\(getuid())/\(Self.agentLabel)"])
    }

    private func verifyRuntimeLaunch() async {
        let attempts = 6
        for attempt in 1...attempts {
            let pingResult = await runtime.ping()
            if pingResult.ok {
                runtimeLaunchError = nil
                if lastError?.contains("runtime") == true || lastError?.contains("ManifoldAgent") == true {
                    lastError = nil
                }
                return
            }
            if attempt < attempts {
                try? await Task.sleep(for: .milliseconds(400))
            }
        }

        runtimeLaunchError = "The Manifold runtime did not respond after launchd registration. Check the launch agent and bundled helper path."
        lastError = runtimeLaunchError
    }

    private struct RuntimeRegistrationError: Error {
        let message: String
    }

    private struct ProcessResult {
        let exitCode: Int32
        let output: String
    }

    static var agentLabel: String {
        ManifoldRuntimeEnvironment.xpcServiceName()
    }

    static var agentPlistName: String {
        "\(agentLabel).plist"
    }

    static var launchAgentPlistURL: URL {
        if let override = ManifoldRuntimeEnvironment.launchAgentPlistURL() {
            return override
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentPlistName)")
    }

    private static func launchAgentPlist(executablePath: String) -> [String: Any] {
        var plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [executablePath],
            "MachServices": [agentLabel: true],
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
        ]
        let environment = ManifoldRuntimeEnvironment.helperEnvironment()
        if !environment.isEmpty {
            plist["EnvironmentVariables"] = environment
        }
        return plist
    }

    @discardableResult
    private static func runLaunchctl(arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            exitCode: process.terminationStatus,
            output: String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    static var storeURL: URL {
        (ManifoldRuntimeEnvironment.appSupportRootURL()
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("Manifold/store")
    }

    static var mcpBinaryPath: String {
        (ManifoldRuntimeEnvironment.appSupportRootURL()
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("Manifold/bin/manifold-mcp")
            .path
    }
}

@Observable
@MainActor
final class PersonalDataOSModel {
    var ledgerEntries: [LedgerEntry] = []
    var ledgerVerification: LedgerVerificationResult?
    var toolCostReport: ToolCostReport?
    var memorySettings = MemorySettings()
    var memoryItems: [MemoryItem] = []
    var memorySources: [MemorySourceSummary] = []
    var skills: [SkillRecord] = []
    var execRuns: [ExecRunRecord] = []
    var capabilityHandles: [ValueHandle] = []
    var graphNodes: [KnowledgeGraphNode] = []
    var fabricationFindings: [FabricationFinding] = []
    var isLoadingLedger = false
    var isLoadingMemory = false
    var isLoadingAgentOS = false
    var lastError: String?

    private var client: (any RuntimeClientProtocol)?

    func configure(client: any RuntimeClientProtocol) {
        self.client = client
    }

    func loadOverview() async {
        await loadLedger()
        await loadMemory()
        await loadAgentOS()
    }

    func loadLedger() async {
        guard let client else { return }
        isLoadingLedger = true
        defer { isLoadingLedger = false }
        do {
            async let entries = client.recentLedgerEntries(limit: 50)
            async let verification = client.verifyLedger()
            async let costReport = client.toolCostReport(limit: 200)
            ledgerEntries = try await entries
            ledgerVerification = try await verification
            toolCostReport = try await costReport
            lastError = nil
        } catch {
            ledgerEntries = []
            ledgerVerification = nil
            toolCostReport = nil
            lastError = error.localizedDescription
            logger.error("Failed to load personal data ledger: \(error.localizedDescription)")
        }
    }

    func loadMemory() async {
        guard let client else { return }
        isLoadingMemory = true
        defer { isLoadingMemory = false }
        do {
            async let settings = client.getMemorySettings()
            async let items = client.listMemory(limit: 100, includeDeleted: false)
            async let sources = client.listMemorySources()
            memorySettings = try await settings
            memoryItems = try await items
            memorySources = try await sources
            lastError = nil
        } catch {
            memorySettings = MemorySettings()
            memoryItems = []
            memorySources = []
            lastError = error.localizedDescription
            logger.error("Failed to load owned memory: \(error.localizedDescription)")
        }
    }

    func updateMemorySettings(amnesiacMode: Bool? = nil, derivedRetentionDays: Int? = nil) async {
        guard let client else { return }
        var updated = memorySettings
        if let amnesiacMode {
            updated.amnesiacMode = amnesiacMode
        }
        if let derivedRetentionDays {
            updated.derivedRetentionDays = derivedRetentionDays
        }
        do {
            memorySettings = try await client.updateMemorySettings(updated)
            await loadMemory()
        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to update memory settings: \(error.localizedDescription)")
        }
    }

    func forgetMemory(_ item: MemoryItem) async {
        guard let client else { return }
        do {
            try await client.forgetMemory(id: item.memoryID)
            await loadMemory()
            await loadLedger()
        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to forget memory \(item.memoryID): \(error.localizedDescription)")
        }
    }

    func loadAgentOS() async {
        guard let client else { return }
        isLoadingAgentOS = true
        defer { isLoadingAgentOS = false }
        do {
            async let loadedSkills = client.listSkills(limit: 50)
            async let loadedRuns = client.recentExecRuns(limit: 50)
            async let loadedHandles = client.listCapabilityHandles(limit: 50)
            async let loadedNodes = client.queryGraphNodes(query: "", limit: 50)
            async let loadedFindings = client.recentFabricationFindings(limit: 50)
            skills = try await loadedSkills
            execRuns = try await loadedRuns
            capabilityHandles = try await loadedHandles
            graphNodes = try await loadedNodes
            fabricationFindings = try await loadedFindings
            lastError = nil
        } catch {
            skills = []
            execRuns = []
            capabilityHandles = []
            graphNodes = []
            fabricationFindings = []
            lastError = error.localizedDescription
            logger.error("Failed to load Agent OS surfaces: \(error.localizedDescription)")
        }
    }

    var activeMemoryCount: Int {
        memoryItems.filter { $0.status == MemoryStatus.active.rawValue }.count
    }

    var hiddenMemoryCount: Int {
        memoryItems.filter {
            $0.status == MemoryStatus.hiddenByScope.rawValue
                || $0.status == MemoryStatus.tombstonedByRevocation.rawValue
                || $0.status == MemoryStatus.expiredByRetention.rawValue
        }.count
    }

    var blockedExecRunCount: Int {
        execRuns.filter {
            $0.status == ExecRunStatus.refused.rawValue
                || $0.status == ExecRunStatus.needsApproval.rawValue
                || $0.status == ExecRunStatus.failed.rawValue
        }.count
    }

    var supportedFindingCount: Int {
        fabricationFindings.filter { $0.status == "supported" }.count
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
