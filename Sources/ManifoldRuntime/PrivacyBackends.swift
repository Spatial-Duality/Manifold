// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

struct PrivacyModelInfo: Sendable {
    let modelVersion: String
    let available: Bool
    let loaded: Bool
    let note: String?
}

enum PrivacyBackendError: Error, LocalizedError {
    case unavailable(PrivacyBackendKind, String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let kind, let message):
            return "\(kind.displayName) backend is unavailable: \(message)"
        }
    }
}

protocol PrivacyBackend: Sendable {
    var kind: PrivacyBackendKind { get }
    func install() async throws -> PrivacyModelInfo
    func uninstall() async throws
    func load() async throws
    func unload() async
    func modelInfo() async -> PrivacyModelInfo
    func scan(_ request: PrivacyScanRequest) async throws -> PrivacyScanResult
    func scanBatch(_ requests: [PrivacyScanRequest]) async throws -> [PrivacyScanResult]
}

extension PrivacyBackend {
    func install() async throws -> PrivacyModelInfo {
        try await load()
        return await modelInfo()
    }

    func uninstall() async throws {}

    func scanBatch(_ requests: [PrivacyScanRequest]) async throws -> [PrivacyScanResult] {
        var results: [PrivacyScanResult] = []
        results.reserveCapacity(requests.count)
        for request in requests {
            results.append(try await scan(request))
        }
        return results
    }
}

