import Foundation
import os
import ManifoldKit

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "history")

@Observable
@MainActor
final class HistoryModel {
    var activityEntries: [AuditEntry] = []
    var sessions: [Session] = []
    var selectedSession: Session?
    var sessionEvents: [SessionEvent] = []
    var showSessionGrouping = true

    private var auditStore: AuditStore?
    private var snapshotStore: SnapshotStore?
    private var contentStore: ContentStore?

    init() {}

    func configure(auditStore: AuditStore, snapshotStore: SnapshotStore, contentStore: ContentStore) {
        self.auditStore = auditStore
        self.snapshotStore = snapshotStore
        self.contentStore = contentStore
    }

    func loadActivity() async {
        do {
            activityEntries = try await auditStore?.recentEntries(limit: 100) ?? []
        } catch {
            logger.error("Failed to load activity: \(error.localizedDescription)")
            activityEntries = []
        }
    }

    func loadSessions() async {
        do {
            sessions = try await auditStore?.recentSessions(limit: 20) ?? []
        } catch {
            logger.error("Failed to load sessions: \(error.localizedDescription)")
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
    func revertFile(event: SessionEvent, activeGrant: GrantRecord?, resolveGrantFilePath: (String) -> ResolvedGrantPath?) async -> RevertResult {
        guard let grant = activeGrant else { return .error("Start a session before reverting files.") }
        guard let snapshotStore, let beforeHash = event.beforeHash else { return .blobPruned }
        guard let filePath = event.filePath, let resolved = resolveGrantFilePath(filePath) else {
            return .error("No file path")
        }

        guard let blobData = try? await contentStore?.retrieve(hash: beforeHash) else {
            return .blobPruned
        }

        if FileManager.default.fileExists(atPath: resolved.fileURL.path) {
            if let afterHash = event.afterHash,
               let currentData = try? Data(contentsOf: resolved.fileURL) {
                let currentHash = currentData.sha256Hex
                if currentHash != afterHash {
                    return .contentDrift
                }
            }
        }

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
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Force revert even when content has drifted.
    func forceRevertFile(event: SessionEvent, activeGrant: GrantRecord?, resolveGrantFilePath: (String) -> ResolvedGrantPath?) async -> RevertResult {
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
}
