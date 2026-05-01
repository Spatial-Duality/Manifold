# Manifold Runtime Migration — Concrete Engineering Plan

**Date:** April 11, 2026 (revised)
**Decision:** App-owned bundled LaunchAgent runtime + XPC clients. One app bundle, one install, one judge. The app is the face. The runtime is the judge.

---

## The Invariant

One runtime is the judge. Every other executable is a client. One source of truth means one judge, not one PID.

The problem today is that `manifold-mcp` acts as a second authority. Both `ManifoldStore.swift` (app) and `ManifoldMCPServer.swift` (MCP) construct their own store graphs and independently make access decisions against the same SQLite file. That is the architectural lie. The fix is: delete the second composition root.

---

## Why This Shape, Not Others

**Not a system LaunchDaemon.** Apple describes daemons as system-context processes unaware of logged-in users. Manifold's state is user-scoped: security-scoped bookmarks, email visibility, approvals, agent sessions. A per-user LaunchAgent fits.

**Not the app hosting a Mach XPC service.** `NSXPCListener(machServiceName:)` is documented for LaunchAgents/LaunchDaemons whose Mach service is advertised in a launchd plist. A GUI app that happens to be running does not get a launchd-registered Mach service name. Anonymous listeners require an existing connection to pass endpoints. The app-as-Mach-service topology is not the documented path.

**A bundled per-user LaunchAgent.** Apple's Ventura guidance says helper executables live inside the app bundle. `SMAppService` registers them. The LaunchAgent declares `MachServices` in its plist, so `NSXPCConnection(machServiceName:)` works correctly — launchd knows about the service and can launch the agent on-demand when a client connects. This is the standard documented topology.

---

## Final Target Architecture

```
Manifold.app/
  Contents/
    MacOS/
      Manifold                         ← SwiftUI app (menu bar + main window)
    Library/
      LaunchAgents/
        com.spatialduality.manifold.runtime.plist
        ManifoldRuntime                ← Persistent runtime (LaunchAgent, owns all stores)
    Resources/
      manifold-mcp                     ← Thin MCP server (stdio ↔ XPC)
```

```
┌──────────────────────────────────────┐
│        ManifoldRuntime               │
│   (bundled LaunchAgent, persistent)  │
│   launchd manages lifecycle          │
│                                      │
│   ManifoldRuntime (actor)            │
│     ├── DatabaseConnection           │
│     ├── PolicyStore                  │
│     ├── GrantStore                   │
│     ├── WorkBlockStore               │
│     ├── ContentStore                 │
│     ├── SnapshotStore                │
│     ├── AuditStore                   │
│     ├── EmailStore                   │
│     ├── ArtifactIndex                │
│     ├── EmailSyncEngine              │
│     └── WorkspaceLeaseManager        │
│                                      │
│   XPC Listener (Mach service)        │
│     com.spatialduality.manifold.runtime
│                                      │
│   ApprovalQueue                      │
│   ExposureStore                      │
└────────────┬─────────────────────────┘
             │ XPC (launchd-registered Mach service)
      ┌──────┼────────────┬──────────────┐
      │      │            │              │
  ┌───┴──┐ ┌─┴─────┐ ┌───┴───┐ ┌───────┴──────┐
  │ App  │ │ mcp   │ │ cli   │ │ Future:      │
  │ UI   │ │       │ │       │ │ Finder ext   │
  └──────┘ └───────┘ └───────┘ │ Shortcuts    │
                               └──────────────┘
```

All clients use `NSXPCConnection(machServiceName: "com.spatialduality.manifold.runtime")`. launchd starts the runtime on-demand if it's not already running. launchd restarts it if it crashes. The app is just another client.

---

## Control Semantics

These must be explicit and honest:

- **Close window** → hides UI. Runtime keeps running. Agents keep working.
- **Pause all access** → runtime denies new requests. Agents get "access paused."
- **Quit Manifold** → stops the LaunchAgent via `SMAppService`. No runtime = no access = fail-closed.
- **Login** → launchd starts the runtime. App appears in menu bar if configured as login item.

---

## Package / Target Layout

