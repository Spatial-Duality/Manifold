# Codex Task Prompts — Runtime Migration

Copy-paste each prompt into Codex one at a time, in order.
Run Phase 1 first. Wait for it to complete. Then Phase 2. And so on.

Each prompt is self-contained. The `---COPY BELOW---` and `---COPY ABOVE---` markers show what to paste.

---

## Phase 1: Extract ManifoldRuntime Target

---COPY BELOW---

Read `codex/AGENTS.md` and `design/RUNTIME-MIGRATION.md` (Phase 1 section) before starting.

**Goal:** Create a new `ManifoldRuntime` Swift package target that becomes the single composition root for all stores. Move `ManifoldBridge.swift` and `AgentRuntimeContext.swift` from `Sources/ManifoldMCP/` into the new `Sources/ManifoldRuntime/` target.

**Steps:**

1. Create `Sources/ManifoldRuntime/` directory.

2. Move `Sources/ManifoldMCP/ManifoldBridge.swift` → `Sources/ManifoldRuntime/ManifoldBridge.swift`. Fix imports to use `import ManifoldKit`. Make any types it needs `public` in ManifoldKit.

3. Move `Sources/ManifoldMCP/AgentRuntimeContext.swift` → `Sources/ManifoldRuntime/AgentRuntimeContext.swift`. Fix imports.

4. Create `Sources/ManifoldRuntime/ManifoldRuntime.swift` — an `actor` that owns all stores as non-optional `public let` properties. It takes an optional `storeURL` (defaults to `~/Library/Application Support/Manifold/store`), creates `DatabaseConnection`, runs `DatabaseMigrator`, then creates all stores: `ContentStore`, `AuditStore`, `SnapshotStore`, `WorkspaceLeaseManager`, `GrantStore`, `EmailStore`, `ArtifactIndex`, `PolicyStore`, `WorkBlockStore`, `EmailSyncEngine`. It manages a `[String: ManifoldBridge]` dictionary with `bridge(for:targetApp:version:)` and `removeBridge(_:)` methods. See the code sketch in `design/RUNTIME-MIGRATION.md` Phase 1.

5. Create `Sources/ManifoldRuntime/ManifoldServiceAPI.swift` — a `public protocol ManifoldServiceAPI: Sendable` defining the product-vocabulary API. Copy from `design/RUNTIME-MIGRATION.md` "The Service Protocol" section.

6. Create `Sources/ManifoldRuntime/RuntimeTypes.swift` — `Sendable` structs for the service API return types: `RuntimeStatus`, `TrustedFolder`, `FileEntry`, `FileContent`, `SearchHit`, `FileMetadata`, `WriteResult`, `TrackedRun`, `PromotionPreview`, `PromotionResult`, `ChangeEntry`, `EmailEntry`, `EmailContent`, `RevealResult`, `SessionEntry`, `SessionDetail`, `ApprovalRequest`, `AccessExplanation`, `ExposureEntry`, `AuditEntry`, `FileScope`. Keep them thin.

7. Update `Package.swift`: add `.target(name: "ManifoldRuntime", dependencies: ["ManifoldKit"], path: "Sources/ManifoldRuntime")`. Update ManifoldMCP deps to `["ManifoldKit", "ManifoldRuntime"]`. Update ManifoldCLI deps to `["ManifoldKit", "ManifoldRuntime"]`. Update ManifoldKitTests deps to `["ManifoldKit", "ManifoldMCP", "ManifoldRuntime"]`.

8. Fix all remaining import/visibility issues until `swift build` passes.

**Constraints:**
- Swift 6 strict concurrency. `ManifoldRuntime` is an `actor`. All store properties non-optional.
- Do NOT modify `ManifoldStore.swift` or `ManifoldMCPServer.swift` — that's Phase 2.
- Do NOT modify existing ManifoldKit store files except to make types `public` where needed.
- Existing tests must pass unchanged.
- Logger: `subsystem: "com.spatialduality.manifold"`, `category: "runtime"`.

**Done when:** `swift build` passes, `swift test` passes, `Sources/ManifoldRuntime/` has all 5 files, the moved files no longer exist in `Sources/ManifoldMCP/`.

---COPY ABOVE---

---

## Phase 2: Delete the Second Composition Root

---COPY BELOW---

Read `codex/AGENTS.md` and `design/RUNTIME-MIGRATION.md` (Phase 2 section) before starting.

