import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "session")

@Observable
@MainActor
final class SessionModel {
    var activeGrant: GrantRecord?
    var activeGrantSources: [GrantSourceRecord] = []
    var lastCompletedSession: Session?
    var selectedPreset: DomainPreset?

    var hasActiveSession: Bool { activeGrant?.isActive == true }

    private var grantStore: GrantStore?
    private var snapshotStore: SnapshotStore?
    private var contentStore: ContentStore?
    private var auditStore: AuditStore?
    private var emailFilter: EmailFilter?

    init() {}

    func configure(
        grantStore: GrantStore,
        snapshotStore: SnapshotStore,
        contentStore: ContentStore,
        auditStore: AuditStore,
        emailFilter: EmailFilter
    ) {
        self.grantStore = grantStore
        self.snapshotStore = snapshotStore
        self.contentStore = contentStore
        self.auditStore = auditStore
        self.emailFilter = emailFilter
    }

    // MARK: - Grant Lifecycle

    /// Start a new session: creates a grant, materializes sources, sets baseline hashes.
    func startSession(
        targetApp: TargetApp = .cowork,
        selectedEmailIDs: Set<String>,
        onError: (String) -> Void
    ) async {
        guard let grantStore, let snapshotStore else { return }
        do {
            let activeSources = try await grantStore.activeSources()
            let emailIDs = Array(selectedEmailIDs).sorted()
            guard !activeSources.isEmpty || !emailIDs.isEmpty else {
                onError("Select at least one folder or shared email before starting a session.")
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

            if !emailIDs.isEmpty {
                let emails = try await grantStore.grantEmailMessages(grantID: grant.grantID)
                let attachments = try await materializeGrantEmails(
                    grantID: grant.grantID,
                    grantRoot: actualRoot,
                    emails: emails
                )
                try await grantStore.attachEmailsToGrant(grantID: grant.grantID, emails: attachments)
            }

            activeGrant = try await grantStore.grant(id: grant.grantID)
            activeGrantSources = try await grantStore.grantSources(grantID: grant.grantID)

            try? await auditStore?.log(
                action: .runStart,
                runID: grant.grantID,
                agent: targetApp.rawValue,
                metadata: ["grant_id": grant.grantID, "email_count": "\(emailIDs.count)"],
                grantID: grant.grantID
            )
            logger.info("Session started: \(grant.grantID) with \(results.count) sources and \(emailIDs.count) emails")
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
        if !usedPaths.contains(base) { return base }

        var index = 2
        while usedPaths.contains("\(base.dropLast(3))-\(index).md") {
            index += 1
        }
        return "\(base.dropLast(3))-\(index).md"
    }

    static func materializationRoot(grantID: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Manifold/materializations/\(grantID)/workspace")
    }
}
