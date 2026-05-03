// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("Mail sync coordinator")
struct MailSyncCoordinatorTests {
    private func makeStore() throws -> (EmailStore, DatabaseConnection, URL, String) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-mail-sync-coordinator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        try DatabaseMigrator(db: db).migrate()
        let store = EmailStore(db: db)
        let account = try store.addEmailAccount(
            displayName: "Coordinator",
            providerType: EmailProvider.fastmail.rawValue,
            server: "imap.fastmail.com",
            port: 993,
            username: "user@example.com",
            authType: "app_password"
        )
        return (store, db, tempDir, account.accountID)
    }

    @Test("Startup registration enqueues initial sync for fresh enabled accounts")
    func startupEnqueuesInitialForFreshAccount() async throws {
        let (store, _, tempDir, accountID) = try makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = MailSyncCoordinator(emailStore: store)
        await coordinator.registerEnabledAccounts(startWorkers: false)

        let jobs = try await coordinator.jobs(accountID: accountID)
        #expect(jobs.count == 1)
        #expect(jobs.first?.jobType == .initial)
        #expect(jobs.first?.state == .queued)
    }

    @Test("Startup registration enqueues recent pass when durable state exists")
    func startupEnqueuesRecentPassForExistingState() async throws {
        let (store, _, tempDir, accountID) = try makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try store.updateSyncState(
            accountID: accountID,
            mailbox: "INBOX",
            uidValidity: 1,
            lastSyncUID: 42,
            messageCount: 10,
            syncStatus: .idle
        )

        let coordinator = MailSyncCoordinator(emailStore: store)
        await coordinator.registerEnabledAccounts(startWorkers: false)

        let jobs = try await coordinator.jobs(accountID: accountID)
        #expect(jobs.map(\.jobType) == [.recentPass])
    }

    @Test("Abandoned running jobs can be recovered as bounded recent passes")
    func recoversAbandonedRunningJobsAsRecentPasses() async throws {
        let (store, _, tempDir, accountID) = try makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        _ = try store.enqueueMailSyncJob(
            accountID: accountID,
            jobType: .incremental,
            priority: 900
        )
        _ = try store.claimNextQueuedMailSyncJob(accountID: accountID)

        let coordinator = MailSyncCoordinator(emailStore: store)
        let recovered = try store.requeueRunningMailSyncJobs()

        #expect(recovered == 1)
        let queued = try await coordinator.jobs(accountID: accountID, states: [.queued])
        #expect(queued.contains { $0.jobType == .recentPass })
        #expect(queued.allSatisfy { $0.state == .queued })
    }

    @Test("Processing a job updates durable state and schedules historical backfill after initial")
    func processJobUpdatesDurableState() async throws {
        let (store, _, tempDir, accountID) = try makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = MailSyncCoordinator(emailStore: store) { accountID, _ in
            SyncResult(
                accountID: accountID,
                newMessages: 3,
                mailboxResults: [
                    MailboxSyncResult(
                        mailboxName: "INBOX",
                        newMessages: 3,
                        lastUID: 200,
                        uidValidity: 1,
                        oldestFetchedUID: 101,
                        fetchedUIDCount: 100,
                        hasMoreHistory: true
                    )
                ]
            )
        }
        _ = try await coordinator.enqueueInitialSync(accountID: accountID)

        let processed = try await coordinator.processNextJob(accountID: accountID)

        #expect(processed?.state == .succeeded)
        let queued = try await coordinator.jobs(accountID: accountID, states: [.queued])
        #expect(queued.map(\.jobType) == [.historicalBackfill])
        #expect(queued.map(\.mailboxName) == ["INBOX"])
    }

    @Test("Historical backfill requeues same mailbox while more history remains")
    func historicalBackfillRequeuesWhileMoreHistoryRemains() async throws {
        let (store, _, tempDir, accountID) = try makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = MailSyncCoordinator(emailStore: store) { accountID, job in
            SyncResult(
                accountID: accountID,
                newMessages: 1,
                mailboxResults: [
                    MailboxSyncResult(
                        mailboxName: job.mailboxName ?? "INBOX",
                        newMessages: 1,
                        lastUID: 500,
                        uidValidity: 1,
                        oldestFetchedUID: 250,
                        fetchedUIDCount: 1,
                        hasMoreHistory: true
                    )
                ]
            )
        }
        let job = try await coordinator.enqueueHistoricalBackfill(accountID: accountID, mailboxName: "Archive")

        let processed = try await coordinator.processNextJob(accountID: accountID)

        #expect(processed?.id == job.id)
        #expect(processed?.state == .succeeded)
        let queued = try await coordinator.jobs(accountID: accountID, states: [.queued])
        #expect(queued.count == 1)
        #expect(queued.first?.jobType == .historicalBackfill)
        #expect(queued.first?.mailboxName == "Archive")
    }

    @Test("Retryable failures are delayed instead of becoming immediate needs-attention failures")
    func retryableFailureSchedulesRetry() async throws {
        let (store, _, tempDir, accountID) = try makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = MailSyncCoordinator(emailStore: store) { accountID, _ in
            SyncResult(
                accountID: accountID,
                errors: ["Trash: IMAP connection lost"]
            )
        }
        _ = try await coordinator.enqueueRecentPass(accountID: accountID)

        let processed = try await coordinator.processNextJob(accountID: accountID)

        #expect(processed?.state == .queued)
        #expect(processed?.errorCode == "sync_retry_scheduled")
        #expect(processed?.attemptCount == 1)
        #expect(processed?.nextAttemptAt != nil)
        let events = try store.mailSyncActivity(accountID: accountID)
        #expect(events.contains { $0.kind == .retryScheduled })
    }

    @Test("Failed jobs keep a redacted error and do not spin")
    func failedJobRecordsRedactedError() async throws {
        let (store, _, tempDir, accountID) = try makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = MailSyncCoordinator(emailStore: store) { accountID, _ in
            SyncResult(accountID: accountID, errors: ["Authentication failed"])
        }
        let job = try await coordinator.enqueueIncrementalSync(accountID: accountID)

        let processed = try await coordinator.processNextJob(accountID: accountID)

        #expect(processed?.id == job.id)
        #expect(processed?.state == .failed)
        #expect(processed?.errorCode == "sync_failed")
        #expect(processed?.errorRedacted == "Authentication failed")
    }

    @Test("Pause and resume update account and queued job state")
    func pauseResumeJobs() async throws {
        let (store, _, tempDir, accountID) = try makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = MailSyncCoordinator(emailStore: store)
        _ = try await coordinator.enqueueIncrementalSync(accountID: accountID)

        try await coordinator.pause(accountID: accountID)
        #expect(try store.emailAccount(id: accountID)?.syncEnabled == false)
        #expect(try await coordinator.jobs(accountID: accountID, states: [.paused]).count == 1)

        try await coordinator.resume(accountID: accountID, startWorker: false)
        #expect(try store.emailAccount(id: accountID)?.syncEnabled == true)
        #expect(try await coordinator.jobs(accountID: accountID, states: [.queued]).count == 1)
    }
}
