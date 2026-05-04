// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("ScopeMirror")
struct ScopeMirrorTests {
    private struct Fixture {
        let policyStore: PolicyStore
        let overrideStore: FileVisibilityOverrideStore
        let tempDir: URL
    }

    private func makeFixture() throws -> Fixture {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-scope-mirror-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        return Fixture(
            policyStore: PolicyStore(db: db),
            overrideStore: FileVisibilityOverrideStore(db: db),
            tempDir: tempDir
        )
    }

    private func cleanup(_ fx: Fixture) {
        try? FileManager.default.removeItem(at: fx.tempDir)
    }

    @Test("Preview between same agent returns empty plan with no diff")
    func previewSameAgent() async throws {
        let fx = try makeFixture()
        defer { cleanup(fx) }

        try await fx.policyStore.addSource("src-1", to: .cowork)

        let plan = try await ScopeMirror.preview(
            from: .cowork,
            to: .cowork,
            policyStore: fx.policyStore,
            overrideStore: fx.overrideStore
        )
        #expect(!plan.hasChanges)
        #expect(plan.sourceIDsToAdd.isEmpty)
        #expect(plan.sourceIDsToRemove.isEmpty)
    }

    @Test("Preview computes source-set diff in both directions")
    func previewSourceDiff() async throws {
        let fx = try makeFixture()
        defer { cleanup(fx) }

        try await fx.policyStore.addSource("shared", to: .cowork)
        try await fx.policyStore.addSource("only-claude", to: .cowork)
        try await fx.policyStore.addSource("shared", to: .codex)
        try await fx.policyStore.addSource("only-codex", to: .codex)

        let plan = try await ScopeMirror.preview(
            from: .cowork,
            to: .codex,
            policyStore: fx.policyStore,
            overrideStore: fx.overrideStore
        )
        #expect(plan.sourceIDsToAdd == ["only-claude"])
        #expect(plan.sourceIDsToRemove == ["only-codex"])
        #expect(plan.hasChanges)
    }

    @Test("Apply makes target's standing source set match the source's")
    func applyMirrorsSources() async throws {
        let fx = try makeFixture()
        defer { cleanup(fx) }

        try await fx.policyStore.addSource("a", to: .cowork)
        try await fx.policyStore.addSource("b", to: .cowork)
        try await fx.policyStore.addSource("z", to: .codex)

        let plan = try await ScopeMirror.preview(
            from: .cowork,
            to: .codex,
            policyStore: fx.policyStore,
            overrideStore: fx.overrideStore
        )
        try await ScopeMirror.apply(plan, policyStore: fx.policyStore, overrideStore: fx.overrideStore)

        let codex = try await fx.policyStore.policy(for: .codex)
        #expect(codex.allowedSourceIDs == ["a", "b"])

        let cowork = try await fx.policyStore.policy(for: .cowork)
        #expect(cowork.allowedSourceIDs == ["a", "b"], "Source agent's policy must not change")
    }

    @Test("Apply mirrors per-file overrides — adds, updates, and clears")
    func applyMirrorsOverrides() async throws {
        let fx = try makeFixture()
        defer { cleanup(fx) }

        try await fx.policyStore.addSource("src-1", to: .cowork)
        try await fx.policyStore.addSource("src-1", to: .codex)

        // Source agent has: deny on Secrets/.env, allow on Specs/API.md
        try await fx.overrideStore.setOverride(
            agent: .cowork, sourceID: "src-1",
            relativePath: "Secrets/.env", isDirectory: false, decision: .deny
        )
        try await fx.overrideStore.setOverride(
            agent: .cowork, sourceID: "src-1",
            relativePath: "Specs/API.md", isDirectory: false, decision: .allow
        )

        // Target has: allow on Secrets/.env (different decision — should flip),
        // deny on Old/legacy.txt (no source counterpart — should clear).
        try await fx.overrideStore.setOverride(
            agent: .codex, sourceID: "src-1",
            relativePath: "Secrets/.env", isDirectory: false, decision: .allow
        )
        try await fx.overrideStore.setOverride(
            agent: .codex, sourceID: "src-1",
            relativePath: "Old/legacy.txt", isDirectory: false, decision: .deny
        )

        let plan = try await ScopeMirror.preview(
            from: .cowork,
            to: .codex,
            policyStore: fx.policyStore,
            overrideStore: fx.overrideStore
        )
        try await ScopeMirror.apply(plan, policyStore: fx.policyStore, overrideStore: fx.overrideStore)

        let codexOverrides = try await fx.overrideStore.overrides(agent: .codex)
        let byPath = Dictionary(uniqueKeysWithValues: codexOverrides.map { ($0.relativePath, $0.decision) })
        #expect(byPath["Secrets/.env"] == .deny, "Mismatched decision should be flipped")
        #expect(byPath["Specs/API.md"] == .allow, "Missing source override should be added")
        #expect(byPath["Old/legacy.txt"] == nil, "Override with no source counterpart should be cleared")
        #expect(codexOverrides.count == 2)

        // Source agent's overrides untouched.
        let coworkOverrides = try await fx.overrideStore.overrides(agent: .cowork)
        #expect(coworkOverrides.count == 2)
    }

