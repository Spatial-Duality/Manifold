import Foundation
import ManifoldKit
import ManifoldXPC

struct DashboardState: Codable, Sendable {
    let runtimeConnected: Bool
    let activeBridgeCount: Int
    let connectedAgents: [String]
    let sources: [SourceRecord]
    let claudePolicy: AgentAccessPolicy
    let codexPolicy: AgentAccessPolicy
    let claudeEmailGovernance: AgentEmailGovernanceSummary
    let codexEmailGovernance: AgentEmailGovernanceSummary
    let activeWorkBlock: WorkBlockRecord?
    let pendingApprovalCount: Int
    let agentCoverages: [AgentCoverageSnapshot]
    let coverageEvents: [CoverageEvent]
}

struct ActiveGrantState: Codable, Sendable {
    let activeGrant: GrantRecord?
    let activeGrantSources: [GrantSourceRecord]
    let targetApp: String?
}

struct StorageStatsSnapshot: Codable, Sendable {
    let storageUsed: Int64
}

struct WorkBlockPreview: Codable, Sendable {
    let applied: [String]
    let conflicts: [String]
    let newFiles: [String]
    let skipped: Int
}

struct ApplyTrackedRunResult: Codable, Sendable {
    let grantID: String
    let filesApplied: [String]
    let filesConflicted: [String]
    let appliedCount: Int
    let conflictCount: Int
}

struct RevertEventResult: Codable, Sendable {
    let status: String
    let message: String?
}

struct EmailBackupInfo: Codable, Sendable {
    let path: String
    let diskUsage: Int64
}

final class AppRuntimeClient: Sendable {
    let xpc = ManifoldXPCClient()

    struct PingResult: Sendable {
        let ok: Bool
        let agentVersion: String?
    }

    func ping() async -> PingResult {
        do {
            let response = try await xpc.command(name: "ping", payload: [:])
            let ok = response["ok"] as? Bool ?? false
            let version = response["agentVersion"] as? String
            return PingResult(ok: ok, agentVersion: version)
        } catch {
            return PingResult(ok: false, agentVersion: nil)
        }
    }

    func dashboardState() async throws -> DashboardState {
        try await command(name: "getStatus", as: DashboardState.self)
    }

    func listSources() async throws -> [SourceRecord] {
        try await command(name: "listSources", field: "sources", as: [SourceRecord].self)
    }

    func addSource(path: String, displayName: String) async throws -> SourceRecord {
        try await command(
            name: "addSource",
            payload: ["path": path, "displayName": displayName],
            field: "source",
            as: SourceRecord.self
        )
    }

    func removeSource(sourceID: String) async throws {
        _ = try await xpc.command(name: "removeSource", payload: ["sourceID": sourceID])
    }

    func pauseSource(sourceID: String) async throws {
        _ = try await xpc.command(name: "pauseSource", payload: ["sourceID": sourceID])
    }

    func resumeSource(sourceID: String) async throws {
        _ = try await xpc.command(name: "resumeSource", payload: ["sourceID": sourceID])
    }

    func policies() async throws -> DashboardState {
        try await dashboardState()
    }

    func pauseAgent(_ agent: TargetApp) async throws {
        _ = try await xpc.command(name: "pauseAgent", payload: ["agent": agent.rawValue])
    }

    func resumeAgent(_ agent: TargetApp) async throws {
        _ = try await xpc.command(name: "resumeAgent", payload: ["agent": agent.rawValue])
    }

    func addSource(_ sourceID: String, to agent: TargetApp) async throws {
        _ = try await xpc.command(name: "addSourceToPolicy", payload: ["sourceID": sourceID, "agent": agent.rawValue])
    }

    func removeSource(_ sourceID: String, from agent: TargetApp) async throws {
        _ = try await xpc.command(name: "removeSourceFromPolicy", payload: ["sourceID": sourceID, "agent": agent.rawValue])
    }

    func updateAccessRecordingLevel(_ level: AccessRecordingLevel, for agent: TargetApp) async throws {
        _ = try await xpc.command(name: "updateAccessRecordingLevel", payload: ["level": level.rawValue, "agent": agent.rawValue])
    }

    func getEmailRuleSet(agent: TargetApp) async throws -> EmailRuleSet {
        try await command(
            name: "getEmailRuleSet",
            payload: ["agent": agent.rawValue],
            field: "ruleSet",
            as: EmailRuleSet.self
        )
    }

    func updateEmailRuleSet(agent: TargetApp, ruleSet: EmailRuleSet) async throws {
        _ = try await xpc.command(
            name: "updateEmailRuleSet",
            payload: [
                "agent": agent.rawValue,
                "ruleSet": try XPCJSON.object(from: ruleSet),
            ]
        )
    }

