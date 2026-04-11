# Manifold Runtime Architecture Plan

**Date:** April 11, 2026
**Status:** Proposed
**Scope:** Restructure Manifold from "two processes sharing a database" to "one runtime with thin clients"

---

## The Problem

Today Manifold has a structural defect at its foundation. Two independent processes — the SwiftUI app and the `manifold-mcp` server — independently instantiate all stores against the same SQLite file and independently make access decisions. They coordinate through `DistributedNotificationCenter`, which is fire-and-forget with no ordering guarantees, no request/response capability, and no way for the app to intercept or deny an action in-flight.

This means:

1. **Two concurrent MCP server instances** (Claude + Cursor both connected) each have their own `ManifoldBridge` actor, their own file enumeration cache, their own access resolution state. The SQLite WAL mode prevents corruption but not logical races (e.g., both reading "no active work block" and both starting one).

2. **The app cannot deny an action in-flight.** When the MCP server makes an access decision, the app learns about it afterward via notification. The "pause" button works because both processes read the same `PolicyStore` table — but there is a window between the MCP server reading "not paused" and the app writing "paused."

3. **If the app is closed, the MCP server still runs** with full policy enforcement capability — which sounds fine until you realize the menu bar approval queue (Phase 2 spec) requires a persistent process to receive and present denied requests. No app = no queue = denials vanish.

4. **`ManifoldStore` and `ManifoldBridge` duplicate logic.** Both enumerate files, both resolve access, both manage grant lifecycle. `ManifoldStore` does it for the UI; `ManifoldBridge` does it for MCP tools. They diverge.

For a product whose entire value proposition is "you control what agents can see," having the control plane be structurally racy is not acceptable as a foundation.

---

## The Target Architecture

```
┌─────────────────────────────────────────────────┐
│                  Manifold.app                     │
│                                                   │
│  ┌─────────────────────────────────────────────┐ │
│  │           ManifoldRuntime (actor)            │ │
│  │                                              │ │
│  │  DatabaseConnection ─── All Stores           │ │
│  │  ManifoldBridge (policy, access, audit)      │ │
│  │  EmailSyncEngine                             │ │
│  │  WorkspaceLeaseManager                       │ │
│  │                                              │ │
│  │  XPC Listener (NSXPCListener, Mach service)  │ │
│  └──────────────┬───────────────────────────────┘ │
│                 │                                  │
│  ┌──────────────┴───────────────────────────────┐ │
│  │  ManifoldStore (@Observable, @MainActor)     │ │
│  │  Reads from ManifoldRuntime (in-process)     │ │
│  │  Drives SwiftUI views                        │ │
│  └──────────────────────────────────────────────┘ │
│                                                   │
│  Menu Bar ──── Main Window ──── Settings          │
└──────────────────┬──────────────────┬─────────────┘
                   │ XPC              │ XPC
        ┌──────────┴──────┐   ┌──────┴──────────┐
        │  manifold-mcp   │   │  manifold-cli    │
        │  (thin client)  │   │  (thin client)   │
        │  stdio ↔ XPC    │   │  terminal ↔ XPC  │
        └─────────────────┘   └─────────────────┘
```

**One process owns truth.** The app IS the runtime. The menu bar keeps it alive.

**Three clients ask for permission:**
- `manifold-mcp` — spawned by Claude Desktop/Codex/Cursor, translates MCP JSON-RPC to XPC calls
- `manifold-cli` — terminal commands translated to XPC calls
- The app's own SwiftUI layer — calls the runtime directly (in-process, no XPC needed)

---

## What Changes (and What Doesn't)

### Stays the same

- **ManifoldKit** — all stores, engines, types. Zero changes. This is the data layer.
- **MCPServer** (the JSON-RPC stdio handler) — stays in the MCP target. It's protocol plumbing.
- **ToolHandlers** — tool definitions and response formatting. Stays.
- **SwiftUI views** — no changes. They read from `ManifoldStore` which reads from the runtime.
- **Database schema** — unchanged. Same SQLite file, same migrations.
- **Tests** — ManifoldKitTests test stores and engines directly. They don't care about IPC.

### Moves

