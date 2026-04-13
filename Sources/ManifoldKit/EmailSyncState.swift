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

    public init(
        accountID: String,
        mailboxName: String,
        uidValidity: UInt32? = nil,
        lastSyncUID: UInt32 = 0,
        lastSyncAt: String? = nil,
        messageCount: Int = 0,
        syncStatus: SyncStatus = .idle,
        errorMessage: String? = nil
    ) {
        self.accountID = accountID
        self.mailboxName = mailboxName
        self.uidValidity = uidValidity
        self.lastSyncUID = lastSyncUID
        self.lastSyncAt = lastSyncAt
        self.messageCount = messageCount
        self.syncStatus = syncStatus
        self.errorMessage = errorMessage
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

    public init(
        mailboxName: String,
        newMessages: Int = 0,
        lastUID: UInt32 = 0,
        uidValidity: UInt32 = 0
    ) {
        self.mailboxName = mailboxName
        self.newMessages = newMessages
        self.lastUID = lastUID
        self.uidValidity = uidValidity
    }
}
