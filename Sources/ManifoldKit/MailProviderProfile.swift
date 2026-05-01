// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum MailProviderID: String, Codable, Sendable, CaseIterable {
    case gmail
    case microsoft
    case iCloud
    case yahoo
    case fastmail
    case otherIMAP

    public var emailProvider: EmailProvider {
        switch self {
        case .gmail: .gmail
        case .microsoft: .outlook
        case .iCloud: .icloud
        case .yahoo: .yahoo
        case .fastmail: .fastmail
        case .otherIMAP: .other
        }
    }
}

public enum MailTransportSecurity: String, Codable, Sendable, Equatable {
    case tlsOnConnect
    case startTLS
    case insecureDisallowed
}

public struct MailEndpoint: Codable, Sendable, Equatable {
    public let host: String
    public let port: Int
    public let security: MailTransportSecurity

    public init(host: String, port: Int, security: MailTransportSecurity = .tlsOnConnect) {
        self.host = host
        self.port = port
        self.security = security
    }
}

public enum OAuthRedirectURIKind: Codable, Sendable, Equatable {
    case customScheme
    case localhost
}

public struct OAuthProviderProfile: Codable, Sendable, Equatable {
    public let provider: String
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let scopes: [String]
    public let redirectURIKind: OAuthRedirectURIKind
    public let requiresPKCE: Bool
    public let clientIDConfigKey: String

    public init(
        provider: String,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        scopes: [String],
        redirectURIKind: OAuthRedirectURIKind,
        requiresPKCE: Bool,
        clientIDConfigKey: String
    ) {
        self.provider = provider
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.scopes = scopes
        self.redirectURIKind = redirectURIKind
        self.requiresPKCE = requiresPKCE
        self.clientIDConfigKey = clientIDConfigKey
    }
}

public enum MailAuthMethod: Codable, Sendable, Equatable {
    case appPasswordIMAP
    case oauthIMAPXOAUTH2(OAuthProviderProfile)
    case manualPasswordIMAP
}

public enum MailUsernameRule: Codable, Sendable, Equatable {
    case fullEmail
    case localPartThenFullEmailFallback
    case userEntered
}

public struct MailSetupInstructions: Codable, Sendable, Equatable {
    public let title: String
    public let steps: [String]
    public let trustCopy: String

    public init(title: String, steps: [String], trustCopy: String = MailProviderCatalog.defaultTrustCopy) {
        self.title = title
        self.steps = steps
        self.trustCopy = trustCopy
    }
}

public struct MailboxProviderRules: Codable, Sendable, Equatable {
    public let preferAllMailForArchive: Bool
    public let syncInboxFirst: Bool
    public let optionalSpamAndTrash: Bool
    public let duplicateCanonicalMailboxNames: Set<String>

    public init(
        preferAllMailForArchive: Bool = false,
        syncInboxFirst: Bool = true,
        optionalSpamAndTrash: Bool = true,
        duplicateCanonicalMailboxNames: Set<String> = []
    ) {
        self.preferAllMailForArchive = preferAllMailForArchive
        self.syncInboxFirst = syncInboxFirst
        self.optionalSpamAndTrash = optionalSpamAndTrash
        self.duplicateCanonicalMailboxNames = duplicateCanonicalMailboxNames
    }
}

public struct MessageIdentityRules: Codable, Sendable, Equatable {
    public let useGmailMessageID: Bool
    public let useRFCMessageID: Bool
    public let fallbackToContentID: Bool

    public init(
        useGmailMessageID: Bool = false,
        useRFCMessageID: Bool = true,
        fallbackToContentID: Bool = true
    ) {
        self.useGmailMessageID = useGmailMessageID
        self.useRFCMessageID = useRFCMessageID
        self.fallbackToContentID = fallbackToContentID
    }
}

public struct MailProviderErrorRule: Codable, Sendable, Equatable {
    public let code: String
    public let userMessage: String

    public init(code: String, userMessage: String) {
        self.code = code
        self.userMessage = userMessage
    }
}

public struct MailProviderProfile: Codable, Sendable, Equatable {
    public let id: MailProviderID
    public let displayName: String
    public let primaryDomains: [String]
    public let domainHints: [String]
    public let imapEndpoint: MailEndpoint?
    public let authMethods: [MailAuthMethod]
    public let defaultAuthMethod: MailAuthMethod
    public let usernameRule: MailUsernameRule
    public let setupInstructions: MailSetupInstructions
    public let expectedCapabilities: Set<String>
    public let mailboxRules: MailboxProviderRules
    public let messageIdentityRules: MessageIdentityRules
    public let errorRules: [MailProviderErrorRule]
    public let revocationInstructions: String

