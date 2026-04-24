// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import ManifoldRuntime
import os

private let xpcLogger = Logger(subsystem: "com.spatialduality.manifold", category: "xpc")

private actor XPCConnectionRegistry {
    private var bridges: [String: ManifoldBridge] = [:]

    func insert(connectionID: String, bridge: ManifoldBridge) {
        bridges[connectionID] = bridge
    }

    func bridge(for connectionID: String) -> ManifoldBridge? {
        bridges[connectionID]
    }

    func remove(connectionID: String) -> ManifoldBridge? {
        bridges.removeValue(forKey: connectionID)
    }
}

private struct ConnectReplyBox: @unchecked Sendable {
    let reply: (String?, NSError?) -> Void
}

private struct ToolReplyBox: @unchecked Sendable {
    let reply: (Data, Bool) -> Void
}

private struct CommandReplyBox: @unchecked Sendable {
    let reply: (Data, NSError?) -> Void
}

/// Hosts the local XPC boundary between the app or MCP adapter and the runtime.
public final class ManifoldXPCService: NSObject, NSXPCListenerDelegate, ManifoldXPCProtocol, @unchecked Sendable {
    let runtime: ManifoldRuntime
    let agentVersion: String
    private let registry = XPCConnectionRegistry()

    /// Creates an exported XPC service backed by the shared runtime instance.
    public init(runtime: ManifoldRuntime, version: String = "0.4.0") {
        self.runtime = runtime
        self.agentVersion = version
        super.init()
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ManifoldXPCProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    public func connect(
        agent: String,
        clientName: String,
        clientVersion: String,
        initializeParams: Data,
        reply: @escaping (String?, NSError?) -> Void
    ) {
        let replyBox = ConnectReplyBox(reply: reply)
        let verifiedIdentity = ClientIdentityVerifier.verify(
            requestedAgent: agent,
            connection: NSXPCConnection.current()
        )
        guard verifiedIdentity.isVerified, let targetApp = verifiedIdentity.resolvedTargetApp else {
            let requestedTarget = TargetApp(rawValue: agent) ?? .cowork
            Task {
                await runtime.recordCoverageEvent(
                    agent: requestedTarget,
                    coverageState: .outsideCoverage,
                    eventType: "verification_failed",
                    message: verifiedIdentity.reason,
                    metadata: [
                        "requested_target_app": agent,
                        "verification_status": verifiedIdentity.status.rawValue,
                        "client_pid": "\(verifiedIdentity.clientProcessID)",
                    ],
                    dedupeKey: "verification:\(verifiedIdentity.clientProcessID):\(agent):\(verifiedIdentity.reason)"
                )
            }
            replyBox.reply(
                nil,
                NSError(
                    domain: "com.spatialduality.manifold.xpc",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: verifiedIdentity.reason]
                )
            )
            return
        }

        Task {
            let connectionID = UUID().uuidString
            let bridge = await runtime.bridge(for: connectionID, targetApp: targetApp, version: clientVersion)
            await bridge.registerVerifiedClientIdentity(verifiedIdentity)
            let params: [String: Any]
            do { params = try XPCJSON.dictionary(from: initializeParams) }
            catch { params = [:]; xpcLogger.warning("Malformed initializeParams: \(error.localizedDescription, privacy: .public)") }
            await bridge.registerClientContext(initializeParams: params)
            await registry.insert(connectionID: connectionID, bridge: bridge)
            replyBox.reply(connectionID, nil)
        }
    }

    public func disconnect(connectionID: String) {
        Task {
            if let bridge = await registry.remove(connectionID: connectionID) {
                await bridge.recordDisconnection()
            }
            await runtime.removeBridge(connectionID)
        }
    }

