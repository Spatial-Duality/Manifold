// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import ManifoldKit

enum PrivacyRuntimeManagerError: Error, LocalizedError {
    case unknownRuntime(String)
    case unsupportedArchitecture
    case invalidPackage(String)
    case checksumMismatch(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownRuntime(let id):
            return "Unknown privacy model runtime: \(id)"
        case .unsupportedArchitecture:
            return "Privacy Preflight requires Apple Silicon."
        case .invalidPackage(let message):
            return "Invalid privacy model package: \(message)"
        case .checksumMismatch(let path):
            return "Privacy model checksum mismatch for \(path)"
        case .downloadFailed(let message):
            return "Privacy model download failed: \(message)"
        }
    }
}

struct InstalledPrivacyRuntime: Sendable {
    let manifest: PrivacyRuntimeManifest
    let rootURL: URL
    let verificationState: PrivacyRuntimeVerificationState

    var isRunnable: Bool {
        manifest.capabilities.contains("mlx-mxfp8-logits")
            && manifest.capabilities.contains("swift-tokenizer")
            && manifest.capabilities.contains("swift-viterbi-decoder")
            && !manifest.modelPath.isEmpty
            && !manifest.tokenizerPath.isEmpty
            && !manifest.configPath.isEmpty
            && !manifest.viterbiCalibrationPath.isEmpty
    }

    var modelURL: URL {
        rootURL.appendingPathComponent(manifest.modelPath)
    }

    var tokenizerURL: URL {
        rootURL.appendingPathComponent(manifest.tokenizerPath)
    }

    var configURL: URL {
        rootURL.appendingPathComponent(manifest.configPath)
    }

    var viterbiCalibrationURL: URL {
        rootURL.appendingPathComponent(manifest.viterbiCalibrationPath)
    }
}

struct PrivacyRuntimeManifest: Sendable, Codable, Hashable {
    let schemaVersion: Int
    let runtimeID: String
    let displayName: String
    let publisher: String
    let version: String
    let sourceRepository: String
    let snapshotSHA: String
    let modelPath: String
    let modelIndexPath: String
    let tokenizerPath: String
    let tokenizerConfigPath: String
    let configPath: String
    let viterbiCalibrationPath: String
    let capabilities: [String]
    let checksums: [String: String]
    let totalBytes: Int64
    let createdAt: String
}

struct PrivacyModelCatalogFile: Sendable, Codable, Hashable {
    let path: String
    let sizeBytes: Int64
    let sha256: String
    let url: URL
}

struct PrivacyModelCatalog: Sendable, Hashable {
    let runtimeID: String
    let modelDirectoryName: String
    let displayName: String
    let publisher: String
    let version: String
    let snapshotSHA: String
    let sourceRepository: String
    let note: String
    let files: [PrivacyModelCatalogFile]

    var totalBytes: Int64 {
        files.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }

