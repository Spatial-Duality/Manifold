# Manifold UI — Stage 3: Surface-by-Surface Redesign

Applies the posture call and the ten principles from Stage 2 to each of the 15 surfaces. Every decision is traced to sources. Each surface section has the same shape: **Now → Problem → Decision → Rationale → Build**.

Source shorthand: DOET (Norman), AF (Cooper, *About Face*), THI (Raskin), APL (Alexander, *A Pattern Language*), NSF (Alexander, *Notes on the Synthesis of Form*), DI (Tidwell, *Designing Interfaces*), RUI (Wathan/Schoger, *Refactoring UI*), 100T (Weinschenk), MC (Yifrah), SW (Podmajersky), WID (Metts/Welfle), NS (Nicely Said), FtW (Jarrett/Gaffney), WFD (Wroblewski), ETS (Bringhurst), TwT (Lupton), DiT (Hochuli), GS (Müller-Brockmann), IoC (Albers), VT (Ware, *Visual Thinking*), VDQI (Tufte), EI (*Envisioning Information*), VE (*Visual Explanations*), BE (*Beautiful Evidence*), IDD (Few, *Information Dashboard Design*), NYS (Few, *Now You See It*), Bertin, IV (Ware, *Information Visualization*), HMW (MacEachren), DIA (Val Head), N (*Nudge*), DBC (Wendel), S&U (Cranor/Garfinkel), US (Garfinkel/Lipford), Johnny (Whitten/Tygar), HIG (Apple), BV (Bret Victor), I&S (Ink & Switch).

---

## Surface A — First-run / trust establishment

**Now.** `SetupAssistantView` sheet on first launch. Setup is framed as "get started"; success is measured by the user clicking through.

**Problem.** A trust product that celebrates click-through is training click-through. The job of first-run is to establish a *mental model* — "Manifold watches, scopes, records, can undo" — and to set a *default of nothing allowed*. Currently first-run is a setup checklist, not a model-installer.

**Decision.** First-run becomes a **three-panel conversation**, each panel standalone and leave-able. Panels: (1) "This is what Manifold does" — two sentences plus a motion loop of a file being read, tracked, reverted (DIA on motion as communication). (2) "You control scope" — empty-state view showing zero sources and zero agents, with the explicit statement *"Nothing is shared until you share it."* This is the default nudge (N). (3) "Try it" — a guided flow to add one folder and connect one agent, with a concrete "watch what happens" moment that previews the ledger.

**Rationale.** Norman (DOET): conceptual model before interface. Wendel (DBC): first-use is where intent converts to action. Nicely Said + Yifrah: tone calibration — this is the one place Manifold should be *warm and clear*, not technical.

**Build.**
- Replace SetupAssistantView with `FirstRunFlow` owning three panels
- Each panel has a max-width (≈ 640pt) for readable line length (ETS: 66 characters)
- The second panel shows the live (empty) scope view as its illustration — the onboarding is the real UI, stripped
- "Skip setup" exits to the menu bar panel, which is unambiguous about status
- Never re-show the flow; a "Show me around again" action lives in Help menu

---

## Surface B — Add/remove files, folders

**Now.** Three entry points: FilesSidebar, Review sheet, Settings > Storage. Scope changes flow through `ReviewAccessSheet` with checkboxes.

**Problem.** Multiple entry points, same job. The mental model the user has to build is "where do I go to add a folder?" — which is Alexander's test for a missing pattern: if the primitive isn't named, users have to learn the paths.

**Decision.** One canonical **Scope** view (surface D). Every "add a folder" entry point routes there. Finder extension and a drag-target in the menu bar panel are the fast paths; Scope view is the authoritative surface. Removing a folder is direct-manipulation in Scope view (select → delete key, or context menu). Every destructive action asks for confirmation and explains what becomes unavailable to which agent as a result (FtW on consequential confirmations).

