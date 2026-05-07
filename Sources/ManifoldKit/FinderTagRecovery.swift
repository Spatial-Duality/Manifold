// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum FinderTagRecoveryMatchKind: String, Sendable, Codable {
    case fileIdentity = "file_identity"
    case fileNameAndTag = "file_name_and_tag"
}

public struct FinderTagRecoveryCandidate: Sendable, Hashable, Codable {
    public let path: String
    public let fileIdentity: String?
    public let isDirectory: Bool
    public let tagName: String

    public init(path: String, fileIdentity: String?, isDirectory: Bool, tagName: String) {
        self.path = path
        self.fileIdentity = fileIdentity
        self.isDirectory = isDirectory
        self.tagName = tagName
    }
}

public struct FinderTagRecoverySuggestion: Sendable, Hashable, Identifiable, Codable {
    public var id: String { "\(sourceID):\(originalPath):\(suggestedPath):\(matchKind.rawValue)" }

    public let sourceID: String
    public let originalPath: String
    public let suggestedPath: String
    public let isDirectory: Bool
    public let tagName: String
    public let isSourceRoot: Bool
    public let matchKind: FinderTagRecoveryMatchKind

    public init(
        sourceID: String,
        originalPath: String,
        suggestedPath: String,
        isDirectory: Bool,
        tagName: String,
        isSourceRoot: Bool,
        matchKind: FinderTagRecoveryMatchKind
    ) {
        self.sourceID = sourceID
        self.originalPath = originalPath
        self.suggestedPath = suggestedPath
        self.isDirectory = isDirectory
        self.tagName = tagName
        self.isSourceRoot = isSourceRoot
        self.matchKind = matchKind
    }
}

public enum FinderTagRecoveryMatcher {
    public static func suggestions(
        records: [FinderTaggedItemRecord],
        candidates: [FinderTagRecoveryCandidate],
        originalSourcePath: String
    ) -> [FinderTagRecoverySuggestion] {
        let sourcePath = URL(fileURLWithPath: originalSourcePath).standardizedFileURL.path
        var suggestions: [FinderTagRecoverySuggestion] = []
        var seen: Set<String> = []

        for record in records {
            let originalPath = URL(fileURLWithPath: record.originalPath).standardizedFileURL.path
            let matchingCandidates = candidates.filter { candidate in
                candidate.tagName == record.tagName
                    && candidate.isDirectory == record.isDirectory
                    && URL(fileURLWithPath: candidate.path).standardizedFileURL.path != originalPath
            }

            for candidate in matchingCandidates {
                let candidatePath = URL(fileURLWithPath: candidate.path).standardizedFileURL.path
                let matchKind: FinderTagRecoveryMatchKind?
                if let recordIdentity = record.fileIdentity,
                   let candidateIdentity = candidate.fileIdentity,
                   !recordIdentity.isEmpty,
                   recordIdentity == candidateIdentity {
                    matchKind = .fileIdentity
                } else if record.fileIdentity == nil,
                          candidate.fileIdentity == nil,
                          URL(fileURLWithPath: originalPath).lastPathComponent == URL(fileURLWithPath: candidatePath).lastPathComponent {
                    matchKind = .fileNameAndTag
                } else {
                    matchKind = nil
                }
                guard let matchKind else { continue }

                let key = "\(record.sourceID):\(originalPath):\(candidatePath)"
                guard seen.insert(key).inserted else { continue }

                suggestions.append(
                    FinderTagRecoverySuggestion(
                        sourceID: record.sourceID,
                        originalPath: originalPath,
                        suggestedPath: candidatePath,
                        isDirectory: record.isDirectory,
                        tagName: record.tagName,
                        isSourceRoot: originalPath == sourcePath,
                        matchKind: matchKind
                    )
                )
            }
        }

        return suggestions.sorted {
            if $0.isSourceRoot != $1.isSourceRoot { return $0.isSourceRoot && !$1.isSourceRoot }
            if $0.matchKind != $1.matchKind { return $0.matchKind == .fileIdentity }
            return $0.suggestedPath.localizedStandardCompare($1.suggestedPath) == .orderedAscending
        }
    }
}
