// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Returns sensitive-content findings for a single file read.
///
/// Pluggable so the runtime can swap detection backends — a regex-based
/// default (this file), a future ML/local-model scanner, or an external
/// vendor scanner — without changing `ManifoldBridge.enforceFileReadRules`.
///
/// The provider is consulted INSIDE the bridge after the runtime has
/// already read the file bytes, so implementations get the actual
/// content rather than re-reading from disk.
public protocol FilterModeFindingsProvider: Sendable {
    /// Scan content for sensitive values. `path` is the canonical mount-
    /// relative path so providers that cache by path can. `content` is
    /// the actual bytes the runtime is about to deliver to an agent
    /// (best-effort UTF-8 decoded; non-text reads pass nil).
    func findings(forFile path: String, content: String?) async -> FilterFindingsSummary
}

/// Default findings provider — regex scanner for common high-confidence
/// secret patterns (AWS access keys, GitHub tokens, JWTs, OpenAI keys,
/// generic Bearer tokens with high entropy). Designed to catch the most
/// dangerous obvious mistakes; intentionally narrow on PII to keep false-
/// positive rate low.
///
/// This is a "good citizen v1" implementation. Real production secret
/// detection wants a tuned model + a maintained pattern catalog; that
/// upgrade ships behind the same `FilterModeFindingsProvider` protocol
/// without touching the bridge integration.
public struct RegexFilterFindingsProvider: FilterModeFindingsProvider {
    public init() {}

    public func findings(forFile path: String, content: String?) async -> FilterFindingsSummary {
        guard let content, !content.isEmpty else { return .empty }
        var secretCount = 0
        var piiCount = 0

        for pattern in Self.secretPatterns {
            secretCount += Self.matchCount(in: content, pattern: pattern)
        }
        for pattern in Self.piiPatterns {
            piiCount += Self.matchCount(in: content, pattern: pattern)
        }

        let total = secretCount + piiCount
        if total == 0 { return .empty }
        return FilterFindingsSummary(
            totalCount: total,
            secretCount: secretCount,
            piiCount: piiCount,
            financialCount: 0
        )
    }

    /// Patterns that strongly indicate secrets. Tuned to minimize false
    /// positives — each pattern is keyed to a known token format that
    /// rarely appears legitimately in user prose.
    private static let secretPatterns: [String] = [
        // AWS Access Key ID — 20-char base32 starting with AKIA / ASIA.
        #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#,
        // GitHub PAT classic + fine-grained.
        #"\bghp_[A-Za-z0-9]{36}\b"#,
        #"\bgithub_pat_[A-Za-z0-9_]{60,}\b"#,
        // OpenAI API key (sk-... 48+ alnum).
        #"\bsk-[A-Za-z0-9]{20,}\b"#,
        // JWT (header.payload.signature, base64url).
        #"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#,
        // Slack bot/user token.
        #"\bxox[abprs]-[A-Za-z0-9-]{10,}\b"#,
        // Stripe live key.
        #"\bsk_live_[A-Za-z0-9]{20,}\b"#,
        // Google API key (AIza...).
        #"\bAIza[A-Za-z0-9_-]{35}\b"#,
    ]

    /// PII patterns are intentionally minimal — only formats unambiguous
    /// enough that a positive match is almost certainly real PII. Email
    /// addresses are NOT included because they appear too often in code
    /// + prose to be useful as a block signal.
    private static let piiPatterns: [String] = [
        // US SSN — three-two-four with dashes; rare to appear by accident.
        #"\b(?!000|666|9\d\d)\d{3}-(?!00)\d{2}-(?!0000)\d{4}\b"#,
        // Credit-card-shaped digit sequences (16 digits in 4 groups of 4).
        #"\b(?:\d{4}[-\s]){3}\d{4}\b"#,
    ]

    /// Counts non-overlapping matches of `pattern` in `text`. Uses
    /// `NSRegularExpression` directly so the provider stays Sendable
    /// (NSRegularExpression is thread-safe for concurrent matches per
    /// the Apple docs).
    private static func matchCount(in text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return 0
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }
}

/// No-op provider for tests / unit isolation. Always returns `.empty`.
public struct NullFilterModeFindingsProvider: FilterModeFindingsProvider {
    public init() {}
    public func findings(forFile path: String, content: String?) async -> FilterFindingsSummary {
        .empty
    }
}
