# 12 — The Ive/Jobs-level review

A meticulous review of Manifold's post-migration codebase against the
quality bar set by Raycast, Apple's own apps (Music, Notes, Mail, Settings,
Reminders), and the explicit principles in `02-posture-and-principles.md`.

I held the code to the `.claude/skills/design-review/SKILL.md` scorecard:
reliability, navigation coherence, macOS-native fit, information density,
performance, visual polish. Each issue is anchored to a file and line, and
ordered by load-bearing impact, not by surface area.

The short summary, in Jobs's voice: *the bones are good. The finishes are
not yet at the bar of the products it wants to sit next to.* We shipped a
consistent concept and then stopped polishing before the concept reads on
the screen.

Overall grade: **B / B+**. Strong architecture, strong empty-state copy,
honest status. The polish gap is in motion, selection affordances,
duplicated chrome, and one Stage-2 rename that never finished.

---

## 1. Reliability and trust

### 1.1 The WorkBlock → Session rename is half-done — and it leaks into the UI layer

148 references to `workBlock` / `WorkBlock` remain across the app and
runtime, in 18 files including `MenuBarPanelView.swift:78`, `PolicyModel.swift`,
`ManifoldStore.swift`, `AppRuntimeClient.swift`, and the Intents surface.
This is not a cosmetic issue; the MenuBar panel literally calls
`store.policy.loadActiveWorkBlock()` on every open. If an exception surfaces
to the user — a refresh failure, a launch log — the vocabulary on screen
will split between "session" (the product term) and "work block" (the
internal term).

**Impact:** Cracks the trust model. If I'm telling a user "your session is
live" but the error dialog names a "work block," they correctly conclude
that the app is a skin over some other abstraction. Jobs called this
*seams*. Ive calls it *product lying to itself*.

**Fix (phase-10, day one):** A single rename PR with three scopes:
1. Persisted schema stays `WorkBlockRecord` on disk (no migration risk) —
   but every call-site above the runtime speaks `Session`.
2. `ManifoldKit` gets a `SessionRecord` typealias/wrapper and deprecates
   the name `WorkBlockRecord` in the app-facing API.
3. Every `loadActiveWorkBlock`, `finishWorkBlock`, `pauseWorkBlock` is
   renamed. 148 touchpoints is a day's careful work.

### 1.2 `ManifoldStore.selectedTab` / `AgentFocus` are dead skin

`ManifoldStore.swift:54–55`:

```swift
var selectedTab: AppTab = .overview
var agentFocus: AgentFocus = .claude
```

The new Ledger navigation is owned by `LedgerDestination` inside
`LedgerWindowView`. `selectedTab` survives for **test fixtures**
(`ManifoldApp.swift:107`) and for `GeneralSettingsPane.swift:31–33`.

**Impact:** The store has two navigation models. A naive developer adding
a new surface doesn't know which one is authoritative. Worse: the fixture
path (`store.selectedTab = .emails`) bootstraps tests that will silently
diverge from runtime behavior once the fixture drops.

**Fix:** Delete `selectedTab`, `AppTab`, `AgentFocus.compare`, and the
fixture overrides. If anything in Settings depends on a "focus" concept
post-redesign, introduce a clean name (`AgentSettingsFocus`) scoped to
Settings only.

### 1.3 `AIAppsSettingsPane` never became `AgentsSettingsPane`

`Views/Settings/AIAppsSettingsPane.swift` still exists. The word "AI apps"
appears nowhere else in the post-migration vocabulary. Settings is where
users look to verify their mental model; a stale noun here is a confidence
leak.

**Fix:** Rename file + type + every call-site. Trivial.

### 1.4 `LiveCheckRow` is documented as a shim

`Setup/ConnectClaudeSheet.swift` and `ConnectCodexSheet.swift` still rely
on `LiveCheckRow`. A shim is fine in a migration, but it should have a
deprecation plan pinned to it. Today it has none.

**Fix:** Add a `// TODO(phase-10): replace with IntegrationHealthRow` in
each reference, or inline and delete.

