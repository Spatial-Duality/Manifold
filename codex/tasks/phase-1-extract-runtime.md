# Phase 1: Extract ManifoldRuntime Target

## Goal

Create a new `ManifoldRuntime` Swift package target that is the single composition root for all stores. Move `ManifoldBridge.swift` and `AgentRuntimeContext.swift` from `ManifoldMCP` into this new target. Both the app and MCP server will import `ManifoldRuntime` instead of creating stores independently.

## Context

Read `design/RUNTIME-MIGRATION.md` (Phase 1 section) and `design/WHY-RUNTIME.md` for full rationale.

Currently, `ManifoldMCPServer.swift` (lines 25-60) and `ManifoldStore.swift` (lines 122-189) both independently create the full store graph (`DatabaseConnection`, `PolicyStore`, `GrantStore`, `AuditStore`, `SnapshotStore`, `ContentStore`, `WorkBlockStore`, `EmailStore`, `ArtifactIndex`) against the same SQLite file. This is the architectural defect. The `ManifoldRuntime` actor will be the one place where stores are created.

### Key existing files

- `Sources/ManifoldMCP/ManifoldBridge.swift` (~1467 lines) — core decision engine, must MOVE to `Sources/ManifoldRuntime/`
- `Sources/ManifoldMCP/AgentRuntimeContext.swift` (~80 lines) — connection metadata, must MOVE to `Sources/ManifoldRuntime/`
- `Sources/ManifoldKit/` — all store actors (`PolicyStore`, `GrantStore`, `WorkBlockStore`, `ContentStore`, `SnapshotStore`, `AuditStore`, `EmailStore`, `ArtifactIndex`, `WorkspaceLeaseManager`, `EmailSyncEngine`, `DatabaseConnection`, `DatabaseMigrator`)
- `Package.swift` — currently has 3 targets: `ManifoldKit`, `ManifoldMCP`, `ManifoldCLI`

## Steps

1. Create directory `Sources/ManifoldRuntime/`.

2. Move `Sources/ManifoldMCP/ManifoldBridge.swift` → `Sources/ManifoldRuntime/ManifoldBridge.swift`. Update its `import` statements: it should `import ManifoldKit` (not rely on being in the ManifoldMCP target).

3. Move `Sources/ManifoldMCP/AgentRuntimeContext.swift` → `Sources/ManifoldRuntime/AgentRuntimeContext.swift`. Same import fix.

4. Create `Sources/ManifoldRuntime/ManifoldRuntime.swift` — the actor that owns all stores. Reference the code sketch in `design/RUNTIME-MIGRATION.md` Phase 1. The actor must:
   - Accept an optional `storeURL` parameter (default: `~/Library/Application Support/Manifold/store`)
   - Create `DatabaseConnection`, run `DatabaseMigrator`, then create all stores in order
   - All store properties are `public let` (non-optional, fail-fast)
   - Manage a dictionary of `ManifoldBridge` instances keyed by `connectionID`
   - Provide `bridge(for:targetApp:version:)` and `removeBridge(_:)` methods

5. Create `Sources/ManifoldRuntime/ManifoldServiceAPI.swift` — the protocol defining the product-vocabulary API. Copy from `design/RUNTIME-MIGRATION.md` "The Service Protocol" section.

6. Create `Sources/ManifoldRuntime/RuntimeTypes.swift` — result types used by the service API (`RuntimeStatus`, `TrustedFolder`, `FileEntry`, `FileContent`, `SearchHit`, `FileMetadata`, `WriteResult`, `TrackedRun`, `PromotionPreview`, `PromotionResult`, `ChangeEntry`, `EmailEntry`, `EmailContent`, `RevealResult`, `SessionEntry`, `SessionDetail`, `ApprovalRequest`, `AccessExplanation`, `ExposureEntry`, `AuditEntry`, `FileScope`). These are `Sendable` structs. They should be thin — just what's needed for the protocol boundary. Many can wrap existing ManifoldKit types.

7. Update `Package.swift`:
   - Add `.target(name: "ManifoldRuntime", dependencies: ["ManifoldKit"], path: "Sources/ManifoldRuntime")`
   - Update `ManifoldMCP` dependencies: `["ManifoldKit", "ManifoldRuntime"]`
   - Update `ManifoldCLI` dependencies: `["ManifoldKit", "ManifoldRuntime"]`
   - Update `ManifoldKitTests` dependencies: `["ManifoldKit", "ManifoldMCP", "ManifoldRuntime"]`

8. Fix any remaining import/visibility issues. `ManifoldBridge` may reference types that were internal to ManifoldMCP — make them `public` in ManifoldKit or ManifoldRuntime as needed.

## Constraints

- Swift 6 strict concurrency. `ManifoldRuntime` must be an `actor`. All store properties are non-optional.
- Do NOT modify `ManifoldStore.swift` or `ManifoldMCPServer.swift` in this phase. They will be updated in Phase 2. For now, the MCP server can continue creating its own stores — the goal of this phase is just to get the new target compiling and the files moved.
- Do NOT modify any existing ManifoldKit store files.
- Do NOT modify existing tests. They must pass as-is.
- `ManifoldBridge` is an `actor` — it stays an actor after the move.
- Logger subsystem: `"com.spatialduality.manifold"`, category: `"runtime"`.

## Done When

- [ ] `Sources/ManifoldRuntime/` exists with: `ManifoldRuntime.swift`, `ManifoldServiceAPI.swift`, `RuntimeTypes.swift`, `ManifoldBridge.swift`, `AgentRuntimeContext.swift`
- [ ] `Sources/ManifoldMCP/ManifoldBridge.swift` and `Sources/ManifoldMCP/AgentRuntimeContext.swift` no longer exist
- [ ] `Package.swift` has the `ManifoldRuntime` target with correct dependencies
- [ ] `swift build` succeeds with zero errors
- [ ] `swift test` passes — all existing `ManifoldKitTests` pass unchanged
- [ ] `ManifoldRuntime` actor can be instantiated with a test URL and all stores are non-nil