| What | From | To | Why |
|---|---|---|---|
| `ManifoldBridge` | `ManifoldMCP` target | `ManifoldKit` target | It's the runtime's decision engine, not MCP plumbing. The app needs it too. |
| `AgentRuntimeContext` | `ManifoldMCP` target | `ManifoldKit` target | Bridge depends on it. |
| Store initialization | Duplicated in both `ManifoldMCPServer.main()` and `ManifoldStore.initStores()` | Single initialization in `ManifoldRuntime` | One process, one init. |

### New code

| What | Where | Size estimate | Purpose |
|---|---|---|---|
| `ManifoldRuntime` | `ManifoldKit` | ~200 lines | Actor that owns all stores, bridge, and lifecycle. Single composition root. |
| `ManifoldXPCProtocol` | `ManifoldKit` | ~80 lines | `@objc protocol` defining the XPC interface. |
| `ManifoldXPCService` | `ManifoldKit` | ~250 lines | XPC listener + delegate. Wraps `ManifoldRuntime` methods as XPC-callable endpoints. |
| `ManifoldXPCClient` | `ManifoldKit` | ~200 lines | XPC connection wrapper. Used by MCP server and CLI. Handles launch-on-connect. |
| `ManifoldServiceTypes` | `ManifoldKit` | ~100 lines | `NSSecureCoding`-conformant request/response types for XPC. |

### Deleted/simplified

| What | Change |
|---|---|
| `ManifoldMCPServer.main()` | Drops all store initialization (50+ lines). Creates XPC client, creates MCPServer, wires tool calls through XPC. |
| `ManifoldCLI.main()` | Drops all store initialization. Each command calls through XPC client. |
| `ManifoldStore.initStores()` | Replaced by creating `ManifoldRuntime` and reading from it. No more optional stores. |
| `ManifoldNotifications` | Replaced by XPC callbacks for MCP→app communication. Kept for Finder extension IPC only. |
| Duplicate file enumeration | `ManifoldStore.enumerateSourceFiles()` and `ManifoldBridge.listFilesFromOriginals()` collapse into one method on the runtime. |

---

## Detailed Design

### 1. ManifoldRuntime

```swift
// In ManifoldKit

/// The single source of truth for all Manifold state.
/// Owns the database, all stores, and the bridge.
/// Lives in the app process. Thin clients connect via XPC.
public actor ManifoldRuntime {
    // Stores (all created once, never re-created)
    public let db: DatabaseConnection
    public let auditStore: AuditStore
    public let contentStore: ContentStore
    public let snapshotStore: SnapshotStore
    public let grantStore: GrantStore
    public let emailStore: EmailStore
    public let artifactIndex: ArtifactIndex
    public let policyStore: PolicyStore
    public let workBlockStore: WorkBlockStore
    public let leaseManager: WorkspaceLeaseManager
    
    // Engines
    public let emailSyncEngine: EmailSyncEngine
    
    // Per-connection bridges (one per connected agent)
    private var bridges: [String: ManifoldBridge] = [:]
    
    public init() throws {
        let storeURL = Self.storeURL
        try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
        
        db = try DatabaseConnection(url: storeURL.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        
        contentStore = try ContentStore(rootURL: storeURL, db: db)
        auditStore = try AuditStore(db: db)
        snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)
        leaseManager = try WorkspaceLeaseManager(db: db, snapshotStore: snapshotStore)
        grantStore = GrantStore(db: db)
        emailStore = EmailStore(db: db)
        artifactIndex = try ArtifactIndex(db: db)
        policyStore = PolicyStore(db: db)
        workBlockStore = WorkBlockStore(db: db)
        emailSyncEngine = EmailSyncEngine(emailStore: emailStore)
    }
    
    /// Get or create a bridge for a specific agent connection.
    public func bridge(
        for connectionID: String,
        targetApp: TargetApp,
        serverVersion: String
    ) -> ManifoldBridge {
        if let existing = bridges[connectionID] { return existing }
        let bridge = ManifoldBridge(
            db: db,
            auditStore: auditStore,
            contentStore: contentStore,
            grantStore: grantStore,
            emailStore: emailStore,
            snapshotStore: snapshotStore,
            artifactIndex: artifactIndex,
            policyStore: policyStore,
            workBlockStore: workBlockStore,
            targetApp: targetApp,
            serverName: "manifold",
            serverVersion: serverVersion
        )
        bridges[connectionID] = bridge
        return bridge
    }
    
    /// Remove a bridge when an agent disconnects.
    public func removeBridge(connectionID: String) {
        bridges.removeValue(forKey: connectionID)
    }
    
    static var storeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Manifold/store")
    }
}
```