**Goal:** Make both the app and MCP server use `ManifoldRuntime` as their single source of stores. Delete all duplicate store creation. Make all store references non-optional in the app model layer.

**Steps:**

1. **MCP Server:** Open `Sources/ManifoldMCP/ManifoldMCPServer.swift`. Delete all direct store creation (the block that creates `DatabaseConnection`, `DatabaseMigrator`, `ContentStore`, `AuditStore`, `SnapshotStore`, `GrantStore`, `EmailStore`, `ArtifactIndex`, `PolicyStore`, `WorkBlockStore`, and `ManifoldBridge`). Replace with: `import ManifoldRuntime`, `let runtime = try ManifoldRuntime()`, get bridge from `runtime.bridge(for:targetApp:version:)`. The MCP server creates ManifoldRuntime in-process for now — Phase 7 replaces this with XPC.

2. **App ManifoldStore:** Open `ManifoldApp/ManifoldApp/Models/ManifoldStore.swift`. Add `import ManifoldRuntime`. Add `let runtime: ManifoldRuntime` as a non-optional property. In init, create: `self.runtime = try! ManifoldRuntime()` (fail-fast). Delete `initStores()` and `reinjectStores()`. Delete all optional store properties. Configure sub-models with `runtime.policyStore`, `runtime.workBlockStore`, etc.

3. **PolicyModel:** Open `ManifoldApp/ManifoldApp/Models/PolicyModel.swift`. Change all optional store properties to non-optional. Remove all `guard let store = ... else { return }` guards. The `configure()` method takes non-optional stores.

4. **SessionModel:** Open `ManifoldApp/ManifoldApp/Models/SessionModel.swift`. Same: non-optional stores, remove optional guards.

5. **Other models:** Check `HistoryModel.swift`, `StorageModel.swift`, `EmailAccountModel.swift` for optional store patterns. Fix each.

6. Run `swift build` and fix any errors. Run `swift test`.

**Constraints:**
- Do NOT change ManifoldBridge logic or store logic. Only change who creates them.
- Do NOT add XPC — that's Phase 5+.
- If tests import ManifoldMCP and expect ManifoldBridge there, update the import to ManifoldRuntime.
- `try!` for runtime init in the app is acceptable — if the DB can't init, the app has nothing to show.

**Done when:** Zero `DatabaseConnection(url:)` calls outside `ManifoldRuntime.swift`. Zero optional store properties in app models. Zero `guard let store` patterns. `swift build` passes. `swift test` passes.

---COPY ABOVE---

---

## Phase 3: Enforce Standing Access = Read-Only

---COPY BELOW---

Read `codex/AGENTS.md` and `design/RUNTIME-MIGRATION.md` (Phase 3 section) before starting. This is the product's core promise — get it right.

**Goal:** Make always-on/standing access strictly read-only. Any write attempt during standing access returns an escalation message instead of writing. Create the `ApprovalQueue` actor.

**Steps:**

1. **Modify ManifoldBridge.writeFile():** Open `Sources/ManifoldRuntime/ManifoldBridge.swift`. Find the `writeFile` method. Find the code path where `resolveAccess()` returns `.standing` (always-on mode). Currently it writes the file. Change it to return an escalation result instead of writing. The agent should receive: "Always-on access is read-only. Start a tracked run to edit files."

   If `WriteResult` doesn't have an `.escalationRequired` case, add one. Check the existing type definition. Add:
   ```swift
   case escalationRequired(message: String, path: String)
   ```

2. **Update ToolHandlers:** Open `Sources/ManifoldMCP/ToolHandlers.swift`. Find the `write_file` handler. Handle the `.escalationRequired` case — return the message as normal text content (not an MCP error), so the agent gets guidance.

3. **Create ApprovalQueue:** Create `Sources/ManifoldRuntime/ApprovalQueue.swift`. An `actor` with a `PendingRequest` struct (id, connectionID, agent, path, action, requestedAt, status enum of pending/approved/denied/expired). Methods: `submit()`, `approve(id:)`, `deny(id:)`, `pending()`, `expire(olderThan:)`. SQL storage via `DatabaseConnection`. Use `RequestStore.swift` as reference for SQL patterns. Logger: category `"approval-queue"`.

