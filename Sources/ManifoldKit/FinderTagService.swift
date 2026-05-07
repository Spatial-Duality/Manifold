// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import os

private let finderTagLogger = Logger(subsystem: "com.spatialduality.manifold", category: "finder-tags")

public enum FinderTagService {
    public static func tagItems(
        at rootURL: URL,
        sourceID: String,
        tagName: String,
        recursive: Bool
    ) -> [FinderTaggedItemRecord] {
        let normalizedTag = normalizedTagName(tagName)
        guard !normalizedTag.isEmpty else { return [] }

        var records: [FinderTaggedItemRecord] = []
        let root = rootURL.standardizedFileURL
        tagOne(root, sourceID: sourceID, tagName: normalizedTag).map { records.append($0) }

        guard recursive, isDirectory(root) else { return records }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .tagNamesKey],
            options: [],
            errorHandler: { url, error in
                finderTagLogger.warning("Finder tag enumeration skipped \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return true
            }
        ) else {
            return records
        }

        while let url = enumerator.nextObject() as? URL {
            if isSymbolicLink(url) {
                enumerator.skipDescendants()
                continue
            }
            if let record = tagOne(url.standardizedFileURL, sourceID: sourceID, tagName: normalizedTag) {
                records.append(record)
            }
        }
        return records
    }

    public static func removeTag(_ tagName: String, from url: URL) {
        let normalizedTag = normalizedTagName(tagName)
        guard !normalizedTag.isEmpty else { return }
        do {
            var mutableURL = url.standardizedFileURL
            let values = try mutableURL.resourceValues(forKeys: [.tagNamesKey])
            var tags = values.tagNames ?? []
            guard let index = tags.firstIndex(of: normalizedTag) else { return }
            tags.remove(at: index)
            let writableURL = mutableURL as NSURL
            try writableURL.setResourceValue(nil, forKey: .tagNamesKey)
            try writableURL.setResourceValue(tags, forKey: .tagNamesKey)
            mutableURL.removeCachedResourceValue(forKey: .tagNamesKey)
            let remaining = try mutableURL.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
            if remaining.contains(normalizedTag) {
                try removeTagFromMetadataXattr(normalizedTag, at: mutableURL)
            }
        } catch {
            finderTagLogger.warning("Failed to remove Finder tag from \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    public static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }

    public static func normalizedTagName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tagOne(
        _ url: URL,
        sourceID: String,
        tagName: String
    ) -> FinderTaggedItemRecord? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            var mutableURL = url.standardizedFileURL
            var values = try mutableURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .tagNamesKey])
            guard values.isSymbolicLink != true else { return nil }
            var tags = values.tagNames ?? []
            if !tags.contains(tagName) {
                tags.append(tagName)
                values.tagNames = tags
                try mutableURL.setResourceValues(values)
            }
            return FinderTaggedItemRecord(
                sourceID: sourceID,
                originalPath: mutableURL.path,
                fileIdentity: try? SourceResolver.fileIdentity(at: mutableURL),
                isDirectory: values.isDirectory == true,
                tagName: tagName
            )
        } catch {
            finderTagLogger.warning("Failed to apply Finder tag to \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static func removeTagFromMetadataXattr(_ tagName: String, at url: URL) throws {
        let attributeName = "com.apple.metadata:_kMDItemUserTags"
        guard let data = try readExtendedAttribute(attributeName, at: url) else {
            return
        }
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard var rawTags = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        ) as? [String] else {
            return
        }

        rawTags.removeAll { rawTagDisplayName($0) == tagName }
        if rawTags.isEmpty {
            try removeExtendedAttribute(attributeName, at: url)
            return
        }

        let updated = try PropertyListSerialization.data(
            fromPropertyList: rawTags,
            format: .binary,
            options: 0
        )
        try writeExtendedAttribute(attributeName, data: updated, at: url)
    }

    private static func rawTagDisplayName(_ rawTag: String) -> String {
        rawTag.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? rawTag
    }

    private static func readExtendedAttribute(_ name: String, at url: URL) throws -> Data? {
        try url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            if size < 0 {
                if errno == ENOATTR { return nil }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { buffer in
                getxattr(path, name, buffer.baseAddress, size, 0, 0)
            }
            if read < 0 {
                if errno == ENOATTR { return nil }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if read < data.count {
                data.removeSubrange(read..<data.count)
            }
            return data
        }
    }

    private static func writeExtendedAttribute(_ name: String, data: Data, at url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            let result = data.withUnsafeBytes { buffer in
                setxattr(path, name, buffer.baseAddress, data.count, 0, 0)
            }
            if result != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    private static func removeExtendedAttribute(_ name: String, at url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            let result = removexattr(path, name, 0)
            if result != 0, errno != ENOATTR {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }
}
