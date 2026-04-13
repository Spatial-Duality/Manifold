# Phase 2: Delete the Second Composition Root

## Goal

Make both the SwiftUI app and the MCP server use `ManifoldRuntime` as their single source of stores. Delete all duplicate store creation. Make all store references non-optional throughout the app's model layer.

## Context

Read `design/RUNTIME-MIGRATION.md` (Phase 2 section).

Phase 1 created the `ManifoldRuntime` actor and moved `ManifoldBridge` into it. But right now, `ManifoldStore.swift` and `ManifoldMCPServer.swift` still create their own stores independently. This phase eliminates both independent composition roots.

### Key files to modify

- `ManifoldApp/ManifoldApp/Models/ManifoldStore.swift` (~697 lines) — the app's composition root. Has `initStores()` (lines ~122-189) that creates all stores. Has optional store properties (`auditStore?`, `snapshotStore?`, etc.) and `reinjectStores()` for async re-initialization. All of this must be replaced with a single `ManifoldRuntime` reference.

- `ManifoldApp/ManifoldApp/Models/PolicyModel.swift` (~239 lines) — every method has `guard let store = policyStore else { return }`. Must become non-optional.

- `ManifoldApp/ManifoldApp/Models/SessionModel.swift` (~809 lines) — same optional guard pattern. Must become non-optional.

- `Sources/ManifoldMCP/ManifoldMCPServer.swift` (~200 lines) — lines 25-60 create a full store graph. Replace with `ManifoldRuntime` import and usage.

- Other app models that may have optional store patterns: `HistoryModel.swift`, `StorageModel.swift`, `EmailAccountModel.swift` — check each and fix.

## Steps

### MCP Server

1. Open `Sources/ManifoldMCP/ManifoldMCPServer.swift`.
2. Delete all direct store creation (the block that creates `DatabaseConnection`, `DatabaseMigrator`, `ContentStore`, `AuditStore`, `SnapshotStore`, `GrantStore`, `EmailStore`, `ArtifactIndex`, `PolicyStore`, `WorkBlockStore`, and the `ManifoldBridge` constructor).
3. Replace with: `let runtime = try ManifoldRuntime()` and get the bridge from it.
4. The MCP server creates a `ManifoldRuntime` in-process for now (temporary — Phase 7 replaces this with XPC). This is acceptable as a transition state.

### App ManifoldStore

1. Open `ManifoldApp/ManifoldApp/Models/ManifoldStore.swift`.
2. Add `import ManifoldRuntime` (you'll need to add ManifoldRuntime as a dependency in the Xcode project's package dependencies).
3. Add a non-optional property: `let runtime: ManifoldRuntime`.
4. In `init()`, create the runtime: `self.runtime = try ManifoldRuntime()`. If this fails, the app should crash on launch — fail-fast, not fail-silent.
5. Delete `initStores()` and `reinjectStores()`.
6. Delete all optional store properties (`var auditStore: AuditStore?`, etc.).
7. Configure sub-models directly: `policyModel.configure(policyStore: runtime.policyStore, workBlockStore: runtime.workBlockStore, grantStore: runtime.grantStore)`.
8. Any place that accessed `self.auditStore` should now access `runtime.auditStore`.

### PolicyModel

1. Open `ManifoldApp/ManifoldApp/Models/PolicyModel.swift`.
2. Change `private var policyStore: PolicyStore?` to `private var policyStore: PolicyStore!` or better: pass it in `configure()` and make it a non-optional `let` set once.
3. Remove all `guard let store = policyStore else { return }` patterns. Replace with direct usage.
4. Same for `workBlockStore` and `grantStoreRef`.

### SessionModel

1. Open `ManifoldApp/ManifoldApp/Models/SessionModel.swift`.
2. Same pattern: make all store references non-optional.
3. Remove all optional guards.
4. The `configure()` method should take non-optional stores and set them once.

### Other Models

1. Check `HistoryModel.swift`, `StorageModel.swift`, `EmailAccountModel.swift` for the same optional store pattern.
2. Fix each: non-optional stores, no optional guards.

## Constraints

- Swift 6 strict concurrency. `ManifoldRuntime` is an actor — accessing its properties requires `await` from non-isolated contexts. The `@MainActor` models will need to call into the runtime asynchronously.
- The app must still compile and launch. If `ManifoldRuntime()` throws, crash immediately — `try!` or `fatalError` is acceptable here because if the database can't initialize, the app has nothing to show.
- Do NOT change `ManifoldBridge` logic. Do NOT change store logic. Only change who creates them and how they're referenced.
- Do NOT add XPC yet — that's Phase 5+.
- Existing tests must pass. If `ManifoldKitTests` import `ManifoldMCP` and expect `ManifoldBridge` there, update the test import to `ManifoldRuntime`.

## Done When

- [ ] `ManifoldMCPServer.swift` has zero direct store creation — uses `ManifoldRuntime`
- [ ] `ManifoldStore.swift` has zero direct store creation — uses `ManifoldRuntime`
- [ ] `ManifoldStore.swift` has zero optional store properties
- [ ] `PolicyModel.swift` has zero `guard let store` patterns
- [ ] `SessionModel.swift` has zero `guard let store` patterns
- [ ] No file outside `ManifoldRuntime.swift` calls `DatabaseConnection(url:)` directly
- [ ] `swift build` succeeds
- [ ] `swift test` passes
- [ ] App compiles (check with `xcodebuild build` if available)
- [ ] MCP server starts without errors (run `swift run manifold-mcp --version` to verify it links)
