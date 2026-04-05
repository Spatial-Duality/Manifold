import Foundation

/// Filters emails based on global auto-rules and user-defined rules.
/// Global rules persist across all profiles (banking, 2FA, healthcare always hidden).
/// Per-profile overrides can relax global rules for specific emails.
public actor EmailFilter {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) throws {
        self.db = db

        try db.execute("""
            CREATE TABLE IF NOT EXISTS email_rules (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                rule_type TEXT NOT NULL,
                pattern TEXT NOT NULL,
                action TEXT NOT NULL DEFAULT 'hide',
                category TEXT,
                is_global INTEGER DEFAULT 1,
                profile_id TEXT,
                created_at TEXT NOT NULL,
                UNIQUE(rule_type, pattern, profile_id)
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS email_cache (
                message_id TEXT PRIMARY KEY,
                account TEXT NOT NULL,
                mailbox TEXT NOT NULL,
                sender TEXT NOT NULL,
                subject TEXT NOT NULL,
                date_received TEXT NOT NULL,
                body_preview TEXT,
                status TEXT NOT NULL DEFAULT 'pending',
                hidden_reason TEXT,
                fetched_at TEXT NOT NULL
            )
        """)

        try db.execute("CREATE INDEX IF NOT EXISTS idx_email_cache_status ON email_cache(status)")

        // Seed default global rules if empty
        let count = try db.queryScalar("SELECT COUNT(*) FROM email_rules WHERE is_global = 1")
        if count == "0" || count == nil {
            try Self.seedDefaultRules(db: db)
        }
    }

    // MARK: - Rule Management

    /// Get all global rules.
    public func globalRules() throws -> [EmailRule] {
        let rows = try db.queryAll("SELECT * FROM email_rules WHERE is_global = 1 ORDER BY category, pattern")
        return rows.compactMap { EmailRule(row: $0) }
    }

    /// Add a global rule.
    public func addGlobalRule(type: RuleType, pattern: String, category: String) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try db.execute("""
            INSERT OR IGNORE INTO email_rules (rule_type, pattern, action, category, is_global, profile_id, created_at)
            VALUES (?, ?, 'hide', ?, 1, NULL, ?)
        """, params: [type.rawValue, pattern, category, now])
    }

    /// Remove a global rule.
    public func removeRule(id: Int) throws {
        try db.execute("DELETE FROM email_rules WHERE id = ?", params: ["\(id)"])
    }

    // MARK: - Email Classification

    /// Classify an email: shared, auto-hidden, or user-hidden.
    public func classify(_ email: CachedEmail) throws -> EmailStatus {
        let rules = try globalRules()

        // Check domain rules
        let senderDomain = extractDomain(from: email.sender)
        for rule in rules where rule.ruleType == .domain {
            if senderDomain.lowercased() == rule.pattern.lowercased() {
                return .autoHidden(reason: rule.category ?? "Domain rule")
            }
        }

        // Check 2FA patterns in subject
        if matches2FA(subject: email.subject, bodyPreview: email.bodyPreview) {
            return .autoHidden(reason: "2FA code")
        }

        // Check sender rules
        for rule in rules where rule.ruleType == .sender {
            if email.sender.lowercased().contains(rule.pattern.lowercased()) {
                return .autoHidden(reason: rule.category ?? "Sender rule")
            }
        }

        // Check keyword rules in subject
        for rule in rules where rule.ruleType == .keyword {
            if email.subject.lowercased().contains(rule.pattern.lowercased()) {
                return .autoHidden(reason: rule.category ?? "Keyword rule")
            }
        }

        return .shared
    }

    /// Classify all cached emails. Returns counts.
    public func classifyAll() throws -> EmailClassificationResult {
        let emails = try allCachedEmails()
        var shared = 0
        var autoHidden = 0
        var reasons: [String: Int] = [:]

        for email in emails {
            let status = try classify(email)
            switch status {
            case .shared:
                shared += 1
                try updateEmailStatus(messageID: email.messageID, status: "shared", reason: nil)
            case .autoHidden(let reason):
                autoHidden += 1
                reasons[reason, default: 0] += 1
                try updateEmailStatus(messageID: email.messageID, status: "auto_hidden", reason: reason)
            case .userHidden:
                // User overrides are already in the cache
                break
            }
        }

        return EmailClassificationResult(
            total: emails.count,
            shared: shared,
            autoHidden: autoHidden,
            reasonBreakdown: reasons
        )
    }

    // MARK: - Email Cache

    /// Cache a fetched email.
    @discardableResult
    public func cacheEmail(_ email: RenderedEmail, account: String, mailbox: String) throws -> String {
        let now = ISO8601DateFormatter().string(from: Date())
        let messageID = email.messageID ?? UUID().uuidString
        let preview = String(email.body.prefix(200))

        try db.execute("""
            INSERT OR REPLACE INTO email_cache (message_id, account, mailbox, sender, subject, date_received, body_preview, status, fetched_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?)
        """, params: [
            messageID,
            account, mailbox,
            email.from, email.subject, email.date,
            preview, now
        ])
        return messageID
    }

    /// Get all cached emails.
    public func allCachedEmails() throws -> [CachedEmail] {
        let rows = try db.queryAll("SELECT * FROM email_cache ORDER BY date_received DESC")
        return rows.compactMap { CachedEmail(row: $0) }
    }

    /// Get only shared (approved) emails.
    public func sharedEmails() throws -> [CachedEmail] {
        let rows = try db.queryAll("SELECT * FROM email_cache WHERE status = 'shared' ORDER BY date_received DESC")
        return rows.compactMap { CachedEmail(row: $0) }
    }

    public func cachedEmail(messageID: String) throws -> CachedEmail? {
        let rows = try db.queryAll(
            "SELECT * FROM email_cache WHERE message_id = ? LIMIT 1",
            params: [messageID]
        )
        return rows.first.flatMap { CachedEmail(row: $0) }
    }

    /// User override: force-include an auto-hidden email.
    public func overrideToShared(messageID: String) throws {
        try updateEmailStatus(messageID: messageID, status: "shared", reason: nil)
    }

    /// User override: manually hide an email.
    public func hideEmail(messageID: String, reason: String = "User hidden") throws {
        try updateEmailStatus(messageID: messageID, status: "user_hidden", reason: reason)
    }

    /// Clear the cache (for re-fetch).
    public func clearCache() throws {
        try db.execute("DELETE FROM email_cache")
    }

    // MARK: - Private

    private func updateEmailStatus(messageID: String, status: String, reason: String?) throws {
        try db.execute(
            "UPDATE email_cache SET status = ?, hidden_reason = ? WHERE message_id = ?",
            params: [status, reason ?? "", messageID]
        )
    }

    private func extractDomain(from email: String) -> String {
        guard let atIndex = email.lastIndex(of: "@") else { return email }
        let domain = email[email.index(after: atIndex)...]
        // Strip angle brackets if present (e.g., "Name <user@domain.com>")
        return domain.trimmingCharacters(in: CharacterSet(charactersIn: "> "))
    }

    private func matches2FA(subject: String, bodyPreview: String?) -> Bool {
        let combined = (subject + " " + (bodyPreview ?? "")).lowercased()
        let patterns = [
            "verification code", "verify your", "login code", "security code",
            "one-time password", "one-time code", "authentication code",
            "2fa", "two-factor", "confirm your identity"
        ]
        for pattern in patterns {
            if combined.contains(pattern) { return true }
        }
        // 6-digit code in subject
        let digitPattern = try? NSRegularExpression(pattern: "\\b\\d{4,8}\\b")
        let subjectLower = subject.lowercased()
        if (subjectLower.contains("code") || subjectLower.contains("verify") || subjectLower.contains("confirm")),
           let regex = digitPattern,
           regex.firstMatch(in: subject, range: NSRange(subject.startIndex..., in: subject)) != nil {
            return true
        }
        return false
    }

    private static func seedDefaultRules(db: DatabaseConnection) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let bankingDomains = [
            "chase.com", "bankofamerica.com", "wellsfargo.com", "citi.com",
            "capitalone.com", "usbank.com", "pnc.com", "tdbank.com",
            "discover.com", "ally.com", "schwab.com", "fidelity.com",
            "vanguard.com", "americanexpress.com", "paypal.com"
        ]
        for domain in bankingDomains {
            try db.execute("""
                INSERT OR IGNORE INTO email_rules (rule_type, pattern, action, category, is_global, created_at)
                VALUES ('domain', ?, 'hide', 'Banking', 1, ?)
            """, params: [domain, now])
        }

        let healthcareDomains = ["mychart.com", "myhealth.va.gov", "patient.info"]
        for domain in healthcareDomains {
            try db.execute("""
                INSERT OR IGNORE INTO email_rules (rule_type, pattern, action, category, is_global, created_at)
                VALUES ('domain', ?, 'hide', 'Healthcare', 1, ?)
            """, params: [domain, now])
        }

        // Government
        for domain in ["irs.gov", "ssa.gov", "state.gov"] {
            try db.execute("""
                INSERT OR IGNORE INTO email_rules (rule_type, pattern, action, category, is_global, created_at)
                VALUES ('domain', ?, 'hide', 'Government', 1, ?)
            """, params: [domain, now])
        }
    }
}

