// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation

public enum MailAgentSourceError: Error, LocalizedError, Sendable, Equatable {
    case accessDenied(String)
    case grantExpired
    case messageNotFound(String)
    case attachmentNotFound(String)
    case storedContentUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied(let kind):
            "Mail access denied: \(kind)"
        case .grantExpired:
            "Mail access grant has expired."
        case .messageNotFound(let id):
            "Mail message not found: \(id)"
        case .attachmentNotFound(let id):
            "Mail attachment not found: \(id)"
        case .storedContentUnavailable(let id):
            "Stored mail content is unavailable: \(id)"
        }
    }
}

public struct MailSearchQuery: Codable, Sendable, Equatable {
    public let query: String
    public let accountID: String?
    public let mailbox: String?
    public let limit: Int

    public init(query: String, accountID: String? = nil, mailbox: String? = nil, limit: Int = 25) {
        self.query = query
        self.accountID = accountID
        self.mailbox = mailbox
        self.limit = limit
    }
}

public struct MailSearchResult: Codable, Sendable, Equatable {
    public let messageID: String
    public let accountID: String
    public let mailbox: String
    public let date: String
    public let subject: String
    public let sender: String
    public let snippet: String?
}

public struct MailMessageForAgent: Codable, Sendable, Equatable {
    public let messageID: String
    public let accountID: String
    public let mailbox: String
    public let date: String
    public let subject: String
    public let sender: String
    public let untrustedSourceMaterial: String
}

public struct MailAttachmentForAgent: Sendable, Equatable {
    public let attachmentID: String
    public let messageID: String
    public let filename: String
    public let mimeType: String
    public let data: Data
    public let untrustedText: String?
}

public protocol MailAgentSourceService {
    func searchMail(query: MailSearchQuery, grant: MailAccessGrant) throws -> [MailSearchResult]
    func getMessageBody(messageID: String, grant: MailAccessGrant) throws -> MailMessageForAgent
    func getAttachment(attachmentID: String, grant: MailAccessGrant) throws -> MailAttachmentForAgent
    func exportMail(_ request: MailExportRequest, grant: MailAccessGrant) throws -> MailExportResult
}

public struct LocalMailAgentSourceService: MailAgentSourceService {
    private let emailStore: EmailStore
    private let archiveStore: MailArchiveStore
    private let exporter: MailExporter

    public init(emailStore: EmailStore, archiveStore: MailArchiveStore) {
        self.emailStore = emailStore
        self.archiveStore = archiveStore
        self.exporter = MailExporter(emailStore: emailStore, archiveStore: archiveStore)
    }

    public func searchMail(query: MailSearchQuery, grant: MailAccessGrant) throws -> [MailSearchResult] {
        try require(grant, allows: .search, accountID: query.accountID, emailID: nil)
        let limit = max(0, min(query.limit, grant.maxResults))
        let messages = try emailStore.searchEmailMessages(
            freeText: query.query,
            accountID: query.accountID,
            mailbox: query.mailbox,
            limit: max(limit * 4, limit)
        )
        let scoped = messages.filter { grantAllows($0, grant: grant) }.prefix(limit)
        try audit(
            grant: grant,
            accountID: query.accountID,
            emailID: nil,
            kind: "search",
            details: "queryTerms=\(MailPrivateTokenIndex.normalizedTokens(query.query).count); results=\(scoped.count)"
        )
        return scoped.map {
            MailSearchResult(
                messageID: $0.emailID,
                accountID: $0.accountID,
                mailbox: $0.mailbox,
                date: $0.receivedAt,
                subject: $0.subject,
                sender: $0.sender,
                snippet: $0.preview
            )
        }
    }

