# Phase 5: Define the XPC Layer

## Goal

Create the `ManifoldXPC` target containing the XPC protocol, service adapter, client, and coding types. This is the transport layer between the ManifoldRuntime (in the LaunchAgent) and all clients (app, MCP, CLI).

## Context

Read `design/RUNTIME-MIGRATION.md` (Phase 5 section) for the full XPC protocol specification.

Cut 1 (Phases 1-4) fixed the trust model. Cut 2 starts here — hardening the lifecycle by putting the runtime in a separate process and connecting via XPC.

The XPC protocol is deliberately minimal: 4 methods (`connect`, `disconnect`, `callTool`, `command`). All feature growth happens behind `callTool` (for agent tool dispatch) and `command` (for UI/CLI operations). This means adding a new MCP tool or a new UI action never requires changing the XPC interface.

### Key reference

- `Sources/ManifoldRuntime/ManifoldServiceAPI.swift` — the product-vocabulary protocol. The XPC service adapter translates between the XPC wire format (JSON Data) and this protocol.
- `Sources/ManifoldMCP/ToolHandlers.swift` — defines the 17 MCP tools. The XPC `callTool` method dispatches to these.

## Steps

### 1. Create Target Directory

Create `Sources/ManifoldXPC/`.

### 2. Create XPC Protocol

Create `Sources/ManifoldXPC/ManifoldXPCProtocol.swift`:

```swift
import Foundation

/// Minimal XPC protocol. Four methods handle everything.
/// This protocol uses Objective-C conventions required by NSXPCInterface.
@objc public protocol ManifoldXPCProtocol {

    /// Agent tool dispatch. connectionID scopes the bridge.
    func callTool(
        connectionID: String,
        toolName: String,
        arguments: Data,    // JSON-encoded [String: Any]
        reply: @escaping (Data, Bool) -> Void  // (result JSON, isError)
    )

    /// UI/CLI commands (policy changes, approvals, status queries).
    func command(
        name: String,
        payload: Data,      // JSON-encoded command-specific data
        reply: @escaping (Data, NSError?) -> Void
    )

    /// Connection lifecycle — agent connecting.
    func connect(
        agent: String,
        clientName: String,
        clientVersion: String,
        initializeParams: Data,  // JSON
        reply: @escaping (String?, NSError?) -> Void  // connectionID or error
    )

    /// Connection lifecycle — agent disconnecting.
    func disconnect(connectionID: String)
}
```

**Important:** This protocol must be `@objc` because `NSXPCInterface` requires Objective-C protocol semantics. All parameter types must be `NSXPCInterface`-compatible (Foundation types: `String`, `Data`, `NSError`, `Bool`).

### 3. Create XPC Service Adapter

Create `Sources/ManifoldXPC/ManifoldXPCService.swift`:

This class wraps `ManifoldRuntime` and implements the XPC protocol. It also acts as `NSXPCListenerDelegate`.

```swift
import Foundation
import ManifoldRuntime
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "xpc-service")

public class ManifoldXPCService: NSObject, NSXPCListenerDelegate, ManifoldXPCProtocol {
    private let runtime: ManifoldRuntime

    public init(runtime: ManifoldRuntime) {
        self.runtime = runtime
        super.init()
    }

    // MARK: - NSXPCListenerDelegate

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: ManifoldXPCProtocol.self)
        conn.exportedObject = self
        conn.invalidationHandler = { [weak self] in
            logger.info("XPC connection invalidated")
            // Cleanup: disconnect any bridges associated with this connection
        }
        conn.resume()
        logger.info("Accepted new XPC connection")
        return true
    }

    // MARK: - ManifoldXPCProtocol

    public func connect(agent: String, clientName: String, clientVersion: String,
                         initializeParams: Data, reply: @escaping (String?, NSError?) -> Void) {
        Task {
            do {
                let connectionID = UUID().uuidString
                let targetApp = TargetApp(rawValue: agent) ?? .cowork
                _ = await runtime.bridge(for: connectionID, targetApp: targetApp, version: clientVersion)
                logger.info("Agent connected: \(agent) as \(connectionID)")
                reply(connectionID, nil)
            } catch {
                reply(nil, error as NSError)
            }
        }
    }

    public func disconnect(connectionID: String) {
        Task {
            await runtime.removeBridge(connectionID)
            logger.info("Agent disconnected: \(connectionID)")
        }
    }

    public func callTool(connectionID: String, toolName: String, arguments: Data,
                          reply: @escaping (Data, Bool) -> Void) {
        Task {
            do {
                let args = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] ?? [:]
                // Get the bridge for this connection
                // Dispatch to ToolHandlers or directly to bridge methods
                // Serialize result back to Data
                // reply(resultData, isError)
            } catch {
                let errorData = try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])
                reply(errorData ?? Data(), true)
            }
        }
    }

    public func command(name: String, payload: Data, reply: @escaping (Data, NSError?) -> Void) {
        Task {
            do {
                let params = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
                // Dispatch based on command name: "pauseAgent", "resumeAgent", "approveRequest", etc.
                // Serialize result back to Data
                // reply(resultData, nil)
            } catch {
                reply(Data(), error as NSError)
            }
        }
    }
}
```