    public init(
        id: MailProviderID,
        displayName: String,
        primaryDomains: [String],
        domainHints: [String] = [],
        imapEndpoint: MailEndpoint?,
        authMethods: [MailAuthMethod],
        defaultAuthMethod: MailAuthMethod,
        usernameRule: MailUsernameRule,
        setupInstructions: MailSetupInstructions,
        expectedCapabilities: Set<String> = [],
        mailboxRules: MailboxProviderRules = MailboxProviderRules(),
        messageIdentityRules: MessageIdentityRules = MessageIdentityRules(),
        errorRules: [MailProviderErrorRule] = [],
        revocationInstructions: String
    ) {
        self.id = id
        self.displayName = displayName
        self.primaryDomains = primaryDomains
        self.domainHints = domainHints
        self.imapEndpoint = imapEndpoint
        self.authMethods = authMethods
        self.defaultAuthMethod = defaultAuthMethod
        self.usernameRule = usernameRule
        self.setupInstructions = setupInstructions
        self.expectedCapabilities = expectedCapabilities
        self.mailboxRules = mailboxRules
        self.messageIdentityRules = messageIdentityRules
        self.errorRules = errorRules
        self.revocationInstructions = revocationInstructions
    }
}

public enum MailProviderCatalog: Sendable {
    public static let defaultTrustCopy = """
    Manifold connects directly to your mail provider from this Mac.
    No Manifold cloud mail sync is used.
    Your password or OAuth token is stored in macOS Keychain.
    Your mail archive is stored locally on this Mac.
    Canonical mail blobs are encrypted.
    Manifold will not send, delete, move, archive, or mark mail as read.
    AI access is off by default and must be explicitly granted.
    Readable .eml files and attachments are only created through explicit export.
    """

    public static let microsoftOAuth = OAuthProviderProfile(
        provider: "microsoft",
        authorizationEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
        tokenEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
        scopes: [
            "offline_access",
            "https://outlook.office.com/IMAP.AccessAsUser.All",
        ],
        redirectURIKind: .customScheme,
        requiresPKCE: true,
        clientIDConfigKey: "MicrosoftClientID"
    )

