// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - IMAP Value Types

/// Result of a SELECT command on a mailbox.
public struct SelectResult: Sendable {
    public let exists: Int
    public let recent: Int
    public let uidValidity: UInt32
    public let uidNext: UInt32
    public let flags: Set<String>
    public let readWrite: Bool

    public init(
        exists: Int = 0,
        recent: Int = 0,
        uidValidity: UInt32 = 0,
        uidNext: UInt32 = 0,
        flags: Set<String> = [],
        readWrite: Bool = true
    ) {
        self.exists = exists
        self.recent = recent
        self.uidValidity = uidValidity
        self.uidNext = uidNext
        self.flags = flags
        self.readWrite = readWrite
    }
}

/// A remote mailbox discovered via LIST command.
public struct RemoteMailbox: Sendable {
    public let accountID: String
    public let name: String
    public let delimiter: String
    public let flags: Set<String>

    public var isNoSelect: Bool { flags.contains("\\Noselect") || flags.contains("\\NoSelect") }

    public init(accountID: String, name: String, delimiter: String = "/", flags: Set<String> = []) {
        self.accountID = accountID
        self.name = name
        self.delimiter = delimiter
        self.flags = flags
    }
}

/// Pure-value parser for IMAP server responses.
/// Handles ENVELOPE, FETCH, SEARCH, SELECT, and LIST responses.
/// No side effects — all methods are static and return parsed values.
public struct IMAPParser: Sendable {

    // MARK: - Response Line Classification

    /// Type of an IMAP response line.
    public enum ResponseType: Sendable {
        case untagged(String)            // * ...
        case tagged(String, String, String) // tag status text
        case continuation(String)        // + ...
    }

    /// Classify a single response line.
    public static func classifyLine(_ line: String) -> ResponseType {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("* ") {
            return .untagged(String(trimmed.dropFirst(2)))
        }
        if trimmed.hasPrefix("+ ") || trimmed == "+" {
            return .continuation(String(trimmed.dropFirst(trimmed.hasPrefix("+ ") ? 2 : 1)))
        }
        // Tagged response: TAG STATUS text
        let parts = trimmed.split(separator: " ", maxSplits: 2)
        if parts.count >= 2 {
            let tag = String(parts[0])
            let status = String(parts[1]).uppercased()
            if status == "OK" || status == "NO" || status == "BAD" {
                let text = parts.count > 2 ? String(parts[2]) : ""
                return .tagged(tag, status, text)
            }
        }
        return .untagged(trimmed)
    }

    // MARK: - SELECT Response Parsing

    /// Parse untagged responses from a SELECT command into a SelectResult.
    public static func parseSelectResponses(_ lines: [String]) -> SelectResult {
        var exists = 0
        var recent = 0
        var uidValidity: UInt32 = 0
        var uidNext: UInt32 = 0
        var flags: Set<String> = []
        var readWrite = true

        for line in lines {
            let upper = line.uppercased()

            // * N EXISTS
            if upper.hasSuffix("EXISTS") {
                let parts = line.split(separator: " ")
                if let n = parts.first.flatMap({ Int($0) }) { exists = n }
            }
            // * N RECENT
            else if upper.hasSuffix("RECENT") {
                let parts = line.split(separator: " ")
                if let n = parts.first.flatMap({ Int($0) }) { recent = n }
            }
            // * OK [UIDVALIDITY N]
            else if let val = extractBracketedValue(from: line, key: "UIDVALIDITY") {
                uidValidity = UInt32(val) ?? 0
            }
            // * OK [UIDNEXT N]
            else if let val = extractBracketedValue(from: line, key: "UIDNEXT") {
                uidNext = UInt32(val) ?? 0
            }
            // * FLAGS (\Seen \Answered ...)
            else if upper.hasPrefix("FLAGS ") {
                flags = parseFlags(from: line)
            }
            // * OK [READ-ONLY]
            else if upper.contains("[READ-ONLY]") {
                readWrite = false
            }
        }

        return SelectResult(
            exists: exists, recent: recent,
            uidValidity: uidValidity, uidNext: uidNext,
            flags: flags, readWrite: readWrite
        )
    }