    func getEmailRuleActivitySummary(agent: TargetApp) async throws -> EmailRuleActivitySummary {
        try await command(
            name: "getEmailRuleActivitySummary",
            payload: ["agent": agent.rawValue],
            field: "summary",
            as: EmailRuleActivitySummary.self
        )
    }

    func activeGrantState(targetApp: TargetApp) async throws -> ActiveGrantState {
        try await command(name: "activeGrantState", payload: ["targetApp": targetApp.rawValue], as: ActiveGrantState.self)
    }

    func sessionPreview(
        targetApp: TargetApp,
        fileScopes: [FileSelectionScope],
        selectedEmailIDs: Set<String>,
        emailSensitivity: String?
    ) async throws -> SessionPreview {
        var payload: [String: Any] = [
            "targetApp": targetApp.rawValue,
            "fileScopes": try XPCJSON.object(from: fileScopes),
            "selectedEmailIDs": Array(selectedEmailIDs),
        ]
        if let emailSensitivity {
            payload["emailSensitivity"] = emailSensitivity
        }
        return try await command(name: "sessionPreview", payload: payload, field: "preview", as: SessionPreview.self)
    }

    func startTrackedRun(
        targetApp: TargetApp,
        fileScopes: [FileSelectionScope],
        selectedEmailIDs: Set<String>,
        summaryFraming: String?,
        noteCaptureMode: SessionNoteCaptureMode,
        emailSensitivity: String?
    ) async throws -> ActiveGrantState {
        var payload: [String: Any] = [
            "targetApp": targetApp.rawValue,
            "fileScopes": try XPCJSON.object(from: fileScopes),
            "selectedEmailIDs": Array(selectedEmailIDs),
            "noteCaptureMode": noteCaptureMode.rawValue,
        ]
        if let summaryFraming {
            payload["summaryFraming"] = summaryFraming
        }
        if let emailSensitivity {
            payload["emailSensitivity"] = emailSensitivity
        }
        return try await command(name: "startTrackedRun", payload: payload, as: ActiveGrantState.self)
    }

    func restoreSnapshot(snapshotID: Int, filePath: String) async throws -> Bool {
        try await command(
            name: "restoreSnapshot",
            payload: ["snapshotID": snapshotID, "filePath": filePath],
            field: "restored",
            as: Bool.self
        )
    }

    func markWorkBlockReviewing(id: String) async throws {
        _ = try await xpc.command(name: "markWorkBlockReviewing", payload: ["workBlockID": id])
    }

    func cancelWorkBlockReview(id: String) async throws {
        _ = try await xpc.command(name: "cancelWorkBlockReview", payload: ["workBlockID": id])
    }

    func pauseTrackedRun(id: String) async throws {
        _ = try await xpc.command(name: "pauseTrackedRun", payload: ["workBlockID": id])
    }

    func resumeTrackedRun(id: String) async throws {
        _ = try await xpc.command(name: "resumeTrackedRun", payload: ["workBlockID": id])
    }

    func discardTrackedRun(id: String, grantID: String?, endSession: Bool = false) async throws {
        var payload: [String: Any] = ["workBlockID": id, "endSession": endSession]
        if let grantID {
            payload["grantID"] = grantID
        }
        _ = try await xpc.command(name: "discardTrackedRun", payload: payload)
    }

    func promotionPreview(grantID: String) async throws -> WorkBlockPreview {
        try await command(name: "promotionPreview", payload: ["grantID": grantID], field: "preview", as: WorkBlockPreview.self)
    }

    func applyTrackedRun(grantID: String, endSession: Bool = false) async throws -> ApplyTrackedRunResult {
        try await command(
            name: "applyTrackedRun",
            payload: ["grantID": grantID, "endSession": endSession],
            field: "result",
            as: ApplyTrackedRunResult.self
        )
    }

    func recentActivity(limit: Int = 100) async throws -> [AuditEntry] {
        try await command(name: "recentActivity", payload: ["limit": limit], field: "entries", as: [AuditEntry].self)
    }

    func recentSessions(limit: Int = 20) async throws -> [Session] {
        try await command(name: "recentSessions", payload: ["limit": limit], field: "sessions", as: [Session].self)
    }

    func sessionEvents(sessionID: String) async throws -> [SessionEvent] {
        try await command(name: "sessionEvents", payload: ["sessionID": sessionID], field: "events", as: [SessionEvent].self)
    }

    func revertSessionEvent(event: SessionEvent, grantID: String, force: Bool) async throws -> RevertEventResult {
        try await command(
            name: "revertSessionEvent",
            payload: [
                "event": try XPCJSON.object(from: event),
                "grantID": grantID,
                "force": force,
            ],
            field: "result",
            as: RevertEventResult.self
        )
    }

