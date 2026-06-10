// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("Mail discovery")
struct MailDiscoveryServiceTests {
    @Test("Autoconfig parser picks the TLS-on-connect IMAP server")
    func parsesISPDBConfig() {
        let xml = """
        <?xml version="1.0"?>
        <clientConfig version="1.1">
          <emailProvider id="customdomain.co">
            <domain>customdomain.co</domain>
            <incomingServer type="pop3">
              <hostname>pop.customdomain.co</hostname>
              <port>995</port>
              <socketType>SSL</socketType>
            </incomingServer>
            <incomingServer type="imap">
              <hostname>imap.customdomain.co</hostname>
              <port>993</port>
              <socketType>SSL</socketType>
              <authentication>password-cleartext</authentication>
              <username>%EMAILADDRESS%</username>
            </incomingServer>
          </emailProvider>
        </clientConfig>
        """
        let server = MailDiscoveryService.parseAutoconfig(xml: Data(xml.utf8))
        #expect(server?.host == "imap.customdomain.co")
        #expect(server?.port == 993)
        #expect(server?.usernameTemplate == "%EMAILADDRESS%")
    }

    @Test("Autoconfig parser rejects STARTTLS and plaintext entries")
    func rejectsNonTLSConfigs() {
        let xml = """
        <clientConfig version="1.1">
          <emailProvider id="legacy.example">
            <incomingServer type="imap">
              <hostname>imap.legacy.example</hostname>
              <port>143</port>
              <socketType>STARTTLS</socketType>
            </incomingServer>
            <incomingServer type="imap">
              <hostname>imap2.legacy.example</hostname>
              <port>143</port>
              <socketType>plain</socketType>
            </incomingServer>
          </emailProvider>
        </clientConfig>
        """
        #expect(MailDiscoveryService.parseAutoconfig(xml: Data(xml.utf8)) == nil)
    }

    @Test("Autoconfig parser rejects malformed documents and bad hostnames")
    func rejectsGarbage() {
        #expect(MailDiscoveryService.parseAutoconfig(xml: Data("<html><body>404</body></html>".utf8)) == nil)
        #expect(MailDiscoveryService.parseAutoconfig(xml: Data("not xml at all".utf8)) == nil)
        let badHost = """
        <clientConfig><emailProvider>
          <incomingServer type="imap">
            <hostname>evil host!</hostname><port>993</port><socketType>SSL</socketType>
          </incomingServer>
        </emailProvider></clientConfig>
        """
        #expect(MailDiscoveryService.parseAutoconfig(xml: Data(badHost.utf8)) == nil)
    }

    @Test("Domain validation guards URL construction")
    func domainValidation() {
        #expect(MailDiscoveryService.isValidDomain("customdomain.co"))
        #expect(MailDiscoveryService.isValidDomain("mail.sub-domain.example.org"))
        #expect(!MailDiscoveryService.isValidDomain("nodots"))
        #expect(!MailDiscoveryService.isValidDomain(".leading.dot"))
        #expect(!MailDiscoveryService.isValidDomain("trailing.dot."))
        #expect(!MailDiscoveryService.isValidDomain("sp ace.com"))
        #expect(!MailDiscoveryService.isValidDomain("host/../path.com"))
        #expect(!MailDiscoveryService.isValidDomain("münchen.de"))
        #expect(!MailDiscoveryService.isValidDomain("a..b.com"))
    }

    @Test("Autoconfig URL chain queries domain sources before ISPDB")
    func autoconfigURLOrder() {
        let urls = MailDiscoveryService.autoconfigURLs(domain: "customdomain.co").map(\.absoluteString)
        #expect(urls == [
            "https://autoconfig.customdomain.co/mail/config-v1.1.xml",
            "https://customdomain.co/.well-known/autoconfig/mail/config-v1.1.xml",
            "https://autoconfig.thunderbird.net/v1.1/customdomain.co",
        ])
    }
}
