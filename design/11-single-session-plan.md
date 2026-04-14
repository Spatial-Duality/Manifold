# Manifold UI — Stage 11: Single-session sequential plan

The whole migration, executed by one Claude Code session, top to bottom,
no parallelism, no feature flags. Replaces Stages 9 and 10 for actual
execution. Those earlier docs remain as reference for surface decisions
and acceptance criteria.

---

## 1. Framing — what "single session" actually means

A Claude Code session can run for hours and across sittings; it cannot
produce all of this output in a single turn. The realistic shape is:

- **One long-running session** (or a resumable one), working through the
  phases below in strict order.
- **Checkpoints at every phase boundary**, where the agent pauses, runs
  verification, commits, and waits for a "continue" before starting the
  next phase.
- **No feature flag.** The Stage-9 `NEW_UI` flag existed to let parallel
  agents fan out. Single session doesn't need it — each phase replaces
  the old surface in place when the new one compiles and launches.
- **Deletions are grouped at the end** (Phase 9). The agent does not
  delete any legacy file during the building phases; this keeps the app
  buildable if a phase reveals a reverse dependency nobody noticed.

If the session times out or the context fills, resume by pasting the
same kickoff prompt and pointing at the last-completed phase.

---

## 2. The plan — nine phases in order

Every phase ends with a commit, a verification pass, and a checkpoint.
The agent does not start phase N+1 until phase N is green.

### Phase 1 · Foundation (tokens, primitives, data types, shell, menu bar)

Combines what Stages 9/10 treated as Phases 0+1+2. The single-session
agent does them together because each depends on the last and there's
no benefit to splitting.

**Build:**
- Rewrite `Components/DesignTokens.swift` — fixed Manifold palette
  (agent colors NOT tied to system accent), light + dark variants,
  gradient helpers, shadow presets, typography roles, motion presets.
- Rewrite `Components/Spacing.swift` — 4pt baseline, 8pt horizontal.
- New `Components/Primitives/` containing all 13 shared components
  enumerated in `design/09-migration-plan.md` §1: LiquidGlassMaterial,
  ManifoldPalette, GradientAvatar, AgentStatusDot, SessionChip,
  SparklineBar, TriStateCheckbox, SegmentedToggle, CommitLadder, Pill,
  FileTypeIcon, EmptyStateIllustration, KbdLabel. Each with working
  `#Preview`.
- Add data primitives to ManifoldRuntime / ManifoldKit:
  `SessionRecord`, `ApprovalRequest`, `Rule`, `ScopeEntry`,
  `DenialEvent`, `SessionHistoryEntry`, `SessionDrift`, `SessionDraft`,
  `ApprovalAnswer`, `RevertOutcome`.
- Extend `PolicyModel`: `activeSession` (adapter over `activeWorkBlock`
  for now), `recentSessions`, `pendingRequests`, `drift(for:)`.
- Extend `ManifoldStore` to expose the new read surface.
- Introduce `ManifoldCommands` protocol for all writes; inject a
  default implementation.
- Build `Views/LedgerWindowView.swift` as the new root window —
  `NavigationSplitView` with 5 destinations (Activity, Access, Mail,
  Requests, Rules), each routed to a placeholder `EmptyView` for now.
- Build `Views/Chrome/{NavSidebar, IntegratedToolbar, StatusBar}.swift`.
- Rebuild `Views/MenuBar/MenuBarPanelView.swift` fully — all four
  states per `design/html/menubar.html`, using real store reads.
  Menu bar is done fully in this phase because it is the primary
  surface and unblocks user testing for everything that follows.
- Wire `ManifoldApp.swift` to present the new `LedgerWindowView` and
  the new `MenuBarPanelView`. Old `MainView.swift` remains on disk but
  is no longer referenced from the Scene graph; it dies in Phase 9.

**Unit tests:** Session reload drift math, Rule predicate evaluation,
ManifoldCommands protocol conformance.

**Verify:**
```
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
    swift build && swift test
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
    xcodebuild -project Manifold.xcodeproj -scheme Manifold \
               -configuration Debug \
               -derivedDataPath /tmp/manifold-derived-data \
               build CODE_SIGNING_ALLOWED=NO
```