    var checksums: [String: String] {
        Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.sha256) })
    }

    var manifest: PrivacyRuntimeManifest {
        PrivacyRuntimeManifest(
            schemaVersion: 1,
            runtimeID: runtimeID,
            displayName: displayName,
            publisher: publisher,
            version: version,
            sourceRepository: sourceRepository,
            snapshotSHA: snapshotSHA,
            modelPath: "model.safetensors",
            modelIndexPath: "model.safetensors.index.json",
            tokenizerPath: "tokenizer.json",
            tokenizerConfigPath: "tokenizer_config.json",
            configPath: "config.json",
            viterbiCalibrationPath: "viterbi_calibration.json",
            capabilities: [
                "mlx-mxfp8-logits",
                "swift-tokenizer",
                "swift-viterbi-decoder",
            ],
            checksums: checksums,
            totalBytes: totalBytes,
            createdAt: ISO8601DateFormatter.shared.string(from: Date())
        )
    }

    static let openAIPrivacyFilterMXFP8: PrivacyModelCatalog = {
        let snapshot = "73372cab9eaf32ef2ccaa4e48ddbbcc63fa55a45"
        let base = "https://huggingface.co/mlx-community/openai-privacy-filter-mxfp8/resolve/\(snapshot)/"
        func file(_ path: String, size: Int64, sha256: String) -> PrivacyModelCatalogFile {
            PrivacyModelCatalogFile(
                path: path,
                sizeBytes: size,
                sha256: sha256,
                url: URL(string: base + path)!
            )
        }
        return PrivacyModelCatalog(
            runtimeID: PrivacyRuntimeDefaults.mlxRuntimeID,
            modelDirectoryName: "openai-privacy-filter-mxfp8",
            displayName: "Fast Local Scanner",
            publisher: "MLX Community / OpenAI",
            version: "2026-04-23-\(snapshot.prefix(12))",
            snapshotSHA: snapshot,
            sourceRepository: "https://huggingface.co/mlx-community/openai-privacy-filter-mxfp8",
            note: "MLX MXFP8 · 1.47 GB · Recommended for Apple Silicon Macs.",
            files: [
                file(
                    "model.safetensors",
                    size: 1_445_175_684,
                    sha256: "3f03343afa10abccc51a0b6452fde93696fb5ce9986e75a51b579a31e38e1d13"
                ),
                file(
                    "model.safetensors.index.json",
                    size: 15_753,
                    sha256: "3b902d8f79970beea9f60dfc8b20ac8bf6850d54e3342012e1b105e7ff0448f3"
                ),
                file(
                    "config.json",
                    size: 3_537,
                    sha256: "df9b4e94ae2ed5ed8babb622bb3bd4c2e062c0047363f6c89124cc092238ed81"
                ),
                file(
                    "tokenizer.json",
                    size: 27_868_174,
                    sha256: "0614fe83cadab421296e664e1f48f4261fa8fef6e03e63bb75c20f38e37d07d3"
                ),
                file(
                    "tokenizer_config.json",
                    size: 283,
                    sha256: "490477def5405c66ae43cf65756976a4c9963b4c20c148a392eb4c3a833b1725"
                ),
                file(
                    "viterbi_calibration.json",
                    size: 372,
                    sha256: "bbc8611ef08a55ed72d64856cbbbb9a91db8dfa881f0a92e2afbad6e4bbc775a"
                ),
            ]
        )
    }()
}

private struct PrivacyDownloadSnapshot: Sendable, Hashable {
    var state: PrivacyInstallState
    var downloadedBytes: Int64
    var totalBytes: Int64
    var lastError: String?

    var progress: Double? {
        guard totalBytes > 0 else { return nil }
        return min(1, max(0, Double(downloadedBytes) / Double(totalBytes)))
    }
}

enum PrivacyRuntimeHardware {
    static var supportsMLX: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}

