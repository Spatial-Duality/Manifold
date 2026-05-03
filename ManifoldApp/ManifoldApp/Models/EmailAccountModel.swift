// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "email-accounts")

struct MailProviderOnboardingLink: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let url: URL

    init(_ title: String, _ urlString: String) {
        self.id = title
        self.title = title
        self.url = URL(string: urlString)!
    }
}

struct MailProviderOnboardingGuide: Sendable, Equatable {
    let displayLabel: String
    let detail: String
    let resolvedProvider: EmailProvider
    let credentialLabel: String
    let steps: [String]
    let links: [MailProviderOnboardingLink]
    let blockers: [String]
    let validationHelp: String
    let primaryActionTitle: String

    static func guide(for provider: EmailProvider, emailAddress: String? = nil) -> MailProviderOnboardingGuide {
        if provider == .other,
           let detectedProvider = detectedOtherProvider(emailAddress: emailAddress) {
            return detectedOtherGuide(for: detectedProvider)
        }

        switch provider {
        case .gmail:
            return MailProviderOnboardingGuide(
                displayLabel: "Google",
                detail: "Gmail and Google Workspace",
                resolvedProvider: .gmail,
                credentialLabel: "Google app password",
                steps: [
                    "Turn on 2-Step Verification for the Google Account.",
                    "Create an app password named Manifold.",
                    "Paste the 16-character app password here after Google shows it.",
                ],
                links: [
                    MailProviderOnboardingLink("Open Google App Passwords", "https://myaccount.google.com/apppasswords"),
                    MailProviderOnboardingLink("Open Google Account Security", "https://myaccount.google.com/security"),
                ],
                blockers: [
                    "App passwords may be unavailable for Advanced Protection, security-key-only 2-Step Verification, or some work and school accounts.",
                    "If Google says the password is wrong, generate a new app password and paste it without spaces.",
                ],
                validationHelp: "Check that 2-Step Verification is enabled and paste a current Google app password, not the normal Google password.",
                primaryActionTitle: "Connect"
            )
        case .outlook:
            return MailProviderOnboardingGuide(
                displayLabel: "Microsoft",
                detail: "Outlook and Microsoft 365",
                resolvedProvider: .outlook,
                credentialLabel: "Microsoft sign-in",
                steps: [
                    "Sign in with Microsoft in the browser window.",
                    "Approve IMAP mail access for Manifold.",
                    "Work or school tenants may require administrator approval or IMAP enablement.",
                ],
                links: [
                    MailProviderOnboardingLink("Open Outlook IMAP Settings", "https://outlook.live.com/mail/0/options/mail/accounts/popImap"),
                    MailProviderOnboardingLink("Read Microsoft IMAP OAuth Guidance", "https://learn.microsoft.com/en-us/exchange/client-developer/legacy-protocols/how-to-authenticate-an-imap-pop-smtp-application-by-using-oauth"),
                ],
                blockers: [
                    "Microsoft 365 tenants can require administrator consent for third-party apps.",
                    "Outlook.com may require IMAP to be enabled in Mail settings.",
                ],
                validationHelp: "If sign-in fails, check whether this Microsoft tenant allows IMAP OAuth and whether an administrator must approve Manifold.",
                primaryActionTitle: "Sign in with Microsoft"
            )
        case .icloud:
            return MailProviderOnboardingGuide(
                displayLabel: "iCloud",
                detail: "iCloud Mail",
                resolvedProvider: .icloud,
                credentialLabel: "Apple app-specific password",
                steps: [
                    "Sign in to your Apple Account.",
                    "Create an app-specific password for Manifold.",
                    "Paste the app-specific password here.",
                ],
                links: [
                    MailProviderOnboardingLink("Open Apple Account", "https://account.apple.com/"),
                    MailProviderOnboardingLink("Read Apple App-Specific Passwords", "https://support.apple.com/en-us/102654"),
                    MailProviderOnboardingLink("Read iCloud Mail Settings", "https://support.apple.com/en-ca/102525"),
                ],
                blockers: [
                    "Apple requires two-factor authentication before app-specific passwords can be generated.",
                    "Manifold tries the iCloud username before the full email address, matching Apple's IMAP guidance.",
                ],
                validationHelp: "Use an Apple app-specific password. If validation fails, revoke it and generate a new one from your Apple Account.",
                primaryActionTitle: "Connect"
            )
        case .yahoo:
            return detectedOtherGuide(for: .yahoo)
        case .fastmail:
            return detectedOtherGuide(for: .fastmail)
        case .other:
            return MailProviderOnboardingGuide(
                displayLabel: "Other",
                detail: "Generic IMAP server",
                resolvedProvider: .other,
                credentialLabel: "Password or app password",
                steps: [
                    "Enter the IMAP host, TLS port, username, and credential from your provider.",
                    "Many providers require an app password when two-factor authentication is enabled.",
                    "Manifold validates the IMAP login before storing the credential in Keychain.",
                ],
                links: [
                    MailProviderOnboardingLink("Gmail IMAP Help", "https://support.google.com/mail/answer/7126229"),
                    MailProviderOnboardingLink("Yahoo App Passwords", "https://help.yahoo.com/kb/account/confirm-delete-password-sln15241.html"),
                    MailProviderOnboardingLink("Fastmail App Passwords", "https://www.fastmail.help/hc/en-us/articles/360058752854-App-passwords"),
                ],
                blockers: [
                    "Plain insecure IMAP is not supported.",
                    "If the account uses two-factor authentication, the normal password may be rejected.",
                ],
                validationHelp: "Confirm the IMAP host, TLS port, username, and whether your provider expects an app password.",
                primaryActionTitle: "Connect"
            )
        }
    }

