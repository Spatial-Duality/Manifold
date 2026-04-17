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
    let integrationHealth: IntegrationHealthModel

    let runtime: any RuntimeClientProtocol
    private var connectionMonitorTask: Task<Void, Never>?
    private var didAttemptAgentRestart = false

    var menuBarIcon: String { isRuntimeConnected ? "checkmark.shield.fill" : "shield.slash" }

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

        session.configure(client: runtime)
        activity.configure(client: runtime)
        storage.configure(client: runtime)
        mailAccounts.configure(client: runtime)
        mailReview.configure(mailAccounts: mailAccounts)
        governance.configure(client: runtime)
        rules.configure(client: runtime)

        integrationHealth.store = self

        if startServices {
            registerAgent()
            requestNotificationPermission()
            startConnectionMonitor()

            Task {
                await refreshAll(force: true)
                await integrationHealth.checkAll()
            }
        }
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

        consumePendingFinderRequest()

        await activity.loadActivity()
        await activity.loadSessions()
        await session.refreshGrantState()
        await storage.loadStorageStats()
        await storage.loadTrackedFiles()
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

    func chooseSourcePathsFromPicker() -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select folders to protect through Manifold"
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
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

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

                if batch.count >= batchSize {
                    await yield(batch)
                    batch.removeAll(keepingCapacity: true)
                }
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
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

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
            }
        }

        return result
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
        if session.isPreviewing {
            session.preview = nil
            session.previewError = nil
            await session.startSession(
                targetApp: targetApp,
                onError: { [weak self] message in self?.lastError = message }
            )
        } else {
            session.previewError = nil
            await session.computePreview(targetApp: targetApp)
        }
        await refreshAll()
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
        switch agent {
        case .cowork:
            if inScope { governance.claudePolicy?.allowedSourceIDs.insert(sourceID) }
            else       { governance.claudePolicy?.allowedSourceIDs.remove(sourceID) }
        case .codex:
            if inScope { governance.codexPolicy?.allowedSourceIDs.insert(sourceID) }
            else       { governance.codexPolicy?.allowedSourceIDs.remove(sourceID) }
        }
    }

    func quitManifold() {
        unregisterAgent()
        NSApplication.shared.terminate(nil)
    }

    func registerAgent() {
        let bundledAgent = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/ManifoldAgent")
        guard FileManager.default.isExecutableFile(atPath: bundledAgent.path) else {
            runtimeLaunchError = "ManifoldAgent is missing from the app bundle, so the runtime cannot start."
            lastError = runtimeLaunchError
            logger.warning("ManifoldAgent not found at \(bundledAgent.path, privacy: .public)")
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

    static let agentLabel = "com.spatialduality.manifold.runtime"
    static let agentPlistName = "com.spatialduality.manifold.runtime.plist"
    static let launchAgentPlistURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(agentPlistName)")

    private static func launchAgentPlist(executablePath: String) -> [String: Any] {
        [
            "Label": agentLabel,
            "ProgramArguments": [executablePath],
            "MachServices": [agentLabel: true],
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
        ]
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
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Manifold/store")
    }

    static var mcpBinaryPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Manifold/bin/manifold-mcp")
            .path
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
