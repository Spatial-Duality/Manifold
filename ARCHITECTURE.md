# Manifold Architecture

Manifold controls what AI agents (Claude, Codex) can access on your Mac. Files, emails, versions. Everything local.

## System Overview

```
┌──────────────────────────────────────────────────────────┐
│                      User's Mac                          │
│                                                          │
│  ┌─────────────┐         XPC          ┌───────────────┐  │
│  │ Manifold.app│◄──────────────────►│ ManifoldAgent  │  │
│  │ (SwiftUI)   │   Mach service      │ (LaunchAgent)  │  │
│  └─────────────┘                     │ ManifoldRuntime│  │
│                                      └───────┬───────┘  │
│  ┌─────────────┐         XPC              │         │
│  │manifold-mcp │◄────────────────────────┘         │
│  │ (stdio MCP) │                                    │
│  └──────┬──────┘                           ┌───────▼───┐ │
│         │                                  │  SQLite   │ │
│  ┌──────▼──────┐                           │  WAL mode │ │
│  │ Claude /    │                           └───────────┘ │
│  │ Codex       │                                         │
│  └─────────────┘                                         │
└──────────────────────────────────────────────────────────┘
```

**ManifoldAgent** is a headless LaunchAgent binary. It owns the SQLite database and all store actors. It exposes a Mach service via `NSXPCListener`.

**Manifold.app** is a pure XPC client. It never opens the database directly. All data access goes through `AppRuntimeClient` → `ManifoldXPCClient` → XPC → `ManifoldXPCService`.

**manifold-mcp** is a stdio MCP server that Claude Desktop and Codex CLI connect to. It's also an XPC client, forwarding MCP tool calls to ManifoldAgent.

## Package Structure

```
Sources/
  ManifoldKit/       # Core types, stores (actor-isolated), database layer
  ManifoldRuntime/   # Runtime composition root, ManifoldBridge (per-connection)
  ManifoldXPC/       # XPC protocol, service, client, coding types
  ManifoldAgent/     # LaunchAgent entry point (main.swift, ~30 lines)
  ManifoldMCP/       # MCP server (stdio JSON-RPC 2.0)

ManifoldApp/
  ManifoldApp/       # SwiftUI app (81 files)
    Models/          # ManifoldStore, sub-models, AppRuntimeClient
    Views/           # All views organized by feature
    Components/      # Design tokens, shared components
```

## Key Types

| Type | Role |
|------|------|
| `ManifoldRuntime` | Actor. Owns all stores. Creates bridges for MCP connections. |
| `ManifoldBridge` | Actor. Per-connection state. Handles MCP tool calls with access control. |
| `ManifoldStore` | `@Observable @MainActor`. App-side state. XPC client. |
| `PolicyStore` | Actor. Per-agent access policies (which sources, which email domains). |
| `GrantStore` | Actor. Source registration, grant lifecycle. |
| `ContentStore` | Actor. Content-addressed blob store (SHA-256). |
| `SnapshotStore` | Actor. File version history (before/after hashes). |
| `AuditStore` | Actor. Activity logging. |
| `WorkBlockStore` | Actor. Tracked work block lifecycle. |

## Data Model

Standing access: each agent (Claude, Codex) has an `AgentAccessPolicy` with allowed source IDs and email domains. Policies persist across sessions. No session ceremony needed to use the app.

Optional tracked work blocks: snapshot files before AI changes, review diffs, promote or discard.

## Building

```bash
swift build                           # Build all targets
swift test                            # 278 tests
swift build --product ManifoldAgent   # Just the agent binary
```

Xcode: open `Manifold.xcodeproj`. The build script phase runs `swift build --product ManifoldAgent` and bundles the binary into `Contents/Library/LaunchServices/`.

## XPC Connection Lifecycle

1. App launches → `ManifoldStore.registerAgent()` → SMAppService or launchd fallback
2. App polls `ping()` every 5 seconds → sets `isRuntimeConnected`
3. On connected: `dashboardState()` fetches sources, policies, work blocks, connected agents
4. On version mismatch: auto-restarts the agent
5. MCP server connects: `connect()` → bridge created → tools available
6. MCP server disconnects: `disconnect()` → bridge removed

## Design System

Design tokens in `Components/DesignTokens.swift`: `Typ` (typography), `Spacing`, `Opacity`, `Anim`, semantic colors (ClaudeBlue, CodexPurple, status colors).

Agent identity: ClaudeBlue and CodexPurple used consistently for card borders, checkboxes, toggles, row tints, and toolbar status indicators.
