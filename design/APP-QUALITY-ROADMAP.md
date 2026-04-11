# App Quality Roadmap

## Target

Raise Manifold from a promising internal-tool-feeling app to a pro macOS app with a Pixelmator Pro-level quality bar.

## Current Grade

- Overall: `C+`
- Concept: `A-`
- Desktop ambition: `B`
- Visual consistency: `B-`
- Interaction coherence: `C+`
- Reliability and trust: `C`
- Performance headroom: `C`

## Phase Order

### Phase 1: Runtime reliability

Fix the flows that currently make the product feel breakable.

Primary goals:

- Launch/runtime registration works in both installed and dev builds.
- Folder-add and other runtime-dependent flows fail less, and fail clearly when they do.
- The app reports runtime connectivity honestly.

Hotspots:

- `ManifoldApp/ManifoldApp/Models/ManifoldStore.swift`
- `ManifoldApp/ManifoldApp/Models/AppRuntimeClient.swift`
- `Sources/ManifoldAgent/**/*.swift`
- `Sources/ManifoldXPC/**/*.swift`
- `Resources/com.spatialduality.manifold.runtime.plist`
- `Manifold.xcodeproj/project.pbxproj`

Acceptance criteria:

- The app can start and talk to the runtime in normal development workflows.
- Adding a folder succeeds when the runtime is healthy.
- When the runtime is not healthy, the user gets a truthful disconnected/error state.
- Connection badges do not derive from guessed agent focus.

### Phase 2: Main-thread performance

Remove the most obvious responsiveness risks.

Primary goals:

- File walking and content search do not run on the main actor.
- Large repos do not freeze the app during search or reload.
- Expensive refresh paths are narrowed and debounced intentionally.

Hotspots:

- `ManifoldApp/ManifoldApp/Models/ManifoldStore.swift`
- `ManifoldApp/ManifoldApp/Views/FilesView.swift`
- `ManifoldApp/ManifoldApp/Views/ActivityView.swift`

Acceptance criteria:

- Content search runs off the UI thread.
- File enumeration and search are cancellable where practical.
- Repeated selection or filter changes do not cause obvious hitching.

### Phase 3: Navigation coherence

Fix places where the UI can route users to the wrong content.

Primary goals:

- Email account selection maps to the expected account and mailbox state.
- Files, inspectors, and activity panes keep one clear source of truth.
- No sidebar action should silently land in unrelated content.

Hotspots:

- `ManifoldApp/ManifoldApp/Views/MainView.swift`
- `ManifoldApp/ManifoldApp/Views/Email/EmailView.swift`
- `ManifoldApp/ManifoldApp/Views/Email/Sidebar/**/*.swift`
- `ManifoldApp/ManifoldApp/Views/FilesView.swift`

Acceptance criteria:

- Clicking an email account selects that account, not an arbitrary default.
- Selection state is stable across reloads.
- Inspector/detail panes follow the selected object consistently.

### Phase 4: Desktop-native surface upgrades

Make dense workflows feel like a serious Mac app.

Primary goals:

- Improve files/activity presentation for scanability and control.
- Tighten command/menu/toolbar behavior.
- Increase clarity of status and action affordances.

Hotspots:

- `ManifoldApp/ManifoldApp/Views/FilesView.swift`
- `ManifoldApp/ManifoldApp/Views/ActivityView.swift`
- `ManifoldApp/ManifoldApp/Views/MainView.swift`
- `ManifoldApp/ManifoldApp/Views/CommandPaletteView.swift`

Acceptance criteria:

- Data-heavy views use appropriately desktop-native components.
- Keyboard and command workflows feel first-class.
- Important status is obvious without being noisy.

### Phase 5: Final polish

Only after the earlier phases are solid.

Primary goals:

- Refine spacing, hierarchy, copy, and motion.
- Remove any remaining “tool UI” roughness.
- Improve empty states and onboarding clarity.

Hotspots:

- `ManifoldApp/ManifoldApp/Views/OverviewView.swift`
- `ManifoldApp/ManifoldApp/Views/Setup/SetupAssistantView.swift`
- `ManifoldApp/ManifoldApp/Views/MenuBar/MenuBarPanelView.swift`
- `ManifoldApp/ManifoldApp/Components/**/*.swift`

Acceptance criteria:

- The app feels calm and deliberate.
- Empty states guide the user without hand-waving around broken flows.
- Visual polish supports trust rather than masking instability.

## Non-Negotiables

- The app remains an XPC client and does not reopen the database directly.
- `ManifoldRuntime` stays the single store composition root.
- The app never claims an agent is connected unless that is actually true.
- Verification must include `xcodebuild` for UI/app changes, not just `swift build`.

## Verification Commands

```bash
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
swift build
```

```bash
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
swift test
```

```bash
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
xcodebuild -project Manifold.xcodeproj -scheme Manifold \
  -configuration Debug \
  -derivedDataPath /tmp/manifold-derived-data \
  build CODE_SIGNING_ALLOWED=NO
```
