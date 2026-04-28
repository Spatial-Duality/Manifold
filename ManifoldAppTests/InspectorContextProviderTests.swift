// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
import ManifoldKit
@testable import Manifold

final class InspectorContextProviderTests: XCTestCase {

    private func makeFileID(_ path: String) -> InspectorFileID {
        InspectorFileID(sourceID: "src-1", relativePath: path)
    }

    /// A fetcher that records every call and returns a stub context.
    /// Used to verify cache hit/miss semantics without external state.
    private actor RecordingFetcher {
        private(set) var calls: [InspectorFileID] = []

        func record(_ fileID: InspectorFileID) {
            calls.append(fileID)
        }
    }

    func testCacheMissTriggersFetch() async throws {
        let recorder = RecordingFetcher()
        let provider = InspectorContextProvider { fileID in
            await recorder.record(fileID)
            return InspectorContext(fileID: fileID)
        }

        _ = try await provider.context(for: makeFileID("a.txt"))

        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 1)
    }

    func testCacheHitWithinTTLDoesNotFetchAgain() async throws {
        let recorder = RecordingFetcher()
        let provider = InspectorContextProvider { fileID in
            await recorder.record(fileID)
            return InspectorContext(fileID: fileID)
        }

        let id = makeFileID("a.txt")
        _ = try await provider.context(for: id)
        _ = try await provider.context(for: id)
        _ = try await provider.context(for: id)

        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 1, "Re-querying within TTL should not refetch")
    }

    func testCacheExpiryTriggersRefetch() async throws {
        let recorder = RecordingFetcher()
        var fakeNow = Date(timeIntervalSince1970: 1000)
        let provider = InspectorContextProvider(
            configuration: .init(ttl: .seconds(60), capacity: 10),
            clock: { fakeNow }
        ) { fileID in
            await recorder.record(fileID)
            return InspectorContext(fileID: fileID)
        }

        let id = makeFileID("a.txt")
        _ = try await provider.context(for: id)

        // Advance past TTL.
        fakeNow = fakeNow.addingTimeInterval(120)
        _ = try await provider.context(for: id)

        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 2, "Fetch should re-run after TTL expiry")
    }

    func testInvalidateClearsSpecificEntry() async throws {
        let recorder = RecordingFetcher()
        let provider = InspectorContextProvider { fileID in
            await recorder.record(fileID)
            return InspectorContext(fileID: fileID)
        }

        let a = makeFileID("a.txt")
        let b = makeFileID("b.txt")
        _ = try await provider.context(for: a)
        _ = try await provider.context(for: b)

        await provider.invalidate(a)

        // Querying a triggers a new fetch; b is still cached.
        _ = try await provider.context(for: a)
        _ = try await provider.context(for: b)

        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 3, "a.txt: 2 fetches (initial + after invalidate); b.txt: 1 fetch")
    }

    func testInvalidateAllClearsEverything() async throws {
        let recorder = RecordingFetcher()
        let provider = InspectorContextProvider { fileID in
            await recorder.record(fileID)
            return InspectorContext(fileID: fileID)
        }

        _ = try await provider.context(for: makeFileID("a.txt"))
        _ = try await provider.context(for: makeFileID("b.txt"))
        _ = try await provider.context(for: makeFileID("c.txt"))

        await provider.invalidateAll()

        let diag = await provider.diagnostics
        XCTAssertEqual(diag.entryCount, 0)

        // Re-query — should fetch fresh.
        _ = try await provider.context(for: makeFileID("a.txt"))
        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 4, "3 initial + 1 after invalidateAll")
    }

    func testLRUEvictionDropsOldestEntry() async throws {
        let recorder = RecordingFetcher()
        let provider = InspectorContextProvider(
            configuration: .init(ttl: .seconds(300), capacity: 3),
            clock: { Date() }
        ) { fileID in
            await recorder.record(fileID)
            return InspectorContext(fileID: fileID)
        }

        // Fill the cache.
        _ = try await provider.context(for: makeFileID("a.txt"))
        _ = try await provider.context(for: makeFileID("b.txt"))
        _ = try await provider.context(for: makeFileID("c.txt"))

        // Touch 'a' so 'b' becomes the oldest.
        _ = try await provider.context(for: makeFileID("a.txt"))

        // Add a 4th entry → should evict 'b' (oldest by access order).
        _ = try await provider.context(for: makeFileID("d.txt"))

        let diag = await provider.diagnostics
        XCTAssertEqual(diag.entryCount, 3)
        XCTAssertEqual(
            Set(diag.accessOrder.map(\.relativePath)),
            ["a.txt", "c.txt", "d.txt"],
            "b.txt should have been evicted"
        )
    }

    func testCachedContextReturnsNilWhenNotInCache() async {
        let provider = InspectorContextProvider { fileID in
            InspectorContext(fileID: fileID)
        }
        let cached = await provider.cachedContext(for: makeFileID("a.txt"))
        XCTAssertNil(cached)
    }

    func testCachedContextReturnsValueWithinTTL() async throws {
        let provider = InspectorContextProvider { fileID in
            InspectorContext(fileID: fileID)
        }

        let id = makeFileID("a.txt")
        _ = try await provider.context(for: id)
        let cached = await provider.cachedContext(for: id)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.fileID, id)
    }

    func testConcurrentFetchesForSameKeyDeduplicate() async throws {
        let recorder = RecordingFetcher()
        let provider = InspectorContextProvider { fileID in
            // Slow fetch so 5 concurrent requests overlap.
            try? await Task.sleep(for: .milliseconds(20))
            await recorder.record(fileID)
            return InspectorContext(fileID: fileID)
        }

        let id = makeFileID("a.txt")
        async let r1 = provider.context(for: id)
        async let r2 = provider.context(for: id)
        async let r3 = provider.context(for: id)
        async let r4 = provider.context(for: id)
        async let r5 = provider.context(for: id)
        _ = try await (r1, r2, r3, r4, r5)

        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 1,
            "5 concurrent fetches for the same key should hit the underlying fetcher exactly once")
    }
}