    // MARK: - SEARCH Response Parsing

    /// Parse a SEARCH response line: "SEARCH uid1 uid2 uid3 ..."
    public static func parseSearchResponse(_ line: String) -> [UInt32] {
        let upper = line.uppercased()
        guard upper.hasPrefix("SEARCH") else { return [] }
        let rest = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return [] }
        return rest.split(separator: " ").compactMap { UInt32($0) }
    }

    // MARK: - FETCH Response Parsing

    /// Parsed result from a FETCH response.
    public struct FetchResult: Sendable {
        public var sequenceNumber: Int = 0
        public var uid: UInt32 = 0
        public var flags: Set<String> = []
        public var envelope: EnvelopeData?
        public var bodyData: Data?
        public var rfc822Size: Int = 0
    }

    /// Parsed ENVELOPE data.
    public struct EnvelopeData: Sendable {
        public var date: String = ""
        public var subject: String = ""
        public var from: String = ""
        public var sender: String = ""
        public var replyTo: String = ""
        public var to: String = ""
        public var cc: String = ""
        public var bcc: String = ""
        public var inReplyTo: String = ""
        public var messageID: String = ""
    }

    /// Parse a FETCH response line. Returns the parsed fields.
    /// Input format: "N FETCH (UID 123 FLAGS (\Seen) ENVELOPE (...) RFC822.SIZE 456 BODY[] {789}...)"
    public static func parseFetchResponse(_ line: String, bodyData: Data? = nil) -> FetchResult {
        var result = FetchResult()

        // Extract sequence number
        let parts = line.split(separator: " ", maxSplits: 1)
        if let seqNum = parts.first.flatMap({ Int($0) }) {
            result.sequenceNumber = seqNum
        }

        // Find the parenthesized data section after "FETCH"
        guard let fetchStart = line.range(of: "FETCH (", options: .caseInsensitive) else {
            return result
        }
        let dataSection = String(line[fetchStart.upperBound...])

        // Parse UID
        if let uidRange = dataSection.range(of: "UID ", options: .caseInsensitive) {
            let afterUID = dataSection[uidRange.upperBound...]
            let uidStr = afterUID.prefix(while: { $0.isNumber })
            result.uid = UInt32(uidStr) ?? 0
        }

        // Parse FLAGS
        if let flagsRange = dataSection.range(of: "FLAGS ", options: .caseInsensitive) {
            let afterFlags = String(dataSection[flagsRange.upperBound...])
            result.flags = parseFlags(from: afterFlags)
        }

        // Parse RFC822.SIZE
        if let sizeRange = dataSection.range(of: "RFC822.SIZE ", options: .caseInsensitive) {
            let afterSize = dataSection[sizeRange.upperBound...]
            let sizeStr = afterSize.prefix(while: { $0.isNumber })
            result.rfc822Size = Int(sizeStr) ?? 0
        }

        // Parse ENVELOPE
        if let envRange = dataSection.range(of: "ENVELOPE ", options: .caseInsensitive) {
            let afterEnv = String(dataSection[envRange.upperBound...])
            result.envelope = parseEnvelope(afterEnv)
        }

        // Attach body data if provided (literal data received separately)
        result.bodyData = bodyData

        return result
    }

    // MARK: - ENVELOPE Parsing

    /// Parse an IMAP ENVELOPE structure.
    /// Format: (date subject from sender reply-to to cc bcc in-reply-to message-id)
    /// Each address field is a list of addresses: ((personal NIL user host) ...)
    static func parseEnvelope(_ raw: String) -> EnvelopeData {
        var env = EnvelopeData()

        // Find the outermost parenthesized list
        guard let openParen = raw.firstIndex(of: "(") else { return env }
        let inner = String(raw[raw.index(after: openParen)...])

        // Tokenize the envelope fields
        var parser = ParenParser(input: inner)
        let fields = parser.parseTopLevelFields(count: 10)

        if fields.count > 0 { env.date = unquote(fields[0]) }
        if fields.count > 1 { env.subject = decodeEnvelopeString(fields[1]) }
        if fields.count > 2 { env.from = formatAddressList(fields[2]) }
        if fields.count > 3 { env.sender = formatAddressList(fields[3]) }
        if fields.count > 4 { env.replyTo = formatAddressList(fields[4]) }
        if fields.count > 5 { env.to = formatAddressList(fields[5]) }
        if fields.count > 6 { env.cc = formatAddressList(fields[6]) }
        if fields.count > 7 { env.bcc = formatAddressList(fields[7]) }
        if fields.count > 8 { env.inReplyTo = unquote(fields[8]) }
        if fields.count > 9 { env.messageID = unquote(fields[9]) }

        return env
    }

    // MARK: - LIST Response Parsing

    /// Parse a LIST response: `LIST (\flags) "delimiter" "name"`
    public static func parseListResponse(_ line: String, accountID: String) -> RemoteMailbox? {
        guard line.uppercased().hasPrefix("LIST ") else { return nil }
        let rest = String(line.dropFirst(5))

        // Extract flags
        var flags: Set<String> = []
        if let flagStart = rest.firstIndex(of: "("),
           let flagEnd = rest.firstIndex(of: ")") {
            let flagStr = rest[rest.index(after: flagStart)..<flagEnd]
            flags = Set(flagStr.split(separator: " ").map { String($0) })
        }

        // Extract delimiter and name
        let afterFlags: String
        if let parenEnd = rest.firstIndex(of: ")") {
            afterFlags = String(rest[rest.index(after: parenEnd)...])
                .trimmingCharacters(in: .whitespaces)
        } else {
            afterFlags = rest
        }

        let parts = afterFlags.split(separator: " ", maxSplits: 1)
        let delimiter = parts.first.map { unquote(String($0)) } ?? "/"
        let name = parts.count > 1 ? unquote(String(parts[1])) : ""

        guard !name.isEmpty else { return nil }

        return RemoteMailbox(
            accountID: accountID,
            name: name,
            delimiter: delimiter,
            flags: flags
        )
    }

    // MARK: - Literal Detection

    /// Extract a `UID <n>` data item from a FETCH response fragment.
    /// Servers may order FETCH data items arbitrarily, so in a body fetch the
    /// UID can appear either before the literal or in the remnant after it
    /// (e.g. ` UID 4577)`).
    public static func uidValue(inFetchFragment fragment: String) -> UInt32? {
        guard let uidRange = fragment.range(of: "UID ", options: .caseInsensitive) else { return nil }
        let digits = fragment[uidRange.upperBound...].prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        return UInt32(digits)
    }

    /// Check if a line ends with a literal count: `{N}` and return N.
    public static func literalCount(in line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("}") else { return nil }
        guard let braceStart = trimmed.lastIndex(of: "{") else { return nil }
        let countStr = trimmed[trimmed.index(after: braceStart)..<trimmed.index(before: trimmed.endIndex)]
        return Int(countStr)
    }

    // MARK: - Helpers

    private static func extractBracketedValue(from line: String, key: String) -> String? {
        let pattern = "[\(key) "
        guard let range = line.range(of: pattern, options: .caseInsensitive) else { return nil }
        let afterKey = line[range.upperBound...]
        guard let endBracket = afterKey.firstIndex(of: "]") else { return nil }
        return String(afterKey[..<endBracket])
    }

    static func parseFlags(from text: String) -> Set<String> {
        guard let openParen = text.firstIndex(of: "("),
              let closeParen = text.firstIndex(of: ")") else { return [] }
        let flagStr = text[text.index(after: openParen)..<closeParen]
        return Set(flagStr.split(separator: " ").map { String($0) })
    }

    static func unquote(_ str: String) -> String {
        var s = str.trimmingCharacters(in: .whitespaces)
        if s.uppercased() == "NIL" { return "" }
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            s = String(s.dropFirst().dropLast())
        }
        // Unescape quoted characters
        return s.replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Decode MIME encoded-word (RFC 2047) in envelope strings.
    static func decodeEnvelopeString(_ raw: String) -> String {
        let s = unquote(raw)
        // Simple RFC 2047 decode for =?charset?encoding?text?=
        guard s.contains("=?") else { return s }
        var result = s
        let pattern = try? NSRegularExpression(pattern: "=\\?([^?]+)\\?([BQbq])\\?([^?]*)\\?=")
        if let matches = pattern?.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: s),
                      let charsetRange = Range(match.range(at: 1), in: s),
                      let encodingRange = Range(match.range(at: 2), in: s),
                      let textRange = Range(match.range(at: 3), in: s) else { continue }

                let charset = String(s[charsetRange])
                let encoding = String(s[encodingRange]).uppercased()
                let text = String(s[textRange])

                var decoded: String?
                if encoding == "B" {
                    if let data = Data(base64Encoded: text) {
                        let enc = Self.stringEncoding(for: charset)
                        decoded = String(data: data, encoding: enc)
                    }
                } else if encoding == "Q" {
                    let qpDecoded = text
                        .replacingOccurrences(of: "_", with: " ")
                        .replacingOccurrences(of: "=([0-9A-Fa-f]{2})", with: "", options: .regularExpression)
                    // Simple QP decode
                    var data = Data()
                    var i = qpDecoded.startIndex
                    while i < qpDecoded.endIndex {
                        if qpDecoded[i] == "=" {
                            let hexStart = qpDecoded.index(after: i)
                            if hexStart < qpDecoded.endIndex {
                                let hexEnd = qpDecoded.index(hexStart, offsetBy: 2, limitedBy: qpDecoded.endIndex) ?? qpDecoded.endIndex
                                let hex = String(qpDecoded[hexStart..<hexEnd])
                                if let byte = UInt8(hex, radix: 16) {
                                    data.append(byte)
                                    i = hexEnd
                                    continue
                                }
                            }
                        }
                        data.append(contentsOf: String(qpDecoded[i]).utf8)
                        i = qpDecoded.index(after: i)
                    }
                    let enc = Self.stringEncoding(for: charset)
                    decoded = String(data: data, encoding: enc)
                }

                if let decoded {
                    result = result.replacingCharacters(in: fullRange, with: decoded)
                }
            }
        }
        return result
    }

    private static func stringEncoding(for charset: String) -> String.Encoding {
        switch charset.uppercased() {
        case "UTF-8", "UTF8": return .utf8
        case "ISO-8859-1", "LATIN1": return .isoLatin1
        case "ISO-8859-2": return .isoLatin2
        case "US-ASCII", "ASCII": return .ascii
        case "WINDOWS-1252", "CP1252": return .windowsCP1252
        default: return .utf8
        }
    }

    /// Format an IMAP address list into a human-readable string.
    /// Input: ((personal NIL user host)(personal NIL user host)) or NIL
    static func formatAddressList(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.uppercased() == "NIL" || trimmed.isEmpty { return "" }

        var addresses: [String] = []
        var parser = ParenParser(input: trimmed)

        // The address list is wrapped in outer parens: ((addr1)(addr2))
        guard parser.consumeChar("(") else { return trimmed }

        while parser.peek() == "(" {
            if let addr = parser.parseAddress() {
                addresses.append(addr)
            } else {
                break
            }
        }

        return addresses.joined(separator: ", ")
    }
}

