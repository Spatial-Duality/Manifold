import Foundation
import os
import ManifoldKit

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "session")

// MARK: - Session Preview

struct SessionPreview {
    struct SourceEstimate {
        let sourceID: String
        let displayName: String
        let fileCount: Int
        let totalBytes: Int64
    }
    let sources: [SourceEstimate]
    let emailCount: Int
    let visibleEmailCount: Int
    let sensitivityLevel: EmailSensitivityFilter.Level
    var totalFiles: Int { sources.reduce(0) { $0 + $1.fileCount } }
    var totalBytes: Int64 { sources.reduce(0) { $0 + $1.totalBytes } }
    var exceedsWarnThreshold: Bool { totalBytes > MaterializationEngine.warnThreshold }
    var exceedsBlockThreshold: Bool { totalBytes > MaterializationEngine.blockThreshold }
    var emailsFiltered: Bool { visibleEmailCount < emailCount }
}

// MARK: - Session Model

@Observable
@MainActor
final class SessionModel {
    var activeGrant: GrantRecord?
    var activeGrantSources: [GrantSourceRecord] = []
    var lastCompletedSession: Session?
    var selectedPreset: DomainPreset?
    var preview: SessionPreview?
    var isComputing: Bool = false
    var previewError: String?

    var hasActiveSession: Bool { activeGrant?.isActive == true }
    var isPreviewing: Bool { preview != nil }

    private var grantStore: GrantStore?
    private var snapshotStore: SnapshotStore?
    private var contentStore: ContentStore?
    private var auditStore: AuditStore?
    private var emailStore: EmailStore?
    private var artifactIndex: ArtifactIndex?
    init() {}

    func configure(
        grantStore: GrantStore,
        snapshotStore: SnapshotStore,
        contentStore: ContentStore,
        auditStore: AuditStore,
        emailStore: EmailStore? = nil,
        artifactIndex: ArtifactIndex
    ) {
        self.grantStore = grantStore
        self.snapshotStore = snapshotStore
        self.contentStore = contentStore
        self.auditStore = auditStore
        self.emailStore = emailStore
        self.artifactIndex = artifactIndex
    }

    // MARK: - Pre-session Preview

    /// Compute a preview of what the session will contain without materializing.
    func computePreview(targetApp: TargetApp = .cowork) async {
        guard let grantStore else { return }
        isComputing = true
        previewError = nil
        do {
            let activeSources = try await grantStore.activeSources()
            guard !activeSources.isEmpty else {
                isComputing = false
                previewError = "Select at least one folder before starting a session."
                return
            }

            let mountInputs = activeSources.map { source in
                (source: source, mountName: URL(fileURLWithPath: source.originalRootPath).lastPathComponent.lowercased())
            }

            let perSource = try MaterializationEngine.estimateSizePerSource(sources: mountInputs)
            let estimates = perSource.map {
                SessionPreview.SourceEstimate(
                    sourceID: $0.sourceID,
                    displayName: $0.displayName,
                    fileCount: $0.fileCount,
                    totalBytes: $0.totalBytes
                )
            }

            let emailCount = (try? await emailStore?.emailMessageCount()) ?? 0
            let preset = selectedPreset ?? DomainPreset.presets.first { $0.id == "general" }
            let sensitivity = EmailSensitivityFilter(rawValue: preset?.emailSensitivity.rawValue ?? "moderate")
            let visibleEmailCount: Int
            if sensitivity.level == .strict {
                visibleEmailCount = (try? await emailStore?.sharedEmailCount()) ?? 0
            } else if sensitivity.level == .open {
                visibleEmailCount = emailCount
            } else {
                visibleEmailCount = (try? await emailStore?.visibleEmailCount(hiddenDomains: sensitivity.hiddenDomains)) ?? emailCount
            }

            preview = SessionPreview(
                sources: estimates,
                emailCount: emailCount,
                visibleEmailCount: visibleEmailCount,
                sensitivityLevel: sensitivity.level
            )
            isComputing = false
        } catch {
            isComputing = false
            previewError = "Couldn't estimate session size: \(error.localizedDescription)"
            logger.error("Preview failed: \(error.localizedDescription)")
        }
    }

