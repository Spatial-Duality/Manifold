# Manifold — Codex Agent Instructions

## What Manifold Is

Manifold is a native macOS app (Swift 6, SwiftUI, macOS 26+) that governs which files and emails Claude and Codex can access through Manifold. It records what was exposed, what changed, and what can be restored, but it must never claim OS-level control over native activity outside the Manifold path.

The product's entire value is the constraint itself. The product IS the thing that sits between an agent and governed data and says: you can see this through Manifold, you cannot see that through Manifold, and here is the proof of both.

## Architecture (Current)

**Current architecture:** One bundled per-user LaunchAgent (`ManifoldAgent`) owns the stores and policy enforcement. The SwiftUI app, `manifold-mcp`, and `manifold-cli` are XPC clients connecting via the launchd-registered Mach service `com.spatialduality.manifold.runtime`.

**Design direction:** keep the runtime as the single judge, keep the MCP/CLI/app clients thin, and keep the product boundary explicit in both code and copy.

**Key design doc:** `design/RUNTIME-MIGRATION.md` — the authoritative 8-phase migration plan with code sketches, plist, file changes, verification checklist.

**Reasoning doc:** `design/WHY-RUNTIME.md` — explains why this architecture exists, grounded in Manifold's core purpose.

## Package Layout

```
ManifoldKit        (library)    → stores, engines, types (unchanged)
ManifoldRuntime    (library)    → runtime actor, service protocol, bridge, approval queue
ManifoldXPC        (library)    → XPC protocol, client, service adapter, coding types
ManifoldAgent      (executable) → LaunchAgent binary: runtime + XPC listener
ManifoldMCP        (executable) → thin: MCPServer + XPC client (no stores)
ManifoldCLI        (executable) → thin: XPC client (no stores)
ManifoldApp        (Xcode)      → SwiftUI app + XPC client (no stores)
```

### Dependencies
```
ManifoldKit        ← nothing
ManifoldRuntime    ← ManifoldKit
ManifoldXPC        ← ManifoldRuntime
ManifoldAgent      ← ManifoldRuntime + ManifoldXPC
ManifoldMCP        ← ManifoldXPC (+ ManifoldKit for tool definitions only)
ManifoldCLI        ← ManifoldXPC
ManifoldApp        ← ManifoldXPC
```

## Key Files

| File | Purpose | Lines |
|------|---------|-------|
| `Sources/ManifoldRuntime/ManifoldBridge.swift` | Core decision engine (dual-path access resolution, audit, exposure) | ~2000 |
| `Sources/ManifoldXPC/ManifoldXPCService.swift` | XPC boundary and command/tool dispatch | ~200 |
| `Sources/ManifoldXPC/ClientIdentityVerifier.swift` | Local caller verification and app-command authorization | ~250 |
| `Sources/ManifoldXPC/ManifoldXPCService+AppCommands.swift` | App and CLI command handlers | ~900 |
| `Sources/ManifoldMCP/ToolHandlers.swift` | 17 MCP tool registrations | ~395 |
| `Sources/ManifoldMCP/AgentRuntimeContext.swift` | Connection metadata | ~80 |
| `Sources/ManifoldMCP/MCPProtocol.swift` | JSON-RPC 2.0 over stdio | ~300 |
| `Sources/ManifoldKit/PolicyStore.swift` | Per-agent standing access policy | ~200 |
| `Sources/ManifoldKit/AgentAccessPolicy.swift` | Policy data structures | ~150 |
| `Sources/ManifoldKit/WorkBlockStore.swift` | Tracked work block lifecycle | ~200 |
| `Sources/ManifoldKit/RequestStore.swift` | Access request queue (rate-limited) | ~150 |
| `Sources/ManifoldKit/GrantStore.swift` | Grant and source management | ~400 |
| `Sources/ManifoldKit/ContentStore.swift` | Content-addressed blob storage (SHA-256) | ~300 |
| `Sources/ManifoldKit/SnapshotStore.swift` | File snapshots for three-way merge | ~250 |
| `Sources/ManifoldKit/AuditStore.swift` | Audit log | ~200 |
| `Sources/ManifoldKit/EmailStore.swift` | Email metadata and body storage | ~250 |
| `Sources/ManifoldKit/DatabaseMigrator.swift` | SQLite schema migrations | ~400 |
| `ManifoldApp/ManifoldApp/Models/AppRuntimeClient.swift` | App-side XPC client and typed runtime commands | ~1000 |
| `ManifoldApp/ManifoldApp/Models/ManifoldStore.swift` | App composition, refresh, and window-level state | ~700 |
| `ManifoldApp/ManifoldApp/Models/PolicyModel.swift` | @Observable policy model (optional stores) | ~239 |
| `ManifoldApp/ManifoldApp/Models/SessionModel.swift` | Session/grant/promotion lifecycle (optional stores) | ~809 |

