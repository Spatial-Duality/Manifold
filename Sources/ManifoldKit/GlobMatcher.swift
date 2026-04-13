// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Gitignore-style pattern matcher for `.manifoldignore` files.
/// Supports: `*` (any non-slash), `**` (any path), `?` (single char),
/// leading `/` (anchored), trailing `/` (directory-only), `!` (negate), `#` (comment).
public struct GlobMatcher: Sendable {

    public struct Pattern: Sendable {
        let regex: NSRegularExpression
        let isNegation: Bool
        let isDirectoryOnly: Bool
    }

    public let patterns: [Pattern]

    public init(content: String) {
        var parsed: [Pattern] = []
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // Skip blank lines and comments
            if line.isEmpty || line.hasPrefix("#") { continue }

            var pattern = line
            let isNegation = pattern.hasPrefix("!")
            if isNegation { pattern = String(pattern.dropFirst()) }

            let isDirectoryOnly = pattern.hasSuffix("/")
            if isDirectoryOnly { pattern = String(pattern.dropLast()) }

            let isAnchored = pattern.hasPrefix("/")
            if isAnchored { pattern = String(pattern.dropFirst()) }

            let regexStr = Self.patternToRegex(pattern, anchored: isAnchored)
            guard let compiled = try? NSRegularExpression(pattern: regexStr, options: []) else { continue }
            parsed.append(Pattern(regex: compiled, isNegation: isNegation, isDirectoryOnly: isDirectoryOnly))
        }
        self.patterns = parsed
    }

    /// Load from a `.manifoldignore` file. Returns empty matcher if file doesn't exist.
    public static func load(from url: URL) -> GlobMatcher {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return GlobMatcher(content: "")
        }
        return GlobMatcher(content: content)
    }

    /// Test whether a relative path should be excluded.
    /// Last matching pattern wins (standard gitignore semantics).
    public func shouldExclude(relativePath: String, isDirectory: Bool = false) -> Bool {
        guard !patterns.isEmpty else { return false }
        var excluded = false
        for pattern in patterns {
            // Directory-only patterns only match directories
            if pattern.isDirectoryOnly && !isDirectory { continue }
            let range = NSRange(relativePath.startIndex..., in: relativePath)
            if pattern.regex.firstMatch(in: relativePath, options: [], range: range) != nil {
                excluded = !pattern.isNegation
            }
        }
        return excluded
    }

    // MARK: - Private

    /// Convert a gitignore glob pattern to a regex string.
    /// - anchored: pattern must match from the start of the path
    /// - unanchored: pattern can match any suffix segment
    static func patternToRegex(_ pattern: String, anchored: Bool) -> String {
        var regex = ""
        var i = pattern.startIndex

        while i < pattern.endIndex {
            let c = pattern[i]
            if c == "*" {
                let next = pattern.index(after: i)
                if next < pattern.endIndex && pattern[next] == "*" {
                    // ** matches any path segments
                    let afterStars = pattern.index(after: next)
                    if afterStars < pattern.endIndex && pattern[afterStars] == "/" {
                        // **/ matches zero or more directories
                        regex += "(.+/)?"
                        i = pattern.index(after: afterStars)
                        continue
                    } else {
                        // ** at end or not followed by /
                        regex += ".*"
                        i = afterStars
                        continue
                    }
                } else {
                    // * matches anything except /
                    regex += "[^/]*"
                }
            } else if c == "?" {
                regex += "[^/]"
            } else if c == "." {
                regex += "\\."
            } else if c == "[" {
                // Pass through character classes
                regex.append(c)
            } else if c == "]" {
                regex.append(c)
            } else if "\\^$|+{}()".contains(c) {
                regex += "\\\(c)"
            } else {
                regex.append(c)
            }
            i = pattern.index(after: i)
        }

        if anchored {
            // Must match from the start
            return "^\(regex)$"
        } else {
            // Match if any path suffix matches (the pattern can appear at any depth)
            // e.g. "*.log" matches "debug.log" and "src/debug.log"
            return "(^|/)\(regex)$"
        }
    }
}
