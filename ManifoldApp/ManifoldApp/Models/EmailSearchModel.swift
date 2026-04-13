// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Model for token-based email search.
@Observable
@MainActor
final class EmailSearchModel {
    /// Structured search tokens (From:, Domain:, Subject:, etc).
    var tokens: [SearchToken] = []
    /// Free text search query.
    var freeText: String = ""
    /// Whether the search field is active/focused.
    var isSearching: Bool = false
    /// Search results (replaces message list when non-empty).
    var results: [EmailMessageRecord] = []

    /// Whether search is currently active (has tokens or text).
    var isActive: Bool {
        !tokens.isEmpty || !freeText.isEmpty
    }

    /// Add a structured search token.
    func addToken(_ token: SearchToken) {
        // Don't add duplicate tokens
        guard !tokens.contains(where: { $0.type == token.type && $0.value == token.value }) else { return }
        tokens.append(token)
    }

    /// Remove a specific token.
    func removeToken(_ token: SearchToken) {
        tokens.removeAll { $0.id == token.id }
    }

    /// Clear all search state.
    func clear() {
        tokens.removeAll()
        freeText = ""
        results.removeAll()
        isSearching = false
    }
}
