# Manifold UI — Stage 10: Parallel Claude Code Workflow

> **Historical note (2026-04-30):** This workflow predates the current
> four-space app model: Work, Access, Mail, and Rules. It is retained as
> historical migration material only; legacy worktree names and route
> examples such as Activity and Requests are not current implementation
> guidance.

A concrete, copy-paste plan for running the Stage-9 migration as four
parallel Claude Code sessions. One sequential setup session, four
parallel UI sessions, one sequential integration session. Total six
sessions; four of them run at the same time.

---

## 1. Shape of the workflow

```
           ┌─────────────────────────┐
           │  Session 0 · Foundation │    ≈ 1–2 days, sequential
           └────────────┬────────────┘
                        │   (commits foundation, publishes CONTRACTS.md,
                        │    stubs every new .swift file in .pbxproj)
                        ▼
   ┌───────────┬───────────┬───────────┬───────────┐
   │ Session 1 │ Session 2 │ Session 3 │ Session 4 │   ≈ 3–5 days, parallel
   │ Activity  │ Access    │ Mail      │ Governance│   (4 git worktrees)
   └─────┬─────┴─────┬─────┴─────┬─────┴─────┬─────┘
         │           │           │           │
         └───────────┴───────────┴───────────┘
                        │
                        ▼
           ┌─────────────────────────┐
           │ Session 5 · Integration │    ≈ 1–2 days, sequential
           └─────────────────────────┘
                        │
                        ▼
                    Done — old UI deleted
```

Seven days elapsed vs. ~30 days sequential. No file-level conflicts
because each parallel session owns a disjoint set of `Views/<Surface>/`
directories and the .pbxproj is pre-populated with stub entries by
Session 0.

---

## 2. Principles that make this work

Synthesized from the research sources at the end of this doc and from
the Stage-9 plan.

- **Task independence is non-negotiable.** Parallel agents must touch
  disjoint file sets. If two agents can modify the same file, they are
  not really parallel.
- **Contracts freeze before fan-out.** The foundation session publishes
  `CONTRACTS.md` that names every primitive, type, and `ManifoldStore`
  API the parallel agents will consume. Primitives are read-only to the
  parallel agents.
- **Pre-stub the Xcode project.** The foundation session creates every
  expected new `.swift` file as a compiling stub and adds all of them to
  `Manifold.xcodeproj/project.pbxproj` up-front. Parallel agents only
  ever rewrite file *contents*; they do not add or remove files from the
  project. This keeps the notoriously merge-hostile `.pbxproj` single-writer.
- **Worktree per agent.** Use `git worktree` so each session has a
  separate directory with its own branch, independent build artifacts,
  and independent DerivedData. No cross-agent pollution.
- **Name worktrees by surface, not by ticket.** `activity`, `access`,
  `mail`, `gov` — readable at a glance in `git worktree list`.
- **Foundation is not ornamental.** If Session 0 ships incomplete
  primitives or loose contracts, all four parallel sessions will drift.
  Budget it honestly — 1–2 full days.
- **Integration owns deletion.** No parallel agent deletes old files.
  Session 5 does all deletions after the new surfaces land. This
  prevents the "half-deleted while branch-B is still depending on it"
  failure mode.
- **Each parallel agent runs its own verification.** `swift build` +
  `xcodebuild` for the surface's target. Integration re-verifies
  everything after merge.

---

## 3. Git worktree setup

Run this once before Session 0. It creates the long-lived migration
branch plus 4 empty worktree slots that Sessions 1–4 will populate.

```bash
cd ~/path/to/Manifold

# Long-lived integration branch
git checkout -b migration/main

# Foundation branch (Session 0 works here directly)
git checkout -b migration/foundation

# Four empty worktree slots (created as branches now,
# checked out in worktrees after Session 0 merges)
git branch migration/activity migration/foundation
git branch migration/access   migration/foundation
git branch migration/mail     migration/foundation
git branch migration/gov      migration/foundation
```

After Session 0 finishes and merges to `migration/main`, create the
parallel worktrees:

```bash
# Run from the main repo
git worktree add ../manifold-activity migration/activity
git worktree add ../manifold-access   migration/access
git worktree add ../manifold-mail     migration/mail
git worktree add ../manifold-gov      migration/gov

# Rebase each onto the latest foundation
for w in activity access mail gov; do
  (cd ../manifold-$w && git rebase migration/main)
done

git worktree list
```

Each of `../manifold-activity`, `../manifold-access`, etc. is a full
checkout. Open each in its own Claude Code session with:

```bash
cd ../manifold-activity && claude
# (repeat for access / mail / gov)
```

Or if you have the 2026 native worktree support:

```bash
cd ~/path/to/Manifold && claude --worktree activity
```

After Sessions 1–4 finish, clean up:

```bash
git worktree remove ../manifold-activity
git worktree remove ../manifold-access
git worktree remove ../manifold-mail
git worktree remove ../manifold-gov
```