// MARK: - Parenthesized List Parser

/// Utility for parsing IMAP parenthesized lists (ENVELOPEs, address lists).
struct ParenParser {
    var input: String
    var index: String.Index

    init(input: String) {
        self.input = input
        self.index = input.startIndex
    }

    var isAtEnd: Bool { index >= input.endIndex }

    func peek() -> Character? {
        guard !isAtEnd else { return nil }
        return input[index]
    }

    mutating func advance() {
        guard !isAtEnd else { return }
        index = input.index(after: index)
    }

    mutating func skipWhitespace() {
        while !isAtEnd && input[index].isWhitespace {
            advance()
        }
    }

    @discardableResult
    mutating func consumeChar(_ c: Character) -> Bool {
        skipWhitespace()
        guard !isAtEnd && input[index] == c else { return false }
        advance()
        return true
    }

    /// Parse the top-level fields of an ENVELOPE (mix of strings, NILs, and paren-lists).
    mutating func parseTopLevelFields(count: Int) -> [String] {
        var fields: [String] = []
        for _ in 0..<count {
            skipWhitespace()
            guard !isAtEnd else { break }
            if input[index] == "(" {
                // This is a parenthesized list (address list or sub-structure)
                fields.append(consumeParenthesizedList())
            } else if input[index] == "\"" {
                fields.append(consumeQuotedString())
            } else {
                fields.append(consumeAtom())
            }
        }
        return fields
    }

