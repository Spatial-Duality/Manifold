@.claude/rules/skill-routing.md
@.claude/rules/verification.md

# Working on Manifold with Claude Code

This file is read into every session. Keep it tight.

## What Manifold is

A native macOS app + local runtime that gives Claude / Codex / Cowork controlled access to chosen files and emails through a single governed path, with a real audit trail and reviewable edits in tracked workspaces. The product **is** the trust boundary; everything else flows from that.

## Hard rules (don't break these)

1. **`ManifoldRuntime` is the single composition root.** The app, MCP, and CLI must not open SQLite or build the store graph themselves. New app features go through `AppRuntimeClient`, not into runtime internals.
2. **Standing access = read; Tracked Work Block = write.** Don't quietly add a write path to standing access. If a feature needs writes, it goes through a Tracked Work Block.
3. **Never fake connection or activity state.** If the runtime is disconnected, uncertain, or returned an error, the UI must say so plainly. No optimistic placeholders that imply the runtime is healthy when it isn't.
4. **Verified identity, not declared identity.** Agent identity in `RuleEngine` comes from `SignedProcessVerifier` / `ClientIdentityVerifier`, never the self-reported label.
5. **No GitHub Actions, workflows, dependabot, or CODEOWNERS.** Manual push-and-verify only. Don't propose them.
6. **Don't claim success without naming the verification commands you ran.** Compilation alone is not verification of behavior.
7. **Leave `unsort/` alone unless explicitly asked.** It's a personal scratch dropzone; tools must not auto-touch, organize, move, or commit anything inside it.

## Quality bar

Pixelmator Pro: calm, native, trustworthy, fast, hard to break. Reliability outranks visual polish. macOS-native means strong keyboard support, clear selection models, accurate status, dense-but-readable data views, low-friction commands. If the app can't register its runtime, add folders, or report state honestly, fix that before any polish work.

## Architecture cheat-sheet

```
SwiftUI app (ManifoldApp/) ──► AppRuntimeClient ──► ManifoldXPC ──► ManifoldAgent (LaunchAgent) ──► ManifoldRuntime ──► Stores
                                                                          ▲
manifold-mcp / manifold-cli ──────────────────────────────────────────────┘  (XPC clients, no stores)
```

- `Sources/ManifoldKit/` — types, stores, SQLite, content storage, snapshot store, email index
- `Sources/ManifoldRuntime/` — runtime actor, composition root, RuleEngine, ManifoldBridge
- `Sources/ManifoldXPC/` — XPC protocol + service + client + coding types
- `Sources/ManifoldAgent/` — LaunchAgent binary entry point
- `Sources/ManifoldMCP/` — thin MCP server (XPC client; no stores)
- `Sources/ManifoldCLI/` — thin CLI (XPC client; no stores)
- `ManifoldApp/ManifoldApp/` — SwiftUI app (XPC client; no stores)
- `Tests/ManifoldKitTests/` — SwiftPM tests
- `ManifoldAppTests/` + `ManifoldAppUITests/` — Xcode tests

## Hotspots (where bugs cluster)

- `ManifoldApp/ManifoldApp/Models/ManifoldStore.swift`
- `ManifoldApp/ManifoldApp/Models/AppRuntimeClient.swift`
- `ManifoldApp/ManifoldApp/Views/MainView.swift`
- `ManifoldApp/ManifoldApp/Views/FilesView.swift`
- `ManifoldApp/ManifoldApp/Views/Email/EmailView.swift`
- `ManifoldApp/ManifoldApp/Views/ActivityView.swift`
- `Manifold.xcodeproj/project.pbxproj`
- `project.yml` (XcodeGen source of truth — regenerate the .xcodeproj from this when targets/sources change)
- `Resources/com.spatialduality.manifold.runtime.plist`

## Verification commands (copy-paste)

```bash
# Runtime / package changes
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
    swift build

# Behavior changes
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
    swift test

# App / UI / Xcode project changes
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
    xcodebuild -project Manifold.xcodeproj \
               -scheme Manifold \
               -configuration Debug \
               -derivedDataPath /tmp/manifold-derived-data \
               build CODE_SIGNING_ALLOWED=NO
```

For launch/runtime fixes, also verify the app actually registers or starts the runtime — not just that it compiles.

## Workflow primitives

- **Plan mode** for multi-file or architecture-heavy work. Don't start editing six files until the user has seen the plan.
- **Subagents** when the task matches: `runtime-reliability`, `ui-polish`, `performance-auditor`.
- **Skills** instead of re-explaining the workflow: `investigate`, `design-review`, `plan-eng-review`, `health`, `review`, `quality-upgrade`. See `.claude/rules/skill-routing.md` for routing rules.
- **TodoWrite** for any task with three or more steps; mark progress honestly.
- **AskUserQuestion** when the request is underspecified — don't guess between two viable approaches.

## Editing rules

- Preserve the XPC boundary. App features go through `AppRuntimeClient`.
- Keep SwiftUI state ownership narrow. Don't push expensive derived work into `body` or `@MainActor` stores.
- Move file walking, content search, and other expensive I/O off the main actor. Avoid full-file reads in UI-facing code paths.
- Prefer small explicit subviews over giant bodies — but don't split mechanically if it hurts readability.
- When touching launch/runtime setup, explain the end-user behavior being fixed; build success alone isn't enough.

## Repo conventions (post-2026-05-01 reorg)

- `docs/` = canonical contributor and user docs. `docs/archive/` = history, don't rewrite.
- `DESIGN.md` (root) = canonical design system. `ARCHITECTURE.md` (root) = deep architecture reference. `docs/architecture.md` = outsider-friendly view.
- `brand/` = mark and brand assets. The PNG at `brand/Icon/Icon Exports/Icon-macOS-Default-256x256@1x.png` is README-load-bearing — don't move or rename without updating `README.md`.
- `scripts/` (plural) = all shell and Python helpers. There is no `script/` directory anymore.
- `Resources/` (root) holds the LaunchAgent plist, referenced by `project.yml`'s post-build script. Don't move it without updating that script.
- `unsort/` = personal scratch dropzone. **Gitignored. Hands off unless asked.**
- AI-tool configs (`.claude/`, `.codex/`, `codex/`, `CLAUDE.md`, `AGENTS.md`, `TODOS.md`) are local-only and gitignored. They never ship in the public repo.

## Current priority order (May 2026, pre-OSS-launch)

1. **Runtime and launch reliability** — runtime registration at startup, `ManifoldStore`, `ManifoldAgent`, `ManifoldXPC`, bundle/plist path. Fix this before any polish.
2. **Truthful state propagation** — derive UI connection status from real runtime responses; remove any guessed state.
3. **Main-thread performance** — move expensive file walking and content search off the main actor.
4. **Navigation coherence** — email/files routing so sidebar, message state, inspectors, and detail panes always agree.
5. **macOS-native surface upgrades** — `Table` and proper desktop affordances for dense file/activity views.
6. **Final polish** — spacing, hierarchy, motion. Only after the above are solid.

## User preferences

- Be deeply honest and critical. Apply real logic, not flattery.
- Think about second- and third-order effects. "Show me the incentive and I'll tell you the outcome."
- Terse responses. Prose over bullet salad. No trailing summaries the user can read in the diff.
- When wrong, own it; don't collapse into apology theatre.
