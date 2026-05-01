// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation

public enum MailExportError: Error, LocalizedError, Sendable {
    case messageNotFound(String)
    case messageBlobUnavailable(String)
    case attachmentBlobUnavailable(String)
    case invalidDestination(String)

    public var errorDescription: String? {
        switch self {
        case .messageNotFound(let id):
            "Mail message could not be found: \(id)"
        case .messageBlobUnavailable(let id):
            "Stored mail content is unavailable for message: \(id)"
        case .attachmentBlobUnavailable(let id):
            "Stored attachment content is unavailable: \(id)"
        case .invalidDestination(let path):
            "Export destination is invalid: \(path)"
        }
    }
}

public struct MailExportResult: Sendable, Equatable {
    public let messageCount: Int
    public let attachmentCount: Int
    public let writtenPaths: [String]
}

public struct MailExporter {
    private let emailStore: EmailStore
    private let archiveStore: MailArchiveStore
    private let fileManager: FileManager

    public init(
        emailStore: EmailStore,
        archiveStore: MailArchiveStore,
        fileManager: FileManager = .default
    ) {
        self.emailStore = emailStore
        self.archiveStore = archiveStore
        self.fileManager = fileManager
    }

    @discardableResult
    public func export(_ request: MailExportRequest) throws -> MailExportResult {
        let destination = URL(fileURLWithPath: request.destinationPath, isDirectory: true)
        guard !request.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MailExportError.invalidDestination(request.destinationPath)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let messages = try resolveMessages(for: request.scope)
        let attachmentsByEmail = Dictionary(grouping: try emailStore.emailAttachments(emailIDs: messages.map(\.emailID))) {
            $0.emailID
        }

        var writtenPaths: [String] = []
        var attachmentCount = 0

        for message in messages {
            let baseName = Self.safeFilename(Self.messageBaseName(message))
            let messageDirectory: URL
            if request.createFolderPerMessage {
                messageDirectory = try uniqueDirectory(in: destination, baseName: baseName)
                writtenPaths.append(messageDirectory.path)
            } else {
                messageDirectory = destination
            }

            let messageData = try messageRFC822Data(message)
            if request.includeOriginalEML {
                let emlURL = try uniqueFileURL(
                    in: messageDirectory,
                    baseName: baseName,
                    fileExtension: "eml"
                )
                try messageData.write(to: emlURL, options: [.atomic])
                writtenPaths.append(emlURL.path)
            }

            if request.includeAttachments {
                let attachments = attachmentsByEmail[message.emailID] ?? []
                if !attachments.isEmpty {
                    let attachmentDirectory: URL
                    if request.createFolderPerMessage {
                        attachmentDirectory = messageDirectory
                    } else {
                        attachmentDirectory = try uniqueDirectory(
                            in: destination,
                            baseName: "\(baseName) Attachments"
                        )
                        writtenPaths.append(attachmentDirectory.path)
                    }

                    for attachment in attachments {
                        let data = try attachmentData(attachment, message: message, messageData: messageData)
                        let filename = Self.safeFilename(URL(fileURLWithPath: attachment.filename).lastPathComponent)
                        let fileURL = try uniqueFileURL(
                            in: attachmentDirectory,
                            baseName: URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent,
                            fileExtension: URL(fileURLWithPath: filename).pathExtension.nilIfEmpty
                        )
                        try data.write(to: fileURL, options: [.atomic])
                        writtenPaths.append(fileURL.path)
                        attachmentCount += 1
                    }
                }
            }
        }

        if request.temporary {
            try TemporaryExportCleaner.recordTemporaryExport(paths: writtenPaths)
        }

        return MailExportResult(
            messageCount: messages.count,
            attachmentCount: attachmentCount,
            writtenPaths: writtenPaths
        )
    }

    private func resolveMessages(for scope: MailExportScope) throws -> [EmailMessageRecord] {
        let messages: [EmailMessageRecord]
        let dateRange: DateInterval?
        switch scope {
        case .messages(let ids):
            var foundByID = Dictionary(uniqueKeysWithValues: try emailStore.emailMessages(ids: ids).map { ($0.emailID, $0) })
            messages = try ids.map { id in
                guard let message = foundByID.removeValue(forKey: id) else {
                    throw MailExportError.messageNotFound(id)
                }
                return message
            }
            dateRange = nil
        case .mailbox(let mailbox, let range):
            messages = try emailStore.allEmailMessages(limit: 1_000_000)
                .filter { $0.mailbox == mailbox }
            dateRange = range
        case .account(let accountID, let range):
            messages = try emailStore.emailMessages(accountID: accountID, limit: 1_000_000)
            dateRange = range
        }
        return messages.filter { message in
            guard let dateRange else { return true }
            guard let date = ISO8601DateFormatter.shared.date(from: message.receivedAt) else { return true }
            return dateRange.contains(date)
        }
    }