    /// Consume a quoted string: "..."
    mutating func consumeQuotedString() -> String {
        guard consumeChar("\"") else { return "" }
        var result = "\""
        while !isAtEnd {
            let c = input[index]
            if c == "\\" {
                result.append(c)
                advance()
                if !isAtEnd {
                    result.append(input[index])
                    advance()
                }
            } else if c == "\"" {
                result.append(c)
                advance()
                return result
            } else {
                result.append(c)
                advance()
            }
        }
        return result
    }

    /// Consume an atom (unquoted token): NIL, number, etc.
    mutating func consumeAtom() -> String {
        skipWhitespace()
        var result = ""
        while !isAtEnd {
            let c = input[index]
            if c.isWhitespace || c == ")" || c == "(" { break }
            result.append(c)
            advance()
        }
        return result
    }

    /// Consume a parenthesized list including the parens, preserving the raw text.
    mutating func consumeParenthesizedList() -> String {
        guard consumeChar("(") else { return "" }
        var result = "("
        var depth = 1
        while !isAtEnd && depth > 0 {
            let c = input[index]
            result.append(c)
            if c == "(" { depth += 1 }
            else if c == ")" { depth -= 1 }
            else if c == "\"" {
                advance()
                result.append(contentsOf: consumeQuotedStringBody())
                continue
            }
            advance()
        }
        return result
    }

