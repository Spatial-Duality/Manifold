# Phase 4: Add AccessDecision + ExposureRecord

## Goal

Record every access decision (allowed or denied, with reason and policy state) and every content exposure (bytes returned to the agent, with hash and byte count). This is Manifold's deepest moat — no other tool answers "what could this agent have seen?" and "what did this agent actually see?"

## Context

Read `design/RUNTIME-MIGRATION.md` (Phase 4 section) and `design/WHY-RUNTIME.md` ("Why AccessDecision and ExposureRecord").

Tools leak content in ways that aren't "reads." `search_files` returns snippets. `diff_file` returns diff content. `read_email` shows body text. `read_range` returns partial files. If the audit log only tracks explicit file reads, it misses most of what the agent actually saw. The exposure record captures them all.

### Key files

- `Sources/ManifoldRuntime/ManifoldBridge.swift` — every access-checking method must record an `AccessDecision`. Every content-returning method must record an `ExposureRecord`.
- `Sources/ManifoldKit/AuditStore.swift` — existing audit log. Reference for SQL patterns.
- `Sources/ManifoldKit/DatabaseMigrator.swift` — needs new migrations.
- `Sources/ManifoldRuntime/ManifoldRuntime.swift` — needs new `exposureStore` property.

## Steps

### 1. Create AccessDecision Model

Create `Sources/ManifoldKit/AccessDecision.swift`:

```swift
import Foundation

/// Records every access check — allowed or denied — with full context.
/// Answers: "What could this agent have seen?"
public struct AccessDecision: Sendable, Codable {
    public let id: String
    public let connectionID: String
    public let agent: String
    public let toolName: String
    public let resourcePath: String?    // file path, email ID, etc.
    public let action: String           // "read", "write", "search", "list"
    public let allowed: Bool
    public let reason: String           // "standing_access", "work_block", "policy_denied", "paused"
    public let accessMode: String       // "standing", "workBlock", "legacyGrant"
    public let timestamp: Date
    public let policySnapshot: String?  // JSON of policy state at decision time (optional, for audits)
}
```

### 2. Create ExposureRecord Model

Create `Sources/ManifoldKit/ExposureRecord.swift`:

```swift
import Foundation

/// Records every byte of content returned to the agent.
/// Answers: "What did this agent actually see?"
public struct ExposureRecord: Sendable, Codable {
    public let id: String
    public let connectionID: String
    public let agent: String
    public let toolName: String         // "read_file", "search_files", "diff_file", "read_email", etc.
    public let resourcePath: String?    // file path, email ID
    public let byteCount: Int
    public let contentHash: String      // SHA-256 of the returned content
    public let exposureType: String     // "full_file", "range", "snippet", "diff", "email_body", "email_preview"
    public let timestamp: Date
    public let accessDecisionID: String // links back to the AccessDecision that allowed this
}
```

### 3. Create ExposureStore Actor

Create `Sources/ManifoldKit/ExposureStore.swift`:

```swift
import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "exposure-store")

/// Persists AccessDecision and ExposureRecord to SQLite.
public actor ExposureStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    // MARK: - AccessDecision

    public func recordDecision(_ decision: AccessDecision) throws {
        try db.execute("""
            INSERT INTO access_decisions (id, connection_id, agent, tool_name, resource_path, action, allowed, reason, access_mode, timestamp, policy_snapshot)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [decision.id, decision.connectionID, decision.agent, decision.toolName,
                  decision.resourcePath, decision.action, decision.allowed ? 1 : 0,
                  decision.reason, decision.accessMode, decision.timestamp.timeIntervalSince1970,
                  decision.policySnapshot])
    }

    public func decisions(connectionID: String, limit: Int = 100) throws -> [AccessDecision] {
        // Query and decode
    }

    public func decisionsForPath(_ path: String, limit: Int = 50) throws -> [AccessDecision] {
        // Query by resource_path
    }

    // MARK: - ExposureRecord

    public func recordExposure(_ exposure: ExposureRecord) throws {
        try db.execute("""
            INSERT INTO exposure_records (id, connection_id, agent, tool_name, resource_path, byte_count, content_hash, exposure_type, timestamp, access_decision_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [exposure.id, exposure.connectionID, exposure.agent, exposure.toolName,
                  exposure.resourcePath, exposure.byteCount, exposure.contentHash,
                  exposure.exposureType, exposure.timestamp.timeIntervalSince1970,
                  exposure.accessDecisionID])
    }

    public func exposures(connectionID: String, limit: Int = 100) throws -> [ExposureRecord] {
        // Query and decode
    }

    public func totalExposure(connectionID: String) throws -> (fileCount: Int, totalBytes: Int) {
        // Aggregate query
    }

    // MARK: - Combined Query

    /// Human-readable explanation: "Allowed because standing access includes folder X"
    public func explainDecision(connectionID: String, path: String, action: String) throws -> String {
        // Find the most recent AccessDecision for this path+action, format as explanation
    }
}
```

Implement all methods fully. Follow the SQL patterns in `AuditStore.swift` for query structure and decoding.

### 4. Add Database Migrations

Open `Sources/ManifoldKit/DatabaseMigrator.swift`. Add migrations:

```sql
CREATE TABLE IF NOT EXISTS access_decisions (
    id TEXT PRIMARY KEY,
    connection_id TEXT NOT NULL,
    agent TEXT NOT NULL,
    tool_name TEXT NOT NULL,
    resource_path TEXT,
    action TEXT NOT NULL,
    allowed INTEGER NOT NULL,
    reason TEXT NOT NULL,
    access_mode TEXT NOT NULL,
    timestamp REAL NOT NULL,
    policy_snapshot TEXT
);
CREATE INDEX IF NOT EXISTS idx_access_decisions_connection ON access_decisions(connection_id);
CREATE INDEX IF NOT EXISTS idx_access_decisions_path ON access_decisions(resource_path);
CREATE INDEX IF NOT EXISTS idx_access_decisions_timestamp ON access_decisions(timestamp);

CREATE TABLE IF NOT EXISTS exposure_records (
    id TEXT PRIMARY KEY,
    connection_id TEXT NOT NULL,
    agent TEXT NOT NULL,
    tool_name TEXT NOT NULL,
    resource_path TEXT,
    byte_count INTEGER NOT NULL,
    content_hash TEXT NOT NULL,
    exposure_type TEXT NOT NULL,
    timestamp REAL NOT NULL,
    access_decision_id TEXT NOT NULL REFERENCES access_decisions(id)
);
CREATE INDEX IF NOT EXISTS idx_exposure_records_connection ON exposure_records(connection_id);
CREATE INDEX IF NOT EXISTS idx_exposure_records_decision ON exposure_records(access_decision_id);
CREATE INDEX IF NOT EXISTS idx_exposure_records_timestamp ON exposure_records(timestamp);
```

### 5. Wire into ManifoldRuntime

Open `Sources/ManifoldRuntime/ManifoldRuntime.swift`. Add `public let exposureStore: ExposureStore`. Initialize after `db` is ready.

### 6. Instrument ManifoldBridge

This is the largest and most important step. Open `Sources/ManifoldRuntime/ManifoldBridge.swift`.

The bridge needs a reference to `ExposureStore`. Add it as an init parameter.

For **every method that checks access** (resolveAccess, readFile, writeFile, searchFiles, listFiles, fileInfo, readRange, diffFile, listArchive, extractFile, readEmail, listEmails):

a) After the access check resolves, create and record an `AccessDecision`:
```swift
let decision = AccessDecision(
    id: UUID().uuidString,
    connectionID: self.connectionID,
    agent: self.targetApp.rawValue,
    toolName: "read_file",
    resourcePath: path,
    action: "read",
    allowed: true,  // or false if denied
    reason: "standing_access",  // or "work_block", "policy_denied", etc.
    accessMode: accessMode.description,
    timestamp: Date(),
    policySnapshot: nil
)
try? await exposureStore.recordDecision(decision)
```

b) For **every method that returns content** (readFile, readRange, searchFiles, diffFile, extractFile, readEmail), also create and record an `ExposureRecord`:
```swift
let contentData = returnedContent.data(using: .utf8) ?? Data()
let hash = SHA256.hash(data: contentData).map { String(format: "%02x", $0) }.joined()
let exposure = ExposureRecord(
    id: UUID().uuidString,
    connectionID: self.connectionID,
    agent: self.targetApp.rawValue,
    toolName: "read_file",
    resourcePath: path,
    byteCount: contentData.count,
    contentHash: hash,
    exposureType: "full_file",
    timestamp: Date(),
    accessDecisionID: decision.id
)
try? await exposureStore.recordExposure(exposure)
```

**Critical:** `searchFiles` must record an exposure for each snippet returned, not just the file path. `diffFile` must record the diff content as an exposure. `readEmail` must record the email body bytes. These are content leaks that a path-only audit log misses.

Use `try?` for recording — exposure tracking must never cause a tool call to fail. Log errors but do not propagate them.

### 7. Add SHA-256 Hashing

If not already available, add a helper for SHA-256:
```swift
import CryptoKit

extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
```

`CryptoKit` is available on macOS and does not require any external dependencies.

## Constraints

- Exposure tracking must NEVER cause a tool call to fail. Use `try?` and log errors.
- SHA-256 for content hashing. Use `CryptoKit` (Apple framework, no external deps).
- `ExposureStore` is an actor. Parameterized SQL only.
- Do not change the return values of any tool. The recording is observational — agents must not know or care that exposures are being recorded.
- Migrations must be idempotent.
- Existing tests must pass unchanged.

## Done When

- [ ] `AccessDecision.swift` exists in ManifoldKit
- [ ] `ExposureRecord.swift` exists in ManifoldKit
- [ ] `ExposureStore.swift` exists in ManifoldKit with full CRUD + `explainDecision`
- [ ] `access_decisions` and `exposure_records` tables created by migration
- [ ] `ManifoldRuntime` has `exposureStore` property
- [ ] `ManifoldBridge` records `AccessDecision` for every access-checking method
- [ ] `ManifoldBridge` records `ExposureRecord` for every content-returning method
- [ ] `searchFiles` records per-snippet exposures (not just file path)
- [ ] `diffFile` records diff content exposure
- [ ] `readEmail` records email body exposure
- [ ] `swift build` succeeds
- [ ] `swift test` passes
- [ ] Write a new test: read a file → verify `AccessDecision` and `ExposureRecord` exist in the store
- [ ] Write a new test: `explainDecision` returns a human-readable string