    public static let profiles: [MailProviderProfile] = [
        MailProviderProfile(
            id: .gmail,
            displayName: "Gmail",
            primaryDomains: ["gmail.com", "googlemail.com"],
            imapEndpoint: MailEndpoint(host: "imap.gmail.com", port: 993),
            authMethods: [.appPasswordIMAP],
            defaultAuthMethod: .appPasswordIMAP,
            usernameRule: .fullEmail,
            setupInstructions: MailSetupInstructions(
                title: "Connect Gmail with an app password",
                steps: [
                    "Turn on 2-Step Verification for your Google Account.",
                    "Create a Google app password named Manifold.",
                    "Paste the app password here. Manifold stores it in Keychain only after validation.",
                ]
            ),
            expectedCapabilities: ["IMAP4REV1", "IDLE"],
            mailboxRules: MailboxProviderRules(
                preferAllMailForArchive: true,
                duplicateCanonicalMailboxNames: ["[gmail]/all mail", "[gmail]/important", "[gmail]/starred"]
            ),
            messageIdentityRules: MessageIdentityRules(useGmailMessageID: true),
            errorRules: [
                MailProviderErrorRule(code: "auth_failed", userMessage: "The Gmail app password may be wrong, revoked, or pasted with spaces."),
                MailProviderErrorRule(code: "app_password_unavailable", userMessage: "Google app passwords require 2-Step Verification and may be unavailable for some organization, security-key-only, or Advanced Protection accounts."),
            ],
            revocationInstructions: "Revoke the Manifold app password from your Google Account security settings."
        ),
        MailProviderProfile(
            id: .microsoft,
            displayName: "Outlook / Microsoft 365",
            primaryDomains: ["outlook.com", "hotmail.com", "live.com", "msn.com"],
            imapEndpoint: MailEndpoint(host: "outlook.office365.com", port: 993),
            authMethods: [.oauthIMAPXOAUTH2(microsoftOAuth)],
            defaultAuthMethod: .oauthIMAPXOAUTH2(microsoftOAuth),
            usernameRule: .fullEmail,
            setupInstructions: MailSetupInstructions(
                title: "Connect Microsoft mail with OAuth",
                steps: [
                    "Manifold opens Microsoft sign-in in your browser.",
                    "Manifold receives an OAuth token for IMAP mail access and stores it in Keychain.",
                    "Some work or school tenants require administrator approval or may disable IMAP.",
                ]
            ),
            expectedCapabilities: ["IMAP4REV1", "AUTH=XOAUTH2"],
            errorRules: [
                MailProviderErrorRule(code: "invalid_client", userMessage: "This build is missing or has an invalid Microsoft OAuth client ID or redirect URI."),
                MailProviderErrorRule(code: "admin_consent_required", userMessage: "This Microsoft 365 tenant requires administrator approval for third-party apps."),
                MailProviderErrorRule(code: "imap_disabled", userMessage: "IMAP is disabled for this mailbox or tenant."),
            ],
            revocationInstructions: "Revoke Manifold from your Microsoft account or organization app permissions."
        ),
        MailProviderProfile(
            id: .iCloud,
            displayName: "iCloud Mail",
            primaryDomains: ["icloud.com", "me.com", "mac.com"],
            imapEndpoint: MailEndpoint(host: "imap.mail.me.com", port: 993),
            authMethods: [.appPasswordIMAP],
            defaultAuthMethod: .appPasswordIMAP,
            usernameRule: .localPartThenFullEmailFallback,
            setupInstructions: MailSetupInstructions(
                title: "Connect iCloud Mail with an app-specific password",
                steps: [
                    "Create an Apple app-specific password for Manifold.",
                    "Manifold first tries your iCloud username without the domain, then the full email address if needed.",
                    "The app-specific password is stored in Keychain only after validation.",
                ]
            ),
            expectedCapabilities: ["IMAP4REV1", "IDLE"],
            errorRules: [
                MailProviderErrorRule(code: "auth_failed", userMessage: "The iCloud app-specific password may be wrong, revoked, or the username form may need to change."),
            ],
            revocationInstructions: "Revoke the Manifold app-specific password from your Apple Account settings."
        ),
        MailProviderProfile(
            id: .yahoo,
            displayName: "Yahoo Mail",
            primaryDomains: ["yahoo.com", "ymail.com", "rocketmail.com", "yahoo.co.uk"],
            imapEndpoint: MailEndpoint(host: "imap.mail.yahoo.com", port: 993),
            authMethods: [.appPasswordIMAP],
            defaultAuthMethod: .appPasswordIMAP,
            usernameRule: .fullEmail,
            setupInstructions: MailSetupInstructions(
                title: "Connect Yahoo Mail with an app password",
                steps: [
                    "Create a Yahoo app password for Manifold.",
                    "Paste it here. Manifold stores it in Keychain only after validation.",
                    "Yahoo app-password eligibility may vary by account.",
                ]
            ),
            expectedCapabilities: ["IMAP4REV1"],
            errorRules: [
                MailProviderErrorRule(code: "auth_failed", userMessage: "The Yahoo app password may be wrong, revoked, or unavailable for this account."),
            ],
            revocationInstructions: "Revoke the Manifold app password from your Yahoo account security settings."
        ),
        MailProviderProfile(
            id: .fastmail,
            displayName: "Fastmail",
            primaryDomains: ["fastmail.com", "fastmail.fm"],
            domainHints: ["fastmailusercontent.com"],
            imapEndpoint: MailEndpoint(host: "imap.fastmail.com", port: 993),
            authMethods: [.appPasswordIMAP],
            defaultAuthMethod: .appPasswordIMAP,
            usernameRule: .fullEmail,
            setupInstructions: MailSetupInstructions(
                title: "Connect Fastmail with an app password",
                steps: [
                    "Create a Fastmail app password for Manifold.",
                    "Prefer a mail-only app password if your account offers scoped access.",
                    "Manifold stores it in Keychain only after validation.",
                ]
            ),
            expectedCapabilities: ["IMAP4REV1", "IDLE"],
            errorRules: [
                MailProviderErrorRule(code: "auth_failed", userMessage: "Fastmail requires an app password for third-party IMAP access."),
            ],
            revocationInstructions: "Revoke the Manifold app password from your Fastmail password settings."
        ),
        MailProviderProfile(
            id: .otherIMAP,
            displayName: "Other IMAP",
            primaryDomains: [],
            imapEndpoint: nil,
            authMethods: [.manualPasswordIMAP],
            defaultAuthMethod: .manualPasswordIMAP,
            usernameRule: .userEntered,
            setupInstructions: MailSetupInstructions(
                title: "Connect a manual IMAP account",
                steps: [
                    "Enter your IMAP host, TLS port, username, and password or app password.",
                    "Plain insecure IMAP is disabled unless you enable an advanced local exception.",
                    "Manifold stores the credential in Keychain only after validation.",
                ]
            ),
            expectedCapabilities: ["IMAP4REV1"],
            revocationInstructions: "Revoke the password or app password from your mail provider."
        ),
    ]

    public static func profile(for id: MailProviderID) -> MailProviderProfile {
        profiles.first { $0.id == id }!
    }

    public static func profile(for provider: EmailProvider) -> MailProviderProfile {
        switch provider {
        case .gmail: profile(for: MailProviderID.gmail)
        case .outlook: profile(for: MailProviderID.microsoft)
        case .icloud: profile(for: MailProviderID.iCloud)
        case .yahoo: profile(for: MailProviderID.yahoo)
        case .fastmail: profile(for: MailProviderID.fastmail)
        case .other: profile(for: MailProviderID.otherIMAP)
        }
    }

    public static func detectProviders(emailAddress: String) -> [MailProviderID] {
        let domain = emailAddress
            .lowercased()
            .split(separator: "@")
            .last
            .map(String.init) ?? ""
        guard !domain.isEmpty else {
            return [.gmail, .microsoft, .iCloud, .yahoo, .fastmail, .otherIMAP]
        }

        if let exact = profiles.first(where: { $0.primaryDomains.contains(domain) }) {
            return [exact.id]
        }
        if let hinted = profiles.first(where: { profile in
            profile.domainHints.contains { domain.hasSuffix($0) }
        }) {
            return [hinted.id, .otherIMAP]
        }
        return [.gmail, .microsoft, .fastmail, .otherIMAP]
    }
}