---

## 2. Navigation coherence

### 2.1 Three surfaces carry identical tab bars — written three times

`AccessWindowView.AccessTabBar`, `MailWindowView.MailTabBar`, and
`RulesWindowView.RulesTabBar` are the same component: capsule buttons,
`claudeSoft` selected fill, `border` unselected stroke, 0.6-pt border,
identical padding. Cumulative ~135 lines of duplicated styling.

Worse: because they're three separate types, a change to the selection
affordance has to be made in three places. This is the classic Ive test —
*you made the component three times? It wasn't a component.*

**Fix:** Introduce `Components/Primitives/SegmentedTabBar.swift`:

```swift
struct SegmentedTabBar<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> (String, String)           // title, systemImage
    var enabled: (Item) -> Bool = { _ in true }
    var trailing: (() -> AnyView)? = nil
}
```

All three surfaces become five-line call-sites. The `trailing:` closure is
where Rules parks its "Preview rule…" button.

### 2.2 The sidebar has no ⌘1–⌘5 shortcuts

Every serious macOS app with sidebar navigation — Music, Photos, Mail,
Reminders, Notion, Obsidian, Linear, Raycast — binds Cmd-N to the nth
sidebar item. Manifold does not.

`ManifoldApp.swift:36–83` wires menu-bar commands but none of them drive
`LedgerDestination`.

**Impact:** The Ledger is positioned as a five-way evidence lens. On
keyboard it's a dead-end.

**Fix:** Add a `CommandGroup(replacing: .sidebar)` that emits five buttons
posting `manifoldShowLedgerDestination` with each destination's rawValue,
bound to ⌘1–⌘5.

### 2.3 Tabs inside surfaces have no sub-shortcuts

Once inside Access or Mail, there's no keyboard way to hop between
Folders / Files / Session / History. On the Mac, the convention is
Cmd-Option-Arrow (Mail, Music) or Cmd-digit (Photos).

**Fix:** Bind Cmd-Option-Left/Right at the window level when a tabbed
surface is active, cycling `AccessWindowView.Tab` / `MailWindowView.Tab`.

### 2.4 `FoldersMatrixView` carries dead code

Lines 127–192 define `FoldersInspector` and `AgentScopeRow` — neither is
referenced; the used inspector is `FileTreeInspector`. This is a merge
artifact from the design cycle, not a "wait and see" decision.

**Fix:** Delete both. Leaves the matrix view at ~90 lines and honest about
its dependencies.

### 2.5 Mail's `MailSessionView` and `MailHistoryView` are hidden inside `ThreadsView.swift`

`ThreadsView.swift` is 714 lines because it carries the scope rail, thread
toolbar, content area, thread group row, message row, inspector, *and*
both `MailSessionView` and `MailHistoryView`. The design plan called for
separate files.

**Impact:** Not a bug; a productivity tax. A developer wanting to change
"what the Session tab shows" has to scroll through a nearly-unrelated
thread renderer. Reviews on a PR are painful.

**Fix:** Extract `MailSessionView.swift` (~60 lines) and
`MailHistoryView.swift` (~80 lines) into their own files under `Views/Mail/`.

---

## 3. macOS-native fit

### 3.1 `Color.accentColor` leaks through Principle 6

`CommandPaletteView.swift:127`:
```swift
.background(highlighted ? Color.accentColor.opacity(0.12) : Color.clear)
```

`Components/ActionFormatting.swift:33`:
```swift
case "mcp_connection": .accentColor
```

Principle 6 (02-posture-and-principles.md) says: fixed Manifold palette,
never system accent. These two bleed the system accent into the brand.
Worse: the command palette is the highest-frequency Manifold surface
(Cmd-K).

**Fix:** Replace with `ManifoldPalette.claude.opacity(0.14)` plus a 1-pt
leading-edge accent stripe (Raycast pattern). The stripe gives you the
*visible focus* that `opacity(0.12)` lacks anyway.

### 3.2 The Claude color is being used as a generic "selected" accent

