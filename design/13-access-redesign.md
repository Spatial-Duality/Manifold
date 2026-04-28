# Access Redesign — Cowork-First Content Boundary UI

**Status:** Phase 1 shipped on `main` (2026-04-28) · Phases 2–3 in flight
**Date:** 2026-04-28
**Branch:** `main`
**Scope:** Manifold's Access surface (file/folder/email per-AI visibility), Mail tidy-up, supporting Settings + Sessions changes

---

## Shipped Today (2026-04-28)

The **selector-control redesign** and the **Mail unification** were the high-priority pieces. Both shipped to `main`. What landed:

### Bullet-proof per-AI selector
- `AccessChipStack` (icon-only) renders one chip per connected AI in every table row across Folders, Files, and Mail. Filled = shared, hollow = hidden, agent-tinted on tap.
- `AccessCheckboxStrip` (labelled, with All tri-state) renders in the file inspector and the folder-tree inspector — the wider surfaces where labels fit.
- The "Both" tri-state checkbox in the Folders matrix recomputes scope from live store state at click time so a `.mixed` cell always moves toward "shared with all".
- `mutateScope` in `ManifoldStore` reads-modifies-writes the whole `AgentAccessPolicy` struct so `@Observable` fires reliably on optional value-type mutation.

### Goal #1 — Add folder/file with per-AI visibility
- Drag-and-drop a Finder folder onto Folders or Files → `store.addSourceFromURL`.
- Drag a file → confirmation dialog with **Add the whole folder** vs **Add only this file**. The latter scopes the parent for every connected AI and writes per-file deny overrides for the existing top-level siblings via the bulk `setManyFileVisibilityOverrides` endpoint.
- Both are wired through the shared `View.manifoldFileDropTarget(store:)` modifier in `Components/Primitives/FileDropTarget.swift`.

### Goal #3 — Toggle on/off for all or specific AIs
- Per-row chip stack on every surface. Right-click context menu offers `Share with all`, `Hide from all`, plus a per-AI toggle line per connected AI.
- Bulk-action bar appears on multi-select; inspector strip exposes the same controls with explicit labels.

### Goal #4 — Adaptive UI based on connected AIs
- `AgentMeta.connected(from:)` drives the agent column count. No greyed-out chips for AIs the user hasn't activated.
- Single-AI setups drop redundant pickers and captions ("Editing X overrides" caption removed; multi-agent picker is `.controlSize(.small)`).

### Goal #5 — Click file → details pane with version history
- File inspector preview opens in the default app on double-click (matches Finder).
- Mail inspector shows a real scrollable message body (220–360pt, selectable, line-spaced, extracted from `bodyText` or fallback to `preview`) plus a bordered **Open in Mail** button that hands the `.eml` to `NSWorkspace.shared.open`.

### Mail (tidied)
- `MailReviewModel` tracks per-agent shared sets (`sharedEmailIDsByAgent`) — single-target dropdown gone.
- Mail thread table prioritises Subject over Sender (Sender capped at 200pt; Subject `min 240, ideal 420, no max`).
- Inspector starts hidden, opens on double-click only, with a close button on the inspector itself plus the toolbar toggle and ⌥⌘0.
- The Share column uses the same `AccessChipStack` as Files for full surface consistency.
- Sharing column on the Folders matrix reads as plain English (`Not shared` / `Shared with X` / `Partly shared · N of M` / `Shared with all` / `Shared with both`); source health pills (`Removed`, `Offline`) moved inline beside the folder name. A small dot beside the Sharing pill flags sources with explicit per-file overrides.

### Engineering
- Per-agent loaders (`loadDriftCounts`, `loadOverrides`, `MailReviewModel.refreshSharedState`) fan out via `withTaskGroup` and only republish on actual change so `@Observable` doesn't fire on no-ops.
- `MailReviewRow` precomputes `sharedAgents: Set<TargetApp>` so the Share TableColumn cell reads from the row instead of re-querying `mailReview` every render.
- `sharedAnyAgentCount` cached as a stored property; new `AgentMeta.stableKey([TargetApp])` and `ManifoldStore.fileVisibilityOverridesByAgent(_:)` deduplicate logic across views.
- Filter-mode plumbing (off/warn/block + per-agent override + grant-scoped overrides) and named-session templates landed in `ManifoldKit` / `ManifoldXPC`; the surface UI for them is the next phase.

### Not yet shipped
- Smart Views section in the Access sidebar is implemented in `FilesFlatView` only — Folders matrix and Mail still need parity.
- Inspector audit timeline (cryptographic ledger verification, exposure mini-chart, tool sparkline, memory lineage) is partially wired into `FileInspectorPane`; full per-row audit panel is in flight.
- Inline `+ Add ▾` toolbar menu, menu-bar quick-add (⌥-click), and Finder Share Extension are still `pending` from the spec — drag-and-drop covers the most common case for now.

---

## Executive Summary

Manifold's backend already supports the Cowork-First Content Boundary Architecture (Sources + Grants + Materializations) with a richer feature set than the current UI exposes. The current UI fragments the question "what can each AI see right now?" across the Folders Matrix, Files Flat, Mail Review, and Session Start sheet, and rates **4/10** on design completeness for the redesign goals.

This redesign:

1. **Unifies the access question into one canonical surface** with an opaque data table grouped by Source, per-AI dot toggles inline, and a trailing inspector pane that surfaces backend capabilities (cryptographic ledger verification, secret-hotspot detection, exposure timeline, memory lineage, tool cost, drift) the runtime already produces.
2. **Reframes the AI selector as a reactive parent-child checkbox group** — the bullet-proof control at the heart of the product. Adaptive (parent disappears with one connected AI), reactive (auto-flip All when a child changes), labeled in plain English at every state, undoable atomically.
3. **Adds two architectural concepts:** a **configurable filter mode** (Off / Warn / Block) for sensitive-content handling with bulk override, and **layered sessions** (Default + saveable named sessions on top, ~2 days backend work).
4. **Tidies Mail** as a Synology-Active-Backup-style read-only archive viewer, sharing the same selector pattern as Access.

Each of the six user goals rates **10/10** with this design. All gems map to existing backend capabilities; named sessions are the only addition, and the backend audit confirms it requires <2 days of runtime work.

References anchored on Apple HIG, Apple System Settings → Privacy & Security → Files and Folders (the closest existing Apple analog), and Apple Mail account preferences (the canonical parent-child checkbox precedent).

---

## Six User Goals — Final Ratings