### Current
```
ManifoldKit      (library)    → stores, engines, types
ManifoldMCP      (executable) → MCPServer + ManifoldBridge + ToolHandlers
ManifoldCLI      (executable) → CLI commands + own store init
ManifoldApp      (Xcode)      → SwiftUI app + ManifoldStore (own store init)
```

### Target
```
ManifoldKit        (library)    → stores, engines, types (unchanged)
ManifoldRuntime    (library)    → runtime actor, service protocol, bridge, approval queue
ManifoldXPC        (library)    → XPC protocol, client, service adapter, coding types
ManifoldAgent      (executable) → LaunchAgent binary: runtime + XPC listener
ManifoldMCP        (executable) → thin: MCPServer + XPC client (no stores)
ManifoldCLI        (executable) → thin: XPC client (no stores)
ManifoldApp        (Xcode)      → SwiftUI app + XPC client (no stores)
```

**Dependencies:**
```
ManifoldKit        ← nothing
ManifoldRuntime    ← ManifoldKit
ManifoldXPC        ← ManifoldRuntime
ManifoldAgent      ← ManifoldRuntime + ManifoldXPC
ManifoldMCP        ← ManifoldXPC (+ ManifoldKit for tool definitions only)
ManifoldCLI        ← ManifoldXPC
ManifoldApp        ← ManifoldXPC
```

---

## The Service Protocol

Product vocabulary. Not store internals.

```swift
// Sources/ManifoldRuntime/ManifoldServiceAPI.swift

public protocol ManifoldServiceAPI: Sendable {

    // MARK: - Connection Lifecycle

    func connect(
        agent: String,
        clientName: String?,
        clientVersion: String?,
        initializeParams: [String: Any]
    ) async throws -> String  // connectionID

    func disconnect(connectionID: String) async

    // MARK: - Status & Folders

    func getStatus(connectionID: String) async throws -> RuntimeStatus
    func listTrustedFolders(agent: String) async throws -> [TrustedFolder]

    // MARK: - File Access (always-on reads)

    func listFiles(connectionID: String) async throws -> [FileEntry]
    func readFile(connectionID: String, path: String) async throws -> FileContent
    func readRange(connectionID: String, path: String, startLine: Int, endLine: Int) async throws -> FileContent
    func searchFiles(connectionID: String, query: String) async throws -> [SearchHit]
    func searchStructured(connectionID: String, query: String, limit: Int) async throws -> String
    func fileInfo(connectionID: String, path: String) async throws -> FileMetadata
    func diffFile(connectionID: String, path: String) async throws -> String
    func listArchive(connectionID: String, path: String) async throws -> [String]
    func extractFile(connectionID: String, archivePath: String, filePath: String) async throws -> String

    // MARK: - Writes (escalate from always-on to tracked run)

    func writeFile(connectionID: String, path: String, content: String) async throws -> WriteResult

    // MARK: - Tracked Runs

    func startTrackedRun(connectionID: String, folderIDs: [String], fileScopes: [FileScope], emailIDs: [String]) async throws -> TrackedRun
    func pauseTrackedRun(connectionID: String) async throws
    func resumeTrackedRun(connectionID: String) async throws
    func finishTrackedRun(connectionID: String) async throws -> PromotionPreview
    func applyTrackedRun(connectionID: String) async throws -> PromotionResult
    func discardTrackedRun(connectionID: String) async throws
    func listChanges(connectionID: String) async throws -> [ChangeEntry]

    // MARK: - Email

    func listEmails(connectionID: String) async throws -> [EmailEntry]
    func readEmail(connectionID: String, id: String) async throws -> EmailContent
    func requestEmailReveal(connectionID: String, emailID: String) async throws -> RevealResult

    // MARK: - Sessions

    func listSessions(connectionID: String, limit: Int) async throws -> [SessionEntry]
    func getSession(connectionID: String, grantID: String) async throws -> SessionDetail
    func saveSessionNote(connectionID: String, note: String, noteType: String) async throws -> String

    // MARK: - Policy Control (UI + CLI, not agents)

    func pauseAgent(_ agent: String) async throws
    func resumeAgent(_ agent: String) async throws
    func updateAlwaysOnAccess(agent: String, addFolders: [String], removeFolders: [String],
                              addEmailDomains: [String], removeEmailDomains: [String],
                              sensitivity: String?) async throws

    // MARK: - Approvals

    func listApprovalRequests() async throws -> [ApprovalRequest]
    func approveRequest(id: String) async throws
    func denyRequest(id: String) async throws

    // MARK: - Provenance

    func explainDecision(connectionID: String, path: String, action: String) async throws -> AccessExplanation
    func exposureLog(connectionID: String, limit: Int) async throws -> [ExposureEntry]
    func recentActivity(limit: Int) async throws -> [AuditEntry]
}
```

