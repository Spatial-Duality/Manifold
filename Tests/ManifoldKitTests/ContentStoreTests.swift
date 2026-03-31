import Testing
import Foundation
@testable import ManifoldKit

@Suite("ContentStore")
struct ContentStoreTests {
    func makeTempStore() throws -> (ContentStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let store = try ContentStore(rootURL: tempDir)
        return (store, tempDir)
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Ingest data and retrieve by hash")
    func ingestAndRetrieve() async throws {
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }

        let content = "Hello, Manifold!".data(using: .utf8)!
        let hash = try await store.ingest(data: content)

        #expect(!hash.isEmpty)
        #expect(hash.count == 64) // SHA-256 hex = 64 chars

        let retrieved = try await store.retrieve(hash: hash)
        #expect(retrieved == content)
    }

    @Test("Deduplication — same content produces same hash, stored once")
    func deduplication() async throws {
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }

        let content = "Duplicate content".data(using: .utf8)!
        let hash1 = try await store.ingest(data: content)
        let hash2 = try await store.ingest(data: content)

        #expect(hash1 == hash2)
        let count = try await store.blobCount()
        #expect(count == 1)
    }

    @Test("Different content produces different hashes")
    func differentContent() async throws {
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }

        let hash1 = try await store.ingest(data: "Content A".data(using: .utf8)!)
        let hash2 = try await store.ingest(data: "Content B".data(using: .utf8)!)

        #expect(hash1 != hash2)
        let count = try await store.blobCount()
        #expect(count == 2)
    }

    @Test("Retrieve nonexistent hash returns nil")
    func retrieveNonexistent() async throws {
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }

        let data = try await store.retrieve(hash: "0000000000000000000000000000000000000000000000000000000000000000")
        #expect(data == nil)
    }

    @Test("Ref count increment and decrement")
    func refCounting() async throws {
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }

        let hash = try await store.ingest(data: "Ref counted".data(using: .utf8)!)
        try await store.incrementRef(hash: hash)
        try await store.incrementRef(hash: hash)

        // Should still exist
        #expect(await store.exists(hash: hash))

        try await store.decrementRef(hash: hash)
        try await store.decrementRef(hash: hash)

        // ref_count is now 0, GC should remove it
        let removed = try await store.garbageCollect()
        #expect(removed == 1)
        #expect(try await store.retrieve(hash: hash) == nil)
    }

    @Test("Ingest file from URL")
    func ingestFromFile() async throws {
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }

        let fileURL = tempDir.appendingPathComponent("test-file.txt")
        try "File content here".data(using: .utf8)!.write(to: fileURL)

        let hash = try await store.ingest(fileURL: fileURL)
        let retrieved = try await store.retrieve(hash: hash)
        #expect(retrieved == "File content here".data(using: .utf8))
    }
}