actor RulesOnlyPrivacyBackend: PrivacyBackend {
    let kind: PrivacyBackendKind = .rulesOnly
    private let modelVersion = "rules-only-v1"

    func load() async throws {}

    func install() async throws -> PrivacyModelInfo {
        await modelInfo()
    }

    func uninstall() async throws {}

    func unload() async {}

    func modelInfo() async -> PrivacyModelInfo {
        PrivacyModelInfo(
            modelVersion: modelVersion,
            available: true,
            loaded: true,
            note: "Local rules-only heuristics for secrets and common identifiers."
        )
    }

    func scan(_ request: PrivacyScanRequest) async throws -> PrivacyScanResult {
        let started = Date()
        let spans = Self.detect(text: request.text, categories: Set(request.categories))
        let merged = Self.merge(spans)
        let redacted = Self.redact(text: request.text, using: merged)
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1_000)
        return PrivacyScanResult(
            spans: merged,
            redactedText: redacted,
            findingsSummary: Self.summary(for: merged),
            backend: kind,
            modelVersion: modelVersion,
            elapsedMs: elapsedMs,
            cacheHit: false
        )
    }

    private static func detect(text: String, categories: Set<PrivacyCategory>) -> [DetectedSpan] {
        var spans: [DetectedSpan] = []

        if categories.contains(.secret) {
            spans += regexMatches(
                pattern: #"-----BEGIN (?:[A-Z ]*PRIVATE KEY|OPENSSH PRIVATE KEY)-----[\s\S]+?-----END [A-Z ]*PRIVATE KEY-----"#,
                in: text,
                category: .secret,
                confidence: 0.99
            )
            spans += regexMatches(pattern: #"\bAKIA[0-9A-Z]{16}\b"#, in: text, category: .secret, confidence: 0.98)
            spans += regexMatches(pattern: #"\bgh[pousr]_[A-Za-z0-9]{20,}\b"#, in: text, category: .secret, confidence: 0.98)
            spans += regexMatches(pattern: #"\bsk-[A-Za-z0-9]{20,}\b"#, in: text, category: .secret, confidence: 0.98)
            spans += regexMatches(pattern: #"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#, in: text, category: .secret, confidence: 0.96)
            spans += regexMatches(
                pattern: #"(?i)\b(?:api[_ -]?key|access[_ -]?token|bearer|secret|password|passwd)\b\s*[:=]\s*['"]?([A-Za-z0-9_./+=\-]{8,})"#,
                in: text,
                category: .secret,
                confidence: 0.95,
                captureGroup: 1
            )
        }

        if categories.contains(.email) {
            spans += regexMatches(
                pattern: #"\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b"#,
                in: text,
                category: .email,
                confidence: 0.95,
                options: [.caseInsensitive]
            )
        }

        if categories.contains(.phone) {
            spans += regexMatches(
                pattern: #"(?:\+?\d[\d(). \-]{7,}\d)"#,
                in: text,
                category: .phone,
                confidence: 0.88
            )
        }

        if categories.contains(.url) {
            spans += regexMatches(
                pattern: #"\b(?:https?://|www\.)\S+\b"#,
                in: text,
                category: .url,
                confidence: 0.9,
                options: [.caseInsensitive]
            )
        }

        if categories.contains(.date) {
            spans += regexMatches(
                pattern: #"\b(?:\d{1,2}[/-]){2}\d{2,4}\b"#,
                in: text,
                category: .date,
                confidence: 0.78
            )
            spans += regexMatches(
                pattern: #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}\b"#,
                in: text,
                category: .date,
                confidence: 0.8,
                options: [.caseInsensitive]
            )
        }

        if categories.contains(.accountNumber) {
            spans += regexMatches(
                pattern: #"(?i)\b(?:account|acct|routing|iban|member id|customer id|ssn|tax id)\b[^A-Za-z0-9]{0,8}([A-Za-z0-9\-]{4,})"#,
                in: text,
                category: .accountNumber,
                confidence: 0.9,
                captureGroup: 1
            )
        }

        if categories.contains(.address) {
            spans += regexMatches(
                pattern: #"\b\d{1,5}\s+[A-Za-z0-9.'\-]+(?:\s+[A-Za-z0-9.'\-]+){0,4}\s(?:Street|St|Road|Rd|Avenue|Ave|Boulevard|Blvd|Lane|Ln|Drive|Dr|Way|Court|Ct)\b"#,
                in: text,
                category: .address,
                confidence: 0.82,
                options: [.caseInsensitive]
            )
        }

        if categories.contains(.privatePerson) {
            spans += regexMatches(
                pattern: #"(?i)\b(?:name|contact|attn)\b\s*:\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,2})"#,
                in: text,
                category: .privatePerson,
                confidence: 0.7,
                captureGroup: 1
            )
        }

        return spans
    }

    private static func regexMatches(
        pattern: String,
        in text: String,
        category: PrivacyCategory,
        confidence: Double,
        options: NSRegularExpression.Options = [],
        captureGroup: Int = 0
    ) -> [DetectedSpan] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: fullRange).compactMap { match in
            let range = match.range(at: captureGroup)
            guard range.location != NSNotFound,
                  range.length > 0,
                  let stringRange = Range(range, in: text) else {
                return nil
            }
            let preview = String(text[stringRange].prefix(48))
            return DetectedSpan(
                startUTF16: range.location,
                endUTF16: range.location + range.length,
                category: category,
                confidence: confidence,
                textPreview: preview,
                replacement: category.replacementToken
            )
        }
    }

    private static func merge(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        let sorted = spans.sorted {
            if $0.startUTF16 != $1.startUTF16 { return $0.startUTF16 < $1.startUTF16 }
            return $0.endUTF16 < $1.endUTF16
        }
        guard var current = sorted.first else { return [] }
        var merged: [DetectedSpan] = []

        for span in sorted.dropFirst() {
            if span.startUTF16 <= current.endUTF16 {
                let preferredCategory: PrivacyCategory
                if current.category == .secret || span.category == .secret {
                    preferredCategory = .secret
                } else if current.confidence >= span.confidence {
                    preferredCategory = current.category
                } else {
                    preferredCategory = span.category
                }
                current = DetectedSpan(
                    startUTF16: min(current.startUTF16, span.startUTF16),
                    endUTF16: max(current.endUTF16, span.endUTF16),
                    category: preferredCategory,
                    confidence: max(current.confidence, span.confidence),
                    textPreview: current.textPreview,
                    replacement: preferredCategory.replacementToken
                )
            } else {
                merged.append(current)
                current = span
            }
        }
        merged.append(current)
        return merged
    }

    private static func redact(text: String, using spans: [DetectedSpan]) -> String {
        var output = text
        for span in spans.sorted(by: { $0.startUTF16 > $1.startUTF16 }) {
            let start = String.Index(utf16Offset: span.startUTF16, in: output)
            let end = String.Index(utf16Offset: span.endUTF16, in: output)
            output.replaceSubrange(start..<end, with: span.replacement)
        }
        return output
    }

    private static func summary(for spans: [DetectedSpan]) -> String {
        guard !spans.isEmpty else { return "No sensitive spans detected." }
        let counts = Dictionary(grouping: spans, by: \.category).mapValues(\.count)
        return counts.keys.sorted(by: { $0.rawValue < $1.rawValue }).map { category in
            let count = counts[category] ?? 0
            let label = category.displayName.lowercased()
            return "\(count) \(label)"
        }.joined(separator: ", ")
    }
}

actor PlaceholderPrivacyBackend: PrivacyBackend {
    let kind: PrivacyBackendKind
    private let note: String

    init(kind: PrivacyBackendKind, note: String) {
        self.kind = kind
        self.note = note
    }

    func load() async throws {}

    func install() async throws -> PrivacyModelInfo {
        await modelInfo()
    }

    func uninstall() async throws {}

    func unload() async {}

    func modelInfo() async -> PrivacyModelInfo {
        PrivacyModelInfo(
            modelVersion: "unavailable",
            available: false,
            loaded: false,
            note: note
        )
    }

    func scan(_ request: PrivacyScanRequest) async throws -> PrivacyScanResult {
        throw PrivacyBackendError.unavailable(kind, note)
    }
}
