# Manifold UI — Stage 1: Honest Critique

**Source basis:** MainView.swift, OverviewView.swift, FilesView.swift, ActivityView.swift, MenuBarPanelView.swift, ReviewAccessSheet.swift, ActivityRow.swift, DesignTokens.swift, ManifoldStore.swift (partial), plus the 15-surface map and the 45-source reading list.

**Posture of this document:** Pixelmator-bar means the app has to survive an adversarial reading. I'm doing that reading now. The goal is not to scold code that works; it's to find the decisions that, if left unchanged, cap Manifold's ceiling.

---

## Overall grade: B-

The concept is unusually strong. Manifold is a **trust product with a version-control spine**, which is a real category gap. The execution is a competent macOS app that is quietly impersonating the wrong category of software. Most of the problems below stem from one root cause: Manifold was built as a sovereign app but its job is a daemon's job. Until that tension is resolved, polish work on any single surface is premature.

**What is concept-strong:**
- Standing = read / tracked = write is a clean mental model most permission products lack
- Exposure auditing (every read recorded, revertable writes, drift detection) is the trust-generating machinery nobody else has
- Two-agent card model in Overview is legible at a glance
- Design tokens file exists and is semantic (Typ, Spacing, Opacity, Anim), not ad-hoc

**What is execution-unfinished:**
- The posture decision is unresolved (§1)
- The *language* Manifold speaks to users is half data-model, half product (§4)
- The activity/exposure view is a log, not evidence (§3)
- Permission flow is modal and dialog-shaped (§2)
- Status is reported as agent or runtime state, not as consequence to the user (§5)

---

## §1. The load-bearing problem: Manifold is pretending to be a sovereign app

**Evidence in code.** `MainView` opens a window with `minWidth: 780, minHeight: 520`, a three-segment tab picker in the principal toolbar slot (Overview / Files / Emails), an inspector, a command palette (⌘K), and a toolbar connection indicator. This is the chrome of an app the user *lives in* — Cooper's sovereign posture (About Face, ch. 9). Mail, Photos, Xcode are sovereign.

**Why this is wrong.** Manifold's actual job is:
1. Govern what AI agents can see (scope), running in the background.
2. Show the user an accurate picture of what just happened (ledger).
3. Ask for consent when scope would change (approval).

None of those jobs require a window the user lives in. All three map to what Cooper calls **daemonic posture** (a service running with transient surface-ups) plus **transient posture** (brief, task-focused visits). Re-read About Face chapter 9 with Manifold in mind and you will find that the sovereign three-tab chrome is a category mistake.

**Second-order cost.** Sovereign chrome signals "come live here." Users then treat the app as something they should open daily, which is the opposite of what a trust product should encourage. The best compliment Manifold can earn is *"I forget it's running, but I trust that it is."* Raskin's whole case against modes in *The Humane Interface* applies: every mode Manifold adds is one the user has to carry.

**Show me the incentive.** The incentive to build sovereign is that sovereign apps feel like "real" apps to the team building them. The incentive pointed away from users, not toward them. An honest reading: the tab picker exists partly because it looked less empty than a single window, not because users needed tabs.

**Recommended posture.** Daemon with three distinct surfaces of different weights:
- **Menu bar panel** — primary surface, ~95% of user contact. (Cooper, Few, Apple HIG.)
- **Transient sheets** — approval, scope change, denial review. Invoked from menu bar or Finder extension. Never modal-blocking on the frontmost app. (Raskin.)
- **Full window — "Ledger"** — a single window that is primarily the exposure history view with secondary workspace/scope inspection. Opened rarely, like Activity Monitor or Console. Not a three-tab app. (Cooper transient, Tufte evidence.)

The Overview tab as it exists should die. It duplicates the menu bar panel at 2× the size with no new information.

---

## §2. The approval flow is modal-shaped. It should be queue-shaped.

**Evidence in code.** `ReviewAccessSheet` is a `.sheet(...)` with `minWidth: 520, minHeight: 500`. Opening it blocks the window. Decisions are made one at a time; each one interrupts. `commitPolicyChange()` applies changes synchronously on dismiss.

**Why this is wrong.** Whitten & Tygar's canonical "Why Johnny Can't Encrypt" paper and every study in Cranor & Garfinkel's *Security and Usability* show the same failure mode: users satisfice on modal consent dialogs. They click through. Raskin's modelessness principle says the same thing from the interaction side: a modal interrupts the user's locus of attention; the user's brain optimizes to dismiss the interrupt, not to reason about it.