**Rationale.** APL: one primitive, many views. DI: single-source-of-truth pattern for configuration. FtW/WFD on forms: the scope view is a permissions form, not a file browser; design it as such.

**Build.**
- Delete FilesSidebar's "add folder" button (surface it in Scope only) OR repurpose it as a deep link to Scope
- Drag a folder onto the menu bar icon = propose addition → goes to the approval queue as a pending scope change
- In Scope view, removing a folder shows an inline summary: *"Claude loses access to 42 files. Codex is not affected."*
- No modal sheet for scope editing. In-place toggles with an autosave indicator (BV: direct manipulation).

---

## Surface C — Add/remove emails

**Now.** Separate Email tab with a Rules sub-view; different model from files.

**Problem.** Files and email are both scope. Two different models means the user learns twice. Email also uses sensitivity/shields/rules/default-policy as separate concepts, stacked in the menu bar card — see §10 of the critique.

**Decision.** Unify under the **Scope** primitive. An email account is a source. A rule is a refinement on a source. Sensitivity level becomes a property of the source. The separate Emails tab goes away; email sources live in Scope alongside folder sources, with a different icon and sensitivity slider. Rules become an inspector pane on the selected email source, not a separate surface.

**Rationale.** APL again. HMW (*How Maps Work*) on representing different kinds of things in one spatial frame — possible and preferred when the user's action is "scope." I&S on user ownership: the user owns the scope; rules are refinements, not a separate universe.

**Build.**
- Scope view has two sections: **Folders**, **Mailboxes**. Same selection model, same context menu, same metadata grammar.
- Selecting a mailbox source opens an inspector with the rule list, sensitivity, default policy. These were the right concepts, wrong shelving.
- "Sensitivity" is renamed and mapped to three concrete outcomes — *Strict (subjects only), Normal (subjects + trusted senders), Permissive (full content)* — per Kinneret Yifrah on microcopy that describes outcomes, not settings.

---

## Surface D — Workspace / scope view

**Now.** Scattered (critique §8).

**Problem.** Manifold's single most important spatial primitive has no canonical UI.

**Decision.** **Scope** is the landing view of the Ledger window. Layout: sources as rows (files and mailboxes together), agents as columns. A filled cell = "agent has scope on this source." Empty cell = no access. This is a **coverage matrix** (Bertin on position as the strongest visual encoding). Rows are groupable by folder hierarchy / mailbox account. Header row shows agent name, status dot (fixed brand color), and count of sources in scope.

**Rationale.** Bertin: visual variables. HMW: scope is a spatial set-theoretic fact. DI: table-with-toggle pattern. IoC: agent color in header, status color in body — never collide. BV: every cell is a handle.

**Build.**
- `ScopeView` — a Table with rows = sources, columns = agents, cells = membership toggles
- Sort by name / recently touched / denial count (relevant ledger events)
- Row selection loads an inspector: source metadata, last activity, rules (for email), and a "revoke from both" action
- Multiselect for batch revoke
- Hover over a cell = tooltip *"Claude can read these 42 files in ~/Projects/Manifold."*
- When a source is newly added, cell gets a subtle entrance animation (DIA on motion as trust signal)

---

## Surface E — Exposure ledger / activity history

**Now.** `ActivityView`: single-column list of `ActivityRow`s, optional session grouping, inline diff expansion, flat time encoding.

**Problem.** Ledger is the trust-generating surface (Principle 1). Current implementation is a log. Treat like Console, read like Console, trusted like Console.

**Decision.** A **three-pane ledger window**: left column = time/session rail, center = dense table of events, right = evidence inspector.

1. **Left rail** — a vertical **time column** spanning days/sessions, with small sparkline bars for each session showing reads (blue) / writes (agent color) / denials (orange). Click selects a session or a time range. This is Tufte's small multiples + Few's at-a-glance (IDD). Position-encoded time (Bertin).

