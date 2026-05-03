// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Sparkle
import SwiftUI
import os
import ManifoldKit

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "updater")

enum SoftwareUpdateState: Equatable {
    case ready
    case checking
    case updateAvailable(version: String)
    case downloading(version: String)
    case downloaded(version: String)
    case installing(version: String)
    case relaunching
    case upToDate(checkedAt: Date)
    case skipped(version: String)
    case deferred(version: String)
    case failed(reason: DiagnosticEvent.SparkleUpdateFailureReason)
}

/// App-side wrapper around `SPUStandardUpdaterController`.
///
/// Two non-default behaviors:
///
/// 1. **Consent-driven automatic checks.** Sparkle's automatic-check setting
///    is mirrored from `DiagnosticsModel.updateChecksEnabled`. When the user
///    flips the toggle in Settings -> General, this model writes through to
///    the live `SPUUpdater`. The `Info.plist` ships with
///    `SUEnableAutomaticChecks=NO` so the default is silent — no traffic
///    leaves the Mac unless the user opts in.
///
/// 2. **Graceful agent shutdown before relaunch.** Sparkle replaces the
///    bundle and relaunches; without intervention, the running
///    `ManifoldAgent` LaunchAgent would still be the old code path, version
///    mismatch the new app, and trigger the auto-restart loop on next
///    launch. The `updaterWillRelaunchApplication(_:)` delegate callback
///    fires synchronously before relaunch — we use it to `launchctl bootout`
///    the agent so the new app boots a fresh agent cleanly.
@MainActor
final class UpdaterModel: NSObject, ObservableObject {

    let controller: SPUStandardUpdaterController
    private let diagnostics: DiagnosticsModel
    private let delegateAdapter: UpdaterDelegateAdapter
    @Published private(set) var state: SoftwareUpdateState = .ready
    @Published private(set) var isManualCheckInFlight = false

    /// Set by `ManifoldStore` after init so the closure can capture `self`.
    /// Invoked on the main actor immediately before Sparkle relaunches.
    var agentShutdown: () -> Void = {}

    init(diagnostics: DiagnosticsModel) {
        self.diagnostics = diagnostics
        let adapter = UpdaterDelegateAdapter()
        self.delegateAdapter = adapter
        // SPUStandardUpdaterController takes its delegates at init and only
        // holds them weakly. Pass the adapter; wire it back to self after
        // super.init so the adapter's owner-pointer is non-nil before any
        // Sparkle callbacks can fire.
        self.controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: adapter,
            userDriverDelegate: adapter
        )
        super.init()
        adapter.owner = self
        controller.startUpdater()

