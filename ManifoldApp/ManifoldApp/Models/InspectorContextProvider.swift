// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

// ┌──────────────────────────────────────────────────────────────────────────┐
// │ InspectorContextProvider                                                 │
// │                                                                          │
// │ Per-fileID LRU cache with TTL, invalidated on grant lifecycle events.    │
// │                                                                          │
// │ Why: per eng-review Issue 3, the inspector fans out to 5 backend stores  │
// │ per file selection (ledger, findings, exposures, memory, tool metrics).  │
// │ A power user clicking 50 unique files in 30s without caching = 250+      │
// │ XPC round trips. With cache + grant-event invalidation, a re-click is    │
// │ instant and freshness is honest.                                         │
// │                                                                          │
// │ Cache invalidation hooks (called by AppRuntimeClient when relevant):     │
// │   - grantStarted    → invalidateAll()                                    │
// │   - grantEnded      → invalidateAll()                                    │
// │   - exposureRecorded(fileID) → invalidate(fileID)                        │
// │   - visibilityToggled(fileID) → invalidate(fileID)                       │
// └──────────────────────────────────────────────────────────────────────────┘

/// Fetches per-file inspector data, deduplicates concurrent fetches for the
/// same key, and caches results until invalidated or aged out.
public actor InspectorContextProvider {
    public struct Configuration: Sendable {
        /// Time-to-live for a cached entry. After this, the next fetch
        /// re-queries even if the entry is still in the LRU.
        public var ttl: Duration
        /// Maximum number of entries the LRU keeps. Older entries are
        /// evicted when the cache exceeds this size.
        public var capacity: Int

        public init(ttl: Duration = .seconds(300), capacity: Int = 200) {
            self.ttl = ttl
            self.capacity = capacity
        }
    }

    public typealias SectionFetcher = @Sendable (InspectorFileID) async throws -> InspectorContext

    private let configuration: Configuration
    private let fetcher: SectionFetcher
    private let clock: @Sendable () -> Date

    private var cache: [InspectorFileID: CacheEntry] = [:]
    /// LRU access order — most recently used at the end.
    private var accessOrder: [InspectorFileID] = []
    private var inFlight: [InspectorFileID: Task<InspectorContext, Error>] = [:]

    public init(
        configuration: Configuration = Configuration(),
        clock: @Sendable @escaping () -> Date = { Date() },
        fetcher: @escaping SectionFetcher
    ) {
        self.configuration = configuration
        self.fetcher = fetcher
        self.clock = clock
    }

    // MARK: - Public API

    /// Returns inspector data for a file, hitting the cache when fresh and
    /// fetching otherwise. Concurrent calls for the same file await a
    /// single fetch (no thundering herd).
    public func context(for fileID: InspectorFileID) async throws -> InspectorContext {
        let now = clock()
        if let entry = cache[fileID], !entry.isExpired(at: now, ttl: configuration.ttl) {
            touchAccessOrder(fileID)
            return entry.value
        }
        if let pending = inFlight[fileID] {
            return try await pending.value
        }
        let task = Task<InspectorContext, Error> {
            try await self.fetcher(fileID)
        }
        inFlight[fileID] = task
        defer { inFlight[fileID] = nil }

        let context = try await task.value
        store(context: context, at: now)
        return context
    }

    /// Returns a cached entry without fetching. Useful for previews and
    /// when the UI just wants to render last-known state without blocking.
    public func cachedContext(for fileID: InspectorFileID) -> InspectorContext? {
        guard let entry = cache[fileID] else { return nil }
        if entry.isExpired(at: clock(), ttl: configuration.ttl) { return nil }
        return entry.value
    }

    /// Drop a single file's cached context. Call when an event indicates
    /// that file's inspector data may have changed (visibility toggled,
    /// exposure recorded).
    public func invalidate(_ fileID: InspectorFileID) {
        cache.removeValue(forKey: fileID)
        accessOrder.removeAll { $0 == fileID }
    }

    /// Drop the entire cache. Call on grant lifecycle changes (start, end)
    /// since session boundaries change exposure counts, ledger entries,
    /// memory lineage, and tool metrics.
    public func invalidateAll() {
        cache.removeAll(keepingCapacity: true)
        accessOrder.removeAll(keepingCapacity: true)
    }

    /// Diagnostic counters. Used by tests to verify cache behavior.
    public var diagnostics: Diagnostics {
        Diagnostics(
            entryCount: cache.count,
            inFlightCount: inFlight.count,
            accessOrder: accessOrder
        )
    }

    public struct Diagnostics: Sendable {
        public let entryCount: Int
        public let inFlightCount: Int
        public let accessOrder: [InspectorFileID]
    }

    // MARK: - Internal

    private func store(context: InspectorContext, at now: Date) {
        cache[context.fileID] = CacheEntry(value: context, storedAt: now)
        touchAccessOrder(context.fileID)
        evictIfNeeded()
    }

    private func touchAccessOrder(_ fileID: InspectorFileID) {
        accessOrder.removeAll { $0 == fileID }
        accessOrder.append(fileID)
    }

    private func evictIfNeeded() {
        while cache.count > configuration.capacity, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    private struct CacheEntry: Sendable {
        let value: InspectorContext
        let storedAt: Date

        func isExpired(at now: Date, ttl: Duration) -> Bool {
            let elapsed = now.timeIntervalSince(storedAt)
            let ttlSeconds = TimeInterval(ttl.components.seconds) + TimeInterval(ttl.components.attoseconds) / 1e18
            return elapsed > ttlSeconds
        }
    }
}