2. **Center table** — dense data table: Time | Agent | Action | Source | File | Bytes | Result. Monospaced digits, fixed-width timestamps, tabular rhythm. A single row is one event. Action column uses an **icon + plain-English verb** (principle 5): "read," "wrote," "denied," "reverted," "search." No schema strings. Writes show size-delta sparkline in a 48pt column ("+2 KB" with a micro bar). Denials have their own row style (strong orange leading edge). Selection in this table updates the right pane.

3. **Right pane — Evidence** — for a read, the file path + a "open in Finder" + who else has access; for a write, the inline diff + Revert button (already good in code); for a denial, *"Claude tried to read X at 4:12pm. Blocked — not in scope. Grant access?"* — one-click grant or reject. For a search event, the query and the files that would have matched.

**Rationale.** Tufte (BE, EI, VDQI), Few (IDD, NYS), Bertin (visual variables), Ware (VT, IV) all converge on this shape for dense event data. Bret Victor on direct manipulation: evidence should be actionable, not display-only.

**Build.**
- Replace the existing `ActivityView` List with a `NavigationSplitView` specialized for the three-pane layout
- A new `SessionRailView` showing sparkline-per-session, time-encoded vertically
- A new `EventTable` replacing FlatActivityContent; Table-native sort on any column
- `EvidenceInspector` replaces inline diff expansion (but keeps the good DiffView)
- Exports become: **session export** (markdown with sparkline-as-ASCII), **time-range export** (CSV preserving tabular structure)
- Filter chips under the table: All / Reads / Writes / Denials / Searches. Persistent. Default = Last 24h.

This is the single surface that most rewards investment. Plan for it to take the most iteration.

---

## Surface F — Approval queue / pending requests

**Now.** Modal sheet fired per-event.

**Problem.** Modal. Satisficing. False consent. See critique §2.

**Decision.** A **persistent queue** that lives in the menu bar panel and in the Ledger window.

- In the menu bar panel: a single line at the top — *"3 requests pending"* with a chevron. Always present if non-zero. Disappears at zero (not dimmed).
- Clicking the chevron expands the queue inline in the menu bar panel: each request is a card — agent, requested source, a plain-English reason, and three actions: **Not this time** (default / focused), **Allow once**, **Allow and add to scope**.
- In the Ledger window, a "Pending" chip on the left rail opens a full queue view with the same cards in a more spacious layout.

**Rationale.** Raskin (THI) modelessness. Johnny: satisficing is the enemy. S&U / US: the most researched UX failure mode in consent is the time-pressured single-yes dialog. Queue + deferred approval + focused "Not this time" default is the well-studied counterfactual. N: default nudge correct.

**Build.**
- `ApprovalQueue` model (may already exist in policy; extend)
- `ApprovalQueueStripView` in menu bar panel, collapsed by default
- `PendingRequestCard` with three-action row
- Every request has a **silent grace period** — if the agent stops asking for 30s, the card greys (MC: informational microcopy — *"Agent is waiting. No rush."*)
- Never fire a system notification for an approval. Notifications are interrupts; the queue is the affordance.

---

## Surface G — Version history for tracked workspaces

**Now.** `VersionDetailView` reachable via file context menu or a right-side inspector after opening a file.

**Problem.** Buried. Two entry points (sheet / inspector). No session-level overview — "show me everything Claude changed in the last work block" is not a one-click thing.

**Decision.** Version history is a **facet of the Ledger**. For any write event in the event table, the evidence pane shows the diff and a **history strip**: "this file, last 10 versions" — sparkline of size-delta over time, each dot clickable for the old content. A work block gets its own session row in the rail, and selecting it shows a **changeset view**: all files written in that block, in a file-tree with +/− diff counts per file — Tufte's VE on cause-and-effect visualizations.

**Rationale.** I&S (Capstone) on history as first-class. Tufte on confections (BE). Cooper on posture — history belongs where evidence lives, not as its own application surface.

