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

    /// UIDs per envelope FETCH command. Envelope-only responses are small, so
    /// large batches trade negligible memory for far fewer round trips.
    private static let envelopeBatchSize = 200

    /// Messages per batched body FETCH and per SQLite write transaction.
    /// Bounds staging-disk usage to roughly two chunks of raw mail at a time
    /// (the chunk being processed plus the one prefetching behind it).
    private static let bodyChunkSize = 24

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
            let repairs = try emailStore.repairStoredMailMetadata(accountID: accountID, limit: 5_000)
            if repairs.dateRepairs > 0 {
                try? emailStore.recordMailSyncEvent(
                    accountID: accountID,
                    kind: .dateRepair,
                    status: "Date metadata repaired",
                    detailRedacted: "\(repairs.dateRepairs) message date(s) repaired"
                )
            }
            if repairs.headerRepairs > 0 {
                try? emailStore.recordMailSyncEvent(
                    accountID: accountID,
                    kind: .headerRepair,
                    status: "Header metadata repaired",
                    detailRedacted: "\(repairs.headerRepairs) message header(s) repaired"
                )
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
                    let retryable = Self.invalidatesConnection(error)
                    recordMailboxError(
                        accountID: accountID,
                        mailboxName: mailboxName,
                        errorMessage: message,
                        retryable: retryable
                    )
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

    private func recordMailboxError(
        accountID: String,
        mailboxName: String,
        errorMessage: String,
        retryable: Bool
    ) {
        do {
            let state = try emailStore.syncState(accountID: accountID, mailbox: mailboxName)
            let count = try emailStore.messageCountInMailbox(accountID: accountID, mailbox: mailboxName)
            let now = ISO8601DateFormatter.shared.string(from: Date())
            try emailStore.updateSyncState(
                accountID: accountID,
                mailbox: mailboxName,
                uidValidity: state?.uidValidity,
                lastSyncUID: state?.lastSyncUID ?? 0,
                messageCount: count,
                syncStatus: retryable ? .idle : .error,
                errorMessage: retryable ? nil : String(errorMessage.prefix(512)),
                oldestSyncedUID: state?.oldestSyncedUID,
                serverMessageCount: state?.serverMessageCount,
                backfillCompleted: state?.backfillCompleted,
                lastSuccessfulSyncAt: state?.lastSuccessfulSyncAt,
                lastErrorAt: now
            )
            try emailStore.recordMailSyncEvent(
                accountID: accountID,
                mailboxName: mailboxName,
                kind: .mailboxError,
                status: retryable ? "Connection interrupted" : "Mailbox error",
                errorCode: retryable ? "connection_interrupted" : "mailbox_error",
                detailRedacted: errorMessage,
                needsAttention: !retryable
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
        try? emailStore.recordMailSyncEvent(
            accountID: accountID,
            mailboxName: mailboxName,
            kind: .mailboxStarted,
            status: "Started",
            detailRedacted: "\(selectResult.exists) message(s) reported by server"
        )

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
                messageCount: try emailStore.messageCountInMailbox(accountID: accountID, mailbox: mailboxName),
                syncStatus: .idle,
                oldestSyncedUID: uidPlan.knownSavedUIDs.min(),
                serverMessageCount: selectResult.exists,
                backfillCompleted: state?.backfillCompleted ?? !uidPlan.hasMoreHistory,
                lastSuccessfulSyncAt: ISO8601DateFormatter.shared.string(from: Date())
            )
            try? emailStore.recordMailSyncEvent(
                accountID: accountID,
                mailboxName: mailboxName,
                kind: .mailboxCompleted,
                status: "Completed",
                detailRedacted: "No new messages"
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

        // Stage 0: envelope metadata for every selected UID, in large batches.
        // Envelope responses are small, so big batches cost little memory and
        // cut round trips.
        var envelopeItems: [IMAPParser.FetchResult] = []
        envelopeItems.reserveCapacity(uidPlan.selectedUIDs.count)
        for batch in stride(from: 0, to: uidPlan.selectedUIDs.count, by: Self.envelopeBatchSize) {
            let end = min(batch + Self.envelopeBatchSize, uidPlan.selectedUIDs.count)
            let batchUIDs = Array(uidPlan.selectedUIDs[batch..<end])
            envelopeItems.append(
                contentsOf: try await session.fetch(uids: batchUIDs, items: "UID FLAGS ENVELOPE RFC822.SIZE")
            )
        }

        // Body pipeline: each chunk downloads in one batched UID FETCH, and the
        // next chunk downloads on the connection actor while this actor parses,
        // encrypts, and lands the current chunk in SQLite.
        let chunks: [[IMAPParser.FetchResult]] = stride(from: 0, to: envelopeItems.count, by: Self.bodyChunkSize).map {
            Array(envelopeItems[$0..<min($0 + Self.bodyChunkSize, envelopeItems.count)])
        }
        let stagingDirectory = Self.syncStagingDirectory(accountID: accountID)
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }

        var pendingBodies: [IMAPConnection.FetchedBodyFile] = []
        if let firstChunk = chunks.first {
            pendingBodies = try await session.fetchBodies(
                uids: firstChunk.map(\.uid),
                stagingDirectory: stagingDirectory
            )
        }

        for index in chunks.indices {
            let bodiesByUID = Dictionary(
                pendingBodies.map { ($0.uid, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            if index + 1 < chunks.count {
                let nextUIDs = chunks[index + 1].map(\.uid)
                async let prefetched = session.fetchBodies(
                    uids: nextUIDs,
                    stagingDirectory: stagingDirectory
                )
                let outcome = try processChunk(
                    chunks[index],
                    bodies: bodiesByUID,
                    accountID: accountID,
                    mailboxName: mailboxName,
                    isJunkMailbox: isJunkMailbox,
                    archiveStore: archiveStore,
                    shouldPersistPlaintextFTS: shouldPersistPlaintextFTS
                )
                newCount += outcome.newCount
                savedUIDs.formUnion(outcome.savedUIDs)
                pendingBodies = try await prefetched
            } else {
                let outcome = try processChunk(
                    chunks[index],
                    bodies: bodiesByUID,
                    accountID: accountID,
                    mailboxName: mailboxName,
                    isJunkMailbox: isJunkMailbox,
                    archiveStore: archiveStore,
                    shouldPersistPlaintextFTS: shouldPersistPlaintextFTS
                )
                newCount += outcome.newCount
                savedUIDs.formUnion(outcome.savedUIDs)
                pendingBodies = []
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
        let storedUIDsAfterSync = try emailStore.storedUIDs(accountID: accountID, mailbox: mailboxName)
        let actualCount = try emailStore.messageCountInMailbox(accountID: accountID, mailbox: mailboxName)
        let backfillCompleted: Bool
        if mode.isHistoricalBackfill {
            backfillCompleted = !uidPlan.hasMoreHistory
        } else {
            backfillCompleted = state?.backfillCompleted ?? !uidPlan.hasMoreHistory
        }
        try emailStore.updateSyncState(
            accountID: accountID, mailbox: mailboxName,
            uidValidity: selectResult.uidValidity,
            lastSyncUID: lastUID,
            messageCount: actualCount,
            syncStatus: .idle,
            oldestSyncedUID: storedUIDsAfterSync.min(),
            serverMessageCount: selectResult.exists,
            backfillCompleted: backfillCompleted,
            lastSuccessfulSyncAt: ISO8601DateFormatter.shared.string(from: Date())
        )
        try? emailStore.recordMailSyncEvent(
            accountID: accountID,
            mailboxName: mailboxName,
            kind: .mailboxCompleted,
            status: backfillCompleted ? "Completed" : "Recent mail ready",
            detailRedacted: "\(newCount) new message(s); \(actualCount) stored"
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

    /// Per-sync staging directory for body literals streamed off the socket.
    /// Unique per call so concurrent syncs of different accounts never share
    /// staging state; the whole directory is removed when the mailbox finishes.
    private static func syncStagingDirectory(accountID: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ManifoldMailSync", isDirectory: true)
            .appendingPathComponent(accountID, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: - Chunk Processing

    private struct ChunkOutcome {
        var newCount = 0
        var savedUIDs: Set<UInt32> = []
    }

    /// Process one chunk of fetched messages: encrypt bodies and attachments
    /// into the archive, parse MIME, then land every metadata row for the
    /// chunk in a single SQLite transaction. Private token indexing follows
    /// the commit because it manages its own transaction (BEGIN does not nest).
    ///
    /// Deliberately synchronous: no suspension points means the actor cannot
    /// interleave other work mid-chunk, and the prefetch of the next chunk on
    /// the connection actor is the only concurrent work for this account.
    private func processChunk(
        _ items: [IMAPParser.FetchResult],
        bodies: [UInt32: IMAPConnection.FetchedBodyFile],
        accountID: String,
        mailboxName: String,
        isJunkMailbox: Bool,
        archiveStore: MailArchiveStore,
        shouldPersistPlaintextFTS: Bool
    ) throws -> ChunkOutcome {
        var outcome = ChunkOutcome()
        var metadataWrites: [() throws -> Void] = []
        var indexWrites: [() throws -> Void] = []
        var events: [EmailSyncEvent] = []
        let store = emailStore

        for item in items {
            let uid = item.uid
            guard let bodyFile = bodies[uid] else {
                logger.warning("No body returned for UID \(uid); server may have expunged it")
                continue
            }

            // Encrypt the raw message into archive v2. The archive path is not
            // a readable EML; explicit export is the readable path.
            let archivedMessage: MailArchiveStoredObject
            let bodyData: Data
            do {
                archivedMessage = try archiveStore.storeMessage(accountID: accountID, plaintextFileURL: bodyFile.fileURL)
                bodyData = try Data(contentsOf: bodyFile.fileURL, options: [.mappedIfSafe])
                try? FileManager.default.removeItem(at: bodyFile.fileURL)
            } catch {
                try? FileManager.default.removeItem(at: bodyFile.fileURL)
                logger.warning("Failed to archive body for UID \(uid): \(error.localizedDescription)")
                continue
            }

            // Parse the message for preview, content type, and attachment
            // metadata. Body text is only persisted for the explicit plaintext
            // FTS mode.
            let parsed = MIMEParser.parse(data: bodyData)
            let preview = parsed.textBody.map {
                String($0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).prefix(200))
            }
            let contentType = parsed.htmlBody != nil ? "text/html" : "text/plain"
            let attachmentCount = parsed.attachments.count
            let rawBody = parsed.textBody ?? parsed.htmlBody.map { Self.stripHTML($0) }
            let bodyText = shouldPersistPlaintextFTS ? rawBody.map { String($0.prefix(51_200)) } : nil

            // Map envelope fields
            let envelope = item.envelope
            let messageID = envelope?.messageID.nilIfEmpty
            let emailID = messageID ?? "imap-\(accountID)-\(mailboxName)-\(uid)"
            let decodedSender = MailHeaderDecoder.decode(envelope?.from)
            let decodedRecipients = MailHeaderDecoder.decode(envelope?.to)
            let decodedCC = MailHeaderDecoder.decode(envelope?.cc)
            let decodedSubject = MailHeaderDecoder.decode(envelope?.subject).nilIfEmpty ?? "(no subject)"
            let normalizedDate = MailDateNormalizer.normalize(
                envelope?.date ?? ISO8601DateFormatter.shared.string(from: Date())
            )
            let senderEmail = Self.extractEmail(from: decodedSender)
            let senderDomain = senderEmail.flatMap { Self.extractDomain(from: $0) }
            let isRead = item.flags.contains("\\Seen")
            let isFlagged = item.flags.contains("\\Flagged")
            let rfc822Size = item.rfc822Size

            // Encrypt attachments into the archive now (file I/O and crypto
            // stay outside the metadata transaction below).
            var attachmentIDs: [String] = []
            var attachmentIndexText: [String] = []
            var archivedAttachments: [(id: String, part: MIMEParser.AttachmentPart, object: MailArchiveStoredObject, contentHash: String)] = []
            for (attachmentIndex, attachment) in parsed.attachments.enumerated() {
                let contentHash = SHA256.hash(data: attachment.data).hexString
                let attachmentID = "\(emailID)-att-\(attachmentIndex)-\(contentHash.prefix(12))"
                let archivedAttachment = try archiveStore.store(
                    accountID: accountID,
                    kind: .attachment,
                    plaintext: attachment.data
                )
                archivedAttachments.append((attachmentID, attachment, archivedAttachment, contentHash))
                attachmentIDs.append(attachmentID)
                attachmentIndexText.append(Self.indexableAttachmentText(attachment))
            }

            metadataWrites.append {
                try store.upsertEmailMessage(
                    emailID: emailID,
                    accountID: accountID,
                    mailbox: mailboxName,
                    sender: decodedSender,
                    senderEmail: senderEmail,
                    senderDomain: senderDomain,
                    recipients: decodedRecipients,
                    cc: decodedCC,
                    subject: decodedSubject,
                    receivedAt: normalizedDate.normalized,
                    receivedAtRaw: normalizedDate.raw,
                    receivedAtIsTrusted: normalizedDate.isTrusted,
                    emlPath: archivedMessage.manifestURL.path,
                    sizeBytes: rfc822Size,
                    preview: preview,
                    contentType: contentType,
                    isRead: isRead,
                    isFlagged: isFlagged,
                    inReplyTo: envelope?.inReplyTo.nilIfEmpty,
                    messageIDHeader: messageID,
                    attachmentCount: attachmentCount,
                    canonicalBlobCID: archivedMessage.contentID
                )
                try store.recordMailBlob(archivedMessage)
                try store.upsertMailboxMembership(
                    accountID: accountID,
                    mailbox: mailboxName,
                    imapUID: uid,
                    emailID: emailID
                )
                if let body = bodyText {
                    try store.updateBodyText(emailID: emailID, bodyText: body)
                }
                try store.deleteEmailAttachments(emailID: emailID)
                for archived in archivedAttachments {
                    try store.recordMailBlob(archived.object)
                    try store.upsertEmailAttachment(
                        attachmentID: archived.id,
                        emailID: emailID,
                        filename: archived.part.filename,
                        mimeType: archived.part.mimeType,
                        sizeBytes: archived.part.size,
                        contentHash: archived.contentHash,
                        contentID: archived.part.contentID,
                        attachmentBlobCID: archived.object.contentID
                    )
                }
                if isJunkMailbox {
                    try store.updateJunkState(emailID: emailID, isJunk: true)
                }
            }

            indexWrites.append {
                try store.replacePrivateTokenIndex(
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
            }

            events.append(
                EmailSyncEvent(
                    emailID: emailID,
                    accountID: accountID,
                    mailbox: mailboxName,
                    attachmentIDs: attachmentIDs,
                    reason: "sync"
                )
            )
            outcome.newCount += 1
            outcome.savedUIDs.insert(uid)
        }

        // One transaction for the chunk's plain metadata statements, then the
        // self-transactional private token index, then events once durable.
        try emailStore.performBatch {
            for write in metadataWrites { try write() }
        }
        for write in indexWrites { try write() }
        for event in events { emit(event) }

        return outcome
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
        MailDateNormalizer.normalize(raw).normalized
    }
}