`grep` finds `ManifoldPalette.claude` or `.claudeSoft` used as selection
tint in:

- `ActivityWindowView.swift:107–113` (filter chips)
- `AccessWindowView.swift:80–93` (tab bar)
- `MailWindowView.swift:100–113` (tab bar)
- `RulesWindowView.swift:164–177` (tab bar)
- `Rules/RulesWindowView.swift:205, 218` (preview banner)
- `Mail/ThreadsView.swift:153, 170, 421` (rail buttons, selected thread)
- `ActivityWindowView.swift:107` (filter selected state)

Claude is an *agent identity*. Filter chips on Activity, Access tab
selection, and the Rules preview banner have nothing to do with Claude as
an agent. This is exactly the error Principle 6 warned against: agent
color == agent identity, not "where the user is looking."

**Impact:** When the user runs a Codex-only session and sees a blue tab
highlight, the color channel is lying. This is a subtle bug, but it's the
difference between the app feeling *lived-in* vs. *template*.

**Fix:** Introduce `ManifoldPalette.selectionSoft` and
`ManifoldPalette.selection` — a neutral brand accent (a grey-blue or
graphite with 10%/35% tints) — and reserve `claude` / `codex` for places
that represent that agent specifically: avatars, commit-ladder "Add to
default" button, gradient icon fills. Audit the seven sites above and
convert.

### 3.3 Mail is not Active Backup yet

Stage 8 chose Active Backup style over Apple Mail — the defining choice
is a *dense 4-column table* (checkbox / sender / subject / date) with
sortable columns, keyboard row navigation, and no reading pane.

`ThreadsView.swift` delivers:
- `LazyVStack(spacing: 0)` of custom `ThreadGroupRow`s — not a `Table`.
- A stacked layout (subject + participants + preview + date stacked
  vertically) closer to Apple Mail than Active Backup.
- No column sorting.
- `ContentUnavailableView` for error/empty, instead of the shared
  `EmptyStateIllustration` used everywhere else.

**Impact:** The Stage 8 decision is visible in the code comments but not
on the screen. If a prospective user opens the surface and expects
Synology Active Backup density, they won't get it.

**Fix:** Replace `ThreadGroupRow` with a `Table(of: MailThreadRow.self,
selection: $browser.selectedThreadKey, sortOrder: $sort) { ... }`. Use
`TableColumn` with widths tuned to the four-column spec. Keep the
tri-state checkbox in the leading column. Move the inspector content
behind selection instead of behind a second click.

### 3.4 No visible focus ring on `Table` in Activity or Access

Native macOS tables show a blue focus ring around the whole table when it
owns key focus. Manifold's tables don't — they use `.tableStyle(.inset)`,
which suppresses the focus ring by default at window-level focus.

**Fix:** Wrap the table in `FocusableTable` view-modifier that adds a
1-pt stroke in `ManifoldPalette.selection` when `.focused`.

### 3.5 `EventTable` has no context menu

Right-click on an audit row in Activity does nothing. On a pro macOS app,
the minimum set is: *Copy path · Reveal in Finder · View evidence ·
Filter to this agent*. Raycast and Finder both exemplify this.

**Fix:** Add a `.contextMenu { ... }` on each `TableRow(entry)`.

### 3.6 No Cmd-F search on the Ledger

Cmd-F on Activity should focus a filter textfield. Cmd-F on Access should
filter the folder matrix. Today it does nothing anywhere but Command
Palette.

**Fix:** Each surface that has a list should accept Cmd-F via
`.searchable` or `@FocusState` + `.keyboardShortcut("f", modifiers: .command)`.
Mail already has a search field (`ThreadsView.swift:186`), but it's not
Cmd-F focused.

---

## 4. Information density and clarity

### 4.1 Empty-state illustration reuses the same glow circle six times

`EmptyStateIllustration` is a 73-line primitive that gets used in Access
empty, Mail empty, Requests empty, and twice in onboarding. It's the same
soft blue glow behind the same SF Symbol each time.

