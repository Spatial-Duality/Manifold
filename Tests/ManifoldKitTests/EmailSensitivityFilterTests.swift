import Testing
import Foundation
@testable import ManifoldKit

@Suite("EmailSensitivityFilter")
struct EmailSensitivityFilterTests {

    private func makeEmail(
        id: String = "test-\(UUID().uuidString.prefix(8))",
        senderDomain: String? = "example.com"
    ) -> EmailMessageRecord {
        let row: [String: String] = [
            "email_id": id,
            "account_id": "acct-1",
            "mailbox": "INBOX",
            "sender": "user@\(senderDomain ?? "unknown")",
            "sender_email": "user@\(senderDomain ?? "unknown")",
            "sender_domain": senderDomain ?? "",
            "recipients": "me@test.com",
            "subject": "Test",
            "received_at": "2026-04-07",
            "size_bytes": "100",
            "is_read": "0",
            "is_flagged": "0",
            "attachment_count": "0",
            "local_is_viewed": "0",
            "is_junk": "0",
        ]
        return EmailMessageRecord(row: row)!
    }

    @Test("Strict mode marks all non-shared emails as not visible")
    func strictHidesAll() {
        let filter = EmailSensitivityFilter(level: .strict)
        let email = makeEmail(senderDomain: "example.com")
        #expect(!filter.isVisible(email: email))
    }

    @Test("Moderate hides banking domains")
    func moderateHidesBanking() {
        let filter = EmailSensitivityFilter(level: .moderate)
        let bankEmail = makeEmail(senderDomain: "alerts.bankofamerica.com")
        #expect(!filter.isVisible(email: bankEmail))
    }

    @Test("Moderate hides health domains")
    func moderateHidesHealth() {
        let filter = EmailSensitivityFilter(level: .moderate)
        let healthEmail = makeEmail(senderDomain: "mychart.com")
        #expect(!filter.isVisible(email: healthEmail))
    }

    @Test("Moderate shows regular domains")
    func moderateShowsRegular() {
        let filter = EmailSensitivityFilter(level: .moderate)
        let regularEmail = makeEmail(senderDomain: "colleague.com")
        #expect(filter.isVisible(email: regularEmail))
    }

    @Test("Open hides only 2FA/notification domains")
    func openHides2FA() {
        let filter = EmailSensitivityFilter(level: .open)
        let twoFactorEmail = makeEmail(senderDomain: "noreply.github.com")
        #expect(!filter.isVisible(email: twoFactorEmail))
    }

    @Test("Open shows banking domains")
    func openShowsBanking() {
        let filter = EmailSensitivityFilter(level: .open)
        // fidelity.com is in moderateHidden but not alwaysHidden
        let bankEmail = makeEmail(senderDomain: "fidelity.com")
        #expect(filter.isVisible(email: bankEmail))
    }

    @Test("Default sensitivity is moderate")
    func defaultIsModerate() {
        let filter = EmailSensitivityFilter(rawValue: "unknown")
        #expect(filter.level == .moderate)
    }

    @Test("Raw value construction works for all levels")
    func rawValueConstruction() {
        #expect(EmailSensitivityFilter(rawValue: "strict").level == .strict)
        #expect(EmailSensitivityFilter(rawValue: "moderate").level == .moderate)
        #expect(EmailSensitivityFilter(rawValue: "open").level == .open)
    }

    @Test("Grant stores and loads email sensitivity")
    func grantStoresSensitivity() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-sens-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        let grantStore = GrantStore(db: db)

        let sourceID = try await grantStore.addSource(displayName: "TestSrc", rootPath: tempDir.path)

        let grant = try await grantStore.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [sourceID],
            materializationRoot: tempDir.appendingPathComponent("mat").path,
            emailSensitivity: "strict",
            summaryFraming: "Legal review session"
        )

        #expect(grant.emailSensitivity == "strict")
        #expect(grant.summaryFraming == "Legal review session")

        // Reload from DB
        let reloaded = try await grantStore.grant(id: grant.grantID)
        #expect(reloaded?.emailSensitivity == "strict")
        #expect(reloaded?.summaryFraming == "Legal review session")
    }

    @Test("Default grant sensitivity is moderate")
    func defaultGrantSensitivity() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-sens-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        let grantStore = GrantStore(db: db)

        let sourceID = try await grantStore.addSource(displayName: "TestSrc", rootPath: tempDir.path)

        let grant = try await grantStore.startGrant(
            targetApp: .cowork,
            profileID: "default",
            sourceIDs: [sourceID],
            materializationRoot: tempDir.appendingPathComponent("mat").path
        )

        #expect(grant.emailSensitivity == "moderate")
        #expect(grant.summaryFraming == nil)
    }
}
