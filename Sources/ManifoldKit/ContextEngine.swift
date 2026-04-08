import Foundation

public struct ContextMatch: Sendable, Hashable {
    public let lineNumber: Int
    public let text: String

    public init(lineNumber: Int, text: String) {
        self.lineNumber = lineNumber
        self.text = text
    }
}

public struct ContextReadResult: Sendable, Hashable {
    public let text: String
    public let selection: ArtifactSelection?
    public let truncated: Bool
    public let bytesRead: Int

    public init(text: String, selection: ArtifactSelection?, truncated: Bool, bytesRead: Int) {
        self.text = text
        self.selection = selection
        self.truncated = truncated
        self.bytesRead = bytesRead
    }
}

public enum ContextEngine {
    public static let maxFullReadBytes = 64_000
    public static let maxReadCharacters = 12_000
    public static let maxReadLines = 240

    private static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "ico", "webp",
        "pdf", "zip", "gz", "tar", "rar", "7z",
        "exe", "dll", "dylib", "so", "a", "o",
        "mp3", "mp4", "wav", "avi", "mov", "mkv",
        "sqlite", "db", "bin", "dat",
    ]

    public static func read(
        fileURL: URL,
        selection: ArtifactSelection? = nil,
        maxCharacters: Int = maxReadCharacters,
        maxLines: Int = maxReadLines
    ) throws -> ContextReadResult {
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let ext = fileURL.pathExtension.lowercased()
        guard !isBinary(fileExtension: ext, fileURL: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return ContextReadResult(
                text: "<binary file, \(data.count) bytes>",
                selection: selection,
                truncated: false,
                bytesRead: data.count
            )
        }

        if let selection {
            return boundedSelectionRead(
                text: text,
                selection: selection,
                maxCharacters: maxCharacters,
                maxLines: maxLines,
                bytesRead: data.count
            )
        }

        if data.count <= maxFullReadBytes,
           text.count <= maxCharacters,
           lineCount(for: text) <= maxLines {
            return ContextReadResult(text: text, selection: nil, truncated: false, bytesRead: data.count)
        }

        let truncated = truncate(text: text, maxCharacters: maxCharacters, maxLines: maxLines)
        let notice = "\n\n[Manifold note: output truncated to the first \(truncated.linesReturned) lines / \(truncated.charactersReturned) characters for context efficiency.]"
        return ContextReadResult(
            text: truncated.text + notice,
            selection: ArtifactSelection(lineStart: 1, lineEnd: truncated.linesReturned),
            truncated: true,
            bytesRead: data.count
        )
    }

    public static func searchMatches(
        query: String,
        fileURL: URL,
        maxMatches: Int = 5,
        maxLineLength: Int = 200
    ) -> [ContextMatch] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let loweredQuery = query.lowercased()
        var matches: [ContextMatch] = []
        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            guard line.lowercased().contains(loweredQuery) else { continue }
            let trimmed = line.count > maxLineLength ? String(line.prefix(maxLineLength)) : line
            matches.append(ContextMatch(lineNumber: index + 1, text: trimmed))
            if matches.count == maxMatches {
                break
            }
        }
        return matches
    }

    public static func preview(
        text: String,
        maxLines: Int,
        maxCharacters: Int
    ) -> String {
        let joined = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(maxLines)
            .joined(separator: "\n")
        if joined.count <= maxCharacters {
            return joined
        }
        return String(joined.prefix(maxCharacters))
    }

    public static func estimateTokens(forText text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }

    public static func lineCount(for text: String) -> Int {
        text.isEmpty ? 0 : text.components(separatedBy: .newlines).count
    }

    public static func isBinary(fileExtension: String, fileURL: URL) -> Bool {
        if binaryExtensions.contains(fileExtension.lowercased()) {
            return true
        }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }
        let prefix = (try? handle.read(upToCount: 1024)) ?? Data()
        return prefix.contains(0)
    }

    private static func boundedSelectionRead(
        text: String,
        selection: ArtifactSelection,
        maxCharacters: Int,
        maxLines: Int,
        bytesRead: Int
    ) -> ContextReadResult {
        if let lineStart = selection.lineStart {
            let lineEnd = max(lineStart, selection.lineEnd ?? lineStart)
            let lines = text.components(separatedBy: .newlines)
            guard lineStart > 0, lineStart <= lines.count else {
                return ContextReadResult(text: "", selection: selection, truncated: false, bytesRead: bytesRead)
            }

            let safeEnd = min(lineEnd, lines.count)
            let requested = Array(lines[(lineStart - 1)..<safeEnd]).joined(separator: "\n")
            let truncated = truncate(text: requested, maxCharacters: maxCharacters, maxLines: maxLines)
            let effectiveEnd = lineStart + truncated.linesReturned - 1
            return ContextReadResult(
                text: truncated.text,
                selection: ArtifactSelection(lineStart: lineStart, lineEnd: effectiveEnd),
                truncated: truncated.wasTruncated,
                bytesRead: bytesRead
            )
        }

        if let byteStart = selection.byteStart {
            let byteEnd = max(byteStart, selection.byteEnd ?? byteStart)
            let utf8 = Array(text.utf8)
            guard byteStart >= 0, byteStart < utf8.count else {
                return ContextReadResult(text: "", selection: selection, truncated: false, bytesRead: bytesRead)
            }
            let safeEnd = min(byteEnd, utf8.count - 1)
            let slice = Data(utf8[byteStart...safeEnd])
            let sliced = String(data: slice, encoding: .utf8) ?? ""
            let truncated = truncate(text: sliced, maxCharacters: maxCharacters, maxLines: maxLines)
            return ContextReadResult(
                text: truncated.text,
                selection: ArtifactSelection(byteStart: byteStart, byteEnd: byteStart + truncated.charactersReturned),
                truncated: truncated.wasTruncated,
                bytesRead: bytesRead
            )
        }

        return ContextReadResult(text: text, selection: selection, truncated: false, bytesRead: bytesRead)
    }

    private static func truncate(
        text: String,
        maxCharacters: Int,
        maxLines: Int
    ) -> (text: String, charactersReturned: Int, linesReturned: Int, wasTruncated: Bool) {
        var charactersUsed = 0
        var linesReturned = 0
        var pieces: [String] = []

        for line in text.components(separatedBy: .newlines) {
            if linesReturned == maxLines {
                break
            }

            let separatorCost = pieces.isEmpty ? 0 : 1
            let remaining = maxCharacters - charactersUsed - separatorCost
            guard remaining > 0 else { break }

            let boundedLine = line.count > remaining ? String(line.prefix(remaining)) : line
            pieces.append(boundedLine)
            charactersUsed += boundedLine.count + separatorCost
            linesReturned += 1

            if boundedLine.count < line.count {
                break
            }
        }

        let output = pieces.joined(separator: "\n")
        return (output, output.count, linesReturned, output != text)
    }
}