### 2. XPC Protocol

```swift
// In ManifoldKit

/// XPC interface for thin clients (MCP server, CLI).
/// All methods use NSSecureCoding-compatible types.
@objc public protocol ManifoldXPCProtocol {
    
    // Connection lifecycle
    func connect(
        connectionID: String,
        targetApp: String,
        serverVersion: String,
        initializeParams: Data,  // JSON-encoded
        reply: @escaping (Data) -> Void  // JSON-encoded status
    )
    
    func disconnect(connectionID: String)
    
    // Tool dispatch — single entry point, keeps XPC surface minimal
    func callTool(
        connectionID: String,
        toolName: String,
        arguments: Data,  // JSON-encoded [String: Any]
        reply: @escaping (Data, Bool) -> Void  // (JSON result, isError)
    )
    
    // CLI commands
    func status(reply: @escaping (Data) -> Void)
    func recentLog(limit: Int, reply: @escaping (Data) -> Void)
    func allSources(reply: @escaping (Data) -> Void)
}
```

Why a single `callTool` method instead of one XPC method per bridge method: the MCP server already dispatches by tool name in `ToolHandlers.handle()`. Replicating 18 XPC methods would be a maintenance nightmare. Instead, the XPC layer is a thin JSON-in/JSON-out tunnel. The bridge does the real work.

### 3. XPC Service (app side)

```swift
// In ManifoldKit or the app target

/// Listens for XPC connections and dispatches to ManifoldRuntime.
public class ManifoldXPCService: NSObject, NSXPCListenerDelegate, ManifoldXPCProtocol {
    private let runtime: ManifoldRuntime
    private let listener: NSXPCListener
    
    public init(runtime: ManifoldRuntime) {
        self.runtime = runtime
        self.listener = NSXPCListener(machServiceName: "com.spatialduality.manifold.runtime")
        super.init()
        listener.delegate = self
    }
    
    public func start() {
        listener.resume()
    }
    
    // NSXPCListenerDelegate
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ManifoldXPCProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
    
    // ManifoldXPCProtocol implementation
    public func callTool(connectionID: String, toolName: String, arguments: Data, reply: @escaping (Data, Bool) -> Void) {
        Task {
            let args = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] ?? [:]
            let bridge = await runtime.bridge(for: connectionID, targetApp: .cowork, serverVersion: "0.4.0")
            let result = await ToolHandlers.handle(name: toolName, arguments: args, bridge: bridge)
            let isError = result["isError"] as? Bool ?? false
            let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
            reply(data, isError)
        }
    }
    
    // ... other protocol methods follow the same pattern
}
```

### 4. XPC Client (MCP server and CLI side)

```swift
// In ManifoldKit

/// Connects to the Manifold app's XPC service.
/// If the app isn't running, launches it first.
public class ManifoldXPCClient {
    private var connection: NSXPCConnection?
    
    public init() {}
    
    public func connect() throws -> ManifoldXPCProtocol {
        // Launch the app if not running
        if !isManifoldAppRunning() {
            launchManifoldApp()
            // Brief wait for XPC service to register
            Thread.sleep(forTimeInterval: 1.0)
        }
        
        let conn = NSXPCConnection(machServiceName: "com.spatialduality.manifold.runtime")
        conn.remoteObjectInterface = NSXPCInterface(with: ManifoldXPCProtocol.self)
        conn.resume()
        self.connection = conn
        
        guard let proxy = conn.remoteObjectProxy as? ManifoldXPCProtocol else {
            throw ManifoldError.workspaceError("Cannot connect to Manifold runtime")
        }
        return proxy
    }
    
    private func isManifoldAppRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.spatialduality.manifold") .isEmpty == false
    }
    
    private func launchManifoldApp() {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false  // Don't steal focus — just start the runtime
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spatialduality.manifold") {
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }
}
```