**Second-order cost.** A permission UI that trains users to click through is worse than no permission UI — it manufactures false consent that the system can cite. This is exactly the UX pattern iOS permission dialogs have been (correctly) criticized for.

**The fix is not better dialog copy.** It's a posture change. Approval requests should accumulate in a **queue** (surface F in the map). The agent waits. The user approves on their schedule, in batch if they like, with full context in front of them. The daemon never blocks the user's current task.

The sheet UI currently exists for *scope editing* too ("Review & Update Access"), which is a different job from "approve this pending request." Conflating the two means scope editing inherits the interrupt pattern.

---

## §3. The Activity view is a log, not evidence

**Evidence in code.** `ActivityView` renders entries in a single-column `List` with `ActivityRow`: icon, one-line description, action name in small caps, timestamp. The big affordance is a "Group by Session" toggle. Session headers show "12 reads, 3 writes" in caption text. Diff expansion is inline and mandatory-per-row — you click a chevron, wait for a snapshot load, see a diff.

**Why this is unfinished.** Manifold's ledger is *the single most important surface in the app*. It is the thing that justifies Manifold's existence. It is also the hardest to get right because it's dense, relational, and temporal. The current implementation treats it like a system log viewer (Console.app). Console.app is the wrong reference.

The right references are Tufte (VDQI, *Envisioning Information*, *Beautiful Evidence*) and Few (*Information Dashboard Design*, *Now You See It*). Applied:
- **Data-ink ratio is low.** Icons, big action labels, lots of chrome per row, single file per row, no density.
- **No small multiples.** A session with 40 events is a scroll. There is no way to see the shape of a session at a glance.
- **No time encoding.** Timestamps are relative strings ("3m ago"), not positioned on a timeline. Bertin's visual variables say position is the strongest encoding; Manifold uses the weakest (text).
- **No comparative view.** You can't see "Claude read 12 files across 3 folders in 4 minutes" as a shape.
- **Diffs are per-row lazy loads.** Good for memory; bad for review. You can't scan 5 writes and compare their size.
- **No anomaly surfacing.** The whole point of a ledger is for the user to notice when something is off; the current view offers zero help to the eye (Ware, *Visual Thinking for Design*).

**Concept strong, execution unfinished.** The revert-to-before flow is genuinely good and almost nobody else has it. But it's buried inside a row expansion.

**What this surface actually is.** It's *evidence presented under adversarial scrutiny* (Tufte, *Beautiful Evidence*). Re-read that book with the Manifold ledger in mind and the shape of the redesign falls out: sparklines for session shape, small multiples for sessions-per-agent, position-encoded time, dense tabular core with one-click drill-down to the evidence (the snapshot + diff).

---

## §4. The app speaks half data-model, half product

**Evidence in code, with user-visible strings:**

| String | Where | Problem |
|---|---|---|
| "No governed sessions yet" | MenuBarHeaderView | *Governed* and *sessions* are internal terms. A user sees "???". |
| "Runtime not connected" | MainView status tooltip | Users don't know what "runtime" is. They want to know: *is this working?* |
| "Manifold-routed / Tracked workspace / Outside coverage" | MenuBarAgentCard | Three mode names, no glossary anywhere. |
| "new ✦" / "current" | ReviewAccessSheet | What does ✦ mean? |
| "1 of 2 sources \u{00B7} 4 rules" | MenuBarAgentCard | 4 rules of what? |
| "file_read" / "file_modified" / "tool_call" / "mcp_connection" | ActivityView filter menu items are prettier, but underlying strings leak through | These are event types in a schema, not things a user recognizes. |
| "Connection Issue" / "Notice" in error banners | MainView | Generic; doesn't tell the user what changed. |
| "Track Changes" | Toolbar when block active | Collides with Word's meaning. Users will assume text edits in a document. |

This is what Yifrah, Podmajersky, and Metts & Welfle all warn about in their own idioms: words are the design. A product whose language is half engineering-vocabulary forces the user to build a model of the engineering, not of the product. Kate Kiefer Lee's *Nicely Said* would catch half of these in one review pass.

**The denial tone is especially important and especially wrong.** When an agent tries to read something it can't, what does the user see? Right now: nothing visible unless they open Activity and filter to `coverage_warning`. This is the missed opportunity. A denial event is Manifold doing exactly what it was built to do. The UI should quietly celebrate it, with language that shows trust, not language that sounds like a firewall. *"Claude tried to read ~/Finances. Not in your workspace — blocked."* Not *"coverage_warning"*.

---

## §5. Status is reported as system state, not as consequence

