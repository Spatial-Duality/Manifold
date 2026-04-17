// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct RuntimeStatus: Sendable {
    public let active: Bool
    public let grantID: String?
    public let sources: [String]
    public let pausedSources: [String]
    public let fileCount: Int
    public let emailCount: Int
    public let message: String
    public let noteCaptureMode: String
    public let noteGuidance: String?

    public init(
        active: Bool,
        grantID: String?,
        sources: [String],
        pausedSources: [String],
        fileCount: Int,
        emailCount: Int,
        message: String,
        noteCaptureMode: String,
        noteGuidance: String?
    ) {
        self.active = active
        self.grantID = grantID
        self.sources = sources
        self.pausedSources = pausedSources
        self.fileCount = fileCount
        self.emailCount = emailCount
        self.message = message
        self.noteCaptureMode = noteCaptureMode
        self.noteGuidance = noteGuidance
    }
}

public typealias StatusResult = RuntimeStatus

public struct TrustedFolder: Sendable, Identifiable {
    public var id: String { folderID }
    public let folderID: String
    public let displayName: String
    public let path: String
    public let status: String

    public init(folderID: String, displayName: String, path: String, status: String) {
        self.folderID = folderID
        self.displayName = displayName
        self.path = path
        self.status = status
    }
}

public struct FileEntry: Sendable {
    public let path: String
    public let sourceName: String
    public let sourceAddedAt: String
    public let sizeBytes: Int
    public let lastModified: String

    public init(path: String, sourceName: String, sourceAddedAt: String, sizeBytes: Int, lastModified: String) {
        self.path = path
        self.sourceName = sourceName
        self.sourceAddedAt = sourceAddedAt
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
    }
}

public typealias FileInfo = FileEntry

public struct FileContent: Sendable {
    public let path: String?
    public let content: String

    public init(path: String? = nil, content: String) {
        self.path = path
        self.content = content
    }
}

public struct SearchHit: Sendable {
    public let path: String
    public let source: String
    public let matches: [String]

    public init(path: String, source: String, matches: [String]) {
        self.path = path
        self.source = source
        self.matches = matches
    }
}

public struct FileMetadata: Sendable {
    public let path: String
    public let sourceName: String
    public let sizeBytes: Int
    public let fileExtension: String
    public let isBinary: Bool
    public let lastModified: String
    public let archiveContents: [String]?

    public init(
        path: String,
        sourceName: String,
        sizeBytes: Int,
        fileExtension: String,
        isBinary: Bool,
        lastModified: String,
        archiveContents: [String]?
    ) {
        self.path = path
        self.sourceName = sourceName
        self.sizeBytes = sizeBytes
        self.fileExtension = fileExtension
        self.isBinary = isBinary
        self.lastModified = lastModified
        self.archiveContents = archiveContents
    }
}

public typealias FileInfoDetail = FileMetadata

public enum WriteResult: Sendable {
    case written(message: String, path: String)
    case escalationRequired(message: String, path: String)

    public var message: String {
        switch self {
        case .written(let message, _), .escalationRequired(let message, _):
            return message
        }
    }

    public var path: String {
        switch self {
        case .written(_, let path), .escalationRequired(_, let path):
            return path
        }
    }
}

public struct TrackedRun: Sendable {
    public let grantID: String
    public let targetApp: String
    public let startedAt: String
    public let folderIDs: [String]
    public let fileScopes: [FileScope]
    public let emailIDs: [String]

    public init(
        grantID: String,
        targetApp: String,
        startedAt: String,
        folderIDs: [String],
        fileScopes: [FileScope],
        emailIDs: [String]
    ) {
        self.grantID = grantID
        self.targetApp = targetApp
        self.startedAt = startedAt
        self.folderIDs = folderIDs
        self.fileScopes = fileScopes
        self.emailIDs = emailIDs
    }
}

public struct PromotionPreview: Sendable {
    public let grantID: String
    public let filesApplied: [String]
    public let filesConflicted: [String]
    public let totalPromotions: Int

    public init(grantID: String, filesApplied: [String], filesConflicted: [String], totalPromotions: Int) {
        self.grantID = grantID
        self.filesApplied = filesApplied
        self.filesConflicted = filesConflicted
        self.totalPromotions = totalPromotions
    }
}

public struct PromotionResult: Sendable {
    public let grantID: String
    public let filesApplied: [String]
    public let filesConflicted: [String]
    public let appliedCount: Int
    public let conflictCount: Int
    public let message: String

    public init(
        grantID: String,
        filesApplied: [String],
        filesConflicted: [String],
        appliedCount: Int,
        conflictCount: Int,
        message: String
    ) {
        self.grantID = grantID
        self.filesApplied = filesApplied
        self.filesConflicted = filesConflicted
        self.appliedCount = appliedCount
        self.conflictCount = conflictCount
        self.message = message
    }
}

public struct ChangeEntry: Sendable {
    public let action: String
    public let path: String?
    public let agent: String?
    public let timestamp: String

    public init(action: String, path: String?, agent: String?, timestamp: String) {
        self.action = action
        self.path = path
        self.agent = agent
        self.timestamp = timestamp
    }
}

public typealias ChangeInfo = ChangeEntry

public struct EmailEntry: Sendable {
    public let id: String
    public let from: String
    public let subject: String
    public let date: String