### 5. Slim MCP Server

`ManifoldMCPServer.swift` becomes:

```swift
@main
struct ManifoldMCPServer {
    static func main() async throws {
        let version = "0.4.0"
        let targetApp = parsedTargetApp(from: CommandLine.arguments)
        
        // Handle --version and --install (unchanged)
        // ...
        
        // Connect to runtime via XPC (instead of creating stores)
        let client = ManifoldXPCClient()
        let proxy = try client.connect()
        
        let connectionID = "mcp-\(UUID().uuidString.prefix(12))"
        
        // Create MCP server (unchanged — it's just stdio JSON-RPC)
        let server = MCPServer(name: "manifold", version: version)
        
        await server.registerInitializeHandler { params in
            let data = try? JSONSerialization.data(withJSONObject: params.value)
            proxy.connect(
                connectionID: connectionID,
                targetApp: targetApp.rawValue,
                serverVersion: version,
                initializeParams: data ?? Data()
            ) { _ in }
        }
        
        await server.registerTools(ToolHandlers.allTools()) { name, arguments in
            let argData = try? JSONSerialization.data(withJSONObject: arguments.value)
            return await withCheckedContinuation { continuation in
                proxy.callTool(
                    connectionID: connectionID,
                    toolName: name,
                    arguments: argData ?? Data()
                ) { resultData, _ in
                    let result = (try? JSONSerialization.jsonObject(with: resultData)) as? [String: Any] ?? [:]
                    continuation.resume(returning: JSONDict(result))
                }
            }
        }
        
        // Resources (unchanged pattern, through XPC)
        // ...
        
        do {
            try await server.start()
        } catch {
            proxy.disconnect(connectionID: connectionID)
            throw error
        }
        proxy.disconnect(connectionID: connectionID)
    }
}
```

### 6. ManifoldStore Simplification

`ManifoldStore` stops creating stores. It holds a reference to `ManifoldRuntime` (in-process, no XPC needed):

```swift
@Observable
@MainActor
class ManifoldStore {
    // All current published properties stay
    
    private let runtime: ManifoldRuntime  // non-optional, created once
    
    init() {
        // Runtime created synchronously (throws on DB failure — that's a fatal error, not recoverable)
        runtime = try! ManifoldRuntime()
        
        // Sub-models configured immediately with real stores (no more optional injection)
        session.configure(
            grantStore: runtime.grantStore,
            snapshotStore: runtime.snapshotStore,
            // ...
        )
        policy.configure(
            policyStore: runtime.policyStore,
            workBlockStore: runtime.workBlockStore,
            grantStore: runtime.grantStore
        )
        // ...
        
        // Start XPC service for external clients
        let xpcService = ManifoldXPCService(runtime: runtime)
        xpcService.start()
        
        setupNotificationObservers()
        // ...
    }
}
```

Key change: **no more optional stores, no more async `initStores()`, no more `reinjectStores()`**. The runtime is created once, synchronously. If it fails, the app can't function — so fail loudly instead of running in a degraded state with `nil` stores.

---

## Phased Implementation

### Phase 1: Move ManifoldBridge to ManifoldKit

**Goal:** Make the bridge available to both the app and MCP targets without code duplication.

**Changes:**
- Move `ManifoldBridge.swift` from `Sources/ManifoldMCP/` to `Sources/ManifoldKit/`
- Move `AgentRuntimeContext.swift` from `Sources/ManifoldMCP/` to `Sources/ManifoldKit/`
- Update imports in `ToolHandlers.swift` (should be minimal — it already imports `ManifoldKit`)
- Verify all tests still pass

**Risk:** Low. This is a file move with import updates. No logic changes.

**Verification:** `swift test` passes. MCP server builds. App builds.

### Phase 2: Create ManifoldRuntime

**Goal:** Single composition root that owns all stores and bridges.

**Changes:**
- Create `Sources/ManifoldKit/ManifoldRuntime.swift` (~200 lines)
- Runtime creates all stores in `init()` (extract from both `ManifoldMCPServer.main()` and `ManifoldStore.initStores()`)
- Runtime manages per-connection bridges (add/remove)
- Update `ManifoldStore` to create `ManifoldRuntime` instead of creating stores directly
- Delete `ManifoldStore.initStores()` and `ManifoldStore.reinjectStores()`
- Sub-models receive stores from `runtime` directly
- All store properties on `ManifoldStore` become non-optional (read from runtime)

