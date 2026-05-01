// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("Mail Provider Catalog")
struct MailProviderCatalogTests {
    @Test("Detects primary providers from known domains")
    func detectsKnownDomains() {
        #expect(MailProviderCatalog.detectProviders(emailAddress: "person@gmail.com") == [.gmail])
        #expect(MailProviderCatalog.detectProviders(emailAddress: "person@googlemail.com") == [.gmail])
        #expect(MailProviderCatalog.detectProviders(emailAddress: "person@outlook.com") == [.microsoft])
        #expect(MailProviderCatalog.detectProviders(emailAddress: "person@hotmail.com") == [.microsoft])
        #expect(MailProviderCatalog.detectProviders(emailAddress: "person@icloud.com") == [.iCloud])
        #expect(MailProviderCatalog.detectProviders(emailAddress: "person@me.com") == [.iCloud])
        #expect(MailProviderCatalog.detectProviders(emailAddress: "person@yahoo.com") == [.yahoo])
        #expect(MailProviderCatalog.detectProviders(emailAddress: "person@ymail.com") == [.yahoo])
        #expect(MailProviderCatalog.detectProviders(emailAddress: "person@fastmail.com") == [.fastmail])
    }

    @Test("Unknown custom domains return ranked choices without forcing provider")
    func customDomainDetectionIsAmbiguous() {
        let candidates = MailProviderCatalog.detectProviders(emailAddress: "person@example.org")
        #expect(candidates == [.gmail, .microsoft, .fastmail, .otherIMAP])
    }

    @Test("Gmail uses app password and does not expose OAuth as normal path")
    func gmailUsesAppPassword() {
        let profile = MailProviderCatalog.profile(for: MailProviderID.gmail)
        #expect(profile.imapEndpoint == MailEndpoint(host: "imap.gmail.com", port: 993))
        #expect(profile.defaultAuthMethod == MailAuthMethod.appPasswordIMAP)
        #expect(!profile.authMethods.contains {
            if case .oauthIMAPXOAUTH2 = $0 { true } else { false }
        })
    }

    @Test("Microsoft uses OAuth IMAP profile")
    func microsoftUsesOAuth() {
        let profile = MailProviderCatalog.profile(for: MailProviderID.microsoft)
        #expect(profile.imapEndpoint == MailEndpoint(host: "outlook.office365.com", port: 993))
        guard case .oauthIMAPXOAUTH2(let oauth) = profile.defaultAuthMethod else {
            Issue.record("Expected Microsoft OAuth IMAP")
            return
        }
        #expect(oauth.scopes.contains("offline_access"))
        #expect(oauth.scopes.contains("https://outlook.office.com/IMAP.AccessAsUser.All"))
        #expect(oauth.requiresPKCE)
        #expect(oauth.clientIDConfigKey == "MicrosoftClientID")
    }

    @Test("Legacy detector now follows provider catalog")
    func legacyDetectorUsesCatalog() {
        let gmail = MailProviderDetector.detect(email: "person@gmail.com")
        #expect(gmail.provider == .gmail)
        #expect(gmail.authMethod == .appPassword)
        #expect(gmail.imapServer == "imap.gmail.com")

        let fastmail = MailProviderDetector.detect(email: "person@fastmail.com")
        #expect(fastmail.provider == .fastmail)
        #expect(fastmail.authMethod == .appPassword)

        let microsoft = MailProviderDetector.detect(email: "person@outlook.com")
        #expect(microsoft.provider == .outlook)
        #expect(microsoft.authMethod == .oauth2Microsoft)
    }
}
