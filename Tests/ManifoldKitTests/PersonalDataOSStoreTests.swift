// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CryptoKit
import Testing
@testable import ManifoldKit

@Suite("Personal Data OS Stores")
struct PersonalDataOSStoreTests {
    func makeDB() throws -> (DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-pdos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        try DatabaseMigrator(db: db).migrate()
        return (db, tempDir)
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func legacyLedgerHash(_ entry: LedgerEntry) -> String {
        sha256([
            "\(entry.sequence)",
            entry.entryType,
            entry.subjectTable ?? "",
            entry.subjectID ?? "",
            entry.previousHash ?? "",
            entry.payloadHash,
            entry.metadataJSON ?? "",
        ].joined(separator: "|"))
    }

    func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    @Test("Ledger verifies hash chain and detects tampering")
    func ledgerVerification() async throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }
        let ledger = try LedgerStore(db: db)

        let first = try await ledger.append(entryType: .memoryItem, subjectTable: "memory_items", subjectID: "mem-1", payload: "alpha")
        let second = try await ledger.append(entryType: .memoryChange, subjectTable: "memory_items", subjectID: "mem-1", payload: "beta")

        let verified = try await ledger.verifyChain()
        #expect(verified.verified)
        #expect(verified.checkedEntries == 2)
        #expect(second.previousHash == first.entryHash)

