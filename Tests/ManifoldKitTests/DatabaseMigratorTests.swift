import Testing
import Foundation
@testable import ManifoldKit

@Suite("Database Migrator")
struct DatabaseMigratorTests {
    func makeDB() throws -> (DatabaseConnection, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-migrator-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseConnection(url: tempDir.appendingPathComponent("manifold.db"))
        return (db, tempDir)
    }

    func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    @Test("Fresh database starts at version 0")
    func freshVersion() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        #expect(try migrator.currentVersion() == 0)
    }

    @Test("Migrate applies all migrations")
    func migrateAll() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        let applied = try migrator.migrate()
        #expect(applied >= 2, "At least baseline + session_id migrations")
        #expect(try migrator.currentVersion() >= 2)
    }

    @Test("Running migrate twice is idempotent")
    func idempotent() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator = try DatabaseMigrator(db: db)
        let first = try migrator.migrate()
        let second = try migrator.migrate()
        #expect(first >= 2)
        #expect(second == 0, "No migrations applied on second run")
    }

    @Test("Migration v2 adds session_id to existing audit_log")
    func upgradeExistingDB() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        // Create old-style audit_log without session_id
        try db.execute("""
            CREATE TABLE audit_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                run_id TEXT, workspace_id TEXT, agent TEXT,
                action TEXT NOT NULL, file_path TEXT,
                before_hash TEXT, after_hash TEXT, metadata TEXT
            )
        """)

        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        // Verify session_id column exists
        let columns = try db.queryAll("PRAGMA table_info(audit_log)")
        let hasSessionID = columns.contains { $0["name"] == "session_id" }
        #expect(hasSessionID, "session_id column should be added by migration v2")
    }

    @Test("Migration tracking persists across instances")
    func persistent() throws {
        let (db, tempDir) = try makeDB()
        defer { cleanup(tempDir) }

        let migrator1 = try DatabaseMigrator(db: db)
        try migrator1.migrate()
        let version1 = try migrator1.currentVersion()

        // New migrator instance on same DB
        let migrator2 = try DatabaseMigrator(db: db)
        #expect(try migrator2.currentVersion() == version1)
        #expect(try migrator2.migrate() == 0)
    }
}