    /// Cancel the preview and return to idle state.
    func cancelPreview() {
        preview = nil
    }

    // MARK: - Grant Lifecycle

    /// Start a new session: creates a grant, materializes sources, sets baseline hashes.
    func startSession(
        targetApp: TargetApp = .cowork,
        onError: (String) -> Void
    ) async {
        guard let grantStore, let snapshotStore else { return }
        do {
            let activeSources = try await grantStore.activeSources()
            guard !activeSources.isEmpty else {
                onError("Select at least one folder before starting a session.")
                return
            }

            let sourceIDs = activeSources.map(\.sourceID)
            let preset = selectedPreset ?? DomainPreset.presets.first { $0.id == "general" }
            let grant = try await grantStore.startGrant(
                targetApp: targetApp,
                profileID: "default",
                sourceIDs: sourceIDs,
                materializationRoot: Self.materializationRoot(grantID: "").path,
                emailSensitivity: preset?.emailSensitivity.rawValue ?? "moderate",
                summaryFraming: preset?.summaryFraming
            )

            let actualRoot = Self.materializationRoot(grantID: grant.grantID)
            try await grantStore.updateMaterializationRoot(grantID: grant.grantID, root: actualRoot.path)

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

            if let artifactIndex {
                try await artifactIndex.ensureGrantIndexed(
                    grantID: grant.grantID,
                    materializationRoot: actualRoot.path,
                    mounts: results.map {
                        ArtifactMount(
                            sourceID: $0.sourceID,
                            mountName: $0.mountName,
                            mountPath: $0.mountPath
                        )
                    }
                )

                let emails = try accessibleEmails(for: grant)
                let attachments = try emailStore?.emailAttachments(emailIDs: emails.map(\.emailID)) ?? []
                try await artifactIndex.syncEmails(
                    grantID: grant.grantID,
                    emails: emails,
                    attachments: attachments
                )
            }

            activeGrant = try await grantStore.grant(id: grant.grantID)
            activeGrantSources = try await grantStore.grantSources(grantID: grant.grantID)

            try? await auditStore?.log(
                action: .runStart,
                runID: grant.grantID,
                agent: targetApp.rawValue,
                metadata: ["grant_id": grant.grantID],
                grantID: grant.grantID
            )
            logger.info("Session started: \(grant.grantID) with \(results.count) sources")
        } catch {
            logger.error("Failed to start session: \(error.localizedDescription)")
            onError("Failed to start session: \(error.localizedDescription)")
        }
    }