        // Publish the current consent state through to Sparkle so the first
        // launch matches the persisted preference. The store polls
        // `diagnostics.updateChecksEnabled` and calls
        // `applyAutomaticCheckPreference` when it changes.
        applyAutomaticCheckPreference(diagnostics.updateChecksEnabled)
    }

    /// Manual `Check for Updates…` invocation. Always allowed regardless of
    /// the automatic-check preference — the user explicitly asked.
    func checkForUpdates() {
        guard canStartManualCheck else { return }
        isManualCheckInFlight = true
        state = .checking
        diagnostics.record(.sparkleUpdateChecked)
        controller.checkForUpdates(nil)
    }

    var canStartManualCheck: Bool {
        controller.updater.canCheckForUpdates && !isManualCheckInFlight
    }

    /// Mirror the consent toggle to Sparkle's persisted automatic-check
    /// setting. Called by `ManifoldStore` whenever the user flips the
    /// "Check for updates automatically" toggle in Settings -> General.
    func applyAutomaticCheckPreference(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        logger.info("Sparkle automatic checks \(enabled ? "enabled" : "disabled", privacy: .public)")
    }

    // MARK: - Delegate callbacks (invoked from the adapter)

    fileprivate func handleWillRelaunch() {
        state = .relaunching
        agentShutdown()
        diagnostics.record(.sparkleUpdateApplied(
            from: Bundle.main.shortVersionString,
            to: "incoming"
        ))
    }

    fileprivate func handleDidFinish(error: Error?) {
        isManualCheckInFlight = false
        guard let error else {
            if state == .checking {
                state = .upToDate(checkedAt: Date())
            }
            return
        }
        let nsError = error as NSError
        let reason = Self.classify(nsError)
        state = .failed(reason: reason)
        diagnostics.record(.sparkleUpdateFailed(reason: reason))
        logger.error("Sparkle update failed: code=\(nsError.code, privacy: .public) reason=\(reason.rawValue, privacy: .public)")
    }

    fileprivate func handleDidFindUpdate(_ item: SUAppcastItem) {
        state = .updateAvailable(version: item.displayVersionString)
    }

    fileprivate func handleDidNotFindUpdate() {
        state = .upToDate(checkedAt: Date())
    }

    fileprivate func handleWillDownload(_ item: SUAppcastItem) {
        state = .downloading(version: item.displayVersionString)
    }

    fileprivate func handleDidDownload(_ item: SUAppcastItem) {
        state = .downloaded(version: item.displayVersionString)
    }

    fileprivate func handleFailedDownload(_ item: SUAppcastItem, error: Error) {
        state = .failed(reason: .downloadFailed)
        diagnostics.record(.sparkleUpdateFailed(reason: .downloadFailed))
        logger.error("Sparkle update download failed for \(item.displayVersionString, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    fileprivate func handleWillInstall(_ item: SUAppcastItem) {
        state = .installing(version: item.displayVersionString)
    }

    fileprivate func handleChoice(_ choice: SPUUserUpdateChoice, item: SUAppcastItem, state updateState: SPUUserUpdateState) {
        let version = item.displayVersionString
        switch choice {
        case .install:
            state = updateState.stage == .notDownloaded ? .downloading(version: version) : .installing(version: version)
        case .skip:
            state = .skipped(version: version)
        case .dismiss:
            state = .deferred(version: version)
        @unknown default:
            state = .ready
        }
    }

    /// Exposed for unit testing. Maps a Sparkle `NSError` (in the
    /// `SUSparkleErrorDomain`) to one of our closed diagnostic reasons.
    /// Pure logic, so it stays nonisolated and callable from any context.
    nonisolated static func classify(_ error: NSError) -> DiagnosticEvent.SparkleUpdateFailureReason {
        switch error.code {
        case Int(SUError.signatureError.rawValue),
             Int(SUError.validationError.rawValue):
            return .signatureMismatch
        case Int(SUError.appcastError.rawValue),
             Int(SUError.appcastParseError.rawValue),
             Int(SUError.downloadError.rawValue):
            return .downloadFailed
        case Int(SUError.installationError.rawValue),
             Int(SUError.relaunchError.rawValue),
             Int(SUError.unarchivingError.rawValue):
            return .installFailed
        case Int(SUError.installationCanceledError.rawValue),
             Int(SUError.installationAuthorizeLaterError.rawValue):
            return .userCancelled
        default:
            return .downloadFailed
        }
    }
}

// MARK: - Adapter

/// Bridges Sparkle's `nonisolated` delegate callbacks into the main-actor
/// `UpdaterModel` without forcing the model itself to be nonisolated.
/// Sparkle calls these from arbitrary queues; the adapter hops to main
/// before touching state.
private final class UpdaterDelegateAdapter: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    weak var owner: UpdaterModel?

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        let owner = self.owner
        DispatchQueue.main.async { owner?.handleWillRelaunch() }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let owner = self.owner
        DispatchQueue.main.async { owner?.handleDidFindUpdate(item) }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        let owner = self.owner
        DispatchQueue.main.async { owner?.handleDidNotFindUpdate() }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let owner = self.owner
        DispatchQueue.main.async { owner?.handleDidNotFindUpdate() }
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        let owner = self.owner
        DispatchQueue.main.async { owner?.handleWillDownload(item) }
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        let owner = self.owner
        DispatchQueue.main.async { owner?.handleDidDownload(item) }
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        let owner = self.owner
        DispatchQueue.main.async { owner?.handleFailedDownload(item, error: error) }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        let owner = self.owner
        DispatchQueue.main.async { owner?.handleWillInstall(item) }
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate item: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let owner = self.owner
        DispatchQueue.main.async { owner?.handleChoice(choice, item: item, state: state) }
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        let owner = self.owner
        DispatchQueue.main.async { owner?.handleDidFinish(error: error) }
    }
}