    public func getMessageBody(messageID: String, grant: MailAccessGrant) throws -> MailMessageForAgent {
        guard let message = try emailStore.emailMessage(id: messageID) else {
            throw MailAgentSourceError.messageNotFound(messageID)
        }
        try require(grant, allows: .bodyRead, accountID: message.accountID, emailID: message.emailID)
        guard grantAllows(message, grant: grant) else {
            try deny(grant: grant, accountID: message.accountID, emailID: message.emailID, kind: "bodyRead")
        }
        let data = try messageData(message)
        let parsed = MIMEParser.parse(data: data)
        let body = parsed.textBody ?? parsed.htmlBody.map(EmailSyncEngine.stripHTML) ?? ""
        try audit(
            grant: grant,
            accountID: message.accountID,
            emailID: message.emailID,
            kind: "bodyRead",
            details: "bytes=\(data.count)"
        )
        return MailMessageForAgent(
            messageID: message.emailID,
            accountID: message.accountID,
            mailbox: message.mailbox,
            date: message.receivedAt,
            subject: message.subject,
            sender: message.sender,
            untrustedSourceMaterial: Self.wrapUntrusted(
                kind: "email",
                id: message.emailID,
                text: body
            )
        )
    }

    public func getAttachment(attachmentID: String, grant: MailAccessGrant) throws -> MailAttachmentForAgent {
        guard let attachment = try emailStore.emailAttachment(id: attachmentID) else {
            throw MailAgentSourceError.attachmentNotFound(attachmentID)
        }
        guard let message = try emailStore.emailMessage(id: attachment.emailID) else {
            throw MailAgentSourceError.messageNotFound(attachment.emailID)
        }
        try require(grant, allows: .attachmentRead, accountID: message.accountID, emailID: message.emailID)
        guard grantAllows(message, grant: grant) else {
            try deny(grant: grant, accountID: message.accountID, emailID: message.emailID, kind: "attachmentRead")
        }
        guard let agent = TargetApp(rawValue: grant.agentID),
              try emailStore.isEmailShared(emailID: message.emailID, agent: agent),
              try emailStore.isEmailAttachmentShared(attachmentID: attachment.attachmentID, agent: agent) else {
            try deny(grant: grant, accountID: message.accountID, emailID: message.emailID, kind: "attachmentRead")
        }
        let data = try attachmentData(attachment, message: message)
        try audit(
            grant: grant,
            accountID: message.accountID,
            emailID: message.emailID,
            kind: "attachmentRead",
            details: "attachment=\(attachment.attachmentID); bytes=\(data.count)"
        )
        return MailAttachmentForAgent(
            attachmentID: attachment.attachmentID,
            messageID: message.emailID,
            filename: attachment.filename,
            mimeType: attachment.mimeType,
            data: data,
            untrustedText: Self.textIfSafe(data: data, mimeType: attachment.mimeType).map {
                Self.wrapUntrusted(kind: "email-attachment", id: attachment.attachmentID, text: $0)
            }
        )
    }

    public func exportMail(_ request: MailExportRequest, grant: MailAccessGrant) throws -> MailExportResult {
        try require(grant, allows: .export, accountID: nil, emailID: nil)
        try validateExportScope(request.scope, grant: grant)
        let result = try exporter.export(request)
        try audit(
            grant: grant,
            accountID: nil,
            emailID: nil,
            kind: "export",
            details: "messages=\(result.messageCount); attachments=\(result.attachmentCount)"
        )
        return result
    }

    private enum Permission {
        case search
        case bodyRead
        case attachmentRead
        case export
    }

    private func require(
        _ grant: MailAccessGrant,
        allows permission: Permission,
        accountID: String?,
        emailID: String?
    ) throws {
        if let expiresAt = grant.expiresAt, expiresAt < Date() {
            try audit(grant: grant, accountID: accountID, emailID: emailID, kind: "policyDenied", details: "expired")
            throw MailAgentSourceError.grantExpired
        }
        let allowed: Bool
        let kind: String
        switch permission {
        case .search:
            allowed = grant.allowSearch
            kind = "search"
        case .bodyRead:
            allowed = grant.allowBodyRead
            kind = "bodyRead"
        case .attachmentRead:
            allowed = grant.allowAttachmentRead
            kind = "attachmentRead"
        case .export:
            allowed = grant.allowExport
            kind = "export"
        }
        guard allowed else {
            try deny(grant: grant, accountID: accountID, emailID: emailID, kind: kind)
        }
    }