**Build.**
- `ChangesetView` for work-block rows in the Ledger
- `FileHistoryStrip` in the evidence pane
- Cross-link: clicking a file path in the Scope view's inspector opens the Ledger filtered to that file

---

## Surface H — Agent connection / state indicator

**Now.** Toolbar dot + tooltip. Status labels are state, not consequence.

**Problem.** Principle 10. The indicator lies by default — shows "Connected" when meaningful work may be blocked.

**Decision.** The indicator is **never a single dot in a toolbar** on a surface that isn't the menu bar. The menu bar icon *is* the status indicator. It has four visual states, each distinguishable in peripheral vision:

1. **Idle** (dot, muted) — Manifold running, no agent active, no queue
2. **Active** (dot, agent-color fill, animated pulse at 0.5Hz) — at least one agent active; pulse is a peripheral signal, not a foreground one (DIA; reduce-motion = static)
3. **Attention** (badge dot overlay with count) — approval queue non-empty
4. **Stopped** (dot with slash) — runtime disconnected or Manifold paused-all

The menu bar icon's tooltip and the panel header sentence map to **consequences**: *"Claude can see 4 folders. Last read: README.md, 12 min ago."* No "Connected." No "Runtime not connected" unless it's actually the truth.

**Rationale.** Cooper on feedback. Norman on signifiers. Few on dashboard honesty. Principle 10.

**Build.**
- Four SF-symbol-composed icons as templates (monochrome for menu bar)
- Pulse animation only when active, muted on reduce-motion
- Attention badge uses Manifold orange (status), not red (danger)

---

## Surface I — Menu bar status panel

**Now.** 380pt wide, header + work block strip + two agent cards + quick actions. Cluttered per-card (critique §10).

**Problem.** The primary surface. Currently an imitation of the Overview tab.

**Decision.** New layout, 360pt wide, four stacked regions:

1. **Status header** (48pt tall) — one-sentence consequence status, agent-color dot(s), no labels. Font: `Typ.heading` weight medium, not caption. If an active work block exists, the sentence is *"Claude is editing with tracking — 14 min."* This is the peripheral-vision surface (Ware VT).
2. **Queue strip** (visible only when pending > 0) — expandable card strip for approvals. See surface F.
3. **Agent summary** (collapsed by default, each ~40pt) — one row per agent: fixed color dot, name, one-line consequence (*"4 folders · quiet for 12 min"*), chevron. Expanding reveals scope glance and the three actions (Pause / Review scope / View ledger). Collapsed by default because an active trust product rewards calm; expansion is deliberate.
4. **Footer actions** — Open Ledger (⌘O), Settings (⌘,), Pause All (never red; a quiet destructive affordance), Quit (guarded with confirmation if any agent is active).

**Rationale.** Cooper posture. Raskin locus of attention (peripheral vision budget). Few dashboard-at-a-glance. RUI on hierarchy: one load-bearing sentence, everything else subordinate.

**Build.**
- Rewrite `MenuBarPanelView` around a `VStack` with four `SectionBlock`s
- Move Pause All from header to footer; restyle as secondary, not prominent
- Guard Quit with `NSAlert`-style confirmation when any agent active or a work block is live

---

## Surface J — Sidebar / top-level navigation

**Now.** Three-tab segmented control in toolbar.

**Decision.** Delete. The main window becomes the **Ledger window**. Its sidebar is a narrow nav rail with four items, and the rail style is macOS-native (`NavigationSplitView` sidebar):

- **Ledger** (default; surface E)
- **Scope** (surface D)
- **Queue** (surface F, with count badge)
- **Versions** (surface G — session-level changesets)

No Emails tab. No Overview tab. Settings is in ⌘,.

**Rationale.** Cooper posture → the Ledger window has one job (evidence + actions on evidence), sidebar navigates evidence facets. HIG on native sidebar. APL on letting the primitives name the views.

