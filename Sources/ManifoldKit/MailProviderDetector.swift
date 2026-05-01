// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "mail-provider")

/// Detects the email provider from an email address and determines the best authentication method.
/// The provider catalog is the source of truth; SRV discovery is only a hint for unknown domains.
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
        let candidates = MailProviderCatalog.detectProviders(emailAddress: email)
        guard let providerID = candidates.first,
              providerID != .otherIMAP else {
            let domain = email.lowercased().components(separatedBy: "@").last ?? ""
            return DetectionResult(
                provider: .other,
                authMethod: .password,
                imapServer: nil,
                imapPort: 993,
                displayName: domain.isEmpty ? "IMAP" : "IMAP (\(domain))"
            )
        }

        let profile = MailProviderCatalog.profile(for: providerID)
        let endpoint = profile.imapEndpoint
        return DetectionResult(
            provider: providerID.emailProvider,
            authMethod: authMethod(for: profile.defaultAuthMethod),
            imapServer: endpoint?.host,
            imapPort: UInt16(endpoint?.port ?? 993),
            displayName: profile.displayName
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

    private static func authMethod(for method: MailAuthMethod) -> DetectionResult.AuthMethod {
        switch method {
        case .appPasswordIMAP:
            .appPassword
        case .oauthIMAPXOAUTH2(let profile):
            profile.provider == "microsoft" ? .oauth2Microsoft : .oauth2Google
        case .manualPasswordIMAP:
            .password
        }
    }
}
