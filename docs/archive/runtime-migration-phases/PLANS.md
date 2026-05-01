# Manifold Runtime Migration — Execution Plan

**Created:** April 11, 2026
**Scope:** Migrate from dual composition roots to single LaunchAgent runtime with XPC clients
**Reference:** `design/RUNTIME-MIGRATION.md` (authoritative spec), `design/WHY-RUNTIME.md` (rationale)

---

## Overview

Manifold currently has two processes that independently make access decisions against the same SQLite file. The app and the MCP server each create their own store graphs. This is the structural defect in a product whose entire value is being the single judge of agent access.

The migration has two cuts:

- **Cut 1 (Phases 1-4):** Fix the trust model. One composition root, delete the duplicate, enforce standing=read-only, add provenance records. The runtime is still in-process.
- **Cut 2 (Phases 5-8):** Harden the lifecycle. XPC transport, LaunchAgent binary, all clients become thin proxies.

Each phase is a standalone task with its own prompt in `codex/tasks/`.

---

## Execution Order

Phases MUST be executed sequentially. Each phase builds on the previous one.

### Cut 1: Fix the Trust Model

| Phase | Task File | Summary | Key Output |
|-------|-----------|---------|------------|
| 1 | `codex/tasks/phase-1-extract-runtime.md` | Create ManifoldRuntime target, move Bridge + Context | New target compiles, `swift build` passes |
| 2 | `codex/tasks/phase-2-delete-second-root.md` | Delete duplicate store creation in app + MCP | Zero `DatabaseConnection(url:)` outside ManifoldRuntime |
| 3 | `codex/tasks/phase-3-enforce-read-only.md` | Standing access = read-only, ApprovalQueue | Write in standing mode → escalation, not a write |
| 4 | `codex/tasks/phase-4-access-exposure-records.md` | AccessDecision + ExposureRecord for every tool call | Every access explained, every exposure recorded |

**Cut 1 checkpoint:** After Phase 4, the trust model is fixed. One runtime, no duplicate stores, standing=read-only, full provenance. The MCP server still runs its own runtime in-process, but it's the same code path. The architectural lie is gone.

### Cut 2: Harden the Lifecycle

| Phase | Task File | Summary | Key Output |
|-------|-----------|---------|------------|
| 5 | `codex/tasks/phase-5-xpc-layer.md` | XPC protocol, service adapter, client | 4-method XPC protocol, async client |
| 6 | `codex/tasks/phase-6-launch-agent.md` | LaunchAgent binary + plist + SMAppService | ManifoldAgent starts via launchd |
| 7 | `codex/tasks/phase-7-thin-mcp-cli.md` | MCP + CLI become XPC clients | manifold-mcp has zero SQLite usage |
| 8 | `codex/tasks/phase-8-app-as-client.md` | App becomes XPC client, delete DistributedNotification | Kill app → agent keeps running → MCP works |

**Cut 2 checkpoint:** After Phase 8, the full architecture is live. One LaunchAgent judge, three XPC clients. Run the verification checklist in `design/RUNTIME-MIGRATION.md`.

---

## Per-Phase Execution Instructions

For each phase:

1. **Read the task file** in `codex/tasks/phase-N-*.md`. It contains Goal, Context, Steps, Constraints, and Done When criteria.
2. **Read `codex/AGENTS.md`** for project conventions, build commands, and hard rules.
3. **Read `design/RUNTIME-MIGRATION.md`** for the relevant phase section — it has code sketches.
4. **Execute the steps** in order. Each step specifies which files to create, move, or modify.
5. **Run `swift build`** after each significant change. Fix errors before proceeding.
6. **Run `swift test`** after completing all steps. All existing tests must pass.
7. **Verify Done When criteria** — every checkbox must be satisfied before the phase is complete.

---

## Reasoning Level Recommendations