    /// Consume the body of a quoted string (after opening quote), returning content + closing quote.
    private mutating func consumeQuotedStringBody() -> String {
        var result = ""
        while !isAtEnd {
            let c = input[index]
            if c == "\\" {
                result.append(c)
                advance()
                if !isAtEnd {
                    result.append(input[index])
                    advance()
                }
            } else if c == "\"" {
                result.append(c)
                advance()
                return result
            } else {
                result.append(c)
                advance()
            }
        }
        return result
    }

    /// Parse a single IMAP address: (personal NIL user host)
    mutating func parseAddress() -> String? {
        guard consumeChar("(") else { return nil }

        let personal = parseAddressField()
        let _ = parseAddressField() // source route (always NIL)
        let user = parseAddressField()
        let host = parseAddressField()

        consumeChar(")")

        let email = "\(user)@\(host)"
        if !personal.isEmpty && personal.uppercased() != "NIL" {
            return "\(IMAPParser.unquote(personal)) <\(email)>"
        }
        return email
    }

    private mutating func parseAddressField() -> String {
        skipWhitespace()
        guard !isAtEnd else { return "" }
        if input[index] == "\"" {
            return IMAPParser.unquote(consumeQuotedString())
        }
        return IMAPParser.unquote(consumeAtom())
    }
}
