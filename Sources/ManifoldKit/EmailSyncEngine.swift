import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "email-sync")

/// Background sync engine for email backup.
/// Connects to IMAP, fetches messages, and saves them as .eml files.
public actor EmailSyncEngine {
    private let emailStore: EmailStore
    private var connections: [String: IMAPConnection] = [:]
    private var syncTasks: [String: Task<Void, Never>] = [:]
    private var backfillTask: Task<Void, Never>?
    private var isStopped = false

    /// Progress of FTS5 body text backfill (0.0 to 1.0). Observable from UI.
    public private(set) var backfillProgress: Double = 1.0
    public private(set) var isBackfilling = false

    public init(emailStore: EmailStore) {
        self.emailStore = emailStore
    }

    // MARK: - Account Registration

    /// Register an account for periodic sync.
    public func register(accountID: String) {
        syncTasks[accountID]?.cancel()
        isStopped = false

        let task = Task {
            await self.periodicSync(accountID: accountID)
        }
        syncTasks[accountID] = task
        logger.info("Registered account \(accountID) for sync")
    }

    /// Unregister an account and stop its sync.
    public func unregister(accountID: String) async {
        syncTasks[accountID]?.cancel()
        syncTasks.removeValue(forKey: accountID)
        if let conn = connections.removeValue(forKey: accountID) {
            await conn.disconnect()
        }
    }

    /// Trigger an immediate sync for one account.
    public func syncNow(accountID: String) async throws -> SyncResult {
        return await syncAccount(accountID: accountID)
    }

    // MARK: - FTS5 Body Text Backfill

    /// Start background backfill of body text for existing emails that lack it.
    /// Processes in batches, resumable across app launches.
    public func startBackfill() {
        guard backfillTask == nil else { return }
        backfillTask = Task {
            await self.runBackfill()
        }
    }

    private func runBackfill() async {
        isBackfilling = true
        defer { isBackfilling = false; backfillTask = nil }

        let totalCount = (try? await emailStore.emailMessageCount()) ?? 0
        let indexedCount = (try? await emailStore.bodyTextIndexedCount()) ?? 0
        guard totalCount > indexedCount else {
            backfillProgress = 1.0
            return
        }

        var processed = indexedCount
        backfillProgress = totalCount > 0 ? Double(processed) / Double(totalCount) : 1.0

        while !Task.isCancelled && !isStopped {
            let batch = (try? await emailStore.emailsNeedingBodyBackfill(limit: 100)) ?? []
            guard !batch.isEmpty else { break }

            for (emailID, emlPath) in batch {
                guard !Task.isCancelled else { return }

                guard let data = try? Data(contentsOf: URL(fileURLWithPath: emlPath)) else { continue }
                let parsed = MIMEParser.parse(data: data)
                let rawBody = parsed.textBody ?? parsed.htmlBody.map { Self.stripHTML($0) }
                guard let body = rawBody else { continue }
                let truncated = String(body.prefix(51_200))
                try? await emailStore.updateBodyText(emailID: emailID, bodyText: truncated)

                processed += 1
                backfillProgress = Double(processed) / Double(totalCount)
            }

            // Yield between batches to avoid starving sync
            try? await Task.sleep(for: .milliseconds(100))
        }

        backfillProgress = 1.0
        logger.info("FTS5 body text backfill complete")
    }

    /// Stop all background sync.
    public func stop() async {
        isStopped = true
        backfillTask?.cancel()
        backfillTask = nil
        for (_, task) in syncTasks { task.cancel() }
        syncTasks.removeAll()
        for (_, conn) in connections { await conn.disconnect() }
        connections.removeAll()
    }

    // MARK: - Periodic Sync Loop

    private func periodicSync(accountID: String) async {
        while !isStopped && !Task.isCancelled {
            guard let account = try? await emailStore.emailAccount(id: accountID) else {
                logger.warning("Account \(accountID) not found, stopping sync")
                break
            }
            guard account.syncEnabled else {
                try? await Task.sleep(for: .seconds(60))
                continue
            }

            let result = await syncAccount(accountID: accountID)
            if result.isSuccess {
                logger.info("Sync OK for \(accountID): \(result.newMessages) new")
            } else {
                logger.warning("Sync errors for \(accountID): \(result.errors.joined(separator: ", "))")
            }

            do {
                try await Task.sleep(for: .seconds(account.syncIntervalSeconds))
            } catch { break }
        }
    }

    // MARK: - Core Sync

    private func syncAccount(accountID: String) async -> SyncResult {
        let start = Date()
        var totalNew = 0
        var errors: [String] = []
        var mailboxResults: [MailboxSyncResult] = []

        do {
            let account = try await emailStore.emailAccount(id: accountID)
            guard let account, let server = account.server, let port = account.port else {
                return SyncResult(accountID: accountID, errors: ["Account not configured"])
            }

            // Get or create connection
            let conn = try await ensureConnection(accountID: accountID, account: account, server: server, port: port)

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
                try await emailStore.upsertIMAPMailbox(
                    accountID: accountID,
                    name: entry.name,
                    delimiter: entry.delimiter,
                    flags: entry.flags,
                    isSelectable: isSelectable,
                    parentPath: parentPath
                )
            }

            // Load persisted mailbox records to detect junk folders
            let imapMailboxes = try await emailStore.imapMailboxes(accountID: accountID)
            let junkMailboxNames = Set(
                imapMailboxes.filter { $0.folderType == .junk }.map(\.mailboxName)
            )

            // Sync all selectable mailboxes, skipping redundant Gmail system folders
            let skipPatterns = ["[gmail]/all mail", "[gmail]/important", "[gmail]/starred"]
            let toSync = listEntries.filter { entry in
                let isSelectable = !entry.flags.contains("\\Noselect") && !entry.flags.contains("\\NonExistent")
                let isRedundant = skipPatterns.contains(entry.name.lowercased())
                return isSelectable && !isRedundant
            }.map(\.name)

            for mailboxName in toSync {
                do {
                    let result = try await syncMailbox(
                        accountID: accountID,
                        conn: conn,
                        mailboxName: mailboxName,
                        isJunkMailbox: junkMailboxNames.contains(mailboxName)
                    )
                    totalNew += result.newMessages
                    mailboxResults.append(result)
                } catch {
                    errors.append("\(mailboxName): \(error.localizedDescription)")
                }
            }

            // SEARCH ALL reconciliation: detect server-side deletions
            for mailboxName in toSync {
                do {
                    try await reconcileMailbox(
                        accountID: accountID,
                        conn: conn,
                        mailboxName: mailboxName
                    )
                } catch {
                    // Non-fatal: reconciliation failure shouldn't block sync
                    logger.warning("Reconciliation failed for \(mailboxName): \(error.localizedDescription)")
                }
            }

            // Confirm deletions for messages missing from ALL mailboxes across two cycles
            let confirmed = try await emailStore.confirmServerDeletions()
            if confirmed > 0 {
                logger.info("Confirmed \(confirmed) server-side deletions for \(accountID)")
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

    private func syncMailbox(
        accountID: String,
        conn: IMAPConnection,
        mailboxName: String,
        isJunkMailbox: Bool = false
    ) async throws -> MailboxSyncResult {
        // Load sync state
        let state = try await emailStore.syncState(accountID: accountID, mailbox: mailboxName)
        var lastUID = state?.lastSyncUID ?? 0
        let savedValidity = state?.uidValidity

        // SELECT mailbox
        let selectResult = try await conn.select(mailbox: mailboxName)

        // Check UIDVALIDITY — if changed, full resync
        if let saved = savedValidity, saved != selectResult.uidValidity {
            logger.warning("UIDVALIDITY changed for \(mailboxName), resetting")
            try await emailStore.resetSyncState(accountID: accountID, mailbox: mailboxName)
            lastUID = 0
        }

        // Search for new messages — sync newest-first so recent emails
        // appear in the UI immediately while older messages backfill.
        let criteria = lastUID > 0 ? "UID \(lastUID + 1):*" : "ALL"
        let uids = try await conn.search(criteria: criteria)
        let newUIDs = uids.filter { $0 > lastUID }.sorted(by: >)

        guard !newUIDs.isEmpty else {
            try await emailStore.updateSyncState(
                accountID: accountID, mailbox: mailboxName,
                uidValidity: selectResult.uidValidity,
                lastSyncUID: lastUID,
                messageCount: state?.messageCount ?? selectResult.exists,
                syncStatus: .idle
            )
            return MailboxSyncResult(mailboxName: mailboxName, lastUID: lastUID, uidValidity: selectResult.uidValidity)
        }

        // Ensure .eml directory exists
        let emlDir = Self.emlDirectory(accountID: accountID, mailbox: mailboxName)
        try FileManager.default.createDirectory(at: emlDir, withIntermediateDirectories: true)

        var newCount = 0

        // Fetch envelopes in batches of 50 for metadata
        for batch in stride(from: 0, to: newUIDs.count, by: 50) {
            let end = min(batch + 50, newUIDs.count)
            let batchUIDs = Array(newUIDs[batch..<end])

            let fetched = try await conn.fetch(uids: batchUIDs, items: "UID FLAGS ENVELOPE RFC822.SIZE")

            for item in fetched {
                let uid = item.uid
                let emlFile = emlDir.appendingPathComponent("\(uid).eml")

                // Fetch raw message body and save as .eml
                do {
                    let bodyData = try await conn.fetchBody(uid: uid)
                    try bodyData.write(to: emlFile, options: Data.WritingOptions.atomic)
                } catch {
                    logger.warning("Failed to fetch body for UID \(uid): \(error.localizedDescription)")
                    continue
                }

                // Parse .eml for preview, content type, attachment count, and body text
                let preview: String?
                let contentType: String?
                let attachmentCount: Int
                let bodyText: String?
                if let data = try? Data(contentsOf: emlFile) {
                    let parsed = MIMEParser.parse(data: data)
                    preview = parsed.textBody.map {
                        String($0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).prefix(200))
                    }
                    contentType = parsed.htmlBody != nil ? "text/html" : "text/plain"
                    attachmentCount = parsed.attachments.count
                    // Extract body text for FTS5 indexing (plaintext preferred, HTML stripped as fallback)
                    let rawBody = parsed.textBody ?? parsed.htmlBody.map { Self.stripHTML($0) }
                    bodyText = rawBody.map { String($0.prefix(51_200)) } // 50KB cap
                } else {
                    preview = nil
                    contentType = nil
                    attachmentCount = 0
                    bodyText = nil
                }

                // Map envelope fields
                let envelope = item.envelope
                let emailID = envelope?.messageID.isEmpty == false
                    ? envelope!.messageID
                    : "imap-\(accountID)-\(mailboxName)-\(uid)"

                // Normalize sender email and domain from envelope.from
                let senderEmail = Self.extractEmail(from: envelope?.from ?? "")
                let senderDomain = senderEmail.flatMap { Self.extractDomain(from: $0) }

                // Map IMAP flags to read/flagged state
                let isRead = item.flags.contains("\\Seen")
                let isFlagged = item.flags.contains("\\Flagged")

                try await emailStore.upsertEmailMessage(
                    emailID: emailID,
                    accountID: accountID,
                    mailbox: mailboxName,
                    sender: envelope?.from ?? "",
                    senderEmail: senderEmail,
                    senderDomain: senderDomain,
                    recipients: envelope?.to ?? "",
                    cc: envelope?.cc ?? "",
                    subject: envelope?.subject ?? "(no subject)",
                    receivedAt: Self.normalizeDate(envelope?.date ?? ISO8601DateFormatter().string(from: Date())),
                    emlPath: emlFile.path,
                    sizeBytes: item.rfc822Size,
                    preview: preview,
                    contentType: contentType,
                    isRead: isRead,
                    isFlagged: isFlagged,
                    inReplyTo: envelope?.inReplyTo.isEmpty == true ? nil : envelope?.inReplyTo,
                    messageIDHeader: envelope?.messageID.isEmpty == true ? nil : envelope?.messageID,
                    attachmentCount: attachmentCount
                )

                // Insert membership row (links this message to this mailbox)
                try await emailStore.upsertMailboxMembership(
                    accountID: accountID,
                    mailbox: mailboxName,
                    imapUID: uid,
                    emailID: emailID
                )

                // Index body text in FTS5 for full-text search
                if let body = bodyText {
                    try await emailStore.updateBodyText(emailID: emailID, bodyText: body)
                }

                // Tag messages in junk/spam folders
                if isJunkMailbox {
                    try await emailStore.updateJunkState(emailID: emailID, isJunk: true)
                }

                newCount += 1
                lastUID = max(lastUID, uid)
            }
        }

        // Update sync state
        try await emailStore.updateSyncState(
            accountID: accountID, mailbox: mailboxName,
            uidValidity: selectResult.uidValidity,
            lastSyncUID: lastUID,
            messageCount: (state?.messageCount ?? 0) + newCount,
            syncStatus: .idle
        )

        logger.info("Synced \(newCount) new messages from \(mailboxName)")
        return MailboxSyncResult(
            mailboxName: mailboxName, newMessages: newCount,
            lastUID: lastUID, uidValidity: selectResult.uidValidity
        )
    }

    // MARK: - EXPUNGE Detection (SEARCH ALL reconciliation)

    /// Compare server UIDs against stored UIDs to detect server-side deletions.
    /// Missing UIDs get a `missing_from` timestamp on their membership row.
    /// Confirmed deletion happens on the NEXT sync cycle (deferred marking).
    private func reconcileMailbox(
        accountID: String,
        conn: IMAPConnection,
        mailboxName: String
    ) async throws {
        let selectResult = try await conn.select(mailbox: mailboxName)

        // Get all UIDs currently on the server
        let serverUIDs = Set(try await conn.search(criteria: "ALL"))

        // Get all UIDs we have stored for this mailbox
        let storedUIDs = try await emailStore.storedUIDs(accountID: accountID, mailbox: mailboxName)

        // UIDs we have but server doesn't = potentially deleted
        let missingUIDs = storedUIDs.subtracting(serverUIDs)

        // UIDs that reappeared (were marked missing but are back)
        let reappearedUIDs = serverUIDs.intersection(storedUIDs)

        if !missingUIDs.isEmpty {
            try await emailStore.markMissingFromMailbox(
                accountID: accountID,
                mailbox: mailboxName,
                missingUIDs: missingUIDs
            )
            logger.info("\(missingUIDs.count) UIDs missing from \(mailboxName)")
        }

        // Clear missing_from for UIDs that reappeared
        if !reappearedUIDs.isEmpty {
            try await emailStore.clearMissingFrom(
                accountID: accountID,
                mailbox: mailboxName,
                reappearedUIDs: reappearedUIDs
            )
        }

        _ = selectResult // suppress unused warning
    }

    // MARK: - HTML Stripping

    /// Strip HTML tags for plaintext body extraction (fallback when no text/plain part).
    nonisolated static func stripHTML(_ html: String) -> String {
        var result = html
        // Remove script/style blocks entirely
        result = result.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: "", options: .regularExpression
        )
        // Replace <br> and block elements with newlines
        result = result.replacingOccurrences(
            of: "<(br|p|div|h[1-6]|li|tr)[^>]*/?>",
            with: "\n", options: [.regularExpression, .caseInsensitive]
        )
        // Remove remaining tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "),
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // Collapse whitespace
        result = result.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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

        // Authenticate — fail fast if credentials are missing rather than
        // sending an empty LOGIN that the server will reject.
        guard let password = KeychainHelper.retrieve(accountID: accountID), !password.isEmpty else {
            await conn.disconnect()
            throw IMAPError.authenticationFailed("No stored credential — please re-enter your password in Settings → Email Backup")
        }
        guard let username = account.username, !username.isEmpty else {
            await conn.disconnect()
            throw IMAPError.authenticationFailed("No username configured for this account")
        }
        try await conn.login(username: username, password: password)

        connections[accountID] = conn
        return conn
    }

    // MARK: - .eml Storage

    /// Root directory for all email backups.
    public static var backupRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Manifold/EmailBackup")
    }

    /// Directory for a specific account + mailbox.
    public static func emlDirectory(accountID: String, mailbox: String) -> URL {
        let safe = mailbox.replacingOccurrences(of: "/", with: "_")
        return backupRoot.appendingPathComponent(accountID).appendingPathComponent(safe)
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
            let iso = ISO8601DateFormatter()
            if iso.date(from: trimmed) != nil { return trimmed }
        }

        // Try RFC 2822 formats
        let rfc2822 = DateFormatter()
        rfc2822.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",     // "Mon, 05 Jan 2013 12:00:00 +0000"
            "dd MMM yyyy HH:mm:ss Z",           // "05 Jan 2013 12:00:00 +0000"
            "EEE, dd MMM yyyy HH:mm:ss zzz",    // "Mon, 05 Jan 2013 12:00:00 GMT"
            "dd MMM yyyy HH:mm:ss zzz",          // "05 Jan 2013 12:00:00 GMT"
            "EEE, d MMM yyyy HH:mm:ss Z",       // "Mon, 5 Jan 2013 12:00:00 +0000"
            "d MMM yyyy HH:mm:ss Z",            // "5 Jan 2013 12:00:00 +0000"
        ]

        for format in formats {
            rfc2822.dateFormat = format
            if let date = rfc2822.date(from: trimmed) {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime]
                return iso.string(from: date)
            }
        }

        // Can't parse — return as-is (better than crashing)
        return trimmed
    }
}
