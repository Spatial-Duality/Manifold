import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "email")

@Observable
@MainActor
final class EmailModel {
    var emailRules: [EmailRule] = []
    var cachedEmails: [CachedEmail] = []
    var emailClassification: EmailClassificationResult?
    var mailAccessStatus: MailAccessStatus?
    var mailboxes: [MailboxInfo] = []
    var selectedEmailIDsForNextSession: Set<String> = []

    private var emailFilter: EmailFilter?
    private var grantStore: GrantStore?
    private var contentStore: ContentStore?
    private let mailConnector = AppleMailConnector()

    init() {}

    func configure(emailFilter: EmailFilter, grantStore: GrantStore, contentStore: ContentStore) {
        self.emailFilter = emailFilter
        self.grantStore = grantStore
        self.contentStore = contentStore
    }

    func checkMailAccess() async {
        do { mailAccessStatus = try mailConnector.checkAccess() }
        catch { mailAccessStatus = .accessDenied }
    }

    func loadMailboxes() async {
        do { mailboxes = try mailConnector.listMailboxes() }
        catch { mailboxes = [] }
    }

    func fetchAndCacheEmails(account: String, mailbox: String) async {
        guard let emailFilter, let grantStore else { return }
        let emails: [RenderedEmail]
        do { emails = try mailConnector.fetchMessages(account: account, mailbox: mailbox, limit: 100) }
        catch { return }

        var fetched: [(id: String, email: RenderedEmail)] = []
        for email in emails {
            guard let messageID = try? await emailFilter.cacheEmail(email, account: account, mailbox: mailbox) else { continue }
            var normalized = email
            normalized.messageID = messageID
            fetched.append((messageID, normalized))
        }

        await reclassifyEmails()
        await loadCachedEmails()

        let statusByID = Dictionary(uniqueKeysWithValues: cachedEmails.map { ($0.messageID, $0) })
        for fetchedEmail in fetched {
            let preview = String(fetchedEmail.email.body.prefix(200))
            let contentHash: String?
            if let contentStore {
                contentHash = try? await contentStore.ingest(data: Data(fetchedEmail.email.toMarkdown().utf8))
            } else {
                contentHash = nil
            }
            let cached = statusByID[fetchedEmail.id]
            try? await grantStore.upsertEmailMessage(
                emailID: fetchedEmail.id,
                account: account,
                mailbox: mailbox,
                sender: fetchedEmail.email.from,
                recipients: fetchedEmail.email.to,
                subject: fetchedEmail.email.subject,
                receivedAt: fetchedEmail.email.date,
                preview: preview,
                classificationStatus: cached?.status ?? "pending",
                hiddenReason: cached?.hiddenReason,
                contentHash: contentHash
            )
        }
    }

    func loadEmailRules() async {
        do { emailRules = try await emailFilter?.globalRules() ?? [] }
        catch { logger.error("Failed to load email rules: \(error.localizedDescription)"); emailRules = [] }
    }

    func addEmailRule(type: RuleType, pattern: String, category: String) async {
        do {
            try await emailFilter?.addGlobalRule(type: type, pattern: pattern, category: category)
        } catch {
            logger.warning("Failed to add email rule: \(error.localizedDescription)")
        }
        await loadEmailRules()
        await reclassifyEmails()
    }

    func removeEmailRule(id: Int) async {
        do { try await emailFilter?.removeRule(id: id) }
        catch { logger.warning("Failed to remove email rule: \(error.localizedDescription)") }
        await loadEmailRules()
        await reclassifyEmails()
    }

    func overrideEmailToShared(messageID: String) async {
        do { try await emailFilter?.overrideToShared(messageID: messageID) }
        catch { logger.warning("Failed to share email: \(error.localizedDescription)") }
        await loadCachedEmails()
    }

    func hideEmail(messageID: String) async {
        do { try await emailFilter?.hideEmail(messageID: messageID, reason: "User hidden") }
        catch { logger.warning("Failed to hide email: \(error.localizedDescription)") }
        selectedEmailIDsForNextSession.remove(messageID)
        await loadCachedEmails()
    }

    func reclassifyEmails() async {
        do { emailClassification = try await emailFilter?.classifyAll() }
        catch { logger.warning("Failed to reclassify emails: \(error.localizedDescription)"); emailClassification = nil }
        await loadCachedEmails()
    }

    func loadCachedEmails() async {
        do { cachedEmails = try await emailFilter?.allCachedEmails() ?? [] }
        catch { logger.warning("Failed to load cached emails: \(error.localizedDescription)"); cachedEmails = [] }
        let sharedIDs = Set(cachedEmails.filter(\.isShared).map(\.messageID))
        selectedEmailIDsForNextSession = selectedEmailIDsForNextSession.intersection(sharedIDs)
        await syncGrantEmailMetadataFromCache()
    }

    func toggleEmailSelection(messageID: String) {
        guard let email = cachedEmails.first(where: { $0.messageID == messageID }), email.isShared else { return }
        if selectedEmailIDsForNextSession.contains(messageID) {
            selectedEmailIDsForNextSession.remove(messageID)
        } else {
            selectedEmailIDsForNextSession.insert(messageID)
        }
    }

    private func syncGrantEmailMetadataFromCache() async {
        guard let grantStore else { return }
        for email in cachedEmails {
            let existing = try? await grantStore.emailMessage(id: email.messageID)
            try? await grantStore.upsertEmailMessage(
                emailID: email.messageID,
                account: email.account,
                mailbox: email.mailbox,
                sender: email.sender,
                recipients: existing?.recipients ?? "",
                subject: email.subject,
                receivedAt: email.dateReceived,
                preview: email.bodyPreview,
                classificationStatus: email.status,
                hiddenReason: email.hiddenReason,
                contentHash: existing?.contentHash
            )
        }
    }
}
