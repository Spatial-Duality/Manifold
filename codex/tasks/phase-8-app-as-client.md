# Phase 8: Make the SwiftUI App an XPC Client

## Goal

Remove the in-process `ManifoldRuntime` from the SwiftUI app. Replace it with `ManifoldXPCClient` connections to the LaunchAgent. The app becomes a pure UI client — it displays data and sends commands, but never touches the database directly.

## Context

Read `design/RUNTIME-MIGRATION.md` (Phase 8 section).

This is the final phase. After this, all three clients (app, MCP, CLI) connect to the ManifoldAgent LaunchAgent via XPC. One judge, three clients. The architectural migration is complete.

### Key files to modify

- `ManifoldApp/ManifoldApp/Models/ManifoldStore.swift` — replace `ManifoldRuntime` (in-process from Phase 2) with `ManifoldXPCClient`
- `ManifoldApp/ManifoldApp/Models/PolicyModel.swift` — all mutations go through XPC `command()`
- `ManifoldApp/ManifoldApp/Models/SessionModel.swift` — session lifecycle goes through XPC
- `ManifoldApp/ManifoldApp/Models/HistoryModel.swift` — queries go through XPC
- `ManifoldApp/ManifoldApp/Models/StorageModel.swift` — queries go through XPC
- `ManifoldApp/ManifoldApp/Models/EmailAccountModel.swift` — email config goes through XPC
- `ManifoldApp/ManifoldApp/ManifoldApp.swift` — register LaunchAgent via SMAppService
- `Sources/ManifoldKit/ManifoldNotifications.swift` — DistributedNotificationCenter usage is deleted

### Control semantics (non-negotiable)

- **Close window** → hides UI. Runtime keeps running. Agents keep working.
- **Pause all access** → `xpc.command("pauseAllAgents")`. Runtime denies new requests.
- **Quit Manifold** → `SMAppService.unregister()`. Runtime stops. Fail-closed.
- **Login** → launchd starts runtime. App appears if configured as login item.

## Steps

### 1. Rewrite ManifoldStore

Open `ManifoldApp/ManifoldApp/Models/ManifoldStore.swift`.

Replace the `ManifoldRuntime` property with `ManifoldXPCClient`:

```swift
@Observable
@MainActor
final class ManifoldStore {
    let xpc = ManifoldXPCClient()

    // Cached state refreshed from runtime
    var runtimeStatus: RuntimeStatus?
    var isRuntimeConnected: Bool = false

    init() {
        // Register the LaunchAgent if not already registered
        registerAgent()
        // Initial data load
        Task { await refreshAll() }
    }

    func refreshAll() async {
        do {
            let status = try await xpc.command(name: "getStatus")
            // Parse status into local state
            isRuntimeConnected = true
        } catch {
            isRuntimeConnected = false
            logger.error("Runtime disconnected: \(error.localizedDescription)")
        }
    }

    private func registerAgent() {
        let service = SMAppService.agent(plistName: "com.spatialduality.manifold.runtime.plist")
        do {
            try service.register()
        } catch {
            logger.error("Failed to register agent: \(error.localizedDescription)")
        }
    }
}
```

Delete all direct store references. Delete `ManifoldRuntime` property. Delete all `import ManifoldRuntime` — the app imports `ManifoldXPC` instead.

### 2. Rewrite PolicyModel

Open `ManifoldApp/ManifoldApp/Models/PolicyModel.swift`.

All mutations become XPC commands:

```swift
@Observable
@MainActor
final class PolicyModel {
    var claudePolicy: AgentAccessPolicy?
    var codexPolicy: AgentAccessPolicy?
    var activeWorkBlock: WorkBlockRecord?

    private let xpc: ManifoldXPCClient

    init(xpc: ManifoldXPCClient) {
        self.xpc = xpc
    }

    func loadPolicies() async {
        do {
            let result = try await xpc.command(name: "getPolicies")
            // Decode result into claudePolicy and codexPolicy
        } catch {
            logger.error("Failed to load policies: \(error.localizedDescription)")
        }
    }

    func pauseAgent(_ agent: TargetApp) async {
        do {
            try await xpc.command(name: "pauseAgent", payload: ["agent": agent.rawValue])
            await loadPolicies()
        } catch {
            logger.error("Failed to pause: \(error.localizedDescription)")
        }
    }

    func resumeAgent(_ agent: TargetApp) async {
        do {
            try await xpc.command(name: "resumeAgent", payload: ["agent": agent.rawValue])
            await loadPolicies()
        } catch {
            logger.error("Failed to resume: \(error.localizedDescription)")
        }
    }

    // Same pattern for addSource, removeSource, addEmailDomain, etc.
    // All go through xpc.command()
}
```

### 3. Rewrite SessionModel

