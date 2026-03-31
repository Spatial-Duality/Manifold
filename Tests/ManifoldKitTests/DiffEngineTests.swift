import Testing
import Foundation
@testable import ManifoldKit

@Suite("DiffEngine")
struct DiffEngineTests {
    @Test("Diff detects additions")
    func additions() {
        let engine = DiffEngine()
        let lines = engine.diff(before: "line1\nline2\n", after: "line1\nline2\nline3\n")
        let additions = lines.filter { $0.type == .addition }
        #expect(!additions.isEmpty)
        #expect(additions.contains { $0.text == "line3" })
    }

    @Test("Diff detects removals")
    func removals() {
        let engine = DiffEngine()
        let lines = engine.diff(before: "line1\nline2\nline3\n", after: "line1\nline3\n")
        let removals = lines.filter { $0.type == .removal }
        #expect(!removals.isEmpty)
        #expect(removals.contains { $0.text == "line2" })
    }

    @Test("Diff of identical content returns empty")
    func identical() {
        let engine = DiffEngine()
        let lines = engine.diff(before: "same\n", after: "same\n")
        #expect(lines.isEmpty)
    }

    @Test("Diff from Data blobs")
    func dataBlobs() {
        let engine = DiffEngine()
        let before = "hello\n".data(using: .utf8)!
        let after = "hello\nworld\n".data(using: .utf8)!
        let lines = engine.diff(beforeData: before, afterData: after)
        #expect(lines != nil)
        #expect(lines!.contains { $0.type == .addition && $0.text == "world" })
    }

    @Test("Large files return nil")
    func largeFiles() {
        let engine = DiffEngine()
        let large = Data(repeating: 65, count: 2_000_000) // 2MB
        let small = "hello".data(using: .utf8)!
        let result = engine.diff(beforeData: large, afterData: small)
        #expect(result == nil)
    }
}
