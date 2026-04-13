// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
@testable import ManifoldKit

@Suite("PolicyStore")
struct PolicyStoreTests {
    func makeStore() throws -> (PolicyStore, DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-policy-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        let store = PolicyStore(db: db)
        return (store, db, tempDir)
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    @Test("Default policy created for new agent")
    func defaultPolicy() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let policy = try await store.policy(for: .cowork)
        #expect(policy.agent == .cowork)
        #expect(policy.allowedSourceIDs.isEmpty)
        #expect(policy.allowedEmailDomains.isEmpty)
        #expect(policy.emailSensitivity == .moderate)
        #expect(policy.isPaused == false)
        #expect(policy.hasCompletedFirstGrant == false)
    }

    @Test("Same agent returns same policy on second call")
    func idempotent() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let first = try await store.policy(for: .cowork)
        let second = try await store.policy(for: .cowork)
        #expect(first.id == second.id)
    }

    @Test("Different agents get different policies")
    func separateAgents() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let claude = try await store.policy(for: .cowork)
        let codex = try await store.policy(for: .codex)
        #expect(claude.id != codex.id)
        #expect(claude.agent == .cowork)
        #expect(codex.agent == .codex)
    }

    @Test("Add and remove source")
    func sourceManagement() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.addSource("src-1", to: .cowork)
        var policy = try await store.policy(for: .cowork)
        #expect(policy.allowedSourceIDs.contains("src-1"))
        #expect(policy.hasCompletedFirstGrant)

        try await store.removeSource("src-1", from: .cowork)
        policy = try await store.policy(for: .cowork)
        #expect(policy.allowedSourceIDs.contains("src-1") == false)
    }

    @Test("Add and remove email domain")
    func domainManagement() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.addEmailDomain("company.com", to: .cowork)
        var policy = try await store.policy(for: .cowork)
        #expect(policy.allowedEmailDomains.contains("company.com"))

        try await store.removeEmailDomain("company.com", from: .cowork)
        policy = try await store.policy(for: .cowork)
        #expect(policy.allowedEmailDomains.contains("company.com") == false)
    }

    @Test("Domain names are lowercased")
    func domainLowercase() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.addEmailDomain("Company.COM", to: .cowork)
        let policy = try await store.policy(for: .cowork)
        #expect(policy.allowedEmailDomains.contains("company.com"))
    }

    @Test("Update sensitivity")
    func sensitivity() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.updateSensitivity(.strict, for: .cowork)
        let policy = try await store.policy(for: .cowork)
        #expect(policy.emailSensitivity == .strict)
    }

    @Test("Pause and resume agent")
    func pauseResume() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.addSource("src-1", to: .cowork)
        try await store.pauseAgent(.cowork)

        var accessible = try await store.isSourceAccessible("src-1", by: .cowork)
        #expect(accessible == false, "Paused agent should not have access")

        try await store.resumeAgent(.cowork)
        accessible = try await store.isSourceAccessible("src-1", by: .cowork)
        #expect(accessible, "Resumed agent should have access")
    }

    @Test("Source accessibility checks policy and pause state")
    func sourceAccessibility() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        // Not in allowed list
        var accessible = try await store.isSourceAccessible("src-1", by: .cowork)
        #expect(accessible == false)

        // Add to allowed list
        try await store.addSource("src-1", to: .cowork)
        accessible = try await store.isSourceAccessible("src-1", by: .cowork)
        #expect(accessible)

        // Different source not accessible
        accessible = try await store.isSourceAccessible("src-2", by: .cowork)
        #expect(accessible == false)
    }

    @Test("Domain accessibility checks policy and pause state")
    func domainAccessibility() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.addEmailDomain("work.com", to: .cowork)

        var accessible = try await store.isDomainAccessible("work.com", by: .cowork)
        #expect(accessible)

        try await store.pauseAgent(.cowork)
        accessible = try await store.isDomainAccessible("work.com", by: .cowork)
        #expect(accessible == false)
    }

    @Test("All policies returns both agents")
    func allPolicies() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        _ = try await store.policy(for: .cowork)
        _ = try await store.policy(for: .codex)

        let all = try await store.allPolicies()
        #expect(all.count == 2)
    }

    @Test("Temporary reveal created and queried")
    func temporaryReveal() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let reveal = try await store.createTemporaryReveal(
            agent: .cowork, emailID: "msg-123", workBlockID: "wb-1"
        )
        #expect(reveal.agent == .cowork)
        #expect(reveal.emailID == "msg-123")

        let reveals = try await store.temporaryReveals(for: .cowork)
        #expect(reveals.count == 1)
        #expect(reveals[0].id == reveal.id)
    }

    @Test("Clear reveals by work block")
    func clearRevealsByWorkBlock() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        _ = try await store.createTemporaryReveal(agent: .cowork, emailID: "msg-1", workBlockID: "wb-1")
        _ = try await store.createTemporaryReveal(agent: .cowork, emailID: "msg-2", workBlockID: "wb-1")
        _ = try await store.createTemporaryReveal(agent: .cowork, emailID: "msg-3", workBlockID: "wb-2")

        try await store.clearReveals(forWorkBlock: "wb-1")
        let remaining = try await store.temporaryReveals(for: .cowork)
        #expect(remaining.count == 1)
        #expect(remaining[0].emailID == "msg-3")
    }
}
