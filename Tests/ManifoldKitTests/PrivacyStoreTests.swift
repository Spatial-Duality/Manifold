// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("Privacy Store")
struct PrivacyStoreTests {
    func makeStore() throws -> (PrivacyStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-privacy-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        try DatabaseMigrator(db: db).migrate()
        return (PrivacyStore(db: db), tempDir)
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Default settings and policies are created on first access")
    func defaultsAreMaterialized() async throws {
        let (store, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let settings = try await store.settings(defaultStoragePath: tempDir.appendingPathComponent("models").path)
        let cowork = try await store.policy(for: .cowork)
        let codex = try await store.policy(for: .codex)

        #expect(settings.id == "privacy-preflight")
        #expect(settings.selectedBackend == .rulesOnly)
        #expect(settings.isEnabled == false)
        #expect(cowork.textHandling == .redact)
        #expect(cowork.codeHandling == .ask)
        #expect(cowork.secretHandling == .block)
        #expect(codex.agent == .codex)
    }

    @Test("Cache key respects categories and content kind")
    func cacheKeyIncludesCategoriesAndContentKind() async throws {
        let (store, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let result = PrivacyScanResult(
            spans: [
                DetectedSpan(
                    startUTF16: 0,
                    endUTF16: 16,
                    category: .email,
                    confidence: 0.95,
                    textPreview: "jane@example.com",
                    replacement: PrivacyCategory.email.replacementToken
                )
            ],
            redactedText: "[EMAIL REDACTED]",
            findingsSummary: "1 emails",
            backend: .rulesOnly,
            modelVersion: "rules-only-v1",
            elapsedMs: 4,
            cacheHit: false
        )

        try await store.cache(
            result,
            inputHash: "hash-1",
            operatingPoint: "text:redact|code:ask|secret:block",
            categories: [.secret, .email],
            contentKind: .email
        )

        let reorderedHit = try await store.cachedResult(
            inputHash: "hash-1",
            backend: .rulesOnly,
            modelVersion: "rules-only-v1",
            operatingPoint: "text:redact|code:ask|secret:block",
            categories: [.email, .secret],
            contentKind: .email
        )
        let differentKindMiss = try await store.cachedResult(
            inputHash: "hash-1",
            backend: .rulesOnly,
            modelVersion: "rules-only-v1",
            operatingPoint: "text:redact|code:ask|secret:block",
            categories: [.email, .secret],
            contentKind: .document
        )
        let differentCategoryMiss = try await store.cachedResult(
            inputHash: "hash-1",
            backend: .rulesOnly,
            modelVersion: "rules-only-v1",
            operatingPoint: "text:redact|code:ask|secret:block",
            categories: [.email],
            contentKind: .email
        )

        #expect(reorderedHit?.cacheHit == true)
        #expect(reorderedHit?.redactedText == "[EMAIL REDACTED]")
        #expect(differentKindMiss == nil)
        #expect(differentCategoryMiss == nil)
    }

    @Test("Approval overrides are consumed once")
    func approvalOverridesAreSingleUse() async throws {
        let (store, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.saveApprovalOverride(
            agent: .codex,
            resourceKey: "src/Secrets.swift",
            inputHash: "input-hash",
            contentKind: .sourceCode,
            decision: .shareRedacted
        )

        let first = try await store.approvalOverride(
            agent: .codex,
            resourceKey: "src/Secrets.swift",
            inputHash: "input-hash",
            contentKind: .sourceCode
        )
        let second = try await store.approvalOverride(
            agent: .codex,
            resourceKey: "src/Secrets.swift",
            inputHash: "input-hash",
            contentKind: .sourceCode
        )

        #expect(first == .shareRedacted)
        #expect(second == nil)
    }

    @Test("Identity, suggestion, and allowlist records round-trip with decrypted values")
    func identityAndAllowlistRoundTrip() async throws {
        let (store, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let identity = PrivacyIdentityRecord(
            id: "identity-me-email",
            kind: .email,
            displayName: "Me",
            value: "me@example.com"
        )
        let disabledIdentity = PrivacyIdentityRecord(
            id: "identity-old-phone",
            kind: .phone,
            displayName: "Old Phone",
            value: "+1 (415) 555-0111",
            isEnabled: false
        )
        let suggestion = PrivacyIdentitySuggestion(
            id: "suggestion-me-name",
            kind: .personName,
            displayName: "Jane Example",
            value: "Jane Example",
            sourceKind: .emailAccount,
            sourceRef: "account-1",
            confidence: 0.91
        )
        let allowEntry = PrivacyOrgAllowEntry(
            id: "allow-openai",
            kind: .senderDomain,
            pattern: "openai.com",
            matchMode: .domainSuffix
        )

        try await store.upsertIdentity(identity)
        try await store.upsertIdentity(disabledIdentity)
        try await store.upsertIdentitySuggestion(suggestion)
        try await store.upsertOrgAllowEntry(allowEntry)

        let allIdentities = try await store.identities()
        let enabledIdentities = try await store.identities(enabledOnly: true)
        let pendingSuggestions = try await store.identitySuggestions(status: .pending)
        let allowlist = try await store.orgAllowlistEntries(enabledOnly: true)

        #expect(allIdentities.count == 2)
        #expect(enabledIdentities.count == 1)
        #expect(enabledIdentities.first?.value == "me@example.com")
        #expect(enabledIdentities.first?.normalizedHash != nil)
        #expect(pendingSuggestions.count == 1)
        #expect(pendingSuggestions.first?.value == "Jane Example")
        #expect(allowlist.count == 1)
        #expect(allowlist.first?.matchMode == .domainSuffix)

        try await store.updateIdentitySuggestionStatus(id: suggestion.id, status: .accepted)
        #expect(try await store.identitySuggestions(status: .accepted).count == 1)
    }

    @Test("Content index, spans, and jobs round-trip with filtering and counters")
    func contentIndexJobsAndCounters() async throws {
        let (store, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let scannedRecord = PrivacyIndexRecord(
            id: "email:msg-1:body",
            subjectKind: .emailBody,
            emailID: "msg-1",
            displayName: "Quarterly Results",
            extractStatus: .ready,
            scanStatus: .scanned,
            backend: .rulesOnly,
            modelVersion: "rules-only-v1",
            containsSensitive: true,
            containsSecret: true,
            severity: .critical,
            matchedCategories: [.secret],
            findingsSummary: "contains secret",
            spanCount: 1
        )
        let staleRecord = PrivacyIndexRecord(
            id: "source:src-1:Notes.txt",
            subjectKind: .sourceFile,
            sourceID: "src-1",
            relativePath: "Notes.txt",
            displayName: "Notes.txt",
            extractStatus: .ready,
            scanStatus: .stale,
            severity: .low
        )
        let span = PrivacySpanRecord(
            id: "span-secret-1",
            contentID: scannedRecord.id,
            category: .secret,
            startUTF16: 4,
            endUTF16: 12,
            confidence: 0.99,
            source: .model,
            placeholder: PrivacyCategory.secret.replacementToken
        )
        let completedJob = PrivacyIndexJobRecord(
            id: "job-completed-1",
            contentID: scannedRecord.id,
            reason: "backfill",
            priority: 4
        )
        let failedJob = PrivacyIndexJobRecord(
            id: "job-failed-1",
            contentID: staleRecord.id,
            reason: "file_change",
            priority: 2
        )

        try await store.upsertContentIndexRecord(scannedRecord)
        try await store.upsertContentIndexRecord(staleRecord)
        try await store.replaceSpans(for: scannedRecord.id, spans: [span])

        _ = try await store.enqueueIndexJob(completedJob)
        _ = try await store.enqueueIndexJob(failedJob)
        #expect(try await store.pendingIndexJobs(limit: 10).count == 2)

        try await store.markIndexJobsRunning(ids: [completedJob.id, failedJob.id])
        try await store.markIndexJobCompleted(id: completedJob.id)
        try await store.markIndexJobFailed(id: failedJob.id, error: "extract failed")

        let filtered = try await store.listContentIndex(
            scope: PrivacyIndexScope(subjectKinds: [.emailBody]),
            filter: PrivacyIndexFilter(containsSecret: true, categories: [.secret]),
            limit: 10
        )
        let storedSpans = try await store.spans(for: scannedRecord.id)
        let counters = try await store.indexRuntimeCounters()

        #expect(filtered.map(\.id) == [scannedRecord.id])
        #expect(storedSpans.count == 1)
        #expect(storedSpans.first?.category == .secret)
        #expect(counters.queued == 0)
        #expect(counters.running == 0)
        #expect(counters.failed == 1)
        #expect(counters.indexed == 2)
        #expect(counters.stale == 1)
    }
}
