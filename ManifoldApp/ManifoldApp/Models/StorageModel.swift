import Foundation
import os
import ManifoldKit

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "storage")

@Observable
@MainActor
final class StorageModel {
    var allTrackedFiles: [String] = []
    var storageUsed: Int64 = 0
    var blobCount: Int = 0

    private var snapshotStore: SnapshotStore?
    private var contentStore: ContentStore?
    private var db: DatabaseConnection?

    init() {}

    func configure(snapshotStore: SnapshotStore, contentStore: ContentStore, db: DatabaseConnection) {
        self.snapshotStore = snapshotStore
        self.contentStore = contentStore
        self.db = db
    }

    func loadTrackedFiles() async {
        do {
            allTrackedFiles = try await snapshotStore?.allTrackedFiles() ?? []
        } catch {
            logger.error("Failed to load tracked files: \(error.localizedDescription)")
            allTrackedFiles = []
        }
    }

    func loadStorageStats() async {
        do { storageUsed = try await contentStore?.totalSize() ?? 0 }
        catch { logger.warning("Failed to load storage size: \(error.localizedDescription)"); storageUsed = 0 }
        do { blobCount = try await contentStore?.blobCount() ?? 0 }
        catch { logger.warning("Failed to load blob count: \(error.localizedDescription)"); blobCount = 0 }
    }

    func fileHistory(filePath: String) async -> [SnapshotRecord] {
        (try? await snapshotStore?.fileHistory(filePath: filePath)) ?? []
    }

    func snapshotData(hash: String) async -> Data? {
        try? await contentStore?.retrieve(hash: hash)
    }

    func runGarbageCollection() async -> Int {
        (try? await contentStore?.garbageCollect()) ?? 0
    }

    func pruneOldRuns() async -> Int {
        (try? await snapshotStore?.pruneOldRuns(keepLast: 10)) ?? 0
    }

    func runIntegrityCheck() async -> Bool {
        (try? db?.integrityCheck()) ?? false
    }
}