    static func detectedOtherProvider(emailAddress: String?) -> EmailProvider? {
        guard let emailAddress = emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              emailAddress.contains("@") else {
            return nil
        }

        switch MailProviderCatalog.detectProviders(emailAddress: emailAddress).first {
        case .yahoo:
            return .yahoo
        case .fastmail:
            return .fastmail
        default:
            return nil
        }
    }

    private static func detectedOtherGuide(for provider: EmailProvider) -> MailProviderOnboardingGuide {
        switch provider {
        case .yahoo:
            return MailProviderOnboardingGuide(
                displayLabel: "Yahoo Mail",
                detail: "Detected from the email address",
                resolvedProvider: .yahoo,
                credentialLabel: "Yahoo app password",
                steps: [
                    "Open Yahoo Account Security.",
                    "Create an app password named Manifold.",
                    "Paste the generated one-time password here.",
                ],
                links: [
                    MailProviderOnboardingLink("Open Yahoo Account Security", "https://login.yahoo.com/account/security"),
                    MailProviderOnboardingLink("Read Yahoo App Passwords", "https://help.yahoo.com/kb/account/confirm-delete-password-sln15241.html"),
                    MailProviderOnboardingLink("Read Yahoo IMAP Settings", "https://help.yahoo.com/kb/new-yahoo-mail/imap-smtp-settings-article-sln4075.html"),
                ],
                blockers: [
                    "Yahoo app-password eligibility can depend on recent account sign-in history.",
                    "Use a normal browser session, not Incognito, when creating the app password.",
                ],
                validationHelp: "Use a Yahoo app password. If Yahoo does not offer one, sign in to Yahoo Mail in a browser and try again later.",
                primaryActionTitle: "Connect"
            )
        case .fastmail:
            return MailProviderOnboardingGuide(
                displayLabel: "Fastmail",
                detail: "Detected from the email address",
                resolvedProvider: .fastmail,
                credentialLabel: "Fastmail app password",
                steps: [
                    "Open Fastmail Privacy & Security settings.",
                    "Create a new app password for Manifold.",
                    "Choose mail access, then paste the generated password here.",
                ],
                links: [
                    MailProviderOnboardingLink("Open Fastmail Settings", "https://app.fastmail.com/settings/security"),
                    MailProviderOnboardingLink("Read Fastmail App Passwords", "https://www.fastmail.help/hc/en-us/articles/360058752854-App-passwords"),
                    MailProviderOnboardingLink("Read Fastmail IMAP Settings", "https://www.fastmail.help/hc/en-us/articles/1500000279921-IMAP-POP-and-SMTP"),
                ],
                blockers: [
                    "Fastmail Basic plans do not include third-party IMAP access or app passwords.",
                    "The app password must include Mail access.",
                ],
                validationHelp: "Use a Fastmail app password with Mail access. Normal Fastmail passwords are rejected by third-party IMAP clients.",
                primaryActionTitle: "Connect"
            )
        default:
            return guide(for: .other)
        }
    }
}

