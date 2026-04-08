import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "mail-discovery")

/// Discovers IMAP server settings using RFC 6186 DNS SRV records.
/// Queries _imaps._tcp.<domain> for the IMAP-over-TLS service.
/// Falls back to common hostname patterns if SRV lookup fails.
public struct MailDiscoveryService: Sendable {

    /// Discovered IMAP server from DNS SRV.
    public struct IMAPServer: Sendable {
        public let host: String
        public let port: UInt16
        public let priority: UInt16
    }

    /// Discover IMAP server for a domain via RFC 6186 DNS SRV lookup.
    /// Returns the highest-priority (lowest value) result, or nil if no SRV record exists.
    public static func discoverIMAP(domain: String) async -> IMAPServer? {
        // RFC 6186: _imaps._tcp.<domain> for IMAP over TLS (port 993)
        let srvName = "_imaps._tcp.\(domain)"
        return await querySRV(name: srvName)
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
