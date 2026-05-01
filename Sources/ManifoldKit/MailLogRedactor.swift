// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct MailLogRedactor: Sendable {
    public init() {}

    public func redact(_ input: String) -> String {
        var result = input
        for (regex, replacement) in Self.patterns {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: replacement
            )
        }
        return result
    }

    private static let patterns: [(NSRegularExpression, String)] = [
        (compile("(?i)(AUTHENTICATE\\s+XOAUTH2\\s+)[A-Za-z0-9+/=._~-]+"), "$1[REDACTED]"),
        (compile("(?i)(LOGIN\\s+)(\"(?:\\\\.|[^\"])*\"|\\S+)\\s+(\"(?:\\\\.|[^\"])*\"|\\S+)"), "$1[REDACTED] [REDACTED]"),
        (compile("(?i)(access_token|refresh_token|id_token|authorization|bearer)[\"'\\s:=]+[A-Za-z0-9._~+/-]+"), "$1=[REDACTED]"),
        (compile("[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", options: [.caseInsensitive]), "[EMAIL]"),
        (compile("(?i)(subject\\s*[:=]\\s*)([^\\r\\n]+)"), "$1[REDACTED]"),
        (compile("(?i)(filename\\*?\\s*=\\s*)(\"[^\"]*\"|[^;\\r\\n]+)"), "$1[REDACTED]"),
        (compile("(?i)(name\\s*=\\s*)(\"[^\"]*\"|[^;\\r\\n]+)"), "$1[REDACTED]"),
    ]

    private static func compile(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            preconditionFailure("Invalid MailLogRedactor regex: \(pattern)")
        }
    }
}
