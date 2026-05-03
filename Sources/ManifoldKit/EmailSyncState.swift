// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - SyncStateRecord

/// Per-mailbox sync state tracking for incremental backup.
public struct SyncStateRecord: Sendable, Identifiable, Codable {
    public var id: String { "\(accountID)/\(mailboxName)" }
    public let accountID: String
    public let mailboxName: String
    public let uidValidity: UInt32?
    public let lastSyncUID: UInt32
    public let lastSyncAt: String?
    public let messageCount: Int
    public let syncStatus: SyncStatus
    public let errorMessage: String?
    public let oldestSyncedUID: UInt32?
    public let serverMessageCount: Int?
    public let backfillCompleted: Bool
    public let lastSuccessfulSyncAt: String?
    public let lastErrorAt: String?

    public init(
        accountID: String,
        mailboxName: String,
        uidValidity: UInt32? = nil,
        lastSyncUID: UInt32 = 0,
        lastSyncAt: String? = nil,
        messageCount: Int = 0,
        syncStatus: SyncStatus = .idle,
        errorMessage: String? = nil,
        oldestSyncedUID: UInt32? = nil,
        serverMessageCount: Int? = nil,
        backfillCompleted: Bool = false,
        lastSuccessfulSyncAt: String? = nil,
        lastErrorAt: String? = nil
    ) {
        self.accountID = accountID
        self.mailboxName = mailboxName
        self.uidValidity = uidValidity
        self.lastSyncUID = lastSyncUID
        self.lastSyncAt = lastSyncAt
        self.messageCount = messageCount
        self.syncStatus = syncStatus
        self.errorMessage = errorMessage
        self.oldestSyncedUID = oldestSyncedUID
        self.serverMessageCount = serverMessageCount
        self.backfillCompleted = backfillCompleted
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastErrorAt = lastErrorAt
    }

    public init?(row: [String: String]) {
        guard let accountID = row["account_id"],
              let mailboxName = row["mailbox_name"] else { return nil }
        self.accountID = accountID
        self.mailboxName = mailboxName
        self.uidValidity = row["uid_validity"].flatMap { UInt32($0) }
        self.lastSyncUID = row["last_sync_uid"].flatMap { UInt32($0) } ?? 0
        self.lastSyncAt = row["last_sync_at"]
        self.messageCount = row["message_count"].flatMap { Int($0) } ?? 0
        self.syncStatus = SyncStatus(rawValue: row["sync_status"] ?? "idle") ?? .idle
        self.errorMessage = row["error_message"].flatMap { $0.isEmpty ? nil : $0 }
        self.oldestSyncedUID = row["oldest_synced_uid"].flatMap { UInt32($0) }
        self.serverMessageCount = row["server_message_count"].flatMap { Int($0) }
        self.backfillCompleted = row["backfill_completed"] == "1"
        self.lastSuccessfulSyncAt = row["last_successful_sync_at"].flatMap { $0.isEmpty ? nil : $0 }
        self.lastErrorAt = row["last_error_at"].flatMap { $0.isEmpty ? nil : $0 }
    }
}

// MARK: - SyncStatus

public enum SyncStatus: String, Sendable, Codable {
    case idle = "idle"
    case syncing = "syncing"
    case error = "error"
    case pausedNoDrive = "paused_no_drive"
}

// MARK: - SyncResult

/// Result of a single sync cycle for one account.
public struct SyncResult: Sendable, Codable {
    public let accountID: String
    public let newMessages: Int
    public let updatedMessages: Int
    public let errors: [String]
    public let duration: TimeInterval
    public let mailboxResults: [MailboxSyncResult]

    public var isSuccess: Bool { errors.isEmpty }

    public init(
        accountID: String,
        newMessages: Int = 0,
        updatedMessages: Int = 0,
        errors: [String] = [],
        duration: TimeInterval = 0,
        mailboxResults: [MailboxSyncResult] = []
    ) {
        self.accountID = accountID
        self.newMessages = newMessages
        self.updatedMessages = updatedMessages
        self.errors = errors
        self.duration = duration
        self.mailboxResults = mailboxResults
    }
}

/// Result of syncing a single mailbox.
public struct MailboxSyncResult: Sendable, Codable {
    public let mailboxName: String
    public let newMessages: Int
    public let lastUID: UInt32
    public let uidValidity: UInt32
    public let oldestFetchedUID: UInt32?
    public let fetchedUIDCount: Int
    public let hasMoreHistory: Bool

    public init(
        mailboxName: String,
        newMessages: Int = 0,
        lastUID: UInt32 = 0,
        uidValidity: UInt32 = 0,
        oldestFetchedUID: UInt32? = nil,
        fetchedUIDCount: Int = 0,
        hasMoreHistory: Bool = false
    ) {
        self.mailboxName = mailboxName
        self.newMessages = newMessages
        self.lastUID = lastUID
        self.uidValidity = uidValidity
        self.oldestFetchedUID = oldestFetchedUID
        self.fetchedUIDCount = fetchedUIDCount
        self.hasMoreHistory = hasMoreHistory
    }
}

