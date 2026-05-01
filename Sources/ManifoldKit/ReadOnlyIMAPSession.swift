// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ReadOnlyIMAPCommand: Sendable, Equatable {
    case capability
    case noop
    case logout
    case namespace
    case list(reference: String, pattern: String)
    case lsub(reference: String, pattern: String)
    case status(mailbox: String, items: String)
    case examine(mailbox: String)
    case uidSearch(criteria: String)
    case uidFetch(uidSet: String, items: String)
    case idle
    case done
    case enableQResync
    case unselect
}

public enum ReadOnlyIMAPCommandError: LocalizedError, Sendable, Equatable {
    case mutatingCommand(String)
    case unsafeFetchItem(String)
    case invalidCommand(String)

    public var errorDescription: String? {
        switch self {
        case .mutatingCommand(let command):
            "IMAP command is not allowed in read-only mail sync: \(command)"
        case .unsafeFetchItem(let item):
            "IMAP FETCH item can mark mail as read and is not allowed: \(item)"
        case .invalidCommand(let command):
            "Invalid IMAP command: \(command)"
        }
    }
}

public enum IMAPCommandBuilder: Sendable {
    public static func build(_ command: ReadOnlyIMAPCommand) throws -> String {
        let raw: String
        switch command {
        case .capability:
            raw = "CAPABILITY"
        case .noop:
            raw = "NOOP"
        case .logout:
            raw = "LOGOUT"
        case .namespace:
            raw = "NAMESPACE"
        case .list(let reference, let pattern):
            raw = "LIST \(reference) \(pattern)"
        case .lsub(let reference, let pattern):
            raw = "LSUB \(reference) \(pattern)"
        case .status(let mailbox, let items):
            raw = "STATUS \(quote(mailbox)) (\(items))"
        case .examine(let mailbox):
            raw = "EXAMINE \(quote(mailbox))"
        case .uidSearch(let criteria):
            raw = "UID SEARCH \(criteria)"
        case .uidFetch(let uidSet, let items):
            raw = "UID FETCH \(uidSet) (\(items))"
        case .idle:
            raw = "IDLE"
        case .done:
            raw = "DONE"
        case .enableQResync:
            raw = "ENABLE QRESYNC"
        case .unselect:
            raw = "UNSELECT"
        }
        try assertReadOnly(raw)
        return raw
    }

    public static func assertReadOnly(_ raw: String) throws {
        let normalized = raw
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ReadOnlyIMAPCommandError.invalidCommand(raw)
        }

        let upper = normalized.uppercased()
        let command = firstCommandToken(in: upper)
        let allowed: Set<String> = [
            "CAPABILITY", "NOOP", "LOGOUT", "NAMESPACE", "LIST", "LSUB",
            "STATUS", "EXAMINE", "UID", "IDLE", "DONE", "ENABLE", "UNSELECT",
        ]
        guard allowed.contains(command) else {
            throw ReadOnlyIMAPCommandError.mutatingCommand(command)
        }
        if command == "UID" {
            guard upper.hasPrefix("UID SEARCH ") || upper.hasPrefix("UID FETCH ") else {
                throw ReadOnlyIMAPCommandError.mutatingCommand(normalized)
            }
            if upper.hasPrefix("UID FETCH ") {
                try assertSafeFetchItems(upper)
            }
        }
        if command == "ENABLE" && upper != "ENABLE QRESYNC" {
            throw ReadOnlyIMAPCommandError.mutatingCommand(normalized)
        }
        if upper.contains(" BODY[") || upper.contains("(BODY[") {
            throw ReadOnlyIMAPCommandError.unsafeFetchItem("BODY[]")
        }
    }

    public static func assertSafeFetchItems(_ rawFetchCommand: String) throws {
        let upper = rawFetchCommand.uppercased()
        if upper.contains("BODY[") && !upper.contains("BODY.PEEK[") {
            throw ReadOnlyIMAPCommandError.unsafeFetchItem("BODY[]")
        }
        for forbidden in [" STORE ", " COPY ", " MOVE ", " APPEND ", " EXPUNGE", " CLOSE", " DELETE ", " CREATE "] {
            if upper.contains(forbidden) {
                throw ReadOnlyIMAPCommandError.mutatingCommand(forbidden.trimmingCharacters(in: .whitespaces))
            }
        }
    }

    private static func firstCommandToken(in raw: String) -> String {
        let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = parts.first else { return raw }
        if first.range(of: #"^[A-Z]\d+$"#, options: .regularExpression) != nil,
           parts.count > 1 {
            return parts[1].split(separator: " ", maxSplits: 1).first.map(String.init) ?? first
        }
        return first
    }

    private static func quote(_ str: String) -> String {
        let clean = str
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let escaped = clean
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

public struct ReadOnlyIMAPSession: Sendable {
    private let connection: IMAPConnection

    public init(connection: IMAPConnection) {
        self.connection = connection
    }

    public func examine(mailbox: String) async throws -> SelectResult {
        try await connection.examine(mailbox: mailbox)
    }

    public func search(criteria: String) async throws -> [UInt32] {
        _ = try IMAPCommandBuilder.build(.uidSearch(criteria: criteria))
        return try await connection.search(criteria: criteria)
    }

    public func fetch(uids: [UInt32], items: String) async throws -> [IMAPParser.FetchResult] {
        guard !uids.isEmpty else { return [] }
        let uidSet = uids.map(String.init).joined(separator: ",")
        _ = try IMAPCommandBuilder.build(.uidFetch(uidSet: uidSet, items: items))
        return try await connection.fetch(uids: uids, items: items)
    }

    public func fetchBody(uid: UInt32) async throws -> Data {
        _ = try IMAPCommandBuilder.build(.uidFetch(uidSet: "\(uid)", items: "BODY.PEEK[]"))
        return try await connection.fetchBody(uid: uid)
    }

    public func fetchBody(uid: UInt32, toFileAt destinationURL: URL) async throws -> Int {
        _ = try IMAPCommandBuilder.build(.uidFetch(uidSet: "\(uid)", items: "BODY.PEEK[]"))
        return try await connection.fetchBody(uid: uid, toFileAt: destinationURL)
    }
}