**Important:** Implement the full `callTool` dispatch. It should look up the bridge for the connectionID from the runtime, then call the appropriate bridge method based on `toolName`. Reference `ToolHandlers.swift` for the mapping of tool names to bridge methods.

Implement the full `command` dispatch. Support at minimum these commands:
- `getStatus` → returns runtime status
- `pauseAgent` → calls `runtime.policyStore.pauseAgent()`
- `resumeAgent` → calls `runtime.policyStore.resumeAgent()`
- `listApprovalRequests` → calls `runtime.approvalQueue.pending()`
- `approveRequest` → calls `runtime.approvalQueue.approve()`
- `denyRequest` → calls `runtime.approvalQueue.deny()`
- `recentActivity` → calls `runtime.auditStore` query
- `exposureLog` → calls `runtime.exposureStore.exposures()`

### 4. Create XPC Client

Create `Sources/ManifoldXPC/ManifoldXPCClient.swift`:

```swift
import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "xpc-client")

/// Client that connects to the ManifoldRuntime LaunchAgent via Mach service.
public class ManifoldXPCClient: @unchecked Sendable {
    public static let serviceName = "com.spatialduality.manifold.runtime"

    private var connection: NSXPCConnection?
    private let lock = NSLock()

    public init() {}

    public func connect() -> ManifoldXPCProtocol {
        lock.lock()
        defer { lock.unlock() }

        if let existing = connection {
            if let proxy = existing.remoteObjectProxy as? ManifoldXPCProtocol {
                return proxy
            }
        }

        let conn = NSXPCConnection(machServiceName: Self.serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: ManifoldXPCProtocol.self)
        conn.invalidationHandler = { [weak self] in
            logger.warning("XPC connection to runtime invalidated")
            self?.lock.lock()
            self?.connection = nil
            self?.lock.unlock()
        }
        conn.interruptionHandler = {
            logger.warning("XPC connection to runtime interrupted")
        }
        conn.resume()

        self.connection = conn
        return conn.remoteObjectProxy as! ManifoldXPCProtocol
    }

    /// Async wrapper for callTool
    public func callTool(connectionID: String, toolName: String, arguments: [String: Any]) async throws -> [String: Any] {
        let proxy = connect()
        let argData = try JSONSerialization.data(withJSONObject: arguments)
        return try await withCheckedThrowingContinuation { cont in
            proxy.callTool(connectionID: connectionID, toolName: toolName, arguments: argData) { data, isError in
                if isError {
                    let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "Unknown error"
                    cont.resume(throwing: NSError(domain: "ManifoldXPC", code: 1, userInfo: [NSLocalizedDescriptionKey: msg]))
                } else {
                    let result = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                    cont.resume(returning: result)
                }
            }
        }
    }

    /// Async wrapper for command
    public func command(name: String, payload: [String: Any] = [:]) async throws -> [String: Any] {
        let proxy = connect()
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        return try await withCheckedThrowingContinuation { cont in
            proxy.command(name: name, payload: payloadData) { data, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    let result = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                    cont.resume(returning: result)
                }
            }
        }
    }

    public func disconnect() {
        lock.lock()
        connection?.invalidate()
        connection = nil
        lock.unlock()
    }
}
```

### 5. Create Coding Types

Create `Sources/ManifoldXPC/XPCCodingTypes.swift` — helper types for JSON serialization of commands and results. Simple `Codable` structs for common command payloads and responses.

### 6. Update Package.swift

Add the new target:
```swift
.target(
    name: "ManifoldXPC",
    dependencies: ["ManifoldRuntime"],
    path: "Sources/ManifoldXPC"
),
```

Update downstream dependencies as needed.

## Constraints

- The XPC protocol is `@objc`. All parameter types must be NSXPCInterface-compatible: `String`, `Data`, `Bool`, `NSError`. No Swift-only types in the protocol.
- The XPC protocol stays at 4 methods. Do NOT add per-feature XPC methods. All features route through `callTool` or `command`.
- `ManifoldXPCClient` must handle connection invalidation and interruption gracefully (reconnect on next call).
- `@unchecked Sendable` on the client is acceptable since it uses `NSLock` for thread safety.
- All JSON serialization/deserialization should use `JSONSerialization` (not `Codable` over XPC — `Data` is the wire format).
- Existing tests must pass. This phase adds new code but doesn't change existing behavior.

## Done When

- [ ] `Sources/ManifoldXPC/` exists with: `ManifoldXPCProtocol.swift`, `ManifoldXPCService.swift`, `ManifoldXPCClient.swift`, `XPCCodingTypes.swift`
- [ ] `ManifoldXPC` target in `Package.swift` with correct dependencies
- [ ] `ManifoldXPCProtocol` is `@objc` with 4 methods
- [ ] `ManifoldXPCService` implements full `callTool` dispatch (all 17 tool names)
- [ ] `ManifoldXPCService` implements full `command` dispatch (status, pause, resume, approvals, activity, exposure)
- [ ] `ManifoldXPCClient` connects via Mach service name, handles invalidation/interruption
- [ ] `ManifoldXPCClient` has async wrappers for `callTool` and `command`
- [ ] `swift build` succeeds
- [ ] `swift test` passes
- [ ] Write a new test: create `ManifoldXPCService` in-process with a runtime, verify `callTool` dispatch works