| # | Goal | 10/10 design |
|---|---|---|
| 1 | Add folder/file/email · See per-AI shared state | `+ Add ▾` toolbar menu (folder/files/mailbox); drag-drop onto surface; menu-bar quick-add (⌥-click); Finder Share Extension; per-row dot stack inline; sidebar Assistants section with live count badges |
| 2 | Glance-quick visual blocks, filter per AI | Smart Views section in sidebar (Mail Smart Mailbox pattern); filter chips in toolbar; user-saveable Smart Views; ⌘1/⌘2/⌘3 keyboard shortcuts; status bar shows current filter context |
| 3 | Toggle on/off for all or specific AIs | Reactive parent-child checkbox group in inspector; per-row dot toggles in table; right-click "Share with → All / Claude / Codex"; bulk action bar on multi-select; option-click column header for bulk-toggle (Fantastical pattern); drag-row → sidebar agent for instant grant; ⌘Z undo on every toggle |
| 4 | Adaptive UI based on connected AIs | Agent column appears only when connected; Assistants sidebar grows/shrinks; "+ Connect AI" persistent; no `.disabled()` anywhere; smooth column-add animation; zero-AI hero card with [Connect Claude] [Connect Codex] |
| 5 | Click file → details pane with version history | Inspector visible by default at 360pt; sharing list, source-default reasoning, origin block, audit (ledger + secret hotspot + exposure mini-chart + tool sparkline + memory lineage), versions timeline with diff click-through, recent activity; QuickLook (Space); multi-select shows union state |
| 6 | Filter / notice AI-created files | ✦ sparkle column (color = creating agent); "AI-made" filter chip; AI-created Smart View; per-line authorship in diff; filter by session ("Show files touched in 'Q4 Reporting'"); cross-agent provenance line ("✦ Claude touched · Codex never saw") |

---

## The Selector Control (Bulletproof Spec)

### Pattern: Reactive Parent-Child Checkbox Group

Native Apple precedent: Mail.app account preferences ("Enable this account" parent + "Use for sending / Storage / Notifications" children); Calendar.app sync settings; Notification Center per-app + per-category groups.

Three Manifold-specific upgrades on the native pattern:

1. **Live state label** — one line below the group always tells you the current state in plain English ("Hidden from all", "Claude only", "All AIs").
2. **"Covered by All" decoration** — when All is on, children show they're covered (soft accent-tint background + "via All" caption), not silently checked.
3. **Cascade microinteraction** — toggling All animates children with a 0.05s stagger.

### Adaptive presentation

| Connected AIs | Control |
|---|---|
| 0 | Hero card: "Connect Claude or Codex to start sharing" with [Connect Claude] [Connect Codex] |
| 1 (e.g., Claude only) | Single `☑ Claude` checkbox. No "All AIs" parent (would be redundant). `+ Connect Codex…` link below |
| 2 (Claude + Codex) | Parent `☐ All AIs` + indented children `☑ Claude` `☐ Codex` |
| 3+ (future) | Same model: parent + N children, label updates dynamically |

### State machine (exhaustive)

| State | All | Claude | Codex | Label |
|---|---|---|---|---|
| 1 | ☐ | ☐ | ☐ | "Hidden from all" |
| 2 | ☐ | ☑ | ☐ | "Claude only" |
| 3 | ☐ | ☐ | ☑ | "Codex only" |
| 4 | ☑ | ☑ (via All) | ☑ (via All) | "All AIs" |

Transitions:

| From | Action | To | Reactive change |
|---|---|---|---|
| 1 | Click All | 4 | Both children fill (cascade) |
| 1 | Click Claude | 2 | All stays off |
| 2 | Click Codex | 4 | All auto-fills |
| 2 | Click All | 4 | Codex fills (cascade) |
| 2 | Click Claude | 1 | All stays off |
| 4 | Click Claude | 3 | All auto-flips off |
| 4 | Click Codex | 2 | All auto-flips off |
| 4 | Click All | 1 | Both children empty (cascade) |
| 3 | Click Claude | 4 | All auto-fills |

**Invariant:** `All == (Claude && Codex)` at all times. State is always derived; no drift possible.

### Multi-select behavior (tri-state)

Apple's tri-state checkbox — used in Finder batch tag editing. Three observable states:

| Symbol | Meaning |
|---|---|
| ☑ | All selected items have this on |
| ☐ | All selected items have this off |
| ─ | Mixed (some on, some off) |

Click cycle in mixed state: `─ → ☑ → ☐ → ☑ → ...`. First click in mixed goes to "set all on" (most common intent). Subsequent clicks alternate.

Bulk action bar for fast paths (additive semantics):

```
┌─ Bulk action bar (3 selected) ──────────────────────────────────────┐
│ 3 selected   Share with: [All] [Claude] [Codex]                     │
│              Hide from:  [All] [Claude] [Codex]                     │
│              [↺ Reset overrides]   [Override sensitive (3 files)]   │
│                                                          ⌘Z undo    │
└──────────────────────────────────────────────────────────────────────┘
```

- "Share with Claude" is **additive** — flips Claude on for all selected, leaves Codex per-file.
- "Hide from Codex" is **subtractive** — flips Codex off, leaves Claude per-file.
- "Share with All" / "Hide from All" set both.
- Single ⌘Z reverts the entire bulk action atomically.

### Microinteractions (joy moments)

1. **Cascade fill** — `.spring(duration: 0.05, bounce: 0.3)` per child when All toggles.
2. **Live label crossfade** — `.snappy` 0.15s when state label changes.
3. **Snackbar undo** — every toggle floats `"Hid from Codex — ⌘Z to undo"` for 4s.
4. **"via All" hover tooltip** — "Click to remove from All — Codex would stay shared individually".
5. **Hover preview tooltip** — hover any state in off mode → "Click to share with both Claude and Codex".
6. **Source default reminder** — `"Source default: Both AIs (inherited from Project A)"` always visible. ↺ revert button when overridden.
7. **Keyboard chord** — `⌘⌥A` toggles All. `⌘1` toggles Claude. `⌘2` toggles Codex.

### Surface mapping

| Surface | Control type | Why |
|---|---|---|
| Inspector | Full reactive group with live label, undo, source default | Deliberate per-item management |
| Table row | Per-AI dots only (one per connected AI) | Fast scanning + one-click toggle |
| Row hover | Trailing reveal: `[Share All] [Hide All]` mini-buttons | One-click "All" without leaving row |
| Right-click context menu | "Share with → All/Claude/Codex" + "Hide from → All/Claude/Codex" | Power user keyboard-light path |
| Bulk action bar | Direct command buttons: `[All] [Claude] [Codex] [Hide all]` | Action-mode for many items |

Every surface ultimately maps to the same state. Click anywhere → inspector reflects.

---

## Information Architecture

### NavigationSplitView shell

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ MANIFOLD                                                                             │
├──────────────────┬──────────────────────────────────────────────┬──────────────────┤
│ SIDEBAR · 240pt  │ CONTENT · flex                                │ INSPECTOR · 360pt │
│ Liquid Glass     │ Opaque                                         │ Opaque            │
└──────────────────┴──────────────────────────────────────────────┴──────────────────┘
```

### Sidebar sections (top to bottom)

```
─── (no header)
  Activity
