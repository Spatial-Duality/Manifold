// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import ManifoldKit
import ManifoldRuntime
import os

private let appCommandLogger = Logger(subsystem: "com.spatialduality.manifold", category: "xpc-app")

private struct StorageStatsPayload: Codable, Sendable {
    let storageUsed: Int64
}

private struct EmailBackupInfoPayload: Codable, Sendable {
    let path: String
    let diskUsage: Int64
}

extension ManifoldXPCService {
    func handleExtendedCommand(name: String, payload: [String: Any]) async throws -> [String: Any]? {
        switch name {
        case "activeGrantState":
            return try await activeGrantStateCommand(payload: payload)

        case "addSourceToPolicy":
            guard let sourceID = payload["sourceID"] as? String,
                  let agentRaw = payload["agent"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.policyStore.addSource(sourceID, to: TargetApp(rawValue: agentRaw) ?? .cowork)
            return ["ok": true]

        case "removeSourceFromPolicy":
            guard let sourceID = payload["sourceID"] as? String,
                  let agentRaw = payload["agent"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            let agent = TargetApp(rawValue: agentRaw) ?? .cowork
            try await runtime.policyStore.removeSource(sourceID, from: agent)
            try await runtime.standingWriteApprovalStore.removeGrants(agent: agent, sourceID: sourceID)
            return ["ok": true]

        case "sessionPreview":
            return try await sessionPreviewCommand(payload: payload)

        case "startTrackedRun":
            return try await startTrackedRunCommand(payload: payload)

        case "trackedFiles":
            return ["trackedFiles": try XPCJSON.object(from: await runtime.snapshotStore.allTrackedFiles())]

        case "storageStats":
            return [
                "stats": try XPCJSON.object(
                    from: StorageStatsPayload(
                        storageUsed: await runtime.contentStore.totalSize()
                    )
                )
            ]

        case "fileHistory":
            guard let filePath = payload["filePath"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["snapshots": try XPCJSON.object(from: await runtime.snapshotStore.fileHistory(filePath: filePath))]

        case "fileHistoryContext":
            guard let filePath = payload["filePath"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            let limit = payload["limit"] as? Int ?? 20
            return ["context": try XPCJSON.object(from: await runtime.fileHistoryContext(filePath: filePath, limit: limit))]

        case "sessionContext":
            guard let sessionID = payload["sessionID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            let viewerAgent: TargetApp?
            if let agentRaw = payload["agent"] as? String {
                viewerAgent = TargetApp(rawValue: agentRaw)
            } else {
                viewerAgent = nil
            }
            return ["context": try XPCJSON.object(from: await runtime.sessionContext(sessionID: sessionID, viewingAs: viewerAgent))]

        case "getEmailRuleSet":
            guard let agentRaw = payload["agent"] as? String,
                  let agent = TargetApp(rawValue: agentRaw) else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["ruleSet": try XPCJSON.object(from: await runtime.emailRuleStore.ruleSet(for: agent))]

        case "updateEmailRuleSet":
            guard let agentRaw = payload["agent"] as? String,
                  let agent = TargetApp(rawValue: agentRaw),
                  let ruleSetObject = payload["ruleSet"] else {
                throw ManifoldXPCError.invalidPayload
            }
            var ruleSet = try XPCJSON.decode(EmailRuleSet.self, from: ruleSetObject)
            ruleSet = EmailRuleSet(
                agent: agent,
                shields: ruleSet.shields,
                domainRules: ruleSet.domainRules,
                contactRules: ruleSet.contactRules,
                keywordRules: ruleSet.keywordRules,
                defaultPolicy: ruleSet.defaultPolicy,
                emailSensitivity: ruleSet.emailSensitivity
            )
            try await runtime.emailRuleStore.updateRuleSet(ruleSet)
            return ["ok": true]

        case "getEmailRuleActivitySummary":
            guard let agentRaw = payload["agent"] as? String,
                  let agent = TargetApp(rawValue: agentRaw) else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["summary": try XPCJSON.object(from: await runtime.emailRuleActivitySummary(for: agent))]

        case "listFileVisibilityOverrides":
            guard let agentRaw = payload["agent"] as? String,
                  let agent = TargetApp(rawValue: agentRaw) else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["overrides": try XPCJSON.object(from: try await runtime.fileVisibilityOverrideStore.overrides(agent: agent))]

        case "setFileVisibilityOverride":
            guard let agentRaw = payload["agent"] as? String,
                  let agent = TargetApp(rawValue: agentRaw),
                  let sourceID = payload["sourceID"] as? String,
                  let relativePath = payload["relativePath"] as? String,
                  let decisionRaw = payload["decision"] as? String,
                  let decision = FileVisibilityOverrideDecision(rawValue: decisionRaw) else {
                throw ManifoldXPCError.invalidPayload
            }
            let isDirectory = payload["isDirectory"] as? Bool ?? false
            try await runtime.fileVisibilityOverrideStore.setOverride(
                agent: agent,
                sourceID: sourceID,
                relativePath: relativePath,
                isDirectory: isDirectory,
                decision: decision
            )
            return ["ok": true]

        case "clearFileVisibilityOverride":
            guard let agentRaw = payload["agent"] as? String,
                  let agent = TargetApp(rawValue: agentRaw),
                  let sourceID = payload["sourceID"] as? String,
                  let relativePath = payload["relativePath"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            let isDirectory = payload["isDirectory"] as? Bool ?? false
            try await runtime.fileVisibilityOverrideStore.clearOverride(
                agent: agent,
                sourceID: sourceID,
                relativePath: relativePath,
                isDirectory: isDirectory
            )
            return ["ok": true]

        case "setManyFileVisibilityOverrides":
            // Bulk-action batch write for the unified Access surface multi-select
            // bar. Decoded as an array of FileVisibilityOverrideRecord so the UI
            // can express mixed allow/deny in a single round-trip.
            let overrides = try decodePayload([FileVisibilityOverrideRecord].self, key: "overrides", from: payload, default: [])
            try await runtime.fileVisibilityOverrideStore.setManyOverrides(overrides)
            return ["ok": true, "count": overrides.count]

        case "listAccessTemplatesForAgent":
            guard let agentRaw = payload["agent"] as? String,
                  let agent = TargetApp(rawValue: agentRaw) else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["templates": try XPCJSON.object(from: try await runtime.accessStore.templatesForAgent(agent))]

        case "saveAccessTemplate":
            guard let name = payload["name"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            let presetID = payload["presetID"] as? String
            let targetAppRaw = payload["targetApp"] as? String
            let targetApp = targetAppRaw.flatMap(TargetApp.init(rawValue:))
            let scopes = try decodePayload([FileSelectionScope].self, key: "fileScopes", from: payload, default: [])
            let emailIDs = payload["emailIDs"] as? [String] ?? []
            let saved = try await runtime.accessStore.savePreset(
                id: presetID,
                name: name,
                targetApp: targetApp,
                fileScopes: scopes,
                emailIDs: emailIDs
            )
            return ["template": try XPCJSON.object(from: saved)]

        case "deleteAccessTemplate":
            guard let presetID = payload["presetID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.accessStore.deletePreset(id: presetID)
            return ["ok": true]

        case "startSessionFromTemplate":
            return try await startSessionFromTemplateCommand(payload: payload)

        case "getFilterMode":
            // Effective per-agent mode (per-agent override > global > .off).
            // If `agent` omitted, returns the global default.
            if let agentRaw = payload["agent"] as? String,
               let agent = TargetApp(rawValue: agentRaw) {
                return ["mode": try await runtime.filterModeStore.mode(for: agent).rawValue]
            }
            return ["mode": try await runtime.filterModeStore.globalMode().rawValue]

        case "setFilterMode":
            guard let modeRaw = payload["mode"] as? String,
                  let mode = FilterMode(rawValue: modeRaw) else {
                throw ManifoldXPCError.invalidPayload
            }
            // If agent provided, set per-agent. Otherwise set global default.
            if let agentRaw = payload["agent"] as? String,
               let agent = TargetApp(rawValue: agentRaw) {
                try await runtime.filterModeStore.setMode(mode, for: agent)
            } else {
                try await runtime.filterModeStore.setGlobalMode(mode)
            }
            return ["ok": true]

        case "clearAgentFilterMode":
            // Clear a per-agent override so the agent falls back to the global default.
            guard let agentRaw = payload["agent"] as? String,
                  let agent = TargetApp(rawValue: agentRaw) else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.filterModeStore.setMode(nil, for: agent)
            return ["ok": true]

        case "addFilterModeOverrides":
            // Bulk override-and-share approvals from the multi-select sheet.
            let overrides = try decodePayload([FilterModeOverrideRecord].self, key: "overrides", from: payload, default: [])
            try await runtime.filterModeStore.addOverrides(overrides)
            return ["ok": true, "count": overrides.count]

        case "listFilterModeOverrides":
            guard let grantID = payload["grantID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["overrides": try XPCJSON.object(from: try await runtime.filterModeStore.overrides(grantID: grantID))]

        case "aiTouchedFilePaths":
            // File paths whose snapshot timeline contains at least one
            // non-baseline agent-authored entry. Drives the sparkle
            // indicator in the Files table.
            return ["paths": Array(try await runtime.snapshotStore.aiTouchedFilePaths())]

        case "fileExposures":
            // Per-file exposure timeline used by the inspector to show
            // "Claude read 5× · Codex 0×". The runtime returns the recent
            // ExposureRecord rows; the app aggregates per agent.
            guard let resourcePath = payload["resourcePath"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            let limit = payload["limit"] as? Int ?? 100
            let records = try await runtime.exposureStore.exposures(resourcePath: resourcePath, limit: limit)
            return ["exposures": try XPCJSON.object(from: records)]

        case "snapshotData":
            guard let hash = payload["hash"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["data": try XPCJSON.object(from: await runtime.contentStore.retrieve(hash: hash))]

        case "runGarbageCollection":
            return ["count": try await runtime.contentStore.garbageCollect()]

        case "runIntegrityCheck":
            return ["ok": try runtime.db.integrityCheck()]

        case "recentSessions":
            let limit = payload["limit"] as? Int ?? 20
            return ["sessions": try XPCJSON.object(from: await runtime.auditStore.recentSessions(limit: limit))]

        case "getCoverageStatus":
            return ["agentCoverages": try XPCJSON.object(from: await runtime.connectedClientSnapshots())]

        case "listCoverageEvents":
            let limit = payload["limit"] as? Int ?? 20
            return ["events": try XPCJSON.object(from: await runtime.coverageEvents(limit: limit))]

        case "sessionEvents":
            guard let sessionID = payload["sessionID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["events": try XPCJSON.object(from: await runtime.auditStore.sessionEvents(sessionID: sessionID))]

        case "restoreSnapshot":
            guard let snapshotID = payload["snapshotID"] as? Int,
                  let filePath = payload["filePath"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["result": try XPCJSON.object(from: await restoreSnapshot(snapshotID: snapshotID, filePath: filePath))]

        case "revertSessionEvent":
            guard let grantID = payload["grantID"] as? String,
                  let eventObject = payload["event"] else {
                throw ManifoldXPCError.invalidPayload
            }
            let force = payload["force"] as? Bool ?? false
            let event = try XPCJSON.decode(SessionEvent.self, from: eventObject)
            return ["result": try await revertSessionEvent(event: event, grantID: grantID, force: force)]

        case "markWorkBlockReviewing":
            guard let workBlockID = payload["workBlockID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.workBlockStore.markReviewing(id: workBlockID)
            return ["ok": true]

        case "cancelWorkBlockReview":
            guard let workBlockID = payload["workBlockID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.workBlockStore.resumeBlock(id: workBlockID)
            return ["ok": true]

        case "pauseTrackedRun":
            guard let workBlockID = payload["workBlockID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.workBlockStore.pauseBlock(id: workBlockID)
            return ["ok": true]

        case "resumeTrackedRun":
            guard let workBlockID = payload["workBlockID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.workBlockStore.resumeBlock(id: workBlockID)
            return ["ok": true]

        case "discardTrackedRun":
            guard let workBlockID = payload["workBlockID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.workBlockStore.endBlock(id: workBlockID, status: .discarded)
            if let endSession = payload["endSession"] as? Bool, endSession,
               let grantID = payload["grantID"] as? String {
                try await runtime.grantStore.endGrant(grantID: grantID, reason: .ended)
            }
            return ["ok": true]

        case "promotionPreview":
            let activeWorkBlock = try await runtime.workBlockStore.anyActiveBlock()
            let grantID = payload["grantID"] as? String ?? activeWorkBlock?.grantID
            guard let grantID else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["preview": try await previewTrackedRun(grantID: grantID)]

        case "applyTrackedRun":
            let activeWorkBlock = try await runtime.workBlockStore.anyActiveBlock()
            let grantID = payload["grantID"] as? String ?? activeWorkBlock?.grantID
            guard let grantID else {
                throw ManifoldXPCError.invalidPayload
            }
            let endSession = payload["endSession"] as? Bool ?? false
            return ["result": try await applyTrackedRun(grantID: grantID, endSession: endSession)]

        case "listEmailAccounts":
            return ["accounts": try XPCJSON.object(from: runtime.emailStore.allEmailAccounts())]

        case "listSyncStates":
            guard let accountID = payload["accountID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["states": try XPCJSON.object(from: runtime.emailStore.syncStates(accountID: accountID))]

        case "emailMessageCount":
            return ["count": try runtime.emailStore.emailMessageCount()]

        case "addIMAPAccount":
            guard let displayName = payload["displayName"] as? String,
                  let providerRaw = payload["provider"] as? String,
                  let provider = EmailProvider(rawValue: providerRaw),
                  let server = payload["server"] as? String,
                  let port = payload["port"] as? Int,
                  let username = payload["username"] as? String,
                  let password = payload["password"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            let connection = IMAPConnection(host: server, port: UInt16(port))
            try await connection.connect()
            try await connection.login(username: username, password: password)
            await connection.disconnect()

            let account = try runtime.emailStore.addEmailAccount(
                displayName: displayName,
                providerType: provider.rawValue,
                server: server,
                port: port,
                username: username,
                authType: "password",
                keychainRef: nil,
                syncIntervalSeconds: 300
            )
            guard KeychainHelper.store(accountID: account.accountID, credential: password) else {
                try? runtime.emailStore.removeEmailAccount(id: account.accountID)
                throw NSError(
                    domain: "com.spatialduality.manifold.xpc",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to store credentials securely"]
                )
            }
            await runtime.emailSyncEngine.register(accountID: account.accountID)
            await runtime.privacyIndexCoordinator.bootstrap()
            return ["account": try XPCJSON.object(from: account)]

        case "removeEmailAccount":
            guard let accountID = payload["accountID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            await runtime.emailSyncEngine.unregister(accountID: accountID)
            KeychainHelper.delete(accountID: accountID)
            try runtime.emailStore.removeEmailAccount(id: accountID)
            await runtime.privacyIndexCoordinator.bootstrap()
            return ["ok": true]

        case "toggleEmailSync":
            guard let accountID = payload["accountID"] as? String,
                  let enabled = payload["enabled"] as? Bool else {
                throw ManifoldXPCError.invalidPayload
            }
            try runtime.emailStore.setEmailAccountSyncEnabled(accountID: accountID, enabled: enabled)
            if enabled {
                await runtime.emailSyncEngine.register(accountID: accountID)
            } else {
                await runtime.emailSyncEngine.unregister(accountID: accountID)
            }
            await runtime.privacyIndexCoordinator.bootstrap()
            return ["ok": true]

        case "syncEmailNow":
            guard let accountID = payload["accountID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            let result = try await runtime.emailSyncEngine.syncNow(accountID: accountID)
            await runtime.privacyIndexCoordinator.bootstrap()
            return ["result": try XPCJSON.object(from: result)]

        case "emailMessages":
            return ["messages": try XPCJSON.object(from: try emailMessages(payload: payload))]

        case "domainCounts":
            let counts = Dictionary(uniqueKeysWithValues: try runtime.emailStore.domainCounts().map { ($0.domain, $0.count) })
            return ["counts": try XPCJSON.object(from: counts)]

        case "unreadCountAll":
            return ["count": try runtime.emailStore.unreadCountAll()]

        case "unreadCount":
            guard let accountID = payload["accountID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            if let mailbox = payload["mailbox"] as? String {
                return ["count": try runtime.emailStore.unreadCount(accountID: accountID, mailbox: mailbox)]
            }
            return ["count": try runtime.emailStore.unreadCount(accountID: accountID)]

        case "imapMailboxes":
            guard let accountID = payload["accountID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["mailboxes": try XPCJSON.object(from: runtime.emailStore.imapMailboxes(accountID: accountID))]

        case "sharedEmailCount":
            let agent = targetApp(from: payload) ?? .cowork
            return ["count": try runtime.emailStore.sharedEmailCount(agent: agent)]

        case "sharedEmailIDs":
            let agent = targetApp(from: payload) ?? .cowork
            return ["ids": Array(try runtime.emailStore.sharedEmailIDs(agent: agent)).sorted()]

        case "sharedEmails":
            let agent = targetApp(from: payload) ?? .cowork
            let limit = payload["limit"] as? Int ?? 500
            return ["messages": try XPCJSON.object(from: runtime.emailStore.sharedEmails(agent: agent, limit: limit))]

        case "shareEmails":
            let agent = targetApp(from: payload) ?? .cowork
            let emailIDs = payload["emailIDs"] as? [String] ?? []
            try runtime.emailStore.shareEmails(emailIDs: emailIDs, for: agent)
            return ["ok": true]

        case "unshareEmails":
            let agent = targetApp(from: payload) ?? .cowork
            let emailIDs = payload["emailIDs"] as? [String] ?? []
            try runtime.emailStore.unshareEmails(emailIDs: emailIDs, for: agent)
            return ["ok": true]

        case "unshareAllEmails":
            try runtime.emailStore.unshareAllEmails()
            return ["ok": true]

        case "updateEmailReadState":
            guard let emailID = payload["emailID"] as? String,
                  let isRead = payload["isRead"] as? Bool else {
                throw ManifoldXPCError.invalidPayload
            }
            try runtime.emailStore.updateEmailReadState(emailID: emailID, isRead: isRead)
            return ["ok": true]

        case "updateEmailFlagState":
            guard let emailID = payload["emailID"] as? String,
                  let isFlagged = payload["isFlagged"] as? Bool else {
                throw ManifoldXPCError.invalidPayload
            }
            try runtime.emailStore.updateEmailFlagState(
                emailID: emailID,
                isFlagged: isFlagged,
                flagColor: payload["flagColor"] as? String
            )
            return ["ok": true]

        case "batchUpdateReadState":
            let emailIDs = payload["emailIDs"] as? [String] ?? []
            guard let isRead = payload["isRead"] as? Bool else {
                throw ManifoldXPCError.invalidPayload
            }
            try runtime.emailStore.batchUpdateReadState(emailIDs: emailIDs, isRead: isRead)
            return ["ok": true]

        case "batchUpdateFlagState":
            let emailIDs = payload["emailIDs"] as? [String] ?? []
            guard let isFlagged = payload["isFlagged"] as? Bool else {
                throw ManifoldXPCError.invalidPayload
            }
            try runtime.emailStore.batchUpdateFlagState(
                emailIDs: emailIDs,
                isFlagged: isFlagged,
                flagColor: payload["flagColor"] as? String
            )
            return ["ok": true]

        case "searchEmailMessages":
            let tokens = try decodePayload([SearchToken].self, key: "tokens", from: payload, default: [])
            let freeText = payload["freeText"] as? String ?? ""
            let accountID = payload["accountID"] as? String
            let mailbox = payload["mailbox"] as? String
            let filter = try decodeOptionalPayload(QuickFilter.self, key: "filter", from: payload)
            let sortKey = try decodeOptionalPayload(EmailSortKey.self, key: "sortKey", from: payload) ?? .date
            let limit = payload["limit"] as? Int ?? 500
            let messages = try runtime.emailStore.searchEmailMessages(
                tokens: tokens,
                freeText: freeText,
                accountID: accountID,
                mailbox: mailbox,
                filter: filter,
                sortKey: sortKey,
                limit: limit
            )
            return ["messages": try XPCJSON.object(from: messages)]

        case "createSmartMailbox":
            guard let displayName = payload["displayName"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try runtime.emailStore.createSmartMailbox(
                displayName: displayName,
                iconName: payload["iconName"] as? String ?? "tray",
                rulesJSON: payload["rulesJSON"] as? String ?? "[]"
            )
            return ["ok": true]

        case "listSmartMailboxes":
            return ["mailboxes": try XPCJSON.object(from: runtime.emailStore.allSmartMailboxes())]

        case "updateSmartMailbox":
            guard let mailboxID = payload["mailboxID"] as? String,
                  let displayName = payload["displayName"] as? String,
                  let iconName = payload["iconName"] as? String,
                  let rulesJSON = payload["rulesJSON"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try runtime.emailStore.updateSmartMailbox(
                mailboxID: mailboxID,
                displayName: displayName,
                iconName: iconName,
                rulesJSON: rulesJSON
            )
            return ["ok": true]

        case "deleteSmartMailbox":
            guard let mailboxID = payload["mailboxID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try runtime.emailStore.deleteSmartMailbox(mailboxID: mailboxID)
            return ["ok": true]

        case "emailBackupInfo":
            return ["info": try XPCJSON.object(from: EmailBackupInfoPayload(path: EmailSyncEngine.backupRoot.path, diskUsage: backupDiskUsage()))]

        case "listPendingApprovals":
            let pending = try await runtime.approvalQueue.pending()
            let rows: [ApprovalRow] = pending.map(ApprovalRow.make(from:))
            return ["requests": try XPCJSON.object(from: rows)]

        case "getPrivacySettings":
            return ["bundle": try XPCJSON.object(from: try await runtime.privacyCoordinator.settingsBundle())]

        case "updatePrivacySettings":
            if let settingsObject = payload["settings"] {
                let settings = try XPCJSON.decode(PrivacyPreflightSettings.self, from: settingsObject)
                try await runtime.privacyCoordinator.updateSettings(settings)
            }
            if let policyObject = payload["policy"] {
                let policy = try XPCJSON.decode(AgentPrivacyPolicy.self, from: policyObject)
                try await runtime.privacyCoordinator.updatePolicy(policy)
            }
            return ["ok": true]

        case "installPrivacyModel":
            return ["status": try XPCJSON.object(from: try await runtime.privacyCoordinator.installModel())]

        case "uninstallPrivacyModel":
            return ["status": try XPCJSON.object(from: try await runtime.privacyCoordinator.uninstallModel())]

        case "privacyRuntimeStatus":
            return ["status": try XPCJSON.object(from: try await runtime.privacyCoordinator.runtimeStatus())]

        case "clearPrivacyCache":
            return ["count": try await runtime.privacyCoordinator.clearCache()]

        case "privacyIndexStatus":
            return ["status": try XPCJSON.object(from: try await runtime.privacyIndexCoordinator.runtimeStatus())]

        case "listPrivacyIndex":
            let scope = try decodePayload(PrivacyIndexScope.self, key: "scope", from: payload, default: PrivacyIndexScope())
            let filter = try decodePayload(PrivacyIndexFilter.self, key: "filter", from: payload, default: PrivacyIndexFilter())
            let limit = payload["limit"] as? Int ?? 200
            return [
                "records": try XPCJSON.object(
                    from: try await runtime.privacyIndexCoordinator.listIndex(scope: scope, filter: filter, limit: limit)
                )
            ]

        case "listPrivacyIdentitySuggestions":
            return [
                "suggestions": try XPCJSON.object(
                    from: try await runtime.privacyIndexCoordinator.listIdentitySuggestions()
                )
            ]

        case "acceptPrivacyIdentitySuggestion":
            guard let id = payload["id"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.privacyIndexCoordinator.acceptIdentitySuggestion(id: id)
            return ["ok": true]

        case "rejectPrivacyIdentitySuggestion":
            guard let id = payload["id"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.privacyIndexCoordinator.rejectIdentitySuggestion(id: id)
            return ["ok": true]

        case "upsertPrivacyIdentity":
            guard let recordObject = payload["record"] else {
                throw ManifoldXPCError.invalidPayload
            }
            let record = try XPCJSON.decode(PrivacyIdentityRecord.self, from: recordObject)
            try await runtime.privacyIndexCoordinator.upsertIdentity(record)
            return ["ok": true]

        case "upsertPrivacyOrgAllowEntry":
            guard let entryObject = payload["entry"] else {
                throw ManifoldXPCError.invalidPayload
            }
            let entry = try XPCJSON.decode(PrivacyOrgAllowEntry.self, from: entryObject)
            try await runtime.privacyIndexCoordinator.upsertOrgAllowEntry(entry)
            return ["ok": true]

        case "listPrivacyIdentities":
            return [
                "identities": try XPCJSON.object(
                    from: try await runtime.privacyIndexCoordinator.listIdentities()
                )
            ]

        case "listPrivacyOrgAllowEntries":
            return [
                "entries": try XPCJSON.object(
                    from: try await runtime.privacyIndexCoordinator.listOrgAllowEntries()
                )
            ]

        case "deletePrivacyIdentity":
            guard let id = payload["id"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.privacyIndexCoordinator.deleteIdentity(id: id)
            return ["ok": true]

        case "deletePrivacyOrgAllowEntry":
            guard let id = payload["id"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.privacyIndexCoordinator.deleteOrgAllowEntry(id: id)
            return ["ok": true]

        case "rescanPrivacyContent":
            let contentIDs = payload["contentIDs"] as? [String] ?? []
            try await runtime.privacyIndexCoordinator.rescan(contentIDs: contentIDs)
            return ["ok": true]

        case "answerApproval":
            guard let id = payload["id"] as? String,
                  let answer = payload["answer"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            guard let request = try await runtime.approvalQueue.request(id: id),
                  let agent = TargetApp(rawValue: request.agent) else {
                throw ManifoldXPCError.invalidPayload
            }
            switch answer {
            case "approve":
                try await runtime.approvalQueue.approve(id: id, resolutionAction: answer)
            case "once":
                guard request.kind == .standingWrite,
                      let sourceID = request.sourceID,
                      let relativePath = request.relativePath else {
                    throw ManifoldXPCError.invalidPayload
                }
                try await runtime.standingWriteApprovalStore.grantOnce(
                    agent: agent,
                    sourceID: sourceID,
                    relativePath: relativePath
                )
                try await runtime.approvalQueue.approve(id: id, resolutionAction: answer)
            case "default":
                guard request.kind == .standingWrite,
                      let sourceID = request.sourceID else {
                    throw ManifoldXPCError.invalidPayload
                }
                try await runtime.standingWriteApprovalStore.grantDefault(agent: agent, sourceID: sourceID)
                try await runtime.approvalQueue.approve(id: id, resolutionAction: answer)
            case "shareRedacted":
                guard request.kind == .privacyExposure,
                      let contextJSON = request.contextJSON,
                      let data = contextJSON.data(using: .utf8) else {
                    throw ManifoldXPCError.invalidPayload
                }
                let context = try JSONDecoder().decode(PrivacyApprovalContext.self, from: data)
                try await runtime.privacyStore.saveApprovalOverride(
                    agent: agent,
                    resourceKey: request.path,
                    inputHash: context.inputHash,
                    contentKind: context.contentKind,
                    decision: .shareRedacted
                )
                try await runtime.approvalQueue.approve(id: id, resolutionAction: answer)
            case "shareOriginalOnce":
                guard request.kind == .privacyExposure,
                      let contextJSON = request.contextJSON,
                      let data = contextJSON.data(using: .utf8) else {
                    throw ManifoldXPCError.invalidPayload
                }
                let context = try JSONDecoder().decode(PrivacyApprovalContext.self, from: data)
                try await runtime.privacyStore.saveApprovalOverride(
                    agent: agent,
                    resourceKey: request.path,
                    inputHash: context.inputHash,
                    contentKind: context.contentKind,
                    decision: .shareOriginalOnce
                )
                try await runtime.approvalQueue.approve(id: id, resolutionAction: answer)
            case "session":
                throw ManifoldXPCError.invalidPayload
            case "deny", "notThisTime":
                try await runtime.approvalQueue.deny(id: id)
            default:
                throw ManifoldXPCError.invalidPayload
            }
            return ["ok": true]

        // MARK: - Unified Rule catalog (file / email / agent)

        case "listRules":
            let scopeFilter = (payload["scope"] as? String).flatMap(RuleScope.init(rawValue:))
            let rules: [RuleRecord]
            if let scopeFilter {
                rules = try await runtime.ruleStore.rules(scope: scopeFilter)
            } else {
                rules = try await runtime.ruleStore.allRules()
            }
            return ["rules": try XPCJSON.object(from: rules)]

        case "upsertRule":
            guard let ruleObject = payload["rule"] else {
                throw ManifoldXPCError.invalidPayload
            }
            let rule = try XPCJSON.decode(RuleRecord.self, from: ruleObject)
            try await runtime.ruleStore.upsert(rule)
            return ["ok": true]

        case "deleteRule":
            guard let id = payload["id"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.ruleStore.delete(id: id)
            return ["ok": true]

        case "setRuleEnabled":
            guard let id = payload["id"] as? String,
                  let enabled = payload["enabled"] as? Bool else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.ruleStore.setEnabled(id: id, enabled: enabled)
            return ["ok": true]

        case "reorderRules":
            guard let scopeRaw = payload["scope"] as? String,
                  let scope = RuleScope(rawValue: scopeRaw),
                  let ids = payload["ids"] as? [String] else {
                throw ManifoldXPCError.invalidPayload
            }
            try await runtime.ruleStore.reorder(scope: scope, ids: ids)
            return ["ok": true]

        case "resetSeededRules":
            // Re-apply the seeded catalog (idempotent). Used by Settings > Rules > "Reset seeded rules".
            try await runtime.ruleStore.seedIfNeeded(RuleSeedCatalog.seeds())
            return ["ok": true]

        case "previewRuleMatches":
            // Live match preview for the inspector. Agent-scoped so "would block for Claude" vs "for Codex" are distinct.
            guard let ruleObject = payload["rule"] else {
                throw ManifoldXPCError.invalidPayload
            }
            let rule = try XPCJSON.decode(RuleRecord.self, from: ruleObject)
            let agent = (payload["agent"] as? String).flatMap(TargetApp.init(rawValue:)) ?? .cowork
            let summary = try await computeRuleMatchPreview(rule: rule, agent: agent)
            return ["preview": try XPCJSON.object(from: summary)]

        default:
            return nil
        }
    }

    /// Plain-JSON row used to ferry ApprovalQueue.PendingRequest across the
    /// XPC boundary (the underlying type is actor-isolated, hence the copy).
    private struct ApprovalRow: Codable, Sendable {
        let id: String
        let connectionID: String
        let agent: String
        let path: String
        let action: String
        let kind: String
        let sourceID: String?
        let mountName: String?
        let relativePath: String?
        let contextJSON: String?
        let requestedAt: Double
        let status: String
        let resolutionAction: String?

        static func make(from request: ApprovalQueue.PendingRequest) -> ApprovalRow {
            ApprovalRow(
                id: request.id,
                connectionID: request.connectionID,
                agent: request.agent,
                path: request.path,
                action: request.action,
                kind: request.kind.rawValue,
                sourceID: request.sourceID,
                mountName: request.mountName,
                relativePath: request.relativePath,
                contextJSON: request.contextJSON,
                requestedAt: request.requestedAt,
                status: request.status.rawValue,
                resolutionAction: request.resolutionAction
            )
        }
    }

    private func activeGrantStateCommand(payload: [String: Any]) async throws -> [String: Any] {
        let preferredAgent = (payload["targetApp"] as? String).flatMap(TargetApp.init(rawValue:)) ?? .cowork
        let state = try await activeGrantState(preferredAgent: preferredAgent)
        return [
            "activeGrant": try state.grant.map { try XPCJSON.object(from: $0) } ?? NSNull(),
            "activeGrantSources": try XPCJSON.object(from: state.sources),
            "targetApp": state.targetApp?.rawValue as Any,
        ]
    }

    private func targetApp(from payload: [String: Any]) -> TargetApp? {
        if let raw = payload["agent"] as? String {
            return TargetApp(rawValue: raw)
        }
        if let raw = payload["targetApp"] as? String {
            return TargetApp(rawValue: raw)
        }
        return nil
    }

    private func sessionPreviewCommand(payload: [String: Any]) async throws -> [String: Any] {
        let targetApp = (payload["targetApp"] as? String).flatMap(TargetApp.init(rawValue:)) ?? .cowork
        let fileScopes = try decodePayload([FileSelectionScope].self, key: "fileScopes", from: payload, default: [])
        let selectedEmailIDs = Set(payload["selectedEmailIDs"] as? [String] ?? [])
        let sensitivity = (payload["emailSensitivity"] as? String).flatMap(EmailSensitivityFilter.Level.init(rawValue:))
        return ["preview": try await computeSessionPreview(
            targetApp: targetApp,
            fileScopes: fileScopes,
            selectedEmailIDs: selectedEmailIDs,
            sensitivityOverride: sensitivity
        )]
    }

    private func startTrackedRunCommand(payload: [String: Any]) async throws -> [String: Any] {
        let targetApp = (payload["targetApp"] as? String).flatMap(TargetApp.init(rawValue:)) ?? .cowork
        let fileScopes = try decodePayload([FileSelectionScope].self, key: "fileScopes", from: payload, default: [])
        let selectedEmailIDs = Set(payload["selectedEmailIDs"] as? [String] ?? [])
        let summaryFraming = payload["summaryFraming"] as? String
        let noteCaptureMode = (payload["noteCaptureMode"] as? String).flatMap(SessionNoteCaptureMode.init(rawValue:)) ?? .off
        let sensitivity = (payload["emailSensitivity"] as? String).flatMap(EmailSensitivityFilter.Level.init(rawValue:))
        let state = try await startTrackedRun(
            targetApp: targetApp,
            fileScopes: fileScopes,
            selectedEmailIDs: selectedEmailIDs,
            summaryFraming: summaryFraming,
            noteCaptureMode: noteCaptureMode,
            sensitivityOverride: sensitivity
        )
        return [
            "activeGrant": try XPCJSON.object(from: state.grant),
            "activeGrantSources": try XPCJSON.object(from: state.sources),
        ]
    }

    /// Start a tracked run from a saved access template.
    ///
    /// Lenient on stale references (per eng-review Issue 2): sources that
    /// have been deleted, removed, or paused are silently dropped from the
    /// scope, and their displayName + sourceID are returned in
    /// `skippedSources` so the UI can surface a banner. The session still
    /// starts with the surviving scope (or with no scope, falling back to
    /// the agent's default policy if the template was empty).
    ///
    /// Disconnected target agent currently does NOT pre-fail here — the
    /// runtime accepts grants for any agent and the UI gates connection at
    /// session-start time. (TODO when AppRuntimeClient surfaces connection
    /// status to the bridge layer.)
    private func startSessionFromTemplateCommand(payload: [String: Any]) async throws -> [String: Any] {
        guard let presetID = payload["presetID"] as? String else {
            throw ManifoldXPCError.invalidPayload
        }
        guard let snapshot = try await runtime.accessStore.loadPreset(id: presetID) else {
            throw ManifoldXPCError.invalidPayload
        }

        // Target agent: explicit override > template's targetApp > cowork.
        let explicitTargetApp = (payload["targetApp"] as? String).flatMap(TargetApp.init(rawValue:))
        let targetApp: TargetApp = explicitTargetApp ?? snapshot.preset.targetApp ?? .cowork

        // Filter stale source references. activeSources() already drops
        // status='removed' rows; we additionally drop paused sources for
        // template-driven runs (paused = "temporarily off" — the template
        // shouldn't silently re-enable them).
        let activeSources = try await runtime.grantStore.activeSources()
        let activeIDs = Set(activeSources.map(\.sourceID))
        let allSources = try await runtime.grantStore.allSources()
        let knownDisplayNamesByID = Dictionary(uniqueKeysWithValues: allSources.map { ($0.sourceID, $0.displayName) })

        var skippedSources: [[String: String]] = []
        var seenSkipped = Set<String>()
        let templateScopes = snapshot.fileScopes
        let survivingScopes: [FileSelectionScope] = templateScopes.compactMap { scope in
            if activeIDs.contains(scope.sourceID) {
                return scope
            }
            if seenSkipped.insert(scope.sourceID).inserted {
                skippedSources.append([
                    "sourceID": scope.sourceID,
                    "displayName": knownDisplayNamesByID[scope.sourceID] ?? scope.sourceID,
                ])
            }
            return nil
        }

        // Email IDs: keep only ones the email store still knows about.
        let templateEmailIDs = snapshot.emailIDs
        var missingEmailIDs: [String] = []
        let survivingEmailIDs: Set<String>
        if templateEmailIDs.isEmpty {
            survivingEmailIDs = []
        } else {
            let known = Set(try runtime.emailStore.emailMessages(ids: templateEmailIDs).map(\.emailID))
            survivingEmailIDs = Set(templateEmailIDs.filter { known.contains($0) })
            missingEmailIDs = templateEmailIDs.filter { !known.contains($0) }
        }

        let summaryFraming = payload["summaryFraming"] as? String
        let noteCaptureMode = (payload["noteCaptureMode"] as? String).flatMap(SessionNoteCaptureMode.init(rawValue:)) ?? .off
        let sensitivity = (payload["emailSensitivity"] as? String).flatMap(EmailSensitivityFilter.Level.init(rawValue:))

        let state = try await startTrackedRun(
            targetApp: targetApp,
            fileScopes: survivingScopes,
            selectedEmailIDs: survivingEmailIDs,
            summaryFraming: summaryFraming,
            noteCaptureMode: noteCaptureMode,
            sensitivityOverride: sensitivity
        )

        return [
            "activeGrant": try XPCJSON.object(from: state.grant),
            "activeGrantSources": try XPCJSON.object(from: state.sources),
            "templateID": presetID,
            "templateName": snapshot.preset.name,
            "skippedSources": skippedSources,
            "missingEmailIDs": missingEmailIDs,
        ]
    }

    private func activeGrantState(preferredAgent: TargetApp) async throws -> (grant: GrantRecord?, sources: [GrantSourceRecord], targetApp: TargetApp?) {
        let candidateApps = [preferredAgent] + TargetApp.allCases.filter { $0 != preferredAgent }
        for candidate in candidateApps {
            if let grant = try await runtime.grantStore.activeGrant(targetApp: candidate, profileID: "default") {
                return (grant, try await runtime.grantStore.grantSources(grantID: grant.grantID), TargetApp(rawValue: grant.targetApp))
            }
        }
        return (nil, [], nil)
    }

    private func computeSessionPreview(
        targetApp: TargetApp,
        fileScopes: [FileSelectionScope],
        selectedEmailIDs: Set<String>,
        sensitivityOverride: EmailSensitivityFilter.Level?
    ) async throws -> [String: Any] {
        let activeSources = try await runtime.grantStore.activeSources()
        let policy = try await runtime.policyStore.policy(for: targetApp)
        let defaultSources = policy.isPaused
            ? []
            : activeSources.filter { policy.allowedSourceIDs.contains($0.sourceID) }
        let explicitScopes = normalizedScopes(fileScopes)
        let usingExplicitSelection = !explicitScopes.isEmpty || !selectedEmailIDs.isEmpty
        let activeSourceMap = Dictionary(uniqueKeysWithValues: activeSources.map { ($0.sourceID, $0) })
        let groupedScopes = Dictionary(grouping: explicitScopes, by: \.sourceID)
        let inputs: [MaterializationEngine.MaterializationSource]
        if usingExplicitSelection {
            inputs = groupedScopes.keys.sorted().compactMap { sourceID in
                guard let source = activeSourceMap[sourceID] else { return nil }
                return MaterializationEngine.MaterializationSource(
                    source: source,
                    mountName: URL(fileURLWithPath: source.originalRootPath).lastPathComponent.lowercased(),
                    selectedScopes: groupedScopes[sourceID] ?? []
                )
            }
        } else {
            inputs = defaultSources.map { source in
                MaterializationEngine.MaterializationSource(
                    source: source,
                    mountName: URL(fileURLWithPath: source.originalRootPath).lastPathComponent.lowercased()
                )
            }
        }

        let perSource = try MaterializationEngine.estimateSizePerSource(sources: inputs)
        let previewSensitivity = sensitivityOverride ?? (usingExplicitSelection ? .strict : .moderate)
        let totalEmailCount: Int
        let visibleEmailCount: Int
        if usingExplicitSelection {
            totalEmailCount = selectedEmailIDs.count
            visibleEmailCount = selectedEmailIDs.count
        } else {
            let allEmails = try runtime.emailStore.allEmailMessages(limit: 5_000)
            totalEmailCount = allEmails.count
            switch previewSensitivity {
            case .strict:
                visibleEmailCount = try runtime.emailStore.sharedEmails(agent: targetApp, limit: 5_000).count
            case .moderate, .open:
                let filter = EmailSensitivityFilter(level: previewSensitivity)
                visibleEmailCount = allEmails.filter { filter.isVisible(email: $0) }.count
            }
        }

        return [
            "sources": perSource.map { source in
                [
                    "sourceID": source.sourceID,
                    "displayName": source.displayName,
                    "fileCount": source.fileCount,
                    "totalBytes": source.totalBytes,
                    "scopeCount": max(1, groupedScopes[source.sourceID]?.count ?? 1),
                ]
            },
            "emailCount": totalEmailCount,
            "visibleEmailCount": visibleEmailCount,
            "sensitivityLevel": previewSensitivity.rawValue,
            "selectedEmailCount": usingExplicitSelection ? selectedEmailIDs.count : visibleEmailCount,
            "targetApp": targetApp.rawValue,
        ]
    }

    private func startTrackedRun(
        targetApp: TargetApp,
        fileScopes: [FileSelectionScope],
        selectedEmailIDs: Set<String>,
        summaryFraming: String?,
        noteCaptureMode: SessionNoteCaptureMode,
        sensitivityOverride: EmailSensitivityFilter.Level?
    ) async throws -> (grant: GrantRecord, sources: [GrantSourceRecord]) {
        let activeSources = try await runtime.grantStore.activeSources()
        let policy = try await runtime.policyStore.policy(for: targetApp)
        let defaultSources = policy.isPaused
            ? []
            : activeSources.filter { policy.allowedSourceIDs.contains($0.sourceID) }
        let explicitScopes = normalizedScopes(fileScopes)
        let usingExplicitSelection = !explicitScopes.isEmpty || !selectedEmailIDs.isEmpty
        let activeSourceMap = Dictionary(uniqueKeysWithValues: activeSources.map { ($0.sourceID, $0) })
        let explicitSourceIDs = Array(Set(explicitScopes.map(\.sourceID))).sorted()
        let sourceIDs = usingExplicitSelection ? explicitSourceIDs : defaultSources.map(\.sourceID)
        let emailSensitivity = (sensitivityOverride ?? (usingExplicitSelection ? .strict : .moderate)).rawValue
        let grant = try await runtime.grantStore.startGrant(
            targetApp: targetApp,
            profileID: "default",
            sourceIDs: sourceIDs,
            materializationRoot: Self.materializationRoot(grantID: "").path,
            emailSensitivity: emailSensitivity,
            summaryFraming: summaryFraming,
            explicitSelection: usingExplicitSelection,
            noteCaptureMode: noteCaptureMode
        )

        let actualRoot = Self.materializationRoot(grantID: grant.grantID)
        try await runtime.grantStore.updateMaterializationRoot(grantID: grant.grantID, root: actualRoot.path)
        let grantSources = try await runtime.grantStore.grantSources(grantID: grant.grantID)
        let scopesBySource = Dictionary(grouping: explicitScopes, by: \.sourceID)
        let mountInputs = grantSources.compactMap { grantSource -> MaterializationEngine.MaterializationSource? in
            guard let source = activeSourceMap[grantSource.sourceID] else { return nil }
            return MaterializationEngine.MaterializationSource(
                source: source,
                mountName: grantSource.mountName,
                selectedScopes: scopesBySource[grantSource.sourceID] ?? []
            )
        }

        let results = try MaterializationEngine.materialize(
            grantID: grant.grantID,
            sources: mountInputs,
            materializationRoot: actualRoot.path
        )

        if usingExplicitSelection {
            try await runtime.grantStore.replaceGrantFileScopes(grantID: grant.grantID, scopes: explicitScopes)
            try runtime.emailStore.replaceGrantEmails(grantID: grant.grantID, emailIDs: Array(selectedEmailIDs))
        }

        for result in results {
            try await runtime.grantStore.setBaselineHash(
                grantID: grant.grantID,
                sourceID: result.sourceID,
                hash: result.manifestHash
            )
            try await baselineSnapshotMount(
                grantID: grant.grantID,
                sourceID: result.sourceID,
                mountName: result.mountName,
                mountPath: result.mountPath
            )
        }

        try await runtime.artifactIndex.ensureGrantIndexed(
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
        let attachments = try runtime.emailStore.emailAttachments(emailIDs: emails.map(\.emailID))
        try await runtime.artifactIndex.syncEmails(
            grantID: grant.grantID,
            emails: emails,
            attachments: attachments
        )

        try await runtime.auditStore.log(
            action: .runStart,
            runID: grant.grantID,
            agent: targetApp.rawValue,
            metadata: [
                "grant_id": grant.grantID,
                "note_capture_mode": noteCaptureMode.rawValue,
            ],
            grantID: grant.grantID
        )

        return (grant, grantSources)
    }

    private func previewTrackedRun(grantID: String) async throws -> [String: Any] {
        let grantSources = try await runtime.grantStore.grantSources(grantID: grantID)
        guard let grant = try await runtime.grantStore.grant(id: grantID) else {
            throw ManifoldXPCError.invalidPayload
        }

        var applied: [String] = []
        var conflicts: [String] = []
        var newFiles: [String] = []
        var skipped = 0

        for grantSource in grantSources {
            guard let source = try await runtime.grantStore.source(id: grantSource.sourceID) else { continue }
            let mountURL = URL(fileURLWithPath: grant.materializationRoot).appendingPathComponent(grantSource.mountName)
            let originalURL = URL(fileURLWithPath: source.originalRootPath)
            guard FileManager.default.fileExists(atPath: mountURL.path) else { continue }

            let (_, _, drySkipped, _) = try PromoteEngine.dryRun(mountURL: mountURL, originalURL: originalURL)
            let manifest = try MaterializationEngine.computeManifest(mountURL: mountURL)
            for (relativePath, currentHash) in manifest {
                let originalFile = originalURL.appendingPathComponent(relativePath)
                let prefixed = "\(grantSource.mountName)/\(relativePath)"
                if !FileManager.default.fileExists(atPath: originalFile.path) {
                    newFiles.append(prefixed)
                } else {
                    let originalData = try Data(contentsOf: originalFile)
                    let originalHash = Self.hashHex(for: originalData)
                    let baselineURL = mountURL.appendingPathComponent(".manifold-baseline.json")
                    let baselineHash: String?
                    if let baselineData = try? Data(contentsOf: baselineURL),
                       let baselineJSON = try? JSONSerialization.jsonObject(with: baselineData) as? [String: String] {
                        baselineHash = baselineJSON[relativePath]
                    } else {
                        baselineHash = nil
                    }

                    if currentHash != baselineHash {
                        if originalHash != baselineHash {
                            conflicts.append(prefixed)
                        } else {
                            applied.append(prefixed)
                        }
                    }
                }
            }
            skipped += drySkipped
        }

        return [
            "applied": applied.sorted(),
            "conflicts": conflicts.sorted(),
            "newFiles": newFiles.sorted(),
            "skipped": skipped,
        ]
    }

    private func applyTrackedRun(grantID: String, endSession: Bool) async throws -> [String: Any] {
        guard let grant = try await runtime.grantStore.grant(id: grantID) else {
            throw ManifoldXPCError.invalidPayload
        }
        let grantSources = try await runtime.grantStore.grantSources(grantID: grantID)
        let activeSources = try await runtime.grantStore.allSources()
        let materializationRoot = URL(fileURLWithPath: grant.materializationRoot)
        let allowedScopes = grant.explicitSelection
            ? (try await runtime.grantStore.grantFileScopes(grantID: grantID)).map {
                FileSelectionScope(
                    sourceID: $0.sourceID,
                    relativePath: $0.relativePath,
                    isDirectory: $0.isDirectory
                )
            }
            : []

        var appliedPaths: [String] = []
        var conflictedPaths: [String] = []

        for grantSource in grantSources {
            guard let source = activeSources.first(where: { $0.sourceID == grantSource.sourceID }) else { continue }
            let mountURL = materializationRoot.appendingPathComponent(grantSource.mountName)
            let originalURL = URL(fileURLWithPath: source.originalRootPath)
            guard FileManager.default.fileExists(atPath: mountURL.path) else { continue }

            let summary = try PromoteEngine.promote(
                sourceID: grantSource.sourceID,
                mountName: grantSource.mountName,
                mountURL: mountURL,
                originalURL: originalURL,
                allowedScopes: allowedScopes
            )

            for file in summary.applied + summary.newFiles {
                let canonical = "\(grantSource.mountName)/\(file.relativePath)"
                appliedPaths.append(canonical)
                try await runtime.grantStore.recordPromotion(
                    grantID: grantID,
                    sourceID: grantSource.sourceID,
                    relativePath: canonical,
                    result: file.result,
                    originalBeforeHash: file.originalBeforeHash,
                    promotedHash: file.promotedHash
                )
                try? await runtime.auditStore.log(
                    action: .promote,
                    runID: grantID,
                    workspaceID: grantSource.sourceID,
                    agent: grant.targetApp,
                    filePath: canonical,
                    beforeHash: file.originalBeforeHash,
                    afterHash: file.promotedHash,
                    metadata: [
                        "grant_id": grantID,
                        "mount": grantSource.mountName,
                        "result": file.result.rawValue,
                    ],
                    grantID: grantID
                )
            }

            for file in summary.conflicts {
                let canonical = "\(grantSource.mountName)/\(file.relativePath)"
                conflictedPaths.append(canonical)
                try await runtime.grantStore.recordPromotion(
                    grantID: grantID,
                    sourceID: grantSource.sourceID,
                    relativePath: canonical,
                    result: .conflict,
                    originalBeforeHash: file.originalBeforeHash,
                    promotedHash: file.promotedHash,
                    conflictReason: file.conflictReason
                )
                try? await runtime.auditStore.log(
                    action: .promote,
                    runID: grantID,
                    workspaceID: grantSource.sourceID,
                    agent: grant.targetApp,
                    filePath: canonical,
                    beforeHash: file.originalBeforeHash,
                    afterHash: file.promotedHash,
                    metadata: [
                        "grant_id": grantID,
                        "mount": grantSource.mountName,
                        "result": ManifoldKit.PromotionResult.conflict.rawValue,
                        "conflict_reason": file.conflictReason ?? "conflict",
                    ],
                    grantID: grantID
                )
            }
        }

        if let workBlock = try await runtime.workBlockStore.anyActiveBlock(), workBlock.grantID == grantID {
            try await runtime.workBlockStore.endBlock(id: workBlock.id, status: .promoted)
        }

        if endSession {
            try await runtime.grantStore.endGrant(grantID: grantID)
            try? await runtime.auditStore.log(
                action: .runEnd,
                runID: grantID,
                metadata: ["grant_id": grantID],
                grantID: grantID
            )
            Self.cleanupMaterialization(for: grant)
        }

        return [
            "grantID": grantID,
            "filesApplied": appliedPaths.sorted(),
            "filesConflicted": conflictedPaths.sorted(),
            "appliedCount": appliedPaths.count,
            "conflictCount": conflictedPaths.count,
        ]
    }

    private func restoreSnapshot(snapshotID: Int, filePath: String) async -> RestoreSnapshotResult {
        do {
            let state = try await activeGrantState(preferredAgent: .cowork)
            guard let grant = state.grant,
                  let data = try await runtime.snapshotStore.dataForRestore(snapshotID: snapshotID),
                  let resolved = Self.resolveGrantFilePath(
                    canonicalPath: filePath,
                    grant: grant,
                    grantSources: state.sources
                  ) else {
                return RestoreSnapshotResult(
                    status: "missingSnapshot",
                    message: "Manifold couldn't find a live tracked file for this snapshot."
                )
            }

            if let expectedHash = try await runtime.snapshotStore.latestHash(runID: grant.grantID, filePath: filePath),
               let currentData = try? ScopedFileAccess.readData(
                    relativePath: resolved.relativePath,
                    rootPath: resolved.mount.mountPath
               ).data,
               Self.hashHex(for: currentData) != expectedHash {
                return RestoreSnapshotResult(
                    status: "conflict",
                    message: "This file changed after the snapshot was recorded. Review the current version before restoring it."
                )
            }

            let written = try ScopedFileAccess.writeDataAtomically(
                data,
                relativePath: resolved.relativePath,
                rootPath: resolved.mount.mountPath
            )
            try await runtime.snapshotStore.recordRestore(
                runID: grant.grantID,
                workspaceID: resolved.mount.sourceID,
                filePath: filePath,
                restoredData: data
            )
            try await runtime.artifactIndex.upsertFile(
                grantID: grant.grantID,
                mount: ArtifactMount(
                    sourceID: resolved.mount.sourceID,
                    mountName: resolved.mount.mountName,
                    mountPath: resolved.mount.mountPath
                ),
                relativePath: resolved.relativePath,
                fileURL: written.fileURL
            )
            return RestoreSnapshotResult(
                status: "success",
                message: "Restored \(filePath) to the selected snapshot."
            )
        } catch {
            return RestoreSnapshotResult(
                status: "error",
                message: error.localizedDescription
            )
        }
    }

    private func revertSessionEvent(event: SessionEvent, grantID: String, force: Bool) async throws -> [String: Any] {
        guard let grant = try await runtime.grantStore.grant(id: grantID),
              let filePath = event.filePath,
              let beforeHash = event.beforeHash,
              let blobData = try await runtime.contentStore.retrieve(hash: beforeHash) else {
            return ["status": "blobPruned"]
        }
        let grantSources = try await runtime.grantStore.grantSources(grantID: grantID)
        guard let resolved = Self.resolveGrantFilePath(
            canonicalPath: filePath,
            grant: grant,
            grantSources: grantSources
        ) else {
            return ["status": "error", "message": "No sources configured"]
        }

        if !force, FileManager.default.fileExists(atPath: resolved.fileURL.path),
           let afterHash = event.afterHash,
           let currentData = try? ScopedFileAccess.readData(
                relativePath: resolved.relativePath,
                rootPath: resolved.mount.mountPath
           ).data,
           Self.hashHex(for: currentData) != afterHash {
            return ["status": "contentDrift"]
        }

        let written = try ScopedFileAccess.writeDataAtomically(
            blobData,
            relativePath: resolved.relativePath,
            rootPath: resolved.mount.mountPath
        )
        try await runtime.snapshotStore.recordRestore(
            runID: grant.grantID,
            workspaceID: resolved.mount.sourceID,
            filePath: filePath,
            restoredData: blobData
        )
        try await runtime.artifactIndex.upsertFile(
            grantID: grant.grantID,
            mount: ArtifactMount(
                sourceID: resolved.mount.sourceID,
                mountName: resolved.mount.mountName,
                mountPath: resolved.mount.mountPath
            ),
            relativePath: resolved.relativePath,
            fileURL: written.fileURL
        )
        return ["status": "success"]
    }

    private func emailMessages(payload: [String: Any]) throws -> [EmailMessageRecord] {
        if let ids = payload["ids"] as? [String] {
            return try runtime.emailStore.emailMessages(ids: ids)
        }
        if let accountID = payload["accountID"] as? String, let mailbox = payload["mailbox"] as? String {
            return try runtime.emailStore.emailMessages(accountID: accountID, mailbox: mailbox, limit: payload["limit"] as? Int ?? 500)
        }
        if let accountID = payload["accountID"] as? String {
            return try runtime.emailStore.emailMessages(accountID: accountID, limit: payload["limit"] as? Int ?? 200)
        }
        return try runtime.emailStore.allEmailMessages(limit: payload["limit"] as? Int ?? 500)
    }

    private func accessibleEmails(for grant: GrantRecord, limit: Int = 1_000) throws -> [EmailMessageRecord] {
        if grant.explicitSelection {
            return try runtime.emailStore.grantEmails(grantID: grant.grantID, limit: limit)
        }
        let filter = EmailSensitivityFilter(rawValue: grant.emailSensitivity)
        if filter.level == .strict {
            let agent = TargetApp(rawValue: grant.targetApp) ?? .cowork
            return try runtime.emailStore.sharedEmails(agent: agent, limit: limit)
        }
        return try runtime.emailStore
            .allEmailMessages(limit: limit)
            .filter { filter.isVisible(email: $0) }
    }

    private func baselineSnapshotMount(
        grantID: String,
        sourceID: String,
        mountName: String,
        mountPath: String
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
            let canonical = Self.canonicalPath(for: url, base: root, mountName: mountName)
            guard !canonical.hasPrefix("\(mountName)/.manifold-") else { continue }
            let data = try Data(contentsOf: url)
            try await runtime.snapshotStore.recordBaseline(
                runID: grantID,
                workspaceID: sourceID,
                filePath: canonical,
                data: data
            )
        }
    }

    private func decodePayload<T: Decodable>(
        _ type: T.Type,
        key: String,
        from payload: [String: Any],
        default defaultValue: T
    ) throws -> T {
        guard let object = payload[key] else { return defaultValue }
        return try XPCJSON.decode(T.self, from: object)
    }

    private func decodeOptionalPayload<T: Decodable>(
        _ type: T.Type,
        key: String,
        from payload: [String: Any]
    ) throws -> T? {
        guard let object = payload[key], !(object is NSNull) else { return nil }
        return try XPCJSON.decode(T.self, from: object)
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

    private func backupDiskUsage() -> Int64 {
        let root = EmailSyncEngine.backupRoot
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return 0
        }

        var total: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }

    private static func materializationRoot(grantID: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Manifold/materializations/\(grantID)/workspace")
    }

    private static func cleanupMaterialization(for grant: GrantRecord) {
        let materializationRoot = URL(fileURLWithPath: grant.materializationRoot)
        let grantDirectory = materializationRoot.deletingLastPathComponent()
        let expectedParent = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Manifold/materializations")
        guard grantDirectory.path.hasPrefix(expectedParent.path),
              grantDirectory.lastPathComponent != "materializations" else {
            appCommandLogger.error("Materialization path escapes expected parent: \(grantDirectory.path)")
            return
        }
        try? FileManager.default.removeItem(at: grantDirectory)
    }

    private static func canonicalPath(for url: URL, base: URL, mountName: String) -> String {
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

    private static func resolveGrantFilePath(
        canonicalPath: String,
        grant: GrantRecord,
        grantSources: [GrantSourceRecord]
    ) -> (mount: GrantMount, relativePath: String, fileURL: URL)? {
        let mounts = grantSources.map { source in
            GrantMount(
                sourceID: source.sourceID,
                mountName: source.mountName,
                mountPath: URL(fileURLWithPath: grant.materializationRoot)
                    .appendingPathComponent(source.mountName)
                    .path
            )
        }

        let cleaned = canonicalPath
            .replacingOccurrences(of: "//", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = cleaned.split(separator: "/", maxSplits: 1)
        if components.count >= 2,
           let mount = mounts.first(where: { $0.mountName == String(components[0]) }) {
            let relativePath = ScopedFileAccess.cleanRelativePath(String(components[1]))
            guard let fileURL = try? ScopedFileAccess.resolve(
                relativePath: relativePath,
                rootPath: mount.mountPath,
                allowMissingLeaf: true
            ).fileURL else { return nil }
            return (mount, relativePath, fileURL)
        }

        if mounts.count == 1, let mount = mounts.first {
            let relativePath = ScopedFileAccess.cleanRelativePath(cleaned)
            guard let fileURL = try? ScopedFileAccess.resolve(
                relativePath: relativePath,
                rootPath: mount.mountPath,
                allowMissingLeaf: true
            ).fileURL else { return nil }
            return (mount, relativePath, fileURL)
        }

        return nil
    }

    private static func hashHex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Rule match preview

    /// Live "would block N files / N emails right now" summary for the Rules inspector.
    /// Best-effort — bounded so the UI stays responsive.
    private func computeRuleMatchPreview(rule: RuleRecord, agent: TargetApp) async throws -> RuleMatchPreview {
        let engine = RuleEngine()
        var fileMatches = 0
        var emailMatches = 0
        var agentMatches = 0
        var sampleMatches: [RuleMatchPreview.Sample] = []

        switch rule.scope {
        case .file:
            // Use snapshot-tracked files as a fast, bounded probe surface.
            let paths = (try? await runtime.snapshotStore.allTrackedFiles()) ?? []
            let bounded = paths.prefix(2_000)
            for path in bounded {
                let leaf = path.split(separator: "/").last.map(String.init) ?? path
                let probe = FileProbe(
                    path: path,
                    isHidden: { leaf.hasPrefix(".") }
                )
                let ctx = RuleEvalContext(fileProbe: probe)
                let decision = engine.evaluate(.fileRead(path: path), against: [rule], agent: agent, context: ctx)
                if decision.action != .allow {
                    fileMatches += 1
                    if sampleMatches.count < 5 {
                        sampleMatches.append(.init(identifier: path, label: path))
                    }
                }
            }
        case .email:
            let messages = (try? runtime.emailStore.allEmailMessages(limit: 2_000)) ?? []
            for message in messages {
                let resolvedSender = message.senderEmail ?? message.sender
                let resolvedDomain = message.senderDomain ?? Self.domain(from: resolvedSender)
                let probe = EmailProbe(
                    emailID: message.emailID,
                    senderEmail: resolvedSender,
                    senderDomain: resolvedDomain,
                    subject: message.subject,
                    bodyText: message.bodyText ?? "",
                    folder: message.mailbox,
                    accountID: message.accountID,
                    hasAttachment: message.attachmentCount > 0,
                    largestAttachmentBytes: Int64(message.sizeBytes),
                    receivedAt: Self.parseISO(message.receivedAt) ?? Date()
                )
                let ctx = RuleEvalContext(emailProbe: probe)
                let decision = engine.evaluate(.emailRead(emailID: message.emailID), against: [rule], agent: agent, context: ctx)
                if decision.action != .allow {
                    emailMatches += 1
                    if sampleMatches.count < 5 {
                        sampleMatches.append(.init(identifier: message.emailID, label: "\(message.sender) — \(message.subject)"))
                    }
                }
            }
        case .agent:
            // Agent rules are stateless — we just report whether the rule would apply to this agent.
            let probe = AgentProbe(agent: agent, tool: .read, payloadBytes: nil, sessionStartedAt: Date())
            let ctx = RuleEvalContext(agentProbe: probe)
            let decision = engine.evaluate(.agentTool(tool: .read, payloadBytes: nil), against: [rule], agent: agent, context: ctx)
            if decision.action != .allow {
                agentMatches += 1
                sampleMatches.append(.init(identifier: agent.rawValue, label: "Applies to \(agent.rawValue)"))
            }
        }

        return RuleMatchPreview(
            ruleID: rule.id,
            fileMatches: fileMatches,
            emailMatches: emailMatches,
            agentMatches: agentMatches,
            sample: sampleMatches
        )
    }

    private static func domain(from sender: String) -> String {
        guard let at = sender.firstIndex(of: "@") else { return "" }
        return String(sender[sender.index(after: at)...]).lowercased()
    }

    private static func parseISO(_ string: String) -> Date? {
        ISO8601DateFormatter.shared.date(from: string)
    }
}