## Build & Test

```bash
# Build the Swift package (ManifoldKit, ManifoldMCP, ManifoldCLI)
swift build

# Run all package tests
swift test

# Build the Xcode app (ManifoldApp)
xcodebuild -project ManifoldApp/ManifoldApp.xcodeproj \
  -scheme Manifold \
  -destination 'platform=macOS' \
  build

# Run Xcode tests
xcodebuild -project ManifoldApp/ManifoldApp.xcodeproj \
  -scheme Manifold \
  -destination 'platform=macOS' \
  test
```

## Conventions

- **Swift 6 strict concurrency.** All new code must compile with Swift 6's complete concurrency checking. Actors for shared mutable state. `Sendable` conformance required on all types crossing isolation boundaries.
- **Actors, not classes with locks.** Every store (`PolicyStore`, `GrantStore`, `WorkBlockStore`, etc.) is an `actor`. New stores must also be actors.
- **SQLite via DatabaseConnection.** No ORM. Direct SQL through the project's `DatabaseConnection` wrapper. Parameterized queries only — no string interpolation in SQL.
- **Content-addressed storage.** Files in `ContentStore` are stored by SHA-256 hash with 2-char prefix sharding (e.g., `ab/abcdef1234...`). Never store file content by path.
- **Migrations via DatabaseMigrator.** New tables require a new migration in `DatabaseMigrator.swift`. Migrations are sequential and idempotent.
- **@Observable + @MainActor for UI models.** All SwiftUI models use `@Observable` and are `@MainActor`-isolated.
- **No force unwraps.** No `!` except in tests.
- **Error handling.** Stores throw. Models catch and log via `os.Logger`. UI never crashes on store errors.
- **Logging.** Use `import os` and `Logger(subsystem: "com.spatialduality.manifold", category: "...")`. No `print()` in production code.

## Hard Rules (Non-Negotiable)

1. **One judge.** After migration, `ManifoldRuntime` is the single composition root. No other process or target creates stores directly against the database. If you find yourself writing `DatabaseConnection(url:)` outside of `ManifoldRuntime.swift`, stop — that's the bug this migration fixes.

2. **Standing access never writes.** Any write attempt in always-on/standing mode must return `.escalationRequired`. This is the product's core promise. Do not add code paths that bypass this.

3. **Every access recorded.** Every tool call that checks permissions must create an `AccessDecision`. Every tool call that returns content must create an `ExposureRecord` with byte count and content hash. Search snippets, diffs, email previews — all exposures.

4. **XPC protocol stays minimal.** Four methods: `connect`, `disconnect`, `callTool`, `command`. All feature growth happens behind `callTool` (for agents) and `command` (for UI/CLI). Do not add XPC methods for individual features.

5. **ManifoldKit stays clean.** `ManifoldKit` is the library of stores, engines, and types. It has no knowledge of XPC, MCP, UI, or runtime lifecycle. It does not import Foundation frameworks beyond what's needed for data types and file operations.

6. **No unauthenticated app commands.** State-changing XPC commands must reject untrusted local callers. Do not add a localhost or Mach control path that assumes same-user equals trusted.

7. **No string-only path checks.** Governed file access must resolve canonical paths before policy decisions. Symlink, hard-link, and TOCTOU risks are in scope and require tests.

8. **Restore must be conflict-aware.** Do not overwrite newer user work silently. Restore paths must compare current content to expected content and surface conflicts explicitly.

9. **Exposure storage is metadata-first.** Do not casually persist raw content previews, prompts, filenames, paths, or email subjects into analytics or telemetry surfaces.

10. **Always state the boundary honestly.** UI copy, docs, and agent instructions must say "through Manifold" when coverage is partial. Manifold does not claim total control over native Claude/Codex behavior outside the governed path.

## Test Strategy

- **ManifoldKitTests** — unit tests for all stores, engines, and types. These must pass unchanged through the migration. They test the logic, not the transport.
- **New tests for ManifoldRuntime** — test the runtime actor's composition and bridge management. Test `AccessDecision` and `ExposureRecord` creation.
- **New tests for ManifoldXPC** — test the XPC service adapter with an in-process runtime (no actual XPC transport needed for unit tests).
- **Integration verification** — after Phase 8, manual verification per the checklist in `design/RUNTIME-MIGRATION.md`.
