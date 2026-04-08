import Foundation
import CommonCrypto
import ManifoldKit

// MARK: - File Browser Types

struct SourceFile: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let path: String
    let relativePath: String
    let sourceName: String
    let sourceID: String
    let fileExtension: String
    let sizeBytes: Int
    let modifiedDate: Date
    let isGrantedToClaude: Bool
    var versionCount: Int = 0
    var hasAIActivity: Bool = false
}

struct SearchResult: Identifiable, Sendable {
    let id = UUID()
    let fileName: String
    let filePath: String
    let sourceName: String
    let isGranted: Bool
    let canonicalPath: String
    let matches: [SearchMatch]
}

struct SearchMatch: Identifiable, Sendable {
    let id = UUID()
    let lineNumber: Int
    let lineText: String
}

// MARK: - Grant Path Resolution

struct ResolvedGrantPath {
    let mount: GrantMount
    let relativePath: String
    let fileURL: URL
}

// MARK: - Revert

enum RevertResult {
    case success
    case blobPruned
    case contentDrift
    case error(String)
}

extension Data {
    var sha256Hex: String {
        let hash = withUnsafeBytes { bytes -> [UInt8] in
            var hash = [UInt8](repeating: 0, count: 32)
            CC_SHA256(bytes.baseAddress, CC_LONG(count), &hash)
            return hash
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
