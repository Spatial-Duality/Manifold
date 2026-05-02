// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import Testing
@testable import ManifoldKit
@testable import ManifoldRuntime

@Suite("Privacy Model Pack Manager")
struct PrivacyRuntimeManagerTests {
    func makeStorage() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-runtime-manager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func makeCatalog(files: [String: Data], checksumOverride: (String, String)? = nil) -> PrivacyModelCatalog {
        PrivacyModelCatalog(
            runtimeID: PrivacyRuntimeDefaults.mlxRuntimeID,
            modelDirectoryName: "test-openai-privacy-filter-mxfp8",
            displayName: PrivacyRuntimeDefaults.displayName,
            publisher: "Test",
            version: "test-snapshot",
            snapshotSHA: "test-snapshot-sha",
            sourceRepository: "https://example.invalid/model",
            note: "Test MLX model pack.",
            files: files.keys.sorted().map { path in
                let data = files[path] ?? Data()
                let hash = checksumOverride?.0 == path ? checksumOverride?.1 ?? sha256(data) : sha256(data)
                return PrivacyModelCatalogFile(
                    path: path,
                    sizeBytes: Int64(data.count),
                    sha256: hash,
                    url: URL(string: "https://example.invalid/\(path)")!
                )
            }
        )
    }

    func requiredFiles() -> [String: Data] {
        [
            "model.safetensors": Data("model".utf8),
            "model.safetensors.index.json": Data(#"{"weight_map":{}}"#.utf8),
            "config.json": Data(#"{"model_type":"openai_privacy_filter"}"#.utf8),
            "tokenizer.json": Data(#"{"model":"tokenizer"}"#.utf8),
            "tokenizer_config.json": Data(#"{}"#.utf8),
            "viterbi_calibration.json": Data(#"{}"#.utf8),
        ]
    }

    func writeIncomingPackage(storageURL: URL, files: [String: Data]) throws -> URL {
        let packageURL = storageURL.appendingPathComponent("incoming-model", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        for (path, data) in files {
            try data.write(to: packageURL.appendingPathComponent(path))
        }
        return packageURL
    }

    @Test("Installs verified incoming MLX model package")
    func installsVerifiedIncomingPackage() async throws {
        let storageURL = try makeStorage()
        defer { cleanup(storageURL) }
        let files = requiredFiles()
        _ = try writeIncomingPackage(storageURL: storageURL, files: files)

        let manager = PrivacyRuntimeManager(
            storageURL: storageURL,
            catalog: makeCatalog(files: files),
            supportsMLX: true
        )
        let installed = try #require(try await manager.install(runtimeID: PrivacyRuntimeDefaults.mlxRuntimeID))

        #expect(installed.manifest.version == "test-snapshot")
        #expect(installed.verificationState == .checksumVerified)
        #expect(installed.isRunnable)
        let descriptor = try #require(await manager.availableRuntimes().first)
        #expect(descriptor.installState == .installed)
        #expect(descriptor.installedVersion == "test-snapshot")
        #expect(descriptor.verificationState == .checksumVerified)
    }

    @Test("Rejects incoming MLX model package with checksum mismatch")
    func rejectsChecksumMismatch() async throws {
        let storageURL = try makeStorage()
        defer { cleanup(storageURL) }
        let files = requiredFiles()
        _ = try writeIncomingPackage(storageURL: storageURL, files: files)

        let manager = PrivacyRuntimeManager(
            storageURL: storageURL,
            catalog: makeCatalog(files: files, checksumOverride: ("model.safetensors", String(repeating: "0", count: 64))),
            supportsMLX: true
        )
        await #expect(throws: PrivacyRuntimeManagerError.self) {
            _ = try await manager.install(runtimeID: PrivacyRuntimeDefaults.mlxRuntimeID)
        }
    }

    @Test("Rejects partial incoming MLX model package")
    func rejectsPartialPackage() async throws {
        let storageURL = try makeStorage()
        defer { cleanup(storageURL) }
        let files = requiredFiles()
        var partial = files
        partial.removeValue(forKey: "tokenizer.json")
        _ = try writeIncomingPackage(storageURL: storageURL, files: partial)

        let manager = PrivacyRuntimeManager(
            storageURL: storageURL,
            catalog: makeCatalog(files: files),
            supportsMLX: true
        )
        await #expect(throws: PrivacyRuntimeManagerError.self) {
            _ = try await manager.install(runtimeID: PrivacyRuntimeDefaults.mlxRuntimeID)
        }
    }

    @Test("Marks MLX runtime unavailable on unsupported hardware")
    func rejectsUnsupportedHardware() async throws {
        let storageURL = try makeStorage()
        defer { cleanup(storageURL) }
        let files = requiredFiles()
        let manager = PrivacyRuntimeManager(
            storageURL: storageURL,
            catalog: makeCatalog(files: files),
            supportsMLX: false
        )

        let descriptor = try #require(await manager.availableRuntimes().first)
        #expect(descriptor.installState == .unavailable)
        await #expect(throws: PrivacyRuntimeManagerError.self) {
            _ = try await manager.install(runtimeID: PrivacyRuntimeDefaults.mlxRuntimeID)
        }
    }

    @Test("Available runtime exposes OpenAI Privacy Filter metadata")
    func availableRuntimeExposesOpenAIPrivacyFilterMetadata() async throws {
        let storageURL = try makeStorage()
        defer { cleanup(storageURL) }
        let manager = PrivacyRuntimeManager(storageURL: storageURL, supportsMLX: true)

        let descriptor = try #require(await manager.availableRuntimes().first)

        #expect(descriptor.id == PrivacyRuntimeDefaults.mlxRuntimeID)
        #expect(descriptor.displayName == PrivacyRuntimeDefaults.displayName)
        #expect(descriptor.publisher == PrivacyRuntimeDefaults.publisherName)
        #expect(descriptor.sourceRepository == PrivacyRuntimeDefaults.installedModelRepositoryURL)
        #expect(descriptor.installState == .downloadRequired)
    }
}