**Risk:** Medium. This changes the app's initialization flow. The async-optional pattern becomes synchronous-required. Need to handle the "database won't open" case as a fatal error with user-facing dialog, not a silent `nil`.

**Verification:** App launches. All sub-models get real store instances. UI shows data. MCP server still works (still using its own stores temporarily — that changes in Phase 4).

### Phase 3: Define and Implement XPC Interface

**Goal:** The app exposes an XPC Mach service that external processes can connect to.

**Changes:**
- Create `Sources/ManifoldKit/ManifoldXPCProtocol.swift` (~80 lines) — the `@objc protocol`
- Create `Sources/ManifoldKit/ManifoldXPCService.swift` (~250 lines) — listener, delegate, dispatch to runtime
- Create `Sources/ManifoldKit/ManifoldXPCClient.swift` (~200 lines) — connection wrapper with app-launch fallback
- Create `Sources/ManifoldKit/ManifoldServiceTypes.swift` (~100 lines) — NSSecureCoding request/response wrappers
- Add XPC Mach service entry to the app's `Info.plist` (or launchd plist)
- Start the XPC listener in `ManifoldStore.init()` after runtime creation

**Risk:** Medium. XPC Mach services require the service name to be registered with launchd (via a plist in `~/Library/LaunchAgents/` or embedded in the app). This needs testing on a real Mac — sandbox and notarization interact with Mach services.

**Verification:** Build a test CLI that connects via XPC and calls `status`. Verify it works when the app is running. Verify the app launches when the CLI connects and the app isn't running.

### Phase 4: Slim Down MCP Server and CLI

**Goal:** `manifold-mcp` and `manifold-cli` become thin XPC clients.