**Build.**
- `MainView` replaced by `LedgerWindowView` owning a NavigationSplitView
- Remove the Picker from toolbar; toolbar has: search, filter, export, connection indicator (muted — consequence text, not label)

---

## Surface K — Inspector / detail pane

**Now.** Used for VersionDetailView and ActivityDrawer, both on the same window, inconsistently invoked.

**Decision.** One inspector per sidebar view. Its content is the evidence pane for the selected item:

- In **Ledger**: selected event → evidence (file, diff, revert, access history)
- In **Scope**: selected source → metadata, rules, recent denials, revoke
- In **Queue**: selected request → full context, actions, related previous denials/grants
- In **Versions**: selected file → history strip, diff browser

**Rationale.** DI: master/detail/inspector pattern. RUI on hierarchy: the inspector is always the noun of the current row. BV: details are not a popup; they're a continuous surface.

**Build.**
- `.inspector(isPresented:)` bound per-view but the inspector view conforms to a single `EvidencePane` protocol rendering the selected item
- Keyboard shortcut to toggle inspector consistent across sidebar views

---

## Surface L — Settings

**Now.** `SettingsView` with Storage / Mail / AI Apps / General panes.

**Decision.** Keep the general structure; rewrite copy (principle 5), and reorganize panes around primitives:

- **General** — launch at login, menu bar icon visibility, reduce motion, telemetry (off by default — principle 3)
- **Agents** — connect/disconnect Claude, Codex, and any future. Per-agent advanced options (access recording level, rate caps).
- **Storage** — database location, retention, snapshot size limits, version-history retention.
- **Mail** — account connections (low-surface — the scope view owns day-to-day mailbox management).
- **Advanced** — runtime controls, log level, restart runtime. Hidden from first-time users.

**Rationale.** FtW: forms are conversations; group by user intent. NS: tone should shift from "product" to "precise" in settings — users here want clarity and precision, not warmth.

**Build.**
- Rename panes per above
- Move anything engineering-flavored into Advanced
- Every switch has a two-sentence description: what it does, what trade-off it makes. No naked toggles (FtW).

---

## Surface M — Empty states / error states / denial feedback

**Now.** `ContentUnavailableView` for empties; a generic banner for errors; denials are invisible unless user filters Activity.

**Problem.** Missed three distinct trust moments.

**Decision.** Three different surface patterns.

**Empty.** Empty is the desired default (principle 3). Language is congratulatory-neutral: *"Nothing shared yet. Manifold is running."* — not "No Sources." Every empty state states the *Manifold-is-watching* fact (principle 1).

**Error.** Named by consequence: *"Can't reach Manifold's runtime. Nothing is being recorded right now."* Action: Reconnect. Timestamps on errors. Errors dismiss on success, not on user click. Principle 10.

**Denial.** Get a promoted surface. When an agent is denied, the denial:
1. Appears in the Ledger with its own row style (strong leading orange — Bertin: color as categorical signal, not hierarchical)
2. Counts against the menu bar icon's attention budget if unusual (e.g., sustained denials against the same source) — a trust product should notice patterns (NYS)
3. Is *quietly celebrated* in language: *"Claude tried to read ~/Finances at 4:12pm. Blocked — not in your workspace."* No scolding tone.

**Rationale.** MC + SW + NS on denial tone. BE on evidence under scrutiny. 100T on cognitive ergonomics — denials are a learning moment for the user's model.

**Build.**
- A `DenialRow` variant in the event table
- A `DenialInspector` with action: "Grant access" or "Always deny"
- A tiny "denial cluster" detector in the store → flags unusual patterns (e.g., same source, 5+ denials in 24h) and surfaces a one-line advisory in the menu bar panel

---

## Surface N — Microcopy

**Now.** Half product / half engineering (critique §4).

**Decision.** A **strings catalog** owned by design, checked into the repo, with tone guidance. Every user-visible string is pulled from the catalog. Translations in one place. Engineering can't sneak in schema strings because there's no ad-hoc NSLocalizedString.