        try db.execute("UPDATE ledger_entries SET payload_hash = ? WHERE entry_id = ?", params: ["tampered", first.entryID])
        let broken = try await ledger.verifyChain()
        #expect(broken.verified == false)
        #expect(broken.firstBrokenEntryID == first.entryID)
    }

    @Test("Ledger timestamp tampering fails for new entries")
    func ledgerTimestampTamperingFails() async throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }
        let ledger = try LedgerStore(db: db)

        let entry = try await ledger.append(
            entryType: .memoryItem,
            subjectTable: "memory_items",
            subjectID: "mem-1",
            payload: "alpha"
        )

        try db.execute(
            "UPDATE ledger_entries SET timestamp = ? WHERE entry_id = ?",
            params: ["\(entry.timestamp + 3_600)", entry.entryID]
        )

        let broken = try await ledger.verifyChain()
        #expect(broken.verified == false)
        #expect(broken.firstBrokenEntryID == entry.entryID)
    }

    @Test("Ledger legacy hashes still verify with warning")
    func ledgerLegacyHashStillVerifies() async throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }
        let ledger = try LedgerStore(db: db)

        let entry = try await ledger.append(
            entryType: .memoryItem,
            subjectTable: "memory_items",
            subjectID: "mem-1",
            payload: "alpha"
        )

        try db.execute(
            "UPDATE ledger_entries SET entry_hash = ? WHERE entry_id = ?",
            params: [legacyLedgerHash(entry), entry.entryID]
        )

        let verified = try await ledger.verifyChain()
        #expect(verified.verified)
        #expect(verified.message.contains("legacy entry is not timestamp-covered"))
    }

    @Test("Exposure hash lookup finds prior content")
    func exposureHashLookup() async throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }
        let store = ExposureStore(db: db)
        let decision = AccessDecision(
            connectionID: "conn-1",
            agent: "cowork",
            toolName: "read_file",
            resourcePath: "Docs/readme.md",
            action: "read",
            allowed: true,
            reason: "standing_access",
            accessMode: "standing"
        )
        try await store.recordDecision(decision)
        try await store.recordExposure(
            ExposureRecord(
                connectionID: "conn-1",
                agent: "cowork",
                toolName: "read_file",
                resourcePath: "Docs/readme.md",
                byteCount: 5,
                contentHash: "hash-1",
                exposureType: "full_file",
                accessDecisionID: decision.id
            )
        )

        #expect(try await store.wasExposedBefore(contentHash: "hash-1"))
        #expect(try await store.wasExposedBefore(contentHash: "missing") == false)
        #expect(try await store.exposures(contentHash: "hash-1", limit: 10).first?.resourcePath == "Docs/readme.md")
    }

    @Test("Memory recall respects current source scope")
    func memoryRecallScopes() async throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }
        let store = try MemoryStore(db: db)

        _ = try await store.save(kind: .summary, title: "Invoice schema", body: "amount, vendor, date", contributingSourceIDs: ["src-invoices"])
        _ = try await store.save(kind: .summary, title: "HR schema", body: "employee, role", contributingSourceIDs: ["src-hr"])

        let scoped = try await store.recall(query: "schema", allowedSourceIDs: ["src-invoices"], limit: 10)
        #expect(scoped.count == 1)
        #expect(scoped[0].title == "Invoice schema")

        let tombstoned = try await store.tombstoneMemories(contributingSourceID: "src-invoices")
        #expect(tombstoned == 1)
        let afterRevocation = try await store.recall(query: "schema", allowedSourceIDs: ["src-invoices"], limit: 10)
        #expect(afterRevocation.isEmpty)
    }

    @Test("Memory settings round-trip and retention expires only agent-derived memory")
    func memorySettingsAndRetention() async throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }
        let store = try MemoryStore(db: db)

        let defaults = try await store.settings()
        #expect(defaults.amnesiacMode == false)
        #expect(defaults.derivedRetentionDays == 90)

        try await store.upsertSettings(MemorySettings(amnesiacMode: true, derivedRetentionDays: 14))
        let updated = try await store.settings()
        #expect(updated.amnesiacMode)
        #expect(updated.derivedRetentionDays == 14)

        let now = Date().timeIntervalSince1970
        let derived = try await store.save(
            kind: .note,
            title: "Derived",
            body: "agent-derived note",
            origin: .agentDerived,
            contributingSourceIDs: ["src-1"],
            expiresAt: now - 1
        )
        let authored = try await store.save(
            kind: .note,
            title: "Authored",
            body: "user-authored note",
            origin: .userAuthored,
            contributingSourceIDs: ["src-1"],
            expiresAt: now - 1
        )

        let expired = try await store.expireDerivedMemory(now: now)
        #expect(expired == 1)
        #expect(try await store.memory(id: derived.memoryID)?.status == MemoryStatus.expiredByRetention.rawValue)
        #expect(try await store.memory(id: authored.memoryID)?.status == MemoryStatus.active.rawValue)
    }

    @Test("Tool cost report aggregates calls")
    func toolCostReport() async throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }
        let store = try ToolMetricsStore(db: db)

        try await store.record(ToolCallMetric(connectionID: "conn", agent: "cowork", toolName: "read_file", durationMS: 12, outputBytes: 100, truncated: false, isError: false))
        try await store.record(ToolCallMetric(connectionID: "conn", agent: "cowork", toolName: "read_file", durationMS: 18, outputBytes: 200, truncated: true, isError: false))
        try await store.record(ToolCallMetric(connectionID: "conn", agent: "cowork", toolName: "recall_memory", durationMS: 3, outputBytes: 50, truncated: false, isError: false))

        let report = try await store.report(limit: 10)
        #expect(report.totalCalls == 3)
        #expect(report.totalOutputBytes == 350)
        #expect(report.callsByTool["read_file"] == 2)
    }

    @Test("Skill store versions manifests by hash")
    func skillManifestHashing() async throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }
        let store = try SkillStore(db: db)

        let first = try await store.save(name: "Summarize folder", manifestJSON: #"{"steps":["search","summarize"]}"#)
        let second = try await store.save(name: "Summarize folder", manifestJSON: #"{"steps":["search","read","summarize"]}"#)

        #expect(first.name == second.name)
        #expect(first.manifestHash != second.manifestHash)
        #expect(try await store.list(limit: 10).count == 1)
    }

    @Test("Capability handles enforce sinks and Rule of Two")
    func capabilityHandleFlowPolicy() async throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }
        let store = try CapabilityHandleStore(db: db)

        let handle = try await store.save(ValueHandle(
            origin: "email:thread-1",
            sensitivity: "sensitive",
            trustLevel: "untrusted",
            allowedSinks: ["model_context", "write_file"],
            grantID: "grant-1",
            lineage: [LineageRef(kind: "source", id: "src-mail")]
        ))

        let deniedSink = try await store.checkFlow(handleID: handle.handleID, sink: "external_url")
        #expect(deniedSink.allowed == false)

        let deniedRuleOfTwo = try await store.checkFlow(
            handleID: handle.handleID,
            sink: "write_file",
            untrustedInput: true,
            stateChangingAction: true
        )
        #expect(deniedRuleOfTwo.allowed == false)
        #expect(deniedRuleOfTwo.ruleOfTwoTriggered)

        let allowed = try await store.checkFlow(handleID: handle.handleID, sink: "model_context")
        #expect(allowed.allowed)
    }

    @Test("Exec run store persists typed statuses")
    func execRunPersistence() async throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }
        let store = try ExecRunStore(db: db)

        _ = try await store.save(result: ExecRunResult(status: .completed, reason: "ok", output: "filtered result"))
        _ = try await store.save(result: ExecRunResult(status: .refused, reason: "network denied"))

        let recent = try await store.recent(limit: 10)
        #expect(recent.count == 2)
        #expect(recent.first?.status == ExecRunStatus.refused.rawValue)
    }

    @Test("Knowledge graph filters nodes by current source lineage")
    func knowledgeGraphScopeFiltering() async throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }
        let store = try KnowledgeGraphStore(db: db)

        _ = try await store.upsertNode(kind: "memory", label: "invoice schema", lineage: [LineageRef(kind: "source", id: "src-invoices")])
        _ = try await store.upsertNode(kind: "memory", label: "hr schema", lineage: [LineageRef(kind: "source", id: "src-hr")])

        let scoped = try await store.query("schema", allowedSourceIDs: ["src-invoices"], limit: 10)
        #expect(scoped.count == 1)
        #expect(scoped[0].label == "invoice schema")
    }

    @Test("Fabrication finding store preserves verification evidence")
    func fabricationFindingPersistence() async throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }
        let store = try FabricationFindingStore(db: db)

        let finding = try await store.save(
            sessionID: "session-1",
            claimText: "I read invoices.csv",
            status: "unverified",
            evidence: ["evidence": "no matching exposure"]
        )

        let recent = try await store.recent(limit: 10)
        #expect(recent.count == 1)
        #expect(recent.first?.findingID == finding.findingID)
        #expect(recent.first?.evidenceJSON.contains("no matching exposure") == true)
    }

    @Test("Artifact index returns contextual chunk hits before full artifacts")
    func artifactIndexContextualChunks() async throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }
        let sourceDir = tempDir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = sourceDir.appendingPathComponent("guide.md")
        let lines = (1...90).map { line in
            line == 47
                ? "The retrieval needlephrase belongs in this exact middle section."
                : "Regular project note line \(line)."
        }
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let index = try ArtifactIndex(db: db)
        try await index.ensureGrantIndexed(
            grantID: "grant-1",
            materializationRoot: sourceDir.path,
            mounts: [ArtifactMount(sourceID: "src-1", mountName: "Docs", mountPath: sourceDir.path)]
        )

        let hits = try await index.search(grantID: "grant-1", query: "needlephrase", limit: 5, kinds: [.file])
        let first = try #require(hits.first)

        #expect(first.retrievalMode.hasPrefix("contextual_chunk"))
        #expect(first.chunkID != nil)
        #expect(first.contentHash != nil)
        #expect(first.context?.contains("Path: Docs/guide.md") == true)
        #expect(first.selection?.lineStart != nil)
        #expect(first.preview.joined(separator: "\n").contains("needlephrase"))
    }
}
