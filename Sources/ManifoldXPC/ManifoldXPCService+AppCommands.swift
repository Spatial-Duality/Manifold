import CryptoKit
import Foundation
import ManifoldKit
import os

private let appCommandLogger = Logger(subsystem: "com.spatialduality.manifold", category: "xpc-app")

private struct MailboxCount: Codable, Sendable {
    let name: String
    let count: Int
}

private struct StorageStatsPayload: Codable, Sendable {
    let storageUsed: Int64
    let blobCount: Int
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
            try await runtime.policyStore.removeSource(sourceID, from: TargetApp(rawValue: agentRaw) ?? .cowork)
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
                        storageUsed: await runtime.contentStore.totalSize(),
                        blobCount: await runtime.contentStore.blobCount()
                    )
                )
            ]

        case "fileHistory":
            guard let filePath = payload["filePath"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["snapshots": try XPCJSON.object(from: await runtime.snapshotStore.fileHistory(filePath: filePath))]

        case "snapshotData":
            guard let hash = payload["hash"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["data": try XPCJSON.object(from: await runtime.contentStore.retrieve(hash: hash))]

        case "runGarbageCollection":
            return ["count": try await runtime.contentStore.garbageCollect()]

        case "pruneOldRuns":
            let keepLast = payload["keepLast"] as? Int ?? 10
            return ["count": try await runtime.snapshotStore.pruneOldRuns(keepLast: keepLast)]

        case "runIntegrityCheck":
            return ["ok": try runtime.db.integrityCheck()]

        case "recentSessions":
            let limit = payload["limit"] as? Int ?? 20
            return ["sessions": try XPCJSON.object(from: await runtime.auditStore.recentSessions(limit: limit))]

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
            return ["restored": try await restoreSnapshot(snapshotID: snapshotID, filePath: filePath)]

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
            return ["account": try XPCJSON.object(from: account)]

        case "removeEmailAccount":
            guard let accountID = payload["accountID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            await runtime.emailSyncEngine.unregister(accountID: accountID)
            KeychainHelper.delete(accountID: accountID)
            try runtime.emailStore.removeEmailAccount(id: accountID)
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
            return ["ok": true]

        case "syncEmailNow":
            guard let accountID = payload["accountID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["result": try XPCJSON.object(from: await runtime.emailSyncEngine.syncNow(accountID: accountID))]

        case "emailMessages":
            return ["messages": try XPCJSON.object(from: try emailMessages(payload: payload))]

        case "mailboxes":
            guard let accountID = payload["accountID"] as? String else {
                throw ManifoldXPCError.invalidPayload
            }
            let mailboxes = try runtime.emailStore.mailboxes(accountID: accountID).map(MailboxCount.init)
            return ["mailboxes": try XPCJSON.object(from: mailboxes)]

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
            return ["count": try runtime.emailStore.sharedEmailCount()]

        case "sharedEmailIDs":
            return ["ids": Array(try runtime.emailStore.sharedEmailIDs()).sorted()]

        case "sharedEmails":
            let limit = payload["limit"] as? Int ?? 500
            return ["messages": try XPCJSON.object(from: runtime.emailStore.sharedEmails(limit: limit))]

        case "shareEmails":
            let emailIDs = payload["emailIDs"] as? [String] ?? []
            try runtime.emailStore.shareEmails(emailIDs: emailIDs)
            return ["ok": true]

        case "unshareEmails":
            let emailIDs = payload["emailIDs"] as? [String] ?? []
            try runtime.emailStore.unshareEmails(emailIDs: emailIDs)
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

        case "smartMailboxCount":
            guard let rulesJSON = payload["rulesJSON"] as? String,
                  let rules = try? JSONDecoder().decode(SmartMailboxRules.self, from: Data(rulesJSON.utf8)) else {
                throw ManifoldXPCError.invalidPayload
            }
            return ["count": try runtime.emailStore.smartMailboxCount(rules: rules)]

        case "smartMailboxMessages":
            guard let rulesJSON = payload["rulesJSON"] as? String,
                  let rules = try? JSONDecoder().decode(SmartMailboxRules.self, from: Data(rulesJSON.utf8)) else {
                throw ManifoldXPCError.invalidPayload
            }
            let sortKey = try decodeOptionalPayload(EmailSortKey.self, key: "sortKey", from: payload) ?? .date
            return ["messages": try XPCJSON.object(from: runtime.emailStore.smartMailboxMessages(rules: rules, sortKey: sortKey))]

        case "emailBackupInfo":
            return ["info": try XPCJSON.object(from: EmailBackupInfoPayload(path: EmailSyncEngine.backupRoot.path, diskUsage: backupDiskUsage()))]

        default:
            return nil
        }
    }

    private func activeGrantStateCommand(payload: [String: Any]) async throws -> [String: Any] {
        let preferredAgent = (payload["targetApp"] as? String).flatMap(TargetApp.init(rawValue:)) ?? .cowork
        let state = try await activeGrantState(preferredAgent: preferredAgent)
        return [
            "activeGrant": state.grant.map { try! XPCJSON.object(from: $0) } ?? NSNull(),
            "activeGrantSources": try XPCJSON.object(from: state.sources),
            "targetApp": state.targetApp?.rawValue as Any,
        ]
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
            inputs = activeSources.map { source in
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
                visibleEmailCount = try runtime.emailStore.sharedEmails(limit: 5_000).count
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
        let explicitScopes = normalizedScopes(fileScopes)
        let usingExplicitSelection = !explicitScopes.isEmpty || !selectedEmailIDs.isEmpty
        let activeSourceMap = Dictionary(uniqueKeysWithValues: activeSources.map { ($0.sourceID, $0) })
        let explicitSourceIDs = Array(Set(explicitScopes.map(\.sourceID))).sorted()
        let sourceIDs = usingExplicitSelection ? explicitSourceIDs : activeSources.map(\.sourceID)
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

    private func restoreSnapshot(snapshotID: Int, filePath: String) async throws -> Bool {
        let state = try await activeGrantState(preferredAgent: .cowork)
        guard let grant = state.grant,
              let data = try await runtime.snapshotStore.dataForRestore(snapshotID: snapshotID),
              let resolved = Self.resolveGrantFilePath(
                canonicalPath: filePath,
                grant: grant,
                grantSources: state.sources
              ) else {
            return false
        }

        try FileManager.default.createDirectory(
            at: resolved.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: resolved.fileURL, options: .atomic)
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
            fileURL: resolved.fileURL
        )
        return true
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
           let currentData = try? Data(contentsOf: resolved.fileURL),
           Self.hashHex(for: currentData) != afterHash {
            return ["status": "contentDrift"]
        }

        try FileManager.default.createDirectory(
            at: resolved.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try blobData.write(to: resolved.fileURL, options: .atomic)
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
            fileURL: resolved.fileURL
        )
        return ["status": "success"]
    }

    private func emailMessages(payload: [String: Any]) throws -> [EmailMessageRecord] {
        if let ids = payload["ids"] as? [String] {
            return try runtime.emailStore.emailMessages(ids: ids)
        }
        if let accountID = payload["accountID"] as? String, let mailbox = payload["mailbox"] as? String {
            return try runtime.emailStore.messagesInMailbox(accountID: accountID, mailbox: mailbox, limit: payload["limit"] as? Int ?? 500)
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
            return try runtime.emailStore.sharedEmails(limit: limit)
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
            let relativePath = String(components[1])
            let fileURL = URL(fileURLWithPath: mount.mountPath)
                .appendingPathComponent(relativePath)
                .standardizedFileURL
            guard fileURL.path.hasPrefix(URL(fileURLWithPath: mount.mountPath).standardizedFileURL.path) else {
                return nil
            }
            return (mount, relativePath, fileURL)
        }

        if mounts.count == 1, let mount = mounts.first {
            let fileURL = URL(fileURLWithPath: mount.mountPath)
                .appendingPathComponent(cleaned)
                .standardizedFileURL
            guard fileURL.path.hasPrefix(URL(fileURLWithPath: mount.mountPath).standardizedFileURL.path) else {
                return nil
            }
            return (mount, cleaned, fileURL)
        }

        return nil
    }

    private static func hashHex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