Tone guidance, cribbed directly from Nicely Said + Yifrah + Podmajersky:

- **First-run and empty:** warm, clear, second-person, present tense. Short sentences.
- **Status and ledger:** factual, consequence-first, past tense for events, tabular feel.
- **Denial:** calm, past tense, no blame, offer remediation.
- **Errors:** name the consequence, name the action, name the time. No exclamation marks.
- **Confirmations (destructive):** name the specific thing that will be lost. Jarrett: "Remove ~/Finances from Claude's scope? Claude loses access to 42 files."
- **Settings:** precise, terse, no jokes.

**Build.**
- `Strings.swift` as the catalog
- Replace every hard-coded string in views
- A tone-linting doc that says what kind of sentence belongs where
- Evans (*Do I Make Myself Clear?*): aggressive prune of passive voice, especially in denials and errors

---

## Surface O — Typography, grid, color system

**Now.** `DesignTokens.swift` has roles; no grid; agent colors are system semantic.

**Decision.**

**Typography.** Adopt a 4pt baseline grid. `Typ` roles unchanged in names but tuned so that every row height is a multiple of 4pt. Body = SF 13 @ 20pt line height; caption = SF 11 @ 16pt; numeric caption = SF Mono 11 @ 16pt. Headings: sectionTitle SF 17 semibold @ 24pt; heading SF 13 semibold @ 20pt. Ledger table row height = 28pt. Sparkline cells align to 20pt rhythm. (Bringhurst, Hochuli, Lupton, GS.)

**Grid.** 8pt horizontal grid, 4pt vertical baseline. Menu bar panel width = 360pt (multiple of 8). Ledger columns snap to 8pt. Every `padding(.section)` = 16pt, `.edge` = 24pt, `.standard` = 8pt, `.tight` = 4pt.

**Color.**

Agents — fixed Manifold brand colors, hand-picked, not `Color.blue` / `Color.purple`:
- **Claude** — #3B6DE6 (light) / #6A94F5 (dark). Not system blue.
- **Codex** — #7C46D6 (light) / #A67AE8 (dark). Not system purple.

Status — system-semantic but with Manifold's tonal overrides so the ledger reads calmly:
- **Active** — system green, muted
- **Paused** — system orange, muted
- **Attention** — stronger orange, only used for queue and denial hints
- **Danger** — system red, reserved for errors that prevent the product from doing its job

Every status uses a second channel (icon shape). Never color-alone. Every agent color passes WCAG AA against both surfaces in both appearances.

**Rationale.** IoC (Albers): color is relational. Bertin: agent = categorical (hue), status = ordinal (value). Ware IV: second channel mandatory. ETS/TwT/DiT: vertical rhythm. GS: 8pt horizontal grid.

**Build.**
- `DesignTokens.swift` gains `AgentPalette` with fixed hex values and dark variants
- `Spacing` tuned against 4pt baseline; a lint step or snapshot test prevents drift
- A one-page design-tokens reference ships in `/design/tokens.md`

---

## Cross-surface: motion

Motion is not in the 15-surface list but touches A/F/M.

**Decision.** Motion communicates three things:
1. **Trust signals** — when a source is added, an animation lands the new row into the Scope matrix (300ms ease-out). When a write is reverted, the file row gets a green pulse (400ms).
2. **State changes** — agent pause/resume, queue count change, use `Anim.stateChange`.
3. **Peripheral signals** — the menu bar icon's active-pulse is 0.5Hz, low-amplitude, reduce-motion disables.

No decorative motion. No springs that overshoot. Val Head: ease-out lands; ease-in leaves; durations in the 150–400ms band.

---

## Cross-surface: keyboard

