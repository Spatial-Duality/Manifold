// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

struct PrivacyIdentityMatch: Sendable, Hashable {
    let identityID: String
    let category: PrivacyCategory
    let startUTF16: Int
    let endUTF16: Int
    let preview: String
}

struct PrivacyDecisionOutcome: Sendable {
    let spanRecords: [PrivacySpanRecord]
    let matchedCategories: [PrivacyCategory]
    let matchedIdentityIDs: [String]
    let matchedAllowIDs: [String]
    let containsSensitive: Bool
    let containsMyInfo: Bool
    let containsThirdPartyPrivate: Bool
    let containsSecret: Bool
    let containsOrgOnly: Bool
    let severity: PrivacySeverity
    let findingsSummary: String
    let redactedPreview: String?
}

struct PrivacyDecisionEngine: Sendable {
    func merge(
        text: String,
        modelResult: PrivacyScanResult,
        identityMatches: [PrivacyIdentityMatch],
        allowMatches: [PrivacyOrgAllowEntry]
    ) -> PrivacyDecisionOutcome {
        var spanRecords: [PrivacySpanRecord] = modelResult.spans.map { span in
            PrivacySpanRecord(
                contentID: "",
                category: span.category,
                startUTF16: span.startUTF16,
                endUTF16: span.endUTF16,
                confidence: span.confidence,
                source: .model,
                placeholder: span.replacement,
                textHash: nil
            )
        }
        spanRecords.append(
            contentsOf: identityMatches.map { match in
                PrivacySpanRecord(
                    contentID: "",
                    category: match.category,
                    startUTF16: match.startUTF16,
                    endUTF16: match.endUTF16,
                    confidence: 1.0,
                    source: .identity,
                    placeholder: match.category.replacementToken,
                    textHash: nil
                )
            }
        )
        spanRecords = dedupe(spanRecords)

        let categories = Array(Set(spanRecords.map(\.category))).sorted(by: { $0.rawValue < $1.rawValue })
        let matchedIdentityIDs = Array(Set(identityMatches.map(\.identityID))).sorted()
        let matchedAllowIDs = Array(Set(allowMatches.map(\.id))).sorted()
        let containsMyInfo = !matchedIdentityIDs.isEmpty
        let containsSecret = categories.contains(.secret)
        let containsAccountNumber = categories.contains(.accountNumber)

        let modelOnlyCategories = Set(modelResult.spans.map(\.category))
        let allowlistCanSuppress = !matchedAllowIDs.isEmpty
            && !containsMyInfo
            && !containsSecret
            && !containsAccountNumber
            && !modelOnlyCategories.isEmpty
            && modelOnlyCategories.isSubset(of: Set([.email, .url]))
        let containsOrgOnly = allowlistCanSuppress
        let containsSensitive = !spanRecords.isEmpty && !containsOrgOnly
        let containsThirdPartyPrivate = containsSensitive && !containsMyInfo && !containsSecret
        let severity = severityFor(categories: categories, containsMyInfo: containsMyInfo)
        let redactedPreview = containsSensitive ? String(redact(text: text, spans: spanRecords).prefix(280)) : nil

        return PrivacyDecisionOutcome(
            spanRecords: spanRecords,
            matchedCategories: categories,
            matchedIdentityIDs: matchedIdentityIDs,
            matchedAllowIDs: matchedAllowIDs,
            containsSensitive: containsSensitive,
            containsMyInfo: containsMyInfo,
            containsThirdPartyPrivate: containsThirdPartyPrivate,
            containsSecret: containsSecret,
            containsOrgOnly: containsOrgOnly,
            severity: severity,
            findingsSummary: findingsSummary(
                categories: categories,
                containsMyInfo: containsMyInfo,
                containsOrgOnly: containsOrgOnly
            ),
            redactedPreview: redactedPreview
        )
    }

    private func dedupe(_ spans: [PrivacySpanRecord]) -> [PrivacySpanRecord] {
        var seen: Set<String> = []
        var unique: [PrivacySpanRecord] = []
        for span in spans.sorted(by: {
            if $0.startUTF16 != $1.startUTF16 { return $0.startUTF16 < $1.startUTF16 }
            if $0.endUTF16 != $1.endUTF16 { return $0.endUTF16 < $1.endUTF16 }
            return $0.category.rawValue < $1.category.rawValue
        }) {
            let key = "\(span.startUTF16):\(span.endUTF16):\(span.category.rawValue)"
            if seen.insert(key).inserted {
                unique.append(span)
            }
        }
        return unique
    }

    private func severityFor(
        categories: [PrivacyCategory],
        containsMyInfo: Bool
    ) -> PrivacySeverity {
        if categories.contains(.secret) {
            return .critical
        }
        if containsMyInfo && categories.contains(.accountNumber) {
            return .critical
        }
        if categories.contains(.accountNumber) {
            return .high
        }

        let contactCategoryCount = categories.filter {
            [.privatePerson, .email, .phone, .address].contains($0)
        }.count
        if contactCategoryCount > 1 {
            return .high
        }
        if contactCategoryCount == 1 {
            return .medium
        }
        if categories.contains(.url) || categories.contains(.date) {
            return .low
        }
        return .none
    }

    private func findingsSummary(
        categories: [PrivacyCategory],
        containsMyInfo: Bool,
        containsOrgOnly: Bool
    ) -> String {
        if containsOrgOnly {
            return "Matched organization allowlist entries only."
        }
        guard !categories.isEmpty else {
            return "No sensitive spans detected."
        }

        var parts: [String] = []
        if containsMyInfo {
            parts.append("contains confirmed personal identifiers")
        }
        parts.append(
            contentsOf: categories.map { category in
                category.displayName.lowercased()
            }
        )
        return parts.joined(separator: ", ")
    }

    private func redact(text: String, spans: [PrivacySpanRecord]) -> String {
        var output = text
        for span in spans.sorted(by: { $0.startUTF16 > $1.startUTF16 }) {
            let start = String.Index(utf16Offset: span.startUTF16, in: output)
            let end = String.Index(utf16Offset: span.endUTF16, in: output)
            output.replaceSubrange(start..<end, with: span.placeholder ?? span.category.replacementToken)
        }
        return output
    }
}