---

## 4. What Session 0 freezes (the contracts)

Before any parallel session starts, Session 0 must commit
`design/CONTRACTS.md` containing the final, frozen public API of:

### Styling

- `ManifoldPalette` — fixed agent and status colors, with `.claude`,
  `.claude2`, `.codex`, `.codex2`, `.session`, `.session2`, `.attention`,
  `.attention2`, `.danger`; light + dark variants hardcoded (not system
  accent).
- `LiquidGlassMaterial` — NSVisualEffectView wrapper + tint layer
  modifier used by every window / sidebar / toolbar / inspector.
- `Typ` (typography roles), `Spacing` (4pt baseline), `Shadow` presets,
  `Anim` presets.

### Components (each with frozen public init signature)

- `GradientAvatar(agent: AgentIdentity, size: CGFloat)`
- `AgentStatusDot(kind: StatusKind, pulse: Bool)`
- `SessionChip(session: SessionRecord)`
- `SparklineBar(reads: Int, writes: Int, denies: Int, accent: Color?)`
- `TriStateCheckbox(state: Binding<TriState>, overridden: Bool)`
- `SegmentedToggle(kind: ToggleKind, isOn: Binding<Bool>)` —
  `default / session / attention`
- `CommitLadder(denyAction:, onceAction:, sessionAction:, defaultAction:,
  sessionActive: Bool)`
- `Pill(variant: PillVariant, text: String)`
- `FileTypeIcon(ext: String)`
- `EmptyStateIllustration(kind: EmptyKind)`
- `KbdLabel(_ keys: String)`

### Data primitives (in ManifoldRuntime, re-exported via ManifoldKit)

- `SessionRecord` — id, name, startedAt, expiresAt, agents,
  baseMode (`default | blank | defaultMinus`), additions, subtractions,
  trackedWrites, origin (fresh | resumedFrom:)
- `ApprovalRequest` — id, agent, operation (.read / .write / .search /
  .mailThread / …), target (path or mailbox key), context, createdAt,
  snoozedUntil
- `Rule` — id, domain (`.email / .files / .agents`), predicate (enum),
  enabled, seeded, createdBy (`.manifold / .user / .autoRule`)
- `ScopeEntry`, `DenialEvent`, `SessionHistoryEntry`

### Store surface (ManifoldStore — read-only during parallel phase)

- `@Published var activeSession: SessionRecord?`
- `func recentSessions(limit: Int) async -> [SessionHistoryEntry]`
- `func pendingRequests() -> [ApprovalRequest]`
- `func rules(domain: RuleDomain) -> [Rule]`
- `func drift(for sessionId: UUID) async -> SessionDrift`
- `func subscribe(_ handler: @escaping (StoreEvent) -> Void) -> Task<Void, Never>`

**Parallel agents may only read from the store.** Any write (start
session, answer request, toggle rule, revert file) goes through a
command API that Session 0 freezes as a protocol:

```swift
protocol ManifoldCommands {
    func startSession(_ draft: SessionDraft) async throws -> SessionRecord
    func finishSession(_ id: UUID) async throws
    func answerRequest(_ id: UUID, with: ApprovalAnswer) async throws
    func toggleRule(_ id: UUID, enabled: Bool) async throws
    func revert(event: AuditEntry) async throws -> RevertOutcome
    // …etc
}
```

Parallel agents inject `ManifoldCommands` — they do not call the store
directly for writes.

### Navigation routing

- `LedgerDestination` — `.activity / .access / .mail / .requests / .rules`
- `LedgerWindowView` is already built and routes to a per-destination
  view via a factory closure. Parallel agents replace their factory
  entry with their real view.

### File ownership table (the only table that matters for parallelism)

| Session | Owns | Must not touch |
|---|---|---|
| 1 · Activity | `Views/Activity/**`, `Views/Activity/Tests/**` | anything else |
| 2 · Access | `Views/Access/**`, `Views/Access/Tests/**` | anything else |
| 3 · Mail | `Views/Mail/**`, `Views/Mail/Tests/**` | anything else |
| 4 · Gov | `Views/Requests/**`, `Views/Rules/**`, `Views/FirstRun/**`, `Views/Session/**`, and corresponding `Tests/` | anything else |
| 0 · Foundation | `Components/**`, `Models/**`, `Views/Chrome/**`, `Views/MenuBar/**`, `Views/LedgerWindowView.swift`, `CONTRACTS.md`, `.pbxproj` | none |
| 5 · Integration | everything (merge-only during parallel phase; full-repo after) | — |