enum MailSyncProgressPresentation {
    static func accountSubtitle(
        progress: MailSyncProgressSnapshot?,
        account: EmailAccountRecord
    ) -> String {
        guard let progress else {
            return account.username ?? account.provider.displayName
        }
        if progress.stage == .needsAttention {
            guard progress.failedMailboxCount > 0 else {
                return "Needs attention · Sync error"
            }
            let errors = progress.failedMailboxCount == 1 ? "1 mailbox error" : "\(progress.failedMailboxCount) mailbox errors"
            return "Needs attention · \(errors)"
        }
        if progress.retryScheduledCount > 0 {
            return "\(formattedCount(progress.syncedMessageCount)) synced · Retry queued"
        }
        return "\(formattedCount(progress.syncedMessageCount)) synced · \(stageTitle(progress.stage))"
    }

    static func mailboxCount(
        progress: MailSyncProgressSnapshot?,
        mailboxName: String
    ) -> String? {
        guard let count = progress?.mailboxSyncedCounts[mailboxName], count > 0 else {
            return nil
        }
        return formattedCount(count)
    }

    static func mailboxSubtitle(
        progress: MailSyncProgressSnapshot?,
        mailboxName: String,
        syncState: SyncStateRecord?
    ) -> String? {
        if syncState?.syncStatus == .error {
            return "Needs attention"
        }
        guard let progress, progress.currentMailboxName == mailboxName, progress.stage.isActive else {
            return nil
        }
        return stageTitle(progress.stage)
    }

    static func toolbarStatus(
        account: EmailAccountRecord?,
        mailboxDisplayName: String?,
        mailboxName: String?,
        progress: MailSyncProgressSnapshot?
    ) -> String {
        guard let account else {
            return "Choose a mailbox to review backed-up mail"
        }
        var parts = [account.displayName]
        if let mailboxDisplayName, !mailboxDisplayName.isEmpty {
            parts.append(mailboxDisplayName)
        }
        let scopedCount: Int
        if let mailboxName, let count = progress?.mailboxSyncedCounts[mailboxName] {
            scopedCount = count
        } else {
            scopedCount = progress?.syncedMessageCount ?? 0
        }
        parts.append("\(formattedCount(scopedCount)) messages")
        if let progress {
            if progress.stage == .upToDate, let updated = relativeTimestamp(progress.lastUpdatedAt) {
                parts.append("Updated \(updated)")
            } else {
                parts.append(stageTitle(progress.stage))
            }
        }
        return parts.joined(separator: " · ")
    }

    static func stageTitle(_ stage: MailSyncProgressStage) -> String {
        switch stage {
        case .checkingMailboxes:
            return "Checking mailboxes"
        case .syncingRecentMail:
            return "Syncing recent mail"
        case .recentMailReady:
            return "Recent mail ready"
        case .archivingOlderMail:
            return "Archiving older mail"
        case .indexingPrivately:
            return "Indexing privately"
        case .paused:
            return "Paused"
        case .needsAttention:
            return "Needs attention"
        case .upToDate:
            return "Up to date"
        }
    }

    static func stageSymbol(_ stage: MailSyncProgressStage) -> String {
        switch stage {
        case .checkingMailboxes, .syncingRecentMail, .archivingOlderMail, .indexingPrivately:
            return "arrow.triangle.2.circlepath"
        case .recentMailReady:
            return "clock.badge.checkmark"
        case .paused:
            return "pause.circle"
        case .needsAttention:
            return "exclamationmark.triangle"
        case .upToDate:
            return "checkmark.circle"
        }
    }

    static func runningJobTitle(_ jobType: MailSyncJobType?) -> String {
        guard let jobType else { return "None" }
        switch jobType {
        case .initial:
            return "Initial mailbox check"
        case .recentPass:
            return "Recent mail sync"
        case .historicalBackfill:
            return "Older mail archive"
        case .incremental:
            return "Incremental sync"
        case .reconcile:
            return "Mailbox reconcile"
        }
    }