    func trackedFiles() async throws -> [String] {
        try await command(name: "trackedFiles", field: "trackedFiles", as: [String].self)
    }

    func storageStats() async throws -> StorageStatsSnapshot {
        try await command(name: "storageStats", field: "stats", as: StorageStatsSnapshot.self)
    }

    func fileHistory(filePath: String) async throws -> [SnapshotRecord] {
        try await command(name: "fileHistory", payload: ["filePath": filePath], field: "snapshots", as: [SnapshotRecord].self)
    }

    func fileHistoryContext(filePath: String, limit: Int = 20) async throws -> FileHistoryContext {
        try await command(
            name: "fileHistoryContext",
            payload: ["filePath": filePath, "limit": limit],
            field: "context",
            as: FileHistoryContext.self
        )
    }

    func sessionContext(sessionID: String, agent: TargetApp? = nil) async throws -> SessionContextDetail {
        var payload: [String: Any] = ["sessionID": sessionID]
        if let agent {
            payload["agent"] = agent.rawValue
        }
        return try await command(
            name: "sessionContext",
            payload: payload,
            field: "context",
            as: SessionContextDetail.self
        )
    }

    func snapshotData(hash: String) async throws -> Data? {
        try await optionalCommand(name: "snapshotData", payload: ["hash": hash], field: "data", as: Data.self)
    }

    func runGarbageCollection() async throws -> Int {
        try await command(name: "runGarbageCollection", field: "count", as: Int.self)
    }

    func runIntegrityCheck() async throws -> Bool {
        try await command(name: "runIntegrityCheck", field: "ok", as: Bool.self)
    }

    func listEmailAccounts() async throws -> [EmailAccountRecord] {
        try await command(name: "listEmailAccounts", field: "accounts", as: [EmailAccountRecord].self)
    }

    func syncStates(accountID: String) async throws -> [SyncStateRecord] {
        try await command(name: "listSyncStates", payload: ["accountID": accountID], field: "states", as: [SyncStateRecord].self)
    }

    func emailMessageCount() async throws -> Int {
        try await command(name: "emailMessageCount", field: "count", as: Int.self)
    }

    func addIMAPAccount(
        displayName: String,
        provider: EmailProvider,
        server: String,
        port: Int,
        username: String,
        password: String
    ) async throws -> EmailAccountRecord {
        try await command(
            name: "addIMAPAccount",
            payload: [
                "displayName": displayName,
                "provider": provider.rawValue,
                "server": server,
                "port": port,
                "username": username,
                "password": password,
            ],
            field: "account",
            as: EmailAccountRecord.self
        )
    }

    func removeEmailAccount(id: String) async throws {
        _ = try await xpc.command(name: "removeEmailAccount", payload: ["accountID": id])
    }

    func toggleEmailSync(accountID: String, enabled: Bool) async throws {
        _ = try await xpc.command(name: "toggleEmailSync", payload: ["accountID": accountID, "enabled": enabled])
    }

    func syncEmailNow(accountID: String) async throws -> SyncResult {
        try await command(name: "syncEmailNow", payload: ["accountID": accountID], field: "result", as: SyncResult.self)
    }

    func emailMessages(accountID: String? = nil, mailbox: String? = nil, ids: [String]? = nil, limit: Int = 500) async throws -> [EmailMessageRecord] {
        var payload: [String: Any] = ["limit": limit]
        if let accountID { payload["accountID"] = accountID }
        if let mailbox { payload["mailbox"] = mailbox }
        if let ids { payload["ids"] = ids }
        return try await command(name: "emailMessages", payload: payload, field: "messages", as: [EmailMessageRecord].self)
    }

    func domainCounts() async throws -> [String: Int] {
        try await command(name: "domainCounts", field: "counts", as: [String: Int].self)
    }

    func unreadCountAll() async throws -> Int {
        try await command(name: "unreadCountAll", field: "count", as: Int.self)
    }

    func unreadCount(accountID: String, mailbox: String? = nil) async throws -> Int {
        var payload: [String: Any] = ["accountID": accountID]
        if let mailbox { payload["mailbox"] = mailbox }
        return try await command(name: "unreadCount", payload: payload, field: "count", as: Int.self)
    }

    func imapMailboxes(accountID: String) async throws -> [IMAPMailboxRecord] {
        try await command(name: "imapMailboxes", payload: ["accountID": accountID], field: "mailboxes", as: [IMAPMailboxRecord].self)
    }

    func sharedEmailCount() async throws -> Int {
        try await command(name: "sharedEmailCount", field: "count", as: Int.self)
    }