    @Test("Removing a source from the target also clears that source's overrides")
    func removingSourceClearsOverrides() async throws {
        let fx = try makeFixture()
        defer { cleanup(fx) }

        // Cowork has nothing; Codex has src-z plus a per-file deny on it.
        try await fx.policyStore.addSource("src-z", to: .codex)
        try await fx.overrideStore.setOverride(
            agent: .codex, sourceID: "src-z",
            relativePath: "private.txt", isDirectory: false, decision: .deny
        )

        let plan = try await ScopeMirror.preview(
            from: .cowork,
            to: .codex,
            policyStore: fx.policyStore,
            overrideStore: fx.overrideStore
        )
        try await ScopeMirror.apply(plan, policyStore: fx.policyStore, overrideStore: fx.overrideStore)

        let codex = try await fx.policyStore.policy(for: .codex)
        #expect(codex.allowedSourceIDs.isEmpty)
        let codexOverrides = try await fx.overrideStore.overrides(agent: .codex)
        #expect(codexOverrides.isEmpty, "Overrides under a removed source must not linger")
    }

    @Test("Apply is idempotent — running twice yields the same plan-empty state")
    func applyIsIdempotent() async throws {
        let fx = try makeFixture()
        defer { cleanup(fx) }

        try await fx.policyStore.addSource("a", to: .cowork)
        try await fx.policyStore.addSource("b", to: .cowork)
        try await fx.overrideStore.setOverride(
            agent: .cowork, sourceID: "a",
            relativePath: "x/y", isDirectory: false, decision: .deny
        )

        let plan1 = try await ScopeMirror.preview(
            from: .cowork, to: .codex,
            policyStore: fx.policyStore, overrideStore: fx.overrideStore
        )
        try await ScopeMirror.apply(plan1, policyStore: fx.policyStore, overrideStore: fx.overrideStore)

        let plan2 = try await ScopeMirror.preview(
            from: .cowork, to: .codex,
            policyStore: fx.policyStore, overrideStore: fx.overrideStore
        )
        #expect(!plan2.hasChanges, "Second mirror should be a no-op")

        try await ScopeMirror.apply(plan2, policyStore: fx.policyStore, overrideStore: fx.overrideStore)
        let codex = try await fx.policyStore.policy(for: .codex)
        #expect(codex.allowedSourceIDs == ["a", "b"])
    }

    @Test("Plan round-trips through Codable (XPC payload contract)")
    func planCodableRoundTrip() async throws {
        let plan = ScopeMirrorPlan(
            sourceAgent: .cowork,
            targetAgent: .codex,
            sourceIDsToAdd: ["a", "b"],
            sourceIDsToRemove: ["c"],
            overridesToWrite: [
                FileVisibilityOverrideRecord(
                    agent: .codex, sourceID: "a",
                    relativePath: "p", isDirectory: false, decision: .deny
                )
            ],
            overridesToClear: []
        )
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(ScopeMirrorPlan.self, from: data)
        #expect(decoded == plan)
    }
}
