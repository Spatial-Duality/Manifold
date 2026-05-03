// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct MailDateNormalizationResult: Sendable, Equatable {
    public let normalized: String
    public let raw: String?
    public let isTrusted: Bool

    public init(normalized: String, raw: String?, isTrusted: Bool) {
        self.normalized = normalized
        self.raw = raw
        self.isTrusted = isTrusted
    }
}

public enum MailDateNormalizer {
    private nonisolated(unsafe) static let isoFormatter = ISO8601DateFormatter()

    private static let rfcFormatters: [DateFormatter] = {
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()

    public static func normalize(_ value: String?) -> MailDateNormalizationResult {
        let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            let fallback = isoFormatter.string(from: Date(timeIntervalSince1970: 0))
            return MailDateNormalizationResult(normalized: fallback, raw: nil, isTrusted: false)
        }

        if let date = parse(raw) {
            return MailDateNormalizationResult(
                normalized: isoFormatter.string(from: date),
                raw: raw,
                isTrusted: true
            )
        }

        let fallback = isoFormatter.string(from: Date(timeIntervalSince1970: 0))
        return MailDateNormalizationResult(normalized: fallback, raw: raw, isTrusted: false)
    }

    public static func parse(_ value: String?) -> Date? {
        guard var raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if let date = isoFormatter.date(from: raw) {
            return date
        }
        let withoutParentheticalZone = raw.replacingOccurrences(
            of: "\\s+\\([^)]*\\)$",
            with: "",
            options: .regularExpression
        )
        for formatter in rfcFormatters {
            if let date = formatter.date(from: withoutParentheticalZone) {
                return date
            }
        }
        return nil
    }
}
