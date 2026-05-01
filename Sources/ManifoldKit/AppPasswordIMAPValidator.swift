// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct AppPasswordIMAPValidator: Sendable {
    public init() {}

    public func validate(
        endpoint: MailEndpoint,
        username: String,
        password: String,
        usernameRule: MailUsernameRule = .fullEmail
    ) async throws -> String {
        guard endpoint.security == .tlsOnConnect else {
            throw IMAPError.connectionFailed("Only TLS-on-connect IMAP validation is supported")
        }
        let candidates = usernameCandidates(username: username, rule: usernameRule)
        var lastError: Error?

        for candidate in candidates {
            let connection = IMAPConnection(
                host: endpoint.host,
                port: UInt16(endpoint.port),
                useTLS: true
            )
            do {
                try await connection.connect()
                try await connection.login(username: candidate, password: password)
                _ = try? await connection.listDetailed()
                await connection.disconnect()
                return candidate
            } catch {
                lastError = error
                await connection.disconnect()
            }
        }

        throw lastError ?? IMAPError.authenticationFailed("Credential validation failed")
    }

    private func usernameCandidates(username: String, rule: MailUsernameRule) -> [String] {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        switch rule {
        case .fullEmail, .userEntered:
            return [trimmed]
        case .localPartThenFullEmailFallback:
            let localPart = trimmed.split(separator: "@", maxSplits: 1).first.map(String.init) ?? trimmed
            return localPart == trimmed ? [trimmed] : [localPart, trimmed]
        }
    }
}
