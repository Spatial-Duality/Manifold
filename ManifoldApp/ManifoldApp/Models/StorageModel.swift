// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "storage")

@Observable
@MainActor
final class StorageModel {
    var allTrackedFiles: [String] = []
    var storageUsed: Int64 = 0

    private var client: (any RuntimeClientProtocol)?

    init() {}

    func configure(client: any RuntimeClientProtocol) {
        self.client = client
    }

    func loadTrackedFiles() async {
        guard let client else { return }
        do {
            allTrackedFiles = try await client.trackedFiles()
        } catch {
            logger.error("Failed to load tracked files: \(error.localizedDescription)")
            allTrackedFiles = []
        }
    }

    func loadStorageStats() async {
        guard let client else { return }
        do {
            let stats = try await client.storageStats()
            storageUsed = stats.storageUsed
        } catch {
            logger.warning("Failed to load storage stats: \(error.localizedDescription)")
            storageUsed = 0
        }
    }

    func fileHistory(filePath: String) async -> [SnapshotRecord] {
        guard let client else { return [] }
        return (try? await client.fileHistory(filePath: filePath)) ?? []
    }

    func snapshotData(hash: String) async -> Data? {
        guard let client else { return nil }
        return try? await client.snapshotData(hash: hash)
    }

    func runGarbageCollection() async -> Int {
        guard let client else { return 0 }
        return (try? await client.runGarbageCollection()) ?? 0
    }

    func runIntegrityCheck() async -> Bool {
        guard let client else { return false }
        return (try? await client.runIntegrityCheck()) ?? false
    }
}
