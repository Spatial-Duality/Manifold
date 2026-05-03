// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum MailSyncProgressStage: String, Sendable, Codable, CaseIterable {
    case checkingMailboxes
    case syncingRecentMail
    case recentMailReady
    case archivingOlderMail
    case indexingPrivately
    case paused
    case needsAttention
    case upToDate
}

public struct MailSyncProgressSnapshot: Sendable, Codable, Identifiable, Equatable {
    public var id: String { accountID }

    public let accountID: String
    public let displayName: String
    public let provider: EmailProvider
    public let syncedMessageCount: Int
    public let mailboxSyncedCounts: [String: Int]
    public let mailboxBackfillCompleted: [String: Bool]
    public let stage: MailSyncProgressStage
    public let runningJobCount: Int
    public let queuedBackfillCount: Int
    public let retryScheduledCount: Int
    public let failedMailboxCount: Int
    public let failedMailboxNames: [String]
    public let currentMailboxName: String?
    public let currentJobType: MailSyncJobType?
    public let lastUpdatedAt: String?
    public let progressCompleted: Int?
    public let progressTotal: Int?
    public let errorMessage: String?

    public init(
        accountID: String,
        displayName: String,
        provider: EmailProvider,
        syncedMessageCount: Int,
        mailboxSyncedCounts: [String: Int],
        mailboxBackfillCompleted: [String: Bool] = [:],
        stage: MailSyncProgressStage,
        runningJobCount: Int = 0,
        queuedBackfillCount: Int = 0,
        retryScheduledCount: Int = 0,
        failedMailboxCount: Int = 0,
        failedMailboxNames: [String] = [],
        currentMailboxName: String? = nil,
        currentJobType: MailSyncJobType? = nil,
        lastUpdatedAt: String? = nil,
        progressCompleted: Int? = nil,
        progressTotal: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.accountID = accountID
        self.displayName = displayName
        self.provider = provider
        self.syncedMessageCount = syncedMessageCount
        self.mailboxSyncedCounts = mailboxSyncedCounts
        self.mailboxBackfillCompleted = mailboxBackfillCompleted
        self.stage = stage
        self.runningJobCount = runningJobCount
        self.queuedBackfillCount = queuedBackfillCount
        self.retryScheduledCount = retryScheduledCount
        self.failedMailboxCount = failedMailboxCount
        self.failedMailboxNames = failedMailboxNames
        self.currentMailboxName = currentMailboxName
        self.currentJobType = currentJobType
        self.lastUpdatedAt = lastUpdatedAt
        self.progressCompleted = progressCompleted
        self.progressTotal = progressTotal
        self.errorMessage = errorMessage
    }

    public static func derive(
        account: EmailAccountRecord,
        states: [SyncStateRecord],
        jobs: [MailSyncJobRecord],
        syncedMessageCount: Int,
        authoritativeMailboxCounts: [String: Int]? = nil,
        privacyIndexActive: Bool = false
    ) -> MailSyncProgressSnapshot {
        var mailboxCounts: [String: Int] = [:]
        for state in states {
            mailboxCounts[state.mailboxName] = max(0, state.messageCount)
        }
        if let authoritativeMailboxCounts {
            mailboxCounts = authoritativeMailboxCounts
        }
        let mailboxBackfillCompleted = Dictionary(
            uniqueKeysWithValues: states.map { ($0.mailboxName, $0.backfillCompleted) }
        )
        let runningJobs = jobs.filter { $0.state == .running }
        let queuedJobs = jobs.filter { $0.state == .queued }
        let failedJobs = jobs.filter { $0.state == .failed }
        let retryScheduledJobs = failedJobs.filter(\.hasRetryScheduled)
        let permanentFailedJobs = failedJobs.filter { !$0.hasRetryScheduled }
        let queuedBackfillCount = queuedJobs.filter { $0.jobType == .historicalBackfill }.count
        let failedMailboxes = Set(
            states.filter { $0.syncStatus == .error }.map(\.mailboxName)
                + permanentFailedJobs.compactMap(\.mailboxName)
        )
        let currentJob = runningJobs.first ?? queuedJobs.first
        let lastUpdatedAt = ([account.updatedAt.nilIfEmpty]
            + states.map(\.lastSyncAt)
            + jobs.map { Optional($0.updatedAt) })
            .compactMap { $0 }
            .max()
        let errorMessage = states.first(where: { $0.syncStatus == .error })?.errorMessage
            ?? failedJobs.first?.errorRedacted

        return MailSyncProgressSnapshot(
            accountID: account.accountID,
            displayName: account.displayName,
            provider: account.provider,
            syncedMessageCount: max(0, syncedMessageCount),
            mailboxSyncedCounts: mailboxCounts,
            mailboxBackfillCompleted: mailboxBackfillCompleted,
            stage: deriveStage(
                account: account,
                syncedMessageCount: syncedMessageCount,
                runningJobs: runningJobs,
                queuedJobs: queuedJobs,
                queuedBackfillCount: queuedBackfillCount,
                retryScheduledCount: retryScheduledJobs.count,
                incompleteBackfillCount: mailboxBackfillCompleted.values.filter { !$0 }.count,
                failedMailboxCount: failedMailboxes.count,
                failedJobCount: permanentFailedJobs.count,
                privacyIndexActive: privacyIndexActive
            ),
            runningJobCount: runningJobs.count,
            queuedBackfillCount: queuedBackfillCount,
            retryScheduledCount: retryScheduledJobs.count,
            failedMailboxCount: failedMailboxes.count,
            failedMailboxNames: failedMailboxes.sorted(),
            currentMailboxName: currentJob?.mailboxName,
            currentJobType: currentJob?.jobType,
            lastUpdatedAt: lastUpdatedAt,
            progressCompleted: nil,
            progressTotal: nil,
            errorMessage: errorMessage
        )
    }

    private static func deriveStage(
        account: EmailAccountRecord,
        syncedMessageCount: Int,
        runningJobs: [MailSyncJobRecord],
        queuedJobs: [MailSyncJobRecord],
        queuedBackfillCount: Int,
        retryScheduledCount: Int,
        incompleteBackfillCount: Int,
        failedMailboxCount: Int,
        failedJobCount: Int,
        privacyIndexActive: Bool
    ) -> MailSyncProgressStage {
        guard account.syncEnabled else { return .paused }
        if failedMailboxCount > 0 || failedJobCount > 0 {
            return .needsAttention
        }
        if let runningJob = runningJobs.first {
            switch runningJob.jobType {
            case .initial, .reconcile:
                return .checkingMailboxes
            case .recentPass, .incremental:
                return .syncingRecentMail
            case .historicalBackfill:
                return .archivingOlderMail
            }
        }
        if queuedJobs.contains(where: { $0.jobType == .initial }) && syncedMessageCount == 0 {
            return .checkingMailboxes
        }
        if queuedJobs.contains(where: { $0.jobType == .recentPass || $0.jobType == .incremental })
            && syncedMessageCount == 0 {
            return .syncingRecentMail
        }
        if queuedBackfillCount > 0 {
            return syncedMessageCount > 0 ? .recentMailReady : .archivingOlderMail
        }
        if retryScheduledCount > 0 || incompleteBackfillCount > 0 {
            return syncedMessageCount > 0 ? .recentMailReady : .archivingOlderMail
        }
        if privacyIndexActive && syncedMessageCount > 0 {
            return .indexingPrivately
        }
        return .upToDate
    }
}
