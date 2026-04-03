import Foundation

/// Computes unified diffs between two blob versions using /usr/bin/diff.
public struct DiffEngine: Sendable {

    public init() {}

    /// Compute a unified diff between two strings.
    /// Returns an array of DiffLine for display.
    public func diff(before: String, after: String) -> [DiffLine] {
        // Write to temp files
        let beforeURL = FileManager.default.temporaryDirectory.appendingPathComponent("manifold-diff-before-\(UUID().uuidString)")
        let afterURL = FileManager.default.temporaryDirectory.appendingPathComponent("manifold-diff-after-\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: beforeURL)
            try? FileManager.default.removeItem(at: afterURL)
        }

        do {
            try before.write(to: beforeURL, atomically: true, encoding: .utf8)
            try after.write(to: afterURL, atomically: true, encoding: .utf8)
        } catch {
            return [DiffLine(type: .context, text: "Error computing diff")]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        process.arguments = ["-u", "--label", "before", "--label", "after", beforeURL.path, afterURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return [DiffLine(type: .context, text: "Error running diff")]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return [DiffLine(type: .context, text: "No changes")]
        }

        return parseDiff(output)
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

    private func parseDiff(_ output: String) -> [DiffLine] {
        let lines = output.components(separatedBy: "\n")
        var result: [DiffLine] = []

        for line in lines {
            // Skip diff headers
            if line.hasPrefix("---") || line.hasPrefix("+++") || line.hasPrefix("@@") { continue }

            if line.hasPrefix("-") {
                result.append(DiffLine(type: .removal, text: String(line.dropFirst())))
            } else if line.hasPrefix("+") {
                result.append(DiffLine(type: .addition, text: String(line.dropFirst())))
            } else if line.hasPrefix(" ") {
                result.append(DiffLine(type: .context, text: String(line.dropFirst())))
            }
        }

        // Limit to 50 lines for display
        if result.count > 50 {
            return Array(result.prefix(50)) + [DiffLine(type: .context, text: "... (\(result.count - 50) more lines)")]
        }

        return result
    }
}

public struct DiffLine: Sendable, Identifiable {
    public let id = UUID()
    public let type: DiffLineType
    public let text: String

    public init(type: DiffLineType, text: String) {
        self.type = type
        self.text = text
    }

    public enum DiffLineType: Sendable {
        case context
        case addition
        case removal
    }
}