actor PrivacyRuntimeManager {
    static let mlxRuntimeID = PrivacyRuntimeDefaults.mlxRuntimeID

    private let storageURL: URL
    private let catalog: PrivacyModelCatalog
    private let supportsMLX: Bool
    private let modelRootURL: URL
    private let stagingURL: URL
    private var downloadTask: Task<Void, Never>?
    private var downloadSnapshot: PrivacyDownloadSnapshot?

    init(
        storageURL: URL,
        catalog: PrivacyModelCatalog = .openAIPrivacyFilterMXFP8,
        supportsMLX: Bool = PrivacyRuntimeHardware.supportsMLX
    ) {
        self.storageURL = storageURL
        self.catalog = catalog
        self.supportsMLX = supportsMLX
        let modelsRoot = storageURL.appendingPathComponent("models", isDirectory: true)
        self.modelRootURL = modelsRoot.appendingPathComponent(catalog.modelDirectoryName, isDirectory: true)
        self.stagingURL = modelsRoot.appendingPathComponent(".\(catalog.modelDirectoryName)-staging", isDirectory: true)
    }

    func availableRuntimes() async -> [PrivacyRuntimeDescriptor] {
        if !supportsMLX {
            return [
                descriptor(
                    installState: .unavailable,
                    verificationState: .notInstalled,
                    installedVersion: nil,
                    sizeBytes: catalog.totalBytes,
                    note: "Privacy Preflight requires Apple Silicon."
                )
            ]
        }

        let installed = try? installedRuntime()
        if let installed {
            return [
                descriptor(
                    installState: .installed,
                    verificationState: installed.verificationState,
                    installedVersion: installed.manifest.version,
                    sizeBytes: directorySize(installed.rootURL),
                    note: "Verified MLX MXFP8 model pack is installed."
                )
            ]
        }

        if let snapshot = downloadSnapshot {
            return [
                descriptor(
                    installState: snapshot.state,
                    verificationState: snapshot.state == .verifying ? .unverified : .notInstalled,
                    installedVersion: nil,
                    sizeBytes: catalog.totalBytes,
                    downloadedBytes: snapshot.downloadedBytes,
                    totalBytes: snapshot.totalBytes,
                    downloadProgress: snapshot.progress,
                    note: snapshot.lastError ?? catalog.note
                )
            ]
        }

        return [
            descriptor(
                installState: .downloadRequired,
                verificationState: .notInstalled,
                installedVersion: nil,
                sizeBytes: catalog.totalBytes,
                downloadedBytes: 0,
                totalBytes: catalog.totalBytes,
                downloadProgress: 0,
                note: catalog.note
            )
        ]
    }

    func installedRuntime() throws -> InstalledPrivacyRuntime? {
        let manifestURL = modelRootURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }
        let manifest = try JSONDecoder().decode(
            PrivacyRuntimeManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let verification = try verify(manifest: manifest, rootURL: modelRootURL)
        return InstalledPrivacyRuntime(
            manifest: manifest,
            rootURL: modelRootURL,
            verificationState: verification
        )
    }

    @discardableResult
    func install(runtimeID: String) async throws -> InstalledPrivacyRuntime? {
        guard runtimeID == catalog.runtimeID else {
            throw PrivacyRuntimeManagerError.unknownRuntime(runtimeID)
        }
        guard supportsMLX else {
            throw PrivacyRuntimeManagerError.unsupportedArchitecture
        }

        if let packageURL = configuredPackageURL() {
            let installed = try installLocalPackage(packageURL)
            downloadSnapshot = nil
            return installed
        }

        if let installed = try installedRuntime() {
            return installed
        }

        if downloadTask == nil {
            downloadSnapshot = PrivacyDownloadSnapshot(
                state: .downloading,
                downloadedBytes: existingStagedBytes(),
                totalBytes: catalog.totalBytes,
                lastError: nil
            )
            downloadTask = Task {
                await self.runDownload()
            }
        }
        return nil
    }

    func uninstall(runtimeID: String) throws {
        guard runtimeID == catalog.runtimeID else {
            throw PrivacyRuntimeManagerError.unknownRuntime(runtimeID)
        }
        downloadTask?.cancel()
        downloadTask = nil
        downloadSnapshot = nil
        if FileManager.default.fileExists(atPath: modelRootURL.path) {
            try FileManager.default.removeItem(at: modelRootURL)
        }
        if FileManager.default.fileExists(atPath: stagingURL.path) {
            try FileManager.default.removeItem(at: stagingURL)
        }
    }

    func cleanupLegacyPrivacyRuntimes() {
        let legacyCLIURL = storageURL.appendingPathComponent("official-cli", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacyCLIURL.path) {
            try? FileManager.default.removeItem(at: legacyCLIURL)
        }
        let legacyModelRuntimeURL = storageURL
            .appendingPathComponent("runtimes", isDirectory: true)
            .appendingPathComponent("openai-privacy-filter-coreml", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacyModelRuntimeURL.path) {
            try? FileManager.default.removeItem(at: legacyModelRuntimeURL)
        }
    }

    private func descriptor(
        installState: PrivacyInstallState,
        verificationState: PrivacyRuntimeVerificationState,
        installedVersion: String?,
        sizeBytes: Int64?,
        downloadedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        downloadProgress: Double? = nil,
        note: String?
    ) -> PrivacyRuntimeDescriptor {
        PrivacyRuntimeDescriptor(
            id: catalog.runtimeID,
            displayName: catalog.displayName,
            publisher: catalog.publisher,
            installedVersion: installedVersion,
            availableVersion: catalog.version,
            sizeBytes: sizeBytes,
            installState: installState,
            verificationState: verificationState,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            downloadProgress: downloadProgress,
            sourceRepository: catalog.sourceRepository,
            note: note
        )
    }

    private func runDownload() async {
        do {
            try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
            for file in catalog.files {
                try Task.checkCancellation()
                try await download(file)
            }

            downloadSnapshot = PrivacyDownloadSnapshot(
                state: .verifying,
                downloadedBytes: catalog.totalBytes,
                totalBytes: catalog.totalBytes,
                lastError: nil
            )
            try writeManifest(to: stagingURL)
            _ = try verify(manifest: catalog.manifest, rootURL: stagingURL)
            try promoteStagingPackage()
            downloadSnapshot = PrivacyDownloadSnapshot(
                state: .installed,
                downloadedBytes: catalog.totalBytes,
                totalBytes: catalog.totalBytes,
                lastError: nil
            )
        } catch is CancellationError {
            downloadSnapshot = PrivacyDownloadSnapshot(
                state: .downloadRequired,
                downloadedBytes: existingStagedBytes(),
                totalBytes: catalog.totalBytes,
                lastError: nil
            )
        } catch {
            downloadSnapshot = PrivacyDownloadSnapshot(
                state: .downloadRequired,
                downloadedBytes: existingStagedBytes(),
                totalBytes: catalog.totalBytes,
                lastError: error.localizedDescription
            )
        }
        downloadTask = nil
    }

    private func download(_ file: PrivacyModelCatalogFile) async throws {
        let destination = stagingURL.appendingPathComponent(file.path)
        if FileManager.default.fileExists(atPath: destination.path),
           (try? sha256Hex(for: destination))?.caseInsensitiveCompare(file.sha256) == .orderedSame {
            updateDownloadProgress()
            return
        }

        let partial = destination.appendingPathExtension("part")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existingBytes = fileSize(partial) ?? 0
        var request = URLRequest(url: file.url)
        if existingBytes > 0 {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse {
            guard (200...299).contains(http.statusCode) else {
                throw PrivacyRuntimeManagerError.downloadFailed("\(file.path) returned HTTP \(http.statusCode)")
            }
            if existingBytes > 0, http.statusCode != 206 {
                try? FileManager.default.removeItem(at: partial)
            }
        }

        do {
            if !FileManager.default.fileExists(atPath: partial.path) {
                _ = FileManager.default.createFile(atPath: partial.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: partial)
            try handle.seekToEnd()
            defer {
                try? handle.close()
            }

            var buffer = Data()
            buffer.reserveCapacity(1_048_576)
            for try await byte in bytes {
                try Task.checkCancellation()
                buffer.append(byte)
                if buffer.count >= 1_048_576 {
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                    updateDownloadProgress()
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
            }
        }

        let actualHash = try sha256Hex(for: partial)
        guard actualHash.caseInsensitiveCompare(file.sha256) == .orderedSame else {
            throw PrivacyRuntimeManagerError.checksumMismatch(file.path)
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: partial, to: destination)
        updateDownloadProgress()
    }

    private func installLocalPackage(_ packageURL: URL) throws -> InstalledPrivacyRuntime {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: modelRootURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let localStaging = modelRootURL.deletingLastPathComponent()
            .appendingPathComponent(".\(catalog.runtimeID)-local-\(UUID().uuidString)", isDirectory: true)
        try fileManager.copyItem(at: packageURL, to: localStaging)
        if !fileManager.fileExists(atPath: localStaging.appendingPathComponent("manifest.json").path) {
            try writeManifest(to: localStaging)
        }
        _ = try verify(manifest: catalog.manifest, rootURL: localStaging)
        if fileManager.fileExists(atPath: modelRootURL.path) {
            try fileManager.removeItem(at: modelRootURL)
        }
        try fileManager.moveItem(at: localStaging, to: modelRootURL)
        guard let installed = try installedRuntime() else {
            throw PrivacyRuntimeManagerError.invalidPackage("Installed model pack could not be reopened")
        }
        return installed
    }

    private func promoteStagingPackage() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: modelRootURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let replacement = modelRootURL.deletingLastPathComponent()
            .appendingPathComponent(".\(catalog.modelDirectoryName)-replacement-\(UUID().uuidString)", isDirectory: true)
        if fileManager.fileExists(atPath: replacement.path) {
            try fileManager.removeItem(at: replacement)
        }
        try fileManager.moveItem(at: stagingURL, to: replacement)
        if fileManager.fileExists(atPath: modelRootURL.path) {
            try fileManager.removeItem(at: modelRootURL)
        }
        try fileManager.moveItem(at: replacement, to: modelRootURL)
    }

    private func writeManifest(to rootURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(catalog.manifest)
            .write(to: rootURL.appendingPathComponent("manifest.json"), options: [.atomic])
    }

    private func verify(
        manifest: PrivacyRuntimeManifest,
        rootURL: URL
    ) throws -> PrivacyRuntimeVerificationState {
        guard manifest.schemaVersion >= 1 else {
            throw PrivacyRuntimeManagerError.invalidPackage("Unsupported manifest schema version")
        }
        guard manifest.runtimeID == catalog.runtimeID else {
            throw PrivacyRuntimeManagerError.invalidPackage("Manifest runtimeID does not match \(catalog.runtimeID)")
        }
        guard manifest.snapshotSHA == catalog.snapshotSHA else {
            throw PrivacyRuntimeManagerError.invalidPackage("Manifest snapshot does not match pinned catalog")
        }
        guard FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("manifest.json").path) else {
            throw PrivacyRuntimeManagerError.invalidPackage("Missing manifest.json")
        }

        let requiredPaths = [
            manifest.modelPath,
            manifest.modelIndexPath,
            manifest.tokenizerPath,
            manifest.tokenizerConfigPath,
            manifest.configPath,
            manifest.viterbiCalibrationPath,
        ]
        for path in requiredPaths {
            guard manifest.checksums[path] != nil else {
                throw PrivacyRuntimeManagerError.invalidPackage("Missing checksum for \(path)")
            }
            let url = try packageFileURL(relativePath: path, rootURL: rootURL)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw PrivacyRuntimeManagerError.invalidPackage("Missing file \(path)")
            }
        }

        for file in catalog.files {
            let url = try packageFileURL(relativePath: file.path, rootURL: rootURL)
            let actualHash = try sha256Hex(for: url)
            guard actualHash.caseInsensitiveCompare(file.sha256) == .orderedSame else {
                throw PrivacyRuntimeManagerError.checksumMismatch(file.path)
            }
        }
        return .checksumVerified
    }

    private func configuredPackageURL() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let path = env["MANIFOLD_PRIVACY_MLX_MODEL_DIR"],
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        let localPackage = storageURL.appendingPathComponent("incoming-model", isDirectory: true)
        if FileManager.default.fileExists(atPath: localPackage.path) {
            return localPackage
        }
        return nil
    }

    private func updateDownloadProgress() {
        downloadSnapshot = PrivacyDownloadSnapshot(
            state: .downloading,
            downloadedBytes: existingStagedBytes(),
            totalBytes: catalog.totalBytes,
            lastError: nil
        )
    }

    private func existingStagedBytes() -> Int64 {
        catalog.files.reduce(Int64(0)) { total, file in
            let complete = stagingURL.appendingPathComponent(file.path)
            if let size = fileSize(complete), size == file.sizeBytes {
                return total + size
            }
            let partial = complete.appendingPathExtension("part")
            return total + min(fileSize(partial) ?? 0, file.sizeBytes)
        }
    }

    private func packageFileURL(relativePath: String, rootURL: URL) throws -> URL {
        guard !relativePath.isEmpty, !(relativePath as NSString).isAbsolutePath else {
            throw PrivacyRuntimeManagerError.invalidPackage("Package paths must be relative")
        }
        let components = relativePath.split(separator: "/").map(String.init)
        guard components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw PrivacyRuntimeManagerError.invalidPackage("Package paths cannot escape the model root")
        }
        return components.reduce(rootURL) { url, component in
            url.appendingPathComponent(component)
        }
    }

    private func directorySize(_ url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }
            size += Int64(values.fileSize ?? 0)
        }
        return size
    }

    private func fileSize(_ url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let size = values.fileSize else {
            return nil
        }
        return Int64(size)
    }

    private func sha256Hex(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 4 * 1_024 * 1_024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
