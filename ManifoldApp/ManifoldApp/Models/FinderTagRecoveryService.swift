// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import os

private let finderTagRecoveryLogger = Logger(subsystem: "com.spatialduality.manifold", category: "finder-tag-recovery")

enum FinderTagRecoveryService {
    @MainActor
    static func suggestions(
        for source: SourceRecord,
        records: [FinderTaggedItemRecord],
        timeout: Duration = .seconds(3)
    ) async -> [FinderTagRecoverySuggestion] {
        let tagNames = Set(records.map(\.tagName).filter { !$0.isEmpty })
        guard !tagNames.isEmpty else { return [] }

        var candidates: [FinderTagRecoveryCandidate] = []
        for tagName in tagNames.sorted() {
            candidates.append(
                contentsOf: await FinderTagMetadataQueryRunner(tagName: tagName).run(timeout: timeout)
            )
        }

        return FinderTagRecoveryMatcher.suggestions(
            records: records,
            candidates: candidates,
            originalSourcePath: source.effectiveRootPath
        )
    }
}

@MainActor
private final class FinderTagMetadataQueryRunner {
    private let tagName: String
    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private var continuation: CheckedContinuation<[FinderTagRecoveryCandidate], Never>?

    init(tagName: String) {
        self.tagName = tagName
    }

    func run(timeout: Duration) async -> [FinderTagRecoveryCandidate] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            start()

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish()
            }
        }
    }

    private func start() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "ANY kMDItemUserTags == %@", tagName)
        query.notificationBatchingInterval = 0.2
        self.query = query
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.finish()
            }
        }

        guard query.start() else {
            finderTagRecoveryLogger.warning("Finder tag metadata query did not start for tag \(self.tagName, privacy: .public)")
            finish()
            return
        }
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil

        if let query {
            query.disableUpdates()
            query.stop()
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }

        continuation.resume(returning: collectCandidates())
        query = nil
    }

    private func collectCandidates() -> [FinderTagRecoveryCandidate] {
        guard let query else { return [] }
        var candidates: [FinderTagRecoveryCandidate] = []
        candidates.reserveCapacity(query.resultCount)

        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem else { continue }
            guard let path = item.value(forAttribute: "kMDItemPath") as? String else { continue }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let isDirectory = FinderTagService.isDirectory(url)
            candidates.append(
                FinderTagRecoveryCandidate(
                    path: url.path,
                    fileIdentity: try? SourceResolver.fileIdentity(at: url),
                    isDirectory: isDirectory,
                    tagName: tagName
                )
            )
        }

        return candidates
    }
}

extension ManifoldStore {
    @MainActor
    func finderTagRecoverySuggestions(for source: SourceRecord) async -> [FinderTagRecoverySuggestion] {
        guard let client = focusClient else { return [] }
        do {
            let records = try await client.finderTagRecords(sourceID: source.sourceID)
            return await FinderTagRecoveryService.suggestions(for: source, records: records)
        } catch {
            finderTagRecoveryLogger.warning("Finder tag recovery failed: \(error.localizedDescription, privacy: .public)")
            lastError = "Couldn't search Finder tags: \(error.localizedDescription)"
            return []
        }
    }
}