---

## XPC Protocol

Minimal. JSON tunnel. Three methods.

```swift
// Sources/ManifoldXPC/ManifoldXPCProtocol.swift

@objc public protocol ManifoldXPCProtocol {

    /// Agent tool dispatch. connectionID scopes the bridge.
    func callTool(
        connectionID: String,
        toolName: String,
        arguments: Data,    // JSON
        reply: @escaping (Data, Bool) -> Void  // (result JSON, isError)
    )

    /// UI/CLI commands (policy changes, approvals, status queries).
    func command(
        name: String,
        payload: Data,      // JSON
        reply: @escaping (Data, NSError?) -> Void
    )

    /// Connection lifecycle.
    func connect(
        agent: String,
        clientName: String,
        clientVersion: String,
        initializeParams: Data,
        reply: @escaping (String?, NSError?) -> Void  // connectionID
    )

    func disconnect(connectionID: String)
}
```

`callTool` handles everything MCP agents need. `command` handles everything the UI and CLI need (`pauseAgent`, `approveRequest`, `getExposureLog`, etc.). This keeps the XPC surface to 4 methods regardless of how many features exist behind the protocol.

---

## LaunchAgent Plist

```xml
<!-- Contents/Library/LaunchAgents/com.spatialduality.manifold.runtime.plist -->
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

`MachServices` tells launchd to register the Mach service name. `KeepAlive.SuccessfulExit = false` means launchd restarts it if it crashes (but not if it exits cleanly via Quit). `ProcessType = Interactive` gives it reasonable scheduling priority.

Registered via `SMAppService.agent(plistName:)` from the app.

---

## Two-Cut Migration

### Cut 1: Fix the Trust Model

Move all policy and data mutations behind a `RuntimeProtocol`. Make `manifold-mcp` a client. The runtime still lives in-process (in the app or a shared library) — the transport doesn't matter yet.

**Phase 1: Extract ManifoldRuntime**

New files:
- `Sources/ManifoldRuntime/ManifoldRuntime.swift` — single composition root (~250 lines)
- `Sources/ManifoldRuntime/ManifoldServiceAPI.swift` — protocol (~150 lines)
- `Sources/ManifoldRuntime/RuntimeTypes.swift` — result types (~200 lines)

Move:
- `ManifoldBridge.swift` → `Sources/ManifoldRuntime/`
- `AgentRuntimeContext.swift` → `Sources/ManifoldRuntime/`

Modify:
- `Package.swift` — add ManifoldRuntime target

The `ManifoldRuntime` actor:
```swift
public actor ManifoldRuntime {
    public let db: DatabaseConnection
    public let contentStore: ContentStore
    public let auditStore: AuditStore
    public let snapshotStore: SnapshotStore
    public let grantStore: GrantStore
    public let emailStore: EmailStore
    public let artifactIndex: ArtifactIndex
    public let policyStore: PolicyStore
    public let workBlockStore: WorkBlockStore
    public let leaseManager: WorkspaceLeaseManager
    public let emailSyncEngine: EmailSyncEngine

    private var bridges: [String: ManifoldBridge] = [:]

    public init(storeURL: URL? = nil) throws {
        let url = storeURL ?? Self.defaultStoreURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        db = try DatabaseConnection(url: url.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()
        contentStore = try ContentStore(rootURL: url, db: db)
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

    public func bridge(for connectionID: String, targetApp: TargetApp, version: String) -> ManifoldBridge {
        if let existing = bridges[connectionID] { return existing }
        let b = ManifoldBridge(
            db: db, auditStore: auditStore, contentStore: contentStore,
            grantStore: grantStore, emailStore: emailStore,
            snapshotStore: snapshotStore, artifactIndex: artifactIndex,
            policyStore: policyStore, workBlockStore: workBlockStore,
            targetApp: targetApp, serverName: "manifold", serverVersion: version
        )
        bridges[connectionID] = b
        return b
    }

    public func removeBridge(_ connectionID: String) { bridges.removeValue(forKey: connectionID) }
    public var activeBridgeCount: Int { bridges.count }

    public static var defaultStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Manifold/store")
    }
}
```

Verify: `swift build` passes. Both app and MCP can import ManifoldRuntime. All tests pass.

**Phase 2: Delete the Second Composition Root**

Modify `ManifoldStore.swift`:
- Delete `initStores()` (lines 122-189)
- Delete `reinjectStores()` (lines 192-221)
- Delete all optional store properties (`auditStore?`, `snapshotStore?`, etc.)
- Create `ManifoldRuntime` in init (non-optional, fail-fast)
- Configure sub-models with `runtime.grantStore`, `runtime.policyStore`, etc. directly

Modify `PolicyModel.swift`, `SessionModel.swift`, `HistoryModel.swift`, `StorageModel.swift`, `EmailAccountModel.swift`:
- All store references become non-optional
- Remove all `guard let store = ... else { return }` guards

Modify `ManifoldMCPServer.swift`:
- Delete all store creation (lines 25-60)
- Import ManifoldRuntime, create shared runtime, get bridge from it
- For now: runtime lives in-process in the MCP server as a temporary state

Verify: App launches with non-optional stores. MCP server uses ManifoldRuntime. Same SQLite file, but now through one composition root per process (next phase eliminates the second one).

**Phase 3: Enforce the Hard Rule**

Always-on access is read-only. Writes escalate.

Modify `ManifoldBridge.swift` — `writeFile` method:
```swift
case .standing:
    return .escalationRequired(
        message: "Always-on access is read-only. Start a tracked run to edit files."
    )
```

New: `Sources/ManifoldRuntime/ApprovalQueue.swift` (~150 lines)
New migration: `approval_requests` table

Modify `ToolHandlers.swift` — handle `WriteResult` enum:
```swift
case .escalationRequired(_, let msg): return textResult(msg)
case .written(_, let msg): return textResult(msg)
```

Verify: Agent in standing access calls `write_file` → gets escalation message. Agent in tracked run calls `write_file` → writes normally. All existing write tests pass (they use grant context).

**Phase 4: Add AccessDecision + ExposureRecord**

New: `Sources/ManifoldKit/AccessDecision.swift` (~80 lines)
New: `Sources/ManifoldKit/ExposureRecord.swift` (~60 lines)
New: `Sources/ManifoldKit/ExposureStore.swift` (~120 lines)
New migration: `access_decisions` and `exposure_records` tables

Modify `ManifoldBridge.swift`:
- Every access-checking method records an `AccessDecision`
- Every content-returning method records an `ExposureRecord` with byte count and content hash
- `searchFiles` records exposure for each snippet (not just the file path)
- `diffFile` records exposure for the diff content
- `readEmail` records exposure for email body bytes

Verify: Read a file → ExposureRecord created. Search files → snippet exposures recorded. Query `explainDecision` → human-readable reason returned.

**Cut 1 is complete.** The trust model is fixed. One `RuntimeProtocol`, no duplicate store graphs, standing access is read-only, every access is explained and every exposure is recorded. The MCP server still runs its own runtime in-process, but it's the same code path. The architectural lie is gone.

---

### Cut 2: Harden the Lifecycle / Transport

**Phase 5: Define XPC Layer**

New:
- `Sources/ManifoldXPC/ManifoldXPCProtocol.swift` (~50 lines)
- `Sources/ManifoldXPC/ManifoldXPCService.swift` (~200 lines)
- `Sources/ManifoldXPC/ManifoldXPCClient.swift` (~150 lines)
- `Sources/ManifoldXPC/XPCCodingTypes.swift` (~100 lines)

`ManifoldXPCService` wraps `ManifoldRuntime` and dispatches XPC calls:
```swift
public class ManifoldXPCService: NSObject, NSXPCListenerDelegate, ManifoldXPCProtocol {
    private let runtime: ManifoldRuntime

    public init(runtime: ManifoldRuntime) {
        self.runtime = runtime
        super.init()
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: ManifoldXPCProtocol.self)
        conn.exportedObject = self
        conn.invalidationHandler = { /* cleanup bridges for this connection */ }
        conn.resume()
        return true
    }

    public func callTool(connectionID: String, toolName: String, arguments: Data, reply: @escaping (Data, Bool) -> Void) {
        Task {
            let args = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] ?? [:]
            let bridge = await runtime.bridge(for: connectionID, targetApp: .cowork, version: "0.4.0")
            let result = await ToolHandlers.handle(name: toolName, arguments: args, bridge: bridge)
            let isError = result["isError"] as? Bool ?? false
            let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
            reply(data, isError)
        }
    }

    // command, connect, disconnect follow same pattern
}
```

`ManifoldXPCClient` connects via `NSXPCConnection(machServiceName:)`:
```swift
public class ManifoldXPCClient: @unchecked Sendable {
    public static let serviceName = "com.spatialduality.manifold.runtime"