**Impact:** Used once: calm. Used six times: template. The user learns
*"this screen has nothing"* instead of *"this screen is Access with
nothing in it yet"*. On Apple's surfaces, empty states are **distinctive**:
the Reminders empty state looks different from the Notes empty state.

**Fix:** Give each surface a bespoke empty composition:

- Activity: a thin sparkline-ish silhouette fading to the right, labelled
  "Events would appear here."
- Access: a ghosted file-tree silhouette (4–5 placeholder rows).
- Requests: a stacked-card silhouette with a calm "nothing waiting" label.
- Mail: an outline of a thread table with the checkbox column visible.

Reuse the same type/copy scaffold; vary the *shape*. The EmptyStateIllustration
primitive can stay as the fallback for onboarding.

### 4.2 FilesFlatView ships without the version timeline

The file comment (`FilesFlatView.swift:6–8`) is candid:

> Phase 3 scaffold without the version timeline — version chips land once
> snapshot tracking is wired through ManifoldCommands.

The surface at the moment is a sortable file list with no concept of
versions, which is exactly what Finder provides for free via the real
filesystem. Without the version timeline, the Access surface gives the
user no reason to leave Finder.

**Impact:** This is the Access surface's load-bearing differentiator from
Finder. Shipping without it is shipping without the point.

**Fix (two levels):**
1. *Minimum viable*: wire `VersionTimelineInspector` — when a row is
   selected, show its tracked revisions in a right-pane inspector with the
   diff preview. Snapshots are already promoted by the runtime; the UI
   just needs to read them.
2. *Proper*: add a "Δ" column to the Table (`SparklineBar` pattern,
   showing N edits) and a Cmd-↓ / Cmd-↑ keyboard path through versions.

### 4.3 Rules is honest — and that honesty is the feature's weakness

`RulesWindowView.swift:65` tells the user:

> This is a preview workspace for future global policy authoring. Seeded
> examples help you explore the shape, but edits here stay local to this
> window for now.

And `PreviewBanner` (line 201) says:

> Rules here are local preview state only. They do not change the live
> runtime policy system yet.

The honesty is correct. The problem is that *the Ledger badges Rules
alongside live surfaces*. The sidebar shows Rules as a first-class
destination with a badge count that is never non-zero because the
system never writes. We've invited the user to sit down at a piano with
no strings.

**Three choices, pick one:**
1. Demote Rules to the Settings surface until the runtime-backed authoring
   lands. (Lowest-risk, most honest.)
2. Wire the seeded file/env/SSH deny rules to actually gate runtime
   read/write decisions. The engine already knows how to deny; the UI
   just doesn't feed it. This is the ambitious path.
3. Restyle Rules as a first-class "preview workspace" with its own
   visual language — a muted palette, a "beaker" treatment applied
   everywhere, a banner that reads "Coming in v1.1" — so the preview
   status reads at a glance, not in footnote copy.

My recommendation: **1 now, 2 later**. Option 3 is the worst because it
preserves the dead piano while trying to dress it up.

### 4.4 Copy tic: "through Manifold" is said 12+ times

Search the onboarding + menu-bar copy for "through Manifold". Count them
out loud.

- "files and mail you choose to share with Claude and Codex through Manifold"
- "governs access routed through Manifold"
- "Claude or Codex can access through Manifold"
- "Nothing is in default scope through Manifold yet"
- "files visible through Manifold when you start a session through Manifold"
- ... etc.