    public func callTool(
        connectionID: String,
        toolName: String,
        arguments: Data,
        reply: @escaping (Data, Bool) -> Void
    ) {
        let replyBox = ToolReplyBox(reply: reply)
        Task {
            guard let bridge = await registry.bridge(for: connectionID) else {
                let result = Self.errorResult("No active runtime connection for \(connectionID)")
                replyBox.reply((try? XPCJSON.data(from: result)) ?? Data(), true)
                return
            }

            let args: [String: Any]
            do { args = try XPCJSON.dictionary(from: arguments) }
            catch { args = [:]; xpcLogger.warning("Malformed tool arguments for \(toolName): \(error.localizedDescription, privacy: .public)") }
            let result = await Self.handleTool(name: toolName, arguments: args, bridge: bridge)
            let isError = result["isError"] as? Bool ?? false
            replyBox.reply((try? XPCJSON.data(from: result)) ?? Data(), isError)
        }
    }

    public func command(
        name: String,
        payload: Data,
        reply: @escaping (Data, NSError?) -> Void
    ) {
        let replyBox = CommandReplyBox(reply: reply)
        let authorization = ClientIdentityVerifier.authorizeCommand(
            name: name,
            connection: NSXPCConnection.current()
        )
        guard authorization.isAuthorized else {
            replyBox.reply(
                Data(),
                NSError(
                    domain: "com.spatialduality.manifold.xpc",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: authorization.reason]
                )
            )
            return
        }
        Task {
            do {
                let commandPayload: [String: Any]
                do { commandPayload = try XPCJSON.dictionary(from: payload) }
                catch { commandPayload = [:]; xpcLogger.warning("Malformed command payload for \(name): \(error.localizedDescription, privacy: .public)") }
                let result = try await handleCommand(name: name, payload: commandPayload)
                replyBox.reply(try XPCJSON.data(from: result), nil)
            } catch {
                replyBox.reply(Data(), XPCJSON.nsError(from: error))
            }
        }
    }

    private func handleCommand(name: String, payload: [String: Any]) async throws -> [String: Any] {
        switch name {
        case "ping":
            return ["ok": true, "agentVersion": agentVersion]

        case "getStatus":
            await runtime.scanForActiveWorkBlockDrift()
            let sources = try await runtime.grantStore.allSources()
            let claudePolicy = try await runtime.policyStore.policy(for: .cowork)
            let codexPolicy = try await runtime.policyStore.policy(for: .codex)
            let claudeEmailGovernance = try await runtime.emailGovernanceSummary(for: .cowork)
            let codexEmailGovernance = try await runtime.emailGovernanceSummary(for: .codex)
            let activeWorkBlock = try await runtime.workBlockStore.anyActiveBlock()
            let pendingApprovals = try await runtime.approvalQueue.pending()
            let connectedAgents = await runtime.connectedAgents
            let coverageSnapshots = await runtime.connectedClientSnapshots()
            let coverageEvents = await runtime.coverageEvents(limit: 20)
            return [
                "runtimeConnected": true,
                "activeBridgeCount": await runtime.activeBridgeCount,
                "connectedAgents": connectedAgents,
                "sources": sources.map(Self.sourceJSON),
                "claudePolicy": Self.policyJSON(claudePolicy),
                "codexPolicy": Self.policyJSON(codexPolicy),
                "claudeEmailGovernance": try XPCJSON.object(from: claudeEmailGovernance),
                "codexEmailGovernance": try XPCJSON.object(from: codexEmailGovernance),
                "activeWorkBlock": activeWorkBlock.map(Self.workBlockJSON) ?? NSNull(),
                "pendingApprovalCount": pendingApprovals.count,
                "agentCoverages": try XPCJSON.object(from: coverageSnapshots),
                "coverageEvents": try XPCJSON.object(from: coverageEvents),
            ]

        case "dataControlSummary":
            return ["summary": try XPCJSON.object(from: try await dataControlSummary())]

        case "pauseAgent":
            guard let agent = payload["agent"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.policyStore.pauseAgent(TargetApp(rawValue: agent) ?? .cowork)
            return ["ok": true]

        case "resumeAgent":
            guard let agent = payload["agent"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.policyStore.resumeAgent(TargetApp(rawValue: agent) ?? .cowork)
            return ["ok": true]

        case "listApprovalRequests":
            let requests = try await runtime.approvalQueue.pending()
            return ["requests": requests.map(Self.approvalJSON)]

        case "approveRequest":
            guard let id = payload["id"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.approvalQueue.approve(id: id)
            return ["ok": true]

        case "denyRequest":
            guard let id = payload["id"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.approvalQueue.deny(id: id)
            return ["ok": true]

        case "recentActivity":
            let limit = payload["limit"] as? Int ?? 20
            let entries = try await runtime.auditStore.recentEntries(limit: limit)
            return ["entries": entries.map(Self.auditJSON)]

        case "exposureLog":
            guard let connectionID = payload["connectionID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            let limit = payload["limit"] as? Int ?? 20
            let exposures = try await runtime.exposureStore.exposures(connectionID: connectionID, limit: limit)
            return ["exposures": exposures.map(Self.exposureJSON)]

        case "listSources":
            let sources = try await runtime.grantStore.allSources()
            return ["sources": sources.map(Self.sourceJSON)]

        case "addSource":
            guard let path = payload["path"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            let displayName = (payload["displayName"] as? String) ?? URL(fileURLWithPath: path).lastPathComponent
            let sourceID = try await runtime.grantStore.addSource(displayName: displayName, rootPath: path)
            try await runtime.privacyIndexCoordinator.sourceDidChange()
            guard let source = try await runtime.grantStore.source(id: sourceID) else {
                return ["ok": true]
            }
            return ["source": Self.sourceJSON(source)]

        case "removeSource":
            guard let sourceID = payload["sourceID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.grantStore.removeSource(sourceID: sourceID)
            try await runtime.standingWriteApprovalStore.removeGrants(sourceID: sourceID)
            try await runtime.fileVisibilityOverrideStore.clearOverrides(sourceID: sourceID)
            try await runtime.privacyIndexCoordinator.sourceDidChange()
            return ["ok": true]

        case "pauseSource":
            guard let sourceID = payload["sourceID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.grantStore.pauseSource(sourceID: sourceID)
            try await runtime.privacyIndexCoordinator.sourceDidChange()
            return ["ok": true]

        case "resumeSource":
            guard let sourceID = payload["sourceID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.grantStore.resumeSource(sourceID: sourceID)
            try await runtime.privacyIndexCoordinator.sourceDidChange()
            return ["ok": true]

        case "getPolicies":
            let claudePolicy = try await runtime.policyStore.policy(for: .cowork)
            let codexPolicy = try await runtime.policyStore.policy(for: .codex)
            let activeWorkBlock = try await runtime.workBlockStore.anyActiveBlock()
            return [
                "claudePolicy": Self.policyJSON(claudePolicy),
                "codexPolicy": Self.policyJSON(codexPolicy),
                "activeWorkBlock": activeWorkBlock.map(Self.workBlockJSON) ?? NSNull(),
            ]

        case "updateAccessRecordingLevel":
            guard let agent = payload["agent"] as? String,
                  let level = payload["level"] as? String,
                  let recordingLevel = AccessRecordingLevel(rawValue: level) else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.policyStore.updateAccessRecordingLevel(recordingLevel, for: TargetApp(rawValue: agent) ?? .cowork)
            return ["ok": true]

        default:
            if let result = try await handleExtendedCommand(name: name, payload: payload) {
                return result
            }
            throw NSError(
                domain: "com.spatialduality.manifold.xpc",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Unknown command: \(name)"]
            )
        }
    }

    private func dataControlSummary() async throws -> DataControlSummary {
        await runtime.scanForActiveWorkBlockDrift()
        let connectedAgents = await runtime.connectedAgents
        let coverageSnapshots = await runtime.connectedClientSnapshots()
        let activeWorkBlock = try await runtime.workBlockStore.anyActiveBlock()
        let pendingApprovals = try await runtime.approvalQueue.pending()
        let recentEntries = try await runtime.auditStore.recentEntries(limit: 1)
        let lastExposure = recentEntries.first.map(Self.summaryExposure)
        let recentSessions = try await runtime.auditStore.recentSessions(limit: 5)

        var agents: [DataControlSummary.Agent] = []
        for agent in TargetApp.allCases {
            let policy = try await runtime.policyStore.policy(for: agent)
            let coverage = coverageSnapshots.first { $0.agent == agent.rawValue }
            let visibleEmailCount = (try? await runtime.visibleEmailCount(for: agent)) ?? 0
            let sharedEmailCount = (try? runtime.emailStore.sharedEmailCount(agent: agent)) ?? 0
            agents.append(
                DataControlSummary.Agent(
                    agent: agent,
                    isConnected: connectedAgents.contains(agent.rawValue),
                    verificationStatus: coverage?.verificationStatus ?? .unknown,
                    coverageState: coverage?.coverageState,
                    isPaused: policy.isPaused,
                    defaultFileScopeCount: policy.allowedSourceIDs.count,
                    visibleEmailCount: visibleEmailCount,
                    sharedEmailCount: sharedEmailCount,
                    emailSensitivity: policy.emailSensitivity,
                    defaultEmailPolicy: policy.defaultEmailPolicy
                )
            )
        }

        return DataControlSummary(
            runtimeConnected: true,
            activeBridgeCount: await runtime.activeBridgeCount,
            agents: agents,
            activeWorkBlock: activeWorkBlock,
            pendingApprovalCount: pendingApprovals.count,
            lastExposure: lastExposure,
            recentHandoffSessions: recentSessions
        )
    }

    private static func handleTool(name: String, arguments: [String: Any], bridge: ManifoldBridge) async -> [String: Any] {
        do {
            let intent = accessIntent(from: arguments)
            switch name {
            case "get_status":
                let status = await bridge.getStatus()
                return textResult(formatStatus(status))

            case "get_coverage_status":
                let coverage = await bridge.currentCoverageSnapshot()
                let text = """
                Agent: \(coverage.agent)
                Coverage: \(coverage.coverageState.displayName)
                Verification: \(coverage.verificationStatus.displayName)
                \(coverage.hostBundleIdentifier.map { "Host: \($0)" } ?? "")
                \(coverage.reason.map { "Reason: \($0)" } ?? "")
                """
                return textResult(text.split(separator: "\n").joined(separator: "\n"))

            case "list_coverage_events":
                let limit = arguments["limit"] as? Int ?? 20
                let events = await bridge.recentCoverageEvents(limit: limit)
                if events.isEmpty { return textResult("No recent coverage events.") }
                let formatted = events.map {
                    "[\($0.timestamp)] \($0.coverageState.displayName) \($0.eventType): \($0.message)\($0.resourcePath.map { " (\($0))" } ?? "")"
                }
                return textResult(formatted.joined(separator: "\n"))

            case "list_files":
                let files = try await bridge.listFiles(intent: intent)
                if files.isEmpty { return textResult("No files available.") }
                let formatted = files.map { file in
                    let size = ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file)
                    return "[\(file.sourceName)] \(file.path)  (\(size), modified: \(file.lastModified.prefix(10)))"
                }
                return textResult("Source folders: \(Set(files.map(\.sourceName)).sorted().joined(separator: ", "))\n\n" + formatted.joined(separator: "\n"))

            case "read_file":
                guard let path = arguments["path"] as? String else {
                    return errorResult("'path' parameter required")
                }
                return textResult(try await bridge.readFile(path: path, intent: intent))

            case "write_file":
                guard let path = arguments["path"] as? String,
                      let content = arguments["content"] as? String else {
                    return errorResult("'path' and 'content' parameters required")
                }
                let result = try await bridge.writeFile(path: path, content: content)
                return textResult(result.message)

            case "search_files":
                guard let query = arguments["query"] as? String else {
                    return errorResult("'query' parameter required")
                }
                let results = try await bridge.searchFiles(query: query, intent: intent)
                if results.isEmpty { return textResult("No matches found for '\(query)'") }
                let formatted = results.map { "## [\($0.source)] \($0.path)\n" + $0.matches.joined(separator: "\n") }
                return textResult(formatted.joined(separator: "\n\n"))

            case "list_emails":
                let emails = try await bridge.listEmails(intent: intent)
                if emails.isEmpty { return textResult("No shared emails.") }
                let formatted = emails.map { "[\($0.id)] \($0.from) — \($0.subject) (\($0.date))" }
                return textResult(formatted.joined(separator: "\n"))

            case "read_email":
                guard let id = arguments["id"] as? String else {
                    return errorResult("'id' parameter required")
                }
                return textResult(try await bridge.readEmail(id: id, intent: intent))

            case "search_emails":
                guard let query = arguments["query"] as? String else {
                    return errorResult("'query' parameter required")
                }
                let emails = try await bridge.searchEmails(query: query, intent: intent)
                if emails.isEmpty { return textResult("No governed emails matched '\(query)'.") }
                let formatted = emails.map {
                    "[\($0.emailID)] \($0.sender) — \($0.subject)\n\($0.preview ?? "(no preview available)")"
                }
                return textResult(formatted.joined(separator: "\n\n"))

            case "list_changes":
                let changes = try await bridge.listChanges()
                if changes.isEmpty { return textResult("No changes recorded yet.") }
                let formatted = changes.map { "[\($0.timestamp)] \($0.action.uppercased()) \($0.path ?? "") (by \($0.agent ?? "unknown"))" }
                return textResult(formatted.joined(separator: "\n"))

            case "file_info":
                guard let path = arguments["path"] as? String else {
                    return errorResult("'path' parameter required")
                }
                let info = try await bridge.fileInfo(path: path, intent: intent)
                let size = ByteCountFormatter.string(fromByteCount: Int64(info.sizeBytes), countStyle: .file)
                var text = """
                File: \(info.path)
                Source: \(info.sourceName)
                Size: \(size)
                Type: .\(info.fileExtension)
                Binary: \(info.isBinary ? "yes" : "no")
                Modified: \(info.lastModified)
                """
                if let contents = info.archiveContents {
                    text += "\n\nArchive contents (\(contents.count) files):\n" + contents.joined(separator: "\n")
                }
                return textResult(text)

            case "list_archive":
                guard let path = arguments["path"] as? String else {
                    return errorResult("'path' parameter required")
                }
                let contents = try await bridge.listArchive(path: path, intent: intent)
                return textResult("Archive: \(path)\n\(contents.count) files:\n\n" + contents.joined(separator: "\n"))

            case "extract_file":
                guard let archivePath = arguments["archive_path"] as? String,
                      let filePath = arguments["file_path"] as? String else {
                    return errorResult("'archive_path' and 'file_path' parameters required")
                }
                return textResult(try await bridge.extractFile(archivePath: archivePath, filePath: filePath, intent: intent))

            case "list_sessions":
                let limit = (arguments["limit"] as? String).flatMap(Int.init) ?? 20
                let sessions = try await bridge.listSessions(limit: limit)
                if sessions.isEmpty { return textResult("No past sessions recorded.") }
                let formatted = sessions.map { session in
                    "[\(session.grantID.prefix(12))...] \(session.targetApp) | \(session.startedAt.prefix(10)) → \(session.endedAt.prefix(10))\n  \(session.summaryPreview)"
                }
                return textResult("Past sessions (\(sessions.count)):\n\n" + formatted.joined(separator: "\n\n"))

            case "get_session":
                guard let grantID = arguments["grant_id"] as? String else {
                    return errorResult("'grant_id' parameter required")
                }
                return textResult(formatSessionDetail(try await bridge.getSession(grantID: grantID)))

            case "get_file_history_context":
                guard let filePath = arguments["file_path"] as? String else {
                    return errorResult("'file_path' parameter required")
                }
                let limit = intArgument(arguments["limit"]) ?? 20
                return textResult(formatFileHistoryContext(try await bridge.fileHistoryContext(filePath: filePath, limit: limit)))

            case "get_session_context":
                guard let sessionID = arguments["session_id"] as? String else {
                    return errorResult("'session_id' parameter required")
                }
                return textResult(formatSessionContext(try await bridge.sessionContext(sessionID: sessionID)))

            case "save_session_note":
                guard let note = arguments["note"] as? String else {
                    return errorResult("'note' parameter required")
                }
                let noteType = (arguments["note_type"] as? String).flatMap(SessionSummaryKind.init(rawValue:)) ?? .checkpointNote
                return textResult(try await bridge.saveSessionNote(note: note, noteType: noteType))

            case "read_range":
                guard let path = arguments["path"] as? String,
                      let startLine = intArgument(arguments["start_line"]),
                      let endLine = intArgument(arguments["end_line"]) else {
                    return errorResult("'path', 'start_line', and 'end_line' parameters required")
                }
                return textResult(try await bridge.readRange(path: path, startLine: startLine, endLine: endLine, intent: intent))

            case "diff_file":
                guard let path = arguments["path"] as? String else {
                    return errorResult("'path' parameter required")
                }
                return textResult(try await bridge.diffFile(path: path, intent: intent))

            case "search_structured":
                guard let query = arguments["query"] as? String else {
                    return errorResult("'query' parameter required")
                }
                let limit = intArgument(arguments["limit"]) ?? 10
                return textResult(try await bridge.searchStructured(query: query, limit: limit, intent: intent))

            default:
                return errorResult("Unknown tool: \(name)")
            }
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    private static func textResult(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]]]
    }

    private static func errorResult(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": true]
    }

    private static func intArgument(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let stringValue = value as? String { return Int(stringValue) }
        return nil
    }

    private static func accessIntent(from arguments: [String: Any]) -> AccessIntent? {
        let intent = AccessIntent(
            summary: arguments["intent_summary"] as? String,
            details: arguments["intent_details"] as? String
        )
        return intent.isEmpty ? nil : intent
    }

    private static func formatStatus(_ status: StatusResult) -> String {
        if status.active {
            var lines: [String] = []
            if let grantID = status.grantID {
                lines.append("Status: ACTIVE (grant \(grantID.prefix(12))...)")
            } else {
                lines.append("Status: ACTIVE (legacy mode)")
            }
            lines.append("Active sources: \(status.sources.joined(separator: ", "))")
            if !status.pausedSources.isEmpty {
                lines.append("Paused sources (not accessible): \(status.pausedSources.joined(separator: ", "))")
            }
            lines.append("Files: \(status.fileCount)")
            lines.append("Emails: \(status.emailCount)")
            if status.noteCaptureMode != SessionNoteCaptureMode.off.rawValue {
                lines.append("Session notes: \(status.noteCaptureMode.uppercased())")
            }
            if let noteGuidance = status.noteGuidance {
                lines.append(noteGuidance)
            }
            lines.append(status.message)
            return lines.joined(separator: "\n")
        } else if !status.pausedSources.isEmpty {
            return """
            Status: ALL SOURCES PAUSED
            Paused sources: \(status.pausedSources.joined(separator: ", "))
            \(status.message)
            """
        } else {
            return status.message
        }
    }

    private static func formatSessionDetail(_ detail: SessionDetail) -> String {
        var lines: [String] = []
        lines.append("Grant: \(detail.grantID)")
        lines.append("Target: \(detail.targetApp)")
        lines.append("Status: \(detail.status)")
        lines.append("Started: \(detail.startedAt)")
        if let ended = detail.endedAt { lines.append("Ended: \(ended)") }
        lines.append("Sources: \(detail.sources.joined(separator: ", "))")
        lines.append("Session notes: \(detail.noteCaptureMode.uppercased())")
        lines.append("")

        if let summary = detail.summaryMarkdown {
            lines.append(summary)
        } else {
            lines.append("No summary recorded.")
        }

        if !detail.sessionNotes.isEmpty {
            lines.append("")
            lines.append("Session Notes:")
            for note in detail.sessionNotes {
                let kind = SessionSummaryKind(rawValue: note.kind)?.displayName ?? note.kind
                lines.append("- \(kind) (\(note.origin), \(note.endedAt))")
                lines.append(note.markdown)
                lines.append("")
            }
        }

        if !detail.filesApplied.isEmpty {
            lines.append("\nFiles applied (\(detail.filesApplied.count)):")
            for file in detail.filesApplied { lines.append("  ✓ \(file)") }
        }
        if !detail.filesConflicted.isEmpty {
            lines.append("\nFiles conflicted (\(detail.filesConflicted.count)):")
            for file in detail.filesConflicted { lines.append("  ✗ \(file)") }
        }
        if detail.totalPromotions == 0 {
            lines.append("\nNo file promotions recorded.")
        }

        return lines.joined(separator: "\n")
    }

    private static func formatFileHistoryContext(_ context: FileHistoryContext) -> String {
        var lines: [String] = []
        lines.append("File: \(context.filePath)")
        lines.append("Snapshots: \(context.snapshots.count)")
        if !context.relatedSessionIDs.isEmpty {
            lines.append("Related sessions: \(context.relatedSessionIDs.joined(separator: ", "))")
        }

        if !context.snapshots.isEmpty {
            lines.append("")
            lines.append("Recent snapshots:")
            for snapshot in context.snapshots.prefix(10) {
                let kind: String
                if snapshot.isBaseline {
                    kind = "baseline"
                } else if snapshot.isDelete {
                    kind = "delete"
                } else {
                    kind = "revision"
                }
                lines.append("- \(snapshot.timestamp) — \(kind) (\(snapshot.filePath))")
            }
        }

        if !context.relatedActivity.isEmpty {
            lines.append("")
            lines.append("Nearby activity:")
            for entry in context.relatedActivity.prefix(10) {
                lines.append("- \(entry.timestamp) — \(entry.action) \(entry.filePath ?? "")".trimmingCharacters(in: .whitespaces))
            }
        }

        if !context.recentExposures.isEmpty {
            lines.append("")
            lines.append("Recent exposures:")
            for exposure in context.recentExposures.prefix(10) {
                let preview = exposure.payloadPreview?.replacingOccurrences(of: "\n", with: " ") ?? "(no preview stored)"
                lines.append("- \(exposure.toolName) at \(ISO8601DateFormatter.shared.string(from: Date(timeIntervalSince1970: exposure.timestamp))) — \(preview)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func formatSessionContext(_ context: SessionContextDetail) -> String {
        var lines: [String] = []
        lines.append("Session: \(context.session?.id ?? "unknown")")
        if let grantID = context.grantID {
            lines.append("Grant: \(grantID)")
        }
        if let session = context.session {
            lines.append("Agent: \(session.agent)")
            lines.append("Window: \(session.startTime) → \(session.endTime)")
            lines.append("Actions: \(session.actionCount) (\(session.readCount) reads, \(session.writeCount) writes, \(session.searchCount) searches)")
        }
        if !context.filePaths.isEmpty {
            lines.append("")
            lines.append("Files:")
            for path in context.filePaths.prefix(20) {
                lines.append("- \(path)")
            }
        }
        if !context.emails.isEmpty {
            lines.append("")
            lines.append("Emails:")
            for email in context.emails.prefix(20) {
                if email.isRedacted {
                    lines.append("- [\(email.id)] \(email.subject)\(email.redactionReason.map { " (\($0))" } ?? "")")
                } else {
                    lines.append("- [\(email.id)] \(email.from) — \(email.subject)")
                }
            }
        }
        if !context.notes.isEmpty {
            lines.append("")
            lines.append("Notes:")
            for note in context.notes.prefix(10) {
                let kind = note.kind.displayName
                lines.append("- \(kind) (\(note.origin), \(note.endedAt))")
            }
        }
        if !context.events.isEmpty {
            lines.append("")
            lines.append("Timeline:")
            for event in context.events.prefix(20) {
                lines.append("- \(event.timestamp) — \(event.action) \(event.filePath ?? "")".trimmingCharacters(in: .whitespaces))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func sourceJSON(_ source: SourceRecord) -> [String: Any] {
        [
            "sourceID": source.sourceID,
            "displayName": source.displayName,
            "originalRootPath": source.originalRootPath,
            "status": source.status,
            "createdAt": source.createdAt,
            "updatedAt": source.updatedAt,
            "isAccessible": source.isAccessible,
            "isPaused": source.isPaused,
            "isRemoved": source.isRemoved,
        ]
    }

    private static func policyJSON(_ policy: AgentAccessPolicy) -> [String: Any] {
        [
            "id": policy.id,
            "agent": policy.agent.rawValue,
            "allowedSourceIDs": policy.allowedSourceIDs.sorted(),
            "allowedEmailDomains": policy.allowedEmailDomains.sorted(),
            "emailSensitivity": policy.emailSensitivity.rawValue,
            "defaultEmailPolicy": policy.defaultEmailPolicy.rawValue,
            "accessRecordingLevel": policy.accessRecordingLevel.rawValue,
            "isPaused": policy.isPaused,
            "hasCompletedFirstGrant": policy.hasCompletedFirstGrant,
            "createdAt": policy.createdAt,
            "updatedAt": policy.updatedAt,
        ]
    }

    private static func workBlockJSON(_ block: WorkBlockRecord) -> [String: Any] {
        [
            "id": block.id,
            "agent": block.agent.rawValue,
            "grantID": block.grantID,
            "sourceIDs": block.sourceIDs,
            "startedAt": block.startedAt,
            "endedAt": block.endedAt as Any,
            "status": block.status.rawValue,
            "modifiedFileCount": block.modifiedFileCount,
            "newFileCount": block.newFileCount,
            "isPaused": block.isPaused,
        ]
    }

    private static func approvalJSON(_ request: ApprovalQueue.PendingRequest) -> [String: Any] {
        [
            "id": request.id,
            "connectionID": request.connectionID,
            "agent": request.agent,
            "path": request.path,
            "action": request.action,
            "requestedAt": request.requestedAt,
            "status": request.status.rawValue,
        ]
    }

    private static func auditJSON(_ entry: ManifoldKit.AuditEntry) -> [String: Any] {
        [
            "id": entry.id,
            "timestamp": entry.timestamp,
            "runID": entry.runID as Any,
            "workspaceID": entry.workspaceID as Any,
            "agent": entry.agent as Any,
            "action": entry.action,
            "filePath": entry.filePath as Any,
            "beforeHash": entry.beforeHash as Any,
            "afterHash": entry.afterHash as Any,
            "metadata": entry.metadata as Any,
            "sessionID": entry.sessionID as Any,
            "grantID": entry.grantID as Any,
        ]
    }

    private static func summaryExposure(_ entry: ManifoldKit.AuditEntry) -> DataControlSummary.Exposure {
        DataControlSummary.Exposure(
            id: entry.id,
            timestamp: entry.timestamp,
            agent: entry.agent.flatMap(TargetApp.init(rawValue:)),
            action: entry.action,
            resourcePath: entry.filePath,
            sessionID: entry.sessionID,
            grantID: entry.grantID
        )
    }

    private static func exposureJSON(_ record: ExposureRecord) -> [String: Any] {
        [
            "id": record.id,
            "connectionID": record.connectionID,
            "agent": record.agent,
            "toolName": record.toolName,
            "resourcePath": record.resourcePath as Any,
            "byteCount": record.byteCount,
            "contentHash": record.contentHash,
            "exposureType": record.exposureType,
            "timestamp": record.timestamp,
            "accessDecisionID": record.accessDecisionID,
            "payloadPreview": record.payloadPreview as Any,
            "payloadPreviewTruncated": record.payloadPreviewTruncated,
            "clientIdentity": record.clientIdentity as Any,
            "intentSummary": record.intentSummary as Any,
            "intentDetails": record.intentDetails as Any,
        ]
    }
}