    private func deny(
        grant: MailAccessGrant,
        accountID: String?,
        emailID: String?,
        kind: String
    ) throws -> Never {
        try audit(grant: grant, accountID: accountID, emailID: emailID, kind: "policyDenied", details: kind)
        throw MailAgentSourceError.accessDenied(kind)
    }

    private func grantAllows(_ message: EmailMessageRecord, grant: MailAccessGrant) -> Bool {
        if !grant.accountIDs.isEmpty, !grant.accountIDs.contains(message.accountID) {
            return false
        }
        if !grant.mailboxIDs.isEmpty, !grant.mailboxIDs.contains(message.mailbox) {
            return false
        }
        if let messageIDs = grant.messageIDs, !messageIDs.contains(message.emailID) {
            return false
        }
        return true
    }

    private func validateExportScope(_ scope: MailExportScope, grant: MailAccessGrant) throws {
        switch scope {
        case .messages(let ids):
            for id in ids {
                guard let message = try emailStore.emailMessage(id: id) else {
                    throw MailAgentSourceError.messageNotFound(id)
                }
                guard grantAllows(message, grant: grant) else {
                    try deny(grant: grant, accountID: message.accountID, emailID: message.emailID, kind: "export")
                }
            }
        case .mailbox(let mailbox, _):
            if !grant.mailboxIDs.isEmpty, !grant.mailboxIDs.contains(mailbox) {
                try deny(grant: grant, accountID: nil, emailID: nil, kind: "export")
            }
        case .account(let accountID, _):
            if !grant.accountIDs.isEmpty, !grant.accountIDs.contains(accountID) {
                try deny(grant: grant, accountID: accountID, emailID: nil, kind: "export")
            }
        }
    }

    private func messageData(_ message: EmailMessageRecord) throws -> Data {
        if let cid = message.canonicalBlobCID {
            return try archiveStore.readObject(contentID: cid, accountID: message.accountID)
        }
        if let path = message.emlPath,
           let data = EmailSyncEngine.readStoredMessage(at: path) {
            return data
        }
        throw MailAgentSourceError.storedContentUnavailable(message.emailID)
    }

    private func attachmentData(_ attachment: EmailAttachmentRecord, message: EmailMessageRecord) throws -> Data {
        if let cid = attachment.attachmentBlobCID {
            return try archiveStore.readObject(contentID: cid, accountID: message.accountID)
        }
        let data = try messageData(message)
        let parsed = MIMEParser.parse(data: data)
        if let matched = parsed.attachments.first(where: { SHA256Hash.hex($0.data) == attachment.contentHash }) {
            return matched.data
        }
        throw MailAgentSourceError.storedContentUnavailable(attachment.attachmentID)
    }

    private func audit(
        grant: MailAccessGrant,
        accountID: String?,
        emailID: String?,
        kind: String,
        details: String
    ) throws {
        try emailStore.recordMailAccessAuditEvent(
            accountID: accountID,
            emailID: emailID,
            agentID: grant.agentID,
            sessionID: grant.sessionID,
            accessKind: kind,
            policyGrantID: grant.id.uuidString,
            detailsRedacted: details
        )
    }

    private static func wrapUntrusted(kind: String, id: String, text: String) -> String {
        """
        <untrusted-mail-source kind="\(kind)" id="\(id)">
        \(text)
        </untrusted-mail-source>
        """
    }

    private static func textIfSafe(data: Data, mimeType: String) -> String? {
        let lower = mimeType.lowercased()
        guard lower.hasPrefix("text/") || lower == "application/json" || lower.hasSuffix("+json") else {
            return nil
        }
        let capped = Data(data.prefix(1_048_576))
        return String(data: capped, encoding: .utf8) ?? String(data: capped, encoding: .isoLatin1)
    }
}

private enum SHA256Hash {
    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