► Access
  Mail
  Requests
  Rules

─── SMART VIEWS
  ✦ AI-created
  ⏱ Recent
  ⊘ Shared with none
  + Save current view…

─── SESSIONS
  ● Default                                       (always present)
  ◯ Q4 Reporting        (Claude)                  (saved template)
  ◯ Code review         (Claude)                  (saved template)
  + New named session…

─── ASSISTANTS                                    (adaptive — only connected appear)
  ● Claude                              47
  ● Codex                               12
  + Connect AI…
```

Sidebar is Liquid Glass on macOS 26 (`NavigationSplitView` provides this automatically).

### Filter chip bar (`.safeAreaInset(.top)`)

```
Q Search files, folders, emails…   [Claude] [Codex] [✦ AI-made] [⏱ Recent] [⊘ Shared none]
```

Tokens combine. SwiftUI: `.searchable` + `.searchScopes` + tokens.

### Main table (opaque, OutlineGroup, `.inset` style)

Columns: **Name** · **Origin** · **Modified** · **Claude** · **Codex** (latter two adaptive).

```
NAME                       ✦   MODIFIED   CLAUDE   CODEX
▼ 📁 Project A             ─    —         ●        ●
  📄 report.pdf            ✦    Mar 12    ●        ⊘──
  📄 budget.xlsx           ─    Apr 2     ●        ●
▼ 📁 Personal              ─    —         ⊘        ⊘
  📄 taxes.pdf             ─    Feb 28    ⊘        ⊘
▼ ✉️  Inbox                 ─    —         ●        ●
  ✉️  "Q4 invoice…"        ─    Apr 24    ●        ⊘──
```

- ●  filled = visible
- ⊘  hollow = hidden
- ── thin underline below dot = explicit override (not just inherited)
- ✦  = AI-created (color = creating agent)
- Folder rows: drift indicator (`⚡ changed since Claude's last session · 12 new files`) when relevant.

### Inspector (visible by default, 360pt)

```
┌─────────────────────────────────────────────────────────────┐
│ ┌─[QuickLook thumb]─┐                                        │
│ │  📄                │  report.pdf                           │
│ │  PDF · 1.2 MB      │  /Project A/2026/                     │
│ └──────────────────  ┘                                        │
├─────────────────────────────────────────────────────────────┤
│ SHARING                                                      │
│   ☐ All AIs                                                 │
│       ☑ Claude                                              │
│       ☐ Codex                                               │
│   ▸ Claude only                              [⌘Z undo]      │
│   Source default · Both AIs (inherited from Project A) ↺    │
│   Rules in effect (2) ▾                                      │
├─────────────────────────────────────────────────────────────┤
│ PROVENANCE                                                   │
│   ✦ Created by you · Mar 12, 2026                           │
│   ✦ Claude touched · Mar 18, 2026 · 12 lines added          │
│   Memory · Claude learned 3 facts from this file ▾          │
├─────────────────────────────────────────────────────────────┤
│ AUDIT                                                        │
│   ✓ Ledger verified · 5 entries chained                     │
│   ⚠ 3 sensitive values flagged (1 secret, 2 PII) ▾          │
│   ▁▂▅▂▁ Claude read 5× (15.2 KB) · Codex 0×                 │
│   Tools · 12 calls · 3.2s total ▾                           │
├─────────────────────────────────────────────────────────────┤
│ VERSIONS                                                     │
│   v3 Today    ✦ Claude   +12 lines       [Diff]             │
│   v2 Mar 15     You      +8 lines        [Diff]             │
│   v1 Mar 12     You      baseline                           │
│   [Restore… ▾]                                               │
└─────────────────────────────────────────────────────────────┘
```

Multi-select inspector shows union state with tri-state checkboxes and a header `"3 files selected — mixed sharing"`.

Folder inspector shows contained file count, per-AI counts, drift status.

### Toolbar (system glass, automatic)

```
Access      [+ Add ▾]   [Inspector ⌥⌘0]                      [Start session ▾]
                                                              ↑ glassProminent
```

`+ Add` menu: Folder, Files, Mailbox, Drag from Finder.

`Start session ▾` menu (adaptive — see Layered Sessions section):

```
Default · Claude
Default · Codex
─────────
Q4 Reporting (Claude)
Code review (Claude)
─────────
+ New named session…
Manage sessions…
```

### Status bar

```
● connected · 3 sources · 1,247 emails · 0 pending requests        ● Claude · 12m active
```

Left: runtime + scope summary. Right: active session chip when running.

---

## Filter Mode (Configurable Sensitive-Content Handling)

Setting lives in **Settings → Privacy → Sensitive Content Detection**:

```
SENSITIVE CONTENT DETECTION

Mode:  ◯ Off       Don't scan files for sensitive values
       ● Warn      Show warnings, files stay accessible
       ◯ Block     Block sharing until you override

Per-agent override (optional):
  Claude:  inherit ▾
  Codex:   Block ▾    ← Codex stricter than default
```

Behavior in Access surface by mode:

| Mode | Row appearance | Sharing behavior | Override flow |
|---|---|---|---|
| **Off** | No badge | Normal | N/A |
| **Warn** | ⚠ "3 sensitive" badge | File shared if visibility on | One-click "got it" in inspector |
| **Block** | 🔒 "blocked: 3" pill, row dimmed | File NOT shared even if visibility on | Inspector "Override and share" with confirm sheet |

Bulk override sheet (Block mode, multi-select):

```
┌─ Override sensitive content blocking ─────────────────┐
│ 5 files contain sensitive values:                      │
│   • 3 API keys                                         │
│   • 8 email addresses                                  │
│   • 2 phone numbers                                    │
│                                                        │
│ Override and share with:                               │
│   ☑ Claude    ☐ Codex                                 │
│                                                        │
│ Per-file detail:                                       │
│   report.pdf — 1 API key, 2 emails                     │
│   budget.xlsx — 1 API key, 6 emails                    │
│   contacts.csv — 2 emails, 2 phones                    │
│   db.config   — 1 API key                              │
│   notes.md    — 0 (false positive flag)               │
│                                                        │
│ [Cancel]                          [Override 5 files →] │
└────────────────────────────────────────────────────────┘
```

Every override is logged to the ledger so the audit trail is preserved.

---

## Layered Sessions (Default + Named Sessions)

### Mental model

- **Default sharing** — the persistent base layer (per-agent visibility, per-file overrides). Always active for all agents.
- **Named saved sessions** — saveable templates that override the default for ONE target agent during their lifetime. End → default returns. Saveable + re-runnable.

Backend audit confirmed: `AccessStore.access_presets` table exists (migration v12). Adding `target_app` column + a new `startSessionFromTemplate` XPC command + ~150 lines total wires up the feature.

### Sidebar SESSIONS section

