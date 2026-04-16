// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// SourceSizeFormatter — renders the cached file count + byte size on a
// SourceRecord into a compact "1,234 files · 84 MB" sentence. Silent
// (returns nil) when the source hasn't been walked yet — Principle 10:
// we never fabricate "0 files" for a source we haven't scanned.

import Foundation
import ManifoldKit

enum SourceSizeFormatter {
    /// Compact "{count} files · {size}" for UI rows. Nil when the source
    /// has no cached size reading. Uses ByteCountFormatter with file
    /// style for consistency with Finder.
    static func summary(for source: SourceRecord) -> String? {
        guard let count = source.fileCount, let bytes = source.cachedSizeBytes else {
            return nil
        }
        let countLabel = count == 1 ? "1 file" : "\(formatCount(count)) files"
        let sizeLabel = formatBytes(bytes)
        return "\(countLabel) · \(sizeLabel)"
    }

    /// Long-form variant used in consequence-confirmation sentences, e.g.
    /// "2,143 files (~84 MB)". Nil when unknown.
    static func confirmation(for source: SourceRecord) -> String? {
        guard let count = source.fileCount, let bytes = source.cachedSizeBytes else {
            return nil
        }
        return "\(formatCount(count)) files (~\(formatBytes(bytes)))"
    }

    private static func formatCount(_ count: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f.string(fromByteCount: bytes)
    }
}