**Evidence in code.** `MainView.statusLabel` returns one of {Disconnected, No agents, Paused, Connected}. `statusDotColor` maps to {red, secondary, orange, green}. The tooltip string is *"Claude: Connected · Codex: Paused"*.

**Why this is wrong.** Every one of those labels answers "what is the internal state" — not "what does that mean for me right now?" Cooper (About Face, ch. 12 on status and feedback) and Norman (DOET, signifiers) both land on the same rule: status must map to user consequence.

Better: instead of *Connected*, the user wants to know *"Claude can see 4 folders and your @work email. It looked at 2 files in the last hour."* That is the status. The green dot is fine. The word next to it should be the consequence.

Second-order cost: the current status is also unfalsifiable without inspection. "Connected" can be true at the XPC level while a policy is silently unloaded. The CLAUDE.md acknowledges this exact risk ("remove guessed agent state"). The language must not be more confident than the state.

---

## §6. Colors collide with the user's system accent

**Evidence in code.** `DesignTokens.swift` defines `claudeBlue = .blue` and `codexPurple = .purple`. These are **system semantic** colors, which follow the user's accent color. A user with a red accent color will see Claude as red. Claude-red is indistinguishable from `statusDanger = .red`. Codex-pink collides with nothing but still isn't codex-purple.

**Why this is wrong.** Albers (*Interaction of Color*) and Bertin (*Semiology of Graphics*) both point to the same rule: color-as-identity and color-as-state must occupy different channels. You can't let the user's OS override either.

**Fix.** Agent identity should be a **fixed brand color** in Manifold's palette, not a system semantic token. Status colors stay system semantic (so accessibility scales apply) but agent colors are constants. A light and a dark variant each, hand-picked for contrast against both surfaces and against each other in the dense ledger.

---

## §7. Typography is 80% there, but there's no grid

**Good:** `Typ` enum in DesignTokens defines roles (sectionTitle / heading / body / caption / mono / numericBody / numericCaption), uses monospaced digits for counts, uses `.monospaced()` for paths. That's Bringhurst and Hochuli showing up. Honest win.

**Missing:**
- No baseline grid. Spacings (`Spacing.tight` / `standard` / `section` / `edge`) exist but are not tuned to a multiple that produces vertical rhythm across views. The Overview card and the menu bar card do not share vertical rhythm.
- Dense views (FilesView table, ActivityView list) fall back to SwiftUI defaults — line heights, padding inside Table rows, column dividers are all system defaults. Hochuli would flag the row padding in the Activity list as too loose for a ledger; Müller-Brockmann would flag that the Files table and the Activity list don't share a column rhythm.
- No tabular number discipline in the Files table `Size` column (`.monospacedDigit()` is applied; good) but `Modified` is `style: .relative` ("3 days ago") with variable width — hurts scan.
- Typographic *states* are not defined. What does a muted row look like? A paused card? An untrusted folder? Currently done ad-hoc with `.secondary` / `.tertiary` / `.opacity(0.6)`.

---

## §8. Navigation and surface duplication

**Evidence.**
- Overview = two agent cards.
- Menu bar = two agent cards, smaller, plus work block strip and quick actions.
- Review sheet = per-agent scope editor.
- Settings > AI Apps = agent connection.
- Files tab > Sources overview = scope editor (from a different angle).

Five places touch "what can agent X see." Tidwell (*Designing Interfaces*) pattern for this is clear: one **workspace / scope** view that is authoritative, and every other surface links to it. Manifold currently has a workspace view scattered across five surfaces with subtly different affordances. This is a classic sign that the model wasn't drawn first (Alexander's pattern language: the primitives were never named).

---

## §9. Missing or weakly-formed surfaces

Against the 15-surface map in the ask:

| Surface | Current state | Gap |
|---|---|---|
| **A. First-run / trust establishment** | `SetupAssistantView` sheet (not read in detail but referenced) | Trust-establishment isn't just setup. It's the first 30 seconds after launch, forever. No "nothing has happened yet, here's why that's good" posture. |
| **B. Add/remove files, folders** | FilesSidebar + Review sheet + Settings | Three entry points, no single canonical flow. Defaults unknown. |
| **C. Add/remove emails** | Separate Email tab, rules system | Separate from files even though both are "scope." User has to learn two models. |
| **D. Workspace / scope view** | Scattered (see §8) | Not a first-class surface. |
| **E. Exposure ledger / activity history** | ActivityView | Log, not evidence. See §3. |
| **F. Approval queue / pending requests** | Approval happens via modal sheet | No *queue*. See §2. |
| **G. Version history for tracked workspaces** | VersionDetailView via file context menu | Buried. No session-level view. No "show me everything changed in this work block." |
| **H. Agent connection/state indicator** | Toolbar dot + tooltip | Reports state, not consequence. See §5. |
| **I. Menu bar status panel** | MenuBarPanelView | Decent skeleton. Too busy. Agent cards duplicate Overview. See §10. |
| **J. Sidebar / top-level navigation** | Three-tab segmented control | Wrong primitive. See §1. |
| **K. Inspector / detail pane** | Used for VersionDetailView, ActivityDrawer | Inconsistent — sometimes sheet, sometimes inspector. |
| **L. Settings** | SettingsView with panes (Storage / Mail / AI Apps / General) | Panes are reasonable. Defaults and copy need pass (§4). |
| **M. Empty states / error states / denial feedback** | `ContentUnavailableView` for empties; banner for errors; **nothing for denials** | Denials are invisible. This is the biggest single miss. §4. |
| **N. Microcopy** | See §4 | Pervasive. |
| **O. Typography, grid, color system** | §6, §7 | Agent color bug; grid not enforced. |

---

## §10. Menu bar panel specifics

The menu bar panel is the highest-leverage surface. Specific issues:

1. **Width is 380px and the panel is still cluttered.** Coverage label + verification status + "1 shared" + "4 rules" + "2 shields" + "Mid" sensitivity + "All activity" recording-level — seven pieces of metadata per agent in a single line, with one pixel between them. Few (*Information Dashboard Design*, ch. on at-a-glance) would flag this as failing the 5-second test.
2. **"Pause All" is red + borderedProminent.** Pause is safety, not danger. Red says *stop, something wrong*. It should be a quiet, easily-findable action, not a bright button.
3. **Work block strip appears only when active.** Good. But "Tracked edit in progress" is in caption text, the same weight as the rest of the panel. For a user stepping away from their keyboard, the menu bar panel's first sentence should be *"Claude is editing with tracking on. 14 minutes."* — in a weight that survives peripheral vision.
4. **"No governed sessions yet" empty state** misses the first-run trust moment. This is where Manifold earns or loses trust before anything has happened. Currently: thin gray text. Should be: the moment the app says, "I'm watching. Nothing has happened. Here's what I'd do if something did."
5. **Quit Manifold is a top-level button in the panel.** A user pressing ⌘Q by habit from another app can kill the daemon. The quit affordance belongs in a menu or requires confirmation when an agent is active, especially during a tracked work block.

---

## Top 10 highest-leverage issues (in order)

1. **Posture is unresolved** (§1). Fix first; everything else reshapes around the answer.
2. **Activity view is a log, not evidence** (§3). Disproportionate leverage — this is the trust-generating surface.
3. **Approvals are modal, not queued** (§2). Changes the whole agent-user-user flow.
4. **Status language reports state, not consequence** (§5). One-pass copy fix with big payoff.
5. **Denial events are invisible** (§9 row M). Biggest missed opportunity to demonstrate the product working.
6. **Agent colors follow the system accent and collide with status** (§6). Silent failure on ~20% of Mac setups.
7. **Workspace/scope is scattered across 5 surfaces** (§8). Draw the primitive first, then the views onto it.
8. **Microcopy is half-engineering** (§4). Needs a full Yifrah / Podmajersky pass.
9. **Menu bar panel is cluttered and under-weighted for peripheral vision** (§10). Pixelmator-bar specifically cares about menu bar craft.
10. **No baseline grid enforced** (§7). Caps the achievable polish.

---

## What I am *not* raising as problems

- The three-layer runtime boundary (ManifoldXPC / ManifoldAgent / ManifoldRuntime). That's architecturally correct; UI should reach through `AppRuntimeClient`, already stated in CLAUDE.md.
- The diff engine inside ActivityView. Good bones.
- The design tokens file. Decent foundation even if not enforced everywhere.
- The Table vs List decision in Files. Table is right.
- The Finder Sync extension existing at all. That's the right instinct for a daemon product.

---

## Posture call (tentative, to be confirmed in Stage 2)

**Manifold is a daemon with two visible surfaces: a menu bar panel (primary) and a transient ledger window (secondary).** The Overview tab should be removed; its contents belong in the menu bar panel. The Files and Email tabs should collapse into the ledger window. The three-tab segmented control should not exist.

This is the highest-leverage decision in the product. Stage 2 argues it in full, with the source-to-decision traceback.

---

## What runs on what

No build verification run for Stage 1 — this is a pure documentation/design-analysis pass. I read source, did not modify source.

Stage 2 next.