// MARK: - Durable Mail Sync Jobs

public enum MailSyncExecutionMode: Sendable, Equatable {
    case incremental
    case recentPass(limitPerMailbox: Int)
    case historicalBackfill(batchLimitPerMailbox: Int)

    public var isHistoricalBackfill: Bool {
        if case .historicalBackfill = self { return true }
        return false
    }

    public var isRecentPass: Bool {
        if case .recentPass = self { return true }
        return false
    }
}

public enum MailSyncJobType: String, Sendable, Codable, CaseIterable {
    case initial
    case recentPass
    case historicalBackfill
    case incremental
    case reconcile
}

public enum MailSyncJobState: String, Sendable, Codable, CaseIterable {
    case queued
    case running
    case succeeded
    case failed
    case paused
    case cancelled
}

public struct MailSyncJobRecord: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let accountID: String
    public let mailboxName: String?
    public let jobType: MailSyncJobType
    public let state: MailSyncJobState
    public let priority: Int
    public let cursorJSONCiphertext: String?
    public let errorCode: String?
    public let errorRedacted: String?
    public let createdAt: String
    public let updatedAt: String
    public let attemptCount: Int
    public let nextAttemptAt: String?

    public init(
        id: String = UUID().uuidString,
        accountID: String,
        mailboxName: String? = nil,
        jobType: MailSyncJobType,
        state: MailSyncJobState = .queued,
        priority: Int,
        cursorJSONCiphertext: String? = nil,
        errorCode: String? = nil,
        errorRedacted: String? = nil,
        createdAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        updatedAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        attemptCount: Int = 0,
        nextAttemptAt: String? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.mailboxName = mailboxName
        self.jobType = jobType
        self.state = state
        self.priority = priority
        self.cursorJSONCiphertext = cursorJSONCiphertext
        self.errorCode = errorCode
        self.errorRedacted = errorRedacted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
    }

    public init?(row: [String: String]) {
        guard let id = row["id"],
              let accountID = row["account_id"],
              let rawType = row["job_type"],
              let jobType = MailSyncJobType(rawValue: rawType),
              let rawState = row["state"],
              let state = MailSyncJobState(rawValue: rawState),
              let createdAt = row["created_at"],
              let updatedAt = row["updated_at"] else {
            return nil
        }
        self.id = id
        self.accountID = accountID
        self.mailboxName = row["mailbox_name"]
        self.jobType = jobType
        self.state = state
        self.priority = row["priority"].flatMap(Int.init) ?? 0
        self.cursorJSONCiphertext = row["cursor_json_ciphertext"]
        self.errorCode = row["error_code"]
        self.errorRedacted = row["error_redacted"]
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attemptCount = row["attempt_count"].flatMap(Int.init) ?? 0
        self.nextAttemptAt = row["next_attempt_at"].flatMap { $0.isEmpty ? nil : $0 }
    }

    public var hasRetryScheduled: Bool {
        state == .failed && nextAttemptAt != nil
    }
}

public enum MailSyncEventKind: String, Sendable, Codable, CaseIterable {
    case jobQueued
    case jobStarted
    case jobSucceeded
    case retryScheduled
    case jobFailed
    case mailboxStarted
    case mailboxCompleted
    case mailboxError
    case dateRepair
    case headerRepair
    case accountDeleted
}

public struct MailSyncActivityLogEntry: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let accountID: String
    public let mailboxName: String?
    public let kind: MailSyncEventKind
    public let status: String
    public let jobType: MailSyncJobType?
    public let errorCode: String?
    public let detailRedacted: String?
    public let createdAt: String
    public let needsAttention: Bool

    public init(
        id: String = UUID().uuidString,
        accountID: String,
        mailboxName: String? = nil,
        kind: MailSyncEventKind,
        status: String,
        jobType: MailSyncJobType? = nil,
        errorCode: String? = nil,
        detailRedacted: String? = nil,
        createdAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        needsAttention: Bool = false
    ) {
        self.id = id
        self.accountID = accountID
        self.mailboxName = mailboxName
        self.kind = kind
        self.status = status
        self.jobType = jobType
        self.errorCode = errorCode
        self.detailRedacted = detailRedacted
        self.createdAt = createdAt
        self.needsAttention = needsAttention
    }

    public init?(row: [String: String]) {
        guard let id = row["id"],
              let accountID = row["account_id"],
              let rawKind = row["kind"],
              let kind = MailSyncEventKind(rawValue: rawKind),
              let status = row["status"],
              let createdAt = row["created_at"] else {
            return nil
        }
        self.id = id
        self.accountID = accountID
        self.mailboxName = row["mailbox_name"]
        self.kind = kind
        self.status = status
        self.jobType = row["job_type"].flatMap(MailSyncJobType.init(rawValue:))
        self.errorCode = row["error_code"]
        self.detailRedacted = row["detail_redacted"]
        self.createdAt = createdAt
        self.needsAttention = row["needs_attention"] == "1"
    }
}
