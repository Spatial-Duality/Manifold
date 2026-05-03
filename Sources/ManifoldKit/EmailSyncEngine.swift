// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CryptoKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "email-sync")

public struct EmailSyncEvent: Sendable, Codable, Hashable {
    public let emailID: String
    public let accountID: String
    public let mailbox: String
    public let attachmentIDs: [String]
    public let reason: String

    public init(
        emailID: String,
        accountID: String,
        mailbox: String,
        attachmentIDs: [String],
        reason: String
    ) {
        self.emailID = emailID
        self.accountID = accountID
        self.mailbox = mailbox
        self.attachmentIDs = attachmentIDs
        self.reason = reason
    }
}

/// Background sync engine for email backup.
/// Connects to IMAP, fetches messages, and saves canonical messages as
/// encrypted archive-v2 blobs.
public actor EmailSyncEngine {
    private let emailStore: EmailStore
    private var connections: [String: IMAPConnection] = [:]
    private var eventContinuations: [UUID: AsyncStream<EmailSyncEvent>.Continuation] = [:]

    public init(emailStore: EmailStore) {
        self.emailStore = emailStore
    }

    /// Disconnect cached network state for an account.
    public func unregister(accountID: String) async {
        if let conn = connections.removeValue(forKey: accountID) {
            await conn.disconnect()
        }
    }

    /// Execute a durable sync job using the job type as the source of truth.
    public func syncJob(_ job: MailSyncJobRecord) async -> SyncResult {
        let mode: MailSyncExecutionMode
        switch job.jobType {
        case .initial, .recentPass:
            mode = .recentPass(limitPerMailbox: 1_000)
        case .historicalBackfill:
            mode = .historicalBackfill(batchLimitPerMailbox: 1_000)
        case .incremental, .reconcile:
            mode = .incremental
        }

        return await syncAccount(
            accountID: job.accountID,
            mode: mode,
            mailboxFilter: job.mailboxName
        )
    }

    public func events() -> AsyncStream<EmailSyncEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            Task { self.addEventContinuation(continuation, id: id) }
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeEventContinuation(id) }
            }
        }
    }

    /// Disconnect all cached IMAP connections.
    public func stop() async {
        for (_, conn) in connections { await conn.disconnect() }
        connections.removeAll()
    }

    private func emit(_ event: EmailSyncEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func addEventContinuation(
        _ continuation: AsyncStream<EmailSyncEvent>.Continuation,
        id: UUID
    ) {
        eventContinuations[id] = continuation
    }

    private func removeEventContinuation(_ id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }

    // MARK: - Core Sync

    private func syncAccount(
        accountID: String,
        mode: MailSyncExecutionMode,
        mailboxFilter: String? = nil
    ) async -> SyncResult {
        let start = Date()
        var totalNew = 0
        var errors: [String] = []
        var mailboxResults: [MailboxSyncResult] = []

        do {
            let account = try emailStore.emailAccount(id: accountID)
            guard let account, let server = account.server, let port = account.port else {
                return SyncResult(accountID: accountID, errors: ["Account not configured"])
            }
            let provider = EmailProvider(rawValue: account.providerType)

            // Get or create connection
            var conn = try await ensureConnection(accountID: accountID, account: account, server: server, port: port)

            // Discover all mailboxes and persist metadata
            let listEntries = try await conn.listDetailed()
            for entry in listEntries {
                // Derive parent path from delimiter
                let parentPath: String?
                if let delim = entry.delimiter, let lastDelim = entry.name.lastIndex(of: Character(delim)) {
                    parentPath = String(entry.name[..<lastDelim])
                } else {
                    parentPath = nil
                }
                let isSelectable = !entry.flags.contains("\\Noselect") && !entry.flags.contains("\\NonExistent")
                try emailStore.upsertIMAPMailbox(
                    accountID: accountID,
                    name: entry.name,
                    delimiter: entry.delimiter,
                    flags: entry.flags,
                    isSelectable: isSelectable,
                    parentPath: parentPath
                )
            }

            // Load persisted mailbox records to detect junk folders
            let imapMailboxes = try emailStore.imapMailboxes(accountID: accountID)
            let junkMailboxNames = Set(
                imapMailboxes.filter { $0.folderType == .junk }.map(\.mailboxName)
            )
            var session = ReadOnlyIMAPSession(connection: conn)

            // Sync all selectable mailboxes. Inbox and sent mail run first so
            // a slow trash/junk body cannot starve the mail users expect to see.
            let toSync = listEntries.filter { entry in
                let isSelectable = !entry.flags.contains("\\Noselect") && !entry.flags.contains("\\NonExistent")
                let isRedundant = Self.isRedundantMailbox(entry, provider: provider)
                let matchesFilter = mailboxFilter == nil || entry.name == mailboxFilter
                return isSelectable && !isRedundant && matchesFilter
            }.sorted { lhs, rhs in
                let lhsKey = Self.mailboxSortKey(lhs)
                let rhsKey = Self.mailboxSortKey(rhs)
                if lhsKey.priority != rhsKey.priority {
                    return lhsKey.priority < rhsKey.priority
                }
                return lhsKey.name.localizedStandardCompare(rhsKey.name) == .orderedAscending
            }

            for (index, entry) in toSync.enumerated() {
                let mailboxName = entry.name
                do {
                    let result = try await syncMailbox(
                        accountID: accountID,
                        session: session,
                        mailboxName: mailboxName,
                        isJunkMailbox: junkMailboxNames.contains(mailboxName),
                        mode: mode
                    )
                    totalNew += result.newMessages
                    mailboxResults.append(result)
                } catch {
                    let message = error.localizedDescription
                    errors.append("\(mailboxName): \(message)")
                    recordMailboxError(accountID: accountID, mailboxName: mailboxName, errorMessage: message)
                    await conn.disconnect()
                    connections.removeValue(forKey: accountID)

                    guard index < toSync.count - 1 else { continue }
                    do {
                        conn = try await ensureConnection(accountID: accountID, account: account, server: server, port: port)
                        session = ReadOnlyIMAPSession(connection: conn)
                    } catch {
                        errors.append("Reconnect after \(mailboxName): \(error.localizedDescription)")
                        break
                    }
                }
            }

            // SEARCH ALL reconciliation: detect server-side deletions
            if !mode.isRecentPass && !mode.isHistoricalBackfill {
                for mailboxName in toSync.map(\.name) {
                    do {
                        try await reconcileMailbox(
                            accountID: accountID,
                            session: session,
                            mailboxName: mailboxName
                        )
                    } catch {
                        // Non-fatal: reconciliation failure shouldn't block sync
                        logger.warning("Reconciliation failed for \(mailboxName): \(error.localizedDescription)")
                    }
                }

                // Confirm deletions for messages missing from ALL mailboxes across two cycles
                let confirmed = try emailStore.confirmServerDeletions()
                if confirmed > 0 {
                    logger.info("Confirmed \(confirmed) server-side deletions for \(accountID)")
                }
            }
        } catch {
            errors.append(error.localizedDescription)
            // Connection likely broken, clear it
            if let conn = connections.removeValue(forKey: accountID) {
                await conn.disconnect()
            }
        }

        return SyncResult(
            accountID: accountID,
            newMessages: totalNew,
            errors: errors,
            duration: Date().timeIntervalSince(start),
            mailboxResults: mailboxResults
        )
    }

    private func recordMailboxError(accountID: String, mailboxName: String, errorMessage: String) {
        do {
            let state = try emailStore.syncState(accountID: accountID, mailbox: mailboxName)
            let count = try emailStore.messageCountInMailbox(accountID: accountID, mailbox: mailboxName)
            try emailStore.updateSyncState(
                accountID: accountID,
                mailbox: mailboxName,
                uidValidity: state?.uidValidity,
                lastSyncUID: state?.lastSyncUID ?? 0,
                messageCount: max(state?.messageCount ?? 0, count),
                syncStatus: .error,
                errorMessage: String(errorMessage.prefix(512))
            )
        } catch {
            logger.warning("Failed to record mailbox sync error for \(mailboxName): \(error.localizedDescription)")
        }
    }

    nonisolated static func isRedundantMailbox(
        _ entry: IMAPConnection.ListEntry,
        provider: EmailProvider?
    ) -> Bool {
        guard provider == .gmail else { return false }
        let lowerName = entry.name.lowercased()
        let flags = Set(entry.flags.map { $0.lowercased() })
        if flags.contains("\\all") || flags.contains("\\important") || flags.contains("\\flagged") {
            return true
        }
        return lowerName == "[gmail]/all mail"
            || lowerName == "[gmail]/important"
            || lowerName == "[gmail]/starred"
            || lowerName == "[google mail]/all mail"
            || lowerName == "[google mail]/important"
            || lowerName == "[google mail]/starred"
    }

    nonisolated static func mailboxSortKey(
        _ entry: IMAPConnection.ListEntry
    ) -> (priority: Int, name: String) {
        let lowerName = entry.name.lowercased()
        let flags = Set(entry.flags.map { $0.lowercased() })
        let priority: Int
        if lowerName == "inbox" {
            priority = 0
        } else if flags.contains("\\sent") || lowerName.contains("sent") {
            priority = 10
        } else if lowerName.contains("archive") {
            priority = 20
        } else if flags.contains("\\drafts") || lowerName.contains("draft") {
            priority = 80
        } else if flags.contains("\\junk")
            || flags.contains("\\trash")
            || lowerName.contains("junk")
            || lowerName.contains("spam")
            || lowerName.contains("trash")
            || lowerName.contains("deleted") {
            priority = 90
        } else if lowerName.contains("notes") {
            priority = 95
        } else {
            priority = 30
        }
        return (priority, entry.name)
    }

    nonisolated static func invalidatesConnection(_ error: Error) -> Bool {
        guard let imapError = error as? IMAPError else { return false }
        switch imapError {
        case .connectionFailed, .timeout, .disconnected:
            return true
        case .authenticationFailed, .mailboxNotFound, .unexpectedResponse, .serverError, .protocolError:
            return false
        }
    }

    private func syncMailbox(
        accountID: String,
        session: ReadOnlyIMAPSession,
        mailboxName: String,
        isJunkMailbox: Bool = false,
        mode: MailSyncExecutionMode
    ) async throws -> MailboxSyncResult {
        // Load sync state
        let state = try emailStore.syncState(accountID: accountID, mailbox: mailboxName)
        let previousLastUID = state?.lastSyncUID ?? 0
        var lastUID = previousLastUID
        let savedValidity = state?.uidValidity

        // EXAMINE mailbox so Manifold never opens a read-write IMAP session.
        let selectResult = try await session.examine(mailbox: mailboxName)

        // Check UIDVALIDITY — if changed, full resync
        if let saved = savedValidity, saved != selectResult.uidValidity {
            logger.warning("UIDVALIDITY changed for \(mailboxName), resetting")
            try emailStore.resetSyncState(accountID: accountID, mailbox: mailboxName)
            lastUID = 0
        }

        let uidPlan = try await syncUIDPlan(
            accountID: accountID,
            session: session,
            mailboxName: mailboxName,
            mode: mode,
            lastUID: lastUID
        )

        guard !uidPlan.selectedUIDs.isEmpty else {
            lastUID = Self.nextHighWatermark(
                previousLastUID: previousLastUID,
                searchedUIDs: uidPlan.searchedUIDs,
                savedUIDs: uidPlan.knownSavedUIDs,
                mode: mode,
                selectedUIDCount: 0,
                candidateUIDCount: uidPlan.candidateUIDCount
            )
            try emailStore.updateSyncState(
                accountID: accountID, mailbox: mailboxName,
                uidValidity: selectResult.uidValidity,
                lastSyncUID: lastUID,
                messageCount: state?.messageCount ?? selectResult.exists,
                syncStatus: .idle
            )
            return MailboxSyncResult(
                mailboxName: mailboxName,
                lastUID: lastUID,
                uidValidity: selectResult.uidValidity
            )
        }

        let archiveStore = try MailArchiveStore(rootURL: Self.mailArchiveRoot)
        let shouldPersistPlaintextFTS =
            (try? emailStore.emailAccount(id: accountID))?.indexPrivacyMode == MailIndexPrivacyMode.plaintextFTSWithDisclosure.rawValue

        var newCount = 0
        var savedUIDs = Set<UInt32>()

        // Fetch envelopes in batches of 50 for metadata
        for batch in stride(from: 0, to: uidPlan.selectedUIDs.count, by: 50) {
            let end = min(batch + 50, uidPlan.selectedUIDs.count)
            let batchUIDs = Array(uidPlan.selectedUIDs[batch..<end])

            let fetched = try await session.fetch(uids: batchUIDs, items: "UID FLAGS ENVELOPE RFC822.SIZE")

            for item in fetched {
                let uid = item.uid
                let archivedMessage: MailArchiveStoredObject
                let bodyData: Data
                let messageStagingURL = Self.messageLiteralStagingURL(accountID: accountID, uid: uid)

                // Fetch raw message body and save into archive v2. The archive
                // path is not a readable EML; explicit export is the readable path.
                do {
                    _ = try await session.fetchBody(uid: uid, toFileAt: messageStagingURL)
                    archivedMessage = try archiveStore.storeMessage(accountID: accountID, plaintextFileURL: messageStagingURL)
                    bodyData = try Data(contentsOf: messageStagingURL, options: [.mappedIfSafe])
                    try? FileManager.default.removeItem(at: messageStagingURL)
                } catch {
                    try? FileManager.default.removeItem(at: messageStagingURL)
                    logger.warning("Failed to fetch body for UID \(uid): \(error.localizedDescription)")
                    if Self.invalidatesConnection(error) {
                        throw error
                    }
                    continue
                }

                // Parse the in-memory message for preview, content type, and
                // attachment metadata. Body text is only persisted for the
                // explicit plaintext FTS mode.
                let preview: String?
                let contentType: String?
                let attachmentCount: Int
                let bodyText: String?
                let parsedEmail: MIMEParser.ParsedEmail
                let parsed = MIMEParser.parse(data: bodyData)
                parsedEmail = parsed
                preview = parsed.textBody.map {
                    String($0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).prefix(200))
                }
                contentType = parsed.htmlBody != nil ? "text/html" : "text/plain"
                attachmentCount = parsed.attachments.count
                let rawBody = parsed.textBody ?? parsed.htmlBody.map { Self.stripHTML($0) }
                bodyText = shouldPersistPlaintextFTS ? rawBody.map { String($0.prefix(51_200)) } : nil

                // Map envelope fields
                let envelope = item.envelope
                let messageID = envelope?.messageID.nilIfEmpty
                let emailID = messageID ?? "imap-\(accountID)-\(mailboxName)-\(uid)"

                // Normalize sender email and domain from envelope.from
                let senderEmail = Self.extractEmail(from: envelope?.from ?? "")
                let senderDomain = senderEmail.flatMap { Self.extractDomain(from: $0) }

                // Map IMAP flags to read/flagged state
                let isRead = item.flags.contains("\\Seen")
                let isFlagged = item.flags.contains("\\Flagged")

                try emailStore.upsertEmailMessage(
                    emailID: emailID,
                    accountID: accountID,
                    mailbox: mailboxName,
                    sender: envelope?.from ?? "",
                    senderEmail: senderEmail,
                    senderDomain: senderDomain,
                    recipients: envelope?.to ?? "",
                    cc: envelope?.cc ?? "",
                    subject: envelope?.subject ?? "(no subject)",
                    receivedAt: Self.normalizeDate(envelope?.date ?? ISO8601DateFormatter.shared.string(from: Date())),
                    emlPath: archivedMessage.manifestURL.path,
                    sizeBytes: item.rfc822Size,
                    preview: preview,
                    contentType: contentType,
                    isRead: isRead,
                    isFlagged: isFlagged,
                    inReplyTo: envelope?.inReplyTo.nilIfEmpty,
                    messageIDHeader: messageID,
                    attachmentCount: attachmentCount,
                    canonicalBlobCID: archivedMessage.contentID
                )
                try emailStore.recordMailBlob(archivedMessage)

                // Insert membership row (links this message to this mailbox)
                try emailStore.upsertMailboxMembership(
                    accountID: accountID,
                    mailbox: mailboxName,
                    imapUID: uid,
                    emailID: emailID
                )

                // Index body text in FTS5 for full-text search
                if let body = bodyText {
                    try emailStore.updateBodyText(emailID: emailID, bodyText: body)
                }

                var attachmentIDs: [String] = []
                var attachmentIndexText: [String] = []
                try emailStore.deleteEmailAttachments(emailID: emailID)
                for (index, attachment) in parsedEmail.attachments.enumerated() {
                    let contentHash = SHA256.hash(data: attachment.data).hexString
                    let attachmentID = "\(emailID)-att-\(index)-\(contentHash.prefix(12))"
                    let archivedAttachment = try archiveStore.store(
                        accountID: accountID,
                        kind: .attachment,
                        plaintext: attachment.data
                    )
                    try emailStore.recordMailBlob(archivedAttachment)
                    try emailStore.upsertEmailAttachment(
                        attachmentID: attachmentID,
                        emailID: emailID,
                        filename: attachment.filename,
                        mimeType: attachment.mimeType,
                        sizeBytes: attachment.size,
                        contentHash: contentHash,
                        contentID: attachment.contentID,
                        attachmentBlobCID: archivedAttachment.contentID
                    )
                    attachmentIDs.append(attachmentID)
                    attachmentIndexText.append(Self.indexableAttachmentText(attachment))
                }
                try emailStore.replacePrivateTokenIndex(
                    accountID: accountID,
                    emailID: emailID,
                    fields: [
                        .subject: envelope?.subject ?? "",
                        .sender: envelope?.from ?? "",
                        .recipients: [envelope?.to, envelope?.cc].compactMap { $0 }.joined(separator: " "),
                        .body: rawBody ?? "",
                        .attachment: attachmentIndexText.joined(separator: " "),
                    ]
                )

                // Tag messages in junk/spam folders
                if isJunkMailbox {
                    try emailStore.updateJunkState(emailID: emailID, isJunk: true)
                }

                emit(
                    EmailSyncEvent(
                        emailID: emailID,
                        accountID: accountID,
                        mailbox: mailboxName,
                        attachmentIDs: attachmentIDs,
                        reason: "sync"
                    )
                )

                newCount += 1
                savedUIDs.insert(uid)
            }
        }

        lastUID = Self.nextHighWatermark(
            previousLastUID: previousLastUID,
            searchedUIDs: uidPlan.searchedUIDs,
            savedUIDs: savedUIDs.union(uidPlan.knownSavedUIDs),
            mode: mode,
            selectedUIDCount: uidPlan.selectedUIDs.count,
            candidateUIDCount: uidPlan.candidateUIDCount
        )

        // Update sync state
        try emailStore.updateSyncState(
            accountID: accountID, mailbox: mailboxName,
            uidValidity: selectResult.uidValidity,
            lastSyncUID: lastUID,
            messageCount: (state?.messageCount ?? 0) + newCount,
            syncStatus: .idle
        )

        logger.info("Synced \(newCount) new messages from \(mailboxName)")
        return MailboxSyncResult(
            mailboxName: mailboxName, newMessages: newCount,
            lastUID: lastUID, uidValidity: selectResult.uidValidity,
            oldestFetchedUID: savedUIDs.min(),
            fetchedUIDCount: savedUIDs.count,
            hasMoreHistory: uidPlan.hasMoreHistory
        )
    }

    private struct MailboxUIDPlan: Sendable {
        let searchedUIDs: [UInt32]
        let selectedUIDs: [UInt32]
        let candidateUIDCount: Int
        let hasMoreHistory: Bool
        let knownSavedUIDs: Set<UInt32>
    }

    private func syncUIDPlan(
        accountID: String,
        session: ReadOnlyIMAPSession,
        mailboxName: String,
        mode: MailSyncExecutionMode,
        lastUID: UInt32
    ) async throws -> MailboxUIDPlan {
        switch mode {
        case .incremental:
            let criteria = lastUID > 0 ? "UID \(lastUID + 1):*" : "ALL"
            let uids = try await session.search(criteria: criteria)
            let storedUIDs = try emailStore.storedUIDs(accountID: accountID, mailbox: mailboxName)
            let searched = uids.filter { $0 > lastUID }.sorted(by: >)
            let candidates = searched.filter { !storedUIDs.contains($0) }
            return MailboxUIDPlan(
                searchedUIDs: searched,
                selectedUIDs: candidates,
                candidateUIDCount: candidates.count,
                hasMoreHistory: false,
                knownSavedUIDs: Set(storedUIDs.filter { $0 > lastUID })
            )

        case .recentPass(let limitPerMailbox):
            let criteria = lastUID > 0 ? "UID \(lastUID + 1):*" : "ALL"
            let uids = try await session.search(criteria: criteria)
            let storedUIDs = try emailStore.storedUIDs(accountID: accountID, mailbox: mailboxName)
            let searched = uids.filter { $0 > lastUID }.sorted(by: >)
            let candidates = searched.filter { !storedUIDs.contains($0) }
            let selected = Array(candidates.prefix(max(0, limitPerMailbox)))
            return MailboxUIDPlan(
                searchedUIDs: searched,
                selectedUIDs: selected,
                candidateUIDCount: candidates.count,
                hasMoreHistory: selected.count < candidates.count,
                knownSavedUIDs: Set(storedUIDs.filter { $0 > lastUID })
            )

        case .historicalBackfill(let batchLimitPerMailbox):
            let storedUIDs = try emailStore.storedUIDs(accountID: accountID, mailbox: mailboxName)
            guard let oldestStoredUID = storedUIDs.min(), oldestStoredUID > 1 else {
                return MailboxUIDPlan(
                    searchedUIDs: [],
                    selectedUIDs: [],
                    candidateUIDCount: 0,
                    hasMoreHistory: false,
                    knownSavedUIDs: storedUIDs
                )
            }

            let criteria = "UID 1:\(oldestStoredUID - 1)"
            let uids = try await session.search(criteria: criteria)
            let candidates = uids
                .filter { $0 < oldestStoredUID && !storedUIDs.contains($0) }
                .sorted(by: >)
            let selected = Array(candidates.prefix(max(0, batchLimitPerMailbox)))
            return MailboxUIDPlan(
                searchedUIDs: candidates,
                selectedUIDs: selected,
                candidateUIDCount: candidates.count,
                hasMoreHistory: selected.count < candidates.count,
                knownSavedUIDs: storedUIDs
            )
        }
    }

    private static func messageLiteralStagingURL(accountID: String, uid: UInt32) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ManifoldMailSync", isDirectory: true)
            .appendingPathComponent(accountID, isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString)-\(uid).rfc822")
    }

    // MARK: - EXPUNGE Detection (SEARCH ALL reconciliation)

    /// Compare server UIDs against stored UIDs to detect server-side deletions.
    /// Missing UIDs get a `missing_from` timestamp on their membership row.
    /// Confirmed deletion happens on the NEXT sync cycle (deferred marking).
    private func reconcileMailbox(
        accountID: String,
        session: ReadOnlyIMAPSession,
        mailboxName: String
    ) async throws {
        let selectResult = try await session.examine(mailbox: mailboxName)

        // Get all UIDs currently on the server
        let serverUIDs = Set(try await session.search(criteria: "ALL"))

        // Get all UIDs we have stored for this mailbox
        let storedUIDs = try emailStore.storedUIDs(accountID: accountID, mailbox: mailboxName)

        // UIDs we have but server doesn't = potentially deleted
        let missingUIDs = storedUIDs.subtracting(serverUIDs)

        // UIDs that reappeared (were marked missing but are back)
        let reappearedUIDs = serverUIDs.intersection(storedUIDs)

        if !missingUIDs.isEmpty {
            try emailStore.markMissingFromMailbox(
                accountID: accountID,
                mailbox: mailboxName,
                missingUIDs: missingUIDs
            )
            logger.info("\(missingUIDs.count) UIDs missing from \(mailboxName)")
        }

        // Clear missing_from for UIDs that reappeared
        if !reappearedUIDs.isEmpty {
            try emailStore.clearMissingFrom(
                accountID: accountID,
                mailbox: mailboxName,
                reappearedUIDs: reappearedUIDs
            )
        }

        _ = selectResult // suppress unused warning
    }

    nonisolated static func safeHighWatermark(
        previousLastUID: UInt32,
        searchedUIDs: [UInt32],
        savedUIDs: Set<UInt32>
    ) -> UInt32 {
        var highWatermark = previousLastUID
        for uid in searchedUIDs.sorted() where uid > previousLastUID {
            guard savedUIDs.contains(uid) else { break }
            highWatermark = uid
        }
        return highWatermark
    }

    nonisolated static func nextHighWatermark(
        previousLastUID: UInt32,
        searchedUIDs: [UInt32],
        savedUIDs: Set<UInt32>,
        mode: MailSyncExecutionMode,
        selectedUIDCount: Int,
        candidateUIDCount: Int
    ) -> UInt32 {
        guard !savedUIDs.isEmpty else { return previousLastUID }

        switch mode {
        case .historicalBackfill:
            return previousLastUID
        case .recentPass:
            // Recent pass intentionally skips older UIDs for later backfill.
            // The high-water mark tracks newest-mail incremental progress only;
            // historical jobs fill the lower UID range from stored membership.
            if selectedUIDCount >= candidateUIDCount {
                return safeHighWatermark(
                    previousLastUID: previousLastUID,
                    searchedUIDs: searchedUIDs,
                    savedUIDs: savedUIDs
                )
            }
            return max(previousLastUID, savedUIDs.max() ?? previousLastUID)
        case .incremental:
            if selectedUIDCount < candidateUIDCount {
                return max(previousLastUID, savedUIDs.max() ?? previousLastUID)
            }
            return safeHighWatermark(
                previousLastUID: previousLastUID,
                searchedUIDs: searchedUIDs,
                savedUIDs: savedUIDs
            )
        }
    }

    // MARK: - HTML Stripping

    /// Strip HTML tags for plaintext body extraction (fallback when no text/plain part).
    /// Uses pre-compiled static regexes + NSMutableString to avoid 7 intermediate String
    /// allocations per call. For a 50KB email, saves ~350KB of string scanning.
    nonisolated static func stripHTML(_ html: String) -> String {
        let mutable = NSMutableString(string: html)
        // Pre-compiled regexes applied in-place — no intermediate String allocations
        for (regex, template) in htmlStripPatterns {
            regex.replaceMatches(in: mutable, range: NSRange(location: 0, length: mutable.length), withTemplate: template)
        }
        // Entity decoding (simple string replace, no regex needed)
        let entityMap: [(NSString, NSString)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "),
        ]
        for (entity, replacement) in entityMap {
            mutable.replaceOccurrences(of: entity as String, with: replacement as String, range: NSRange(location: 0, length: mutable.length))
        }
        return (mutable as String).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func indexableAttachmentText(_ attachment: MIMEParser.AttachmentPart) -> String {
        var parts = [attachment.filename]
        let mimeType = attachment.mimeType.lowercased()
        let isTextLike = mimeType.hasPrefix("text/")
            || mimeType == "application/json"
            || mimeType == "application/xml"
            || mimeType == "application/csv"
            || mimeType.hasSuffix("+json")
            || mimeType.hasSuffix("+xml")

        if isTextLike {
            let capped = Data(attachment.data.prefix(1_048_576))
            if let text = String(data: capped, encoding: .utf8)
                ?? String(data: capped, encoding: .isoLatin1) {
                parts.append(text)
            }
        }
        return parts.joined(separator: " ")
    }

    /// Pre-compiled regex patterns for HTML stripping. Compiled once, reused for every email.
    private static let htmlStripPatterns: [(NSRegularExpression, String)] = {
        [
            // Remove script/style blocks entirely
            (compileRegex("<(script|style)[^>]*>[\\s\\S]*?</\\1>", options: .caseInsensitive), ""),
            // Replace block elements with newlines
            (compileRegex("<(br|p|div|h[1-6]|li|tr)[^>]*/?>", options: .caseInsensitive), "\n"),
            // Remove all remaining tags
            (compileRegex("<[^>]+>"), ""),
            // Collapse horizontal whitespace
            (compileRegex("[ \\t]+"), " "),
            // Collapse excessive newlines
            (compileRegex("\\n{3,}"), "\n\n"),
        ]
    }()

    private static func compileRegex(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            preconditionFailure("Invalid EmailSyncEngine regex pattern: \(pattern)")
        }
    }

    // MARK: - Cached Date Formatters

    private static let rfc2822Formatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
        ]
        return formats.map { fmt in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            return f
        }
    }()

    // MARK: - Connection Management

    private func ensureConnection(
        accountID: String,
        account: EmailAccountRecord,
        server: String,
        port: Int
    ) async throws -> IMAPConnection {
        // Check existing connection health with a NOOP
        if let existing = connections[accountID] {
            do {
                try await existing.noop()
                return existing
            } catch {
                logger.info("Stale connection for \(accountID), reconnecting")
                await existing.disconnect()
                connections.removeValue(forKey: accountID)
            }
        }

        let conn = IMAPConnection(host: server, port: UInt16(port))
        try await conn.connect()

        guard let username = account.username, !username.isEmpty else {
            await conn.disconnect()
            throw IMAPError.authenticationFailed("No username configured for this account")
        }

        if account.mailCredentialReference?.kind == .oauthTokenSet {
            try await authenticateWithOAuth2(conn: conn, accountID: accountID, username: username)
        } else {
            // Authenticate — fail fast if credentials are missing rather than
            // sending an empty LOGIN that the server will reject.
            guard let password = Self.storedCredential(for: account), !password.isEmpty else {
                await conn.disconnect()
                throw IMAPError.authenticationFailed("No stored credential — please re-enter your password in Settings -> Email Backup")
            }
            try await conn.login(username: username, password: password)
            try? emailStore.setEmailAccountAuthState(accountID: accountID, authState: .valid)
        }

        connections[accountID] = conn
        return conn
    }

    private func authenticateWithOAuth2(
        conn: IMAPConnection,
        accountID: String,
        username: String
    ) async throws {
        let oauthClient = MicrosoftOAuthClient(config: LocalAuthConfig.load())
        guard var tokenSet = try oauthClient.loadTokenSet(accountID: accountID) else {
            try? emailStore.setEmailAccountAuthState(accountID: accountID, authState: .needsReauthentication)
            throw IMAPError.authenticationFailed("Microsoft OAuth token is missing. Reconnect the account.")
        }

        if tokenSet.expires(within: 300) {
            tokenSet = try await refreshedMicrosoftToken(
                oauthClient: oauthClient,
                tokenSet: tokenSet,
                accountID: accountID
            )
        }

        do {
            try await conn.authenticateOAuth2(username: username, accessToken: tokenSet.accessToken)
            try? emailStore.setEmailAccountAuthState(accountID: accountID, authState: .valid)
        } catch {
            do {
                let refreshed = try await refreshedMicrosoftToken(
                    oauthClient: oauthClient,
                    tokenSet: tokenSet,
                    accountID: accountID
                )
                try await conn.authenticateOAuth2(username: username, accessToken: refreshed.accessToken)
                try? emailStore.setEmailAccountAuthState(accountID: accountID, authState: .valid)
            } catch {
                try? emailStore.setEmailAccountAuthState(accountID: accountID, authState: .needsReauthentication)
                throw IMAPError.authenticationFailed("Microsoft OAuth token could not be refreshed. Reconnect the account.")
            }
        }
    }

    private func refreshedMicrosoftToken(
        oauthClient: MicrosoftOAuthClient,
        tokenSet: MicrosoftOAuthTokenSet,
        accountID: String
    ) async throws -> MicrosoftOAuthTokenSet {
        do {
            let refreshed = try await oauthClient.refresh(tokenSet)
            try oauthClient.storeTokenSet(refreshed, accountID: accountID)
            return refreshed
        } catch {
            try? emailStore.setEmailAccountAuthState(accountID: accountID, authState: .needsReauthentication)
            throw error
        }
    }

    public nonisolated static func storedCredential(
        for account: EmailAccountRecord,
        secretStore: KeychainMailSecretStore = KeychainMailSecretStore()
    ) -> String? {
        if let reference = account.mailCredentialReference,
           let data = secretStore.retrieve(reference: reference),
           let secret = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !secret.isEmpty {
            return secret
        }

        return nil
    }

    // MARK: - Mail Storage Roots

    /// Legacy pre-v2 backup root. Fresh-start cleanup removes this directory;
    /// new sync writes only archive-v2 objects under `mailArchiveRoot`.
    public static var backupRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Manifold/EmailBackup")
    }

    /// Root directory for archive-v2 canonical mail blobs.
    public static var mailArchiveRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Manifold/MailArchive")
    }

    /// Reads archive-v2 message data. The legacy encrypted-EML branch remains
    /// only for tests and developer safety during the fresh-start transition.
    public static func readStoredMessage(at path: String) -> Data? {
        let url = URL(fileURLWithPath: path)
        if MailArchiveStore.isArchiveV2Path(url) {
            return try? MailArchiveStore.readArchivedObject(atManifestURL: url)
        }
        guard let stored = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        return try? ProtectedStorageCrypto.decrypt(stored)
    }

    // MARK: - Email Address Parsing

    /// Extract bare email address from "Display Name <user@domain.com>" format.
    nonisolated static func extractEmail(from sender: String) -> String? {
        let trimmed = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let ltIdx = trimmed.firstIndex(of: "<"),
           let gtIdx = trimmed.firstIndex(of: ">"),
           ltIdx < gtIdx {
            let email = trimmed[trimmed.index(after: ltIdx)..<gtIdx]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            return email.isEmpty ? nil : email
        }
        // No angle brackets — treat whole string as email if it contains @
        let lower = trimmed.lowercased()
        return lower.contains("@") ? lower : nil
    }

    /// Extract domain from an email address.
    nonisolated static func extractDomain(from email: String) -> String? {
        guard let atIdx = email.lastIndex(of: "@") else { return nil }
        let domain = email[email.index(after: atIdx)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return domain.isEmpty ? nil : domain
    }

    // MARK: - Date Normalization

    /// Normalize IMAP envelope dates (RFC 2822) to ISO 8601 for consistent sorting.
    /// IMAP dates come in formats like "05 Jan 2013 12:00:00 +0000" which sort
    /// incorrectly as strings. This converts them to "2013-01-05T12:00:00Z".
    nonisolated static func normalizeDate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        // Already ISO 8601?
        if trimmed.contains("T") && (trimmed.hasSuffix("Z") || trimmed.contains("+") || trimmed.contains("-")) {
            let iso = ISO8601DateFormatter.shared
            if iso.date(from: trimmed) != nil { return trimmed }
        }

        // Try RFC 2822 formats (cached formatters — DateFormatter creation is expensive)
        for formatter in Self.rfc2822Formatters {
            if let date = formatter.date(from: trimmed) {
                return ISO8601DateFormatter.shared.string(from: date)
            }
        }

        // Can't parse — return as-is (better than crashing)
        return trimmed
    }
}