| Phase | Reasoning | Why |
|-------|-----------|-----|
| 1 | High | New target creation, file moves, dependency graph — structural decisions |
| 2 | High | Deleting code across many files, changing optionality — subtle breakage risk |
| 3 | Extra-high | Core product invariant — the read-only boundary must be airtight |
| 4 | Extra-high | Instrumentation touches every tool call path — must not break any return values |
| 5 | High | XPC protocol design — @objc constraints, NSXPCInterface compatibility |
| 6 | Medium | Straightforward binary creation + plist |
| 7 | High | Rewriting MCP server core — must preserve exact tool behavior |
| 8 | High | Rewriting app model layer — must handle disconnection gracefully |

---

## Verification Checklist (Post Phase 8)

Run this after all phases are complete:

- [ ] ManifoldAgent registered as LaunchAgent via SMAppService
- [ ] launchd starts ManifoldAgent on login or on first XPC connection
- [ ] launchd restarts ManifoldAgent if it crashes
- [ ] ManifoldAgent owns the single SQLite database
- [ ] App connects to agent via XPC, shows data
- [ ] manifold-mcp connects to agent via XPC, tools work
- [ ] manifold-cli connects to agent via XPC, commands work
- [ ] Two simultaneous MCP connections share state
- [ ] Kill app → agent still running → MCP still works
- [ ] Kill agent → app shows disconnected → launchd restarts → app reconnects
- [ ] Pause agent in app → MCP immediately blocked
- [ ] Write in always-on mode → escalation returned, not a write
- [ ] AccessDecision recorded for every tool call
- [ ] ExposureRecord recorded for every content return
- [ ] explainDecision returns human-readable reason
- [ ] Approval queue persists across agent restarts
- [ ] Close app window → agent keeps running
- [ ] Quit Manifold → agent stops → fail-closed
- [ ] All ManifoldKitTests pass unchanged
- [ ] `swift test` passes
- [ ] `xcodebuild test` passes

---

## File Inventory

### New files created across all phases

```
Sources/ManifoldRuntime/
  ManifoldRuntime.swift          (Phase 1)
  ManifoldServiceAPI.swift       (Phase 1)
  RuntimeTypes.swift             (Phase 1)
  ManifoldBridge.swift           (Phase 1 — moved from ManifoldMCP)
  AgentRuntimeContext.swift      (Phase 1 — moved from ManifoldMCP)
  ApprovalQueue.swift            (Phase 3)

Sources/ManifoldKit/
  AccessDecision.swift           (Phase 4)
  ExposureRecord.swift           (Phase 4)
  ExposureStore.swift            (Phase 4)

Sources/ManifoldXPC/
  ManifoldXPCProtocol.swift      (Phase 5)
  ManifoldXPCService.swift       (Phase 5)
  ManifoldXPCClient.swift        (Phase 5)
  XPCCodingTypes.swift           (Phase 5)

Sources/ManifoldAgent/
  main.swift                     (Phase 6)

Resources/
  com.spatialduality.manifold.runtime.plist  (Phase 6)
```

### Files significantly modified

```
Package.swift                                (Phases 1, 5, 6)
Sources/ManifoldKit/DatabaseMigrator.swift    (Phases 3, 4)
Sources/ManifoldMCP/ManifoldMCPServer.swift   (Phases 2, 7)
Sources/ManifoldMCP/ToolHandlers.swift        (Phases 3, 7)
ManifoldApp/.../ManifoldStore.swift           (Phases 2, 8)
ManifoldApp/.../PolicyModel.swift             (Phases 2, 8)
ManifoldApp/.../SessionModel.swift            (Phases 2, 8)
```

### Files deleted or gutted

```
Sources/ManifoldKit/ManifoldNotifications.swift  (Phase 8 — DistributedNotification removed)
```

### Net impact

- ~1,500 lines new
- ~400 lines deleted (duplicate init, optional guards, notifications)
- ~1,600 lines moved (Bridge + Context → ManifoldRuntime)