4. **Database migration:** Open `Sources/ManifoldKit/DatabaseMigrator.swift`. Add a migration creating `approval_requests` table:
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
   ```

5. **Wire into runtime:** Open `Sources/ManifoldRuntime/ManifoldRuntime.swift`. Add `public let approvalQueue: ApprovalQueue`. Init after db is ready.

**Constraints:**
- Do NOT break writes for tracked runs / work blocks. Only `.standing` mode is affected.
- The escalation message is text, not an MCP error.
- `ApprovalQueue` is an actor. Parameterized SQL only. Migrations are idempotent.
- Existing write tests (which use grant/workBlock context) must still pass.

**Done when:** Calling `writeFile` under standing access returns `.escalationRequired`. Calling `writeFile` under a work block still writes normally. `ApprovalQueue` exists with full CRUD. Migration exists. `swift build` passes. `swift test` passes.

---COPY ABOVE---

---

## Phase 4: Add AccessDecision + ExposureRecord

---COPY BELOW---

Read `codex/AGENTS.md` and `design/RUNTIME-MIGRATION.md` (Phase 4 section) before starting. This is Manifold's deepest moat — careful instrumentation.

**Goal:** Record every access decision (allowed/denied with reason) and every content exposure (bytes returned to agent with hash). Search snippets, diffs, email previews — all are exposures.

**Steps:**

1. **Create `Sources/ManifoldKit/AccessDecision.swift`:** A `Sendable Codable` struct with: id (String), connectionID, agent, toolName, resourcePath (optional), action ("read"/"write"/"search"/"list"), allowed (Bool), reason ("standing_access"/"work_block"/"policy_denied"/"paused"), accessMode, timestamp, policySnapshot (optional String).

2. **Create `Sources/ManifoldKit/ExposureRecord.swift`:** A `Sendable Codable` struct with: id, connectionID, agent, toolName, resourcePath (optional), byteCount (Int), contentHash (String, SHA-256), exposureType ("full_file"/"range"/"snippet"/"diff"/"email_body"/"email_preview"), timestamp, accessDecisionID (links to the AccessDecision).

3. **Create `Sources/ManifoldKit/ExposureStore.swift`:** An `actor` with methods:
   - `recordDecision(_ decision: AccessDecision) throws`
   - `recordExposure(_ exposure: ExposureRecord) throws`
   - `decisions(connectionID:limit:) throws -> [AccessDecision]`
   - `exposures(connectionID:limit:) throws -> [ExposureRecord]`
   - `totalExposure(connectionID:) throws -> (fileCount: Int, totalBytes: Int)`
   - `explainDecision(connectionID:path:action:) throws -> String` — human-readable
   
   Use `AuditStore.swift` as SQL pattern reference.

4. **Database migrations** in `DatabaseMigrator.swift`:
   ```sql
   CREATE TABLE IF NOT EXISTS access_decisions (
       id TEXT PRIMARY KEY, connection_id TEXT NOT NULL, agent TEXT NOT NULL,
       tool_name TEXT NOT NULL, resource_path TEXT, action TEXT NOT NULL,
       allowed INTEGER NOT NULL, reason TEXT NOT NULL, access_mode TEXT NOT NULL,
       timestamp REAL NOT NULL, policy_snapshot TEXT
   );
   CREATE INDEX IF NOT EXISTS idx_ad_connection ON access_decisions(connection_id);
   CREATE INDEX IF NOT EXISTS idx_ad_path ON access_decisions(resource_path);
   
   CREATE TABLE IF NOT EXISTS exposure_records (
       id TEXT PRIMARY KEY, connection_id TEXT NOT NULL, agent TEXT NOT NULL,
       tool_name TEXT NOT NULL, resource_path TEXT, byte_count INTEGER NOT NULL,
       content_hash TEXT NOT NULL, exposure_type TEXT NOT NULL,
       timestamp REAL NOT NULL, access_decision_id TEXT NOT NULL
   );
   CREATE INDEX IF NOT EXISTS idx_er_connection ON exposure_records(connection_id);
   CREATE INDEX IF NOT EXISTS idx_er_decision ON exposure_records(access_decision_id);
   ```

5. **Wire into ManifoldRuntime:** Add `public let exposureStore: ExposureStore`. Pass it to `ManifoldBridge` as a new init parameter.

6. **Instrument ManifoldBridge:** Open `Sources/ManifoldRuntime/ManifoldBridge.swift`. For EVERY method that checks access, create and record an `AccessDecision` after the check resolves. For EVERY method that returns content, also create and record an `ExposureRecord` with byte count and SHA-256 hash (`import CryptoKit`, use `SHA256.hash(data:)`).

   Critical: `searchFiles` must record an exposure per snippet. `diffFile` must record diff content. `readEmail` must record body bytes. `readRange` must record the range content. These are all content the agent saw.

   Use `try?` for all recording — exposure tracking must never cause a tool call to fail. Log errors with `os.Logger`.

**Constraints:**
- Recording must NEVER cause a tool call to fail. Use `try?`.
- SHA-256 via `CryptoKit` (Apple framework, no external deps).
- Do not change any tool return values. Recording is observational.
- Existing tests must pass unchanged.

**Done when:** Every access-checking bridge method records an `AccessDecision`. Every content-returning bridge method records an `ExposureRecord`. Search snippets, diffs, email bodies all get exposure records. `explainDecision` returns a readable string. `swift build` passes. `swift test` passes. Write a test that reads a file and verifies both records exist.

---COPY ABOVE---

---

## Phase 5: Define the XPC Layer

---COPY BELOW---

Read `codex/AGENTS.md` and `design/RUNTIME-MIGRATION.md` (Phase 5 section) before starting.

**Goal:** Create the `ManifoldXPC` target with XPC protocol, service adapter, client, and coding types. This is the transport between the LaunchAgent runtime and all clients.

**Steps:**

1. Create `Sources/ManifoldXPC/` directory.

2. **`ManifoldXPCProtocol.swift`:** An `@objc public protocol ManifoldXPCProtocol` with exactly 4 methods:
   - `callTool(connectionID: String, toolName: String, arguments: Data, reply: @escaping (Data, Bool) -> Void)`
   - `command(name: String, payload: Data, reply: @escaping (Data, NSError?) -> Void)`
   - `connect(agent: String, clientName: String, clientVersion: String, initializeParams: Data, reply: @escaping (String?, NSError?) -> Void)`
   - `disconnect(connectionID: String)`
   
   Must be `@objc` — `NSXPCInterface` requires it. All params are Foundation types only.

3. **`ManifoldXPCService.swift`:** A class implementing `NSXPCListenerDelegate` and `ManifoldXPCProtocol`. Takes a `ManifoldRuntime` in init. `listener(_:shouldAcceptNewConnection:)` sets up the exported interface and resumes. `callTool` dispatches to the bridge for the connectionID — reference `ToolHandlers.swift` for the tool name → bridge method mapping. `command` dispatches based on name: "getStatus", "pauseAgent", "resumeAgent", "listApprovalRequests", "approveRequest", "denyRequest", "recentActivity", "exposureLog". All dispatch in `Task {}` blocks.

4. **`ManifoldXPCClient.swift`:** A `@unchecked Sendable` class. `static let serviceName = "com.spatialduality.manifold.runtime"`. Creates `NSXPCConnection(machServiceName:)`, sets `remoteObjectInterface`, handles invalidation/interruption. Provides async wrappers:
   - `callTool(connectionID:toolName:arguments:) async throws -> [String: Any]`
   - `command(name:payload:) async throws -> [String: Any]`
   - `connectAgent(agent:clientName:clientVersion:) async throws -> String`
   - `disconnectAgent(connectionID:)`
   
   Uses `withCheckedThrowingContinuation` to bridge callback → async.

5. **`XPCCodingTypes.swift`:** Helper `Codable` structs for common command payloads and responses.

6. **Package.swift:** Add `.target(name: "ManifoldXPC", dependencies: ["ManifoldRuntime"], path: "Sources/ManifoldXPC")`.

**Constraints:**
- Protocol is `@objc`. No Swift-only types in the protocol signature.
- Protocol stays at 4 methods forever. All features route through `callTool` or `command`.
- Client handles connection invalidation gracefully (reconnect on next call).
- JSON serialization via `JSONSerialization`, not `Codable` over XPC.

**Done when:** `ManifoldXPC` target compiles. Protocol is `@objc` with 4 methods. Service dispatches all 17 tool names and all command names. Client has async wrappers. `swift build` passes. `swift test` passes.

---COPY ABOVE---

---

## Phase 6: Build the LaunchAgent Binary

---COPY BELOW---

Read `codex/AGENTS.md` and `design/RUNTIME-MIGRATION.md` (Phase 6 section) before starting.

**Goal:** Create the `ManifoldAgent` executable — a headless LaunchAgent that hosts `ManifoldRuntime` and exposes it as an XPC Mach service. Create the launchd plist.

**Steps:**

1. **`Sources/ManifoldAgent/main.swift`:**
   ```swift
   import Foundation
   import ManifoldRuntime
   import ManifoldXPC
   import os
   
   let logger = Logger(subsystem: "com.spatialduality.manifold", category: "agent")
   logger.info("ManifoldAgent starting...")
   
   do {
       let runtime = try ManifoldRuntime()
       let service = ManifoldXPCService(runtime: runtime)
       let listener = NSXPCListener(machServiceName: ManifoldXPCClient.serviceName)
       listener.delegate = service
       listener.resume()
       logger.info("ManifoldAgent ready on \(ManifoldXPCClient.serviceName)")
       
       Task {
           try? await runtime.snapshotStore.pruneByAge(days: 30)
           try? await runtime.contentStore.garbageCollect()
           try? await runtime.approvalQueue.expire(olderThan: 30 * 60)
       }
       
       RunLoop.main.run()
   } catch {
       logger.fault("ManifoldAgent failed: \(error.localizedDescription)")
       exit(1)
   }
   ```

2. **LaunchAgent plist** at `Resources/com.spatialduality.manifold.runtime.plist`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>Label</key>
       <string>com.spatialduality.manifold.runtime</string>
       <key>BundleIdentifier</key>
       <string>com.spatialduality.manifold.runtime</string>
       <key>MachServices</key>
       <dict>
           <key>com.spatialduality.manifold.runtime</key>
           <true/>
       </dict>
       <key>KeepAlive</key>
       <dict>
           <key>SuccessfulExit</key>
           <false/>
       </dict>
       <key>ProcessType</key>
       <string>Interactive</string>
   </dict>
   </plist>
   ```