The phrase is doing two jobs: *disambiguation* ("the Manifold channel,
not other channels the agent might have") and *branding* (reminding the
user the app's name is Manifold). The reader internalizes it after the
first use. Every subsequent use reads as over-explanation — a
lawyer-reviewed disclaimer, not a product voice.

**Fix:** Keep the phrase in the onboarding's *first* Concept panel and in
the StatusBar's "boundary" caption where the scope is being defined. Drop
it everywhere else. Replace with "here" or "this app" or nothing.

Example rewrite, `FirstRunPanels.swift:184`:

> Before:
> "Manifold only governs access routed through Manifold. Native app
> connectors, terminal access, and other local capabilities outside
> Manifold are outside this control path."
>
> After:
> "Manifold governs the access it mediates. Native app connectors,
> terminal access, and other local capabilities fall outside this
> boundary."

Cleaner, same meaning.

### 4.5 "You've shared 4 folders through Manifold by default" is ambiguous

`MenuBarPanelView.swift:110–111`. "By default" reads in English as "we
shared them without asking." What we mean is *"these are the folders in
your default scope."*

**Fix:** "4 folders are in your default scope." Or even shorter: "Default
scope: 4 folders." The menu bar is a status display — short labels, the
kind Apple uses in Control Center.

---

## 5. Motion and delight

### 5.1 The motion vocabulary is defined but unused

`DesignTokens.swift:237–256` carefully defines `micro` / `state` /
`landing` / `spring` / `pulseEaseOut` and a `ManifoldAnimations` alias
group that maps them to stateChange / structural / entrance / micro.

Actual call-sites found by grep:
- `ManifoldMotion.state` — used once (menu bar queue section expand).
- `ManifoldMotion.micro` — used once (file tree disclosure).
- `ManifoldMotion.pulseEaseOut` — used in `AgentStatusDot` and
  `SessionChip`.

That's it. Five animations in a 6,000-line UI.

**The tells:**
- Ledger destination changes are `NavigationSplitView` system defaults.
  On a session-live view, swapping from Activity to Requests snaps.
- Tab changes inside Access/Mail/Rules snap.
- Filter chip toggles on Activity snap.
- Approval card dismissals (`store.answer(request, with: .once)`) just
  cause the row to disappear. A Raycast answer slides; a Things task
  sweeps; an Apple Mail delete animates.
- Session start/finish: the `SessionChip` appears/disappears in the
  sidebar and toolbar with zero transition.

**Fix:** Three concrete additions, scoped to primitives so the sites
inherit automatically:

1. `ApprovalCard` on `onAnswer` → `.transition(.asymmetric(insertion:
   .opacity, removal: .push(from: .trailing).combined(with: .opacity)))`
   with `ManifoldMotion.state`.
2. `SegmentedTabBar` (once extracted) wraps selection change in
   `withAnimation(ManifoldMotion.micro)` so the fill / stroke lerps.
3. `SessionChip` appear/disappear gets
   `.transition(.scale(scale: 0.94).combined(with: .opacity))` with
   `ManifoldMotion.landing`.

None of these is a "feature." They are the difference between *the app
feels alive* and *the app feels like a wireframe*.

### 5.2 No selection animation on the sidebar

`NavSidebar` uses system `List(selection:)` — fine — but system sidebar
selection animates the fill only when you click. Keyboard-driven
selection change via ⌘1–⌘5 (once added) will snap. A 120ms
`.easeOut` fill transition would bring it to parity with Mail and
Reminders.

**Fix:** Once ⌘1–⌘5 exists, drive `destination` through
`withAnimation(ManifoldMotion.micro) { destination = … }`.

### 5.3 Pulse halo is the only ambient motion — and it's the right one

Credit where due: `AgentStatusDot` + `SessionChip` both pulse at 2s,
respect reduce-motion, and are used exactly where you'd expect (a live
session, a connected agent). This is *correct* taste. Copy this pattern
in more places: the Requests badge when a new request arrives should
pulse once, not twice.

---

## 6. Performance and responsiveness

### 6.1 `FilesFlatView` enumerates every file on view-enter

`FilesFlatView.swift:72–76`:

```swift
.task {
    isLoading = true
    files = await store.enumerateSourceFiles()
    isLoading = false
}
```

For a user with 3 repos of ~20k files each, this is a 60k-row synchronous
load. No pagination, no incremental streaming, no priority.

**Fix (short-term):** Cap the initial load at 2,000 files with a "Show
all 58,420 files" affordance at the bottom. For interaction polish, use
`AsyncSequence` to stream rows as they're discovered.

