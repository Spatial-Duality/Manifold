# Manifold menu-bar panel — Swift design spike

## What this is

A single-file SwiftUI spike of the redesigned menu bar panel. Replaces the
Stage-4 HTML mockup, which couldn't carry the materials, SF Symbols, depth,
and native chrome the real product needs. Use this to iterate on the visual
design in Xcode's preview canvas — not as production code yet.

**File:** `ManifoldMenuBarPanel.swift`

## What it covers

All four menu-bar states from the Stage-3/6/8 design decisions:

1. **Idle (empty)** — first-run state; nothing shared, warm-but-neutral copy.
2. **Idle with recent sessions** — after first session; one-click reload list.
3. **Active with queue** — agent running, session live, pending requests.
4. **Tracked edit in progress** — session with writes tracked + reversible.

Each state has its own `#Preview` entry; a fifth preview renders all four
side-by-side for reviewing density and rhythm.

## How to preview it

Drop the file into an Xcode project (macOS 14+, Xcode 15+):

```
File → Add Files to "Manifold"… → ManifoldMenuBarPanel.swift
```

Open the file, show the canvas (`⌥⌘↵`), and step through the `#Preview`
entries via the preview picker at the top. No project changes needed — the
file is self-contained with a mock state model (`MenuBarMockState`) so it
renders without any Manifold dependencies.

For dark-mode review, flip the preview appearance in the canvas toolbar.
For reduce-motion review, toggle it in System Settings → Accessibility →
Display → Reduce Motion.

## What's mocked (and why)

The spike deliberately does **not** talk to `ManifoldStore`. It declares a
local `@Observable` class `MenuBarMockState` that exposes the same fields
the real panel will consume. This keeps the visual design separable from
store-plumbing decisions, and lets the design iterate before store types
are finalized.

Wire-up checklist for when the design is accepted:

1. **Delete** `MenuBarMockState`.
2. **Replace** `state: MenuBarMockState` with `store: ManifoldStore`
   (via `@Environment(ManifoldStore.self)`).
3. **Add** these store/model extensions that the current `PolicyModel`
   does not yet have — they correspond to the Stage-6 session primitive:
   - `ManifoldStore.activeSession: SessionRecord?`
   - `ManifoldStore.recentSessions: [SessionRecord]` (for reload list)
   - `ManifoldStore.pendingRequests: [ApprovalRequest]` (queue)
   - `SessionRecord.isTrackedEdit: Bool`
   - `ApprovalRequest` type: agent, headline, target path, context string
4. **Replace** the headline copy computation. The spike's `headlinePrimary`
   / `headlineSecondary` are hard-coded; in the real view they derive from
   store state. Keep the user-as-subject voice (Principle 5, Stage 5):
   *"You've shared…"*, not *"Claude can see…"*.
5. **Wire** the footer actions to real methods: `store.policy.pauseAllAgents()`,
   `store.quitManifold()`, `NSApp.sendAction(Selector(("showSettingsWindow:"))…)`,
   session-start sheet presentation, etc.
6. **Guard Quit** when any agent is active or tracked edit is live.
   The existing `MenuBarPanelView.swift` does not guard this; critique §10.

## Design decisions visible in the code

Each is traceable to the docs in `design/`:

- **Fixed agent palette.** `Color.manifoldClaude` / `.manifoldCodex` are
  hand-picked with light/dark variants via a dynamic `NSColor` provider.
  Does not track the user's system accent. (Principle 6, Stage 2.)
- **Session chip / tracked-edit strip.** Distinct visual treatments for
  regular sessions vs write-tracked sessions. Different background tint,
  different icon. (Stage 6.)
- **User-as-subject headline.** Every state's primary sentence makes the
  user the grammatical actor when describing shared state; the agent is
  only the subject when describing what it did. (Stage 5.)
- **Pulse halo on active dot.** Uses a SwiftUI `repeatForever` ease-out
  animation on the halo scale + opacity. Respects `accessibilityReduceMotion`
  — completely suppressed in that mode. (Principle 9.)
- **Focused default on approvals.** "Not this time" is `.borderedProminent`
  and carries `.keyboardShortcut(.defaultAction)`. Return triggers deny,
  not approve. (Principle 3 + Johnny.)
- **Session-only button appears conditionally.** The "Session" approval
  button is rendered only when `sessionLive == true`. No greyed-out dead
  affordances. (Cooper.)
- **Monospaced digits for counts & durations.** Every number in the UI
  — pending count, countdown, session duration — uses `.monospacedDigit()`.
  (Hochuli / Bringhurst; Principle 7.)
- **Real material backing.** `.regularMaterial` on the panel body; the
  shadow stack is two layers (soft + tight) matching Apple HIG for popover
  elevation.
- **SF Symbols everywhere.** `timeline.selection` (tracked edit),
  `arrow.uturn.backward.circle` (reload), `folder.badge.plus` (add folder),
  `envelope.badge` (add mailbox), `sparkle` (Claude), `chevron.left.forwardslash.chevron.right` (Codex), `pause.circle`, `power`. No emoji.

## What it does NOT cover (explicit)

- **Real `ManifoldStore` wiring.** Spike only; data is synthetic.
- **Menu-bar status-item icon itself.** The four-state icon (idle / active /
  attention / stopped) from Stage 3 §H is separate from this panel; it lives
  in the `NSStatusItem` template image, not in the SwiftUI view.
- **Start-session sheet.** That's a separate surface; see `session-start.html`
  for the structure; needs its own Swift spike.
- **Error banner.** Runtime-disconnect state still needs an explicit copy +
  visual pass; the current spike just dims the dot.
- **Dynamic Type scaling audit.** Rendered at default type size; larger
  sizes need a review pass before ship.

## Verification

Cannot run `swift build` inside this session's sandbox (no Swift toolchain
present). The user should verify on their machine with:

```
# Minimal — compile-check only, in a scratch package:
mkdir /tmp/menubar-spike && cd /tmp/menubar-spike
cat > Package.swift <<'EOF'
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "MenuBarSpike",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MenuBarSpike", targets: ["MenuBarSpike"])],
    targets: [.target(name: "MenuBarSpike", path: "Sources")]
)
EOF
mkdir -p Sources/MenuBarSpike
cp ~/path/to/Manifold/design/swift-spike/ManifoldMenuBarPanel.swift Sources/MenuBarSpike/
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
    swift build
```

Or just add the file to the main Manifold Xcode project and open the
canvas — compilation errors will surface there with full diagnostics.

## Next surfaces to spike

In decreasing order of leverage:

1. **Session-start sheet** — small, high-reuse pattern.
2. **Activity (Ledger)** — most-invested surface; best to prototype the
   three-pane + sparkline rail with real SwiftUI `Table` + `Chart` so we
   learn what macOS gives us for free.
3. **Mail** — Active-Backup-style dense table; will reveal whether
   SwiftUI `Table` can carry the density or if we need a custom `NSTableView`
   bridge. Important architectural probe.
4. **Access** — coverage matrix; likely a `Table` with custom cells.

Recommend spiking #1 + #2 next. The rest can wait until those two lock
the chrome language.
