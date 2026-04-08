import Foundation

/// Filters emails based on domain preset sensitivity level.
/// Used by ManifoldBridge to control which emails are visible to AI agents.
public struct EmailSensitivityFilter: Sendable {

    public enum Level: String, Sendable {
        case strict    // Only shared emails
        case moderate  // Hide banking, health, 2FA domains
        case open      // Hide only 2FA/OTP notification domains
    }

    public let level: Level

    public init(level: Level) {
        self.level = level
    }

    public init(rawValue: String) {
        self.level = Level(rawValue: rawValue) ?? .moderate
    }

    /// Domains always hidden (2FA, OTP, transactional notifications).
    private static let alwaysHiddenDomains: Set<String> = [
        "noreply.github.com",
        "accounts.google.com",
        "account.live.com",
        "verify.stripe.com",
        "no-reply.stripe.com",
        "noreply.apple.com",
        "notifications.amazon.com",
        "donotreply.twilio.com",
        "noreply.duo.com",
        "alerts.bankofamerica.com",
        "notification.chase.com",
        "alerts.wellsfargo.com",
        "notifications.citi.com",
        "alerts.discover.com",
        "noreply.venmo.com",
        "noreply.squareup.com",
    ]

    /// Domains hidden at moderate+ sensitivity (health, insurance, finance internals).
    private static let moderateHiddenDomains: Set<String> = [
        "mychart.com",
        "myhealth.va.gov",
        "express-scripts.com",
        "aetna.com",
        "uhc.com",
        "anthem.com",
        "cigna.com",
        "humana.com",
        "kaiserpermanente.org",
        "fidelity.com",
        "vanguard.com",
        "schwab.com",
        "etrade.com",
        "ameriprise.com",
        "irs.gov",
        "ssa.gov",
    ]

    /// Check if a single email should be visible at this sensitivity level.
    public func isVisible(email: EmailMessageRecord) -> Bool {
        switch level {
        case .strict:
            // Only shared emails are visible. Caller must check shared_emails table.
            return false
        case .moderate:
            let domain = email.senderDomain ?? ""
            let allHidden = Self.alwaysHiddenDomains.union(Self.moderateHiddenDomains)
            return !allHidden.contains(domain)
        case .open:
            let domain = email.senderDomain ?? ""
            return !Self.alwaysHiddenDomains.contains(domain)
        }
    }

    /// All hidden domains for the current sensitivity level.
    public var hiddenDomains: Set<String> {
        switch level {
        case .strict:
            return []  // Not domain-based, uses shared_emails table
        case .moderate:
            return Self.alwaysHiddenDomains.union(Self.moderateHiddenDomains)
        case .open:
            return Self.alwaysHiddenDomains
        }
    }
}
