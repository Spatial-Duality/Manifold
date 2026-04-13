# Phase 6: Build the LaunchAgent Binary

## Goal

Create the `ManifoldAgent` executable — a headless LaunchAgent binary that hosts `ManifoldRuntime` and exposes it over an XPC Mach service. Create the launchd plist. Wire up `SMAppService` registration from the app.

## Context

Read `design/RUNTIME-MIGRATION.md` (Phase 6 section).

This phase creates the actual separate process. After this, the runtime runs independently from the UI. launchd manages its lifecycle: starts on login (or on first XPC connection), restarts on crash, stops on clean exit.

### Key reference

- `design/RUNTIME-MIGRATION.md` — LaunchAgent plist specification, main.swift sketch
- `Sources/ManifoldXPC/ManifoldXPCService.swift` — the service adapter created in Phase 5
- `Sources/ManifoldRuntime/ManifoldRuntime.swift` — the runtime actor

## Steps

### 1. Create ManifoldAgent Executable

Create `Sources/ManifoldAgent/main.swift`:

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

    logger.info("ManifoldAgent ready. Listening on \(ManifoldXPCClient.serviceName)")

    // Background maintenance tasks
    Task {
        // Prune old snapshots
        try? await runtime.snapshotStore.pruneByAge(days: 30)
        // Garbage collect unreferenced content blobs
        try? await runtime.contentStore.garbageCollect()
        // Expire old approval requests
        try? await runtime.approvalQueue.expire(olderThan: 30 * 60) // 30 minutes
        logger.info("Background maintenance complete")
    }

    // Keep the process alive
    RunLoop.main.run()
} catch {
    logger.fault("ManifoldAgent failed to start: \(error.localizedDescription)")
    exit(1)
}
```

**Important:** `NSXPCListener(machServiceName:)` only works when the Mach service name is registered in a launchd plist. This binary is designed to be launched BY launchd, not run directly from the command line (unless for testing with `launchctl debug`).

### 2. Create LaunchAgent Plist

This file must be placed in the app bundle at build time. For the Swift Package, create it at a known location. For the Xcode project, it needs to be in the app bundle at `Contents/Library/LaunchAgents/`.

Create the plist content (the Xcode project build phase will copy it):

File: `Resources/com.spatialduality.manifold.runtime.plist`

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

- `MachServices` tells launchd to register the Mach service name so `NSXPCConnection(machServiceName:)` can find it.
- `KeepAlive.SuccessfulExit = false` means launchd restarts on crash but not on clean exit.
- `ProcessType = Interactive` gives reasonable scheduling priority.
- No `Program` or `ProgramArguments` key — `SMAppService` fills these in based on the bundle location.

### 3. Update Package.swift

Add the executable target:

```swift
.executableTarget(
    name: "ManifoldAgent",
    dependencies: ["ManifoldRuntime", "ManifoldXPC"],
    path: "Sources/ManifoldAgent"
),
```

### 4. Add SMAppService Registration to the App

This step involves the Xcode project (ManifoldApp). Add code to register the LaunchAgent on first launch.

In the app's initialization (e.g., `ManifoldApp.swift` or `ManifoldStore.swift`), add:

```swift
import ServiceManagement

func registerAgent() {
    let service = SMAppService.agent(plistName: "com.spatialduality.manifold.runtime.plist")
    do {
        try service.register()
        logger.info("ManifoldAgent registered with launchd")
    } catch {
        logger.error("Failed to register ManifoldAgent: \(error.localizedDescription)")
        // Non-fatal for now — agent might already be registered
    }
}
```

Call this early in the app lifecycle. `SMAppService.agent(plistName:)` expects the plist to be at `Contents/Library/LaunchAgents/<plistName>` inside the app bundle.

### 5. Xcode Project Configuration

The Xcode project needs:
- The `ManifoldAgent` binary copied to `Contents/Library/LaunchAgents/ManifoldRuntime`
- The plist copied to `Contents/Library/LaunchAgents/com.spatialduality.manifold.runtime.plist`
- A "Copy Files" build phase targeting the `Library/LaunchAgents` directory inside the bundle

**Note:** If you cannot modify the Xcode project directly, document what build phases need to be added and leave this as a manual step.

### 6. Add Quit/Stop Semantics

In the app's termination handler, add logic for "Quit Manifold = stop the agent":

```swift
func unregisterAgent() {
    let service = SMAppService.agent(plistName: "com.spatialduality.manifold.runtime.plist")
    service.unregister { error in
        if let error {
            logger.error("Failed to unregister ManifoldAgent: \(error.localizedDescription)")
        } else {
            logger.info("ManifoldAgent unregistered — will not restart")
        }
    }
}
```

This should be called when the user explicitly "Quits Manifold" (not just closes the window). Closing the window should NOT stop the agent.

## Constraints

- The LaunchAgent binary must be headless — no UI frameworks, no AppKit, no SwiftUI imports.
- `NSXPCListener(machServiceName:)` only works with launchd registration. Do not try to use it without the plist.
- `SMAppService` requires macOS 13+ (we target macOS 26, so this is fine).
- The agent must be a separate executable, not a framework or library.
- Fail-fast on startup: if `ManifoldRuntime()` throws, exit with code 1 so launchd knows it failed.
- Existing tests must pass. This phase adds new code.

## Done When

- [ ] `Sources/ManifoldAgent/main.swift` exists and compiles
- [ ] LaunchAgent plist exists at `Resources/com.spatialduality.manifold.runtime.plist`
- [ ] `ManifoldAgent` target in `Package.swift`
- [ ] `swift build` succeeds (builds ManifoldAgent binary)
- [ ] App has `registerAgent()` / `unregisterAgent()` calls using `SMAppService`
- [ ] Documentation exists for Xcode build phase setup (Copy Files to LaunchAgents)
- [ ] `swift test` passes
