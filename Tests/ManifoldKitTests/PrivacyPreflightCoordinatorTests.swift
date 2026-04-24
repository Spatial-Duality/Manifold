// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import Testing
@testable import ManifoldKit
@testable import ManifoldRuntime

@Suite("Privacy Preflight Coordinator")
struct PrivacyPreflightCoordinatorTests {
    func makeCoordinator() throws -> (PrivacyStore, PrivacyPreflightCoordinator, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-privacy-coordinator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        try DatabaseMigrator(db: db).migrate()
        let store = PrivacyStore(db: db)
        let coordinator = PrivacyPreflightCoordinator(
            store: store,
            defaultStorageURL: tempDir.appendingPathComponent("privacy-models", isDirectory: true)
        )
        return (store, coordinator, tempDir)
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @Test("Document-like content is redacted by default")
    func redactsDocumentContent() async throws {
        let (_, coordinator, tempDir) = try makeCoordinator()
        defer { cleanup(tempDir) }

        _ = try await coordinator.installModel()

        let delivery = try await coordinator.preflight(
            agent: .cowork,
            toolName: "read_email",
            resourcePath: "_emails/inbox/123.eml",
            text: "Contact jane@example.com or call +1 (415) 555-0123.",
            contentKind: .email,
            accessDecisionID: "decision-1"
        )

        #expect(delivery.outcome == .filtered)
        #expect(delivery.deliveredText?.contains("[EMAIL REDACTED]") == true)
        #expect(delivery.deliveredText?.contains("[PHONE REDACTED]") == true)
        #expect(delivery.deliveredText?.contains("jane@example.com") == false)
        #expect(Set(delivery.matchedCategories).isSuperset(of: [.email, .phone]))
        #expect(delivery.backend == .rulesOnly)
    }

    @Test("Code-like content asks before sharing original")
    func codeContentRequiresApproval() async throws {
        let (_, coordinator, tempDir) = try makeCoordinator()
        defer { cleanup(tempDir) }

        _ = try await coordinator.installModel()

        let delivery = try await coordinator.preflight(
            agent: .codex,
            toolName: "read_file",
            resourcePath: "Sources/Users.swift",
            text: #"let ownerEmail = "jane@example.com""#,
            contentKind: .sourceCode,
            accessDecisionID: "decision-2"
        )

        #expect(delivery.outcome == .approvalRequired)
        #expect(delivery.deliveredText == nil)
        #expect(delivery.approvalContext?.contentKind == .sourceCode)
        #expect(delivery.approvalContext?.matchedCategories == [.email])
        #expect(delivery.approvalContext?.redactedPreview?.contains("[EMAIL REDACTED]") == true)
    }

    @Test("Secrets are blocked by default")
    func blocksSecrets() async throws {
        let (_, coordinator, tempDir) = try makeCoordinator()
        defer { cleanup(tempDir) }

        _ = try await coordinator.installModel()

        let delivery = try await coordinator.preflight(
            agent: .cowork,
            toolName: "extract_file",
            resourcePath: "docs/credentials.txt",
            text: "OPENAI_API_KEY=sk-1234567890abcdefghijklmnop",
            contentKind: .document,
            accessDecisionID: "decision-3"
        )

        #expect(delivery.outcome == .blocked)
        #expect(delivery.deliveredText == nil)
        #expect(delivery.matchedCategories == [.secret])
    }

    @Test("One-time original approval is consumed after use")
    func originalApprovalOverrideIsSingleUse() async throws {
        let (store, coordinator, tempDir) = try makeCoordinator()
        defer { cleanup(tempDir) }

        _ = try await coordinator.installModel()
        let text = #"let ownerEmail = "jane@example.com""#
        let inputHash = sha256(text)

        try await store.saveApprovalOverride(
            agent: .codex,
            resourceKey: "Sources/Users.swift",
            inputHash: inputHash,
            contentKind: .sourceCode,
            decision: .shareOriginalOnce
        )

        let first = try await coordinator.preflight(
            agent: .codex,
            toolName: "read_file",
            resourcePath: "Sources/Users.swift",
            text: text,
            contentKind: .sourceCode,
            accessDecisionID: "decision-4"
        )
        let second = try await coordinator.preflight(
            agent: .codex,
            toolName: "read_file",
            resourcePath: "Sources/Users.swift",
            text: text,
            contentKind: .sourceCode,
            accessDecisionID: "decision-5"
        )

        #expect(first.outcome == .warning)
        #expect(first.deliveredText == text)
        #expect(second.outcome == .approvalRequired)
        #expect(second.deliveredText == nil)
    }

    @Test("Unavailable installed backend falls back to rules-only scanning")
    func unavailableBackendFallsBackToRulesOnly() async throws {
        let (_, coordinator, tempDir) = try makeCoordinator()
        defer { cleanup(tempDir) }

        try await coordinator.updateSettings(
            PrivacyPreflightSettings(
                isEnabled: true,
                selectedBackend: .mlx,
                installState: .installed,
                storagePath: tempDir.appendingPathComponent("privacy-models").path
            )
        )

        let status = try await coordinator.runtimeStatus()
        let delivery = try await coordinator.preflight(
            agent: .cowork,
            toolName: "search_emails",
            resourcePath: "_emails/inbox/123.eml",
            text: "Email jane@example.com",
            contentKind: .snippet,
            accessDecisionID: "decision-6"
        )

        #expect(status.selectedBackend == .mlx)
        #expect(status.effectiveBackend == .rulesOnly)
        #expect(delivery.backend == .rulesOnly)
        #expect(delivery.outcome == .filtered)
    }
}