```
─── SESSIONS
  ● Default                              (always present)
  ◯ Q4 Reporting    (Claude)             (saved template)
  ◯ Code review     (Claude)             (saved template)
  ◯ Tax filing      (Codex)              (saved template)
  + New named session…
```

Each saved session row shows: name, target agent badge. Click → opens session detail/editor in main pane (with [Start] / [Edit] / [Delete] actions).

### "New named session…" sheet

```
┌─ New named session ─────────────────────────────────────┐
│  Name:    [Q4 Reporting________________]                 │
│  Target:  ● Claude    ◯ Codex    ◯ Both                  │
│                                                          │
│  Base scope:  Default sharing for Claude                 │
│              (Project A, Personal/notes)                 │
│                                                          │
│  ─── Additions (only this session) ─────────────         │
│  + Add files or folders…                                 │
│      📁 /Q4-financials/                                  │
│      📄 /Project A/2026/budget.xlsx                      │
│                                                          │
│  ─── Removals (only this session) ──────────────         │
│  + Add files or folders to hide…                         │
│      📁 /Personal/draft.txt                              │
│                                                          │
│  [Cancel]    [Save without starting]    [Save & Start]  │
└──────────────────────────────────────────────────────────┘
```

### Active session indicator

- Status bar: `● Q4 Reporting · Claude · 12m active`
- Banner in Access view: `Running Q4 Reporting · 3 files added · 1 removed [End session]`
- Sidebar: that session row gets ● green dot

### Mid-session changes

- **Default sharing changes during a named session:** apply to the persistent base. Named session continues with frozen scope. Banner: `"Default updated · Named session 'Q4 Reporting' unaffected until restart"`.
- **Named-session add/remove changes during active session:** pending banner with `[Apply now (End & restart)]`.

---

## Mail (Tidied, Synology-Active-Backup-Style Read-Only Archive)

### Posture

Mail is a **read-only archive viewer**, not a mail client. Same selector pattern as Access. Sidebar and main view tidied for archive browsing.

### Sidebar (replaces today's messy IMAP-folder tree)

```
─── ACCOUNTS
  ✉ amar@me.com           1,247
  ✉ work@manifold.dev       423
  + Add account…

─── ARCHIVED FOLDERS                  (universal, rolled up across accounts)
  📥 Inbox                 1,420
  📤 Sent                    187
  📂 Archive                  63

─── SMART VIEWS                       (shared with Access)
  ✦ AI-replied
  ⏱ Recent
  ⊘ Hidden domains          16

─── ASSISTANTS                        (shared with Access)
  ● Claude                 47
  ● Codex                  12
```

Removed: per-account IMAP tree, Drafts (read-only viewer has no drafts), Spam/Trash (not relevant), Review/Session/History tabs.

### Main view

Domain-grouped table (Smart Mailbox pattern):

```
DOMAIN / SENDER          COUNT     LATEST    CL    CX
▼ acme.com                  47    Apr 24    ●     ●
  "Q4 invoice from..."    Apr 24            ●     ⊘──
  "Project schedule"      Apr 20            ●     ●
▼ banking.com  ⚠ sensitive  12    Apr 15    ⊘     ⊘
▼ github.com                23    Apr 18    ●     ●
▼ noreply (auto-hidden)    342    Apr 28    ⊘     ⊘
```

Selector + inspector identical to Access. Inspector for an email shows from/subject/body preview, sensitivity (domain-driven + per-message override), origin (received date), audit (per-agent reads, ledger badge), per-domain rule shortcuts.

---

## Backend Gems Surfaced in Inspector

| Gem | Source store | Inspector treatment |
|---|---|---|
| Ledger verification badge | `LedgerStore.verifyChain()` | `✓ Ledger verified · 5 entries chained` line in AUDIT section |
| Secret hotspot | `CapabilityHandleStore` | `⚠ 3 sensitive values flagged (1 secret, 2 PII) ▾` (gated by filter mode) |
| Exposure mini-chart | `ExposureStore` | `▁▂▅▂▁ Claude read 5× (15.2 KB) · Codex 0×` sparkline |
| Memory lineage | `MemoryStore` | `Memory · Claude learned 3 facts from this file ▾` |
| Tool cost | `ToolMetricsStore` | `Tools · 12 calls · 3.2s total ▾` |
| Drift detection | (existing runtime signal) | Folder row: `⚡ changed since Claude's last session · 12 new files [Refresh scope]` |
| Rule explanation | `RuleEngine.evaluate()` dry-run | Hover over hidden ⊘ dot → tooltip with matched rule name + summary |
| Cross-agent provenance | `was_exposed_before` | `✦ Claude touched · Codex never saw` line in PROVENANCE |
| Per-line authorship | `SnapshotStore` + diff | Diff view: colored gutter ("Claude wrote lines 47–58") |
| Visibility provenance | `FileVisibilityOverrideStore.evaluate()` | `explicit (you set this)` vs `inherited from parent` chips on each child checkbox |

---

## Required State Coverage

| Surface | Loading | Empty | Error | Success | Partial |
|---|---|---|---|---|---|
| Access table | Skeleton rows (8 placeholder rows, shimmer) | Hero card "Add a folder to start. Drag from Finder or click + Add" | Banner at top: "Couldn't load sources [Retry]" | Standard table | Inline `Loading more…` row at bottom of sources list |
| Inspector | Skeleton sections | (when no row selected) "Select an item to see details" centered text | Banner inside inspector: "Couldn't load details [Retry]" | Standard inspector | Per-section spinners while individual queries run |
| Sidebar Assistants | (sync, no loading state) | (when no AIs connected) `+ Connect AI…` link only, no agents | Toolbar banner: "Manifold runtime offline · [Reconnect]" | Standard list with counts | Per-agent "syncing…" caption when count is being recomputed |
| Filter chips | (sync) | (no chips needed) | N/A | Standard chip row | Active chip pulses `.snappy` while query runs |
| Bulk action bar | N/A — UI only when items selected | N/A | "Action failed [Retry]" snackbar | Standard | "Applying to 47 files…" progress while mass action runs |
| Settings filter mode | N/A | N/A | "Privacy model unavailable" with [Re-download] | Standard | Per-agent override pickers update independently |

---

## Responsive & Accessibility

### Column width contracts

Per Apple SwiftUI Table conventions and macOS Finder list-view norms:

| Column | Min | Ideal | Max | Truncation |
|---|---|---|---|---|
| Name (with icon) | 200 | 320 | unlimited | tail (`...`) with full path tooltip on hover |
| Origin (✦) | 32 | 32 | 32 | fixed icon-only |
| Modified | 80 | 100 | 140 | tail; numeric monospaced digits |
| Claude (dot) | 60 | 60 | 60 | fixed |
| Codex (dot) | 60 | 60 | 60 | fixed |

SwiftUI: `TableColumn("Name", value: \.name) { … }.width(min: 200, ideal: 320)` per [Hacking with Swift — How to create multi-column lists using Table](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-multi-column-lists-using-table).

