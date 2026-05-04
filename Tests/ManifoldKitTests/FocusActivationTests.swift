// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// Storage-layer simulation of the Focus activation pipeline. The
// runtime/XPC orchestration (`setActiveFocus` end+swap+start) lives
// upstairs; here we verify the data-plane invariants the orchestration
// relies on:
//   - Activating a Focus copies its scope into the agent's policy and
//     clears+repopulates the agent's overrides.
//   - Switching Focus A → B fully replaces A's state with B's.
//   - Default-Focus seeding from existing per-agent state works and is
//     idempotent.

import Foundation
import Testing
@testable import ManifoldKit

@Suite("FocusActivation")
struct FocusActivationTests {
    private struct Fixture {
        let access: AccessStore
        let policy: PolicyStore
        let overrides: FileVisibilityOverrideStore
        let db: DatabaseConnection
        let tempDir: URL
    }

    private func makeFixture() throws -> Fixture {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-focus-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        return Fixture(
            access: AccessStore(db: db),
            policy: PolicyStore(db: db),
            overrides: FileVisibilityOverrideStore(db: db),
            db: db,
            tempDir: tempDir
        )
    }

    private func cleanup(_ fx: Fixture) {
        try? FileManager.default.removeItem(at: fx.tempDir)
    }

    /// Seed `sources` rows so preset file_scopes referencing them satisfy
    /// the FK constraint. Mirrors how AccessStoreTests does it.
    private func seedSources(_ ids: [String], in fx: Fixture) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        for id in ids {
            try fx.db.execute(
                """
                INSERT OR IGNORE INTO sources (source_id, display_name, original_root_path, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                params: [id, id, "/tmp/\(id)", "idle", now, now]
            )
        }
    }

    /// Replicates the runtime's `setActiveFocus` data-plane swap so we can
    /// exercise the AccessStore + PolicyStore + FileVisibilityOverrideStore
    /// triangle without dragging the XPC layer into ManifoldKit tests.
    private func simulateActivate(
        focus presetID: String,
        for agent: TargetApp,
        in fx: Fixture
    ) async throws {
        guard let snapshot = try await fx.access.loadPreset(id: presetID) else { return }

        var p = try await fx.policy.policy(for: agent)
        p.allowedSourceIDs = Set(snapshot.fileScopes.map(\.sourceID))
        try await fx.policy.updatePolicy(p)

        try await fx.overrides.clearAllOverrides(agent: agent)
        if !snapshot.overrides.isEmpty {
            let stamped = snapshot.overrides.map {
                FileVisibilityOverrideRecord(
                    agent: agent, sourceID: $0.sourceID,
                    relativePath: $0.relativePath, isDirectory: $0.isDirectory,
                    decision: $0.decision
                )
            }
            try await fx.overrides.setManyOverrides(stamped)
        }
    }

    @Test("Activating a Focus copies its scope into agent policy")
    func activationCopiesScope() async throws {
        let fx = try makeFixture()
        defer { cleanup(fx) }
        try seedSources(["old-1", "old-2", "q4-a", "q4-b"], in: fx)

        // Existing agent state has different sources than the Focus.
        try await fx.policy.addSource("old-1", to: .cowork)
        try await fx.policy.addSource("old-2", to: .cowork)

        let focus = try await fx.access.savePreset(
            id: nil, name: "Q4", targetApp: .cowork,
            fileScopes: [
                FileSelectionScope(sourceID: "q4-a", relativePath: "", isDirectory: true),
                FileSelectionScope(sourceID: "q4-b", relativePath: "", isDirectory: true),
            ],
            emailIDs: []
        )
        try await simulateActivate(focus: focus.presetID, for: .cowork, in: fx)

        let policy = try await fx.policy.policy(for: .cowork)
        #expect(policy.allowedSourceIDs == ["q4-a", "q4-b"])
    }

    @Test("Activating a Focus clears prior overrides and applies the Focus's saved set")
    func activationSwapsOverrides() async throws {
        let fx = try makeFixture()
        defer { cleanup(fx) }
        try seedSources(["q4-a"], in: fx)

        // Pre-existing agent overrides we expect activation to wipe.
        try await fx.overrides.setOverride(
            agent: .cowork, sourceID: "old", relativePath: "x",
            isDirectory: false, decision: .deny
        )

        let focus = try await fx.access.savePreset(
            id: nil, name: "Q4", targetApp: .cowork,
            fileScopes: [], emailIDs: [],
            overrides: [
                FileVisibilityOverrideRecord(agent: .cowork, sourceID: "q4-a",
                    relativePath: "Secrets/.env", isDirectory: false, decision: .deny)
            ]
        )

        try await simulateActivate(focus: focus.presetID, for: .cowork, in: fx)

        let resolved = try await fx.overrides.overrides(agent: .cowork)
        #expect(resolved.count == 1)
        #expect(resolved.first?.sourceID == "q4-a")
        #expect(resolved.first?.relativePath == "Secrets/.env")
    }

    @Test("Switching Focus A → B fully replaces state")
    func switchingFocusReplacesState() async throws {
        let fx = try makeFixture()
        defer { cleanup(fx) }
        try seedSources(["a-only", "b-only"], in: fx)

        let a = try await fx.access.savePreset(
            id: nil, name: "A", targetApp: .cowork,
            fileScopes: [FileSelectionScope(sourceID: "a-only", relativePath: "", isDirectory: true)],
            emailIDs: [],
            overrides: [
                FileVisibilityOverrideRecord(agent: .cowork, sourceID: "a-only",
                    relativePath: "skip.txt", isDirectory: false, decision: .deny)
            ]
        )
        let b = try await fx.access.savePreset(
            id: nil, name: "B", targetApp: .cowork,
            fileScopes: [FileSelectionScope(sourceID: "b-only", relativePath: "", isDirectory: true)],
            emailIDs: [],
            overrides: [
                FileVisibilityOverrideRecord(agent: .cowork, sourceID: "b-only",
                    relativePath: "include.md", isDirectory: false, decision: .allow)
            ]
        )

        try await simulateActivate(focus: a.presetID, for: .cowork, in: fx)
        try await simulateActivate(focus: b.presetID, for: .cowork, in: fx)

        let policy = try await fx.policy.policy(for: .cowork)
        #expect(policy.allowedSourceIDs == ["b-only"])
        let resolved = try await fx.overrides.overrides(agent: .cowork)
        #expect(resolved.count == 1)
        #expect(resolved.first?.sourceID == "b-only")
        #expect(resolved.first?.decision == .allow)
    }

    @Test("Activating an already-active Focus is a no-op (idempotent)")
    func activationIsIdempotent() async throws {
        let fx = try makeFixture()
        defer { cleanup(fx) }
        try seedSources(["src"], in: fx)

        let focus = try await fx.access.savePreset(
            id: nil, name: "Idem", targetApp: .cowork,
            fileScopes: [FileSelectionScope(sourceID: "src", relativePath: "", isDirectory: true)],
            emailIDs: [],
            overrides: [
                FileVisibilityOverrideRecord(agent: .cowork, sourceID: "src",
                    relativePath: "x.md", isDirectory: false, decision: .allow)
            ]
        )
        try await simulateActivate(focus: focus.presetID, for: .cowork, in: fx)
        try await simulateActivate(focus: focus.presetID, for: .cowork, in: fx)

        let policy = try await fx.policy.policy(for: .cowork)
        #expect(policy.allowedSourceIDs == ["src"])
        let resolved = try await fx.overrides.overrides(agent: .cowork)
        #expect(resolved.count == 1)
    }

    @Test("Default-Focus seeding is idempotent (running twice yields one preset)")
    func defaultFocusSeedingIsIdempotent() async throws {
        let fx = try makeFixture()
        defer { cleanup(fx) }
        try seedSources(["seeded-1", "seeded-2"], in: fx)

        try await fx.policy.addSource("seeded-1", to: .cowork)
        try await fx.policy.addSource("seeded-2", to: .cowork)

        // Manual seeding (mirrors ManifoldRuntime.seedDefaultFocusIfNeeded
        // path so we can verify idempotency without spinning up the full
        // runtime here).
        func seed() async throws {
            if try await fx.access.defaultPresetForLaunch(agent: .cowork) != nil { return }
            let policy = try await fx.policy.policy(for: .cowork)
            let scopes = policy.allowedSourceIDs.sorted().map {
                FileSelectionScope(sourceID: $0, relativePath: "", isDirectory: true)
            }
            let preset = try await fx.access.savePreset(
                id: nil, name: "Default", targetApp: .cowork,
                fileScopes: scopes, emailIDs: []
            )
            try await fx.access.setDefaultAtLaunch(presetID: preset.presetID, for: .cowork)
        }

        try await seed()
        try await seed()
        try await seed()

        let presets = try await fx.access.allPresets()
        let defaults = presets.filter { $0.isDefaultAtLaunch && $0.targetApp == .cowork }
        #expect(defaults.count == 1)
        #expect(defaults.first?.name == "Default")
    }
}