**Launch verify:** app opens, menu bar panel renders all 4 states when
the store state matches. The Ledger window opens but all destinations
are placeholders.

**Checkpoint:** commit as `phase-1: foundation, tokens, primitives,
data, shell, menu bar`. Stop. Ask user to confirm before Phase 2.

---

### Phase 2 · Activity (primary trust-generating surface)

Why second: the Activity ledger is what proves the whole design works
on real data. If it renders, the primitives are correct. Builds first
confidence.

**Build, per `design/html/activity.html`:**
- `Views/Activity/ActivityWindowView.swift` — three-pane layout
- `Views/Activity/SessionRail.swift` — vertical session list with
  per-session sparklines via `SparklineBar`, sticky date headers
- `Views/Activity/EventTable.swift` — 7-column dense grid, monospaced
  time column, denial rows with orange leading edge, write-row inline
  size-delta sparklines
- `Views/Activity/EvidenceInspector.swift` — kicker + title + mono path
  + stats + `DiffView` (reuse existing component) + "Why allowed" card
  + file-history sparkline + related-files list + Revert/Open actions
- Denial detail sub-state: selected denial row replaces the evidence
  body with the orange "Claude tried to read" card + remedy actions
- Toolbar filter chips: All / Reads / Writes / Denials / Searches /
  Tracked edits
- Wire into `LedgerWindowView`'s Activity destination, replacing the
  Phase-1 placeholder

**Verify:** `xcodebuild` + launch, click Activity, scroll events, click
rows, verify inspector updates, trigger a revert against a test fixture.

**Checkpoint:** commit `phase-2: activity`. Stop.

---

### Phase 3 · Access (folders, files, session, history, empty)

Five sub-views, per `design/html/access.html`. Biggest single phase.

**Build:**
- `Views/Access/AccessWindowView.swift` — tab router (Folders / Files
  / Session / History)
- `Views/Access/FoldersMatrixView.swift` — folder × agent coverage
  matrix with bulk-select
- `Views/Access/BulkActionBar.swift` — floating action bar at matrix
  bottom when multi-select active
- `Views/Access/FileTreeInspector.swift` — tri-state checkboxes via
  `TriStateCheckbox`, indent guides, override dots, exclusion traces,
  rules list for selected folder
- `Views/Access/FilesFlatView.swift` — flat file list with version
  chips (write count, reverted, original), session/modified columns
- `Views/Access/VersionTimelineInspector.swift` — vertical version
  timeline with per-version dots, selected-version diff, Revert-to-vN
- `Views/Access/SessionDiffView.swift` — live overlay: Added /
  Removed / Inherited sections with distinct accents, session head bar
- `Views/Access/SessionAdditionInspector.swift` — session context,
  Promote to default / Remove actions
- `Views/Access/HistoryListView.swift` — past sessions grouped by day
  with Resume button
- `Views/Access/SessionDetailInspector.swift` — drift-vs-now callout
- `Views/Access/EmptyFoldersView.swift` — folders-only empty state
  (no mailbox CTA)

**Verify + launch:** add a folder, drill file tree, trigger a denial,
run an agent write with tracking on, revert from Files view version
timeline, reload a past session, observe drift.

**Checkpoint:** commit `phase-3: access`. Stop.

---

### Phase 4 · Mail (Active Backup style)

Five sub-views, per `design/html/mail.html`. Second-biggest phase.

**Build:**
- `Views/Mail/MailWindowView.swift` — tab router (Mailboxes / Threads /
  Session / History)
- `Views/Mail/MailboxesMatrixView.swift` — mailbox × agent × sensitivity
- `Views/Mail/SensitivitySelector.swift` — three-option segment
  (Subjects only / Trusted senders / Full content) with bar indicators
- `Views/Mail/MailboxInspector.swift` — sensitivity selector, global
  rules banner, top senders list with colored discs, labels tree
- `Views/Mail/ThreadsView.swift` — **four-column body** (nav sidebar +
  sender rail + thread table + minimal inspector)
- `Views/Mail/SenderRail.swift` — Accounts / Top senders / Folders /
  Smart filters, with colored initials discs