**Fix (proper):** `store.enumerateSourceFiles()` should return an async
sequence, and `FilesFlatView` should render progressively.

### 6.2 `visibleEntries` filters on the main actor

`ActivityWindowView.swift:38–41`:

```swift
private var visibleEntries: [AuditEntry] {
    guard let selectedSession else { return store.activityEntries }
    return store.activityEntries.filter { $0.sessionID == selectedSession.id
        || $0.grantID == selectedSession.id }
}
```

This runs on every view-body pass. For a high-activity session, the
filter is O(n) per re-render.

**Fix:** Memoize on `(selectedSession?.id, store.activityEntries.count)`
via `@State` cached array, or move the filter into `ManifoldStore` with
an `@Observable` derived property that recomputes only on store mutation.

### 6.3 `ActivityWindowView.task` reloads on every sidebar switch back

Lines 80–83 reload `history.loadActivity()` + `loadSessions()` every time
Activity is shown. If the user ping-pongs between Activity and Access
during a session, that's 4+ network round trips.

**Fix:** Skip reload if `history.lastLoadedAt` is within 5s, or make the
calls idempotent and use `force:` like `AccessWindowView` does.

### 6.4 Menu bar panel task loads policy + history on every open

`MenuBarPanelView.swift:76–80` runs three awaits every time the panel
opens. The menu bar panel opens tens of times a day.

**Fix:** Cache the last load time in `CommandCenter`; skip if
fresher than 10s. Note that `store.policy` is already `@Observable` — the
panel would receive updates via the reactive graph anyway.

---

## 7. Visual polish (the last 10%)

### 7.1 CommandPalette highlight is too soft to read as selection

`CommandPaletteView.swift:127`:

```swift
.background(highlighted ? Color.accentColor.opacity(0.12) : Color.clear)
```

12% opacity is below the contrast floor for selection in bright window
chrome. Raycast uses a solid fill with a 2-pt leading-edge stripe in the
brand color. Things uses a 20% fill + 1-pt stroke. Apple's own
contextual lists use 15% solid + dimmed border.

**Fix:**
```swift
.background(
    RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
        .fill(highlighted ? ManifoldPalette.selectionSoft : .clear)
)
.overlay(alignment: .leading) {
    if highlighted {
        Capsule()
            .fill(ManifoldPalette.claude)
            .frame(width: 2)
    }
}
```

The stripe is 2 points wide and reads from six feet.

### 7.2 Menu bar panel is a 586-line megafile

`MenuBarPanelView.swift` contains 9 sub-types: `StatusHeader`,
`SessionChipStrip`, `TrackedEditStrip`, `RequestsQueueSection`,
`RequestCard`, `AgentSummaryBlock`, `AgentRow`, `RecentSessionsBlock`,
`FooterActions`, `FooterItem`, `FooterDivider`, `HoverRowStyle`.

Inline `#Preview`s exist only for the top-level `MenuBarPanelView`.
Previews for individual strips (session-live, tracked-edit, pending-queue,
error) would catch pixel regressions.

**Fix:** Extract into `Views/MenuBar/` as separate files per sub-type,
each with 2–3 `#Preview` states driven by fixtures. `MenuBarPanelView.swift`
should end up ~120 lines.

### 7.3 Duplicate avatar primitives

`ThreadsView.swift` defines its own `SenderAvatar` (colored circle with
initials) while the rest of the app uses `GradientAvatar`. They should
share a root — `GradientAvatar` extended with an initials variant, or a
new `Avatar` enum (`agent | person(initials) | brand`).

**Fix:** Collapse into one.

### 7.4 The "pending request" count badge in `NavSidebar` has no overflow story

`.badge(pendingCount)` on a row with 99+ requests shows "99" truncated.
Not a today-problem, a tomorrow-problem. Apple's Mail badges 999+.

**Fix:** Cap at "99+" via string badge (`.badge(Text("99+"))`).

### 7.5 `RuleCard` dims at 60% when disabled

`RulesWindowView.swift:279` — `.opacity(isEnabled ? 1 : 0.6)`.

