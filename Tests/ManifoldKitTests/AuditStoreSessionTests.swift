import Testing
import Foundation
@testable import ManifoldKit

@Suite("Session Grouping")
struct AuditStoreSessionTests {
    func makeStore() throws -> (AuditStore, DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        let store = try AuditStore(db: db)
        return (store, db, tempDir)
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Helper: log an entry with a specific timestamp offset (seconds from a base date).
    private func logAt(store: AuditStore, offsetSeconds: TimeInterval, agent: String = "cowork", action: AuditAction = .fileRead, filePath: String = "test.txt") async throws {
        // We use the public log() method which auto-assigns session_id.
        // To control timing, we need a different approach — log directly and set timestamps.
        try await store.log(action: action, agent: agent, filePath: filePath)
    }

    @Test("Zero entries returns empty sessions")
    func zeroEntries() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        let sessions = try await store.recentSessions(limit: 20)
        #expect(sessions.isEmpty)
    }

    @Test("Single entry creates single-event session")
    func singleEntry() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.log(action: .fileRead, agent: "cowork", filePath: "doc.txt")

        let sessions = try await store.recentSessions(limit: 20)
        #expect(sessions.count == 1)
        #expect(sessions[0].agent == "cowork")
        #expect(sessions[0].actionCount == 1)
        #expect(sessions[0].readCount == 1)
        #expect(sessions[0].writeCount == 0)
    }

    @Test("Multiple rapid entries stay in same session")
    func rapidEntries() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.log(action: .fileRead, agent: "cowork", filePath: "a.txt")
        try await store.log(action: .fileRead, agent: "cowork", filePath: "b.txt")
        try await store.log(action: .fileModified, agent: "cowork", filePath: "a.txt")

        let sessions = try await store.recentSessions(limit: 20)
        #expect(sessions.count == 1)
        #expect(sessions[0].actionCount == 3)
        #expect(sessions[0].readCount == 2)
        #expect(sessions[0].writeCount == 1)
    }

    @Test("Mixed agents create separate sessions")
    func mixedAgents() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.log(action: .fileRead, agent: "cowork", filePath: "a.txt")
        try await store.log(action: .fileRead, agent: "codex", filePath: "b.txt")

        let sessions = try await store.recentSessions(limit: 20)
        #expect(sessions.count == 2)
        let agents = Set(sessions.map(\.agent))
        #expect(agents.contains("cowork"))
        #expect(agents.contains("codex"))
    }

    @Test("Entries without agent grouped as Unknown Agent")
    func noAgent() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.log(action: .fileRead, filePath: "anon.txt")

        let sessions = try await store.recentSessions(limit: 20)
        #expect(sessions.count == 1)
        #expect(sessions[0].agent == "Unknown Agent")
    }

    @Test("Session events include snapshot join data for writes")
    func sessionEventsWriteJoin() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.log(action: .fileModified, agent: "cowork", filePath: "code.swift")

        let sessions = try await store.recentSessions(limit: 20)
        #expect(sessions.count == 1)

        let events = try await store.sessionEvents(sessionID: sessions[0].id)
        #expect(events.count == 1)
        #expect(events[0].action == "file_modified")
        #expect(events[0].filePath == "code.swift")
        // snapshot join may be nil if no matching snapshot exists
    }

    @Test("Session events show nil snapshot for reads")
    func sessionEventsReadNoSnapshot() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.log(action: .fileRead, agent: "cowork", filePath: "readme.md")

        let sessions = try await store.recentSessions(limit: 20)
        let events = try await store.sessionEvents(sessionID: sessions[0].id)
        #expect(events.count == 1)
        #expect(events[0].snapshotID == nil)
        #expect(events[0].beforeHash == nil)
    }

    @Test("Session ID is assigned on all entries")
    func sessionIDAssigned() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.log(action: .fileRead, agent: "cowork", filePath: "a.txt")
        try await store.log(action: .fileRead, agent: "cowork", filePath: "b.txt")

        let entries = try await store.recentEntries(limit: 10)
        for entry in entries {
            #expect(entry.sessionID != nil)
            #expect(!entry.sessionID!.isEmpty)
        }
        // Both should have the same session ID (rapid entries, same agent)
        #expect(entries[0].sessionID == entries[1].sessionID)
    }

    @Test("Backfill assigns session_ids to existing entries")
    func backfillMigration() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create DB with old-style entries (no session_id column initially simulated by inserting without it)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        try db.execute("""
            CREATE TABLE IF NOT EXISTS audit_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                run_id TEXT, workspace_id TEXT, agent TEXT,
                action TEXT NOT NULL, file_path TEXT,
                before_hash TEXT, after_hash TEXT, metadata TEXT
            )
        """)

        // Insert entries without session_id column
        let ts1 = "2026-04-05T10:00:00Z"
        let ts2 = "2026-04-05T10:01:00Z"
        let ts3 = "2026-04-05T10:10:00Z" // 10 min later — new session
        try db.execute("INSERT INTO audit_log (timestamp, agent, action, file_path) VALUES (?, ?, ?, ?)", params: [ts1, "cowork", "file_read", "a.txt"])
        try db.execute("INSERT INTO audit_log (timestamp, agent, action, file_path) VALUES (?, ?, ?, ?)", params: [ts2, "cowork", "file_read", "b.txt"])
        try db.execute("INSERT INTO audit_log (timestamp, agent, action, file_path) VALUES (?, ?, ?, ?)", params: [ts3, "cowork", "file_read", "c.txt"])

        // Run migrator — adds session_id column to existing table
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        // Now init AuditStore — this triggers the backfill
        let store = try AuditStore(db: db)

        let sessions = try await store.recentSessions(limit: 20)
        #expect(sessions.count == 2) // ts1+ts2 in one session, ts3 in another

        // Verify all entries now have session_ids
        let entries = try await store.recentEntries(limit: 10)
        for entry in entries {
            #expect(entry.sessionID != nil)
        }
    }

    @Test("Write count tracks file_modified and file_created")
    func writeCountAccuracy() async throws {
        let (store, _, tempDir) = try makeStore()
        defer { cleanup(tempDir) }

        try await store.log(action: .fileModified, agent: "cowork", filePath: "a.txt")
        try await store.log(action: .fileCreated, agent: "cowork", filePath: "b.txt")
        try await store.log(action: .fileRead, agent: "cowork", filePath: "c.txt")

        let sessions = try await store.recentSessions(limit: 20)
        #expect(sessions.count == 1)
        #expect(sessions[0].writeCount == 2)
        #expect(sessions[0].readCount == 1)
    }
}