3. **Package.swift:** Add `.executableTarget(name: "ManifoldAgent", dependencies: ["ManifoldRuntime", "ManifoldXPC"], path: "Sources/ManifoldAgent")`.

4. **SMAppService registration:** In the app (whichever file handles first-launch setup), add:
   ```swift
   import ServiceManagement
   let service = SMAppService.agent(plistName: "com.spatialduality.manifold.runtime.plist")
   try service.register()
   ```
   Add `unregister()` call for Quit Manifold (not close window).

**Constraints:**
- LaunchAgent binary is headless — no AppKit, no SwiftUI imports.
- `NSXPCListener(machServiceName:)` only works with launchd plist registration.
- Fail-fast: if `ManifoldRuntime()` throws, `exit(1)`.
- No `Program`/`ProgramArguments` in plist — `SMAppService` fills those from the bundle.

**Done when:** `swift build` produces ManifoldAgent binary. Plist exists. App has register/unregister calls. `swift test` passes.

---COPY ABOVE---

---

## Phase 7: Make MCP + CLI Thin XPC Clients

---COPY BELOW---

Read `codex/AGENTS.md` and `design/RUNTIME-MIGRATION.md` (Phase 7 section) before starting.

**Goal:** Rewrite `manifold-mcp` and `manifold-cli` to forward all operations through XPC to the ManifoldAgent. Neither opens SQLite or creates stores.

