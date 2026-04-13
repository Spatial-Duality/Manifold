// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
@testable import ManifoldKit

@Suite("GlobMatcher")
struct GlobMatcherTests {

    @Test("Basic wildcard matches files at any depth")
    func basicWildcard() {
        let matcher = GlobMatcher(content: "*.log")
        #expect(matcher.shouldExclude(relativePath: "debug.log"))
        #expect(matcher.shouldExclude(relativePath: "src/debug.log"))
        #expect(!matcher.shouldExclude(relativePath: "debug.log.bak"))
        #expect(!matcher.shouldExclude(relativePath: "readme.md"))
    }

    @Test("Double star matches nested paths")
    func doubleStar() {
        let matcher = GlobMatcher(content: "**/build/")
        #expect(matcher.shouldExclude(relativePath: "build", isDirectory: true))
        #expect(matcher.shouldExclude(relativePath: "project/build", isDirectory: true))
        #expect(matcher.shouldExclude(relativePath: "a/b/build", isDirectory: true))
        // Directory-only pattern should not match files
        #expect(!matcher.shouldExclude(relativePath: "build", isDirectory: false))
    }

    @Test("Negation re-includes previously excluded files")
    func negation() {
        let matcher = GlobMatcher(content: """
        *.log
        !important.log
        """)
        #expect(matcher.shouldExclude(relativePath: "debug.log"))
        #expect(!matcher.shouldExclude(relativePath: "important.log"))
        #expect(matcher.shouldExclude(relativePath: "error.log"))
    }

    @Test("Directory-only pattern matches directories not files")
    func directoryOnly() {
        let matcher = GlobMatcher(content: "build/")
        #expect(matcher.shouldExclude(relativePath: "build", isDirectory: true))
        #expect(!matcher.shouldExclude(relativePath: "build", isDirectory: false))
        #expect(matcher.shouldExclude(relativePath: "src/build", isDirectory: true))
    }

    @Test("Anchored pattern matches only at root")
    func anchored() {
        let matcher = GlobMatcher(content: "/vendor")
        #expect(matcher.shouldExclude(relativePath: "vendor"))
        #expect(!matcher.shouldExclude(relativePath: "lib/vendor"))
    }

    @Test("Comments and blank lines are ignored")
    func commentsAndBlanks() {
        let matcher = GlobMatcher(content: """
        # This is a comment

        *.log

        # Another comment
        """)
        #expect(matcher.patterns.count == 1)
        #expect(matcher.shouldExclude(relativePath: "debug.log"))
    }

    @Test("Missing file returns empty matcher")
    func missingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/path/.manifoldignore")
        let matcher = GlobMatcher.load(from: url)
        #expect(matcher.patterns.isEmpty)
        #expect(!matcher.shouldExclude(relativePath: "anything.txt"))
    }

    @Test("Empty content excludes nothing")
    func emptyContent() {
        let matcher = GlobMatcher(content: "")
        #expect(matcher.patterns.isEmpty)
        #expect(!matcher.shouldExclude(relativePath: "file.txt"))
    }

    @Test("Question mark matches single character")
    func questionMark() {
        let matcher = GlobMatcher(content: "file?.txt")
        #expect(matcher.shouldExclude(relativePath: "file1.txt"))
        #expect(matcher.shouldExclude(relativePath: "fileA.txt"))
        #expect(!matcher.shouldExclude(relativePath: "file12.txt"))
        #expect(!matcher.shouldExclude(relativePath: "file.txt"))
    }

    @Test("Multiple patterns with last-match-wins semantics")
    func lastMatchWins() {
        let matcher = GlobMatcher(content: """
        *.txt
        !important.txt
        temp*.txt
        """)
        // *.txt excludes, !important.txt re-includes
        #expect(!matcher.shouldExclude(relativePath: "important.txt"))
        // temp*.txt re-excludes even though it was re-included by *.txt
        #expect(matcher.shouldExclude(relativePath: "tempfile.txt"))
        // Regular .txt still excluded
        #expect(matcher.shouldExclude(relativePath: "notes.txt"))
    }

    @Test("Integration: load from file on disk")
    func loadFromDisk() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("manifold-glob-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let ignoreFile = tmpDir.appendingPathComponent(".manifoldignore")
        try "*.log\nbuild/\n".write(to: ignoreFile, atomically: true, encoding: .utf8)

        let matcher = GlobMatcher.load(from: ignoreFile)
        #expect(matcher.patterns.count == 2)
        #expect(matcher.shouldExclude(relativePath: "debug.log"))
        #expect(matcher.shouldExclude(relativePath: "build", isDirectory: true))
        #expect(!matcher.shouldExclude(relativePath: "src/main.swift"))
    }
}