// MARK: - Types

public enum RuleType: String, Sendable {
    case domain
    case sender
    case keyword
}

public enum EmailStatus: Sendable {
    case shared
    case autoHidden(reason: String)
    case userHidden
}

public struct EmailRule: Sendable {
    public let id: Int
    public let ruleType: RuleType
    public let pattern: String
    public let action: String
    public let category: String?
    public let isGlobal: Bool

    init?(row: [String: String]) {
        guard let idStr = row["id"], let id = Int(idStr),
              let typeStr = row["rule_type"], let ruleType = RuleType(rawValue: typeStr),
              let pattern = row["pattern"],
              let action = row["action"] else { return nil }
        self.id = id
        self.ruleType = ruleType
        self.pattern = pattern
        self.action = action
        self.category = row["category"]
        self.isGlobal = row["is_global"] == "1"
    }
}

public struct CachedEmail: Sendable, Identifiable {
    public var id: String { messageID }
    public let messageID: String
    public let account: String
    public let mailbox: String
    public let sender: String
    public let subject: String
    public let dateReceived: String
    public let bodyPreview: String?
    public let status: String
    public let hiddenReason: String?

    public var senderDomain: String {
        guard let atIndex = sender.lastIndex(of: "@") else { return sender }
        return String(sender[sender.index(after: atIndex)...]).trimmingCharacters(in: CharacterSet(charactersIn: "> "))
    }

    public var isShared: Bool { status == "shared" }
    public var isAutoHidden: Bool { status == "auto_hidden" }
    public var isUserHidden: Bool { status == "user_hidden" }

    init?(row: [String: String]) {
        guard let messageID = row["message_id"],
              let account = row["account"],
              let mailbox = row["mailbox"],
              let sender = row["sender"],
              let subject = row["subject"],
              let dateReceived = row["date_received"],
              let status = row["status"] else { return nil }
        self.messageID = messageID
        self.account = account
        self.mailbox = mailbox
        self.sender = sender
        self.subject = subject
        self.dateReceived = dateReceived
        self.bodyPreview = row["body_preview"]
        self.status = status
        self.hiddenReason = row["hidden_reason"].flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct EmailClassificationResult: Sendable {
    public let total: Int
    public let shared: Int
    public let autoHidden: Int
    public let reasonBreakdown: [String: Int]
}
