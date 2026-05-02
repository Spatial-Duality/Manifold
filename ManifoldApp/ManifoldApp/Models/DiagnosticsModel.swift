// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftUI
import os
import ManifoldKit

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "diagnostics-model")

/// App-side diagnostics owner. Holds consent state, the resettable anonymous
/// install ID, and the report builder. The recorder is the source of truth
/// for events; this model coordinates the user-facing surface.
///
/// V1 scope: export-only. No network transport and no server endpoint are
/// wired. The `installID` lifecycle and report builder exist so users can
/// decide exactly what to save or attach when asking for support.
@Observable
@MainActor
final class DiagnosticsModel {
    // MARK: - Consent

    /// Default off. Persisted to UserDefaults.
    var diagnosticSharingEnabled: Bool {
        didSet {
            defaults.set(diagnosticSharingEnabled, forKey: Keys.diagnosticSharing)
            if diagnosticSharingEnabled {
                ensureInstallID()
            } else {
                clearInstallID()
            }
        }
    }

    /// Default off. Sparkle automatic checks key off this in Phase B.
    var updateChecksEnabled: Bool {
        didSet { defaults.set(updateChecksEnabled, forKey: Keys.updateChecks) }
    }

    // MARK: - Identity

    /// Resettable anonymous install ID. `nil` until the user enables sharing.
    private(set) var installID: String?

    // MARK: - Reports

    /// Reserved for a future transport receipt. V1 keeps this nil because
    /// diagnostic reports are previewed and exported locally.
    private(set) var lastReceiptID: String?

    // MARK: - Dependencies

    private let defaults: UserDefaults
    private let recorder: DiagnosticsRecorder
    private let endpoint: URL?

    // MARK: - Init

    init(
        defaults: UserDefaults = AppTestEnvironment.userDefaults(),
        recorder: DiagnosticsRecorder = DiagnosticsRecorder(process: .app),
        endpoint: URL? = DiagnosticsModel.bundledEndpoint()
    ) {
        self.defaults = defaults
        self.recorder = recorder
        self.endpoint = endpoint

        diagnosticSharingEnabled = defaults.bool(forKey: Keys.diagnosticSharing)
        updateChecksEnabled = defaults.bool(forKey: Keys.updateChecks)
        installID = defaults.string(forKey: Keys.installID)
        lastReceiptID = defaults.string(forKey: Keys.lastReceiptID)

        if diagnosticSharingEnabled && installID == nil {
            ensureInstallID()
        }
    }

    // MARK: - Public API

    /// V1 is export-only. Keep the UI from exposing a dead network action even
    /// if a developer experiments with a local Info.plist endpoint.
    var canSendReports: Bool { false }

    /// Reset the anonymous identifier. The next exported report uses a fresh ID.
    /// The user-facing copy frames this as "as if you reinstalled."
    func resetInstallID() {
        clearInstallID()
        if diagnosticSharingEnabled {
            ensureInstallID()
        }
    }

    /// Record an event from the app process.
    func record(_ event: DiagnosticEvent) {
        recorder.record(event)
    }

    /// Build a report from the current local state. Pure — no I/O beyond
    /// reading the on-disk JSONL files. This is the exact JSON users can
    /// preview and export.
    func buildReport() -> DiagnosticReportV1 {
        let records = recorder.readAllRecords()
        let rollups = Self.rollups(from: records)
        let runtimeHealth = currentRuntimeHealth(from: records)

        return DiagnosticReportV1(
            app: appInfo,
            platform: platformInfo,
            consent: DiagnosticReportV1.ConsentState(
                diagnosticSharingEnabled: diagnosticSharingEnabled,
                updateChecksEnabled: updateChecksEnabled
            ),
            installID: diagnosticSharingEnabled ? installID : nil,
            runtimeHealth: runtimeHealth,
            rollups: rollups,
            signatures: [],            // Phase B/C: MetricKit signatures
            metricKitPayloads: []      // Phase B/C: MetricKit payloads
        )
    }