- `Views/Mail/ThreadTable.swift` — dense rows, checkbox · sender disc ·
  (sender + subject on two lines) · date · agents · ⋯, session-green
  vs default-blue checkboxes, excluded-by-rule rows dimmed orange
- `Views/Mail/ThreadInspector.swift` — subject, first-line preview card
  (one row, italic; NOT a reading pane), visible-to-Claude metadata
  grid, messages list
- `Views/Mail/MailSessionView.swift` — Added / Removed / Inherited
- `Views/Mail/MailHistoryView.swift` — past mail sessions with resume
- `Views/Mail/EmptyMailView.swift` — envelope illustration, primary
  "Connect a mailbox" with provider chips, dashed drag-and-drop alt

**No reading pane anywhere.** Stage 8 Active Backup posture is load-
bearing; reject any Apple-Mail chrome that creeps in.

**Verify + launch:** connect mailbox, pick sender, check threads, start
session with mail additions, finish, reload.

**Checkpoint:** commit `phase-4: mail`. Stop.

---

### Phase 5 · Requests (replaces modal approval)

Per `design/html/requests.html`.

**Build:**
- `Views/Requests/RequestsWindowView.swift`
- `Views/Requests/PendingQueueView.swift`
- `Views/Requests/ApprovalCard.swift` — agent avatar + headline + tags
  + code-pill target + italic context + `CommitLadder` with 4 buttons
  (Not this time focused / Once / For session / Add to default). Session
  button hidden when no session live. Keyboard: ↩ ⇧↩ ⌥↩ ⌘↩.
- `Views/Requests/RecentAnswersView.swift` — same card shape with
  answer-chip in top-right, grouped by hour / day
- `Views/Requests/PatternDetectionInspector.swift` — auto-rule
  suggestion with 14-day denial chart when user denies same pattern 3+
- `Views/Requests/EmptyRequestsView.swift` — daemon-recedes check mark
  + how-it-works card

**Wire the agent request emitter** to insert into the
`ApprovalRequest` queue rather than firing a modal. Find every call
site that currently presents `ReviewAccessSheet` and redirect to the
queue-insert API on `ManifoldCommands`.

**Verify:** trigger an agent read outside scope, confirm card appears,
test all 4 commitment actions including keyboard. No modal fires.

**Checkpoint:** commit `phase-5: requests`. Stop.

---

### Phase 6 · Rules (global policy surface)

Per `design/html/rules.html`. Three tabs + new-rule sheet.

**Build:**
- `Views/Rules/RulesWindowView.swift` — Email / Files / Agents tabs
- `Views/Rules/FilesRulesView.swift`, `EmailRulesView.swift`,
  `AgentsRulesView.swift`
- `Views/Rules/RuleCard.swift` — sentence with code chips, seeded/user
  pill, scope pill, confident-slot toggle
- `Views/Rules/BlastRadiusPreview.swift` — "4 files match", "0 in
  shared folders", "14 blocks this month"
- `Views/Rules/NewRuleSheet.swift` — floating sheet over blurred parent
- `Views/Rules/RuleBuilder.swift` — three-picker subject/verb/object
  grammar, no regex by default, Advanced toggle
- `Views/Rules/LiveMatchPreview.swift` — attention-orange card with
  count + sample matches

**Seed migration:** on first launch under the new UI, seed the default
safe rules (*.env, *.pem, .ssh/, .aws/, credit-card redaction, SSN
redaction, never-write-to-.git/) if the user has none.

**Verify:** create a new rule via the sheet, watch live match count,
toggle it, trigger the auto-rule suggestion from Recent answers.

**Checkpoint:** commit `phase-6: rules`. Stop.

---

### Phase 7 · First-run + Session sheets

Per `design/html/firstrun.html` and `design/html/session-start.html`.

**Build:**
- `Views/FirstRun/FirstRunFlow.swift` — three-panel orchestrator
- `Views/FirstRun/Panels/Concept.swift` — metaphor + motion loop
- `Views/FirstRun/Panels/Defaults.swift` — real empty Access as
  illustration, "Nothing is shared until you share it"