    private func messageRFC822Data(_ message: EmailMessageRecord) throws -> Data {
        if let cid = message.canonicalBlobCID {
            return try archiveStore.readObject(contentID: cid, accountID: message.accountID)
        }
        if let path = message.emlPath,
           let data = EmailSyncEngine.readStoredMessage(at: path) {
            return data
        }
        throw MailExportError.messageBlobUnavailable(message.emailID)
    }

    private func attachmentData(
        _ attachment: EmailAttachmentRecord,
        message: EmailMessageRecord,
        messageData: Data
    ) throws -> Data {
        if let cid = attachment.attachmentBlobCID {
            do {
                return try archiveStore.readObject(contentID: cid, accountID: message.accountID)
            } catch {
                throw MailExportError.attachmentBlobUnavailable(attachment.attachmentID)
            }
        }
        let parsed = MIMEParser.parse(data: messageData)
        if let matched = parsed.attachments.first(where: { SHA256Hash.hex($0.data) == attachment.contentHash }) {
            return matched.data
        }
        throw MailExportError.attachmentBlobUnavailable(attachment.attachmentID)
    }

    private func uniqueDirectory(in directory: URL, baseName: String) throws -> URL {
        var candidate = directory.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(suffix)", isDirectory: true)
            suffix += 1
        }
        try fileManager.createDirectory(at: candidate, withIntermediateDirectories: true)
        return candidate
    }

    private func uniqueFileURL(in directory: URL, baseName: String, fileExtension ext: String?) throws -> URL {
        let cleanedBase = baseName.nilIfEmpty ?? "mail"
        let cleanedExt = ext?.nilIfEmpty
        func makeURL(_ suffix: Int?) -> URL {
            let name = suffix.map { "\(cleanedBase) \($0)" } ?? cleanedBase
            let filename = cleanedExt.map { "\(name).\($0)" } ?? name
            return directory.appendingPathComponent(filename, isDirectory: false)
        }

        var candidate = makeURL(nil)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = makeURL(suffix)
            suffix += 1
        }
        return candidate
    }

    private static func messageBaseName(_ message: EmailMessageRecord) -> String {
        let date = message.receivedAt.prefix(10).replacingOccurrences(of: ":", with: "-")
        let subject = message.subject.nilIfEmpty ?? "No Subject"
        return "\(date) \(subject) \(message.emailID)"
    }

    public static func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let replaced = value.unicodeScalars.map { scalar -> Character in
            forbidden.contains(scalar) ? "_" : Character(scalar)
        }
        let collapsed = String(replaced)
            .replacingOccurrences(of: "..", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "._ "))
        let fallback = collapsed.nilIfEmpty ?? "mail"
        return String(fallback.prefix(120))
    }
}

public enum TemporaryExportCleaner {
    public static var temporaryExportRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Manifold/MailTemporaryExports", isDirectory: true)
    }

    private static var manifestURL: URL {
        temporaryExportRoot.appendingPathComponent("manifest.txt", isDirectory: false)
    }

    public static func recordTemporaryExport(paths: [String]) throws {
        try FileManager.default.createDirectory(at: temporaryExportRoot, withIntermediateDirectories: true)
        let payload = (paths + [""]).joined(separator: "\n")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let handle = try FileHandle(forWritingTo: manifestURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(payload.utf8))
        } else {
            try Data(payload.utf8).write(to: manifestURL, options: [.atomic])
        }
    }

    public static func cleanupExpired(now: Date = Date(), maxAge: TimeInterval = 86_400) throws {
        let root = temporaryExportRoot
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let contents = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        for url in contents where url.lastPathComponent != "manifest.txt" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = values?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) >= maxAge {
                try? FileManager.default.removeItem(at: url)
            }
        }
        try? FileManager.default.removeItem(at: manifestURL)
    }
}

private enum SHA256Hash {
    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
