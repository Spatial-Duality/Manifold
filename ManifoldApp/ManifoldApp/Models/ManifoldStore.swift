// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Darwin
import Security
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
    var runtimeSupervisor = RuntimeSupervisor()
    var dataControlSummary: DataControlSummary?

    /// Whether Claude (cowork) has an active MCP bridge connection to the runtime.
    var isClaudeConnected: Bool { connectedAgents.contains(TargetApp.cowork.rawValue) }
    /// Whether Codex has an active MCP bridge connection to the runtime.
    var isCodexConnected: Bool { connectedAgents.contains(TargetApp.codex.rawValue) }

    var sources: [SourceRecord] = []
    var approvedSources: [String] { sources.filter(\.isResolvedForAccess).map(\.effectiveRootPath) }

    var lastError: String?

    let session: SessionModel
    let activity: ActivityModel
    let storage: StorageModel
    let setup: SetupModel
    let mailAccounts: MailAccountsModel
    let mailReview: MailReviewModel
    let governance: GovernanceModel
    let rules: RulesModel
    let sessionWorkbench: SessionWorkbenchModel
    var integrationHealth: IntegrationHealthModel
    let diagnostics: DiagnosticsModel
    let updater: UpdaterModel?

    var runtime: any RuntimeClientProtocol
    private let defaults: UserDefaults
    let canStartRuntimeServices: Bool
    private let gatesRuntimeStartup: Bool
    private var runtimeServicesStarted = false

    static let demoModeDefaultsKey = "manifold.demoMode"
    static let demoWarningDefaultsKey = "manifold.demoMode.showWarning"
    static let autoMirrorDefaultsKey = "manifold.autoMirrorSharing"
    static let finderIntegrationTagsEnabledDefaultsKey = "manifold.finderIntegration.tagsEnabled"
    static let finderIntegrationTagNameDefaultsKey = "manifold.finderIntegration.tagName"

    var isDemoModeEnabled: Bool {
        didSet { defaults.set(isDemoModeEnabled, forKey: Self.demoModeDefaultsKey) }
    }

    var showDemoWarning: Bool {
        didSet { defaults.set(showDemoWarning, forKey: Self.demoWarningDefaultsKey) }
    }

    /// When on, every per-agent sharing change (source add/remove + per-file
    /// override write/clear) fans out to the other assistant so both AIs
    /// stay in lockstep. Off by default — the user opts in. Existing
    /// divergence is *not* auto-resolved; users run the explicit "Mirror…"
    /// sheet for that.
    var isAutoMirrorEnabled: Bool {
        didSet { defaults.set(isAutoMirrorEnabled, forKey: Self.autoMirrorDefaultsKey) }
    }

    var finderIntegrationTagsEnabled: Bool {
        didSet {
            defaults.set(finderIntegrationTagsEnabled, forKey: Self.finderIntegrationTagsEnabledDefaultsKey)
            writeFinderIntegrationSnapshot()
            syncFinderIntegrationSettingsToRuntime()
        }
    }

    var finderIntegrationTagName: String {
        didSet {
            let trimmed = finderIntegrationTagName.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed.isEmpty ? "Manifold" : trimmed, forKey: Self.finderIntegrationTagNameDefaultsKey)
            writeFinderIntegrationSnapshot()
            syncFinderIntegrationSettingsToRuntime()
        }
    }

    /// Active Focus (preset_id) per agent. Tracked in-memory and mirrored
    /// to UserDefaults so a relaunch restores the active selection
    /// immediately while the runtime catches up. Mutated by
    /// `setActiveFocus` and the launch-default routing in
    /// `startDefaultSessionIfNeeded`. Empty string for an agent means
    /// "no Focus active" (the user is on the agent's standing scope).
    var activeFocusID: [TargetApp: String] = [:] {
        didSet {
            let serialized = activeFocusID.reduce(into: [String: String]()) { acc, kv in
                acc[kv.key.rawValue] = kv.value
            }
            defaults.set(serialized, forKey: Self.activeFocusDefaultsKey)
        }
    }

    /// All Focuses (presets) the user can pick from. Refreshed lazily —
    /// the sidebar calls `refreshFocuses()` on open to stay current
    /// without polling. Sorted newest-first by updated_at.
    var availableFocuses: [AccessPresetRecord] = []

    /// Which Focus the editor pane is currently bound to, per agent.
    /// `nil` (or absent key) = editor binds to the active Focus (the
    /// common case — edits flow to the live grant). When a non-active
    /// Focus is selected for editing (sidebar selection), this pins the
    /// editor to that Focus's preset row instead — edits write to the
    /// preset only, leaving live state untouched. Lets the user create
    /// "Q4 reports" while Default keeps running.
    var editingFocusID: [TargetApp: String] = [:]

    /// preset_id of the Focus marked default-at-launch per agent. Cached
    /// alongside `availableFocuses` so the chip can render a "default" dot
    /// without an extra round trip. nil = no default for that agent.
    var defaultLaunchFocusID: [TargetApp: String?] = [:]

    /// Resolves the Focus the editor should currently bind to for an
    /// agent. Falls back to the active Focus when the user hasn't
    /// explicitly picked a different one to edit.
    func resolvedEditingFocusID(for agent: TargetApp) -> String? {
        editingFocusID[agent] ?? activeFocusID[agent]
    }

    static let activeFocusDefaultsKey = "manifold.activeFocusByAgent"

    var demoMCPInstallStatus: String?

    // Cross-cohort properties: declared `internal` so the
    // ManifoldStore+ConnectionState extension (in a sibling file) can
    // access them. Module-internal — no visibility leak outside the app
    // target.
    var connectionMonitorTask: Task<Void, Never>?
    var xpcConnectionObserver: NSObjectProtocol?
    var didAttemptAgentRestart = false
    var didAttemptDefaultSessionStart = false
    var suppressDefaultSessionUntilNextLaunch = false

    /// Per-agent connection events, newest first. Capped at 50 — older
    /// events fall off so the in-memory list stays bounded. Surfaced in
    /// the Activity timeline; not persisted across launches.
    var connectionEvents: [ConnectionEvent] = []
    var lastObservedConnectedAgents: Set<String> = []
    let connectionAlerts: any ConnectionAlertPresenting = SystemConnectionAlertPresenter()
    static let connectionEventCap = 50

    /// Drives the menu bar icon. Replaces the previous SF-Symbol-name string
    /// so the menu bar shows the Manifold mark with a small state badge
    /// instead of a generic Apple shield. Active session and tracked-edit
    /// states are deliberately badge-less — the mark's presence is the
    /// signal, less is more.
    var menuBarBadgeState: MenuBarBadgeState {
        guard isRuntimeConnected else { return .disconnected }
        if (dataControlSummary?.pendingApprovalCount ?? governance.pendingApprovals.count) > 0 {
            return .approvalsPending
        }
        if dataControlSummary?.agents.allSatisfy(\.isPaused) == true {
            return .paused
        }
        return .clear
    }

    init(
        runtime: any RuntimeClientProtocol = AppRuntimeClient(),
        integrationHealth: IntegrationHealthModel = IntegrationHealthModel(),
        startServices: Bool = true,
        defaults: UserDefaults = AppTestEnvironment.userDefaults(),
        gateRuntimeStartup: Bool? = nil
    ) {
        self.defaults = defaults
        self.canStartRuntimeServices = startServices
        self.gatesRuntimeStartup = gateRuntimeStartup ?? startServices
        self.runtime = runtime
        self.integrationHealth = integrationHealth
        isDemoModeEnabled = defaults.bool(forKey: Self.demoModeDefaultsKey)
        showDemoWarning = defaults.object(forKey: Self.demoWarningDefaultsKey) as? Bool ?? true
        isAutoMirrorEnabled = defaults.bool(forKey: Self.autoMirrorDefaultsKey)
        finderIntegrationTagsEnabled = defaults.bool(forKey: Self.finderIntegrationTagsEnabledDefaultsKey)
        finderIntegrationTagName = (
            defaults.string(forKey: Self.finderIntegrationTagNameDefaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        ).flatMap { $0.isEmpty ? nil : $0 } ?? "Manifold"
        if let stored = defaults.dictionary(forKey: Self.activeFocusDefaultsKey) as? [String: String] {
            var restored: [TargetApp: String] = [:]
            for (rawAgent, presetID) in stored {
                if let agent = TargetApp(rawValue: rawAgent), !presetID.isEmpty {
                    restored[agent] = presetID
                }
            }
            activeFocusID = restored
        }
        // Migrate the old "Welcome to Work" coachmark dismissal flag forward to
        // the renamed "Welcome to Focus" key so users who already dismissed it
        // don't see it return after the rename.
        if defaults.object(forKey: "focus.coachmark.dismissed") == nil,
           defaults.bool(forKey: "work.coachmark.dismissed") {
            defaults.set(true, forKey: "focus.coachmark.dismissed")
            defaults.removeObject(forKey: "work.coachmark.dismissed")
        }
        session = SessionModel()
        activity = ActivityModel()
        storage = StorageModel()
        setup = SetupModel(defaults: defaults)
        mailAccounts = MailAccountsModel()
        mailReview = MailReviewModel()
        governance = GovernanceModel()
        rules = RulesModel()
        sessionWorkbench = SessionWorkbenchModel()
        diagnostics = DiagnosticsModel()
        // Sparkle is only meaningful when the bundle has a public EdDSA key
        // — i.e. an official build. In source builds where the key is empty
        // we skip the controller entirely; Help -> Check for Updates and the
        // consent toggle no-op cleanly.
        if startServices, Self.sparkleConfigured() {
            updater = UpdaterModel(diagnostics: diagnostics)
        } else {
            updater = nil
        }

        configureModels(client: runtime)
        mailReview.configure(mailAccounts: mailAccounts)

        integrationHealth.store = self

        if shouldStartRuntimeServicesAtLaunch {
            startRuntimeServicesIfNeeded(forceRefresh: true, startDefaultSession: true)
        }
    }

    private var shouldStartRuntimeServicesAtLaunch: Bool {
        guard canStartRuntimeServices, !isDemoModeEnabled else { return false }
        guard gatesRuntimeStartup else { return true }
        return setup.hasCompletedOnboarding && setup.runtimeEnabled
    }

    func enableRuntime() {
        setup.runtimeEnabled = true
        startRuntimeServicesIfNeeded(forceRefresh: true, startDefaultSession: true)
    }

    private func startRuntimeServicesIfNeeded(
        forceRefresh: Bool,
        startDefaultSession: Bool = false
    ) {
        guard canStartRuntimeServices else {
            if forceRefresh {
                Task { await refreshAll(force: true) }
            }
            return
        }
        guard !isDemoModeEnabled else {
            if forceRefresh {
                Task {
                    await refreshAll(force: true)
                    await integrationHealth.checkAll()
                }
            }
            return
        }
        guard !runtimeServicesStarted else {
            if forceRefresh {
                Task {
                    await refreshAll(force: true)
                    if startDefaultSession {
                        await maybeStartDefaultSessionOnLaunch()
                    }
                    await integrationHealth.checkAll()
                }
            }
            return
        }

        runtimeServicesStarted = true

        // Diagnostics: record launch + detect any unexpected exit of the
        // previous agent run before we start the new one.
        diagnostics.record(.appLaunch)
        diagnostics.checkAgentExitState()

        // Clean stale pending Keychain credential entries left over from a
        // previous crash mid-IMAP-handoff. This does not read mail account
        // credentials and is safe before Mail has been opened.
        KeychainMailSecretStore().sweepStalePendingCredentials()

        syncInstalledMCPHelperIfNeeded()
        registerAgent()
        requestNotificationPermission()
        startConnectionMonitor()
        startXPCConnectionObserver()

        // Sparkle: thread the agent shutdown into the updater so the app
        // and agent versions never drift across an auto-update.
        updater?.agentShutdown = { [weak self] in self?.unregisterAgent() }
        startUpdaterConsentBridge()

        if forceRefresh {
            Task {
                await refreshAll(force: true)
                if startDefaultSession {
                    await maybeStartDefaultSessionOnLaunch()
                }
                await integrationHealth.checkAll()
            }
        }
    }

    private func configureModels(client: any RuntimeClientProtocol) {
        session.configure(client: client)
        activity.configure(client: client)
        storage.configure(client: client)
        mailAccounts.configure(client: client)
        mailReview.configure(mailAccounts: mailAccounts)
        governance.configure(client: client, diagnostics: diagnostics)
        rules.configure(client: client)
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

    func setDemoModeEnabled(_ enabled: Bool) {
        guard enabled != isDemoModeEnabled else { return }
        isDemoModeEnabled = enabled
        if enabled {
            showDemoWarning = true
        }
        applyRuntimeForCurrentMode()
    }

    func resetDemoData() {
        guard isDemoModeEnabled else { return }
        applyRuntimeForCurrentMode()
    }

    private func applyRuntimeForCurrentMode() {
        let client: any RuntimeClientProtocol
        if isDemoModeEnabled {
            client = DemoRuntimeClient.anthropologie()
            integrationHealth = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: .demo))
        } else {
            client = AppRuntimeClient()
            integrationHealth = IntegrationHealthModel()
        }
        runtime = client
        integrationHealth.store = self
        configureModels(client: client)
        if shouldStartRuntimeServicesAtLaunch {
            startRuntimeServicesIfNeeded(forceRefresh: false, startDefaultSession: true)
        }
        Task {
            await refreshAll(force: true)
            await integrationHealth.checkAll()
        }
    }

    func refreshAll(force: Bool = false) async {
        guard !gatesRuntimeStartup || runtimeServicesStarted || isDemoModeEnabled else {
            isRuntimeConnected = false
            isConnected = false
            connectedAgent = nil
            connectedAgents = []
            dataControlSummary = nil
            if force, setup.runtimeEnabled {
                lastError = "Local runtime is starting. Try again in a moment."
            } else if !setup.runtimeEnabled {
                lastError = nil
            }
            return
        }

        let pingResult = await runtime.ping()
        isRuntimeConnected = pingResult.ok
        isConnected = pingResult.ok

        guard pingResult.ok else {
            _ = runtimeSupervisor.markDegraded(issue: "runtime_unavailable")
            connectedAgent = nil
            connectedAgents = []
            dataControlSummary = nil
            if force {
                lastError = runtimeLaunchError ?? "Unable to connect to the Manifold runtime."
            }
            return
        }

        runtimeLaunchError = nil
        _ = runtimeSupervisor.markHealthy()

        // XPC version check: auto-restart agent on mismatch (once per app launch)
        let appVersion = Bundle.main.shortVersionString
        if let agentVersion = pingResult.agentVersion, agentVersion != appVersion, !didAttemptAgentRestart {
            didAttemptAgentRestart = true
            logger.notice("Agent version \(agentVersion) != app version \(appVersion). Restarting agent.")
            diagnostics.record(.versionMismatchRestart(appVersion: appVersion, runtimeVersion: agentVersion))
            _ = runtimeSupervisor.markRestarting(reason: .versionMismatch)
            diagnostics.record(.runtimeRestartStarted)
            unregisterAgent()
            registerAgent()
            try? await Task.sleep(for: .seconds(1))
            let retry = await runtime.ping()
            isRuntimeConnected = retry.ok
            isConnected = retry.ok
            guard retry.ok else {
                lastError = runtimeLaunchError ?? "Unable to reconnect to the Manifold runtime after restarting it."
                _ = runtimeSupervisor.markFailed(issue: "version_mismatch_restart_failed")
                diagnostics.record(.runtimeRestartFailed)
                return
            }
            if let retryAgentVersion = retry.agentVersion, retryAgentVersion != appVersion {
                lastError = "The Manifold runtime is still version \(retryAgentVersion) after restart, but the app is \(appVersion)."
                _ = runtimeSupervisor.markFailed(issue: "version_mismatch_unresolved")
                diagnostics.record(.runtimeRestartFailed)
                return
            }
            _ = runtimeSupervisor.markHealthy()
            diagnostics.record(.runtimeRestartSucceeded)
        }

        do {
            let snapshot = try await runtime.runtimeStatusSnapshot()
            sources = Self.visibleSources(from: snapshot.sources)
            governance.claudePolicy = snapshot.claudePolicy
            governance.codexPolicy = snapshot.codexPolicy
            governance.claudeEmailGovernance = snapshot.claudeEmailGovernance
            governance.codexEmailGovernance = snapshot.codexEmailGovernance
            governance.activeSessionRecord = snapshot.activeSession
            governance.claudeCoverage = snapshot.agentCoverages.first { $0.agent == TargetApp.cowork.rawValue }
            governance.codexCoverage = snapshot.agentCoverages.first { $0.agent == TargetApp.codex.rawValue }
            governance.coverageEvents = snapshot.coverageEvents
            recordConnectionTransition(newConnectedAgents: Set(snapshot.connectedAgents))
            connectedAgents = snapshot.connectedAgents
            // Derive connectedAgent from actual runtime data, not heuristics
            connectedAgent = snapshot.connectedAgents.first
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to refresh runtime status: \(error.localizedDescription)")
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

        await refreshFocuses()
        syncFinderIntegrationSettingsToRuntime()
        writeFinderIntegrationSnapshot()
        await consumePendingFinderCommands()

        await activity.loadActivity()
        await activity.loadSessions()
        await session.refreshGrantState()
        await storage.loadStorageStats()
        await storage.loadTrackedFiles()
        await rules.load()
    }

    private func maybeStartDefaultSessionOnLaunch() async {
        guard !didAttemptDefaultSessionStart else { return }
        didAttemptDefaultSessionStart = true
        await syncRuntimeSessionAccessMode()
        await startDefaultSessionIfNeeded()
    }

    private func startDefaultSessionIfNeeded() async {
        guard sessionStartupMode == .defaultSession else { return }
        guard !suppressDefaultSessionUntilNextLaunch else { return }
        guard session.activeGrant == nil else { return }

        // Focus-aware launch: if a Focus is marked default-at-launch for
        // the configured agent, activate it (which starts a new grant
        // with that Focus's saved scope + settings). Falls through to the
        // legacy "manual draft" path when no default Focus is set.
        if let client = focusClient,
           let preset = try? await client.defaultPresetForLaunch(agent: defaultSessionAgent) {
            await setActiveFocus(presetID: preset.presetID, targetApp: defaultSessionAgent)
            return
        }

        var draft = SessionDraft()
        draft.name = "Default"
        draft.agents = [defaultSessionAgent]
        draft.usesExplicitFileSelection = false
        try? await startGatewaySession(draft: draft)
    }

    private func syncRuntimeSessionAccessMode() async {
        let mode: SessionAccessMode = sessionStartupMode == .defaultSession
            ? .defaultSession
            : .manualRequiresSession
        do {
            try await runtime.setSessionAccessMode(mode)
        } catch {
            logger.error("Failed to sync session access mode: \(error.localizedDescription)")
        }
    }

    // Connection-state cohort moved to ManifoldStore+ConnectionState.swift.
    // Cross-file extensions can't see `private`, so the supporting stored
    // properties were promoted to module-internal in the type body above.

    private func consumePendingFinderRequest() {
        let requestURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Manifold/finder-sync-request.json")
        guard let data = try? Data(contentsOf: requestURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paths = payload["paths"] as? [String] else {
            return
        }

        for path in paths {
            if !sources.contains(where: { $0.originalRootPath == path || $0.effectiveRootPath == path }) {
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
                let bookmark = try? SourceResolver.bookmarkDataBase64(for: URL(fileURLWithPath: path))
                _ = try await runtime.addSource(path: path, displayName: folderName, bookmarkDataBase64: bookmark)
                await loadSources()
            } catch {
                logger.error("Failed to add source \(folderName): \(error.localizedDescription)")
                lastError = "Failed to add \"\(folderName)\": \(error.localizedDescription)"
            }
        }
    }

    func removeSource(path: String) {
        Task {
            guard let source = sources.first(where: { $0.originalRootPath == path || $0.effectiveRootPath == path }) else { return }
            await removeSource(sourceID: source.sourceID)
        }
    }

    func removeSource(sourceID: String) async {
        do {
            try await runtime.removeSource(sourceID: sourceID)
            await loadSources()
            await refreshAll()
        } catch {
            logger.error("Failed to remove source: \(error.localizedDescription)")
            lastError = "Failed to remove source"
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

        Task {
            for path in filePaths {
                await addSourceForSingleFile(URL(fileURLWithPath: path))
            }
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

    func removeSources(sourceIDs: Set<String>) {
        Task {
            for sourceID in sourceIDs {
                await removeSource(sourceID: sourceID)
            }
        }
    }

    func repairSourceFromPicker(sourceID: String) {
        guard let source = sources.first(where: { $0.sourceID == sourceID }) else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = source.sourceKind == .file
        panel.canChooseDirectories = source.sourceKind == .folder
        panel.allowsMultipleSelection = false
        panel.message = "Locate \(source.displayName)"
        if panel.runModal() == .OK, let url = panel.urls.first {
            Task { await repairSource(sourceID: sourceID, url: url) }
        }
    }

    func repairSource(sourceID: String, url: URL) async {
        do {
            let resolved = url.standardizedFileURL
            let bookmark = try? SourceResolver.bookmarkDataBase64(for: resolved)
            let record = try await runtime.repairSource(
                sourceID: sourceID,
                path: resolved.path,
                displayName: resolved.lastPathComponent,
                bookmarkDataBase64: bookmark
            )
            if let index = sources.firstIndex(where: { $0.sourceID == sourceID }) {
                sources[index] = record
            }
            await loadSources()
            await refreshAll()
        } catch {
            logger.error("Failed to repair source: \(error.localizedDescription)")
            lastError = "Couldn't reconnect source: \(error.localizedDescription)"
        }
    }

    /// File URLs resolve to the containing folder; existing sources are
    /// returned without re-adding so callers can chain follow-up overrides.
    @discardableResult
    func addSourceFromURL(_ url: URL) async -> SourceRecord? {
        let resolved = resolvedFolderURL(for: url)
        let path = resolved.path
        if let existing = sources.first(where: { $0.originalRootPath == path || $0.effectiveRootPath == path }) {
            return existing
        }
        guard isRuntimeConnected else {
            lastError = "Cannot add \"\(resolved.lastPathComponent)\" — runtime is not connected. Check that ManifoldAgent is running."
            return nil
        }
        do {
            let bookmark = try? SourceResolver.bookmarkDataBase64(for: resolved)
            let record = try await runtime.addSource(
                path: path,
                displayName: resolved.lastPathComponent,
                bookmarkDataBase64: bookmark
            )
            await loadSources()
            return record
        } catch {
            logger.error("Failed to add source \(resolved.lastPathComponent): \(error.localizedDescription)")
            lastError = "Failed to add \"\(resolved.lastPathComponent)\": \(error.localizedDescription)"
            return nil
        }
    }

    /// Adds the parent folder but applies a default-deny root override plus
    /// an explicit allow for the chosen file. This keeps future siblings
    /// hidden without inventing a second single-file source model.
    func addSourceForSingleFile(_ fileURL: URL) async {
        let parent = fileURL.deletingLastPathComponent()
        guard let source = await addSourceFromURL(parent) else { return }

        let activeAgents = AgentMeta.connected(from: connectedAgents)
        guard !activeAgents.isEmpty else { return }
        let relativePath = fileURL.lastPathComponent

        let batch = activeAgents.flatMap { agent in
            [
                FileVisibilityOverrideRecord(
                    agent: agent,
                    sourceID: source.sourceID,
                    relativePath: "",
                    isDirectory: true,
                    decision: .deny
                ),
                FileVisibilityOverrideRecord(
                    agent: agent,
                    sourceID: source.sourceID,
                    relativePath: relativePath,
                    isDirectory: false,
                    decision: .allow
                ),
            ]
        }

        // Bulk endpoint is on the concrete AppRuntimeClient only; loop
        // through the per-record protocol API for fixture clients.
        if let client = runtime as? AppRuntimeClient {
            do {
                try await client.setManyFileVisibilityOverrides(batch)
            } catch {
                logger.error("Single-file drop override failed: \(error.localizedDescription)")
                lastError = "Added folder but couldn't restrict it to the selected file: \(error.localizedDescription)"
            }
            return
        }
        for record in batch {
            do {
                try await runtime.setFileVisibilityOverride(
                    agent: record.agent,
                    sourceID: record.sourceID,
                    relativePath: record.relativePath,
                    isDirectory: record.isDirectory,
                    decision: record.decision
                )
            } catch {
                logger.error("Single-file drop override failed for \(record.relativePath): \(error.localizedDescription)")
                lastError = "Added folder but couldn't restrict it to the selected file: \(error.localizedDescription)"
                return
            }
        }
    }

    /// True for files and symlinks; false for directories or non-existent paths.
    func dropTargetIsFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && !isDir.boolValue
    }

    private func resolvedFolderURL(for url: URL) -> URL {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists, isDir.boolValue { return url }
        return url.deletingLastPathComponent()
    }

    func loadSources() async {
        do {
            // `removeSource` is a soft delete (status='removed') that
            // preserves the audit trail. Removed sources must not appear
            // in any UI surface — filtering here keeps every consumer of
            // `store.sources` consistent without sprinkling the check
            // through the views.
            sources = Self.visibleSources(from: try await runtime.listSources())
        } catch {
            logger.error("Failed to load sources: \(error.localizedDescription)")
        }
    }

    private nonisolated static func visibleSources(from sources: [SourceRecord]) -> [SourceRecord] {
        sources.filter { !$0.isRemoved }
    }

    func enumerateSourceFiles() async -> [SourceFile] {
        let activeSources = Self.dedupedByPath(sources.filter { $0.isResolvedForAccess && !$0.isRemoved })
        return await Task.detached(priority: .userInitiated) {
            Self.walkSourceFiles(sources: activeSources)
        }.value
    }

    func enumerateSourceFilesProgressively(batchSize: Int = 200) -> AsyncStream<[SourceFile]> {
        let activeSources = Self.dedupedByPath(sources.filter { $0.isResolvedForAccess && !$0.isRemoved })
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

    /// Older "ws-" workspaces and newer "src-" sources can both point at
    /// the same folder — listSources returns both rows, the file walker
    /// emits each file twice, and SwiftUI's Table logs the
    /// duplicate-ID warning ("undefined results"). Dedupe on the actual
    /// path so each file is yielded once. Order is preserved so the
    /// most recently updated record wins, matching listSources's sort.
    private nonisolated static func dedupedByPath(_ sources: [SourceRecord]) -> [SourceRecord] {
        var seen: Set<String> = []
        var result: [SourceRecord] = []
        result.reserveCapacity(sources.count)
        for source in sources where seen.insert(source.effectiveRootPath).inserted {
            result.append(source)
        }
        return result
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
            let root = URL(fileURLWithPath: source.effectiveRootPath)
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
                        canonicalPath: "\(source.canonicalMountName)/\(relativePath)",
                        relativePath: relativePath,
                        sourceName: source.displayName,
                        sourceID: source.sourceID,
                        fileExtension: url.pathExtension.lowercased(),
                        sizeBytes: values.fileSize ?? 0,
                        modifiedDate: values.contentModificationDate ?? .distantPast
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
            let root = URL(fileURLWithPath: source.effectiveRootPath)
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
                    canonicalPath: "\(source.canonicalMountName)/\(relativePath)",
                    relativePath: relativePath,
                    sourceName: source.displayName,
                    sourceID: source.sourceID,
                    fileExtension: url.pathExtension.lowercased(),
                    sizeBytes: values.fileSize ?? 0,
                    modifiedDate: values.contentModificationDate ?? .distantPast
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
        if DemoFileCatalog.isDemoSource(source) {
            return DemoFileCatalog.files(for: source)
        }

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

        let root = URL(fileURLWithPath: source.effectiveRootPath, isDirectory: true)
        return relativePaths.map { relativePath in
            let url = root.appendingPathComponent(relativePath)
            return SourceFile(
                name: url.lastPathComponent,
                path: url.path,
                canonicalPath: "\(source.canonicalMountName)/\(relativePath)",
                relativePath: relativePath,
                sourceName: source.displayName,
                sourceID: source.sourceID,
                fileExtension: url.pathExtension.lowercased(),
                sizeBytes: 0,
                modifiedDate: Date()
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
                        canonicalPath: relativePath,
                        relativePath: relativePath,
                        sourceName: mount.mountName,
                        sourceID: mount.sourceID,
                        fileExtension: url.pathExtension.lowercased(),
                        sizeBytes: values.fileSize ?? 0,
                        modifiedDate: values.contentModificationDate ?? .distantPast
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
        try? await startGatewaySession(draft: draft)
    }

    func endSession() async {
        let endingGrantID = session.activeGrant?.grantID
        let endingWasDefault = session.activeGrant?.summaryFraming == "Default"
        await session.endSession(
            onError: { [weak self] message in self?.lastError = message },
            onConflict: { [weak self] count in self?.lastError = "\(count) conflict(s) while ending the session. Check activity for details." }
        )
        await refreshAll()
        if let endingGrantID {
            session.lastCompletedSession = activity.sessions.first(where: { $0.id == endingGrantID })
        }
        if endingWasDefault {
            suppressDefaultSessionUntilNextLaunch = true
        } else {
            await startDefaultSessionIfNeeded()
        }
    }

    func stopAllSessions() async {
        suppressDefaultSessionUntilNextLaunch = true
        await endSession()
    }

    func defaultSourceIDs(for agent: TargetApp) -> Set<String> {
        governance.policy(for: agent)?.allowedSourceIDs ?? []
    }

    func connectedOrDefaultAgents() -> [TargetApp] {
        let agents = connectedAgents.compactMap { TargetApp(rawValue: $0) }
        return agents.isEmpty ? [.cowork, .codex] : agents
    }

    func beginSessionPreload(agent: TargetApp? = nil, baseMode: PreloadBaseMode = .buildOnDefault) {
        let resolvedAgent = agent ?? defaultSessionAgent
        sessionWorkbench.newPreload(
            agent: resolvedAgent,
            baseMode: baseMode,
            defaultSourceIDs: defaultSourceIDs(for: resolvedAgent)
        )
    }

    func clearSessionPreload() {
        sessionWorkbench.clearPreload()
    }

    func setPreloadAgent(_ agent: TargetApp) {
        sessionWorkbench.setAgent(agent, defaultSourceIDs: defaultSourceIDs(for: agent))
    }

    func setPreloadBaseMode(_ baseMode: PreloadBaseMode) {
        guard let preload = sessionWorkbench.preload else { return }
        sessionWorkbench.setBaseMode(baseMode, defaultSourceIDs: defaultSourceIDs(for: preload.agent))
    }

    func setPreloadSource(sourceID: String, included: Bool) {
        guard let preload = sessionWorkbench.preload else { return }
        sessionWorkbench.setSource(
            sourceID,
            included: included,
            defaultSourceIDs: defaultSourceIDs(for: preload.agent)
        )
    }

    func setPreloadEmail(emailID: String, included: Bool) {
        sessionWorkbench.setEmail(emailID, included: included)
    }

    func setPreloadEmails(emailIDs: Set<String>, included: Bool) {
        sessionWorkbench.setEmails(emailIDs, included: included)
    }

    func clearPreloadEmails() {
        sessionWorkbench.clearEmails()
    }

    func loadSessionTemplates() async {
        guard !sessionWorkbench.isLoadingTemplates else { return }
        sessionWorkbench.isLoadingTemplates = true
        defer { sessionWorkbench.isLoadingTemplates = false }
        do {
            var seen: Set<String> = []
            var templates: [AccessPresetRecord] = []
            for agent in connectedOrDefaultAgents() {
                for template in try await runtime.accessTemplates(for: agent) where seen.insert(template.presetID).inserted {
                    templates.append(template)
                }
            }
            sessionWorkbench.templates = templates.sorted {
                if $0.updatedAt == $1.updatedAt { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return $0.updatedAt > $1.updatedAt
            }
            sessionWorkbench.lastError = nil
        } catch {
            sessionWorkbench.lastError = "Couldn't load sessions: \(error.localizedDescription)"
        }
    }

    func loadSessionTemplate(_ template: AccessPresetRecord) async {
        do {
            let snapshot = try await runtime.loadAccessTemplate(presetID: template.presetID)
            sessionWorkbench.loadPreload(snapshot: snapshot, fallbackAgent: template.targetApp ?? defaultSessionAgent)
            sessionWorkbench.lastError = nil
        } catch {
            sessionWorkbench.lastError = "Couldn't load \(template.name): \(error.localizedDescription)"
        }
    }

    func saveSessionPreload() async {
        guard let preload = sessionWorkbench.preload else { return }
        guard let name = preload.trimmedName else {
            sessionWorkbench.lastError = "Name the session before saving it."
            return
        }
        let defaultIDs = defaultSourceIDs(for: preload.agent)
        let sourceScopes = preload.effectiveSourceIDs(defaultSourceIDs: defaultIDs)
            .sorted()
            .map { FileSelectionScope(sourceID: $0, relativePath: "", isDirectory: true) }
        sessionWorkbench.isSaving = true
        defer { sessionWorkbench.isSaving = false }
        do {
            let saved = try await runtime.saveAccessTemplate(
                presetID: preload.presetID,
                name: name,
                targetApp: preload.agent,
                fileScopes: sourceScopes,
                emailIDs: Array(preload.selectedEmailIDs).sorted()
            )
            var updated = preload
            updated.presetID = saved.presetID
            updated.name = saved.name
            sessionWorkbench.preload = updated
            sessionWorkbench.lastMessage = "Saved \(saved.name)."
            sessionWorkbench.lastError = nil
            await loadSessionTemplates()
        } catch {
            sessionWorkbench.lastError = "Couldn't save session: \(error.localizedDescription)"
        }
    }

    func activateSessionPreload() async {
        guard let preload = sessionWorkbench.preload else { return }
        let defaultIDs = defaultSourceIDs(for: preload.agent)
        let sourceIDs = preload.effectiveSourceIDs(defaultSourceIDs: defaultIDs)
        var draft = SessionDraft()
        draft.name = preload.trimmedName ?? "\(displayName(for: preload.agent)) session"
        draft.agents = [preload.agent]
        draft.usesExplicitFileSelection = true
        draft.selectedSourceIDs = sourceIDs
        draft.selectedEmailIDs = preload.selectedEmailIDs
        draft.requestDetailOverride = preload.requestDetailOverride
        draft.allowFileMemory = preload.allowFileMemory
        sessionWorkbench.isActivating = true
        defer { sessionWorkbench.isActivating = false }
        do {
            try await startGatewaySession(draft: draft)
            suppressDefaultSessionUntilNextLaunch = false
            sessionWorkbench.lastMessage = "Activated \(draft.name)."
            sessionWorkbench.lastError = nil
        } catch {
            sessionWorkbench.lastError = "Couldn't activate session: \(error.localizedDescription)"
        }
    }

    /// Apply a session-scoped request-detail override to the active
    /// grant. This deliberately does not rewrite the agent's persistent
    /// policy; MCP reads the active grant first when validating intent.
    func applyRequestDetailOverride(_ level: AccessRecordingLevel, for agent: TargetApp) async {
        guard let grant = session.activeGrant,
              TargetApp(rawValue: grant.targetApp) == agent else {
            return
        }
        do {
            let updated = try await runtime.updateGrantRequestDetailLevel(grantID: grant.grantID, level: level)
            session.activeGrant = updated
            await refreshAll()
        } catch {
            lastError = "Couldn't update session request detail: \(error.localizedDescription)"
        }
    }

    func clearRequestDetailOverride(for agent: TargetApp) async {
        guard let grant = session.activeGrant,
              TargetApp(rawValue: grant.targetApp) == agent else {
            return
        }
        do {
            let updated = try await runtime.updateGrantRequestDetailLevel(grantID: grant.grantID, level: nil)
            session.activeGrant = updated
            await refreshAll()
        } catch {
            lastError = "Couldn't clear session request detail: \(error.localizedDescription)"
        }
    }

    /// True when the active session has a request-detail override in
    /// effect for the given agent. Used by the UI so it can label the
    /// picker as session-scoped vs agent-default.
    func hasActiveRequestDetailOverride(for agent: TargetApp) -> Bool {
        guard let grant = session.activeGrant,
              TargetApp(rawValue: grant.targetApp) == agent else {
            return false
        }
        return grant.sessionRequestDetailLevel != nil
    }

    /// Apply the session-scoped file-memory query permission. Memory
    /// capture remains automatic; this only controls whether the active
    /// agent may query prior memory for the session's file scope.
    func applyFileMemoryAccess(_ enabled: Bool, for agent: TargetApp) async {
        guard let grant = session.activeGrant,
              TargetApp(rawValue: grant.targetApp) == agent else {
            return
        }
        do {
            let updated = try await runtime.updateGrantMemoryAccess(grantID: grant.grantID, enabled: enabled)
            session.activeGrant = updated
            await refreshAll()
        } catch {
            lastError = "Couldn't update file memory access: \(error.localizedDescription)"
        }
    }

    func hasActiveFileMemoryAccess(for agent: TargetApp) -> Bool {
        guard let grant = session.activeGrant,
              TargetApp(rawValue: grant.targetApp) == agent else {
            return false
        }
        return grant.memoryAccessEnabled
    }

    /// Effective request-detail level for the given agent — the
    /// session-scoped override if one is in effect, otherwise the
    /// agent's persistent default.
    func effectiveRequestDetail(for agent: TargetApp) -> AccessRecordingLevel {
        if let grant = session.activeGrant,
           TargetApp(rawValue: grant.targetApp) == agent,
           let level = grant.sessionRequestDetailLevel {
            return level
        }
        return governance.policy(for: agent)?.accessRecordingLevel ?? .lightweight
    }

    func displayName(for agent: TargetApp) -> String {
        switch agent {
        case .cowork: return "Claude"
        case .codex: return "Codex"
        }
    }

    func restartRuntimeHelper() async {
        await restartRuntimeHelper(reason: .manual)
    }

    func restartRuntimeHelper(reason: RuntimeSupervisorRestartReason) async {
        runtimeLaunchError = nil
        lastError = nil
        setup.runtimeEnabled = true
        _ = runtimeSupervisor.markRestarting(reason: reason)
        diagnostics.record(.runtimeRestartStarted)
        guard canStartRuntimeServices else {
            await refreshAll(force: true)
            await integrationHealth.checkAll(force: true)
            return
        }
        if gatesRuntimeStartup, !runtimeServicesStarted {
            startRuntimeServicesIfNeeded(forceRefresh: false)
            try? await Task.sleep(for: .seconds(1))
            await refreshAll(force: true)
            await integrationHealth.checkAll(force: true)
            return
        }
        syncInstalledMCPHelperIfNeeded()
        unregisterAgent()
        registerAgent()
        Self.terminateStaleMCPHelpers()
        try? await Task.sleep(for: .seconds(1))
        await refreshAll(force: true)
        await integrationHealth.checkAll(force: true)
    }

    /// Reconnect every agent helper (Claude / Codex `manifold-mcp`
    /// processes). Sends SIGTERM to all running `manifold-mcp` PIDs
    /// regardless of which agent spawned them; the host (Claude or
    /// Codex) will relaunch the helper from the freshly-installed
    /// binary the next time it sends a request.
    ///
    /// This is the targeted fix for the "stale helper signature"
    /// problem: when the runtime overwrites the installed helper at
    /// app launch, processes Claude spawned earlier still reference
    /// the old code in memory and fail dynamic code-signing checks.
    /// Killing them lets Claude relaunch a process whose in-memory
    /// code matches the new on-disk file.
    func reconnectAgentHelpers() async {
        runtimeLaunchError = nil
        lastError = nil
        Self.terminateStaleMCPHelpers()
        // The freshly-spawned helpers won't be ready instantly; give
        // the host a moment to detect the disconnect and relaunch
        // before we re-probe.
        try? await Task.sleep(for: .seconds(1))
        await refreshAll(force: true)
        await integrationHealth.checkAll(force: true)
    }

    /// Find every running installed `manifold-mcp` process and send
    /// SIGTERM. The path comparison uses proc_pidpath so we don't kill
    /// arbitrary development helpers whose basename happens to match.
    private nonisolated static func terminateStaleMCPHelpers() {
        let installedPath = URL(fileURLWithPath: mcpBinaryPath).standardizedFileURL.path
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid="]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            logger.error("Failed to enumerate processes for reconnect: \(error.localizedDescription, privacy: .public)")
            return
        }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let listing = String(data: data, encoding: .utf8) else { return }
        var terminated = 0
        for rawLine in listing.split(whereSeparator: { $0.isNewline }) {
            let pidString = rawLine.trimmingCharacters(in: .whitespaces)
            guard let pid = pid_t(pidString), pid > 1 else { continue }
            guard resolvedExecutablePath(for: pid) == installedPath else {
                continue
            }
            if kill(pid, SIGTERM) == 0 {
                terminated += 1
            }
        }
        logger.info("Reconnect agents: terminated \(terminated) helper process(es)")
    }

    private nonisolated static func resolvedExecutablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4_096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
        return URL(fileURLWithPath: String(decoding: path, as: UTF8.self)).standardizedFileURL.path
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
    func resolveActiveGrantFilePath(_ canonicalPath: String) -> ResolvedGrantPath? {
        session.resolveGrantFilePath(canonicalPath)
    }
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
    var sessionStartupMode: SessionStartupMode {
        get { setup.sessionStartupMode }
        set {
            setup.sessionStartupMode = newValue
            suppressDefaultSessionUntilNextLaunch = false
            Task {
                await syncRuntimeSessionAccessMode()
                if newValue == .manual {
                    await endSession()
                } else {
                    await startDefaultSessionIfNeeded()
                }
            }
        }
    }
    var defaultSessionAgent: TargetApp {
        get { setup.defaultSessionAgent }
        set {
            setup.defaultSessionAgent = newValue
            suppressDefaultSessionUntilNextLaunch = false
            Task {
                guard sessionStartupMode == .defaultSession else { return }
                if session.activeGrant?.summaryFraming == "Default" {
                    await session.endSession(
                        onError: { [weak self] message in self?.lastError = message },
                        onConflict: { [weak self] count in self?.lastError = "\(count) conflict(s) while changing the default session." }
                    )
                    await refreshAll()
                }
                await startDefaultSessionIfNeeded()
            }
        }
    }
    var hasCompletedOnboarding: Bool {
        get { setup.hasCompletedOnboarding }
        set { setup.hasCompletedOnboarding = newValue }
    }
    var runtimeEnabled: Bool { setup.runtimeEnabled }
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
            if try Self.installBundledMCPHelper(force: true) {
                Self.terminateStaleMCPHelpers()
            }
            try ConfigWriter(binaryPath: Self.mcpBinaryPath).installAll()
            Task { await integrationHealth.checkAll(force: true) }
        } catch {
            integrationHealth.claude.errorDetail = error.localizedDescription
        }
    }

    func installCodexMCP() throws {
        if try Self.installBundledMCPHelper(force: true) {
            Self.terminateStaleMCPHelpers()
        }
        try ConfigWriter(binaryPath: Self.mcpBinaryPath).installCodex()
    }

    func installDemoMCP() {
        do {
            if try Self.installBundledMCPHelper(force: true) {
                Self.terminateStaleMCPHelpers()
            }
            try ConfigWriter(binaryPath: Self.mcpBinaryPath, demoMode: true).installAll()
            demoMCPInstallStatus = "Claude and Codex are configured to use Demo Mode data. Restart those apps to pick it up."
            Task { await integrationHealth.checkAll(force: true) }
        } catch {
            demoMCPInstallStatus = "Could not configure Demo Mode for Claude and Codex: \(error.localizedDescription)"
            integrationHealth.claude.errorDetail = error.localizedDescription
        }
    }

    @discardableResult
    private func syncInstalledMCPHelperIfNeeded() -> Bool {
        do {
            guard try Self.installBundledMCPHelper(force: false) else { return false }
            logger.info("Updated installed manifold-mcp helper from bundled copy")
            Self.terminateStaleMCPHelpers()
            Task { await integrationHealth.checkAll(force: true) }
            return true
        } catch {
            logger.warning("Unable to update installed manifold-mcp helper: \(error.localizedDescription, privacy: .public)")
            integrationHealth.claude.errorDetail = error.localizedDescription
            return false
        }
    }

    @discardableResult
    private nonisolated static func installBundledMCPHelper(force: Bool) throws -> Bool {
        guard let bundled = Bundle.main.url(forResource: "manifold-mcp", withExtension: nil) else {
            return false
        }

        let destinationPath = mcpBinaryPath
        let destinationURL = URL(fileURLWithPath: destinationPath)
        let fileManager = FileManager.default
        let destinationExists = fileManager.fileExists(atPath: destinationPath)

        guard force || destinationExists else {
            return false
        }

        // Skip the overwrite when the installed helper is the same code
        // as the bundled one. Compare CDHashes (the cryptographic digest
        // of the code-signing payload) rather than raw bytes — Debug
        // rebuilds can perturb non-signing bytes in the binary even when
        // nothing meaningful changed, so byte-compare would replace the
        // file on every launch and invalidate the running helpers Claude
        // and Codex have already spawned.
        if !force, destinationExists, helpersMatchByCodeIdentity(bundled, destinationURL) {
            return false
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if destinationExists {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: bundled, to: destinationURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationPath)
        return true
    }

    /// True if the two binaries have the same code-signing identity:
    /// same CDHash AND same team identifier. CDHash is the canonical
    /// "is this the same code?" check — it digests the code directory
    /// the kernel uses to validate a running process. If both files
    /// carry the same CDHash, replacing one with the other is a no-op
    /// from the runtime's perspective, so we skip the overwrite and
    /// preserve any helper PIDs that are still talking to it.
    private nonisolated static func helpersMatchByCodeIdentity(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let lhsInfo = codeSigningInfo(at: lhs),
              let rhsInfo = codeSigningInfo(at: rhs) else {
            return false
        }
        let lhsHash = lhsInfo[kSecCodeInfoUnique as String] as? Data
        let rhsHash = rhsInfo[kSecCodeInfoUnique as String] as? Data
        let lhsTeam = lhsInfo[kSecCodeInfoTeamIdentifier as String] as? String
        let rhsTeam = rhsInfo[kSecCodeInfoTeamIdentifier as String] as? String
        let lhsValidationStatus = codeSigningValidationStatus(at: lhs)
        let rhsValidationStatus = codeSigningValidationStatus(at: rhs)
        guard let lhsHash, let rhsHash, lhsHash == rhsHash else { return false }
        // A team/ad-hoc mismatch can still break a team-signed runtime's
        // helper verification even when the code hash matches. Treat it
        // as stale and reinstall from the active app bundle.
        if lhsTeam != rhsTeam {
            return false
        }
        // `SecCodeCopySigningInformation` can still return metadata for a
        // modified binary. Keep the installed helper only when its static
        // validation result matches the bundled source of truth too. This
        // tolerates local Debug certificates that are not trusted on this
        // machine while still replacing genuinely corrupted helpers.
        if lhsValidationStatus != rhsValidationStatus {
            return false
        }
        return true
    }

    private nonisolated static func codeSigningValidationStatus(at url: URL) -> OSStatus {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else { return createStatus }
        return SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil)
    }

    private nonisolated static func codeSigningInfo(at url: URL) -> [String: Any]? {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else { return nil }
        var infoRef: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &infoRef
        )
        guard infoStatus == errSecSuccess, let info = infoRef as? [String: Any] else {
            return nil
        }
        return info
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

    /// Pulls overrides for every requested agent in parallel — one XPC
    /// per agent. Failures land as empty arrays so the caller doesn't
    /// have to special-case partial loads.
    func fileVisibilityOverridesByAgent(_ agents: [TargetApp]) async -> [TargetApp: [FileVisibilityOverrideRecord]] {
        await withTaskGroup(of: (TargetApp, [FileVisibilityOverrideRecord]).self) { group in
            for agent in agents {
                group.addTask { (agent, await self.fileVisibilityOverrides(agent: agent)) }
            }
            var result: [TargetApp: [FileVisibilityOverrideRecord]] = [:]
            for await (agent, overrides) in group {
                result[agent] = overrides
            }
            return result
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
            return
        }

        if isActiveFocusMirrorMode(for: agent) {
            let other = agent == .cowork ? TargetApp.codex : TargetApp.cowork
            do {
                try await runtime.setFileVisibilityOverride(
                    agent: other,
                    sourceID: sourceID,
                    relativePath: relativePath,
                    isDirectory: isDirectory,
                    decision: decision
                )
            } catch {
                logger.error("Auto-mirror fan-out failed for override (\(sourceID, privacy: .public):\(relativePath, privacy: .public)) agent \(other.rawValue, privacy: .public): \(error.localizedDescription)")
                lastError = "Auto-mirror couldn't update \(other.rawValue): \(error.localizedDescription)"
            }
        }

        // Focus auto-save: keep the active Focus's saved override set in
        // sync with the live state. Same best-effort failure mode as the
        // auto-mirror fan-out above.
        await persistOverrideToActiveFocus(
            agent: agent,
            sourceID: sourceID,
            relativePath: relativePath,
            isDirectory: isDirectory,
            decision: decision
        )
        if isActiveFocusMirrorMode(for: agent) {
            let other = agent == .cowork ? TargetApp.codex : TargetApp.cowork
            await persistOverrideToActiveFocus(
                agent: other,
                sourceID: sourceID,
                relativePath: relativePath,
                isDirectory: isDirectory,
                decision: decision
            )
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
            return
        }

        if isActiveFocusMirrorMode(for: agent) {
            let other = agent == .cowork ? TargetApp.codex : TargetApp.cowork
            do {
                try await runtime.clearFileVisibilityOverride(
                    agent: other,
                    sourceID: sourceID,
                    relativePath: relativePath,
                    isDirectory: isDirectory
                )
            } catch {
                logger.error("Auto-mirror fan-out failed for clear (\(sourceID, privacy: .public):\(relativePath, privacy: .public)) agent \(other.rawValue, privacy: .public): \(error.localizedDescription)")
                lastError = "Auto-mirror couldn't update \(other.rawValue): \(error.localizedDescription)"
            }
        }

        // Focus auto-save: clear the matching entry from the active
        // Focus's override set so the saved Focus stays consistent.
        await clearOverrideFromActiveFocus(
            agent: agent,
            sourceID: sourceID,
            relativePath: relativePath,
            isDirectory: isDirectory
        )
        if isActiveFocusMirrorMode(for: agent) {
            let other = agent == .cowork ? TargetApp.codex : TargetApp.cowork
            await clearOverrideFromActiveFocus(
                agent: other,
                sourceID: sourceID,
                relativePath: relativePath,
                isDirectory: isDirectory
            )
        }
    }

    func sourceIsInDefaultScope(_ sourceID: String, for agent: TargetApp) -> Bool {
        governance.policy(for: agent)?.allowedSourceIDs.contains(sourceID) == true
    }

    /// Toggle a source's membership in an agent's default scope. Rolls back
    /// the optimistic local mutation if the XPC round-trip fails, so UI
    /// state never silently diverges from runtime truth.
    ///
    /// When `isAutoMirrorEnabled` is on, the same change also fans out to
    /// the other assistant. Fan-out failures are logged but don't roll back
    /// the primary mutation — auto-mirror is best-effort, and the user can
    /// re-run the explicit Mirror… sheet to reconcile.
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
            return
        }

        if isActiveFocusMirrorMode(for: agent) {
            await mirrorSourceScope(sourceID: sourceID, from: agent, inScope: inScope)
        }

        // Focus auto-save: mirror the new scope into the active Focus's
        // saved file_scopes so switching away and back preserves the edit.
        await persistScopeToActiveFocus(agent: agent)
        if isActiveFocusMirrorMode(for: agent) {
            let other = agent == .cowork ? TargetApp.codex : TargetApp.cowork
            await persistScopeToActiveFocus(agent: other)
        }
    }

    /// Fan-out half of `setSourceScope`. Applies the same change to the
    /// other assistant when auto-mirror is on. Best-effort: fan-out errors
    /// surface to `lastError` but don't unwind the primary mutation.
    private func mirrorSourceScope(sourceID: String, from primary: TargetApp, inScope: Bool) async {
        let other = primary == .cowork ? TargetApp.codex : TargetApp.cowork
        let alreadyMatches = sourceIsInDefaultScope(sourceID, for: other) == inScope
        guard !alreadyMatches else { return }

        mutateScope(agent: other, sourceID: sourceID, inScope: inScope)
        do {
            if inScope {
                try await runtime.addSource(sourceID, to: other)
            } else {
                try await runtime.removeSource(sourceID, from: other)
            }
        } catch {
            logger.error("Auto-mirror fan-out failed for source \(sourceID, privacy: .public) agent \(other.rawValue, privacy: .public): \(error.localizedDescription)")
            lastError = "Auto-mirror couldn't update \(other.rawValue): \(error.localizedDescription)"
            mutateScope(agent: other, sourceID: sourceID, inScope: !inScope)
        }
    }

    // MARK: - Focus auto-save fan-out

    /// Concrete `AppRuntimeClient` if available — the Focus extension
    /// methods (`setActiveFocus`, `setDefaultAtLaunch`, etc.) live on the
    /// concrete type per the AccessRedesign convention. Fixture clients
    /// silently no-op the Focus surface.
    var focusClient: AppRuntimeClient? { runtime as? AppRuntimeClient }

    /// Public wrapper: snapshot live agent state into the active Focus's
    /// preset rows for both agents. Called after a one-shot Mirror sync
    /// so the divergence-eliminating change persists across Focus
    /// deactivation/reactivation. Without this, the saved preset would
    /// re-overlay its old (divergent) scope on next activation,
    /// undoing the sync.
    func snapshotLiveStateToActivePresets() async {
        for agent in TargetApp.allCases {
            await persistScopeToActiveFocus(agent: agent)
            // Override snapshot: read the runtime's current per-agent
            // overrides and write them into the active preset's per-
            // agent rows. The existing per-key persistence helpers
            // operate one entry at a time; for a bulk snapshot we use
            // the savePresetOverrides full-replace path on the client.
            guard let focusID = activeFocusID[agent], !focusID.isEmpty,
                  let client = focusClient else { continue }
            do {
                let overrides = try await runtime.fileVisibilityOverrides(agent: agent)
                try await client.savePresetOverrides(presetID: focusID, overrides: overrides)
            } catch {
                logger.error("Snapshot (overrides) failed for preset \(focusID, privacy: .public) agent \(agent.rawValue, privacy: .public): \(error.localizedDescription)")
            }
        }
    }

    /// Push the current allowed-source set into the agent's active Focus
    /// preset row, if any. Best-effort — auto-save failures log but never
    /// roll back the primary mutation. Hot path; cheap on the happy
    /// no-active-Focus case (early return).
    private func persistScopeToActiveFocus(agent: TargetApp) async {
        guard let focusID = activeFocusID[agent], !focusID.isEmpty,
              let client = focusClient else { return }
        let allowed = (governance.policy(for: agent)?.allowedSourceIDs ?? []).sorted()
        let scopes = allowed.map {
            FileSelectionScope(sourceID: $0, relativePath: "", isDirectory: true)
        }
        do {
            try await client.updatePresetFileScopes(presetID: focusID, fileScopes: scopes)
        } catch {
            logger.error("Focus auto-save (scope) failed for preset \(focusID, privacy: .public): \(error.localizedDescription)")
        }
    }

    /// Patch one override into the active Focus's saved override set.
    private func persistOverrideToActiveFocus(
        agent: TargetApp,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool,
        decision: FileVisibilityOverrideDecision
    ) async {
        guard let focusID = activeFocusID[agent], !focusID.isEmpty,
              let client = focusClient else { return }
        do {
            try await client.setPresetOverride(
                presetID: focusID,
                sourceID: sourceID,
                relativePath: relativePath,
                isDirectory: isDirectory,
                decision: decision
            )
        } catch {
            logger.error("Focus auto-save (override) failed for preset \(focusID, privacy: .public): \(error.localizedDescription)")
        }
    }

    /// Remove an override entry from the active Focus's saved set.
    private func clearOverrideFromActiveFocus(
        agent: TargetApp,
        sourceID: String,
        relativePath: String,
        isDirectory: Bool
    ) async {
        guard let focusID = activeFocusID[agent], !focusID.isEmpty,
              let client = focusClient else { return }
        do {
            try await client.clearPresetOverride(
                presetID: focusID,
                sourceID: sourceID,
                relativePath: relativePath,
                isDirectory: isDirectory
            )
        } catch {
            logger.error("Focus auto-save (clear override) failed for preset \(focusID, privacy: .public): \(error.localizedDescription)")
        }
    }

    /// Patch session-level settings (memory / detail / note capture) into
    /// the active Focus's saved settings. Called by the active session
    /// card when the user toggles one of those controls while a Focus is
    /// active.
    func persistSettingsToActiveFocus(
        agent: TargetApp,
        requestDetailLevel: AccessRecordingLevel?,
        noteCaptureMode: SessionNoteCaptureMode?,
        allowFileMemory: Bool,
        summaryFraming: String?,
        emailSensitivity: EmailSensitivityLevel?
    ) async {
        guard let focusID = activeFocusID[agent], !focusID.isEmpty,
              let client = focusClient else { return }
        do {
            _ = try await client.updatePresetSettings(
                presetID: focusID,
                requestDetailLevel: requestDetailLevel,
                noteCaptureMode: noteCaptureMode,
                allowFileMemory: allowFileMemory,
                summaryFraming: summaryFraming,
                emailSensitivity: emailSensitivity
            )
        } catch {
            logger.error("Focus auto-save (settings) failed for preset \(focusID, privacy: .public): \(error.localizedDescription)")
        }
    }

    // MARK: - Focus activation

    /// Atomically activate a Focus for its target agent: ends the agent's
    /// current grant, swaps standing scope and overrides to match the
    /// Focus, starts a new grant with the Focus's settings.
    ///
    /// Optimistic UI: `activeFocusID` flips IMMEDIATELY so the toggle in
    /// the active card and the navigation subtitle update on the same
    /// frame as the click. The XPC end+swap+start round-trip happens in
    /// the background. If it fails, we revert. `refreshAll(force:)` is
    /// dropped from this path — its individual XPC calls (snapshot,
    /// approvals, data control summary, privacy discovery, activity,
    /// sessions, grant state, storage stats) added up to multi-second
    /// latency between click and visible state change. The UI surfaces
    /// that already update from observable state don't need a full
    /// refresh; they re-render off `activeFocusID` and `availableFocuses`.
    func setActiveFocus(presetID: String, targetApp: TargetApp? = nil) async {
        guard let client = focusClient else {
            lastError = "Focus activation requires the runtime client."
            return
        }

        // Optimistic flip — UI updates this frame.
        let optimisticAgents: [TargetApp] = targetApp.map { [$0] } ?? Array(TargetApp.allCases)
        let previousActive: [TargetApp: String?] = optimisticAgents.reduce(into: [:]) { acc, agent in
            acc[agent] = activeFocusID[agent]
        }
        for agent in optimisticAgents { activeFocusID[agent] = presetID }

        do {
            let result = try await client.setActiveFocus(presetID: presetID, targetApp: targetApp)
            let agent = TargetApp(rawValue: result.grant.targetApp) ?? targetApp ?? .cowork
            activeFocusID[agent] = presetID
            // Cheap targeted refresh: just the grant state + sessions
            // (used for the active session card). Full refreshAll is
            // overkill here and was the source of the perceived lag.
            await session.refreshGrantState()
        } catch {
            logger.error("setActiveFocus failed: \(error.localizedDescription)")
            lastError = "Couldn't activate Focus: \(error.localizedDescription)"
            // Revert optimistic flip.
            for (agent, prior) in previousActive {
                if let prior {
                    activeFocusID[agent] = prior
                } else {
                    activeFocusID.removeValue(forKey: agent)
                }
            }
        }
    }

    /// Refresh `availableFocuses` and `defaultLaunchFocusID` from the
    /// runtime. Cheap enough to call from the chip menu's open handler;
    /// no polling.
    func refreshFocuses() async {
        availableFocuses = (try? await fetchAllFocuses()) ?? []
        guard let client = focusClient else { return }
        for agent in TargetApp.allCases {
            defaultLaunchFocusID[agent] = (try? await client.defaultPresetForLaunch(agent: agent))?.presetID
        }
    }

    private func fetchAllFocuses() async throws -> [AccessPresetRecord] {
        guard let client = focusClient else { return [] }
        var seen = Set<String>()
        var combined: [AccessPresetRecord] = []
        for agent in TargetApp.allCases {
            for preset in try await client.accessTemplates(for: agent) where seen.insert(preset.presetID).inserted {
                combined.append(preset)
            }
        }
        return combined.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Set or clear which Focus auto-launches when the agent connects.
    func setDefaultAtLaunch(presetID: String?, agent: TargetApp) async {
        guard let client = focusClient else { return }
        do {
            try await client.setDefaultAtLaunch(presetID: presetID, agent: agent)
            defaultLaunchFocusID[agent] = presetID
        } catch {
            lastError = "Couldn't change default-at-launch: \(error.localizedDescription)"
        }
    }

    /// Create a new Focus record without activating it. Default Focus
    /// keeps running; user lands in editor mode for the new one.
    /// `targetApp = nil` creates a both-AIs Focus (mirror-mode default);
    /// passing a single agent creates a per-agent Focus.
    ///
    /// Sidebar workflow: caller invokes this on "+ New Focus", then
    /// updates `editingFocusID[targetApp ?? primaryAgent] = saved.presetID`
    /// to land the user in inline-rename + editing context. Activation
    /// is the user's explicit next move via the Toggle in the editor.
    @discardableResult
    func createFocus(name: String, targetApp: TargetApp? = nil, mirrorToBoth: Bool = true) async -> AccessPresetRecord? {
        guard let client = focusClient else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            // Create through the basic XPC saveAccessTemplate first
            // (carries name + targetApp + empty scope/email lists), then
            // patch settings + mirror flag through the dedicated helpers.
            let saved = try await client.saveAccessTemplate(
                presetID: nil,
                name: trimmed,
                targetApp: targetApp,
                fileScopes: [],
                emailIDs: []
            )
            // Patch the v44 fields. saveAccessTemplate doesn't carry
            // mirror_to_both yet — we land the new Focus with the
            // requested mirror state via updatePresetSettings + a
            // separate flag-only patch routed through the same XPC.
            try await client.updatePresetSettings(
                presetID: saved.presetID,
                requestDetailLevel: nil,
                noteCaptureMode: nil,
                allowFileMemory: false,
                summaryFraming: nil,
                emailSensitivity: nil
            )
            await refreshFocuses()
            // Reload the saved record so the caller sees mirror_to_both /
            // is_built_in defaults from the row (not the placeholder
            // record returned by saveAccessTemplate).
            return availableFocuses.first { $0.presetID == saved.presetID } ?? saved
        } catch {
            lastError = "Couldn't create Focus: \(error.localizedDescription)"
            return nil
        }
    }

    /// Snapshot current state into a brand-new Focus and activate it.
    /// Convenience for "+ New Focus from current state" — what the old
    /// chip menu used to do. Kept for callers that want one-shot
    /// snapshot+activate (the inline-rename sidebar flow uses
    /// `createFocus` + manual activate instead).
    @discardableResult
    func createFocusFromCurrent(name: String, agent: TargetApp) async -> AccessPresetRecord? {
        guard let client = focusClient else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let allowed = (governance.policy(for: agent)?.allowedSourceIDs ?? []).sorted()
        let scopes = allowed.map {
            FileSelectionScope(sourceID: $0, relativePath: "", isDirectory: true)
        }
        let overrides = await fileVisibilityOverrides(agent: agent)
        let policy = governance.policy(for: agent)
        do {
            let saved = try await client.saveAccessTemplate(
                presetID: nil,
                name: trimmed,
                targetApp: agent,
                fileScopes: scopes,
                emailIDs: []
            )
            if !overrides.isEmpty {
                try await client.savePresetOverrides(presetID: saved.presetID, overrides: overrides)
            }
            try await client.updatePresetSettings(
                presetID: saved.presetID,
                requestDetailLevel: policy?.accessRecordingLevel,
                noteCaptureMode: nil,
                allowFileMemory: false,
                summaryFraming: nil,
                emailSensitivity: policy?.emailSensitivity
            )
            await refreshFocuses()
            await setActiveFocus(presetID: saved.presetID, targetApp: agent)
            return saved
        } catch {
            lastError = "Couldn't create Focus: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Active-Focus mirror-mode predicate

    /// Whether the active Focus for an agent is in mirror mode (i.e.
    /// edits to its scope should fan out to the other agent's live
    /// state). Replaces the global `isAutoMirrorEnabled` predicate.
    /// Falls back to the legacy global toggle when no Focus is active
    /// (covers users who haven't migrated to a Focus yet).
    func isActiveFocusMirrorMode(for agent: TargetApp) -> Bool {
        if let focusID = activeFocusID[agent],
           let focus = availableFocuses.first(where: { $0.presetID == focusID }) {
            return focus.mirrorToBoth
        }
        return isAutoMirrorEnabled
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
        if case .restarting = runtimeSupervisor.state {
            // Preserve the restart generation assigned by the supervisor.
        } else {
            _ = runtimeSupervisor.markStarting()
        }

        let bundledAgent = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/ManifoldAgent")
        guard FileManager.default.isExecutableFile(atPath: bundledAgent.path) else {
            runtimeLaunchError = "ManifoldAgent is missing from the app bundle, so the runtime cannot start."
            lastError = runtimeLaunchError
            _ = runtimeSupervisor.markFailed(issue: "helper_missing")
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
            let bootstrap = try Self.bootstrapRuntimeAgent()
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
            _ = runtimeSupervisor.markFailed(issue: "launchctl_bootstrap_failed")
            logger.error("Failed to register ManifoldAgent via launchd: \(detail, privacy: .public)")
        }
    }

    func unregisterAgent() {
        _ = try? Self.runLaunchctl(arguments: ["bootout", "gui/\(getuid())/\(Self.agentLabel)"])
    }

    private static func bootstrapRuntimeAgent() throws -> ProcessResult {
        let domain = "gui/\(getuid())"
        let arguments = ["bootstrap", domain, launchAgentPlistURL.path]
        var lastResult = try runLaunchctl(arguments: arguments)
        guard shouldRetryBootstrap(lastResult) else { return lastResult }

        for attempt in 1...5 {
            let delay = UInt64(attempt * 200_000_000)
            Thread.sleep(forTimeInterval: Double(delay) / 1_000_000_000)
            lastResult = try runLaunchctl(arguments: arguments)
            if !shouldRetryBootstrap(lastResult) {
                return lastResult
            }
        }
        return lastResult
    }

    private static func shouldRetryBootstrap(_ result: ProcessResult) -> Bool {
        guard result.exitCode != 0 else { return false }
        let output = result.output.lowercased()
        return result.exitCode == 37
            || result.exitCode == 5
            || output.contains("operation already in progress")
            || output.contains("input/output error")
    }

    private func verifyRuntimeLaunch() async {
        let attempts = 6
        for attempt in 1...attempts {
            let pingResult = await runtime.ping()
            if pingResult.ok {
                runtimeLaunchError = nil
                _ = runtimeSupervisor.markHealthy()
                diagnostics.record(.runtimeRestartSucceeded)
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
        _ = runtimeSupervisor.markFailed(issue: "health_timeout")
        diagnostics.record(.runtimeRestartFailed)
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

    nonisolated static var storeURL: URL {
        (ManifoldRuntimeEnvironment.appSupportRootURL()
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("Manifold/store")
    }

    nonisolated static var mcpBinaryPath: String {
        (ManifoldRuntimeEnvironment.appSupportRootURL()
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("Manifold/bin/manifold-mcp")
            .path
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
