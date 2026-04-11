import SwiftUI
import ManifoldKit

/// Token-based search field for email. Supports structured tokens
/// (From:, Domain:, Subject:) and free text search.
struct EmailSearchField: View {
    @Bindable var search: EmailSearchModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            // Active tokens
            if !search.tokens.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.tight) {
                        ForEach(search.tokens) { token in
                            SearchTokenChip(token: token) {
                                search.removeToken(token)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.edge)
                }
            }

            // Token suggestions when typing
            if !search.freeText.isEmpty {
                tokenSuggestions
            }
        }
    }

    @ViewBuilder
    private var tokenSuggestions: some View {
        let text = search.freeText.trimmingCharacters(in: .whitespaces)
        let suggestions = parseSuggestions(from: text)

        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions, id: \.id) { token in
                    Button {
                        search.addToken(token)
                        search.freeText = ""
                    } label: {
                        HStack(spacing: Spacing.standard) {
                            Image(systemName: iconForTokenType(token.type))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text("\(token.type.rawValue.capitalized): \(token.value)")
                                .font(.callout)
                        }
                        .padding(.horizontal, Spacing.edge)
                        .padding(.vertical, Spacing.tight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.bar)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, Spacing.edge)
        }
    }

    /// Parse typed text into suggested tokens.
    /// Recognizes patterns like "from:user@example.com", "domain:example.com", "subject:hello".
    private func parseSuggestions(from text: String) -> [SearchToken] {
        var suggestions: [SearchToken] = []
        let lower = text.lowercased()

        // Explicit prefix patterns
        let prefixes: [(String, SearchTokenType)] = [
            ("from:", .from),
            ("domain:", .domain),
            ("subject:", .subject),
            ("to:", .to),
        ]

        for (prefix, type) in prefixes {
            if lower.hasPrefix(prefix) {
                let value = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    suggestions.append(SearchToken(type: type, value: value))
                }
            }
        }

        // If text contains @ and no prefix, suggest as From: token
        if suggestions.isEmpty && text.contains("@") {
            suggestions.append(SearchToken(type: .from, value: text))
            // Also suggest domain if it looks like just a domain
            if !text.contains(" "), let atIdx = text.lastIndex(of: "@") {
                let domain = String(text[text.index(after: atIdx)...])
                if !domain.isEmpty {
                    suggestions.append(SearchToken(type: .domain, value: domain))
                }
            }
        }

        // If text contains a dot and no @ (looks like domain)
        if suggestions.isEmpty && text.contains(".") && !text.contains("@") && !text.contains(" ") {
            suggestions.append(SearchToken(type: .domain, value: text))
        }

        return suggestions
    }

    private func iconForTokenType(_ type: SearchTokenType) -> String {
        switch type {
        case .from: "person"
        case .domain: "globe"
        case .subject: "text.alignleft"
        case .to: "person.2"
        case .hasAttachments: "paperclip"
        case .body: "doc.text.magnifyingglass"
        case .dateAfter: "calendar.badge.plus"
        case .dateBefore: "calendar.badge.minus"
        case .isJunk: "xmark.bin"
        case .isDeleted: "cloud.slash"
        }
    }
}

/// Removable token chip in the search bar.
private struct SearchTokenChip: View {
    let token: SearchToken
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("\(token.type.rawValue.capitalized):")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(token.value)
                .font(.caption)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}