    static func eventTitle(_ event: MailSyncActivityLogEntry) -> String {
        var parts = [event.status]
        if let mailbox = event.mailboxName, !mailbox.isEmpty {
            parts.append(mailbox)
        }
        if let jobType = event.jobType {
            parts.append(runningJobTitle(jobType))
        }
        return parts.joined(separator: " · ")
    }

    static func orderedForActivity(_ snapshots: [MailSyncProgressSnapshot]) -> [MailSyncProgressSnapshot] {
        snapshots.sorted { left, right in
            if left.stage.activitySortRank != right.stage.activitySortRank {
                return left.stage.activitySortRank < right.stage.activitySortRank
            }
            if left.runningJobCount != right.runningJobCount {
                return left.runningJobCount > right.runningJobCount
            }
            if left.syncedMessageCount != right.syncedMessageCount {
                return left.syncedMessageCount > right.syncedMessageCount
            }
            return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
        }
    }

    static func formattedCount(_ count: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
    }

    static func relativeTimestamp(_ isoString: String?) -> String? {
        guard let isoString,
              let date = ISO8601DateFormatter.shared.date(from: isoString) else {
            return nil
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension MailSyncProgressStage {
    var isActive: Bool {
        switch self {
        case .checkingMailboxes, .syncingRecentMail, .archivingOlderMail, .indexingPrivately:
            return true
        case .recentMailReady, .paused, .needsAttention, .upToDate:
            return false
        }
    }

    fileprivate var activitySortRank: Int {
        switch self {
        case .needsAttention:
            return 0
        case .checkingMailboxes, .syncingRecentMail, .archivingOlderMail, .indexingPrivately:
            return 1
        case .recentMailReady:
            return 2
        case .paused:
            return 3
        case .upToDate:
            return 4
        }
    }
}

enum MailOnboardingProvider: String, CaseIterable, Identifiable, Hashable {
    case google
    case microsoft
    case icloud
    case other

    var id: String { rawValue }

    var emailProvider: EmailProvider {
        switch self {
        case .google:
            return .gmail
        case .microsoft:
            return .outlook
        case .icloud:
            return .icloud
        case .other:
            return .other
        }
    }

    var guide: MailProviderOnboardingGuide {
        MailProviderOnboardingGuide.guide(for: emailProvider)
    }

    var accessibilityIdentifier: String {
        "settings.mail.provider.\(rawValue)"
    }
}

@Observable
@MainActor
final class MailAccountsModel {
    var accounts: [EmailAccountRecord] = []
    var syncStates: [String: [SyncStateRecord]] = [:]
    var syncJobsByAccountID: [String: [MailSyncJobRecord]] = [:]
    var syncProgressByAccountID: [String: MailSyncProgressSnapshot] = [:]
    var syncActivityByAccountID: [String: [MailSyncActivityLogEntry]] = [:]
    var totalMessageCount: Int = 0
    var mailboxRefreshToken: Int = 0
    var lastQueryError: String?
    var lastRemovalHistoryPath: String?
    var lastRemovalError: String?

    /// Whether any account is currently syncing.
    var isSyncing: Bool {
        syncProgressByAccountID.values.contains { $0.stage.isActive }
            || syncStates.values.contains { states in states.contains { $0.syncStatus == .syncing } }
    }

    private var client: (any RuntimeClientProtocol)?
    private var archiveInfo: MailArchiveInfo?

    init() {}

    func configure(client: any RuntimeClientProtocol) {
        self.client = client
    }

    func loadAccounts() async {
        guard let client else { return }
        do {
            let fetchedAccounts = try await client.listEmailAccounts()
            let fetchedMessageCount = try await client.emailMessageCount()
            let fetchedArchiveInfo = try? await client.emailBackupInfo()
            let fetchedProgress = (try? await client.mailSyncProgress(accountID: nil)) ?? []
            var nextStates: [String: [SyncStateRecord]] = [:]
            var nextJobs: [String: [MailSyncJobRecord]] = [:]
            var nextActivity: [String: [MailSyncActivityLogEntry]] = [:]
            for account in fetchedAccounts {
                nextStates[account.accountID] = try await client.syncStates(accountID: account.accountID)
                nextJobs[account.accountID] = try await client.mailSyncJobs(
                    accountID: account.accountID,
                    states: [.queued, .running, .failed],
                    limit: 100
                )
                nextActivity[account.accountID] = (try? await client.mailSyncActivity(
                    accountID: account.accountID,
                    limit: 50
                )) ?? []
            }
            accounts = fetchedAccounts
            totalMessageCount = fetchedMessageCount
            archiveInfo = fetchedArchiveInfo
            syncStates = nextStates
            syncJobsByAccountID = nextJobs
            syncActivityByAccountID = nextActivity
            syncProgressByAccountID = Dictionary(
                uniqueKeysWithValues: fetchedProgress.map { ($0.accountID, $0) }
            )
            mailboxRefreshToken &+= 1
        } catch {
            logger.error("Failed to load email accounts: \(error.localizedDescription)")
        }
    }

    func addIMAPAccount(
        displayName: String,
        provider: EmailProvider,
        server: String,
        port: Int,
        username: String,
        password: String
    ) async -> String? {
        guard let client else { return "Runtime unavailable" }
        do {
            _ = try await client.addIMAPAccount(
                displayName: displayName,
                provider: provider,
                server: server,
                port: port,
                username: username,
                password: password
            )
            await loadAccounts()
            return nil
        } catch {
            logger.error("Failed to add email account: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    func addOAuthIMAPAccount(
        displayName: String,
        provider: EmailProvider,
        server: String,
        port: Int,
        username: String,
        tokenSet: MicrosoftOAuthTokenSet
    ) async -> String? {
        guard let client else { return "Runtime unavailable" }
        do {
            _ = try await client.addOAuthIMAPAccount(
                displayName: displayName,
                provider: provider,
                server: server,
                port: port,
                username: username,
                tokenSet: tokenSet
            )
            await loadAccounts()
            return nil
        } catch {
            logger.error("Failed to add OAuth email account: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    func removeAccount(id: String) async -> MailAccountRemovalResult? {
        guard let client else {
            lastRemovalError = "Runtime unavailable"
            return nil
        }
        do {
            let result = try await client.removeEmailAccount(id: id)
            lastRemovalHistoryPath = result.contextArchivePath
            lastRemovalError = nil
            await loadAccounts()
            return result
        } catch {
            logger.error("Failed to remove account: \(error.localizedDescription)")
            lastRemovalError = error.localizedDescription
            await loadAccounts()
            return nil
        }
    }

    func toggleSync(accountID: String, enabled: Bool) async {
        guard let client else { return }
        do {
            try await client.toggleEmailSync(accountID: accountID, enabled: enabled)
            await loadAccounts()
        } catch {
            logger.error("Failed to toggle sync: \(error.localizedDescription)")
        }
    }

    func syncNow(accountID: String) async {
        guard let client else { return }
        do {
            let result = try await client.syncEmailNow(accountID: accountID)
            if !result.isSuccess {
                logger.warning("Sync errors: \(result.errors.joined(separator: ", "))")
                lastQueryError = result.errors.joined(separator: ", ")
            } else {
                lastQueryError = nil
            }
        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
            lastQueryError = error.localizedDescription
        }
        await loadAccounts()
    }

    func syncActivity(accountID: String) -> [MailSyncActivityLogEntry] {
        syncActivityByAccountID[accountID] ?? []
    }

    func messages(accountID: String, limit: Int = 200) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        do {
            let result = try await client.emailMessages(
                accountID: accountID,
                mailbox: nil,
                ids: nil,
                limit: limit
            )
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func allMessages(limit: Int = 500) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        do {
            let result = try await client.emailMessages(
                accountID: nil,
                mailbox: nil,
                ids: nil,
                limit: limit
            )
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func messages(ids: [String]) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        do {
            let result = try await client.emailMessages(
                accountID: nil,
                mailbox: nil,
                ids: ids,
                limit: max(ids.count, 500)
            )
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func domainCounts() async -> [String: Int] {
        guard let client else { return [:] }
        return (try? await client.domainCounts()) ?? [:]
    }

    func unreadCountAll() async -> Int {
        guard let client else { return 0 }
        return (try? await client.unreadCountAll()) ?? 0
    }

    func unreadCount(accountID: String) async -> Int {
        guard let client else { return 0 }
        return (try? await client.unreadCount(accountID: accountID)) ?? 0
    }

    func unreadCount(accountID: String, mailbox: String) async -> Int {
        guard let client else { return 0 }
        return (try? await client.unreadCount(accountID: accountID, mailbox: mailbox)) ?? 0
    }

    func imapMailboxes(accountID: String) async -> [IMAPMailboxRecord] {
        guard let client else { return [] }
        do {
            let result = try await client.imapMailboxes(accountID: accountID)
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func messagesInMailbox(accountID: String, mailbox: String, limit: Int = 500) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        let resolvedMailbox = await resolvedMailboxName(accountID: accountID, requestedName: mailbox)
        do {
            let result = try await client.emailMessages(
                accountID: accountID,
                mailbox: resolvedMailbox,
                ids: nil,
                limit: limit
            )
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func messagePage(
        tokens: [SearchToken] = [],
        freeText: String = "",
        accountID: String? = nil,
        mailbox: String? = nil,
        filter: QuickFilter? = nil,
        sortKey: EmailSortKey = .date,
        limit: Int,
        offset: Int
    ) async -> EmailMessagePage {
        guard let client else {
            return EmailMessagePage(messages: [], totalCount: 0, limit: limit, offset: offset)
        }
        do {
            let resolvedMailbox: String?
            if let accountID, let mailbox {
                resolvedMailbox = await resolvedMailboxName(accountID: accountID, requestedName: mailbox)
            } else {
                resolvedMailbox = mailbox
            }
            let page = try await client.emailMessagePage(
                tokens: tokens,
                freeText: freeText,
                accountID: accountID,
                mailbox: resolvedMailbox,
                filter: filter,
                sortKey: sortKey,
                limit: limit,
                offset: offset
            )
            lastQueryError = nil
            return page
        } catch {
            lastQueryError = error.localizedDescription
            return EmailMessagePage(messages: [], totalCount: 0, limit: limit, offset: offset)
        }
    }

    func resolvedMailboxName(accountID: String, requestedName: String) async -> String {
        let mailboxes = await imapMailboxes(accountID: accountID)
        return MailboxResolver.resolve(requestedName: requestedName, imapMailboxes: mailboxes)
    }

    func sharedEmailCount(agent: TargetApp = .cowork) async -> Int {
        guard let client else { return 0 }
        return (try? await client.sharedEmailCount(agent: agent)) ?? 0
    }

    func sharedEmailIDs(agent: TargetApp = .cowork) async -> Set<String> {
        guard let client else { return [] }
        do {
            let result = try await client.sharedEmailIDs(agent: agent)
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func sharedEmails(agent: TargetApp = .cowork, limit: Int = 500) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        do {
            let result = try await client.sharedEmails(agent: agent, limit: limit)
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func shareEmails(emailIDs: [String], for agent: TargetApp = .cowork) async {
        guard let client else { return }
        do {
            try await client.shareEmails(emailIDs: emailIDs, for: agent)
            lastQueryError = nil
        } catch {
            lastQueryError = error.localizedDescription
        }
    }

    func unshareEmails(emailIDs: [String], for agent: TargetApp = .cowork) async {
        guard let client else { return }
        do {
            try await client.unshareEmails(emailIDs: emailIDs, for: agent)
            lastQueryError = nil
        } catch {
            lastQueryError = error.localizedDescription
        }
    }

    func attachments(emailID: String) async -> [EmailAttachmentRecord] {
        guard let client else { return [] }
        do {
            let result = try await client.emailAttachments(emailID: emailID)
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func sharedEmailAttachmentIDs(agent: TargetApp, emailID: String) async -> Set<String> {
        guard let client else { return [] }
        do {
            let result = try await client.sharedEmailAttachmentIDs(agent: agent, emailID: emailID)
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func shareEmailAttachments(attachmentIDs: [String], for agent: TargetApp) async {
        guard let client else { return }
        do {
            try await client.shareEmailAttachments(attachmentIDs: attachmentIDs, for: agent)
            lastQueryError = nil
        } catch {
            lastQueryError = error.localizedDescription
        }
    }

    func unshareEmailAttachments(attachmentIDs: [String], for agent: TargetApp) async {
        guard let client else { return }
        do {
            try await client.unshareEmailAttachments(attachmentIDs: attachmentIDs, for: agent)
            lastQueryError = nil
        } catch {
            lastQueryError = error.localizedDescription
        }
    }

    func openEmail(emailID: String) async -> String? {
        guard let client else { return nil }
        do {
            let path = try await client.openEmailExport(emailID: emailID)
            lastQueryError = nil
            return path
        } catch {
            lastQueryError = error.localizedDescription
            return nil
        }
    }

    func openAttachment(attachmentID: String) async -> String? {
        guard let client else { return nil }
        do {
            let path = try await client.openEmailAttachment(attachmentID: attachmentID)
            lastQueryError = nil
            return path
        } catch {
            lastQueryError = error.localizedDescription
            return nil
        }
    }

    func unshareAllEmails() async {
        guard let client else { return }
        try? await client.unshareAllEmails()
    }

    func updateReadState(emailID: String, isRead: Bool) async {
        guard let client else { return }
        try? await client.updateEmailReadState(emailID: emailID, isRead: isRead)
    }

    func updateFlagState(emailID: String, isFlagged: Bool, flagColor: String? = nil) async {
        guard let client else { return }
        try? await client.updateEmailFlagState(emailID: emailID, isFlagged: isFlagged, flagColor: flagColor)
    }

    func batchUpdateReadState(emailIDs: [String], isRead: Bool) async {
        guard let client else { return }
        try? await client.batchUpdateReadState(emailIDs: emailIDs, isRead: isRead)
    }

    func batchUpdateFlagState(emailIDs: [String], isFlagged: Bool, flagColor: String? = nil) async {
        guard let client else { return }
        try? await client.batchUpdateFlagState(emailIDs: emailIDs, isFlagged: isFlagged, flagColor: flagColor)
    }

    func searchMessages(
        tokens: [SearchToken] = [],
        freeText: String = "",
        accountID: String? = nil,
        mailbox: String? = nil,
        filter: QuickFilter? = nil,
        sortKey: EmailSortKey = .date,
        limit: Int = 500
    ) async -> [EmailMessageRecord] {
        guard let client else { return [] }
        do {
            let result = try await client.searchEmailMessages(
                tokens: tokens,
                freeText: freeText,
                accountID: accountID,
                mailbox: mailbox,
                filter: filter,
                sortKey: sortKey,
                limit: limit
            )
            lastQueryError = nil
            return result
        } catch {
            lastQueryError = error.localizedDescription
            return []
        }
    }

    func createSmartMailbox(displayName: String, iconName: String = "tray", rulesJSON: String = "[]") async throws {
        guard let client else { return }
        try await client.createSmartMailbox(displayName: displayName, iconName: iconName, rulesJSON: rulesJSON)
    }

    func allSmartMailboxes() async throws -> [SmartMailboxRecord] {
        guard let client else { return [] }
        return try await client.listSmartMailboxes()
    }

    func updateSmartMailbox(mailboxID: String, displayName: String, iconName: String, rulesJSON: String) async throws {
        guard let client else { return }
        try await client.updateSmartMailbox(
            mailboxID: mailboxID,
            displayName: displayName,
            iconName: iconName,
            rulesJSON: rulesJSON
        )
    }

    func deleteSmartMailbox(mailboxID: String) async throws {
        guard let client else { return }
        try await client.deleteSmartMailbox(mailboxID: mailboxID)
    }

    var archiveRootPath: String {
        archiveInfo?.path ?? EmailSyncEngine.mailArchiveRoot.path
    }

    func progress(for accountID: String) -> MailSyncProgressSnapshot? {
        syncProgressByAccountID[accountID]
    }

    func progress(for account: EmailAccountRecord) -> MailSyncProgressSnapshot? {
        progress(for: account.accountID)
    }
}