    public func proxy() throws -> ManifoldXPCProtocol {
        let conn = NSXPCConnection(machServiceName: Self.serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: ManifoldXPCProtocol.self)
        conn.resume()
        guard let proxy = conn.remoteObjectProxy as? ManifoldXPCProtocol else {
            throw ManifoldError.workspaceError("Cannot connect to Manifold runtime")
        }
        return proxy
    }
}
```

Verify: Build the XPC layer. Unit test the service adapter with an in-process runtime.

**Phase 6: Build the LaunchAgent Binary**

New: `Sources/ManifoldAgent/main.swift` (~30 lines)

```swift
import Foundation
import ManifoldRuntime
import ManifoldXPC

let runtime = try ManifoldRuntime()
let service = ManifoldXPCService(runtime: runtime)
let listener = NSXPCListener(machServiceName: ManifoldXPCClient.serviceName)
listener.delegate = service
listener.resume()

// Background maintenance
Task {
    try? await runtime.snapshotStore.pruneByAge(days: 30)
    try? await runtime.contentStore.garbageCollect()
}

RunLoop.main.run()
```

New: LaunchAgent plist at `Contents/Library/LaunchAgents/com.spatialduality.manifold.runtime.plist`

Register in the app via `SMAppService.agent(plistName: "com.spatialduality.manifold.runtime.plist")`.

Verify: `ManifoldAgent` starts. launchd registers the Mach service. An XPC client connects and calls `command("status", ...)`. launchd restarts the agent if killed.

**Phase 7: Make MCP Server and CLI Thin XPC Clients**

Rewrite `ManifoldMCPServer.swift`:
```swift
@main
struct ManifoldMCPServer {
    static func main() async throws {
        let version = "0.4.0"
        let targetApp = parsedTargetApp(from: CommandLine.arguments)

        if CommandLine.arguments.contains("--version") { print("manifold-mcp \(version)"); return }
        if CommandLine.arguments.contains("--install") { /* unchanged */ return }

        let proxy = try ManifoldXPCClient().proxy()
        let connectionID = UUID().uuidString

        let server = MCPServer(name: "manifold", version: version)

        await server.registerInitializeHandler { params in
            let data = (try? JSONSerialization.data(withJSONObject: params.value)) ?? Data()
            proxy.connect(agent: targetApp.rawValue, clientName: "", clientVersion: "",
                         initializeParams: data) { _, _ in }
        }

        await server.registerTools(ToolHandlers.allTools()) { name, arguments in
            let argData = (try? JSONSerialization.data(withJSONObject: arguments.value)) ?? Data()
            return await withCheckedContinuation { cont in
                proxy.callTool(connectionID: connectionID, toolName: name, arguments: argData) { resultData, _ in
                    let result = (try? JSONSerialization.jsonObject(with: resultData)) as? [String: Any] ?? [:]
                    cont.resume(returning: JSONDict(result))
                }
            }
        }

        do { try await server.start() }
        catch { proxy.disconnect(connectionID: connectionID); throw error }
        proxy.disconnect(connectionID: connectionID)
    }
}
```

Rewrite `ManifoldCLI.swift` — all commands go through XPC `command(...)`.

Delete from ManifoldMCP target: `ManifoldBridge.swift`, `AgentRuntimeContext.swift` (already moved in Phase 1).

Verify: `manifold-mcp` no longer opens SQLite. Claude Desktop connects → tools return correct results. `manifold-cli status` works through XPC.

**Phase 8: Make the App a Client**

Modify `ManifoldStore.swift`:
- Remove `ManifoldRuntime` in-process creation (Phase 2 scaffolding)
- Replace with `ManifoldXPCClient` connection
- All mutations go through `proxy.command(...)`
- All tool-like queries go through `proxy.callTool(...)`
- Register the LaunchAgent via `SMAppService` on first launch

Modify `PolicyModel.swift`:
- `pauseAgent` → `proxy.command(name: "pauseAgent", ...)`
- `addSource` → `proxy.command(name: "addSource", ...)`
- etc.

Modify `SessionModel.swift`:
- `startSession` → `proxy.command(name: "startTrackedRun", ...)`
- etc.

Remove `DistributedNotificationCenter` usage (replaced by XPC or in-process observation where the runtime pushes state changes to connected clients).

Verify:
- Kill the LaunchAgent → app shows "runtime disconnected"
- Relaunch → app reconnects
- App and MCP server both connected → shared state, no races
- Kill app → LaunchAgent keeps running → MCP keeps working
- Two MCP clients simultaneously → same work block, same audit log

---

## Files Changed Summary

| Phase | New | Moved | Modified | Deleted |
|-------|-----|-------|----------|---------|
| 1 | ManifoldRuntime.swift, ManifoldServiceAPI.swift, RuntimeTypes.swift | ManifoldBridge.swift, AgentRuntimeContext.swift | Package.swift | — |
| 2 | — | — | ManifoldStore.swift, PolicyModel.swift, SessionModel.swift, HistoryModel.swift, StorageModel.swift, EmailAccountModel.swift, ManifoldMCPServer.swift | — |
| 3 | ApprovalQueue.swift | — | ManifoldBridge.swift, ToolHandlers.swift, DatabaseMigrator.swift | — |
| 4 | AccessDecision.swift, ExposureRecord.swift, ExposureStore.swift | — | ManifoldBridge.swift, ManifoldRuntime.swift, DatabaseMigrator.swift | — |
| 5 | ManifoldXPCProtocol.swift, ManifoldXPCService.swift, ManifoldXPCClient.swift, XPCCodingTypes.swift | — | Package.swift | — |
| 6 | ManifoldAgent/main.swift, LaunchAgent plist | — | Package.swift, Xcode project (bundle helper) | — |
| 7 | — | — | ManifoldMCPServer.swift, ManifoldCLI.swift | Bridge+Context from MCP (already moved) |
| 8 | — | — | ManifoldStore.swift, ManifoldApp.swift, PolicyModel.swift, SessionModel.swift, all sub-models | DistributedNotification usage |

**Net new code:** ~1,500 lines
**Net deleted:** ~400 lines (duplicate store init, optional guards, distributed notifications)
**Net moved:** ~1,600 lines (Bridge + Context → ManifoldRuntime)

---

## Verification Checklist (Post Phase 8)

- [ ] ManifoldAgent registered as LaunchAgent via SMAppService
- [ ] launchd starts ManifoldAgent on login or on first XPC connection
- [ ] launchd restarts ManifoldAgent if it crashes
- [ ] ManifoldAgent owns the single SQLite database
- [ ] App connects to agent via XPC, shows data
- [ ] manifold-mcp connects to agent via XPC, tools work
- [ ] manifold-cli connects to agent via XPC, commands work
- [ ] Two simultaneous MCP connections share state (one work block, one audit log)
- [ ] Kill app → agent still running → MCP still works
- [ ] Kill agent → app shows disconnected → MCP fails gracefully → launchd restarts agent
- [ ] Pause agent in app → MCP immediately blocked
- [ ] Write in always-on mode → escalation returned, not a write
- [ ] AccessDecision recorded for every tool call
- [ ] ExposureRecord recorded for every content return
- [ ] `explainDecision` returns human-readable reason
- [ ] Approval queue persists across agent restarts
- [ ] Close app window → agent keeps running → MCP keeps working
- [ ] Quit Manifold → agent stops → MCP fails closed
- [ ] All ManifoldKitTests pass unchanged
- [ ] `swift test` passes
- [ ] `xcodebuild test` passes
