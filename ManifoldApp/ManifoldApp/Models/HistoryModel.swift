import Foundation
import ManifoldKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "history")

@Observable
@MainActor
final class HistoryModel {
    var activityEntries: [AuditEntry] = []
    var sessions: [Session] = []
    var selectedSession: Session?
    var sessionEvents: [SessionEvent] = []
    var showSessionGrouping = true

    private var client: AppRuntimeClient?

    init() {}

    func configure(client: AppRuntimeClient) {
        self.client = client
    }

    func loadActivity() async {
        guard let client else { return }
        do {
            activityEntries = try await client.recentActivity(limit: 100)
        } catch {
            logger.error("Failed to load activity: \(error.localizedDescription)")
            activityEntries = []
        }
    }

    func loadSessions() async {
        guard let client else { return }
        do {
            sessions = try await client.recentSessions(limit: 20)
        } catch {
            logger.error("Failed to load sessions: \(error.localizedDescription)")
            sessions = []
        }
    }

    func loadSessionEvents(sessionID: String) async {
        guard let client else { return }
        do {
            sessionEvents = try await client.sessionEvents(sessionID: sessionID)
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

    func revertFile(event: SessionEvent, activeGrant: GrantRecord?) async -> RevertResult {
        guard let client, let grant = activeGrant else { return .error("Start a session before reverting files.") }
        do {
            let result = try await client.revertSessionEvent(event: event, grantID: grant.grantID, force: false)
            return revertResult(from: result)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    func forceRevertFile(event: SessionEvent, activeGrant: GrantRecord?) async -> RevertResult {
        guard let client, let grant = activeGrant else { return .error("Start a session before reverting files.") }
        do {
            let result = try await client.revertSessionEvent(event: event, grantID: grant.grantID, force: true)
            return revertResult(from: result)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    func sessionSummary(session: Session, events: [SessionEvent]) -> String {
        let formatter = ISO8601DateFormatter()
        let startDate = formatter.date(from: session.startTime)
        let endDate = formatter.date(from: session.endTime)

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .medium
        timeFormatter.timeStyle = .short

        let startStr = startDate.map { timeFormatter.string(from: $0) } ?? session.startTime
        let duration: String
        if let startDate, let endDate {
            let minutes = Int(endDate.timeIntervalSince(startDate) / 60)
            duration = minutes < 1 ? "< 1 minute" : "\(minutes) minutes"
        } else {
            duration = "unknown"
        }

        let eventTimeFormatter = DateFormatter()
        eventTimeFormatter.timeStyle = .short

        var lines = [
            "# Session: \(session.agent) — \(startStr)",
            "Duration: \(duration) | \(session.readCount) reads, \(session.writeCount) writes, \(session.searchCount) searches",
            "",
            "## Timeline",
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

    private func revertResult(from result: RevertEventResult) -> RevertResult {
        switch result.status {
        case "success":
            return .success
        case "blobPruned":
            return .blobPruned
        case "contentDrift":
            return .contentDrift
        default:
            return .error(result.message ?? "Unknown revert error")
        }
    }
}
