// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("ExposureStore")
struct ExposureStoreTests {
    func makeStore() throws -> (DatabaseConnection, ExposureStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-exposure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        return (db, ExposureStore(db: db), tempDir)
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Exposure previews roundtrip with truncation flag and resource lookup")
    func previewsRoundtrip() async throws {
        let (_, store, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let decision = AccessDecision(
            connectionID: "conn-1",
            agent: TargetApp.cowork.rawValue,
            toolName: "read_file",
            resourcePath: "shared/worklog.md",
            action: "read",
            allowed: true,
            reason: "Allowed by standing access",
            accessMode: "standing_access"
        )
        try await store.recordDecision(decision)

        let exposure = ExposureRecord(
            connectionID: "conn-1",
            agent: TargetApp.cowork.rawValue,
            toolName: "read_file",
            resourcePath: "shared/worklog.md",
            byteCount: 128,
            contentHash: "abc123",
            exposureType: "text",
            accessDecisionID: decision.id,
            payloadPreview: "preview text",
            payloadPreviewTruncated: true
        )
        try await store.recordExposure(exposure)

        let recent = try await store.exposures(connectionID: "conn-1", limit: 10)
        #expect(recent.count == 1)
        #expect(recent[0].payloadPreview == "preview text")
        #expect(recent[0].payloadPreviewTruncated)

        let byPath = try await store.exposures(resourcePath: "shared/worklog.md", limit: 10)
        #expect(byPath.count == 1)
        #expect(byPath[0].contentHash == "abc123")
    }
}
