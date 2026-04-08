import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "imap")

/// Thread-safe flag for guarding single-resume of continuations.
private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    /// Returns true if this is the first call that sets the flag. Returns false on subsequent calls.
    func testAndSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _value { return false }
        _value = true
        return true
    }
}

/// IMAP client built on Network.framework with TLS support.
/// Manages a single connection to an IMAP server, providing tagged
/// command/response protocol handling.
public actor IMAPConnection {
    private let host: String
    private let port: UInt16
    private let useTLS: Bool
    private var connection: NWConnection?
    private var tagCounter: UInt32 = 0
    private var buffer = Data()
    private nonisolated let commandTimeout: TimeInterval = 30
    private nonisolated let connectTimeout: TimeInterval = 15

    public init(host: String, port: UInt16 = 993, useTLS: Bool = true) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
    }

    // MARK: - Connection Lifecycle

    /// Connect to the IMAP server and wait for the greeting.
    public func connect() async throws {
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!

        let parameters: NWParameters
        if useTLS {
            let tlsOptions = NWProtocolTLS.Options()
            parameters = NWParameters(tls: tlsOptions)
        } else {
            parameters = NWParameters.tcp
        }

        // TCP keepalive
        if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.connectionTimeout = Int(connectTimeout)
        }

        let conn = NWConnection(host: nwHost, port: nwPort, using: parameters)
        self.connection = conn

        logger.info("IMAP connecting to \(self.host):\(self.port) (TLS: \(self.useTLS))")

        // Wait for connection with timeout
        let connQueue = DispatchQueue(label: "com.spatialduality.manifold.imap.\(UUID().uuidString.prefix(8))")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let flag = AtomicFlag()

            // Timeout via GCD timer
            let timer = DispatchSource.makeTimerSource(queue: connQueue)
            timer.schedule(deadline: .now() + self.connectTimeout)
            timer.setEventHandler {
                guard flag.testAndSet() else { return }
                timer.cancel()
                conn.stateUpdateHandler = nil
                conn.cancel()
                logger.error("IMAP connection timed out after \(self.connectTimeout)s")
                continuation.resume(throwing: IMAPError.timeout)
            }
            timer.resume()

            conn.stateUpdateHandler = { [weak conn] state in
                switch state {
                case .ready:
                    guard flag.testAndSet() else { return }
                    timer.cancel()
                    conn?.stateUpdateHandler = nil
                    logger.info("IMAP connection ready")
                    continuation.resume()
                case .failed(let error):
                    guard flag.testAndSet() else { return }
                    timer.cancel()
                    conn?.stateUpdateHandler = nil
                    logger.error("IMAP connection failed: \(error.localizedDescription)")
                    continuation.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                case .waiting(let error):
                    guard flag.testAndSet() else { return }
                    timer.cancel()
                    conn?.stateUpdateHandler = nil
                    logger.error("IMAP connection waiting (likely TLS issue): \(error.localizedDescription)")
                    continuation.resume(throwing: IMAPError.connectionFailed("Connection stalled: \(error.localizedDescription)"))
                case .cancelled:
                    guard flag.testAndSet() else { return }
                    timer.cancel()
                    conn?.stateUpdateHandler = nil
                    continuation.resume(throwing: IMAPError.disconnected)
                case .preparing:
                    logger.debug("IMAP connection preparing...")
                default:
                    break
                }
            }
            conn.start(queue: connQueue)
        }

        // Read server greeting
        logger.debug("IMAP waiting for greeting...")
        let greeting = try await readLine()
        logger.info("IMAP greeting: \(greeting)")
        let classified = IMAPParser.classifyLine(greeting)
        if case .untagged(let text) = classified {
            let upper = text.uppercased()
            guard upper.hasPrefix("OK") else {
                throw IMAPError.serverError("Server rejected connection: \(text)")
            }
        }
    }

    /// Disconnect from the server.
    public func disconnect() {
        connection?.cancel()
        connection = nil
        buffer = Data()
    }

    // MARK: - IMAP Commands

    /// LOGIN with username and password.
    public func login(username: String, password: String) async throws {
        let cmd = "LOGIN \(quote(username)) \(quote(password))"
        logger.info("IMAP LOGIN \(username) ***")
        let (_, status, text) = try await sendCommand(cmd)
        guard status == "OK" else {
            throw IMAPError.authenticationFailed(text)
        }
        logger.info("IMAP LOGIN succeeded")
    }

    /// AUTHENTICATE with XOAUTH2 (for Gmail, Microsoft 365).
    public func authenticateOAuth2(username: String, accessToken: String) async throws {
        let saslString = OAuthManager.xoauth2String(user: username, accessToken: accessToken)
        guard let conn = connection else { throw IMAPError.disconnected }

        let tag = nextTag()
        let fullCommand = "\(tag) AUTHENTICATE XOAUTH2 \(saslString)\r\n"

        try await send(data: Data(fullCommand.utf8), on: conn)
        logger.debug("C: \(tag) AUTHENTICATE XOAUTH2 [redacted]")

        while true {
            let line = try await readLine()
            logger.debug("S: \(line.prefix(200))")

            let classified = IMAPParser.classifyLine(line)
            switch classified {
            case .tagged(let respTag, let status, let text):
                if respTag == tag {
                    guard status == "OK" else {
                        throw IMAPError.authenticationFailed("OAuth2 auth failed: \(text)")
                    }
                    return
                }
            case .continuation(let detail):
                try await send(data: Data("\r\n".utf8), on: conn)
                if let data = Data(base64Encoded: detail),
                   let errorStr = String(data: data, encoding: .utf8) {
                    throw IMAPError.authenticationFailed("OAuth2 rejected: \(errorStr)")
                }
                throw IMAPError.authenticationFailed("OAuth2 authentication rejected")
            case .untagged:
                continue
            }
        }
    }

    /// SELECT a mailbox. Returns parsed SelectResult.
    public func select(mailbox: String) async throws -> SelectResult {
        let cmd = "SELECT \(quote(mailbox))"
        let (untagged, status, text) = try await sendCommand(cmd)
        guard status == "OK" else {
            if text.uppercased().contains("NOT") || text.uppercased().contains("NONEXISTENT") {
                throw IMAPError.mailboxNotFound(mailbox)
            }
            throw IMAPError.serverError("SELECT failed: \(text)")
        }
        return IMAPParser.parseSelectResponses(untagged)
    }

    /// SEARCH for UIDs matching criteria. Returns sorted UIDs.
    public func search(criteria: String) async throws -> [UInt32] {
        let cmd = "UID SEARCH \(criteria)"
        let (untagged, status, text) = try await sendCommand(cmd)
        guard status == "OK" else {
            throw IMAPError.serverError("SEARCH failed: \(text)")
        }

        var uids: [UInt32] = []
        for line in untagged {
            let upper = line.uppercased()
            if upper.hasPrefix("SEARCH") || upper.contains("SEARCH") {
                uids.append(contentsOf: IMAPParser.parseSearchResponse(line))
            }
        }
        return uids.sorted()
    }

    /// FETCH data for specific UIDs. Returns parsed FetchResults.
    public func fetch(uids: [UInt32], items: String) async throws -> [IMAPParser.FetchResult] {
        guard !uids.isEmpty else { return [] }

        let uidSet = uids.map(String.init).joined(separator: ",")
        let cmd = "UID FETCH \(uidSet) (\(items))"

        let (untagged, status, text) = try await sendCommand(cmd)
        guard status == "OK" else {
            throw IMAPError.serverError("FETCH failed: \(text)")
        }

        var results: [IMAPParser.FetchResult] = []
        for line in untagged {
            let upper = line.uppercased()
            if upper.contains("FETCH") {
                let result = IMAPParser.parseFetchResponse(line)
                if result.uid > 0 {
                    results.append(result)
                }
            }
        }
        return results
    }

    /// FETCH the full body for a single UID. Returns the raw message data.
    public func fetchBody(uid: UInt32) async throws -> Data {
        guard let conn = connection else { throw IMAPError.disconnected }

        let tag = nextTag()
        let cmd = "\(tag) UID FETCH \(uid) (BODY.PEEK[])\r\n"

        try await send(data: Data(cmd.utf8), on: conn)
        logger.debug("C: \(tag) UID FETCH \(uid) (BODY.PEEK[])")

        var bodyData: Data?

        while true {
            let line = try await readLine()

            let classified = IMAPParser.classifyLine(line)
            switch classified {
            case .tagged(let respTag, let status, let text):
                if respTag == tag {
                    guard status == "OK" else {
                        throw IMAPError.serverError("FETCH BODY failed: \(text)")
                    }
                    if let data = bodyData {
                        return data
                    }
                    throw IMAPError.unexpectedResponse("No body data in FETCH response")
                }
            case .untagged(let text):
                // Check for literal: {SIZE}\r\n followed by raw bytes
                if let literalSize = IMAPParser.literalCount(in: text) {
                    logger.debug("IMAP reading \(literalSize) byte literal")
                    bodyData = try await readExactly(count: literalSize)
                    // Read the closing paren line
                    _ = try await readLine()
                }
            case .continuation:
                break
            }
        }
    }

    /// LIST mailboxes matching a pattern. Returns parsed mailbox names (not raw LIST lines).
    public func list(reference: String = "\"\"", pattern: String = "\"*\"") async throws -> [String] {
        let cmd = "LIST \(reference) \(pattern)"
        let (untagged, status, text) = try await sendCommand(cmd)
        guard status == "OK" else {
            throw IMAPError.serverError("LIST failed: \(text)")
        }

        // Parse raw LIST responses into mailbox names
        var names: [String] = []
        for line in untagged {
            guard line.uppercased().hasPrefix("LIST ") else { continue }
            // Format: LIST (\flags) "delimiter" "name"
            // Extract the mailbox name (last quoted string, or last token)
            let rest = String(line.dropFirst(5)) // drop "LIST "

            // Skip past flags section: (\flags)
            guard let flagEnd = rest.firstIndex(of: ")") else { continue }
            let afterFlags = String(rest[rest.index(after: flagEnd)...]).trimmingCharacters(in: .whitespaces)

            // Split remaining: "delimiter" "name" (or delimiter name)
            let parts = afterFlags.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let nameRaw = String(parts[1])

            // Unquote if needed
            var name = nameRaw.trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\"") && name.hasSuffix("\"") && name.count >= 2 {
                name = String(name.dropFirst().dropLast())
            }
            guard !name.isEmpty else { continue }
            names.append(name)
        }
        return names
    }

    /// Structured LIST result with flags and delimiter.
    public struct ListEntry: Sendable {
        public let name: String
        public let delimiter: String?
        public let flags: [String]
    }

    /// LIST with full metadata (flags, delimiter) for populating imap_mailboxes.
    public func listDetailed(reference: String = "\"\"", pattern: String = "\"*\"") async throws -> [ListEntry] {
        let cmd = "LIST \(reference) \(pattern)"
        let (untagged, status, text) = try await sendCommand(cmd)
        guard status == "OK" else {
            throw IMAPError.serverError("LIST failed: \(text)")
        }

        var entries: [ListEntry] = []
        for line in untagged {
            guard line.uppercased().hasPrefix("LIST ") else { continue }
            let rest = String(line.dropFirst(5))

            // Parse flags: (\Seen \Flagged)
            var flags: [String] = []
            if let flagStart = rest.firstIndex(of: "("),
               let flagEnd = rest.firstIndex(of: ")") {
                let flagStr = rest[rest.index(after: flagStart)..<flagEnd]
                flags = flagStr.split(separator: " ").map(String.init)
            }

            guard let flagEndIdx = rest.firstIndex(of: ")") else { continue }
            let afterFlags = String(rest[rest.index(after: flagEndIdx)...]).trimmingCharacters(in: .whitespaces)

            let parts = afterFlags.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }

            // Parse delimiter
            var delimStr = String(parts[0]).trimmingCharacters(in: .whitespaces)
            if delimStr.hasPrefix("\"") && delimStr.hasSuffix("\"") && delimStr.count >= 2 {
                delimStr = String(delimStr.dropFirst().dropLast())
            }
            let delimiter: String? = delimStr == "NIL" ? nil : delimStr

            // Parse name
            var name = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\"") && name.hasSuffix("\"") && name.count >= 2 {
                name = String(name.dropFirst().dropLast())
            }
            guard !name.isEmpty else { continue }

            entries.append(ListEntry(name: name, delimiter: delimiter, flags: flags))
        }
        return entries
    }

    /// LOGOUT from the server.
    public func logout() async throws {
        _ = try? await sendCommand("LOGOUT")
        disconnect()
    }

    /// NOOP — keep the connection alive.
    public func noop() async throws {
        let (_, status, text) = try await sendCommand("NOOP")
        guard status == "OK" else {
            throw IMAPError.serverError("NOOP failed: \(text)")
        }
    }

    // MARK: - Tagged Command Protocol

    /// Send a command and collect all responses until the tagged completion.
    private func sendCommand(_ command: String) async throws -> ([String], String, String) {
        guard let conn = connection else { throw IMAPError.disconnected }

        let tag = nextTag()
        let fullCommand = "\(tag) \(command)\r\n"

        try await send(data: Data(fullCommand.utf8), on: conn)
        // Never log commands that carry credentials
        let redacted = command.uppercased().hasPrefix("LOGIN") || command.uppercased().hasPrefix("AUTHENTICATE")
            ? "[REDACTED]"
            : String(command.prefix(80))
        logger.debug("C: \(tag) \(redacted)")

        var untagged: [String] = []

        while true {
            let line = try await readLine()
            logger.debug("S: \(line.prefix(200))")

            let classified = IMAPParser.classifyLine(line)
            switch classified {
            case .tagged(let respTag, let status, let text):
                if respTag == tag {
                    return (untagged, status, text)
                }
                untagged.append(line)
            case .untagged(let text):
                untagged.append(text)
            case .continuation:
                break
            }
        }
    }

    // MARK: - Network I/O

    private func send(data: Data, on conn: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Read a single CRLF-terminated line from the connection.
    private func readLine() async throws -> String {
        while true {
            // Check buffer for a complete line
            if let crlfRange = buffer.range(of: Data("\r\n".utf8)) {
                let lineData = buffer[buffer.startIndex..<crlfRange.lowerBound]
                let endIndex = crlfRange.upperBound
                buffer.removeSubrange(buffer.startIndex..<endIndex)
                return String(data: Data(lineData), encoding: .utf8) ?? ""
            }

            // Need more data
            let chunk = try await readChunk()
            buffer.append(chunk)
        }
    }

    /// Read exactly N bytes from the connection.
    private func readExactly(count: Int) async throws -> Data {
        while buffer.count < count {
            let chunk = try await readChunk()
            buffer.append(chunk)
        }
        let data = buffer.prefix(count)
        buffer.removeFirst(count)
        return Data(data)
    }

    /// Read a chunk of data from the connection with timeout.
    private func readChunk() async throws -> Data {
        guard let conn = connection else { throw IMAPError.disconnected }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let flag = AtomicFlag()
            let timeoutSeconds = self.commandTimeout

            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            timer.schedule(deadline: .now() + timeoutSeconds)
            timer.setEventHandler {
                guard flag.testAndSet() else { return }
                timer.cancel()
                logger.warning("IMAP read timed out after \(timeoutSeconds)s")
                continuation.resume(throwing: IMAPError.timeout)
            }
            timer.resume()

            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                guard flag.testAndSet() else { return }
                timer.cancel()

                if let error {
                    logger.error("IMAP read error: \(error.localizedDescription)")
                    continuation.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                } else if let data = content, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    logger.info("IMAP connection closed by server")
                    continuation.resume(throwing: IMAPError.disconnected)
                } else {
                    continuation.resume(throwing: IMAPError.disconnected)
                }
            }
        }
    }

    // MARK: - Helpers

    private func nextTag() -> String {
        tagCounter += 1
        return String(format: "M%04d", tagCounter)
    }

    private func quote(_ str: String) -> String {
        // Strip CR/LF — these MUST NOT appear inside an IMAP quoted string
        // (they'd split the command across protocol lines).
        let clean = str
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let escaped = clean
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
