// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "mail-provider")

/// Detects the email provider from an email address and determines the best authentication method.
/// Uses a known-provider table first, then falls back to RFC 6186 SRV lookup for unknown domains.
public struct MailProviderDetector: Sendable {

    /// The result of provider detection for an email address.
    public struct DetectionResult: Sendable {
        public let provider: EmailProvider
        public let authMethod: AuthMethod
        public let imapServer: String?
        public let imapPort: UInt16
        public let displayName: String

        /// How the user should authenticate with this provider.
        public enum AuthMethod: String, Sendable {
            case oauth2Google       // Google OAuth2 PKCE → XOAUTH2
            case oauth2Microsoft    // Microsoft OAuth2 PKCE → XOAUTH2
            case appPassword        // iCloud, Gmail fallback: app-specific password
            case password           // Generic IMAP: username + password
        }
    }

    /// Detect the provider from an email address.
    /// Returns a detection result with the provider, recommended auth method, and server info.
    public static func detect(email: String) -> DetectionResult {
        let domain = email.lowercased().components(separatedBy: "@").last ?? ""

        // Known providers with explicit rules
        if let known = knownProviders[domain] ?? matchWildcard(domain: domain) {
            return known
        }

        // Unknown domain — will need RFC 6186 SRV discovery or manual setup
        return DetectionResult(
            provider: .other,
            authMethod: .password,
            imapServer: nil,
            imapPort: 993,
            displayName: "IMAP (\(domain))"
        )
    }

    /// Detect and, for unknown domains, attempt RFC 6186 SRV discovery.
    public static func detectWithDiscovery(email: String) async -> DetectionResult {
        let initial = detect(email: email)

        // If we already know the provider, no discovery needed
        if initial.provider != .other || initial.imapServer != nil {
            return initial
        }

        // Try RFC 6186 SRV lookup for the domain
        let domain = email.lowercased().components(separatedBy: "@").last ?? ""
        if let discovered = await MailDiscoveryService.discoverIMAP(domain: domain) {
            logger.info("SRV discovery found \(discovered.host):\(discovered.port) for \(domain)")
            return DetectionResult(
                provider: .other,
                authMethod: .password,
                imapServer: discovered.host,
                imapPort: discovered.port,
                displayName: "IMAP (\(domain))"
            )
        }

        // Fallback: try common imap.domain.com pattern
        let guessedServer = "imap.\(domain)"
        return DetectionResult(
            provider: .other,
            authMethod: .password,
            imapServer: guessedServer,
            imapPort: 993,
            displayName: "IMAP (\(domain))"
        )
    }

    // MARK: - Known Provider Table

    private static let knownProviders: [String: DetectionResult] = [
        // Google
        "gmail.com": DetectionResult(provider: .gmail, authMethod: .appPassword, imapServer: "imap.gmail.com", imapPort: 993, displayName: "Gmail"),
        "googlemail.com": DetectionResult(provider: .gmail, authMethod: .appPassword, imapServer: "imap.gmail.com", imapPort: 993, displayName: "Gmail"),
        // Microsoft
        "outlook.com": DetectionResult(provider: .outlook, authMethod: .oauth2Microsoft, imapServer: "outlook.office365.com", imapPort: 993, displayName: "Outlook"),
        "hotmail.com": DetectionResult(provider: .outlook, authMethod: .oauth2Microsoft, imapServer: "outlook.office365.com", imapPort: 993, displayName: "Outlook"),
        "live.com": DetectionResult(provider: .outlook, authMethod: .oauth2Microsoft, imapServer: "outlook.office365.com", imapPort: 993, displayName: "Outlook"),
        // iCloud
        "icloud.com": DetectionResult(provider: .icloud, authMethod: .appPassword, imapServer: "imap.mail.me.com", imapPort: 993, displayName: "iCloud Mail"),
        "me.com": DetectionResult(provider: .icloud, authMethod: .appPassword, imapServer: "imap.mail.me.com", imapPort: 993, displayName: "iCloud Mail"),
        "mac.com": DetectionResult(provider: .icloud, authMethod: .appPassword, imapServer: "imap.mail.me.com", imapPort: 993, displayName: "iCloud Mail"),
        // Yahoo
        "yahoo.com": DetectionResult(provider: .yahoo, authMethod: .appPassword, imapServer: "imap.mail.yahoo.com", imapPort: 993, displayName: "Yahoo Mail"),
        "yahoo.co.uk": DetectionResult(provider: .yahoo, authMethod: .appPassword, imapServer: "imap.mail.yahoo.com", imapPort: 993, displayName: "Yahoo Mail"),
        "aol.com": DetectionResult(provider: .yahoo, authMethod: .appPassword, imapServer: "imap.aol.com", imapPort: 993, displayName: "AOL Mail"),
        // Fastmail
        "fastmail.com": DetectionResult(provider: .fastmail, authMethod: .password, imapServer: "imap.fastmail.com", imapPort: 993, displayName: "Fastmail"),
        "fastmail.fm": DetectionResult(provider: .fastmail, authMethod: .password, imapServer: "imap.fastmail.com", imapPort: 993, displayName: "Fastmail"),
    ]

    /// Match wildcard patterns for Google Workspace and Microsoft 365 custom domains.
    /// These can't be in the static table — detected by MX record in a real client,
    /// but here we just handle the most common secondary domains.
    private static func matchWildcard(domain: String) -> DetectionResult? {
        // Google Workspace domains often use google.com MX — but we can't check MX here.
        // Microsoft 365 domains use outlook.com/office365 MX — same limitation.
        // For now, only match the explicit domains above. RFC 6186 SRV handles the rest.
        nil
    }
}