Same pattern. Session lifecycle goes through XPC:

- `startSession()` → `xpc.command(name: "startTrackedRun", payload: [...])`
- `endSession()` → `xpc.command(name: "finishTrackedRun", payload: [...])`
- `computePreview()` → `xpc.command(name: "promotionPreview", payload: [...])`
- `completeWorkBlock()` → `xpc.command(name: "applyTrackedRun", payload: [...])`

### 4. Rewrite Other Models

- `HistoryModel` — queries go through `xpc.command(name: "recentActivity")`
- `StorageModel` — storage stats through `xpc.command(name: "storageStats")`
- `EmailAccountModel` — email config through `xpc.command(name: "emailConfig")`

### 5. Add Runtime Connection State

The app needs to handle the runtime being unavailable:

```swift
// In ManifoldStore or a dedicated ConnectionMonitor
func monitorConnection() {
    Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
        Task { @MainActor in
            do {
                _ = try await self?.xpc.command(name: "ping")
                self?.isRuntimeConnected = true
            } catch {
                self?.isRuntimeConnected = false
            }
        }
    }
}
```

When `isRuntimeConnected` is false, the UI should show a "Runtime Disconnected" state. This handles:
- LaunchAgent hasn't started yet
- LaunchAgent crashed (launchd will restart it)
- User quit Manifold and re-opened just the window

### 6. Delete DistributedNotificationCenter Usage

Open `Sources/ManifoldKit/ManifoldNotifications.swift`. This file defined fire-and-forget notifications for cross-process communication. It's no longer needed — XPC replaces it.

Delete or gut the file. Remove all `DistributedNotificationCenter.post()` calls throughout the codebase. Remove all observers.

Search for:
- `DistributedNotificationCenter`
- `ManifoldNotification`
- `.agentConnected`
- `.agentDisconnected`
- `.accessDenied`
- `.fileAccessed`
- `.dataChanged`

### 7. Update App Package Dependencies

The Xcode project's package dependency should change from `ManifoldRuntime` to `ManifoldXPC`. The app should NOT import `ManifoldRuntime` or `ManifoldKit` directly (except for shared type definitions).

If some ManifoldKit types are needed for the UI (e.g., `AgentAccessPolicy`, `WorkBlockRecord`, `TargetApp`), keep ManifoldKit as a dependency but the app should never import ManifoldRuntime.

### 8. Implement "Quit Manifold" Properly

In the app delegate or SwiftUI lifecycle:

```swift
// When user selects "Quit Manifold" from menu
func applicationWillTerminate(_ notification: Notification) {
    // Only unregister if user explicitly quit (not just closed window)
    if userExplicitlyQuit {
        let service = SMAppService.agent(plistName: "com.spatialduality.manifold.runtime.plist")
        service.unregister { error in
            // Agent will stop, fail-closed
        }
    }
}
```

## Constraints

- The app must NOT import `ManifoldRuntime`. It imports `ManifoldXPC` and `ManifoldKit` (for types only).
- The app must NOT open any SQLite database.
- The app must NOT create any store instances.
- Close window ≠ quit. The app should use `NSApp.setActivationPolicy(.accessory)` or similar to stay alive as a menu bar app when the window closes.
- All XPC calls can fail. Every model method must handle errors gracefully — show disconnected state, not crash.
- Existing ManifoldKit types (`AgentAccessPolicy`, `WorkBlockRecord`, etc.) should still be usable in the UI without change. They're Codable/Sendable structs that come back from XPC as decoded JSON.
- `swift test` must pass.

## Done When

- [ ] `ManifoldStore` uses `ManifoldXPCClient`, not `ManifoldRuntime`
- [ ] `PolicyModel` sends all mutations through XPC commands
- [ ] `SessionModel` sends all session operations through XPC commands
- [ ] All other models use XPC for data access
- [ ] App shows "runtime disconnected" when LaunchAgent is not running
- [ ] App reconnects automatically when LaunchAgent starts
- [ ] Close window → agent keeps running → MCP keeps working
- [ ] Quit Manifold → `SMAppService.unregister()` → agent stops → fail-closed
- [ ] No `DistributedNotificationCenter` usage anywhere in the codebase
- [ ] No `DatabaseConnection` usage in the app target
- [ ] `swift build` succeeds
- [ ] `swift test` passes
- [ ] App compiles with Xcode
- [ ] Full verification checklist from `design/RUNTIME-MIGRATION.md` passes:
  - Kill app → agent still running → MCP still works
  - Kill agent → app shows disconnected → launchd restarts agent → app reconnects
  - Pause in app → MCP immediately blocked
  - Two MCP clients → shared state, no races
  - Write in always-on → escalation returned
  - AccessDecision + ExposureRecord for every tool call
