// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "mail-discovery")

/// Discovers IMAP server settings for domains the provider catalog doesn't know.
///
/// Resolution order follows the Thunderbird autoconfiguration chain:
/// 1. `https://autoconfig.<domain>/mail/config-v1.1.xml` (domain-published)
/// 2. `https://<domain>/.well-known/autoconfig/mail/config-v1.1.xml`
/// 3. Thunderbird ISPDB (`autoconfig.thunderbird.net`, covers most hosted mail)
/// 4. RFC 6186 DNS SRV (`_imaps._tcp.<domain>`)
///
/// Autoconfig sources are not authenticated, so results can suggest a host but
/// must never weaken transport security: only TLS-on-connect (`SSL` socketType)
/// entries are accepted, which also matches the only mode IMAPConnection speaks.
public struct MailDiscoveryService: Sendable {

    /// Discovered IMAP server from autoconfig or DNS SRV.
    public struct IMAPServer: Sendable {
        public let host: String
        public let port: UInt16
        public let priority: UInt16
        /// Autoconfig username template (`%EMAILADDRESS%` or `%EMAILLOCALPART%`)
        /// when the source published one; nil for SRV results.
        public let usernameTemplate: String?

        public init(host: String, port: UInt16, priority: UInt16, usernameTemplate: String? = nil) {
            self.host = host
            self.port = port
            self.priority = priority
            self.usernameTemplate = usernameTemplate
        }
    }

    /// Maximum autoconfig document size; real configs are a few KB.
    private static let maxAutoconfigBytes = 256 * 1024

    /// Per-probe timeout. The chain runs at most four sequential probes during
    /// account setup, so each one must fail fast.
    private static let probeTimeout: TimeInterval = 5

    /// Discover IMAP settings for a domain: autoconfig chain first, SRV last.
    public static func discover(domain: String) async -> IMAPServer? {
        guard isValidDomain(domain) else { return nil }
        for url in autoconfigURLs(domain: domain) {
            if let server = await fetchAutoconfig(url: url) {
                logger.info("Autoconfig found \(server.host):\(server.port) for \(domain) via \(url.host ?? "?")")
                return server
            }
        }
        return await discoverIMAP(domain: domain)
    }

    /// Discover IMAP server for a domain via RFC 6186 DNS SRV lookup.
    /// Returns the highest-priority (lowest value) result, or nil if no SRV record exists.
    public static func discoverIMAP(domain: String) async -> IMAPServer? {
        // RFC 6186: _imaps._tcp.<domain> for IMAP over TLS (port 993)
        let srvName = "_imaps._tcp.\(domain)"
        return await querySRV(name: srvName)
    }

    // MARK: - Autoconfig (Thunderbird config-v1.1 format)

    static func autoconfigURLs(domain: String) -> [URL] {
        [
            "https://autoconfig.\(domain)/mail/config-v1.1.xml",
            "https://\(domain)/.well-known/autoconfig/mail/config-v1.1.xml",
            "https://autoconfig.thunderbird.net/v1.1/\(domain)",
        ].compactMap(URL.init(string:))
    }

    /// Domains come from user-typed email addresses; allow only plain DNS
    /// labels before interpolating into URLs. Internationalized domains fall
    /// through to SRV/guess rather than being percent-mangled here.
    static func isValidDomain(_ domain: String) -> Bool {
        guard domain.count <= 253, domain.contains("."),
              !domain.hasPrefix("."), !domain.hasSuffix("."),
              !domain.hasPrefix("-"), !domain.contains("..") else { return false }
        return domain.allSatisfy { char in
            char.isASCII && (char.isLetter || char.isNumber || char == "." || char == "-")
        }
    }

    private static func fetchAutoconfig(url: URL) async -> IMAPServer? {
        var request = URLRequest(url: url)
        request.timeoutInterval = probeTimeout
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  !data.isEmpty,
                  data.count <= maxAutoconfigBytes else { return nil }
            return parseAutoconfig(xml: data)
        } catch {
            logger.debug("Autoconfig probe failed for \(url.host ?? "?"): \(error.localizedDescription)")
            return nil
        }
    }

    /// Parse a clientConfig XML document and return the first IMAP server that
    /// uses TLS-on-connect. STARTTLS and plaintext entries are rejected.
    static func parseAutoconfig(xml: Data) -> IMAPServer? {
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        let delegate = AutoconfigParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else { return nil }

        for candidate in delegate.servers {
            guard candidate.type.lowercased() == "imap",
                  candidate.socketType.uppercased() == "SSL",
                  let port = candidate.port, port > 0, port <= 65_535,
                  isValidDomain(candidate.hostname)
            else { continue }
            return IMAPServer(
                host: candidate.hostname,
                port: UInt16(port),
                priority: 0,
                usernameTemplate: candidate.username.nilIfEmpty
            )
        }
        return nil
    }

    private final class AutoconfigParserDelegate: NSObject, XMLParserDelegate {
        struct Server {
            var type = ""
            var hostname = ""
            var port: Int?
            var socketType = ""
            var username = ""
        }

        var servers: [Server] = []
        private var current: Server?
        private var text = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            text = ""
            if elementName == "incomingServer" {
                current = Server(type: attributes["type"] ?? "")
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            guard current != nil else { return }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "hostname": current?.hostname = value
            case "port": current?.port = Int(value)
            case "socketType": current?.socketType = value
            case "username": current?.username = value
            case "incomingServer":
                if let server = current { servers.append(server) }
                current = nil
            default: break
            }
        }
    }

    /// Discover submission (SMTP) server for a domain via RFC 6186.
    public static func discoverSMTP(domain: String) async -> IMAPServer? {
        let srvName = "_submission._tcp.\(domain)"
        return await querySRV(name: srvName)
    }

    // MARK: - DNS SRV Query via dnssd

    /// Use the system DNS resolver to look up SRV records.
    /// We shell out to `dig` since Foundation doesn't expose SRV queries directly
    /// and dnssd/CFNetwork SRV APIs are cumbersome for a single lookup.
    private static func querySRV(name: String) async -> IMAPServer? {
        logger.debug("SRV lookup: \(name)")

        // Use nslookup -type=SRV which is available on all macOS
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dig")
        process.arguments = ["+short", "SRV", name]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.warning("SRV dig failed to launch: \(error.localizedDescription)")
            return nil
        }

        // Read result with a timeout
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            logger.debug("SRV dig exited with status \(process.terminationStatus)")
            return nil
        }

        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            logger.debug("No SRV record found for \(name)")
            return nil
        }

        // dig +short SRV format: "priority weight port target"
        // Example: "10 1 993 imap.example.com."
        return parseSRVResponse(output)
    }

    /// Parse dig +short SRV output. Returns the highest-priority (lowest number) result.
    static func parseSRVResponse(_ output: String) -> IMAPServer? {
        var best: IMAPServer?
        var bestPriority: UInt16 = .max

        for line in output.components(separatedBy: .newlines) {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
            guard parts.count >= 4,
                  let priority = UInt16(parts[0]),
                  let port = UInt16(parts[2]) else { continue }

            // Target: remove trailing dot
            var host = String(parts[3])
            if host.hasSuffix(".") { host = String(host.dropLast()) }

            // SRV target "." means "service not available here"
            guard host != "" && host != "." else { continue }

            if priority < bestPriority {
                bestPriority = priority
                best = IMAPServer(host: host, port: port, priority: priority)
            }
        }

        return best
    }
}