- `Views/FirstRun/Panels/GuidedAdd.swift` — single folder CTA
  (NO mailbox card, explicit per Stage 5 empty-view decision)
- `Views/Session/SessionStartSheet.swift` — short form (name /
  duration / base-radio / agents / track-writes)
- `Views/Session/ReloadDriftSheet.swift` — same shape + drift preview

Wire ⌘N in menu bar to `SessionStartSheet`. Present `FirstRunFlow`
when the store reports no sources shared and no flow completed.

**Verify:** fresh user home, launch → first-run renders correctly →
skippable → idle menu bar → ⌘N → session starts → finish → reload
from Recent shows drift preview.

**Checkpoint:** commit `phase-7: first-run + sessions`. Stop.

---

### Phase 8 · Settings copy pass

Per Stage 3 §L. No visual rebuild — the new tokens already apply.

**Do:**
- Visit each pane in `Views/Settings/*`
- Rename Storage / Mail / AI Apps / General panes to the Stage-3
  structure (General / Agents / Storage / Mail / Advanced)
- Move anything engineering-flavored to the new Advanced pane
- Every toggle gets a two-sentence description per FtW
- Run the microcopy tone pass (Stage 5)

**Verify:** `xcodebuild`, visit each pane, no visual regression.

**Checkpoint:** commit `phase-8: settings copy pass`. Stop.

---

### Phase 9 · Cleanup & deletions

This phase removes every legacy file. Until now nothing has been
deleted. Doing it all here protects against the "replacement looked
fine but reveals a reverse dependency" class of bug.

**Rename first, delete second.** In `PolicyModel` and `ManifoldStore`,
rename every remaining `workBlock` identifier to `session`, remove
the adapter introduced in Phase 1. Run `swift build` after each group
of renames.

**Then delete, in this order:**

Root views:
- `Views/MainView.swift`
- `Views/OverviewView.swift`
- `Views/AgentPolicyCard.swift`
- `Views/AgentFocusControl.swift`
- `Views/ActivityView.swift`
- `Views/ActivityRow.swift`
- `Views/ActivityDrawer.swift`
- `Views/FilesView.swift`
- `Views/FilesDashboardView.swift`
- `Views/FilesSidebar.swift`
- `Views/SourcesTableView.swift`
- `Views/ReviewAccessSheet.swift`
- `Views/ReviewChangesSheet.swift`
- `Views/WorkBlockBannerView.swift`

