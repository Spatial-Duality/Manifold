import Testing
import Foundation
@testable import ManifoldKit

@Suite("EmailFilter")
struct EmailFilterTests {
    func makeFilter() throws -> (EmailFilter, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let filter = try EmailFilter(db: db)
        return (filter, tempDir)
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    func makeCachedEmail(sender: String, subject: String, body: String? = nil) -> CachedEmail {
        CachedEmail(row: [
            "message_id": UUID().uuidString,
            "account": "test",
            "mailbox": "INBOX",
            "sender": sender,
            "subject": subject,
            "date_received": "2026-04-03",
            "body_preview": body ?? "",
            "status": "pending",
            "hidden_reason": ""
        ])!
    }

    @Test("Banking domain auto-hidden")
    func bankingDomain() async throws {
        let (filter, tempDir) = try makeFilter()
        defer { cleanup(tempDir) }

        let email = makeCachedEmail(sender: "alerts@chase.com", subject: "Your statement is ready")
        let status = try await filter.classify(email)

        if case .autoHidden(let reason) = status {
            #expect(reason == "Banking")
        } else {
            #expect(Bool(false), "Expected autoHidden, got \(status)")
        }
    }

    @Test("2FA code detected in subject")
    func twoFADetection() async throws {
        let (filter, tempDir) = try makeFilter()
        defer { cleanup(tempDir) }

        let email = makeCachedEmail(sender: "noreply@service.com", subject: "Your verification code is 847291")
        let status = try await filter.classify(email)

        if case .autoHidden(let reason) = status {
            #expect(reason == "2FA code")
        } else {
            #expect(Bool(false), "Expected autoHidden for 2FA")
        }
    }

    @Test("Normal email passes through as shared")
    func normalEmail() async throws {
        let (filter, tempDir) = try makeFilter()
        defer { cleanup(tempDir) }

        let email = makeCachedEmail(sender: "colleague@company.com", subject: "Project update")
        let status = try await filter.classify(email)

        if case .shared = status {
            // pass
        } else {
            #expect(Bool(false), "Expected shared, got \(status)")
        }
    }

    @Test("Custom domain rule hides email")
    func customDomainRule() async throws {
        let (filter, tempDir) = try makeFilter()
        defer { cleanup(tempDir) }

        try await filter.addGlobalRule(type: .domain, pattern: "spam.com", category: "Custom")
        let email = makeCachedEmail(sender: "offer@spam.com", subject: "You won!")
        let status = try await filter.classify(email)

        if case .autoHidden(let reason) = status {
            #expect(reason == "Custom")
        } else {
            #expect(Bool(false), "Expected autoHidden")
        }
    }

    @Test("Override auto-hidden email to shared")
    func overrideToShared() async throws {
        let (filter, tempDir) = try makeFilter()
        defer { cleanup(tempDir) }

        let email = RenderedEmail(
            messageID: "test-override-123",
            from: "alerts@chase.com",
            subject: "Important notice"
        )
        try await filter.cacheEmail(email, account: "test", mailbox: "INBOX")
        _ = try await filter.classifyAll()

        // Should be auto-hidden initially
        let before = try await filter.allCachedEmails()
        #expect(before.first?.isAutoHidden == true)

        // Override
        try await filter.overrideToShared(messageID: "test-override-123")
        let after = try await filter.allCachedEmails()
        #expect(after.first?.isShared == true)
    }

    @Test("Classify all returns correct counts")
    func classifyAllCounts() async throws {
        let (filter, tempDir) = try makeFilter()
        defer { cleanup(tempDir) }

        // Cache some emails
        try await filter.cacheEmail(
            RenderedEmail(messageID: "e1", from: "friend@company.com", subject: "Hello"),
            account: "a", mailbox: "INBOX"
        )
        try await filter.cacheEmail(
            RenderedEmail(messageID: "e2", from: "alerts@chase.com", subject: "Statement"),
            account: "a", mailbox: "INBOX"
        )
        try await filter.cacheEmail(
            RenderedEmail(messageID: "e3", from: "noreply@auth.com", subject: "Your code: 123456"),
            account: "a", mailbox: "INBOX"
        )

        let result = try await filter.classifyAll()
        #expect(result.total == 3)
        #expect(result.shared == 1)
        #expect(result.autoHidden == 2)
    }

    @Test("Default rules are seeded on init")
    func defaultRules() async throws {
        let (filter, tempDir) = try makeFilter()
        defer { cleanup(tempDir) }

        let rules = try await filter.globalRules()
        #expect(rules.count > 10) // Banking + healthcare + government domains
        #expect(rules.contains { $0.pattern == "chase.com" })
    }
}