**Steps:**

1. **Split ToolHandlers.swift:** Extract tool definitions (names, descriptions, input schemas) into `Sources/ManifoldMCP/ToolDefinitions.swift` — a static method returning definitions without any bridge/runtime dependency. The execution logic stays in `ManifoldXPCService.callTool()` from Phase 5.

2. **Rewrite ManifoldMCPServer.swift:** Delete all `ManifoldRuntime` / store creation. The new flow:
   - Create `ManifoldXPCClient()`
   - Call `xpc.connectAgent(agent:clientName:clientVersion:)` to get a connectionID
   - Create `MCPServer` (JSON-RPC stdio), register tool definitions from step 1
   - For each tool call: `xpc.callTool(connectionID:toolName:arguments:)` → return result
   - On exit: `xpc.disconnectAgent(connectionID:)`
   - The `--install` and `--version` flags stay unchanged (local operations, no XPC needed)

3. **Rewrite ManifoldCLI:** All commands go through `xpc.command(name:payload:)`:
   - `status` → `command("getStatus")`
   - `pause` → `command("pauseAgent", ["agent": name])`
   - `resume` → `command("resumeAgent", ["agent": name])`
   - `activity` → `command("recentActivity", ["limit": n])`

4. **Update Package.swift dependencies:**
   - ManifoldMCP: `["ManifoldXPC"]` (plus ManifoldKit only if ToolDefinitions needs Kit types for schemas)
   - ManifoldCLI: `["ManifoldXPC"]`
   - ManifoldMCP should NOT depend on ManifoldRuntime.

