// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

/// Owner-only directory and file permissions for Manifold-managed local state.
public enum LocalFileProtection: Sendable {
    public static let directoryMode: Int = 0o700
    public static let fileMode: Int = 0o600

    public static func ensureDirectory(at url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try secureItem(at: url, mode: directoryMode)
    }

    public static func secureFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try secureItem(at: url, mode: fileMode)
    }

    public static func writeOwnerOnly(_ data: Data, to url: URL, options: Data.WritingOptions = [.atomic]) throws {
        try ensureDirectory(at: url.deletingLastPathComponent())
        try data.write(to: url, options: options)
        try secureFile(at: url)
    }

    public static func copyOwnerOnlyItem(at sourceURL: URL, to destinationURL: URL) throws {
        let fm = FileManager.default
        try ensureDirectory(at: destinationURL.deletingLastPathComponent())
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.copyItem(at: sourceURL, to: destinationURL)
        try secureFile(at: destinationURL)
    }

    public static func posixPermissions(at url: URL) throws -> Int? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let permissions = attributes[.posixPermissions] as? NSNumber {
            return permissions.intValue
        }
        return nil
    }

    private static func secureItem(at url: URL, mode: Int) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: mode)],
            ofItemAtPath: url.path
        )
    }
}
