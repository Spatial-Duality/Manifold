// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let mailSyncCoordinatorLogger = Logger(
    subsystem: "com.spatialduality.manifold",
    category: "mail-sync-coordinator"
)

public actor MailSyncCoordinator {
    public typealias SyncRunner = @Sendable (String, MailSyncJobRecord) async -> SyncResult

    private let emailStore: EmailStore
    private let syncRunner: SyncRunner
    private var accountTasks: [String: Task<Void, Never>] = [:]
    private var activeJobAccounts = Set<String>()
    private var stopped = false
    private let idleDelay: Duration

    public init(
        emailStore: EmailStore,
        syncEngine: EmailSyncEngine? = nil,
        idleDelay: Duration = .seconds(5),
        syncRunner: SyncRunner? = nil
    ) {
        self.emailStore = emailStore
        self.idleDelay = idleDelay
        let engine = syncEngine ?? EmailSyncEngine(emailStore: emailStore)
        self.syncRunner = syncRunner ?? { _, job in
            await engine.syncJob(job)
        }
    }

    public func startRuntimeSync() async {
        stopped = false
        do {
            let recovered = try emailStore.requeueRunningMailSyncJobs()
            if recovered > 0 {
                mailSyncCoordinatorLogger.info("Recovered \(recovered) abandoned running mail sync jobs")
            }
        } catch {
            mailSyncCoordinatorLogger.error("Failed to recover abandoned mail sync jobs: \(error.localizedDescription)")
        }
        await registerEnabledAccounts(startWorkers: true)
    }

    public func registerEnabledAccounts(startWorkers: Bool = true) async {
        do {
            let accounts = try emailStore.allEmailAccounts().filter(\.syncEnabled)
            for account in accounts {
                _ = try enqueueStartupJob(accountID: account.accountID)
                if startWorkers {
                    register(accountID: account.accountID)
                }
            }
            mailSyncCoordinatorLogger.info("Registered \(accounts.count) enabled mail accounts")
        } catch {
            mailSyncCoordinatorLogger.error("Failed to register enabled mail accounts: \(error.localizedDescription)")
        }
    }

    @discardableResult
    public func enqueueInitialSync(accountID: String) throws -> MailSyncJobRecord {
        try emailStore.enqueueMailSyncJob(
            accountID: accountID,
            jobType: .initial,
            priority: 1_000
        )
    }

    @discardableResult
    public func enqueueIncrementalSync(accountID: String) throws -> MailSyncJobRecord {
        try emailStore.enqueueMailSyncJob(
            accountID: accountID,
            jobType: .incremental,
            priority: 900
        )
    }

    @discardableResult
    public func enqueueRecentPass(accountID: String) throws -> MailSyncJobRecord {
        try emailStore.enqueueMailSyncJob(
            accountID: accountID,
            jobType: .recentPass,
            priority: 900
        )
    }

    @discardableResult
    public func enqueueHistoricalBackfill(accountID: String, mailboxName: String? = nil) throws -> MailSyncJobRecord {
        try emailStore.enqueueMailSyncJob(
            accountID: accountID,
            mailboxName: mailboxName,
            jobType: .historicalBackfill,
            priority: 100
        )
    }

    public func jobs(accountID: String, states: [MailSyncJobState]? = nil) throws -> [MailSyncJobRecord] {
        try emailStore.mailSyncJobs(accountID: accountID, states: states)
    }

    @discardableResult
    public func recoverStaleRunningJobs(
        accountID: String,
        olderThan age: TimeInterval = 300
    ) throws -> Int {
        guard !activeJobAccounts.contains(accountID) else { return 0 }
        return try emailStore.requeueRunningMailSyncJobs(
            accountID: accountID,
            updatedBefore: Date().addingTimeInterval(-age),
            errorRedacted: "Recovered stale running job before manual sync"
        )
    }

    public func pause(accountID: String) async throws {
        try emailStore.setEmailAccountSyncEnabled(accountID: accountID, enabled: false)
        try emailStore.pauseMailSyncJobs(accountID: accountID)
        accountTasks[accountID]?.cancel()
        accountTasks.removeValue(forKey: accountID)
    }

    public func resume(accountID: String, startWorker: Bool = true) async throws {
        try emailStore.setEmailAccountSyncEnabled(accountID: accountID, enabled: true)
        try emailStore.resumeMailSyncJobs(accountID: accountID)
        if try emailStore.mailSyncJobs(accountID: accountID, states: [.queued]).isEmpty {
            _ = try enqueueRecentPass(accountID: accountID)
        }
        if startWorker {
            register(accountID: accountID)
        }
    }

    public func stop() {
        stopped = true
        for task in accountTasks.values {
            task.cancel()
        }
        accountTasks.removeAll()
    }

    @discardableResult
    public func processNextJob(accountID: String) async throws -> MailSyncJobRecord? {
        try await processNextJobWithResult(accountID: accountID)?.job
    }

    public func processNextJobWithResult(accountID: String) async throws -> (job: MailSyncJobRecord, result: SyncResult)? {
        guard let job = try emailStore.claimNextQueuedMailSyncJob(accountID: accountID) else {
            return nil
        }

        activeJobAccounts.insert(job.accountID)
        defer {
            activeJobAccounts.remove(job.accountID)
        }
        let result = await syncRunner(accountID, job)
        if result.isSuccess {
            try emailStore.updateMailSyncJobState(id: job.id, state: .succeeded)
            try scheduleFollowupJobs(after: job, result: result)
        } else {
            try scheduleFollowupJobs(after: job, result: result)
            try emailStore.updateMailSyncJobState(
                id: job.id,
                state: .failed,
                errorCode: "sync_failed",
                errorRedacted: result.errors.joined(separator: "; ").prefix(512).description
            )
        }
        let updatedJob = try emailStore.mailSyncJob(id: job.id) ?? job
        return (updatedJob, result)
    }

    private func scheduleFollowupJobs(after job: MailSyncJobRecord, result: SyncResult) throws {
        switch job.jobType {
        case .initial, .recentPass, .historicalBackfill:
            let backfillMailboxes = result.mailboxResults
                .filter(\.hasMoreHistory)
                .map(\.mailboxName)
            for mailboxName in backfillMailboxes {
                _ = try enqueueHistoricalBackfill(accountID: job.accountID, mailboxName: mailboxName)
            }
        case .incremental, .reconcile:
            break
        }
    }

    private func enqueueStartupJob(accountID: String) throws -> MailSyncJobRecord {
        let states = try emailStore.syncStates(accountID: accountID)
        if states.isEmpty {
            return try enqueueInitialSync(accountID: accountID)
        }
        return try enqueueRecentPass(accountID: accountID)
    }

    private func register(accountID: String) {
        guard accountTasks[accountID] == nil else { return }
        stopped = false
        accountTasks[accountID] = Task {
            await self.runAccountQueue(accountID: accountID)
        }
    }

    private func runAccountQueue(accountID: String) async {
        while !Task.isCancelled && !stopped {
            do {
                guard let account = try emailStore.emailAccount(id: accountID), account.syncEnabled else {
                    try await Task.sleep(for: idleDelay)
                    continue
                }

                if try await processNextJob(accountID: accountID) == nil {
                    try await Task.sleep(for: idleDelay)
                }
            } catch is CancellationError {
                break
            } catch {
                mailSyncCoordinatorLogger.warning(
                    "Mail sync worker error for \(accountID): \(error.localizedDescription)"
                )
                try? await Task.sleep(for: idleDelay)
            }
        }
    }
}
