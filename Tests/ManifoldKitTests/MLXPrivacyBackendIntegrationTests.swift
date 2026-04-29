// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit
@testable import ManifoldRuntime

@Suite("MLX Privacy Backend Integration")
struct MLXPrivacyBackendIntegrationTests {
    func makeStorage() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-mlx-backend-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test(
        "Scans with local MLX MXFP8 model pack",
        .enabled(if: ProcessInfo.processInfo.environment["MANIFOLD_PRIVACY_MLX_MODEL_DIR"] != nil)
    )
    func scansWithLocalMLXModelPack() async throws {
        let storageURL = try makeStorage()
        defer { cleanup(storageURL) }

        let manager = PrivacyRuntimeManager(storageURL: storageURL)
        let backend = MLXPrivacyBackend(runtimeManager: manager)
        _ = try await backend.install()

        let result = try await backend.scan(
            PrivacyScanRequest(
                inputHash: "fixture",
                text: """
                Alice Smith uses alice@example.com and +1 415 555 0101. \
                Profile: https://private.example/alice. Account ACCT-938271. \
                Secret sk-test-abcdefghijklmnopqrstuv.
                """,
                categories: PrivacyCategory.allCases,
                operatingPoint: "default",
                contentKind: .document,
                backend: .mlx,
                agent: .codex,
                resourcePath: "fixture.txt",
                toolName: "read_file"
            )
        )

        #expect(result.backend == .mlx)
        #expect(result.spans.contains { $0.category == .email })
        #expect(result.spans.contains { $0.category == .privatePerson })
        #expect(result.spans.contains { $0.category == .phone })
        #expect(result.spans.contains { $0.category == .url })
        #expect(result.spans.contains { $0.category == .accountNumber })
        #expect(result.spans.contains { $0.category == .secret })

        let loadedInfo = await backend.modelInfo()
        #expect(loadedInfo.loaded)

        try await backend.uninstall()
        let removedInfo = await backend.modelInfo()
        #expect(!removedInfo.loaded)
        #expect(!removedInfo.available)
    }
}