5. **Delete stale files:** Verify `ManifoldBridge.swift` and `AgentRuntimeContext.swift` do NOT exist in `Sources/ManifoldMCP/` (they were moved in Phase 1). Delete if still present.

6. **Update test imports:** If any tests import ManifoldBridge from ManifoldMCP, change to import ManifoldRuntime.

**Constraints:**
- `manifold-mcp` must NOT import ManifoldRuntime. Only ManifoldXPC.
- `manifold-mcp` must NOT open SQLite or create any stores.
- `MCPProtocol.swift` stays in ManifoldMCP — it's stdio plumbing.
- `ConfigWriter` stays in ManifoldKit — it's a local file op.
- Tool behavior must be identical from the agent's perspective.

**Done when:** `manifold-mcp` has zero store/bridge/runtime imports. `manifold-cli` has zero store imports. Both forward through XPC. `swift build` passes. `swift test` passes.

---COPY ABOVE---

---

## Phase 8: Make the App an XPC Client

---COPY BELOW---

Read `codex/AGENTS.md` and `design/RUNTIME-MIGRATION.md` (Phase 8 section) before starting. This is the final phase.

**Goal:** Remove in-process `ManifoldRuntime` from the SwiftUI app. Replace with `ManifoldXPCClient`. The app becomes a pure UI client — it displays data and sends commands but never touches the database.

**Steps:**

1. **Rewrite ManifoldStore.swift:** Replace `let runtime: ManifoldRuntime` with `let xpc = ManifoldXPCClient()`. Delete `import ManifoldRuntime`. Add `import ManifoldXPC`. Add `var isRuntimeConnected: Bool` state. In init: call `registerAgent()` (SMAppService), then `Task { await refreshAll() }`. `refreshAll()` calls `xpc.command(name: "getStatus")`, sets `isRuntimeConnected`.

2. **Rewrite PolicyModel.swift:** All mutations go through XPC:
   - `pauseAgent(agent)` → `xpc.command(name: "pauseAgent", payload: ["agent": agent])`
   - `resumeAgent(agent)` → `xpc.command(name: "resumeAgent", payload: ["agent": agent])`
   - `addSource(...)` → `xpc.command(name: "addSource", payload: [...])`
   - Store properties replaced by cached state refreshed from XPC queries.

3. **Rewrite SessionModel.swift:** Session lifecycle through XPC:
   - `startSession()` → `xpc.command(name: "startTrackedRun", payload: [...])`
   - `endSession()` → `xpc.command(name: "finishTrackedRun", payload: [...])`
   - `computePreview()` → `xpc.command(name: "promotionPreview", payload: [...])`
   - `completeWorkBlock()` → `xpc.command(name: "applyTrackedRun", payload: [...])`

4. **Rewrite HistoryModel, StorageModel, EmailAccountModel:** Same pattern — all queries through XPC.

5. **Add connection monitoring:** Poll `xpc.command("ping")` every 5 seconds. When disconnected, set `isRuntimeConnected = false` and show disconnected state in UI.

6. **Delete DistributedNotificationCenter usage:** Search entire codebase for `DistributedNotificationCenter`, `ManifoldNotification`, `.agentConnected`, `.agentDisconnected`, `.accessDenied`, `.fileAccessed`, `.dataChanged`. Delete all posts and observers. Gut or delete `Sources/ManifoldKit/ManifoldNotifications.swift`.

7. **Quit semantics:** In app termination handler: if user explicitly quit (not just closed window), call `SMAppService.agent(plistName:).unregister()`. Close window = hide UI only, agent keeps running.

8. **Update Xcode project dependencies:** App imports `ManifoldXPC` and `ManifoldKit` (for types). NOT ManifoldRuntime.

**Constraints:**
- App must NOT import ManifoldRuntime. Must NOT open SQLite.
- Close window ≠ quit. Agent keeps running when window closes.
- All XPC calls can fail. Every model method handles errors gracefully.
- ManifoldKit types (AgentAccessPolicy, WorkBlockRecord, etc.) still usable in UI.

**Done when:** App uses ManifoldXPCClient, not ManifoldRuntime. Zero DatabaseConnection in app. Zero DistributedNotificationCenter in codebase. Kill app → agent still runs → MCP works. Kill agent → app shows disconnected → launchd restarts → app reconnects. `swift build` passes. `swift test` passes. Full verification checklist from `design/RUNTIME-MIGRATION.md` passes.

---COPY ABOVE---