60% is too light to read; native macOS uses the native disabled
appearance (≈35%) or, better, leaves text at full opacity and adds a
"DISABLED" pill. The current treatment reads as *"this control is
broken,"* not *"this rule is off."*

**Fix:** Swap to a `Pill(text: "off", variant: .neutral)` leading of the
card body, at 100% text opacity. Binary state, not a gradient.

### 7.6 The preview banner uses `claudeSoft` as a background, which re-confuses agent color

`RulesWindowView.swift:218` — `.background(ManifoldPalette.claudeSoft.opacity(0.75))`

A preview banner has nothing to do with Claude. It should use a neutral
"info/preview" color — a warm amber tinted surface ("this is preview
land") or a neutral grey.

**Fix:** Introduce `ManifoldPalette.preview` (soft amber, or the `beaker`
symbol's native color) and use it for preview-state treatments
consistently.

---

## 8. First-run and session flows

### 8.1 First-run is good — one word change

`FirstRunFlow` is well-structured: 4 panels (concept → defaults →
guidedAdd → scopeReview) with progress dots and a "Skip setup"
affordance. The scope-review panel is Ive-caliber: the user sees exactly
what they are about to protect, named and pathed.

One copy nit on `DefaultsPanel`:

> "Claude and Codex start with no shared scope through Manifold."

If the user hasn't installed either, this reads as though both are
present. Consider:

> "No agent can see anything until you share it."

Agent-agnostic, shorter, and the same meaning.

### 8.2 The post-first-run sheet jumps too fast

`FirstRunFlow.finish()` immediately posts
`.manifoldShowSessionStartSheet`. The user chose their first folder three
seconds ago; we are already asking them to set duration/agents/track-writes.

**Fix:** Land on the Access surface with the new folder selected and a
non-modal banner: *"Start a protected session whenever you're ready
(⌘N)."* Let the user read their own scope before we ask them to
configure the next thing.

### 8.3 `SessionStartSheet` uses the right primitives — and one dead field

`SessionStartSheet` is a model sheet done correctly: labelled form rows,
radio group for `BaseMode`, clear primary action. One small issue:
`draft.trackWrites` toggles on every session-start but the copy is
inconsistent with the Tracked Edit strip in the menu bar — the sheet
calls it "Track writes" and the menu bar says "TRACKED EDIT."

**Fix:** Pick one noun and use it everywhere. My vote: "track writes"
(verb) on the sheet, "Tracked" (adjective) in the chip. They're talking
about the same state but with the right part-of-speech per context.

---

## 9. Accessibility

This is the strongest dimension in the app. Every primitive has
`accessibilityLabel`, `accessibilityHint`, or `accessibilityIdentifier`.
`SessionChip` and `AgentStatusDot` respect
`accessibilityReduceMotion`. `.accessibilityAddTraits(.isSelected)` is
applied to tab and sidebar items.

The one gap: **contrast of `text3` / `tertiary` foreground in bright
mode**. On an iMac in sunlight, the "caption" copy in `RecapMetric`
(line 163) and the trailing timestamps in `RecentSessionsBlock` will fall
below AA. Consider bumping the tertiary token by ~4% luminance in the
light mode palette.

---

## 10. What's *right* (so we don't accidentally undo it)

Calling these out deliberately — removing them in a polish pass would be
a regression.

1. **StatusBar honesty** (`Chrome/StatusBar.swift`). Priority-ordered
   state with "Reconnect" button exposed only when the runtime is
   disconnected. This is the scorecard principle made concrete. Copy it
   to the menu bar panel's error path.
2. **CommitLadder keyboard map**. ⏎ / ⇧⏎ / ⌥⏎ / ⌘⏎ maps to Not this
   time / Once / For this session / Add to default. This is the kind of
   detail that makes Raycast fans feel at home.
3. **Native `Table` in EventTable**. `.inset` style, real
   `TableColumn`s, keyboard selection — the right macOS choice over a
   bespoke LazyVStack.
4. **NavSidebar uses system idioms**. `.navigationTitle`, `.badge`,
   `.listStyle(.sidebar)` — don't fight the platform.
5. **FirstRun scope-review panel**. The user sees the exact folder
   paths they're about to protect before committing. Apple-caliber.
6. **Default + Session + Reload primitive is coherent**. `BaseMode` on
   the start sheet, `SessionChip` in the chrome, `ReloadDriftSheet`
   preview. The mental model survives from spec to screen.
7. **Preview-surface banner for Rules**. The honesty beats a fake-feature
   that silently doesn't wire. Keep the honesty, resolve the awkwardness
   via option 1 or 2 from §4.3.

---

## Prioritization — what to ship first

If you can only do one week of phase-10 work, in order:

**Day 1–2 (load-bearing):**
- Finish WorkBlock → Session rename (§1.1). Run `swift build` + full test
  suite.
- Delete `selectedTab`, `AppTab`, `AgentFocus`, fixture overrides (§1.2).
- Rename `AIAppsSettingsPane` → `AgentsSettingsPane` (§1.3).
- Strip `Color.accentColor` from `CommandPaletteView` and
  `ActionFormatting` (§3.1).

**Day 3 (navigation coherence):**
- Extract `SegmentedTabBar` primitive, collapse three tab bars (§2.1).
- Add ⌘1–⌘5 sidebar shortcuts (§2.2).
- Add Cmd-Opt-Left/Right sub-tab shortcuts (§2.3).
- Delete `FoldersInspector` dead code (§2.4).
- Extract `MailSessionView` and `MailHistoryView` (§2.5).

**Day 4 (color discipline + motion):**
- Introduce `ManifoldPalette.selection` + `.selectionSoft` + `.preview`
  (§3.2, §7.6). Audit the 7 mis-tinted sites.
- Wire `ApprovalCard` dismiss transition (§5.1.1).
- Wire `SessionChip` appear/disappear transition (§5.1.3).

**Day 5 (content):**
- Wire `VersionTimelineInspector` to FilesFlatView selection (§4.2).
- Convert `ThreadsView` body from LazyVStack to `Table` (§3.3).
- Decide Rules disposition (demote / wire / restyle) — §4.3.

**Running throughout:**
- Split `MenuBarPanelView.swift` into `Views/MenuBar/*` (§7.2).
- Copy audit: the "through Manifold" tic (§4.4, §4.5).
- Bespoke empty-state silhouettes per surface (§4.1).

Performance work (§6) is a separate PR with its own verification — it
touches the store, not just the views.

---

## Verification note

This is a review, not a code change; no `swift build` or `xcodebuild`
was run. Claims about file content are anchored to the file paths and
line numbers above so any of them can be checked by opening the file.

Two claims I could not verify from static reading alone, and which
deserve a manual pass before the phase-10 PR:

1. That the `SessionDiffView` and `AccessHistoryView` actually render
   non-placeholder content with a populated store. I read their sizes
   but not the bodies. If either is a shell, it should be flagged in §4
   alongside Rules.
2. That the runtime really does deny-but-log when the seeded Rules would
   match. The UI implies so; the Stage 8 / Stage 11 docs imply so; I
   didn't trace through `ManifoldBridge.swift` to confirm.

Both are worth a 30-minute pairing before the phase-10 PR opens.

---

## Closing

The redesign did the hard part: it picked a posture (daemon with a
ledger), a primitive (Default + Session + Reload), a vocabulary
(user-as-subject), and a palette (fixed agent colors, never system
accent). The shipped code honors ~85% of that. What's left is the 15%
that separates a product people use from a product people feel.

The 15% is not more features. It is:

- **Rename the abstractions so nothing on screen ever says "work block."**
- **Animate state changes so the app feels alive.**
- **Use Claude-color for Claude, not for selection.**
- **Give each empty state a face of its own.**
- **Let the keyboard drive the whole thing.**
- **Decide what Rules is — and commit.**

Jobs at the NeXT whiteboard liked to say: *the polish is the product.*
The bones are good. Polish to the bar you picked.
