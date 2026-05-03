// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct MailAccountRemovalResult: Codable, Sendable, Equatable {
    public let accountID: String
    public let displayName: String
    public let providerType: String?
    public let username: String?
    public let removedAt: String
    public let messageCount: Int
    public let attachmentCount: Int
    public let blobRecordCount: Int
    public let accessAuditEventCount: Int
    public let sharedReferenceCount: Int
    public let grantReferenceCount: Int
    public let temporaryRevealCount: Int
    public let accessPresetReferenceCount: Int
    public let contextArchivePath: String

    public init(
        accountID: String,
        displayName: String,
        providerType: String?,
        username: String?,
        removedAt: String,
        messageCount: Int,
        attachmentCount: Int,
        blobRecordCount: Int,
        accessAuditEventCount: Int,
        sharedReferenceCount: Int,
        grantReferenceCount: Int,
        temporaryRevealCount: Int,
        accessPresetReferenceCount: Int,
        contextArchivePath: String
    ) {
        self.accountID = accountID
        self.displayName = displayName
        self.providerType = providerType
        self.username = username
        self.removedAt = removedAt
        self.messageCount = messageCount
        self.attachmentCount = attachmentCount
        self.blobRecordCount = blobRecordCount
        self.accessAuditEventCount = accessAuditEventCount
        self.sharedReferenceCount = sharedReferenceCount
        self.grantReferenceCount = grantReferenceCount
        self.temporaryRevealCount = temporaryRevealCount
        self.accessPresetReferenceCount = accessPresetReferenceCount
        self.contextArchivePath = contextArchivePath
    }
}

