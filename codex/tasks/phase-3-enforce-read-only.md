# Phase 3: Enforce Standing Access = Read-Only

## Goal

Make always-on/standing access strictly read-only. Any write attempt during standing access returns an escalation message instead of writing. Create the `ApprovalQueue` actor for handling escalation requests.

This is the product's core differentiator — the demo, the Show HN screenshot, the entire thesis in one flow: agent tries to write → runtime escalates → user approves → tracked run starts → changes are versioned.

## Context

Read `design/RUNTIME-MIGRATION.md` (Phase 3 section) and `design/WHY-RUNTIME.md` ("Why Standing Access Must Be Read-Only").

Currently, `ManifoldBridge.writeFile()` resolves original-path mounts and writes directly during standing access. That means an agent in "always-on" mode can modify original files without a tracked run, without materialization, without snapshots. This bypasses the safety net that makes Manifold's promise real.

### Key files

- `Sources/ManifoldRuntime/ManifoldBridge.swift` — the `writeFile` method and `resolveAccess()` method. `resolveAccess()` returns an enum with cases like `.standing`, `.workBlock`, `.legacyGrant`. The `writeFile` method currently handles `.standing` by resolving original-path mounts and writing. This must change.

- `Sources/ManifoldMCP/ToolHandlers.swift` — registers the `write_file` tool. Must handle a new `WriteResult` case (`.escalationRequired`).

- `Sources/ManifoldKit/RequestStore.swift` — existing access request queue with rate limiting. This is the basis for the `ApprovalQueue`.

## Steps

### 1. Modify ManifoldBridge.writeFile()

Open `Sources/ManifoldRuntime/ManifoldBridge.swift`. Find the `writeFile` method. Find the code path where `resolveAccess()` returns `.standing` (always-on mode).

Current behavior: it resolves the file path against original-path mounts and writes directly.

New behavior:
```swift
case .standing:
    // Record the access decision as denied-write
    // ... (AccessDecision recording comes in Phase 4, skip for now)
    return .escalationRequired(
        message: "Always-on access is read-only. Start a tracked run to edit files.",
        path: path
    )
```

If `WriteResult` doesn't have an `.escalationRequired` case yet, add it. Check the existing `WriteResult` type — it may be in `ManifoldBridge.swift` or in `ManifoldKit`. Add:
```swift
public enum WriteResult: Sendable {
    case written(path: String, message: String)
    case escalationRequired(message: String, path: String)
    case error(message: String)
}
```

### 2. Update ToolHandlers

Open `Sources/ManifoldMCP/ToolHandlers.swift`. Find the `write_file` tool handler. It currently takes the result from `bridge.writeFile()` and returns it as MCP content.

Update it to handle the new `.escalationRequired` case:
```swift
case .escalationRequired(let message, _):
    return [["type": "text", "text": message]]
```

The escalation message should be returned as a normal text result (not an MCP error) so the agent receives it as guidance, not as a crash.

### 3. Create ApprovalQueue

Create `Sources/ManifoldRuntime/ApprovalQueue.swift`:

```swift
import Foundation
import os
import ManifoldKit

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "approval-queue")

/// Manages pending approval requests for write escalations.
/// When an agent tries to write during standing access, the request
/// lands here. The UI presents it. The user approves or denies.
public actor ApprovalQueue {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) {
        self.db = db
    }

    public struct PendingRequest: Sendable, Codable {
        public let id: String
        public let connectionID: String
        public let agent: String
        public let path: String
        public let action: String  // "write", "delete", etc.
        public let requestedAt: Date
        public var status: Status

        public enum Status: String, Sendable, Codable {
            case pending, approved, denied, expired
        }
    }

    public func submit(connectionID: String, agent: String, path: String, action: String) async throws -> PendingRequest {
        let request = PendingRequest(
            id: UUID().uuidString,
            connectionID: connectionID,
            agent: agent,
            path: path,
            action: action,
            requestedAt: Date(),
            status: .pending
        )
        try db.execute(
            "INSERT INTO approval_requests (id, connection_id, agent, path, action, requested_at, status) VALUES (?, ?, ?, ?, ?, ?, ?)",
            [request.id, request.connectionID, request.agent, request.path, request.action, request.requestedAt.timeIntervalSince1970, request.status.rawValue]
        )
        logger.info("Approval request submitted: \(request.id) for \(action) on \(path)")
        return request
    }

    public func approve(id: String) async throws { /* update status to approved */ }
    public func deny(id: String) async throws { /* update status to denied */ }
    public func pending() async throws -> [PendingRequest] { /* query pending requests */ }
    public func expire(olderThan: TimeInterval) async throws -> Int { /* expire old requests */ }
}
```

Implement the full CRUD. Use `RequestStore.swift` as reference for the SQL patterns.

### 4. Add Database Migration

Open `Sources/ManifoldKit/DatabaseMigrator.swift`. Add a new migration that creates the `approval_requests` table:

```sql
CREATE TABLE IF NOT EXISTS approval_requests (
    id TEXT PRIMARY KEY,
    connection_id TEXT NOT NULL,
    agent TEXT NOT NULL,
    path TEXT NOT NULL,
    action TEXT NOT NULL,
    requested_at REAL NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    resolved_at REAL
);
CREATE INDEX IF NOT EXISTS idx_approval_requests_status ON approval_requests(status);
CREATE INDEX IF NOT EXISTS idx_approval_requests_agent ON approval_requests(agent);
```

### 5. Wire ApprovalQueue into ManifoldRuntime

Open `Sources/ManifoldRuntime/ManifoldRuntime.swift`. Add `public let approvalQueue: ApprovalQueue` as a property. Initialize it in `init()` after the database is ready.

## Constraints

- Do NOT break existing write functionality for tracked runs / work blocks. Only `.standing` mode is affected. Verify by checking that the `.workBlock` and `.legacyGrant` code paths in `writeFile` still write normally.
- The escalation message must be user-friendly. An agent reading "Always-on access is read-only. Start a tracked run to edit files." should understand what to do.
- `ApprovalQueue` is an actor. SQL uses parameterized queries only.
- The migration must be idempotent (use `CREATE TABLE IF NOT EXISTS`).

## Done When

- [ ] `ManifoldBridge.writeFile()` returns `.escalationRequired` when `resolveAccess()` is `.standing`
- [ ] `ToolHandlers` handles `.escalationRequired` and returns the message as text content
- [ ] `ApprovalQueue.swift` exists with submit/approve/deny/pending/expire methods
- [ ] `approval_requests` table migration exists in `DatabaseMigrator.swift`
- [ ] `ManifoldRuntime` has an `approvalQueue` property
- [ ] `swift build` succeeds
- [ ] `swift test` passes — existing write tests (which use grant/workBlock context) still pass
- [ ] Manual test: calling `writeFile` with a standing-access bridge returns escalation, not a write