    /// Encoded report as pretty-printed JSON for the preview UI.
    func reportPreviewJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(buildReport()),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    /// Save the current report to a user-chosen URL. Returns the URL written.
    func saveReport(to url: URL) throws {
        let json = reportPreviewJSON()
        try json.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Show the diagnostics directory in Finder.
    func revealDiagnosticsInFinder() {
        let url = recorder.diagnosticsDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Wipe local diagnostics. Does not affect consent state or install ID.
    func deleteLocalDiagnostics() throws {
        try recorder.deleteAll()
    }

    /// Check the agent state marker on app launch. If the previous agent run
    /// did not record a clean shutdown, emit `runtimeUnexpectedExit` so the
    /// next report carries that signal. Idempotent — only fires for a marker
    /// we have not yet processed.
    func checkAgentExitState() {
        guard let marker = recorder.readAgentState() else { return }
        let lastSeenKey = Keys.lastSeenAgentLaunch
        let lastSeen = defaults.string(forKey: lastSeenKey)
        guard marker.launchUUID != lastSeen else { return }
        defaults.set(marker.launchUUID, forKey: lastSeenKey)

        if marker.state == .running {
            recorder.record(.runtimeUnexpectedExit(launchUUID: marker.launchUUID, lastState: .running))
            logger.warning("Detected unexpected agent exit (launch \(marker.launchUUID, privacy: .public))")
        }
    }

    // MARK: - Private

    private func ensureInstallID() {
        if installID == nil {
            let id = UUID().uuidString
            installID = id
            defaults.set(id, forKey: Keys.installID)
        }
    }

    private func clearInstallID() {
        installID = nil
        defaults.removeObject(forKey: Keys.installID)
        // A reset implies any pending receipt is no longer associated with
        // the user — drop it so the UI doesn't misrepresent identity history.
        lastReceiptID = nil
        defaults.removeObject(forKey: Keys.lastReceiptID)
    }

    private var appInfo: DiagnosticReportV1.AppInfo {
        let version = Bundle.main.shortVersionString
        let build = Bundle.main.buildVersion
        let channel: DiagnosticReportV1.AppInfo.Channel = endpoint == nil ? .sourceBuild : .directDownload
        return .init(version: version, build: build, channel: channel)
    }

    private var platformInfo: DiagnosticReportV1.PlatformInfo {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch: DiagnosticReportV1.PlatformInfo.Arch = .arm64
        #else
        let arch: DiagnosticReportV1.PlatformInfo.Arch = .x86_64
        #endif
        return .init(osMajor: v.majorVersion, osMinor: v.minorVersion, arch: arch)
    }

    private func currentRuntimeHealth(from records: [DiagnosticEventRecord]) -> DiagnosticReportV1.RuntimeHealth {
        // Derive last-known registration outcome from the most recent
        // registration event in the local log.
        let registrationEvents = records.filter {
            $0.name.hasPrefix("runtimeRegistration") || $0.name == "runtimePingTimeout"
        }
        let outcome: DiagnosticReportV1.RuntimeHealth.RegistrationOutcome
        switch registrationEvents.last?.name {
        case "runtimeRegistrationSucceeded": outcome = .succeeded
        case "runtimeRegistrationFailedHelperMissing": outcome = .helperMissing
        case "runtimeRegistrationFailedLaunchctlBootstrap": outcome = .launchctlBootstrapFailed
        case "runtimePingTimeout": outcome = .pingTimeout
        default: outcome = .unknown
        }

        return .init(
            runtimeConnected: false,    // resolved by caller before export if needed
            agentBootstrapped: outcome == .succeeded,
            lastRegistrationOutcome: outcome
        )
    }

    private static func rollups(from records: [DiagnosticEventRecord]) -> [DiagnosticReportV1.Rollup] {
        struct Key: Hashable {
            let day: String
            let process: DiagnosticEventRecord.Process
            let name: String
        }
        var counts: [Key: Int] = [:]
        for record in records {
            let key = Key(day: record.day, process: record.process, name: record.name)
            counts[key, default: 0] += 1
        }
        return counts
            .map { DiagnosticReportV1.Rollup(day: $0.key.day, process: $0.key.process, name: $0.key.name, count: $0.value) }
            .sorted { ($0.day, $0.process.rawValue, $0.name) < ($1.day, $1.process.rawValue, $1.name) }
    }

    private static func bundledEndpoint() -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ManifoldTelemetryEndpoint") as? String,
              !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme == "https" else {
            return nil
        }
        return url
    }

    private enum Keys {
        static let diagnosticSharing = "manifold.diagnostics.sharing"
        static let updateChecks      = "manifold.diagnostics.updateChecks"
        static let installID         = "manifold.diagnostics.installID"
        static let lastReceiptID     = "manifold.diagnostics.lastReceiptID"
        static let lastSeenAgentLaunch = "manifold.diagnostics.lastSeenAgentLaunch"
    }
}

// MARK: - Bundle helpers

extension Bundle {
    var buildVersion: String {
        (object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }
}
