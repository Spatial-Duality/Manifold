# Phase 7: Make MCP Server and CLI Thin XPC Clients

## Goal

Rewrite `manifold-mcp` and `manifold-cli` to be thin XPC clients that forward all operations to the ManifoldRuntime LaunchAgent. Neither should open the SQLite database or create any stores.

## Context

Read `design/RUNTIME-MIGRATION.md` (Phase 7 section).

After Phase 6, the ManifoldAgent LaunchAgent is running and accepting XPC connections. Now the MCP server and CLI must stop being independent authorities and instead proxy everything through XPC.

### Key files to rewrite

- `Sources/ManifoldMCP/ManifoldMCPServer.swift` — currently creates `ManifoldRuntime` in-process (from Phase 2). Must become: parse stdio MCP JSON-RPC → forward tool calls via XPC → return results on stdio.
- `Sources/ManifoldMCP/ToolHandlers.swift` — currently dispatches directly to `ManifoldBridge`. Must keep tool definitions (names, schemas) but forward execution through XPC.
- `Sources/ManifoldCLI/` — whatever CLI entry point exists. Must forward all commands through XPC.

### Files that should have already been moved (verify)

- `ManifoldBridge.swift` should be in `Sources/ManifoldRuntime/` (moved in Phase 1)
- `AgentRuntimeContext.swift` should be in `Sources/ManifoldRuntime/` (moved in Phase 1)

If these files still exist in `Sources/ManifoldMCP/`, delete them. They should only exist in ManifoldRuntime.

## Steps

### 1. Rewrite ManifoldMCPServer.swift

The MCP server becomes a stdio↔XPC bridge. It:
- Reads JSON-RPC from stdin (MCP protocol)
- Parses tool calls
- Forwards them to ManifoldAgent via `ManifoldXPCClient.callTool()`
- Returns results on stdout

```swift
import Foundation
import ManifoldXPC

@main
struct ManifoldMCPServer {
    static func main() async throws {
        let version = "0.4.0"

        if CommandLine.arguments.contains("--version") {
            print("manifold-mcp \(version)")
            return
        }
        if CommandLine.arguments.contains("--install") {
            // ConfigWriter logic stays — it writes MCP config to Claude/Codex config files
            // This doesn't need XPC, it's a local file operation
            return
        }

        let targetApp = parseTargetApp(from: CommandLine.arguments)
        let xpc = ManifoldXPCClient()

        // Connect to runtime
        let connectionID = try await xpc.connectAgent(
            agent: targetApp,
            clientName: "manifold-mcp",
            clientVersion: version
        )

        // Create MCP server (JSON-RPC over stdio)
        let server = MCPServer(name: "manifold", version: version)

        // Register tools — keep the tool definitions from ToolHandlers
        // but forward execution through XPC
        await server.registerTools(ToolHandlers.toolDefinitions()) { name, arguments in
            let result = try await xpc.callTool(
                connectionID: connectionID,
                toolName: name,
                arguments: arguments
            )
            return result
        }

        // Run the stdio loop
        do {
            try await server.start()
        } catch {
            xpc.disconnectAgent(connectionID: connectionID)
            throw error
        }
        xpc.disconnectAgent(connectionID: connectionID)
    }
}
```

### 2. Refactor ToolHandlers.swift

`ToolHandlers` must split into two concerns:

a) **Tool definitions** (names, descriptions, input schemas) — stay in ManifoldMCP because the MCP server needs to register them. Extract a static method:
```swift
public static func toolDefinitions() -> [(name: String, description: String, schema: [String: Any])] {
    // Return the 17 tool definitions without any bridge dependency
}
```

b) **Tool execution** (dispatch to bridge) — stays in ManifoldRuntime (or ManifoldXPC service adapter). The MCP server no longer calls these directly — it goes through XPC.

If `ToolHandlers` currently tightly couples definitions with execution, split it:
- `Sources/ManifoldMCP/ToolDefinitions.swift` — tool names, descriptions, schemas (no runtime dependency)
- The execution logic is already handled by `ManifoldXPCService.callTool()` from Phase 5

### 3. Update ManifoldMCP Package Dependencies

In `Package.swift`, change ManifoldMCP's dependencies:
```swift
.executableTarget(
    name: "ManifoldMCP",
    dependencies: ["ManifoldXPC"],  // No longer needs ManifoldKit or ManifoldRuntime directly
    path: "Sources/ManifoldMCP"
),
```

If tool definitions reference ManifoldKit types for schemas, keep ManifoldKit as a dependency but ManifoldMCP should NOT import ManifoldRuntime.

### 4. Rewrite ManifoldCLI

Same pattern. All commands go through `ManifoldXPCClient.command()`:

```swift
// status command
let status = try await xpc.command(name: "getStatus")

// pause command
try await xpc.command(name: "pauseAgent", payload: ["agent": "cowork"])

// activity command
let activity = try await xpc.command(name: "recentActivity", payload: ["limit": 20])

// exposure command
let exposure = try await xpc.command(name: "exposureLog", payload: ["limit": 50])
```

### 5. Delete Stale Files

Verify and delete any files from ManifoldMCP that should only exist in ManifoldRuntime:
- `Sources/ManifoldMCP/ManifoldBridge.swift` (should have been moved in Phase 1)
- `Sources/ManifoldMCP/AgentRuntimeContext.swift` (should have been moved in Phase 1)

### 6. Add XPC Async Helpers to Client

If not already done in Phase 5, add async convenience methods to `ManifoldXPCClient`:

```swift
public func connectAgent(agent: String, clientName: String, clientVersion: String) async throws -> String {
    // Wraps connect() with async/await
}

public func disconnectAgent(connectionID: String) {
    // Wraps disconnect()
}
```

## Constraints

- `manifold-mcp` must NOT import ManifoldRuntime. It only imports ManifoldXPC (and ManifoldKit if needed for type definitions).
- `manifold-mcp` must NOT open any SQLite database.
- `manifold-mcp` must NOT create any store instances.
- `MCPProtocol.swift` (the JSON-RPC stdio server) stays in ManifoldMCP — it's protocol plumbing, not runtime logic.
- `ConfigWriter` stays in ManifoldKit — it's a local file operation for installing MCP config.
- The `--install` flag behavior is unchanged.
- Existing tool behavior must be identical from the agent's perspective — same tool names, same schemas, same return formats.
- `swift test` must pass. Update test imports if tests reference ManifoldBridge from ManifoldMCP.

## Done When

- [ ] `manifold-mcp` starts, connects to ManifoldAgent via XPC, registers tools, runs stdio loop
- [ ] `manifold-mcp` has zero SQLite / store / bridge imports
- [ ] `manifold-cli` commands all go through XPC
- [ ] `manifold-cli` has zero SQLite / store imports
- [ ] Tool definitions separated from tool execution
- [ ] No stale bridge/context files in ManifoldMCP
- [ ] `swift build` succeeds
- [ ] `swift test` passes
- [ ] Manual test: start ManifoldAgent, then run `manifold-mcp` → agent tool calls return correct results via XPC
- [ ] Manual test: `manifold-cli status` works through XPC
