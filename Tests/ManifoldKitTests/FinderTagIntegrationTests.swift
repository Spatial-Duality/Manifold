// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("Finder tag integration")
struct FinderTagIntegrationTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-finder-tags-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeLedgerStore() throws -> (FinderTagLedgerStore, URL) {
        let root = try makeTempDirectory()
        let db = try DatabaseConnection(url: root.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        return (try FinderTagLedgerStore(db: db), root)
    }

    @Test("Finder tags preserve unrelated tags and remove only the configured tag")
    func finderTagAddRemovePreservesUnrelatedTags() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("notes.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        var mutableFile = file
        var initial = URLResourceValues()
        initial.tagNames = ["Personal"]
        try mutableFile.setResourceValues(initial)

        let records = FinderTagService.tagItems(
            at: file,
            sourceID: "src-one",
            tagName: "Manifold",
            recursive: false
        )
        #expect(records.count == 1)

        let tagged = try mutableFile.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
        #expect(tagged.contains("Personal"))
        #expect(tagged.contains("Manifold"))

        FinderTagService.removeTag("Manifold", from: file)

        mutableFile.removeCachedResourceValue(forKey: .tagNamesKey)
        var remaining = try mutableFile.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
        for _ in 0..<10 where remaining.contains("Manifold") {
            try await Task.sleep(for: .milliseconds(50))
            mutableFile.removeCachedResourceValue(forKey: .tagNamesKey)
            remaining = try mutableFile.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
        }
        #expect(remaining.contains("Personal"))
        #expect(!remaining.contains("Manifold"))
    }

    @Test("Finder tag ledger skips untagging when another source owns the same item")
    func ledgerDetectsOtherOwnerByIdentity() async throws {
        let (store, root) = try makeLedgerStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let identity = "1:2:3:4"
        try await store.record([
            FinderTaggedItemRecord(
                sourceID: "src-one",
                originalPath: "/tmp/shared.txt",
                fileIdentity: identity,
                isDirectory: false,
                tagName: "Manifold"
            ),
            FinderTaggedItemRecord(
                sourceID: "src-two",
                originalPath: "/tmp/other-name.txt",
                fileIdentity: identity,
                isDirectory: false,
                tagName: "Manifold"
            ),
        ])

        let hasOther = try await store.hasOtherOwner(
            fileIdentity: identity,
            path: "/tmp/shared.txt",
            tagName: "Manifold",
            excluding: "src-one"
        )
        #expect(hasOther)

        try await store.removeRecords(sourceID: "src-two")
        let noOther = try await store.hasOtherOwner(
            fileIdentity: identity,
            path: "/tmp/shared.txt",
            tagName: "Manifold",
            excluding: "src-one"
        )
        #expect(!noOther)
    }

    @Test("Finder tag ledger recognizes folder roots tagged for watcher inheritance")
    func ledgerRecognizesTaggedSourceRoot() async throws {
        let (store, root) = try makeLedgerStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceRoot = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        try await store.record([
            FinderTaggedItemRecord(
                sourceID: "src-folder",
                originalPath: sourceRoot.standardizedFileURL.path,
                fileIdentity: "folder-identity",
                isDirectory: true,
                tagName: "Manifold"
            ),
            FinderTaggedItemRecord(
                sourceID: "src-file",
                originalPath: sourceRoot.appendingPathComponent("README.md").path,
                fileIdentity: "file-identity",
                isDirectory: false,
                tagName: "Manifold"
            ),
        ])

        #expect(try await store.sourceHasTaggedRoot(sourceID: "src-folder", rootPath: sourceRoot.path))
        #expect(!((try? await store.sourceHasTaggedRoot(sourceID: "src-file", rootPath: sourceRoot.path)) ?? true))
    }

    @Test("Finder tag recovery matcher prefers identity matches and marks source roots")
    func recoveryMatcherFindsMovedTaggedRoot() {
        let records = [
            FinderTaggedItemRecord(
                sourceID: "src-one",
                originalPath: "/Users/me/Documents/Project",
                fileIdentity: "dev:ino:birth:nsec",
                isDirectory: true,
                tagName: "Manifold"
            ),
            FinderTaggedItemRecord(
                sourceID: "src-one",
                originalPath: "/Users/me/Documents/Project/Notes.md",
                fileIdentity: "dev:file:birth:nsec",
                isDirectory: false,
                tagName: "Manifold"
            ),
        ]
        let candidates = [
            FinderTagRecoveryCandidate(
                path: "/Users/me/Desktop/Renamed Project",
                fileIdentity: "dev:ino:birth:nsec",
                isDirectory: true,
                tagName: "Manifold"
            ),
            FinderTagRecoveryCandidate(
                path: "/Users/me/Desktop/Renamed Project/Notes.md",
                fileIdentity: "dev:file:birth:nsec",
                isDirectory: false,
                tagName: "Manifold"
            ),
        ]

        let suggestions = FinderTagRecoveryMatcher.suggestions(
            records: records,
            candidates: candidates,
            originalSourcePath: "/Users/me/Documents/Project"
        )

        #expect(suggestions.count == 2)
        let root = suggestions[0]
        #expect(root.isSourceRoot)
        #expect(root.suggestedPath == "/Users/me/Desktop/Renamed Project")
        #expect(root.matchKind == .fileIdentity)
    }
}