**Decision.** Manifold publishes a Keyboard Shortcuts sheet (from Help menu) documenting:
- Menu bar panel: ⌘⇧M to open, ⌘P pause all, Esc close
- Ledger: ⌘O open, ⌘F filter, ⌘E export, ⌘⇧R revert (with confirmation), ⌘[/⌘] nav sidebar, Space toggle inspector
- Queue: ↑↓ navigate, Return = Not this time (default — principle 3), ⇧Return = Allow once, ⌥Return = Allow and add to scope

Every modifier is named in the tooltip, not just shown (HIG, accessibility).

---

## Cross-surface: what is deleted

Clear list, for candor:

- **Overview tab** (entire surface, with `OverviewView.swift`, `AgentPolicyCard.swift`)
- **Emails tab** (rolled into Scope / Ledger; `EmailView`, `EmailRulesView`, `EmailsTab` private struct)
- **Three-tab segmented picker** in MainView toolbar
- **Modal approval sheet** (`ReviewAccessSheet` — replaced by inline/scope-view editing + queue cards)
- **Red Pause All in menu bar header**
- **"Runtime not connected" as a status label in headers** (replaced with consequence text)
- **Every bare event schema string in user-visible UI**
- **Agent colors pegged to system accent**

---

## Traceability summary

Every surface maps to at least one principle and at least one source. Rough audit:

| Surface | Primary principles | Load-bearing sources |
|---|---|---|
| A | 3, 5, 10 | DOET, DBC, NS, MC |
| B | 4, 2, 3 | APL, DI, FtW |
| C | 4 | APL, HMW |
| D | 4, 8 | APL, Bertin, HMW, BV |
| E | 1, 7, 8 | VDQI, EI, BE, IDD, NYS, Bertin, IV, BV |
| F | 2, 3 | THI, Johnny, S&U, US, N |
| G | 1, 8 | I&S, BE, VE |
| H | 10, 1 | AF, DOET, IDD |
| I | 3, 7, 10, 5 | AF, THI, IDD, HIG, RUI |
| J | posture | AF, APL, HIG |
| K | 8 | DI, BV, RUI |
| L | 5 | FtW, NS, MC |
| M | 5, 1, 10 | BE, MC, NS, SW, 100T |
| N | 5 | MC, SW, NS, WID, Evans |
| O | 7, 6 | ETS, DiT, TwT, GS, IoC, Bertin, IV |

No surface decision unsupported. Where a surface has more than one principle in tension, the load-bearing-principle-hierarchy from Stage 2 resolves the tie (honesty > trust > posture > modelessness > defaults > language > scope-as-primitive > direct-manipulation > density > color > accessibility — accessibility last only because it's structural, not because it's low priority).

---

## Open questions for Amar

These are real, not rhetorical. My answers are guesses.

1. **Do you want Manifold to have a Dock icon at all?** My recommended posture (daemon + menu bar) argues for no Dock icon in normal operation — only when the Ledger window is open. This is HIG-supported (see `LSUIElement`) and matches Things/Fantastical for comparable products. Cost: loses ⌘Tab ability. Gain: stronger daemon identity, less "come live here" signal.

2. **Is the Ledger window single-instance or many-instance?** My guess is single. Opening "Open Ledger" from anywhere brings the one window forward.

3. **How loud should attention-worthy denials be?** Silent in ledger (always there), visible badge on menu bar icon (attention), never system notification (principle 2). Unless you want more.

4. **Auto-approve affordances.** Cooper + Whitten/Tygar would both say *never*. But some users will legitimately want *"auto-approve this known-safe agent for this known-safe folder."* My read: offer it, require explicit per-pair opt-in, audit it in the ledger with its own color, surface a weekly *"auto-approvals in last 7 days"* advisory. Disagreement welcome.

5. **Terminology.** Is *source*, *scope*, *session*, *exposure*, *workspace*, *track* the right set? Or should any be renamed for the user-facing layer? My vote: keep source, scope, session; rename *exposure* to *access event* in UI; rename *workspace* to *tracked edit* since that's what users will call it.

Stage 4 next: HTML visual spec.