**Changes:**
- Rewrite `ManifoldMCPServer.main()`: remove all store creation, connect via `ManifoldXPCClient`, wire tool calls through XPC `callTool` method
- Rewrite `ManifoldCLI.main()`: remove all store creation, connect via `ManifoldXPCClient`, wire commands through XPC
- `ManifoldMCP` target's dependency changes: still depends on `ManifoldKit` (for tool definitions and types) but no longer creates stores or bridge
- Delete duplicate `manifoldStoreURL()` from both MCP and CLI (it's on `ManifoldRuntime` now)

**Risk:** Medium. The MCP server's behavior must be identical from the agent's perspective. Every tool call must return the same shape. The XPC serialization round-trip must be transparent.

**Verification:**
- `manifold-mcp --version` still works (no XPC needed for this)
- `manifold-mcp --install` still works (no XPC needed for this either)
- Connect Claude Desktop to manifold-mcp → call `get_status` → get valid response
- Call `list_files`, `read_file`, `write_file` — verify identical behavior
- Connect two MCP clients simultaneously → verify they share state (same work block, same audit log)
- Kill the app → verify MCP server either re-launches it or fails gracefully

### Phase 5: Replace DistributedNotificationCenter with XPC Callbacks

**Goal:** The MCP server ↔ app communication becomes bidirectional and reliable.

**Changes:**
- Remove `ManifoldNotification.post()` calls from `ManifoldBridge` and `ManifoldMCPServer`
- Instead, when the runtime processes a tool call, it directly updates observable state (since it's in the app process now)
- For real-time UI updates: the runtime can post to `NotificationCenter.default` (in-process, not distributed) after each tool call
- Keep `DistributedNotificationCenter` only for Finder Sync Extension communication (Phase 3 of menu bar spec)
- Update `ManifoldStore.setupNotificationObservers()` to observe in-process notifications instead of distributed ones

**Risk:** Low. The new path is simpler — no cross-process notification delivery to worry about.

**Verification:** Connect an agent → perform file operations → verify the app UI updates in real-time. Verify the menu bar shows correct connection status without distributed notifications.

### Phase 6: Cleanup

**Goal:** Remove dead code and verify the architecture is clean.

**Changes:**
- Delete the store-creation code from `ManifoldMCPServer` (already replaced in Phase 4)
- Delete the store-creation code from `ManifoldCLI` (already replaced in Phase 4)
- Delete `ManifoldStore.initStores()` and `reinjectStores()` (already replaced in Phase 2)
- Remove unused `ManifoldNotification` cases (keep only what Finder extension needs)
- Update `README.md` architecture section to reflect single-runtime model
- Update `ConfigWriter` if the MCP binary path or launch semantics changed
- Run full test suite, verify everything passes

**Verification:** `swift test` passes. `xcodebuild test` passes. App launches. MCP server connects. CLI works. No orphaned code.

---

## XPC Considerations for macOS

### Mach Service Registration

For a non-sandboxed app (which Manifold likely is, given it needs file system access), the Mach service name must be registered. Two options:

**Option A: Login Item with Mach Service** — The app registers as a login item and declares the Mach service in its `Info.plist` under `MachServices`. This is the modern approach for menu bar apps.

**Option B: LaunchAgent Plist** — Install a `~/Library/LaunchAgents/com.spatialduality.manifold.runtime.plist` that registers the Mach service name. The app creates this plist on first launch. `manifold-cli install` can also create it.

Option A is cleaner. The app already should be a login item (menu bar app).

### Sandboxing

If the app is sandboxed (App Store distribution), XPC Mach services work differently — you'd use an XPC Service bundle inside the app instead of a Mach service. For now, assume non-sandboxed (direct distribution via DMG/Homebrew), which is what the launch plan describes.

### Error Handling

If the app crashes or is force-quit while an MCP server is connected:
- The XPC connection will invalidate
- The MCP server should detect this (connection invalidation handler) and either:
  - Re-launch the app and reconnect (preferred)
  - Fail the current tool call with "Manifold runtime unavailable — restart the app"

This is strictly better than the current behavior where the MCP server silently continues with stale state.

### Performance

XPC overhead is negligible for this use case. MCP tool calls happen at human-interaction frequency (seconds between calls, not milliseconds). The XPC round-trip adds ~1ms. The bottleneck is always file I/O and SQLite queries, not IPC.

---

## What This Enables (That the Current Architecture Cannot)

1. **Approval queue.** The runtime can hold a denied access request and wait for the user to approve it in the menu bar. Currently impossible — the MCP server makes the decision alone and returns immediately.

2. **Concurrent agents with shared state.** Two MCP servers connecting simultaneously get bridges from the same runtime. One work block, one audit log, one policy engine. No races.

3. **Write escalation.** When an agent tries to write during standing access, the runtime can escalate to a tracked run — prompting the user via the menu bar — and hold the write until approved. Currently, the MCP server just returns an error.

4. **Real-time UI.** Every tool call goes through the app process. The UI can update instantly — no distributed notification delay, no dropped notifications, no stale state.

5. **Reliable "what is the agent doing right now?"** The runtime knows every active bridge, every in-flight tool call, every connected agent. The menu bar can show live activity, not reconstructed-from-audit-log activity.

6. **Safe app termination.** Before quitting, the runtime can notify all connected bridges that the runtime is going down. The MCP servers can fail gracefully. Currently, killing the app leaves MCP servers orphaned with no notification.

---

## Migration Verification Checklist

After all phases are complete, verify:

- [ ] App launches and shows correct data (sources, policies, history)
- [ ] Menu bar shows correct agent connection status
- [ ] `manifold-mcp` connects to runtime via XPC when spawned by Claude Desktop
- [ ] `manifold-mcp` auto-launches the app if it's not running
- [ ] `manifold-cli status` returns correct data via XPC
- [ ] `manifold-cli install` still writes correct config files
- [ ] Two simultaneous MCP connections share the same runtime state
- [ ] Pausing an agent in the app immediately affects the MCP server
- [ ] File reads, writes, and searches return identical results to pre-migration
- [ ] Email listing and reading returns identical results
- [ ] Work block start/pause/end works correctly across app UI and MCP
- [ ] Audit log records all actions from all clients
- [ ] Killing the app while MCP is connected → MCP fails gracefully
- [ ] Re-launching the app after kill → MCP reconnects
- [ ] `swift test` passes
- [ ] `xcodebuild test` passes
- [ ] No stale `DistributedNotificationCenter` usage except for Finder extension
