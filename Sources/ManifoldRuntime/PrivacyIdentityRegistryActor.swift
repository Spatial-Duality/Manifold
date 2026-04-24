// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import ManifoldKit

actor PrivacyIdentityRegistryActor {
    private let store: PrivacyStore
    private let emailStore: EmailStore
    private let grantStore: GrantStore

    private var cachedIdentities: [PrivacyIdentityRecord] = []
    private var cachedAllowlist: [PrivacyOrgAllowEntry] = []
    private var isLoaded = false

    init(store: PrivacyStore, emailStore: EmailStore, grantStore: GrantStore) {
        self.store = store
        self.emailStore = emailStore
        self.grantStore = grantStore
    }

    func refresh() async throws {
        cachedIdentities = try await store.identities(enabledOnly: true)
        cachedAllowlist = try await store.orgAllowlistEntries(enabledOnly: true)
        isLoaded = true
    }

    func identities() async throws -> [PrivacyIdentityRecord] {
        try await ensureLoaded()
        return cachedIdentities
    }

    func allowlist() async throws -> [PrivacyOrgAllowEntry] {
        try await ensureLoaded()
        return cachedAllowlist
    }

    func suggestions() async throws -> [PrivacyIdentitySuggestion] {
        try await refreshSuggestions()
        return try await store.identitySuggestions(status: .pending)
    }

    func acceptSuggestion(id: String) async throws {
        let pending = try await store.identitySuggestions()
        guard let suggestion = pending.first(where: { $0.id == id }) else { return }
        try await store.upsertIdentity(
            PrivacyIdentityRecord(
                kind: suggestion.kind,
                displayName: suggestion.displayName,
                value: suggestion.value,
                normalizedHash: suggestion.normalizedHash,
                matchingMode: .exact
            )
        )
        try await store.updateIdentitySuggestionStatus(id: id, status: .accepted)
        try await refresh()
    }

    func rejectSuggestion(id: String) async throws {
        try await store.updateIdentitySuggestionStatus(id: id, status: .rejected)
    }

    func upsertIdentity(_ identity: PrivacyIdentityRecord) async throws {
        try await store.upsertIdentity(identity)
        try await refresh()
    }

    func upsertAllowEntry(_ entry: PrivacyOrgAllowEntry) async throws {
        try await store.upsertOrgAllowEntry(entry)
        try await refresh()
    }

    func refreshSuggestions() async throws {
        let existingIdentities = try await store.identities()
        let existingSuggestions = try await store.identitySuggestions()
        var knownHashes = Set(existingIdentities.compactMap(\.normalizedHash))
        knownHashes.formUnion(existingSuggestions.compactMap(\.normalizedHash))

        let accounts = try emailStore.allEmailAccounts()
        for account in accounts {
            if let username = account.username?.trimmingCharacters(in: .whitespacesAndNewlines),
               username.contains("@") {
                let hash = Self.normalizedHash(kind: .email, value: username)
                if knownHashes.insert(hash).inserted {
                    try await store.upsertIdentitySuggestion(
                        PrivacyIdentitySuggestion(
                            id: "privacy-suggestion-\(hash.prefix(12))",
                            kind: .email,
                            displayName: account.displayName,
                            value: username,
                            normalizedHash: hash,
                            sourceKind: .emailAccount,
                            sourceRef: account.accountID,
                            confidence: 0.98
                        )
                    )
                }
            }

            let suggestedName = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.looksLikePersonName(suggestedName) {
                let hash = Self.normalizedHash(kind: .personName, value: suggestedName)
                if knownHashes.insert(hash).inserted {
                    try await store.upsertIdentitySuggestion(
                        PrivacyIdentitySuggestion(
                            id: "privacy-suggestion-\(hash.prefix(12))",
                            kind: .personName,
                            displayName: suggestedName,
                            value: suggestedName,
                            normalizedHash: hash,
                            sourceKind: .emailAccount,
                            sourceRef: account.accountID,
                            confidence: 0.62
                        )
                    )
                }
            }
        }

        let sources = try await grantStore.allSources()
        for source in sources {
            let components = URL(fileURLWithPath: source.originalRootPath).pathComponents
            if let userIndex = components.lastIndex(of: "Users"), userIndex + 1 < components.count {
                let rawName = components[userIndex + 1]
                let candidate = rawName
                    .replacingOccurrences(of: ".", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if Self.looksLikePersonName(candidate) {
                    let hash = Self.normalizedHash(kind: .personName, value: candidate)
                    if knownHashes.insert(hash).inserted {
                        try await store.upsertIdentitySuggestion(
                            PrivacyIdentitySuggestion(
                                id: "privacy-suggestion-\(hash.prefix(12))",
                                kind: .personName,
                                displayName: candidate,
                                value: candidate,
                                normalizedHash: hash,
                                sourceKind: .sourceRoot,
                                sourceRef: source.sourceID,
                                confidence: 0.45
                            )
                        )
                    }
                }
            }
        }
    }

    func match(text: String) async throws -> [PrivacyIdentityMatch] {
        try await ensureLoaded()
        var matches: [PrivacyIdentityMatch] = []
        for identity in cachedIdentities where identity.isEnabled {
            matches.append(contentsOf: Self.matches(for: identity, in: text))
        }
        return Array(Set(matches)).sorted {
            if $0.startUTF16 != $1.startUTF16 { return $0.startUTF16 < $1.startUTF16 }
            if $0.endUTF16 != $1.endUTF16 { return $0.endUTF16 < $1.endUTF16 }
            return $0.identityID < $1.identityID
        }
    }

    func matchAllowlist(text: String) async throws -> [PrivacyOrgAllowEntry] {
        try await ensureLoaded()
        let lowercased = text.lowercased()
        return cachedAllowlist.filter { entry in
            guard entry.isEnabled else { return false }
            let pattern = entry.pattern.lowercased()
            switch entry.matchMode {
            case .exact:
                return lowercased.contains(pattern)
            case .contains:
                return lowercased.contains(pattern)
            case .domainSuffix:
                return lowercased.contains("@\(pattern)") || lowercased.contains(pattern)
            }
        }
    }

    private func ensureLoaded() async throws {
        if !isLoaded {
            try await refresh()
        }
    }

    private static func matches(for identity: PrivacyIdentityRecord, in text: String) -> [PrivacyIdentityMatch] {
        switch identity.kind {
        case .phone:
            return phoneMatches(for: identity, in: text)
        default:
            return literalMatches(for: identity, in: text)
        }
    }

    private static func literalMatches(for identity: PrivacyIdentityRecord, in text: String) -> [PrivacyIdentityMatch] {
        let pattern = NSRegularExpression.escapedPattern(for: identity.value)
        let regexPattern: String
        if identity.kind == .personName {
            regexPattern = "\\b\(pattern)\\b"
        } else {
            regexPattern = pattern
        }
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let stringRange = Range(match.range, in: text) else { return nil }
            return PrivacyIdentityMatch(
                identityID: identity.id,
                category: category(for: identity.kind),
                startUTF16: match.range.location,
                endUTF16: match.range.location + match.range.length,
                preview: String(text[stringRange].prefix(64))
            )
        }
    }

    private static func phoneMatches(for identity: PrivacyIdentityRecord, in text: String) -> [PrivacyIdentityMatch] {
        let targetDigits = identity.value.filter(\.isNumber)
        guard !targetDigits.isEmpty,
              let regex = try? NSRegularExpression(pattern: #"(?:\+?\d[\d(). \-]{7,}\d)"#) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let stringRange = Range(match.range, in: text) else { return nil }
            let candidate = String(text[stringRange])
            guard candidate.filter(\.isNumber) == targetDigits else { return nil }
            return PrivacyIdentityMatch(
                identityID: identity.id,
                category: .phone,
                startUTF16: match.range.location,
                endUTF16: match.range.location + match.range.length,
                preview: String(candidate.prefix(64))
            )
        }
    }

    private static func category(for kind: PrivacyIdentityKind) -> PrivacyCategory {
        switch kind {
        case .personName: return .privatePerson
        case .email: return .email
        case .phone: return .phone
        case .address: return .address
        case .accountNumber: return .accountNumber
        case .url: return .url
        case .secret: return .secret
        }
    }

    private static func looksLikePersonName(_ value: String) -> Bool {
        let tokens = value.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty, tokens.count <= 4 else { return false }
        return tokens.allSatisfy { token in
            token.count >= 2 && token.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" }
        }
    }

    private static func normalizedHash(kind: PrivacyIdentityKind, value: String) -> String {
        let normalized: String
        switch kind {
        case .email, .url:
            normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        case .phone:
            normalized = value.filter(\.isNumber)
        case .accountNumber:
            normalized = value.uppercased().filter { $0.isNumber || $0.isLetter }
        case .personName, .address, .secret:
            normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