    /// End the current session: promotes changes, ends grant.
    func endSession(onError: (String) -> Void, onConflict: (Int) -> Void) async {
        guard let grantStore, let grant = activeGrant else { return }
        do {
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

                for file in summary.applied + summary.newFiles {
                    let canonical = "\(gs.mountName)/\(file.relativePath)"
                    try await grantStore.recordPromotion(
                        grantID: grant.grantID, sourceID: gs.sourceID,
                        relativePath: canonical, result: file.result,
                        originalBeforeHash: file.originalBeforeHash,
                        promotedHash: file.promotedHash
                    )
                    try? await auditStore?.log(
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
                    try? await auditStore?.log(
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
                }

                if !summary.conflicts.isEmpty {
                    onConflict(summary.conflicts.count)
                }
            }

            try? await generateSessionSummary(grantID: grant.grantID)
            try await grantStore.endGrant(grantID: grant.grantID)
            try? await auditStore?.log(action: .runEnd, runID: grant.grantID, metadata: ["grant_id": grant.grantID], grantID: grant.grantID)

            // Clean up materialization directory after successful promotion
            Self.cleanupMaterialization(for: grant)

            activeGrant = nil
            activeGrantSources = []
            logger.info("Session ended: \(grant.grantID)")
        } catch {
            logger.error("Failed to end session: \(error.localizedDescription)")
            onError("Failed to end session: \(error.localizedDescription)")
        }
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

    // MARK: - File Resolution

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

    // MARK: - File Restore

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
            try await artifactIndex?.upsertFile(
                grantID: grant.grantID,
                mount: ArtifactMount(
                    sourceID: resolved.mount.sourceID,
                    mountName: resolved.mount.mountName,
                    mountPath: resolved.mount.mountPath
                ),
                relativePath: resolved.relativePath,
                fileURL: resolved.fileURL
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
            return true
        } catch { return false }
    }

    // MARK: - Private Helpers

    private func generateSessionSummary(grantID: String) async throws {
        guard let grantStore else { return }
        let grant = try await grantStore.grant(id: grantID)
        let promotions = try await grantStore.promotions(grantID: grantID)
        let grantSources = try await grantStore.grantSources(grantID: grantID)
        let created = promotions.filter { $0.result == "applied" && $0.originalBeforeHash == nil }
        let applied = promotions.filter { $0.result == "applied" && $0.originalBeforeHash != nil }
        let conflicts = promotions.filter { $0.result == "conflict" }

        let framing = grant?.summaryFraming ?? "Session"
        var lines: [String] = []
        lines.append("# \(framing.prefix(1).uppercased() + framing.dropFirst()) Summary")
        lines.append("")
        lines.append("- **Grant:** \(grantID.prefix(12))...")
        lines.append("- **Sources:** \(grantSources.map(\.mountName).joined(separator: ", "))")

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
        let summaries = try await grantStore.summaries(grantID: grantID)
        try await artifactIndex?.syncSessionSummaries(grantID: grantID, summaries: summaries)
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

    static func materializationRoot(grantID: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Manifold/materializations/\(grantID)/workspace")
    }

    // MARK: - Materialization Cleanup

    /// Delete the materialization directory for a completed grant.
    /// Safety: only deletes paths within the expected materializations/ parent.
    static func cleanupMaterialization(for grant: GrantRecord) {
        let matRoot = URL(fileURLWithPath: grant.materializationRoot)
        // materializationRoot is .../materializations/<grantID>/workspace
        // Delete the grant-level parent: .../materializations/<grantID>/
        let grantDir = matRoot.deletingLastPathComponent()
        let expectedParent = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Manifold/materializations")
        guard grantDir.path.hasPrefix(expectedParent.path),
              grantDir.lastPathComponent != "materializations" else {
            logger.error("Materialization path escapes expected parent: \(grantDir.path)")
            return
        }
        do {
            try FileManager.default.removeItem(at: grantDir)
            logger.info("Cleaned materialization: \(grantDir.lastPathComponent)")
        } catch {
            logger.warning("Failed to clean materialization: \(error.localizedDescription)")
        }
    }

    /// Remove materialization directories for ended or orphaned grants.
    /// Called at app launch to reclaim disk space from crashed sessions.
    static func cleanupOrphanedMaterializations(grantStore: GrantStore) async {
        let matParent = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Manifold/materializations")
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: matParent.path) else { return }
        for entry in entries {
            let grantDir = matParent.appendingPathComponent(entry)
            // Only delete if we can confirm the grant is ended or doesn't exist.
            // On DB error, skip to avoid deleting active session data.
            do {
                if let grant = try await grantStore.grant(id: entry), grant.isActive { continue }
            } catch {
                logger.warning("Skipping orphan cleanup for \(entry): DB error \(error.localizedDescription)")
                continue
            }
            try? fm.removeItem(at: grantDir)
            logger.info("Cleaned orphaned materialization: \(entry)")
        }
    }

    private func accessibleEmails(for grant: GrantRecord, limit: Int = 1_000) throws -> [EmailMessageRecord] {
        guard let emailStore else { return [] }
        let filter = EmailSensitivityFilter(rawValue: grant.emailSensitivity)

        if filter.level == .strict {
            return try emailStore.sharedEmails(limit: limit)
        }

        return try emailStore
            .allEmailMessages(limit: limit)
            .filter { filter.isVisible(email: $0) }
    }
}