Versions (replaced by Files view's version timeline):
- `Views/Versions/VersionsView.swift`
- `Views/Versions/VersionDetailView.swift`
- `Views/Versions/SnapshotRow.swift`

Library:
- `Views/Library/EmailAccountSetupView.swift`

Setup (the first-run replacement):
- `Views/Setup/SetupAssistantView.swift`
  (keep `ConnectClaudeSheet`, `ConnectCodexSheet`, `AddMailAccountSheet`)

Email subtree — all 23 files:
- `Views/Email/EmailView.swift`
- `Views/Email/MessageList/*.swift` (5 files)
- `Views/Email/ReadingPane/*.swift` (6 files)
- `Views/Email/Rules/*.swift` (7 files)
- `Views/Email/ShareWithCowork/ShareWithCoworkSheet.swift`
- `Views/Email/Sidebar/*.swift` (6 files)
- `Views/Email/SmartMailbox/SmartMailboxEditor.swift`

Components:
- `Components/AgentBadge.swift`
- `Components/Badge.swift`
- `Components/StatusBadge.swift`
- `Components/ColorIndicator.swift`
- `Components/DetailLine.swift`
- `Components/LiveCheckRow.swift`
- `Components/RuleFormComponents.swift`
- `Components/TrackChangesToolbarContent.swift`

For each deletion:
1. Delete from disk
2. Remove the entry from `Manifold.xcodeproj/project.pbxproj`
3. Run `swift build` after every ~5 deletions to catch reverse
   dependencies immediately

After all deletions, reduce `ManifoldApp.swift` to a clean Scene graph:
`LedgerWindowView` + `MenuBarExtra { MenuBarPanelView }` + `Settings {
SettingsView }` + the first-run presentation rule.

**Final verification:**
```
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
    swift build && swift test

env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
    xcodebuild -project Manifold.xcodeproj -scheme Manifold \
               -configuration Release \
               -derivedDataPath /tmp/manifold-derived-data-final \
               build CODE_SIGNING_ALLOWED=NO

# Nothing should match:
git grep -l "WorkBlock\|OverviewView\|ReviewAccessSheet\|ActivityDrawer\|AgentBadge" -- '*.swift'
```

**Launch from clean state:**
```
rm -rf ~/Library/Containers/com.spatialduality.manifold
open /Applications/Manifold.app   # or from DerivedData
```
Walk through: first-run → guided folder share → menu bar states →
each sidebar destination → start session → finish session → reload →
create a rule → answer a request from the queue.

**Checkpoint:** commit `phase-9: cleanup, deletions, final verify`.
Done.

---

## 3. Review — is this order right for one session?

Gone through three times. Observations:

- **Foundation first is forced.** Nothing else compiles without
  primitives, data types, or the shell. Phase 1 is the critical path.

- **Activity second, not last, is deliberate.** Stage 9 implicitly
  wanted to build the most complex surface first to validate the
  primitives. Activity does that with less scope than Access or Mail —
  three pane types + one table. If Activity works, Access/Mail will
  work because they are visual variations on the same chrome.

- **Access before Mail is forced by dependency.** Access introduces
  the file tree + version timeline that nothing else uses, but its
  matrix view is the pattern Mail's Mailboxes view copies. Building
  Access first gives Mail a reference implementation.

- **Requests before Rules is deliberate.** Requests reveals the
  auto-rule pattern-detection flow that Rules consumes. Building
  Requests first means Rules has real denial data to preview against.

- **First-run late, not early, is correct.** First-run presents the
  real empty Access view as its illustration — so Access has to exist.
  First-run is also lowest-priority for internal testing: you run it
  once, then never again on your test account.

- **Settings penultimate.** It's the least dependent surface; it can
  slot in anywhere after Phase 1. Doing it ninth lets every copy pass
  from prior phases inform the Settings copy pass.

- **Cleanup last is non-negotiable.** Deleting during building risks
  discovering a reverse dependency (a deleted type that some other
  legacy file imports). Saving deletions means every deletion runs
  against a known-good new surface.

**Risks specific to single-session execution:**

- **Context length.** If the session runs long, the agent's context
  fills. The checkpoint protocol (commit + stop at every phase)
  mitigates this — each phase can be a fresh session that reads the
  plan, picks up the last committed state, and works the next phase.

- **Agent drift.** Long sessions drift stylistically. Every phase
  starts by re-reading `design/CONTRACTS.md` (if Phase 1 produced one)
  or the relevant HTML mockup. Re-grounding matters.

- **Irreversible merges.** No branch scaffolding. If a phase goes bad,
  `git reset --hard` to the prior commit. Don't force anything through.

- **Build time.** Full `xcodebuild` + `swift test` after every phase
  adds up. If verification becomes a bottleneck, accept partial
  verification (only the surface just built) during Phases 2–8, and
  do a full-project verify only at Phase 9.

Order is correct. Single-session execution is viable with checkpoints.

---

## 4. The kickoff prompt (copy-paste into Claude Code)

Paste this at the start of a session. The agent will work through
Phase 1, commit, and stop. Paste "continue" (or the prompt again
pointing at the next phase) to proceed.

```
You are executing the Manifold UI migration end-to-end, single session,
phases in order. You are working on the main repo directly; no
worktrees, no parallel agents, no feature flag.

READ FIRST in this order:
- /CLAUDE.md — project rules, verification commands, XPC boundary,
  editing rules
- /design/11-single-session-plan.md — THIS FILE, your authoritative plan
- /design/09-migration-plan.md — file-level build/delete specs,
  referenced by Phase 9
- /design/03-surface-redesign.md — surface-level decisions
- /design/02-posture-and-principles.md — the ten principles that
  resolve any design question
- /design/html/*.html — acceptance references for each UI phase

EXECUTION PROTOCOL:
1. Work through the nine phases in /design/11-single-session-plan.md §2
   in strict order. Never start a phase before the prior phase has
   committed and verified green.
2. After each phase:
   a. Run the phase's verify commands; report output.
   b. Launch the app (macOS only) and walk through the phase's launch
      verification checklist.
   c. Commit in small logical chunks with conventional commit messages
      starting "phase-N: <summary>".
   d. Report "Phase N complete. <one-line summary>. Ready for Phase
      N+1 on your confirmation." then STOP. Do not auto-continue.
3. If a phase verify fails, DO NOT move on. Debug until green. If
   stuck for more than 30 minutes of real work, report the blocker
   and stop.
4. NEVER delete any legacy file until Phase 9. During building
   phases, old files remain on disk but are no longer wired into the
   Scene graph. Untouched.
5. NEVER edit `Manifold.xcodeproj/project.pbxproj` by hand for new
   file additions — let Xcode do it. For deletions in Phase 9, remove
   entries surgically.
6. Use SF Symbols for all icons. Use ManifoldPalette colors; never
   `.blue`, `.purple`, or any raw `Color.red`.
7. Every new view's public body uses `LiquidGlassMaterial` or a
   primitive. No ad-hoc `.background(...)` stacks.
8. Reduce-motion and accessibility labels are mandatory on every
   interactive element, not optional.

WHEN YOU START: print "Starting Phase 1 — Foundation" then read the
files listed above and begin building. Commit frequently. Stop at
Phase 1's checkpoint.

WHEN YOU FINISH PHASE 9: run the full acceptance checklist from
/design/09-migration-plan.md §8 and confirm every box. Then stop and
announce migration complete.
```

---

## 5. Resume prompt (between phases)

If the session needs to pick up mid-plan (new session, context reset,
next day), use this instead:

```
You are continuing the Manifold UI migration from Stage 11. You are
about to start Phase N.

READ FIRST:
- /design/11-single-session-plan.md §2 Phase N (your current phase)
- /design/11-single-session-plan.md §4 EXECUTION PROTOCOL (rules that
  apply to every phase)
- /CLAUDE.md
- /design/html/<relevant>.html for Phase N's acceptance

VERIFY YOU ARE STARTING FROM A GREEN STATE:
  git log -1          # confirm last commit is "phase-(N-1): …"
  swift build         # must be green
  xcodebuild …        # must be green

Then begin Phase N. Same checkpoint protocol: verify, commit, stop.
```

Replace `N` with the phase number.

---

## 6. Acceptance — the one checklist that matters

When Phase 9 finishes, run through every item in
`design/09-migration-plan.md` §8 and confirm:

- [ ] Every file in §2 "What gets deleted" is gone from
      `ManifoldApp/ManifoldApp/`
- [ ] `git grep` finds zero references to any deleted type, including
      tests and fixtures
- [ ] `xcodebuild … -configuration Release` succeeds
- [ ] `swift test` passes with no availability-gated fallbacks to
      deleted code paths
- [ ] App launches from a clean `DerivedData` and a fresh user home;
      first-run flow renders correctly
- [ ] Menu bar panel shows each of the 4 states against the matching
      runtime condition
- [ ] All 5 sidebar destinations render their content; empty states
      are reachable and look correct
- [ ] Agents can request access; request appears in
      `RequestsWindowView`; no modal fires on any code path
- [ ] Sessions can be started, resumed, finished; reload shows drift
      preview honestly
- [ ] Rules: create, toggle, live blast preview updates, seed defaults
      were applied on first run
- [ ] Accessibility audit (VoiceOver, keyboard-only, reduce-motion,
      increase-contrast) passes every surface

When all boxes are checked, the old UI is gone and the designed UI is
what ships.

---

## 7. Rollback

At any phase boundary:
```
git reset --hard HEAD~1      # discard the just-finished phase
# or
git checkout phase-<N-1>     # back to a known-good tag
```
Because deletions are concentrated in Phase 9, Phases 1–8 are
individually reversible. Phase 9 is the only irreversible step and
should be tackled only when Phases 1–8 have all been lived with for
at least one full working session.
