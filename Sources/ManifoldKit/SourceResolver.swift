// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

public struct SourceResolution: Sendable, Hashable {
    public let sourceID: String
    public let resolvedRootPath: String?
    public let bookmarkDataBase64: String?
    public let health: SourceHealthStatus
    public let detail: String?
    public let rootFileIdentity: String?
    public let lastResolvedAt: String

    public var isUsable: Bool { health.isUsable }
}

public enum SourceResolver: Sendable {
    public static func bookmarkDataBase64(for url: URL, securityScoped: Bool = true) throws -> String {
        let options: URL.BookmarkCreationOptions = securityScoped ? [.withSecurityScope] : []
        let bookmark = try url.standardizedFileURL.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return bookmark.base64EncodedString()
    }

    public static func resolve(_ source: SourceRecord) -> SourceResolution {
        let now = ISO8601DateFormatter.shared.string(from: Date())

        if let encoded = source.bookmarkDataBase64,
           let data = Data(base64Encoded: encoded) {
            return resolveBookmarkBackedSource(source, data: data, now: now)
        }

        return resolvePathBackedSource(source, now: now)
    }

    public static func fileIdentity(at url: URL) throws -> String {
        var state = stat()
        guard lstat(url.path, &state) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
        }
        return "\(state.st_dev):\(state.st_ino):\(state.st_birthtimespec.tv_sec):\(state.st_birthtimespec.tv_nsec)"
    }

    private static func resolveBookmarkBackedSource(
        _ source: SourceRecord,
        data: Data,
        now: String
    ) -> SourceResolution {
        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ).standardizedFileURL

            return resolvedBookmark(source, url: url, stale: stale, now: now, startSecurityScope: true)
        } catch {
            do {
                var stale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ).standardizedFileURL

                return resolvedBookmark(source, url: url, stale: stale, now: now, startSecurityScope: false)
            } catch {
                return unresolvedBookmarkFallback(source, error: error, now: now)
            }
        }
    }

    private static func resolvedBookmark(
        _ source: SourceRecord,
        url: URL,
        stale: Bool,
        now: String,
        startSecurityScope: Bool
    ) -> SourceResolution {
        let didStart = startSecurityScope && url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let checked = checkResolvedURL(url, source: source)
        guard checked.health.isUsable else {
            return SourceResolution(
                sourceID: source.sourceID,
                resolvedRootPath: checked.path,
                bookmarkDataBase64: source.bookmarkDataBase64,
                health: checked.health,
                detail: checked.detail,
                rootFileIdentity: checked.identity,
                lastResolvedAt: now
            )
        }

        let health: SourceHealthStatus
        if url.path != source.originalRootPath {
            health = .moved
        } else if stale, source.rootFileIdentity != nil {
            return SourceResolution(
                sourceID: source.sourceID,
                resolvedRootPath: url.path,
                bookmarkDataBase64: source.bookmarkDataBase64,
                health: .replaced,
                detail: "The bookmark is stale at the saved path, so Manifold treats the source as replaced until it is reconnected.",
                rootFileIdentity: checked.identity,
                lastResolvedAt: now
            )
        } else if stale {
            health = .staleBookmark
        } else {
            health = .available
        }

        return SourceResolution(
            sourceID: source.sourceID,
            resolvedRootPath: url.path,
            bookmarkDataBase64: source.bookmarkDataBase64,
            health: health,
            detail: stale ? "The bookmark is stale and should be refreshed." : checked.detail,
            rootFileIdentity: checked.identity,
            lastResolvedAt: now
        )
    }

    private static func unresolvedBookmarkFallback(
        _ source: SourceRecord,
        error: Error,
        now: String
    ) -> SourceResolution {
        let fallback = resolvePathBackedSource(source, now: now)
        if fallback.health == .moved || fallback.health == .missing || fallback.health == .replaced || fallback.health == .invalid {
            return SourceResolution(
                sourceID: source.sourceID,
                resolvedRootPath: fallback.resolvedRootPath,
                bookmarkDataBase64: source.bookmarkDataBase64,
                health: fallback.health,
                detail: fallback.detail,
                rootFileIdentity: fallback.rootFileIdentity,
                lastResolvedAt: now
            )
        }
        if fallback.health == .available {
            return SourceResolution(
                sourceID: source.sourceID,
                resolvedRootPath: fallback.resolvedRootPath,
                bookmarkDataBase64: source.bookmarkDataBase64,
                health: .staleBookmark,
                detail: "The saved bookmark could not be resolved, but the approved item still exists at its saved location.",
                rootFileIdentity: fallback.rootFileIdentity,
                lastResolvedAt: now
            )
        }
        return SourceResolution(
            sourceID: source.sourceID,
            resolvedRootPath: nil,
            bookmarkDataBase64: source.bookmarkDataBase64,
            health: .needsPermission,
            detail: error.localizedDescription,
            rootFileIdentity: source.rootFileIdentity,
            lastResolvedAt: now
        )
    }

    private static func resolvePathBackedSource(_ source: SourceRecord, now: String) -> SourceResolution {
        let url = URL(fileURLWithPath: source.originalRootPath).standardizedFileURL
        let checked = checkResolvedURL(url, source: source)
        return SourceResolution(
            sourceID: source.sourceID,
            resolvedRootPath: checked.path,
            bookmarkDataBase64: source.bookmarkDataBase64,
            health: checked.health,
            detail: checked.detail,
            rootFileIdentity: checked.identity,
            lastResolvedAt: now
        )
    }

    private static func checkResolvedURL(
        _ url: URL,
        source: SourceRecord
    ) -> (path: String?, health: SourceHealthStatus, detail: String?, identity: String?) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            if let movedURL = nearbyMovedURL(for: source) {
                return (
                    movedURL.path,
                    .moved,
                    "The approved item moved from its saved location.",
                    source.rootFileIdentity
                )
            }
            return (url.path, .missing, "The approved item no longer exists at this location.", source.rootFileIdentity)
        }
        guard isDirectory.boolValue || source.sourceKind == .file else {
            return (url.path, .invalid, "The approved source is not a folder.", nil)
        }
        do {
            let identity = try fileIdentity(at: url)
            if let stored = source.rootFileIdentity, stored != identity {
                return (url.path, .replaced, "A different item now exists at the approved location.", identity)
            }
            return (url.path, .available, nil, identity)
        } catch {
            return (url.path, .needsPermission, error.localizedDescription, source.rootFileIdentity)
        }
    }

    private static func nearbyMovedURL(for source: SourceRecord) -> URL? {
        guard let storedIdentity = source.rootFileIdentity else { return nil }
        let originalURL = URL(fileURLWithPath: source.originalRootPath).standardizedFileURL
        let parentURL = originalURL.deletingLastPathComponent()
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for candidate in candidates {
            guard (try? fileIdentity(at: candidate)) == storedIdentity else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
                continue
            }
            guard isDirectory.boolValue || source.sourceKind == .file else {
                continue
            }
            return candidate.standardizedFileURL
        }
        return nil
    }
}