Sortable via `KeyPathComparator`: `@State var sortOrder = [KeyPathComparator(\.name)]` bound to `Table(items, selection:, sortOrder:)`. Per [forums.swift.org KeyPathComparator + Bool issues](https://forums.swift.org/t/trouble-with-keypathcomparator-and-bool-related-tablecolumn/62962): wrap Bool toggles in a `Comparable` proxy or use raw integer comparison for the visibility columns.

### Window-size breakpoints

| Window width | Behavior |
|---|---|
| ≥ 1280pt (Studio Display, large MBP 16") | Full layout: 240pt sidebar + flex content + 360pt inspector |
| 960–1279pt (small MBP 14", default MBA 13") | Inspector collapsible (toolbar toggle); default still visible if width permits |
| 720–959pt (compact MBA 13" half-screen) | Inspector hidden by default (toggle to overlay); sidebar collapsible |
| < 720pt (split-screen quarter, rare on macOS) | Sidebar collapsed to icons; inspector overlay only |

`NavigationSplitView` handles automatic collapse per window size — see [Hacking with Swift — How to create a two-column or three-column layout with NavigationSplitView](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-a-two-column-or-three-column-layout-with-navigationsplitview). Use `.navigationSplitViewColumnVisibility($columnVisibility)` to control sidebar; `.inspector(isPresented:)` for the trailing pane.

Filter chip bar wraps to second line when chip count exceeds available width (Apple's `Layout` protocol with horizontal-then-wrap behavior; or `LazyHGrid` with adaptive rows).

### Text overflow rules

- Path text: `lineLimit(1)` + `truncationMode(.tail)`. Hover tooltip via `.help(file.absolutePath)`.
- Email subject: `lineLimit(1)` + `truncationMode(.tail)`. Inspector shows full subject + body preview.
- Sender names and account labels in sidebar: `lineLimit(1)` + `truncationMode(.middle)` (preserve domain visibility for `verylongname@…@acme.com`).
- Status bar: collapses left-to-right (most-important-first) when window narrows; runtime state always visible.

### Keyboard navigation

- ⌘1 / ⌘2 — toggle Claude / Codex on selected row
- ⌘⌥A — toggle "All AIs" on selected row(s)
- ⌘F — focus search field
- ⌘⌥0 — toggle inspector
- ⌘Z — undo last toggle (queue, multi-step)
- ↑ ↓ — navigate rows; → ← — expand/collapse folder rows
- Space — QuickLook preview selected file
- Return — focus inspector pane
- Tab cycle: search → filter chips → table → inspector
- ⌘1 / ⌘2 / ⌘3 (mod) — first three Smart Views (Mail.app pattern; mod prefix to avoid conflict with row-toggle ⌘1)

### Accessibility

- VoiceOver labels on every checkbox: `"Share with Claude — currently visible. Tap to hide."`
- Dot toggles: `accessibilityRepresentation(as: .toggle)`; rotor groups for "All Claude toggles" / "All Codex toggles" for keyboard-light navigation.
- Sparkles (✦) and dots (●/⊘): `accessibilityHidden(true)` on the glyph itself; `accessibilityLabel` on the row carries the meaning.
- Drift / sensitive / blocked badges: distinct VoiceOver phrases ("12 new files since last session", "3 sensitive values blocked from sharing").
- Color contrast: agent dots respect `Increase Contrast` (filled circle vs hollow ring is shape-distinguishable, not just color).
- Reduce Motion: cascade animation falls back to instant fill; row tint snaps instead of fades.
- Reduce Transparency: Liquid Glass falls back to `.ultraThinMaterial` per [DESIGN.md](../DESIGN.md) glass fallback helper.
- Touch targets (rare on macOS but present on macOS 26 trackpad force-touch): all toggles ≥ 28pt hit region.

---

## SwiftUI Implementation Notes

### Inspector visibility default

Per user direction, inspector is visible by default. Persist via `@AppStorage("access.inspectorVisible") = true`. Toolbar toggle button binds to this. macOS remembers user's choice across launches.

```swift
@AppStorage("access.inspectorVisible") private var inspectorVisible: Bool = true

NavigationSplitView { sidebar } content: { table } detail: { /* unused */ }
    .inspector(isPresented: $inspectorVisible) { inspectorContent }
    .inspectorColumnWidth(min: 320, ideal: 360, max: 480)
```

### Tri-state checkbox custom ToggleStyle

SwiftUI ships `.toggleStyle(.checkbox)` for binary state on macOS. Tri-state requires a custom `ToggleStyle` per [AppCoda — How to create a Checkbox in SwiftUI Using ToggleStyle](https://www.appcoda.com/swiftui-checkbox/):

```swift
enum TriState { case on, off, mixed }

struct TriStateCheckbox: View {
    @Binding var state: TriState
    let label: String
    var body: some View {
        Button { cycle() } label: {
            HStack {
                glyph.frame(width: 14, height: 14)
                Text(label)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(stateLabel)
        .accessibilityAddTraits(.isToggle)
    }
    @ViewBuilder var glyph: some View {
        switch state {
        case .on:    Image(systemName: "checkmark.square.fill")
        case .off:   Image(systemName: "square")
        case .mixed: Image(systemName: "minus.square.fill")
        }
    }
    func cycle() {
        switch state {
        case .mixed: state = .on
        case .on:    state = .off
        case .off:   state = .on
        }
    }
}
```

### Reactive parent-child group

Source of truth for parent state is `(claude && codex)`. Keep this as a computed binding; don't store the parent independently:

```swift
struct SharingControl: View {
    @Binding var claude: Bool
    @Binding var codex: Bool
    let connectedAgents: [TargetApp]

    var allBinding: Binding<Bool> {
        Binding(
            get: { connectedAgents.allSatisfy { isOn($0) } },
            set: { newValue in
                for agent in connectedAgents {
                    setOn(agent, newValue)
                }
            }
        )
    }
    // ...
}
```

This guarantees the invariant `All == (Claude && Codex)` automatically — no drift.

### Liquid Glass fallback

Per [DESIGN.md](../DESIGN.md) glass section:

```swift
extension View {
    @ViewBuilder
    func manifoldGlass(_ shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
```

Use on toolbar regions, command palette, error banners. **Never on the data table.**

### Drag-drop

- Row → sidebar agent: `.onDrag { NSItemProvider(object: row.id as NSString) }` on row; `.dropDestination(for:)` on sidebar Assistant rows. Drop = additive grant.
- Folder from Finder → Access surface: `.dropDestination(for: URL.self)` on the table view's background. Drop = `addSourceFromPicker(url:)`.

### Snackbar

`.overlay(alignment: .bottom)` with a state-driven banner that auto-dismisses via `.task { try? await Task.sleep(...) }`. Stack snackbars when multiple actions fire in quick succession (limit to 3 visible; collapse to "+N more").

---

## Migration from Current UI

| Current view | Future view |
|---|---|
| `AccessWindowView` (5 internal tabs) | `AccessWindowView` (single unified surface; tabs removed) |
| `FoldersMatrixView` | folded into unified table (folders are top-level rows) |
| `FilesFlatView` + `FileInspectorPane` | folded into unified table + inspector |
| `MailWindowView` (Review/Session/History tabs) | `MailWindowView` (single archive view; tabs removed) |
| `MailboxesMatrixView` | folded into unified Mail table by domain |
| `SessionStartSheet` | extended to support template selection from new sidebar SESSIONS section |
| `RulesView` | unchanged (separate sidebar destination) |
| `ActivityView` | unchanged (separate sidebar destination); deep-linked from inspector "Audit" section |

Phased migration:

1. **Phase 1** — Build unified Access table with reactive selector. Keep old views behind a feature flag. Validate selector control with internal users.
2. **Phase 2** — Wire backend gems into inspector (ledger badge, exposure chart, memory lineage, tool sparkline). Expose drift banner.
3. **Phase 3** — Add filter mode (Off/Warn/Block) to Settings + Block-mode bulk override sheet.
4. **Phase 4** — Add named session backend (`target_app` column, `startSessionFromTemplate` XPC). Wire SESSIONS sidebar section + new-session sheet.
5. **Phase 5** — Mail tidy-up (sidebar simplification + unified table).
6. **Phase 6** — Remove old views behind feature flag.

---

## Required Backend Changes

Single migration + one XPC command + ~150 lines total. Per backend audit:

```swift
// Migration v21
Migration(version: 21, name: "session_templates") { db in
    let columns = try db.queryAll("PRAGMA table_info(access_presets)")
    let names = Set(columns.compactMap { $0["name"] })
    if !names.contains("target_app") {
        try db.execute("ALTER TABLE access_presets ADD COLUMN target_app TEXT")
    }
    try db.execute("CREATE INDEX IF NOT EXISTS idx_presets_agent ON access_presets(target_app)")
}

// New AccessStore method
public func templatesForAgent(_ agent: TargetApp) throws -> [AccessPresetRecord] { ... }

// New XPC command
case "startSessionFromTemplate":
    return try await startSessionFromTemplateCommand(payload: payload)
```

No other backend changes required for this redesign. All inspector gems map to existing stores.

---

## Filter Mode Runtime Enforcement

**Decision (eng review Issue 1):** Filter mode (Off / Warn / Block) is enforced as a new compositing layer in `ManifoldBridge.enforceFileReadRules`, not as a synthetic rule type and not in the UI alone.

Layer order at file-read time:

```
Agent requests file via MCP
       │
       ▼
┌─────────────────────────────────────────────┐
│ ManifoldBridge.enforceFileReadRules         │
│                                              │
│  1. RuleEngine.evaluate(.fileRead, agent)   │  ← rules deny first
│         │                                    │
│         ▼                                    │
│  2. FileVisibilityOverrideStore.evaluate()  │  ← per-agent overrides
│         │                                    │
│         ▼                                    │
│  3. NEW: filterMode(forGrant) check          │  ← Off / Warn / Block
│         │                                    │
│         ▼                                    │
│  4. Return content OR deny + reason          │
└─────────────────────────────────────────────┘
```

API shape (per ManifoldBridge extension):

```swift
extension ManifoldBridge {
    enum FilterMode: String { case off, warn, block }
    enum FilterDecision {
        case allow
        case allowWithWarning(findings: [Finding])
        case deny(findings: [Finding], canOverride: Bool)
    }
    func evaluateFilterMode(grantID: String, agent: TargetApp,
                            sourceID: String, relativePath: String) async -> FilterDecision
}
```

Per-grant filter mode resolution: `Settings.filterMode(forAgent:)` is the global default; user-set per-agent override on the grant takes precedence. Override-and-share creates an explicit `filter_mode_overrides` row keyed by `(grantID, sourceID, relativePath)`, logged to ledger as a separate Exposure-style entry so the audit trail records each deliberate override.

**Why not a synthetic rule:** filter mode is per-grant property, not a rule pattern. Conflating them grows the rule store with synthetic entries and forces awkward per-agent override semantics.

**Why not UI-only:** the agent reads files via MCP. UI hiding does nothing if the runtime returns content. Block mode must enforce in the bridge or it's theater.

---

## Named Session Error Handling

**Decision (eng review Issue 2):** Lenient with skip + banner. Future enhancement: filesystem watcher.

`startSessionFromTemplate` resolution at start time:

| Stale reference | Behavior |
|---|---|
| Source ID not found in `sources` table | Skip silently, accumulate in `skippedSources` |
| Source paused (status: `.paused`) | Skip, accumulate in `skippedSources` |
| Source removed (status: `.removed`) | Skip, accumulate in `skippedSources` |
| File path within source no longer exists | Drop from grant_file_scopes, accumulate in `missingPaths` |
| Target agent disconnected | Error before grant creation; user must reconnect or change target |

Returned `GrantStartResult` includes:

```swift
struct GrantStartResult {
    let grant: GrantRecord
    let skippedSources: [String]   // displayName for banner
    let missingPaths: [String]     // relative paths skipped
}
```

UI banner: `"Started Q4 Reporting. Skipped 2 missing folders. [Edit template]"`. Banner persists for the session duration; clicking [Edit template] opens the named-session sheet pre-filled with the surviving scope.

**Future work (deferred, requires backend):** filesystem watcher (FSEvents) tracks source moves/deletes/changes and auto-updates `sources` + dependent `access_presets`. This is a separate sprint.

---

## Inspector Caching + Lazy Load

**Decision (eng review Issue 3):** Per-fileID LRU cache, TTL 5 min, invalidated on grant lifecycle events.

```swift
@Observable
final class InspectorViewModel {
    private var cache = LRUCache<FileID, InspectorContext>(capacity: 200)
    private let cacheTTL: Duration = .seconds(300)

    func context(for fileID: FileID) async -> InspectorContext {
        if let cached = cache.get(fileID), !cached.isExpired(ttl: cacheTTL) {
            return cached.value
        }
        let fresh = await fetchSections(fileID)  // 5 parallel queries
        cache.put(fileID, InspectorEntry(fresh, expiresAt: .now + cacheTTL))
        return fresh
    }

    // Invalidation hooks wired to NotificationCenter:
    //   - .grantStarted → invalidate all
    //   - .grantEnded   → invalidate all
    //   - .exposureRecorded(fileID) → invalidate that fileID
    //   - .visibilityToggled(fileID) → invalidate that fileID
}
```

Section-level lazy loading inside `InspectorContext`: `LedgerVerification`, `SecretFindings`, `ExposureCounts`, `MemoryFacts`, `ToolInvocations`, `Versions` are async properties; sections render skeleton until populated.

**Drift detection** uses the same cache pattern keyed by `sourceID` instead of `fileID`. Drift state per source is computed once per grant lifecycle event and cached until the next event.

---

## Performance Notes

**Bulk action batched writes (eng review Issue 6):**

`FileVisibilityOverrideStore.setMany()` — single transaction, single SQL with VALUES list. Required for multi-select bulk action bar performance.

```swift
public func setMany(_ overrides: [FileVisibilityOverride]) throws {
    try db.transaction {
        let stmt = try db.prepare("""
            INSERT OR REPLACE INTO file_visibility_overrides
              (agent, source_id, relative_path, is_directory, decision, set_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """)
        for o in overrides {
            try stmt.execute(o.agent.rawValue, o.sourceID, o.relativePath,
                             o.isDirectory, o.decision.rawValue, Date())
        }
    }
}
```

Target latency: 50-file bulk action ≤ 20ms end-to-end (UI click → write → snackbar shown). The XPC `setManyOverrides` command marshals once.

**Smart View "AI-created" query:** filter on `creator_agent IS NOT NULL`. With <100K files no index needed (sequential scan ~50ms). At >100K files, add covering index `(creator_agent, modified_at)`. Track via TODO.

**Sidebar count badges (`Claude · 47`, `Codex · 12`):** recompute on grant lifecycle events + visibility-toggle events. Naive full count (one indexed query) is acceptable for v1 — measure before optimizing to incremental delta.

**Inspector cold load target:** ≤ 200ms from row click to all sections populated, with cache warm ≤ 16ms (single frame).

---

## Test Plan

**Decision (eng review Issue 5):** Comprehensive coverage. ~52 unit tests + 7 E2E + 1 critical regression.

### Critical regression (mandatory)

| ID | Description | File |
|---|---|---|
| **R1** | Migration v21 idempotent + existing `access_presets` queries unaffected on legacy rows (NULL `target_app`) | `Tests/ManifoldKitTests/DatabaseMigratorTests.swift` |

### Unit tests

**`SharingState` model (~14 tests)** — `Tests/ManifoldAppTests/SharingStateTests.swift`:
- 8 single-item state transitions (per state machine table in plan)
- 4 multi-select tri-state cycle transitions
- 1 adaptive single-AI presentation (no parent rendered)
- 1 adaptive zero-AI presentation (hero card mode)

**`AccessStore.templatesForAgent` (~5 tests)** — `Tests/ManifoldKitTests/AccessStoreTests.swift`:
- target_app filter returns only matching agent's templates
- target_app NULL returns templates for any agent (legacy)
- empty result on no templates
- ordering by `updated_at DESC`
- exclusion of soft-deleted presets

**`FileVisibilityOverrideStore.setMany` (~6 tests)** — extend existing test file:
- Empty input is no-op
- 50-file batch in single transaction
- Atomicity: one bad row aborts all (no partial writes)
- INSERT OR REPLACE semantics on existing override
- Mixed allow/deny in one batch
- Performance: 200-file batch < 50ms (perf assertion)

**`startSessionFromTemplate` XPC command (~10 tests)** — `Tests/ManifoldXPCTests/StartSessionFromTemplateTests.swift`:
- Happy path: template → grant created with merged scope
- Skip stale source (deleted), banner data populated
- Skip paused source, banner data populated
- Skip missing file path within valid source
- Disconnected target agent → ManifoldError before grant create
- Empty template (no additions/removals) = default sharing
- Template with only additions
- Template with only removals
- Both additions and removals applied correctly
- Grant materialization includes merged scope

**`ManifoldBridge.evaluateFilterMode` (~10 tests)** — `Tests/ManifoldRuntimeTests/FilterModeTests.swift`:
- Off mode: bypass entirely, no findings check
- Warn mode + no findings → allow, no warning
- Warn mode + findings → allow with warning, exposure record flagged
- Block mode + no findings → allow
- Block mode + findings → deny with reason
- Per-agent override (Claude=inherit, Codex=block)
- Override-and-share creates filter_mode_override row
- Override-and-share logs ledger entry
- Block mode after override → allows that file
- Filter mode change mid-session → applies to new reads, not retroactive

**`InspectorViewModel` cache (~7 tests)** — `Tests/ManifoldAppTests/InspectorViewModelTests.swift`:
- Cache miss → 5 queries fire
- Cache hit within TTL → 0 queries
- TTL expiry → re-fetch
- Grant start invalidates all
- Grant end invalidates all
- Exposure recorded invalidates that fileID
- Visibility toggle invalidates that fileID

### E2E tests (`ManifoldAppUITests/`)

| ID | Flow | File |
|---|---|---|
| E1 | Drag row to sidebar Claude → grant applied | `AccessSelectorE2ETests.swift` |
| E2 | Bulk action: select 50 files, "Share with Claude" → all 50 toggled | same |
| E3 | First-launch zero-AI hero card → connect Claude → adaptive UI grows | `AdaptiveUIE2ETests.swift` |
| E4 | Block mode + secret-bearing file → agent's MCP read denied with reason | `FilterModeE2ETests.swift` |
| E5 | Block mode override sheet → confirm → agent can now read | same |
| E6 | Save named session → start it → active session banner correct | `NamedSessionsE2ETests.swift` |
| E7 | Restore version → snackbar shown → ⌘Z restores prior state | `VersionRestoreE2ETests.swift` |

### Performance assertions

Embed in unit/E2E:
- 50-file `setMany` < 50ms
- Inspector cold load < 200ms; cache warm < 16ms
- 200-file bulk action click → snackbar < 100ms

### Test plan artifact

A test plan artifact for `/qa` consumption is written to `~/.gstack/projects/amargandhi-Manifold/x01-main-eng-review-test-plan-{datetime}.md` covering: pages tested (Access, Mail, Settings/Privacy), key interactions (selector flips, bulk actions, drag-drop, named session start/end), edge cases (zero AIs, single AI, mixed multi-select, stale template refs), critical paths (E1–E7).

---

## Worktree Parallelization Strategy

This plan splits cleanly into 3 parallel lanes plus 2 sequential merges:

| Lane | Phases | Modules touched | Depends on |
|---|---|---|---|
| **A** | Phase 1 (unified table + selector) | `ManifoldApp/Views/Access/`, new `SharingState` | — |
| **B** | Phase 4 backend (migration v21 + XPC + AccessStore) | `Sources/ManifoldKit/AccessStore.swift`, `Sources/ManifoldXPC/`, `Sources/ManifoldKit/DatabaseMigrator.swift` | — |
| **C** | Phase 3 backend (filter mode bridge layer) | `Sources/ManifoldRuntime/ManifoldBridge*.swift`, `Sources/ManifoldKit/CapabilityHandleStore.swift` | — |
| **D** | Phase 2 (inspector gems wiring) | `ManifoldApp/Views/Access/FileInspectorPane.swift`, new `InspectorViewModel` | A merged |
| **E** | Phase 4 UI + Phase 5 (sessions UI + Mail tidy) | `ManifoldApp/Views/Session/`, `ManifoldApp/Views/Mail/` | A + B merged |

**Execution:** launch A + B + C in parallel worktrees. Merge each as it lands. Then D builds on A, E builds on A + B. Phase 6 (remove old views) happens after E ships.

**Conflict flags:** A and D both touch `ManifoldApp/Views/Access/`. Merge A first, rebase D. C doesn't touch app code so it's fully independent.

---

## Failure Modes

For each new codepath, one realistic production failure + coverage status:

| Codepath | Failure mode | Test? | Error handling? | User sees? |
|---|---|---|---|---|
| `SharingState.toggleAgent` | Concurrent edit from another window | Yes (unit) | `@Observable` reactivity | Snackbar conflict notice |
| `setMany()` | Transaction rollback mid-write | Yes (R1 + atomicity test) | Rollback + error | Snackbar "Update failed [Retry]" |
| `startSessionFromTemplate` | Template references all-deleted sources | Yes (unit) | Lenient skip | Banner "All sources missing — edit template" |
| `filterMode` enforcement | CapabilityHandleStore unavailable | Yes (unit) | Fail-closed (deny) | Inspector shows "blocked, source unavailable" |
| `InspectorViewModel.context` | One section query times out | Yes (unit) | Per-section retry | That section shows skeleton + retry |
| Drift detection | FSEvents queue overflow | No (manual) | Cache miss → recompute | Banner "Drift state unknown" |
| Named session materialization | Disk full mid-materialization | No (manual) | Cleanup + error | Sheet "Couldn't start session — disk full" |

**Critical gap:** drift detection FSEvents overflow has no test. Manual QA pass required, OR add to deferred TODO.



- Custom backend permission model changes beyond the named-sessions migration (defer)
- Per-line authorship for binary files (only text files in v1)
- AI-created Smart View user-customization (system Smart View only in v1; user-saveable views deferred)
- Cross-account email rule sharing (per-account scope only in v1)
- Power-user "copy access settings" / "paste access settings" (deferred)
- Finder Share Extension target (Phase 2 ship — not v1 blocker)
- Mid-session live re-materialization (banner-driven "End and restart" instead, per architectural fit)
- **Filesystem watcher (FSEvents) for source moves/deletes/changes** (eng review Issue 2 future work — separate sprint)
- **Drift detection FSEvents overflow auto-recovery** (manual QA pass for v1)
- **Smart View "AI-created" covering index** (sequential scan acceptable below 100K files)

## What Already Exists (Reuse)

- `AccessCheckboxStrip` component — extend to render "via All" decoration
- `CoverageDotButton` — reuse as in-row dot toggle
- `FileInspectorPane` — extend with new AUDIT and PROVENANCE sections
- `RulesView` — keep as-is, no scope change
- `EvidenceInspector` — Activity tab; deep-link target from inspector "Audit" section
- All XPC commands for grant lifecycle (`startTrackedRun`, `applyTrackedRun`)
- All stores (`MemoryStore`, `LedgerStore`, `ExposureStore`, `ToolMetricsStore`, `SnapshotStore`, `CapabilityHandleStore`, `FileVisibilityOverrideStore`, `AccessStore`, `RuleEngine`)

## Unresolved Decisions

None blocking. Two minor calls deferred to implementation:

1. **Smart View saving UX** — popover sheet vs. inline rename. Default to popover sheet for v1.
2. **Snackbar stacking limit** — 3 visible? 5? Default to 3 with "+N more" collapse for now.

## Approved Mockups

ASCII wireframes embedded above. PNG mockups not generated this session (gstack designer unauthenticated). Wireframes serve as the visual reference; SwiftUI implementation follows the design tokens in [DESIGN.md](../DESIGN.md).

## References

### Apple HIG / WWDC

- [Apple HIG — Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Apple HIG — Inspectors / Panels](https://developer.apple.com/design/human-interface-guidelines/panels)
- [Apple HIG — Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles/)
- [Apple HIG — Search Fields](https://developer.apple.com/design/human-interface-guidelines/macos/fields-and-labels/search-fields)
- [WWDC23 — Inspectors in SwiftUI (#10161)](https://developer.apple.com/videos/play/wwdc2023/10161/)
- [WWDC25 — Meet Liquid Glass (#219)](https://developer.apple.com/videos/play/wwdc2025/219/)
- [Apple Newsroom — Liquid Glass announcement](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)

### Apple product precedents

- [macOS Privacy & Security → Files and Folders](https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac) — closest existing Apple analog; canonical visual reference
- [Apple Mail Smart Mailboxes](https://support.apple.com/guide/mail/use-smart-mailboxes-mlhlp1190/mac)
- [Apple Notes shared notes](https://support.apple.com/guide/notes/manage-shared-notes-and-folders-apd881ec5518/mac) — per-participant permission pattern
- [iCloud sharing in Finder](https://support.apple.com/guide/mac-help/mchl91854a7a/mac)

### SwiftUI implementation

- [Hacking with Swift — Multi-column Tables](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-multi-column-lists-using-table) — column widths, KeyPathComparator
- [Hacking with Swift — NavigationSplitView two/three-column layouts](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-a-two-column-or-three-column-layout-with-navigationsplitview)
- [Hacking with Swift forums — NavigationSplitView on macOS](https://www.hackingwithswift.com/forums/macos/navigationsplitview-on-macos/24237)
- [AppCoda — Checkbox via ToggleStyle](https://www.appcoda.com/swiftui-checkbox/) — base for tri-state custom ToggleStyle
- [Liquid Glass Reference — Conor Luddy](https://www.conor.fyi/writing/liquid-glass-reference)

### Permissioning patterns

- [1Password Vault sharing](https://support.1password.com/create-share-vaults/) — sources-as-permission-unit precedent
- [Notion sharing & permissions](https://www.notion.com/help/sharing-and-permissions)
- [Linear filters + multi-select](https://linear.app/docs/filters)
- [Dropbox sync icons](https://help.dropbox.com/sync/sync-icons-windows) — tri-state badge technique

---

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | — |
| Codex Review | `/codex review` | Independent 2nd opinion | 0 | — | — |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | CLEAN | 6 issues (3 arch + 1 quality + 1 test + 1 perf), all resolved; 1 critical regression test mandated; 0 PLANBLOCKERs |
| Design Review | `/plan-design-review` | UI/UX gaps | 1 | CLEAN | score: 4/10 → 10/10, 30 use cases mapped, 2 architectural additions confirmed feasible |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

**UNRESOLVED:** 0
**CRITICAL GAPS:** 1 (drift FSEvents overflow — manual QA pass for v1)
**VERDICT:** ENG + DESIGN CLEARED — ready to implement. Phased ship: A+B+C parallel worktrees, then D+E.
