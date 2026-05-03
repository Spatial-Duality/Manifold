// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import ManifoldKit

@Suite("Mail sync progress")
struct MailSyncProgressTests {
    @Test
    func derivesUpToDateAccount() {
        let snapshot = MailSyncProgressSnapshot.derive(
            account: account(),
            states: [state(mailbox: "INBOX", count: 842, backfillCompleted: true)],
            jobs: [],
            syncedMessageCount: 842
        )

        #expect(snapshot.stage == .upToDate)
        #expect(snapshot.syncedMessageCount == 842)
        #expect(snapshot.mailboxSyncedCounts["INBOX"] == 842)
        #expect(snapshot.progressCompleted == nil)
        #expect(snapshot.progressTotal == nil)
    }

    @Test
    func derivesRunningRecentSync() {
        let snapshot = MailSyncProgressSnapshot.derive(
            account: account(),
            states: [],
            jobs: [job(type: .recentPass, state: .running, mailbox: "INBOX")],
            syncedMessageCount: 0
        )

        #expect(snapshot.stage == .syncingRecentMail)
        #expect(snapshot.runningJobCount == 1)
        #expect(snapshot.currentMailboxName == "INBOX")
    }

    @Test
    func derivesRecentReadyWithHistoricalBackfillQueued() {
        let snapshot = MailSyncProgressSnapshot.derive(
            account: account(),
            states: [state(mailbox: "INBOX", count: 120)],
            jobs: [job(type: .historicalBackfill, state: .queued, mailbox: "Archive")],
            syncedMessageCount: 120
        )

        #expect(snapshot.stage == .recentMailReady)
        #expect(snapshot.queuedBackfillCount == 1)
    }

    @Test
    func derivesPausedAccount() {
        let snapshot = MailSyncProgressSnapshot.derive(
            account: account(syncEnabled: false),
            states: [state(mailbox: "INBOX", count: 10)],
            jobs: [job(type: .recentPass, state: .running)],
            syncedMessageCount: 10
        )

        #expect(snapshot.stage == .paused)
    }

    @Test
    func derivesMailboxError() {
        let snapshot = MailSyncProgressSnapshot.derive(
            account: account(),
            states: [
                state(mailbox: "INBOX", count: 10),
                state(mailbox: "Archive", count: 0, syncStatus: .error, errorMessage: "Login expired"),
            ],
            jobs: [job(type: .historicalBackfill, state: .failed, mailbox: "Sent", error: "Timed out")],
            syncedMessageCount: 10
        )

        #expect(snapshot.stage == .needsAttention)
        #expect(snapshot.failedMailboxCount == 2)
        #expect(snapshot.failedMailboxNames == ["Archive", "Sent"])
        #expect(snapshot.errorMessage == "Login expired")
    }

    @Test
    func unknownRemainingWorkDoesNotProduceFakeTotals() {
        let snapshot = MailSyncProgressSnapshot.derive(
            account: account(),
            states: [state(mailbox: "INBOX", count: 50)],
            jobs: [job(type: .historicalBackfill, state: .running, mailbox: "Archive")],
            syncedMessageCount: 50
        )

        #expect(snapshot.stage == .archivingOlderMail)
        #expect(snapshot.progressCompleted == nil)
        #expect(snapshot.progressTotal == nil)
    }

    private func account(syncEnabled: Bool = true) -> EmailAccountRecord {
        EmailAccountRecord(
            accountID: "account-1",
            displayName: "Gmail",
            providerType: EmailProvider.gmail.rawValue,
            syncEnabled: syncEnabled,
            createdAt: "2026-05-02T10:00:00Z",
            updatedAt: "2026-05-02T10:05:00Z"
        )
    }

    private func state(
        mailbox: String,
        count: Int,
        syncStatus: SyncStatus = .idle,
        errorMessage: String? = nil,
        backfillCompleted: Bool = false
    ) -> SyncStateRecord {
        SyncStateRecord(
            accountID: "account-1",
            mailboxName: mailbox,
            lastSyncAt: "2026-05-02T10:05:00Z",
            messageCount: count,
            syncStatus: syncStatus,
            errorMessage: errorMessage,
            backfillCompleted: backfillCompleted
        )
    }

    private func job(
        type: MailSyncJobType,
        state: MailSyncJobState,
        mailbox: String? = nil,
        error: String? = nil
    ) -> MailSyncJobRecord {
        MailSyncJobRecord(
            id: "\(type.rawValue)-\(state.rawValue)",
            accountID: "account-1",
            mailboxName: mailbox,
            jobType: type,
            state: state,
            priority: 10,
            errorRedacted: error,
            createdAt: "2026-05-02T10:00:00Z",
            updatedAt: "2026-05-02T10:03:00Z"
        )
    }
}