    func sharedEmailIDs() async throws -> Set<String> {
        Set(try await command(name: "sharedEmailIDs", field: "ids", as: [String].self))
    }

    func sharedEmails(limit: Int = 500) async throws -> [EmailMessageRecord] {
        try await command(name: "sharedEmails", payload: ["limit": limit], field: "messages", as: [EmailMessageRecord].self)
    }

    func shareEmails(emailIDs: [String]) async throws {
        _ = try await xpc.command(name: "shareEmails", payload: ["emailIDs": emailIDs])
    }

    func unshareEmails(emailIDs: [String]) async throws {
        _ = try await xpc.command(name: "unshareEmails", payload: ["emailIDs": emailIDs])
    }

    func unshareAllEmails() async throws {
        _ = try await xpc.command(name: "unshareAllEmails")
    }

    func updateEmailReadState(emailID: String, isRead: Bool) async throws {
        _ = try await xpc.command(name: "updateEmailReadState", payload: ["emailID": emailID, "isRead": isRead])
    }

    func updateEmailFlagState(emailID: String, isFlagged: Bool, flagColor: String?) async throws {
        var payload: [String: Any] = ["emailID": emailID, "isFlagged": isFlagged]
        if let flagColor { payload["flagColor"] = flagColor }
        _ = try await xpc.command(name: "updateEmailFlagState", payload: payload)
    }

    func batchUpdateReadState(emailIDs: [String], isRead: Bool) async throws {
        _ = try await xpc.command(name: "batchUpdateReadState", payload: ["emailIDs": emailIDs, "isRead": isRead])
    }

    func batchUpdateFlagState(emailIDs: [String], isFlagged: Bool, flagColor: String?) async throws {
        var payload: [String: Any] = ["emailIDs": emailIDs, "isFlagged": isFlagged]
        if let flagColor { payload["flagColor"] = flagColor }
        _ = try await xpc.command(name: "batchUpdateFlagState", payload: payload)
    }

    func searchEmailMessages(
        tokens: [SearchToken],
        freeText: String,
        accountID: String?,
        mailbox: String?,
        filter: QuickFilter?,
        sortKey: EmailSortKey,
        limit: Int
    ) async throws -> [EmailMessageRecord] {
        var payload: [String: Any] = [
            "tokens": try XPCJSON.object(from: tokens),
            "freeText": freeText,
            "sortKey": try XPCJSON.object(from: sortKey),
            "limit": limit,
        ]
        if let accountID { payload["accountID"] = accountID }
        if let mailbox { payload["mailbox"] = mailbox }
        if let filter { payload["filter"] = try XPCJSON.object(from: filter) }
        return try await command(name: "searchEmailMessages", payload: payload, field: "messages", as: [EmailMessageRecord].self)
    }

    func createSmartMailbox(displayName: String, iconName: String, rulesJSON: String) async throws {
        _ = try await xpc.command(
            name: "createSmartMailbox",
            payload: ["displayName": displayName, "iconName": iconName, "rulesJSON": rulesJSON]
        )
    }

    func listSmartMailboxes() async throws -> [SmartMailboxRecord] {
        try await command(name: "listSmartMailboxes", field: "mailboxes", as: [SmartMailboxRecord].self)
    }

    func updateSmartMailbox(mailboxID: String, displayName: String, iconName: String, rulesJSON: String) async throws {
        _ = try await xpc.command(
            name: "updateSmartMailbox",
            payload: [
                "mailboxID": mailboxID,
                "displayName": displayName,
                "iconName": iconName,
                "rulesJSON": rulesJSON,
            ]
        )
    }

    func deleteSmartMailbox(mailboxID: String) async throws {
        _ = try await xpc.command(name: "deleteSmartMailbox", payload: ["mailboxID": mailboxID])
    }

    func emailBackupInfo() async throws -> EmailBackupInfo {
        try await command(name: "emailBackupInfo", field: "info", as: EmailBackupInfo.self)
    }

    private func command<T: Decodable>(
        name: String,
        payload: [String: Any] = [:],
        field: String? = nil,
        as type: T.Type
    ) async throws -> T {
        let response = try await xpc.command(name: name, payload: payload)
        if let field {
            guard let object = response[field], !(object is NSNull) else {
                throw ManifoldXPCError.malformedReply
            }
            return try XPCJSON.decode(T.self, from: object)
        }
        return try XPCJSON.decode(T.self, from: response)
    }

    private func optionalCommand<T: Decodable>(
        name: String,
        payload: [String: Any] = [:],
        field: String,
        as type: T.Type
    ) async throws -> T? {
        let response = try await xpc.command(name: name, payload: payload)
        guard let object = response[field], !(object is NSNull) else { return nil }
        return try XPCJSON.decode(T.self, from: object)
    }
}
