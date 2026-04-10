import Foundation

/// Computes unified diffs between two text versions.
/// Uses Swift's CollectionDifference (Myers algorithm) instead of
/// spawning /usr/bin/diff — eliminates fork+exec+temp files per diff.
public struct DiffEngine: Sendable {

    public init() {}

    /// Compute a diff between two strings. Returns an array of DiffLine for display.
    public func diff(before: String, after: String) -> [DiffLine] {
        let beforeLines = before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let afterLines = after.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let changes = afterLines.difference(from: beforeLines)

        // Build result with context
        var result: [DiffLine] = []
        var lineIndex = 0

        // Track which before-lines are removed and which after-lines are inserted
        var removedIndices = Set<Int>()
        var insertedIndices = Set<Int>()
        var insertedLines: [Int: String] = [:]

        for change in changes {
            switch change {
            case .remove(let offset, _, _):
                removedIndices.insert(offset)
            case .insert(let offset, let element, _):
                insertedIndices.insert(offset)
                insertedLines[offset] = element
            }
        }

        // Walk through before-lines, emitting removals and context
        var afterIdx = 0
        for (i, line) in beforeLines.enumerated() {
            // Emit any insertions that come before this position in the after-array
            while afterIdx < afterLines.count && insertedIndices.contains(afterIdx) && afterIdx <= i + result.filter({ $0.type == .addition }).count {
                if insertedIndices.contains(afterIdx) {
                    result.append(DiffLine(id: lineIndex, type: .addition, text: afterLines[afterIdx]))
                    lineIndex += 1
                }
                afterIdx += 1
            }

            if removedIndices.contains(i) {
                result.append(DiffLine(id: lineIndex, type: .removal, text: line))
                lineIndex += 1
            } else {
                // Context line (skip for brevity if too many)
                afterIdx += 1
            }
        }

        // Emit remaining insertions
        while afterIdx < afterLines.count {
            if insertedIndices.contains(afterIdx) {
                result.append(DiffLine(id: lineIndex, type: .addition, text: afterLines[afterIdx]))
                lineIndex += 1
            }
            afterIdx += 1
        }

        // If the simple walk didn't produce clean output, fall back to a direct approach
        if result.isEmpty && !changes.isEmpty {
            result = simpleDiff(beforeLines: beforeLines, afterLines: afterLines)
        }

        // Limit to 50 lines for display
        if result.count > 50 {
            return Array(result.prefix(50)) + [DiffLine(id: 50, type: .context, text: "... (\(result.count - 50) more lines)")]
        }

        return result
    }

    /// Simple diff: emit all removals then all additions.
    /// Used as fallback when the walk-based approach doesn't produce clean output.
    private func simpleDiff(beforeLines: [String], afterLines: [String]) -> [DiffLine] {
        let changes = afterLines.difference(from: beforeLines)
        var result: [DiffLine] = []
        var lineIndex = 0

        for change in changes {
            switch change {
            case .remove(_, let element, _):
                result.append(DiffLine(id: lineIndex, type: .removal, text: element))
                lineIndex += 1
            case .insert(_, let element, _):
                result.append(DiffLine(id: lineIndex, type: .addition, text: element))
                lineIndex += 1
            }
        }
        return result
    }

    /// Compute a diff between two Data blobs.
    /// Returns nil if either blob is not valid UTF-8 or is too large (>1MB).
    public func diff(beforeData: Data, afterData: Data) -> [DiffLine]? {
        guard beforeData.count < 1_000_000, afterData.count < 1_000_000 else {
            return nil // Too large for inline diff
        }
        guard let before = String(data: beforeData, encoding: .utf8),
              let after = String(data: afterData, encoding: .utf8) else {
            return nil // Not text
        }
        return diff(before: before, after: after)
    }
}

public struct DiffLine: Sendable, Identifiable {
    public let id: Int  // Sequential index, not UUID (avoids /dev/urandom reads)
    public let type: DiffLineType
    public let text: String

    public init(id: Int, type: DiffLineType, text: String) {
        self.id = id
        self.type = type
        self.text = text
    }

    public enum DiffLineType: Sendable {
        case context
        case addition
        case removal
    }
}
