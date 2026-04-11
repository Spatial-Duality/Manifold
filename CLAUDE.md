@AGENTS.md

## Manifold

- Manifold is a macOS SwiftUI app with a SwiftPM runtime stack.
- Main app target: `Manifold` in `Manifold.xcodeproj`.
- Runtime path: app UI -> `ManifoldXPC` -> `ManifoldAgent` -> `ManifoldRuntime` -> stores.
- The app must not open SQLite or build the store graph directly. `ManifoldRuntime` is the single composition root.

## Quality Bar

- Pixelmator Pro is the target bar for quality: calm, native, trustworthy, fast, and hard to break.
- Reliability outranks visual flourish. If the app cannot register its runtime, add folders, or report state honestly, fix that before polish work.
- Desktop UX should feel macOS-native: strong keyboard support, clear selection models, accurate status, dense-but-readable data views, and low-friction commands.
- Never fake connection or activity state. If the runtime is disconnected or uncertain, the UI must say so plainly.

## Current Priority Order

1. Runtime and launch reliability.
   The app currently depends on runtime registration at startup. Work in `ManifoldStore`, `ManifoldAgent`, `ManifoldXPC`, and the bundle/plist path before polishing UI.
2. Truthful state propagation.
   Remove guessed agent state and derive UI connection status from real runtime responses.
3. Main-thread performance.
   Move expensive file walking and content search off the main actor. Avoid full-file reads in UI-facing code paths.
4. Navigation coherence.
   Fix email/files routing so sidebar selection, message state, inspectors, and detail panes always agree.
5. macOS-native surface upgrades.
   Prefer `Table`/better desktop affordances for dense file and activity views where appropriate.
6. Final polish.
   Tighten spacing, hierarchy, and motion only after the flows above are solid.

## Hotspots

- `ManifoldApp/ManifoldApp/Models/ManifoldStore.swift`
- `ManifoldApp/ManifoldApp/Models/AppRuntimeClient.swift`
- `ManifoldApp/ManifoldApp/Views/MainView.swift`
- `ManifoldApp/ManifoldApp/Views/FilesView.swift`
- `ManifoldApp/ManifoldApp/Views/Email/EmailView.swift`
- `ManifoldApp/ManifoldApp/Views/ActivityView.swift`
- `Manifold.xcodeproj/project.pbxproj`
- `Resources/com.spatialduality.manifold.runtime.plist`

## Verification

- Runtime/package changes:
  `env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache swift build`
- Behavior changes:
  `env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache swift test`
- App/UI/Xcode project changes:
  `env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache xcodebuild -project Manifold.xcodeproj -scheme Manifold -configuration Debug -derivedDataPath /tmp/manifold-derived-data build CODE_SIGNING_ALLOWED=NO`
- For launch/runtime fixes, also verify the app can register or start the runtime, not just compile.
- Do not claim success unless you name which verification commands actually ran.

## Workflow

- Use plan mode for multi-file or architecture-heavy work.
- Use the project subagents when the task matches them:
  - `runtime-reliability`
  - `ui-polish`
  - `performance-auditor`
- Use project skills instead of re-explaining the workflow each time:
  - `investigate`
  - `design-review`
  - `plan-eng-review`
  - `health`
  - `review`
  - `quality-upgrade`

## Editing Rules

- Preserve the XPC boundary. New app features should go through `AppRuntimeClient` rather than reaching into runtime internals.
- Keep SwiftUI state ownership narrow. Avoid pushing expensive derived work into `body` or `@MainActor` stores.
- Prefer small, explicit subviews over giant bodies, but do not split files mechanically if it hurts readability.
- When touching launch/runtime setup, explain the end-user behavior being fixed: build success alone is not enough.