    public init(id: String, from: String, subject: String, date: String) {
        self.id = id
        self.from = from
        self.subject = subject
        self.date = date
    }
}

public typealias EmailSummary = EmailEntry

public struct EmailContent: Sendable {
    public let id: String
    public let content: String

    public init(id: String, content: String) {
        self.id = id
        self.content = content
    }
}

public struct RevealResult: Sendable {
    public let emailID: String
    public let revealedUntil: String?
    public let message: String

    public init(emailID: String, revealedUntil: String?, message: String) {
        self.emailID = emailID
        self.revealedUntil = revealedUntil
        self.message = message
    }
}

public struct SessionEntry: Sendable {
    public let grantID: String
    public let targetApp: String
    public let startedAt: String
    public let endedAt: String
    public let summaryPreview: String

    public init(grantID: String, targetApp: String, startedAt: String, endedAt: String, summaryPreview: String) {
        self.grantID = grantID
        self.targetApp = targetApp
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.summaryPreview = summaryPreview
    }
}

public typealias SessionSummary = SessionEntry

public struct SessionDetail: Sendable {
    public let grantID: String
    public let targetApp: String
    public let status: String
    public let startedAt: String
    public let endedAt: String?
    public let sources: [String]
    public let summaryMarkdown: String?
    public let noteCaptureMode: String
    public let sessionNotes: [SessionNoteDetail]
    public let filesApplied: [String]
    public let filesConflicted: [String]
    public let totalPromotions: Int

    public init(
        grantID: String,
        targetApp: String,
        status: String,
        startedAt: String,
        endedAt: String?,
        sources: [String],
        summaryMarkdown: String?,
        noteCaptureMode: String,
        sessionNotes: [SessionNoteDetail],
        filesApplied: [String],
        filesConflicted: [String],
        totalPromotions: Int
    ) {
        self.grantID = grantID
        self.targetApp = targetApp
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sources = sources
        self.summaryMarkdown = summaryMarkdown
        self.noteCaptureMode = noteCaptureMode
        self.sessionNotes = sessionNotes
        self.filesApplied = filesApplied
        self.filesConflicted = filesConflicted
        self.totalPromotions = totalPromotions
    }
}

public struct SessionNoteDetail: Sendable {
    public let summaryID: String
    public let kind: String
    public let origin: String
    public let endedAt: String
    public let markdown: String

    public init(summaryID: String, kind: String, origin: String, endedAt: String, markdown: String) {
        self.summaryID = summaryID
        self.kind = kind
        self.origin = origin
        self.endedAt = endedAt
        self.markdown = markdown
    }
}

public struct ApprovalRequest: Sendable {
    public let id: String
    public let connectionID: String
    public let agent: String
    public let path: String
    public let action: String
    public let requestedAt: String
    public let status: String

    public init(id: String, connectionID: String, agent: String, path: String, action: String, requestedAt: String, status: String) {
        self.id = id
        self.connectionID = connectionID
        self.agent = agent
        self.path = path
        self.action = action
        self.requestedAt = requestedAt
        self.status = status
    }
}

public struct AccessExplanation: Sendable {
    public let connectionID: String
    public let path: String
    public let action: String
    public let reason: String
    public let message: String

    public init(connectionID: String, path: String, action: String, reason: String, message: String) {
        self.connectionID = connectionID
        self.path = path
        self.action = action
        self.reason = reason
        self.message = message
    }
}

public struct ExposureEntry: Sendable {
    public let id: String
    public let toolName: String
    public let resourcePath: String?
    public let byteCount: Int
    public let contentHash: String
    public let exposureType: String
    public let timestamp: String

    public init(
        id: String,
        toolName: String,
        resourcePath: String?,
        byteCount: Int,
        contentHash: String,
        exposureType: String,
        timestamp: String
    ) {
        self.id = id
        self.toolName = toolName
        self.resourcePath = resourcePath
        self.byteCount = byteCount
        self.contentHash = contentHash
        self.exposureType = exposureType
        self.timestamp = timestamp
    }
}

public struct AuditEntry: Sendable {
    public let action: String
    public let path: String?
    public let agent: String?
    public let timestamp: String
    public let metadata: String?

    public init(action: String, path: String?, agent: String?, timestamp: String, metadata: String?) {
        self.action = action
        self.path = path
        self.agent = agent
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

public struct FileScope: Sendable, Hashable {
    public let sourceID: String
    public let relativePath: String
    public let isDirectory: Bool

    public init(sourceID: String, relativePath: String, isDirectory: Bool) {
        self.sourceID = sourceID
        self.relativePath = relativePath
        self.isDirectory = isDirectory
    }
}

public enum ManifoldMCPError: Error, LocalizedError {
    case noActiveSession
    case noSources
    case fileNotFound(String)
    case invalidPath(String)
    case accessPaused
    case noAccessConfigured
    case intentRequired(String)
    case ruleDenied(ruleName: String, explanation: String)

    public var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "No active session"
        case .noSources:
            return "No sources configured"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .invalidPath(let message):
            return "Invalid path: \(message)"
        case .accessPaused:
            return "Access is paused for this agent. Resume access in Manifold to continue."
        case .noAccessConfigured:
            return "No file or email access configured. Use Review & Update Access in Manifold to grant access."
        case .intentRequired(let message):
            return message
        case .ruleDenied(let ruleName, let explanation):
            return "Blocked by rule \"\(ruleName)\": \(explanation)"
        }
    }
}
