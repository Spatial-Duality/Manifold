// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Represents a file or folder in the lazy-loaded tree browser.
struct FileNode: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let fileSize: Int
    var children: [FileNode]?

    var isLoaded: Bool { children != nil }

    var iconName: String {
        if isDirectory { return "folder" }
        let ext = (name as NSString).pathExtension.lowercased()
        return switch ext {
        case "swift", "py", "js", "ts", "rb", "go", "rs": "doc.text"
        case "html", "css", "xml", "json", "yaml", "yml", "toml": "doc.text"
        case "md", "txt", "rtf": "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "ico": "photo"
        case "pdf": "doc.richtext"
        case "zip", "tar", "gz", "rar": "doc.zipper"
        case "mp4", "mov", "avi": "film"
        case "mp3", "wav", "aac": "music.note"
        case "ttf", "otf", "woff", "woff2": "textformat"
        default: "doc"
        }
    }

    /// Load children from disk (lazy, called on expand).
    static func loadChildren(at path: String) -> [FileNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        return items
            .filter { !$0.hasPrefix(".") } // skip hidden
            .sorted { lhs, rhs in
                let lhsPath = (path as NSString).appendingPathComponent(lhs)
                let rhsPath = (path as NSString).appendingPathComponent(rhs)
                let lhsDir = isDir(lhsPath)
                let rhsDir = isDir(rhsPath)
                if lhsDir != rhsDir { return lhsDir } // folders first
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .map { name in
                let fullPath = (path as NSString).appendingPathComponent(name)
                let dir = isDir(fullPath)
                let size = dir ? 0 : ((try? fm.attributesOfItem(atPath: fullPath)[.size] as? Int) ?? 0)
                return FileNode(name: name, path: fullPath, isDirectory: dir, fileSize: size)
            }
    }

    private static func isDir(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