No Views/* directory is written by more than one session.

---

## 5. Pbxproj strategy

The single biggest merge hazard in parallel Xcode work is
`Manifold.xcodeproj/project.pbxproj`. Resolve it once, in Session 0.

**Strategy: pre-stub every new file.**

Session 0 creates every expected new `.swift` file — around 55 of them
— with a minimal compiling stub:

```swift
// Views/Activity/ActivityWindowView.swift (stub created by Session 0)
import SwiftUI

struct ActivityWindowView: View {
    var body: some View { Color.clear }
}
```

Session 0 adds all of them to the Xcode project in a single commit. The
parallel agents only rewrite file *contents*, never add or remove files
from the project. Session 5 handles any .pbxproj deletions at the end.

If a parallel agent discovers it needs a new file that wasn't stubbed,
the rule is: **add it via SPM/folder reference, not via pbxproj edits**.
Failing that, defer to Session 5. In practice, 55 pre-stubs cover
everything in the Stage-9 plan with margin.

---

## 6. The six prompts (copy-paste)

All prompts assume the user has Claude Code installed and the repository
cloned at a path the agent can see. Each prompt is self-contained; each
starts by directing the agent to read the design docs it needs and the
frozen contracts.

### ─── SESSION 0 · Foundation ───

**Worktree:** the main repo (work directly on `migration/foundation`)
**Duration:** 1–2 days
**Blocks:** all parallel sessions

```
You are the foundation agent for the Manifold UI migration. You work
sequentially and alone. No parallel agent has started yet.

READ FIRST:
- /CLAUDE.md (project rules — XPC boundary, verification commands)
- /design/09-migration-plan.md (the phased migration plan you are
  implementing Phases 0, 1, and 2 of)
- /design/02-posture-and-principles.md (the 10 principles)
- /design/03-surface-redesign.md (the 15 surfaces and their decisions)
- /design/html/*.html (visual acceptance references)

YOUR SCOPE — Phases 0, 1, 2 of the migration plan. Specifically:

A. DESIGN TOKENS & PRIMITIVES (Phase 0)
   - Rewrite ManifoldApp/ManifoldApp/Components/DesignTokens.swift
     with the fixed Manifold palette — agent colors are NOT tied to
     system accent. Include light + dark variants. Add gradient
     helpers and shadow presets.
   - Rewrite Components/Spacing.swift on a 4pt baseline, 8pt horizontal
     grid.
   - Create Components/Primitives/ with exactly these files:
       LiquidGlassMaterial.swift
       ManifoldPalette.swift
       GradientAvatar.swift
       AgentStatusDot.swift
       SessionChip.swift
       SparklineBar.swift
       TriStateCheckbox.swift
       SegmentedToggle.swift
       CommitLadder.swift
       Pill.swift
       FileTypeIcon.swift
       EmptyStateIllustration.swift
       KbdLabel.swift
   - Each primitive must render correctly in its own #Preview and use
     only ManifoldPalette colors (never .blue / .purple).

B. DATA PRIMITIVES (Phase 1)
   - Add SessionRecord, ApprovalRequest, Rule, ScopeEntry, DenialEvent,
     SessionHistoryEntry, SessionDrift, SessionDraft, ApprovalAnswer,
     RevertOutcome types in the ManifoldRuntime package (or its
     equivalent in ManifoldKit). Follow the shapes in
     /design/CONTRACTS.md (which you are about to write).
   - Extend PolicyModel with activeSession (adapter wrapping
     activeWorkBlock for now), recentSessions, pendingRequests, drift(for:).
   - Extend ManifoldStore to expose the read surface in the CONTRACTS.
   - Introduce a ManifoldCommands protocol for all writes and inject
     a conforming default implementation.
   - Write unit tests for Session reload drift math and Rule predicate
     evaluation.

C. SHELL + MENU BAR + FIRST-RUN SHELL (Phase 2)
   - Views/LedgerWindowView.swift — NavigationSplitView with 5
     destinations (Activity, Access, Mail, Requests, Rules). Each
     destination uses a factory closure that returns a placeholder
     Color.clear for now; parallel agents will replace these.
   - Views/Chrome/NavSidebar.swift, IntegratedToolbar.swift,
     StatusBar.swift — shared chrome.
   - Views/MenuBar/MenuBarPanelView.swift — 4 states matching
     /design/html/menubar.html. Implement fully, using real store reads.
   - Views/MenuBar/States/{Idle,IdleWithRecent,ActiveWithQueue,
     TrackedEdit}.swift
   - Views/LedgerWindowView.swift is gated behind a NEW_UI environment
     flag. Old MainView.swift remains functional when NEW_UI is off.

D. STUB EVERY NEW FILE (critical)
   - Under Views/Activity/, Views/Access/, Views/Mail/, Views/Requests/,
     Views/Rules/, Views/FirstRun/, Views/Session/ — create a compiling
     stub .swift file for every new file listed in
     /design/09-migration-plan.md §1. Each stub declares the type and
     returns Color.clear from its body. This lets parallel agents
     rewrite contents without touching project.pbxproj.
   - Add ALL stubs to Manifold.xcodeproj/project.pbxproj in a single
     commit.

E. PUBLISH CONTRACTS
   - Write /design/CONTRACTS.md. Document every primitive's public init
     signature, every data primitive's public fields, the
     ManifoldCommands protocol, the LedgerDestination routing, and the
     file-ownership table. This is the single source of truth for
     parallel agents.

VERIFICATION at end of session:
   env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
       SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
       swift build && swift test
   env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
       SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
       xcodebuild -project Manifold.xcodeproj -scheme Manifold \
                  -configuration Debug \
                  -derivedDataPath /tmp/manifold-derived-data \
                  build CODE_SIGNING_ALLOWED=NO

COMMIT AND MERGE:
   - Commit on migration/foundation in small logical chunks.
   - Rebase onto migration/main when green.
   - Open a PR. Merge it before starting any parallel session.
   - Announce "foundation merged" so parallel sessions can fan out.

DELETE NOTHING. All deletions happen in Session 5. Your job is to add
every new scaffolding without touching any legacy file.
```

### ─── SESSION 1 · Activity ───

**Worktree:** `../manifold-activity`
**Branch:** `migration/activity`
**Duration:** 3–4 days
**Runs in parallel with 2, 3, 4**

```
You are the Activity UI agent for Manifold. You work in parallel with
three other agents. Foundation has been merged to migration/main; your
branch migration/activity is based on it.

READ FIRST:
- /CLAUDE.md
- /design/CONTRACTS.md (the frozen public APIs you consume — you may
  not modify this file or anything listed as foundation-owned)
- /design/09-migration-plan.md §3 Phase 3
- /design/html/activity.html (your acceptance reference — the window
  you build must match this mockup end-to-end)
- /design/03-surface-redesign.md §E (the Activity surface decisions)

YOUR SCOPE — everything under Views/Activity/. That is only:
- ActivityWindowView.swift
- SessionRail.swift
- EventTable.swift
- EvidenceInspector.swift
- Plus a Tests/ subfolder for XCTests you write

YOU MUST NOT:
- Modify any file outside Views/Activity/
- Modify project.pbxproj (all files are pre-stubbed there)
- Add new files to the Xcode project
- Call any ManifoldStore write method directly — use ManifoldCommands
- Delete any legacy file (Session 5 handles deletions)

WHAT TO BUILD (matches design/html/activity.html):
1. Three-column body: session rail (left, 216pt) + dense event table
   (center) + evidence inspector (right, 340pt)
2. Session rail — vertical list grouped by day ("Today", "Yesterday"),
   each session gets timestamp, agent dot, name, kind pill, meta
   counts, and a real sparkline via SparklineBar primitive.
3. Event table — 7-column grid: Time | Agent | Action | Target | Size
   | Session | ⋯. 30pt row height, tabular numerics, fixed-width
   monospaced time, denial rows have orange leading edge.
4. Evidence inspector — kicker + title + mono path + stats row + diff
   block (reuse Components/DiffView.swift) + "Why this was allowed"
   card + file history sparkline + related files list + action buttons
   (Revert, Open).
5. Toolbar — 6-chip filter segment (All / Reads / Writes / Denials /
   Searches / Tracked edits) + search + session chip in right slot.
6. Status bar at the bottom.
7. Denial detail sub-state — when a denial row is selected, inspector
   shows the orange "Claude tried to read this file" evidence card
   with remedy actions.

ALL DATA MUST COME FROM ManifoldStore via its read API. Do not
hard-code fixture data except behind #Preview. Respect reduce-motion
on the pulse animation. Every interactive element needs an
accessibility label.

VERIFY:
   env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
       SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
       xcodebuild -project Manifold.xcodeproj -scheme Manifold \
                  -configuration Debug \
                  -derivedDataPath /tmp/manifold-derived-data-activity \
                  build CODE_SIGNING_ALLOWED=NO

LAUNCH VERIFICATION:
   Run the app with NEW_UI=1, click the Activity sidebar item. Confirm
   every region of design/html/activity.html renders with real data.

COMMIT DISCIPLINE:
   Small focused commits. When complete, open a PR targeting
   migration/main. Do not merge yourself — Session 5 will merge in
   sequence.

WHEN DONE: announce "Activity done, PR opened" and stop.
```

### ─── SESSION 2 · Access ───

**Worktree:** `../manifold-access`
**Branch:** `migration/access`
**Duration:** 4–5 days
**Runs in parallel with 1, 3, 4**

```
You are the Access UI agent for Manifold. You work in parallel with
three other agents. Foundation has been merged.

READ FIRST:
- /CLAUDE.md
- /design/CONTRACTS.md
- /design/09-migration-plan.md §3 Phase 4
- /design/html/access.html (acceptance reference — five views in one
  file, stacked vertically: Folders, Files, Session, History, Empty)
- /design/03-surface-redesign.md §D, §G
- /design/07-mail-separation-decision.md (why Mail is NOT your job —
  confirm you don't touch Mail)

YOUR SCOPE — everything under Views/Access/. Only these files:
- AccessWindowView.swift (tab router)
- FoldersMatrixView.swift
- BulkActionBar.swift
- FileTreeInspector.swift
- FilesFlatView.swift
- VersionTimelineInspector.swift
- SessionDiffView.swift
- SessionAdditionInspector.swift
- HistoryListView.swift
- SessionDetailInspector.swift
- EmptyFoldersView.swift
- Tests/

YOU MUST NOT: touch anything outside Views/Access/. No Mail. No Rules.
No project.pbxproj edits. Use ManifoldCommands for writes.

WHAT TO BUILD:
1. Four-tab toolbar: Folders | Files | Session | History.
2. Folders — coverage matrix (source × agent × denials). Row selection
   opens FileTreeInspector. Multi-select shows a floating BulkActionBar
   at the bottom of the matrix, with Share-with-Claude / Share-with-
   Codex / Add-to-session / Unshare actions.
3. FileTreeInspector — tri-state checkboxes via TriStateCheckbox
   primitive, indent guides, override dots on rules-overridden nodes,
   smart-default exclusions surfaced with trace chips, exclusion rules
   list, + Add rule action.
4. Files — flat file list across all shared folders with version chips
   (write count or "reverted" or "original"). Row selection opens
   VersionTimelineInspector showing the full per-file version timeline
   with dots, diff preview on selected version, Revert-to-vN action.
5. Session — diff view while a session is live. Three sections:
   "Added for this session", "Removed for this session", "Inherited
   from default". Session head bar at the top. Finish/Review actions.
6. History — list of past sessions grouped by day. Each row has
   timestamp, session kind pill (Live/Session/Tracked edit/Default
   minus…), overlapping sender/folder avatars, mini-sparkline, Resume
   button. Inspector shows drift vs. current default.
7. Empty — no folders shared. Primary CTA "Share your first folder"
   with smart-default note. Dashed drag-and-drop alt card. DO NOT
   include mailbox CTA — empty is folders only.

Use LiquidGlassMaterial for every surface. Use SessionChip primitive
in the toolbar. All colors from ManifoldPalette. Every row keyboard-
reachable.

VERIFY:
   env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
       SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
       xcodebuild -project Manifold.xcodeproj -scheme Manifold \
                  -configuration Debug \
                  -derivedDataPath /tmp/manifold-derived-data-access \
                  build CODE_SIGNING_ALLOWED=NO

LAUNCH: NEW_UI=1, click Access sidebar, step through all four tabs
and the empty state. Confirm file-tree inspector + version timeline.

COMMIT + PR as in Session 1. Announce "Access done, PR opened."
```

### ─── SESSION 3 · Mail ───

**Worktree:** `../manifold-mail`
**Branch:** `migration/mail`
**Duration:** 4–5 days
**Runs in parallel with 1, 2, 4**

```
You are the Mail UI agent for Manifold. You work in parallel with
three other agents. Foundation has been merged.

READ FIRST:
- /CLAUDE.md
- /design/CONTRACTS.md
- /design/09-migration-plan.md §3 Phase 5
- /design/html/mail.html (acceptance reference — 5 views)
- /design/08-mail-ui-style.md (Active Backup, NOT Apple Mail — this is
  load-bearing)
- /design/07-mail-separation-decision.md (why Mail is its own surface)

YOUR SCOPE — Views/Mail/. Only these files:
- MailWindowView.swift (tab router)
- MailboxesMatrixView.swift
- MailboxInspector.swift
- SensitivitySelector.swift
- ThreadsView.swift
- SenderRail.swift
- ThreadTable.swift
- ThreadInspector.swift
- MailSessionView.swift
- MailHistoryView.swift
- EmptyMailView.swift
- Tests/

YOU MUST NOT: touch anything outside Views/Mail/. No Access. No Rules.
No project.pbxproj edits.

WHAT TO BUILD (Active Backup style, never Apple Mail):
1. Four-tab toolbar: Mailboxes | Threads | Session | History.
2. Mailboxes — matrix of mailbox × agent × sensitivity × thread-count
   × denials. SensitivitySelector component = 3-option segment
   (Subjects only / Trusted senders / Full content) with bar indicators.
   Row selection opens MailboxInspector with sensitivity selector,
   global-rules banner, top senders list with colored discs, labels
   tree.
3. Threads — FOUR-column body: nav sidebar | sender rail | thread
   table | minimal inspector. ABSOLUTELY NO READING PANE.
   - SenderRail: Accounts block, Top senders (colored initials discs),
     Folders (Inbox/Sent/Archive/Confidential), Smart filters.
   - ThreadTable: dense rows with checkbox · sender disc · (sender +
     subject on two lines) · date · agents · ⋯. Session-green
     checkboxes for in-session; default-blue for default scope;
     excluded-by-rule rows dimmed with orange leading edge.
   - ThreadInspector: subject, sender, first-line preview card (italic,
     ONE ROW TALL — not a reading pane), "Visible to Claude" metadata
     grid, messages list with dots, Remove/Promote actions.
   - Footer running count: "3 threads · 6 messages in session" etc.
4. Session — diff view showing additions/subtractions/inherited
   threads for the live session.
5. History — past mail sessions with Resume. Inspector shows drift.
6. Empty — no mailboxes. Primary "Connect a mailbox" with provider
   chips (Apple Mail, Gmail OAuth, IMAP, Fastmail). Dashed drop-
   email-here alt. Seeded global email rules note.

Use mail-native row content (subject, sender disc, thread collapse,
mail-convention dates) but reject mail-client chrome. No reply
button. No archive button. No reading pane.

VERIFY + LAUNCH + COMMIT as Session 1. Announce "Mail done, PR opened."
```

### ─── SESSION 4 · Governance (Requests + Rules + First-run + Session sheets) ───

**Worktree:** `../manifold-gov`
**Branch:** `migration/gov`
**Duration:** 5–7 days
**Runs in parallel with 1, 2, 3**

```
You are the Governance UI agent for Manifold. You cover Requests,
Rules, First-run, and the Session start/reload sheets. You work in
parallel with three other agents.

READ FIRST:
- /CLAUDE.md
- /design/CONTRACTS.md
- /design/09-migration-plan.md §3 Phases 6, 7, 8
- /design/html/requests.html (acceptance reference)
- /design/html/rules.html (acceptance reference — 4 views including
  the New-rule sheet)
- /design/html/firstrun.html (acceptance reference)
- /design/html/session-start.html (acceptance reference)
- /design/05-addendum.md (Session + reload addendum)

YOUR SCOPE — four directories:
- Views/Requests/
    RequestsWindowView.swift
    PendingQueueView.swift
    ApprovalCard.swift
    RecentAnswersView.swift
    PatternDetectionInspector.swift
    EmptyRequestsView.swift
- Views/Rules/
    RulesWindowView.swift
    FilesRulesView.swift
    EmailRulesView.swift
    AgentsRulesView.swift
    RuleCard.swift
    BlastRadiusPreview.swift
    NewRuleSheet.swift
    RuleBuilder.swift
    LiveMatchPreview.swift
- Views/FirstRun/
    FirstRunFlow.swift
    Panels/Concept.swift
    Panels/Defaults.swift
    Panels/GuidedAdd.swift
- Views/Session/
    SessionStartSheet.swift
    ReloadDriftSheet.swift
- Tests/ for each

YOU MUST NOT: touch anything outside these four directories.
No Activity. No Access. No Mail. No project.pbxproj edits.

WHAT TO BUILD:

A. REQUESTS (Phase 6 — replaces the old modal approval sheet)
   - Pending queue with ApprovalCard. Each card has agent avatar,
     headline, tags (read/write/agent/attention), code-pill target,
     italic context, and a CommitLadder with 4 buttons:
     Not this time (focused default) | Once | For session | Add to default
     The "For session" button is hidden when no session is live.
     Keyboard: ↩, ⇧↩, ⌥↩, ⌘↩.
   - Recent answers — same card shape with an answer-chip in the
     top-right (Deny/Once/Session/Default color-coded).
   - PatternDetectionInspector — when user denies same pattern 3+ times,
     suggest an auto-rule with a 14-day denial chart and "Create
     auto-deny rule" action.
   - Empty state — quiet daemon-recedes illustration + how-it-works card.

B. RULES (Phase 7)
   - Three tabs: Email | Files | Agents.
   - RuleCard with plain-English sentence + seeded/user pill + scope
     pill + BlastRadiusPreview ("4 files match", "0 in shared folders",
     "14 blocks this month"). Toggle with confident slot.
   - Groups per tab: Exclude / Redact / Never-write (Files);
     Exclude / Redact (Email); Require-approval / Auto-pause (Agents).
   - NewRuleSheet — floating over a blurred parent, with three-picker
     subject+verb+object builder grammar (no regex by default),
     agent-scope segment, live blast-radius meter showing count +
     sample matches. Advanced toggle for regex.
   - Seeded defaults loaded on first launch.

C. FIRST-RUN (Phase 8)
   - Three-panel flow: Concept (metaphor + motion loop), Defaults
     (empty Access as illustration, "Nothing is shared until you share
     it"), Guided add (single folder CTA; no mailbox card).
   - Skip affordances at every step.

D. SESSION SHEETS (Phase 8)
   - SessionStartSheet — short form: name, duration segment
     (30m/2h/4h/Until sign-out), three base radios (Default / Blank /
     Default minus…), agents checkboxes, Track writes toggle.
   - ReloadDriftSheet — same shape + drift preview showing what
     changed since the original session.

Every sheet uses LiquidGlassMaterial, ManifoldPalette, and primitives.
Every button has a keyboard shortcut. Notifications are never fired —
the queue is the only affordance.

VERIFY + LAUNCH + COMMIT as Session 1.
Announce "Governance done, PR opened."
```

### ─── SESSION 5 · Integration ───

**Worktree:** main repo, on a new branch
**Duration:** 1–2 days
**Runs after all 4 parallel PRs are open**

```
You are the integration agent. All four parallel agents have opened
PRs against migration/main. Your job: merge them, finish Phases 9 +
10 of the migration plan, delete every legacy file, remove the
NEW_UI flag, and ship.

READ FIRST:
- /CLAUDE.md
- /design/09-migration-plan.md §3 Phases 9, 10 + §4 Verification + §8
  Acceptance checklist
- /design/CONTRACTS.md
- Each parallel PR's description

STEP 1: MERGE THE PARALLEL PRs
   git checkout migration/main
   git merge migration/activity  --no-ff
   git merge migration/access    --no-ff
   git merge migration/mail      --no-ff
   git merge migration/gov       --no-ff

   Expect zero file-content conflicts if the parallel agents held
   their lanes. Expect minor .pbxproj conflicts only if any agent
   violated the no-pbxproj-edit rule — if so, resolve manually by
   keeping both additions.

STEP 2: CONSISTENCY PASS
   Do a visual audit of all four surfaces by launching the app with
   NEW_UI=1 and stepping through every sidebar destination. Look for:
   - Inconsistent paddings across surfaces
   - Inconsistent session chip implementations
   - Differing empty-state illustrations (they should share a look)
   - Any hardcoded colors that bypassed ManifoldPalette
   Fix drift in a single commit; each fix should move values into
   the primitives, not into the surfaces.

STEP 3: PHASE 9 — SETTINGS COPY PASS
   - Apply the new palette to Views/Settings/*; they'll inherit tokens
     automatically but re-verify.
   - Copy pass per Stage 3 §L: move engineering-flavored strings to a
     new "Advanced" pane. Every switch gets a two-sentence description.
   - NO deletions.

STEP 4: PHASE 10 — CLEANUP & DELETIONS
   Delete, in order, every file listed in /design/09-migration-plan.md
   §2 "What gets deleted". This is the authoritative list. For each:
   - Delete the .swift file from disk
   - Remove its entry from Manifold.xcodeproj/project.pbxproj
   - Run swift build and xcodebuild after each batch of ~5 deletions
     to catch reverse dependencies immediately

   Specifically remove:
   - Views/MainView.swift (reducing ManifoldApp.swift to the new
     Scene graph — LedgerWindow + MenuBarExtra + Settings +
     FirstRunFlow presentation rules)
   - Views/OverviewView.swift + AgentPolicyCard.swift
   - Views/Activity{View,Row,Drawer}.swift
   - Views/Files{View,DashboardView,Sidebar}.swift + SourcesTableView.swift
   - Views/Versions/{VersionsView,VersionDetailView,SnapshotRow}.swift
   - Views/ReviewAccessSheet.swift + ReviewChangesSheet.swift
   - Views/WorkBlockBannerView.swift
   - Views/AgentFocusControl.swift
   - Views/Library/EmailAccountSetupView.swift
   - Entire Views/Email/ subtree (23 files)
   - Components/{AgentBadge,Badge,StatusBadge,ColorIndicator,DetailLine,
     LiveCheckRow,RuleFormComponents,TrackChangesToolbarContent}.swift
   - Views/Setup/SetupAssistantView.swift (rewritten as FirstRunFlow)

STEP 5: RENAMES
   - In PolicyModel and ManifoldStore, rename every remaining
     "workBlock" identifier to "session". Remove the adapter.
   - If Views/CommandPaletteView.swift survives, keep it; otherwise
     delete + remove Models/CommandCenter.swift.

STEP 6: REMOVE THE FLAG
   - Delete the NEW_UI environment flag plumbing.
   - LedgerWindowView becomes the only window. MainView.swift is gone.

STEP 7: FINAL VERIFICATION
   env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
       SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
       swift build && swift test
   env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
       SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
       xcodebuild -project Manifold.xcodeproj -scheme Manifold \
                  -configuration Release \
                  -derivedDataPath /tmp/manifold-derived-data-final \
                  build CODE_SIGNING_ALLOWED=NO

   git grep -l "WorkBlock\|OverviewView\|ReviewAccessSheet\|ActivityDrawer\|AgentBadge" --  '*.swift'
   # Expect zero results.

STEP 8: LAUNCH FROM CLEAN STATE
   Quit the app, remove ~/Library/Containers/com.spatialduality.manifold,
   rebuild, launch. Verify:
   - First-run flow appears
   - Add a folder via the guided flow
   - Menu bar panel shows appropriate state
   - Every sidebar destination renders
   - Start a session, finish it
   - Create a rule, toggle it
   - Trigger an agent request, answer it from the queue

STEP 9: SHIP
   - Merge migration/main into main.
   - Delete the migration branches and worktrees.
   - Tag the release.
   - Update the acceptance checklist in 09-migration-plan.md §8.

ANNOUNCE: "Migration complete. Old UI deleted. Acceptance checklist
passing." Stop.
```

---

## 7. Common pitfalls + mitigations

Specific things I expect to go wrong, with fixes:

- **Parallel agent touches a foundation file.** Reject in PR review.
  Foundation file contents are frozen between Session 0 and Session 5.
  If a parallel agent genuinely needs a new primitive, they file an
  issue against Session 5, who either adds it in the consistency pass
  or directs the agent to compose what they have.

- **pbxproj conflict.** The only legitimate source is Session 0. If
  Session 1–4 produces a pbxproj change, Session 5 discards it
  (`git checkout --theirs project.pbxproj` where "theirs" is the pre-
  parallel main). The stub approach makes this safe.

- **Stylistic drift.** Four agents will interpret "Pixelmator-bar
  polish" four ways. Session 5's consistency pass is mandatory, not
  optional. Budget half a day for it.

- **One agent finishes late.** Do not block the others. Session 5
  can merge the first three PRs and begin integration while the
  fourth agent finishes. But do not start Phase 10 deletions until all
  four are merged.

- **Xcode DerivedData collision between worktrees.** Each parallel
  session uses its own `-derivedDataPath` (see the prompts —
  `/tmp/manifold-derived-data-activity`, etc.). Never share DerivedData
  across worktrees.

- **Session 0 publishes contracts that are incomplete.** If parallel
  agents hit a missing type, they file an issue and keep building
  against a local stub. Session 5 reconciles. Worst case: Session 5
  does a contracts pass before Phase 10.

- **Agent write operations during parallel phase.** None — parallel
  agents only read from the store. Writes route through
  ManifoldCommands, which Session 0 implements fully before fan-out.

---

## 8. Why 4 and not more

Research notes that Claude Code supports up to 7 parallel agents.
Manifold's migration has four natural cleavage planes that don't
overlap: **Activity**, **Access**, **Mail**, **Governance** (Requests +
Rules + First-run + Session sheets). Further splits would either:

- Split a surface in two (e.g., Access-Folders vs. Access-Files), which
  forces cross-PR coordination on shared Access chrome
- Split a primitive out (e.g., "SessionChip agent"), which is too small
  to justify a session
- Split the integration (e.g., "settings pass agent"), which reintroduces
  the merge problem Session 5 is designed to solve

Four is the point where scope is large enough to warrant a dedicated
agent and small enough that file ownership stays clean.

---

## 9. Checklist — ready to fan out

Before running Sessions 1–4, verify all of these are true:

- [ ] Session 0 has merged to `migration/main`
- [ ] `/design/CONTRACTS.md` exists and is complete
- [ ] Every expected new `.swift` file is pre-stubbed and appears in
      `project.pbxproj`
- [ ] `swift build && swift test && xcodebuild` is green on
      `migration/main`
- [ ] `NEW_UI=1` launch works and shows the shell with empty
      destinations
- [ ] `MenuBarPanelView` renders all 4 states
- [ ] All 4 worktrees have been created and rebased onto
      `migration/main`
- [ ] Each parallel session's prompt (from §6 above) is in a scratchpad
      ready to paste

When all 7 boxes are checked, launch Sessions 1–4 in parallel. Session 5
runs after their PRs are open.

---

## Sources

- [Common workflows — Claude Code Docs](https://code.claude.com/docs/en/common-workflows)
- [How to Run Parallel Claude Code Agents (Verdent)](https://www.verdent.ai/guides/how-to-run-parallel-claude-code-agents)
- [Claude Code Git Worktree Pattern (MindStudio)](https://www.mindstudio.ai/blog/claude-code-git-worktree-parallel-branches)
- [Agent Teams Workflow (claude-code-ultimate-guide)](https://github.com/FlorianBruniaux/claude-code-ultimate-guide/blob/main/guide/workflows/agent-teams.md)
- [Mastering Parallel Agent Development in Claude Code (Claude Lab)](https://claudelab.net/en/articles/claude-code/claude-code-parallel-development-mastery)
- [Multi-agent workflows — Claude Code](https://www.mintlify.com/VineeTagarwaL-code/claude-code/guides/multi-agent)
- [Worktree for Claude Agents (Medium, Naresh Kancharla)](https://medium.com/@naresh.kancharla/worktree-for-claude-agents-547701f82732)
- [Running Claude Code in Parallel — Git Worktree Guide (jangwook.net)](https://jangwook.net/en/blog/en/claude-code-parallel-sessions-git-worktree/)
- [Claude Code Workflow Patterns — Agentic Guide 2026 (Popular AI Tools)](https://popularaitools.ai/blog/claude-code-workflow-patterns-agentic-guide-2026)
- [How to Run Claude Code Agents in Parallel (lowcode.agency)](https://www.lowcode.agency/blog/claude-code-parallel-agents)
