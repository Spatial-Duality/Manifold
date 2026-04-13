// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Errors specific to IMAP operations.
public enum IMAPError: Error, LocalizedError, Sendable {
    case connectionFailed(String)
    case authenticationFailed(String)
    case mailboxNotFound(String)
    case unexpectedResponse(String)
    case timeout
    case serverError(String)
    case disconnected
    case protocolError(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): "IMAP connection failed: \(msg)"
        case .authenticationFailed(let msg): "IMAP authentication failed: \(msg)"
        case .mailboxNotFound(let name): "Mailbox not found: \(name)"
        case .unexpectedResponse(let msg): "Unexpected IMAP response: \(msg)"
        case .timeout: "IMAP operation timed out"
        case .serverError(let msg): "IMAP server error: \(msg)"
        case .disconnected: "IMAP connection lost"
        case .protocolError(let msg): "IMAP protocol error: \(msg)"
        }
    }
}
