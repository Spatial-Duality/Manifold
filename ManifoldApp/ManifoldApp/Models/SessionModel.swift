// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import ManifoldXPC
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "session")

struct SessionPreview: Codable, Sendable {
    struct SourceEstimate: Codable, Sendable {
        let sourceID: String
        let displayName: String
        let fileCount: Int
        let totalBytes: Int64
        let scopeCount: Int
    }

    let sources: [SourceEstimate]
    let emailCount: Int
    let visibleEmailCount: Int
    let sensitivityLevel: String
    let selectedEmailCount: Int

    var emailsFiltered: Bool { visibleEmailCount < emailCount }
    var totalFiles: Int { sources.reduce(0) { $0 + $1.fileCount } }
    var totalBytes: Int64 { sources.reduce(0) { $0 + $1.totalBytes } }
    var exceedsWarnThreshold: Bool { totalBytes > MaterializationEngine.warnThreshold }
    var exceedsBlockThreshold: Bool { totalBytes > MaterializationEngine.blockThreshold }
}

@Observable
@MainActor
final class SessionModel {
    var activeGrant: GrantRecord?
    var activeGrantSources: [GrantSourceRecord] = []
    var activeTargetApp: TargetApp = .cowork
    var lastCompletedSession: Session?
    var selectedPreset: DomainPreset?
    var preview: SessionPreview?
    var isComputing = false
    var previewError: String?

    var hasActiveSession: Bool { activeGrant?.isActive == true }
    var isPreviewing: Bool { preview != nil }

    private var client: (any RuntimeClientProtocol)?

    init() {}

    func configure(client: any RuntimeClientProtocol) {
        self.client = client
    }

    func computePreview(
        targetApp: TargetApp = .cowork,
        fileScopes: [FileSelectionScope] = [],
        selectedEmailIDs: Set<String> = []
    ) async {
        guard let client else { return }
        isComputing = true
        previewError = nil
        do {
            preview = try await client.sessionPreview(
                targetApp: targetApp,
                fileScopes: normalizedScopes(fileScopes),
                selectedEmailIDs: selectedEmailIDs,
                emailSensitivity: selectedPreset?.emailSensitivity.rawValue
            )
            activeTargetApp = targetApp
        } catch {
            previewError = "Couldn't estimate session size: \(error.localizedDescription)"
            logger.error("Preview failed: \(error.localizedDescription)")
        }
        isComputing = false
    }

    func cancelPreview() {
        preview = nil
    }

    func startSession(
        targetApp: TargetApp = .cowork,
        fileScopes: [FileSelectionScope] = [],
        selectedEmailIDs: Set<String> = [],
        summaryFraming: String? = nil,
        noteCaptureMode: SessionNoteCaptureMode? = nil,
        onError: (String) -> Void
    ) async {
        guard let client else { return }
        do {
            let state = try await client.startTrackedRun(
                targetApp: targetApp,
                fileScopes: normalizedScopes(fileScopes),
                selectedEmailIDs: selectedEmailIDs,
                summaryFraming: summaryFraming ?? selectedPreset?.summaryFraming,
                noteCaptureMode: noteCaptureMode ?? Self.defaultSessionNoteCaptureMode(),
                emailSensitivity: selectedPreset?.emailSensitivity.rawValue
            )
            activeTargetApp = targetApp
            activeGrant = state.activeGrant
            activeGrantSources = state.activeGrantSources
            preview = nil
            previewError = nil
        } catch {
            logger.error("Failed to start session: \(error.localizedDescription)")
            onError("Failed to start session: \(error.localizedDescription)")
        }
    }

    func endSession(onError: (String) -> Void, onConflict: (Int) -> Void) async {
        guard let client, let grant = activeGrant else { return }
        do {
            let result = try await client.applyTrackedRun(grantID: grant.grantID, endSession: true)
            if result.conflictCount > 0 {
                onConflict(result.conflictCount)
            }
            activeGrant = nil
            activeGrantSources = []
        } catch {
            logger.error("Failed to end session: \(error.localizedDescription)")
            onError("Failed to end session: \(error.localizedDescription)")
        }
    }

    func refreshGrantState(targetApp: TargetApp? = nil) async {
        guard let client else { return }
        do {
            let state = try await client.activeGrantState(targetApp: targetApp ?? activeTargetApp)
            activeGrant = state.activeGrant
            activeGrantSources = state.activeGrantSources
            if let raw = state.targetApp, let target = TargetApp(rawValue: raw) {
                activeTargetApp = target
            }
        } catch {
            logger.error("Failed to refresh grant state: \(error.localizedDescription)")
            activeGrant = nil
            activeGrantSources = []
        }
    }

    func currentGrantMounts() -> [GrantMount] {
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

    func canonicalPath(for url: URL, base: URL, mountName: String) -> String {
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

    func resolveGrantFilePath(_ canonicalPath: String) -> ResolvedGrantPath? {
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

    func restoreFile(snapshotID: Int, filePath: String) async -> RestoreSnapshotResult {
        guard let client else {
            return RestoreSnapshotResult(status: "error", message: "No runtime client is available for restore.")
        }
        do {
            return try await client.restoreSnapshot(snapshotID: snapshotID, filePath: filePath)
        } catch {
            return RestoreSnapshotResult(status: "error", message: error.localizedDescription)
        }
    }

    private func normalizedScopes(_ scopes: [FileSelectionScope]) -> [FileSelectionScope] {
        var unique: [String: FileSelectionScope] = [:]
        for scope in scopes {
            let normalized = FileSelectionScope(
                sourceID: scope.sourceID,
                relativePath: scope.normalizedRelativePath,
                isDirectory: scope.isDirectory
            )
            unique[normalized.id] = normalized
        }
        return Array(unique.values)
    }

    private static func defaultSessionNoteCaptureMode() -> SessionNoteCaptureMode {
        SessionNoteCaptureMode(
            rawValue: UserDefaults.standard.string(forKey: "manifold.sessionNotes.mode") ?? ""
        ) ?? .off
    }
}
