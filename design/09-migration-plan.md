# Manifold UI — Stage 9: Migration Plan

Goal: replace the existing UI with the one designed across Stages 1–8 and
rendered in `design/html/*.html`, while never leaving the codebase in a
half-migrated state. By the end of this plan, every file listed under
"Delete" is gone and only the new surfaces ship.

---

## 1. What gets built

Every HTML file in `design/html/` is a committed spec. Each is the
acceptance reference for a concrete Swift surface. The table below maps
the new surface, the HTML reference, and the Swift location it will live
at.

| New surface | HTML ref | Swift file(s) (new) |
|---|---|---|
| **Ledger window shell** — 5-item sidebar, integrated toolbar, status bar | implied across all app surfaces | `Views/LedgerWindowView.swift`, `Views/Chrome/NavSidebar.swift`, `Views/Chrome/IntegratedToolbar.swift`, `Views/Chrome/StatusBar.swift` |
| **Menu bar panel** — 4 states (idle / idle+recent / active+queue / tracked edit) | `menubar.html` | `Views/MenuBar/MenuBarPanelView.swift` (rewritten), `Views/MenuBar/States/*.swift` |
| **First-run** — 3 panels: concept / defaults / guided add | `firstrun.html` | `Views/FirstRun/FirstRunFlow.swift`, `Views/FirstRun/Panels/*.swift` |
| **Activity** — 3-pane ledger with session rail, event table, evidence inspector | `activity.html` | `Views/Activity/ActivityWindowView.swift`, `Views/Activity/SessionRail.swift`, `Views/Activity/EventTable.swift`, `Views/Activity/EvidenceInspector.swift` |
| **Access — Folders** — coverage matrix, bulk select, file-tree inspector | `access.html` view 1 | `Views/Access/AccessWindowView.swift`, `Views/Access/FoldersMatrixView.swift`, `Views/Access/FileTreeInspector.swift`, `Views/Access/BulkActionBar.swift` |
| **Access — Files** — flat file list with version timeline | `access.html` view 2 | `Views/Access/FilesFlatView.swift`, `Views/Access/VersionTimelineInspector.swift` |
| **Access — Session** — live overlay diff | `access.html` view 3 | `Views/Access/SessionDiffView.swift`, `Views/Access/SessionAdditionInspector.swift` |
| **Access — History** — past sessions with resume | `access.html` view 4 | `Views/Access/HistoryListView.swift`, `Views/Access/SessionDetailInspector.swift` |
| **Access — Empty** | `access.html` view 5 | `Views/Access/EmptyFoldersView.swift` |
| **Mail — Mailboxes** | `mail.html` view 1 | `Views/Mail/MailWindowView.swift`, `Views/Mail/MailboxesMatrixView.swift`, `Views/Mail/MailboxInspector.swift`, `Views/Mail/SensitivitySelector.swift` |
| **Mail — Threads (Active Backup)** | `mail.html` view 2 | `Views/Mail/ThreadsView.swift`, `Views/Mail/SenderRail.swift`, `Views/Mail/ThreadTable.swift`, `Views/Mail/ThreadInspector.swift` |
| **Mail — Session / History / Empty** | `mail.html` views 3–5 | `Views/Mail/MailSessionView.swift`, `Views/Mail/MailHistoryView.swift`, `Views/Mail/EmptyMailView.swift` |
| **Requests — Pending / Recent / Empty** | `requests.html` | `Views/Requests/RequestsWindowView.swift`, `Views/Requests/PendingQueueView.swift`, `Views/Requests/ApprovalCard.swift`, `Views/Requests/RecentAnswersView.swift`, `Views/Requests/PatternDetectionInspector.swift`, `Views/Requests/EmptyRequestsView.swift` |
| **Rules — Files / Email / Agents** | `rules.html` views 1–3 | `Views/Rules/RulesWindowView.swift`, `Views/Rules/FilesRulesView.swift`, `Views/Rules/EmailRulesView.swift`, `Views/Rules/AgentsRulesView.swift`, `Views/Rules/RuleCard.swift`, `Views/Rules/BlastRadiusPreview.swift` |
| **Rules — New rule sheet** | `rules.html` view 4 | `Views/Rules/NewRuleSheet.swift`, `Views/Rules/RuleBuilder.swift`, `Views/Rules/LiveMatchPreview.swift` |
| **Session start / reload** | `session-start.html` | `Views/Session/SessionStartSheet.swift`, `Views/Session/ReloadDriftSheet.swift` |

Shared primitive components (all new, under `Components/Primitives/`):

- `LiquidGlassMaterial.swift` — NSVisualEffectView wrapper with inner highlight + tinted translucent fill
- `ManifoldPalette.swift` — fixed agent / status colors with light+dark variants (replaces system accent)
- `GradientAvatar.swift` — agent tile used in rows, cards, inspectors
- `AgentStatusDot.swift` — dot with optional pulse halo + reduce-motion
- `SessionChip.swift` — green pulsing chip used in toolbars, sidebars, cards
- `SparklineBar.swift` — session / event / blast-radius sparklines
- `TriStateCheckbox.swift` — tri-state + override-dot variant for file trees
- `SegmentedToggle.swift` — confident slot toggles (default/session/attention variants)
- `CommitLadder.swift` — 4-button approval row (deny-focused)
- `PillLibrary.swift` — session / default / attention / scope / seeded / user pills
- `FileIcon.swift` — file-type colored icons (swift orange, JSON yellow, MD grey, folder blue)
- `EvidenceInspector.swift` — shared chrome for selected-item inspectors
- `KbdLabel.swift` — keyboard hint pill
- `EmptyStateIllustration.swift` — glowing card + icon composite

Data primitives (new, in `ManifoldRuntime` + exposed via `PolicyModel`):

- `Session` — name, start, expiresAt, agents, baseMode (default / blank / defaultMinus), additions, subtractions, tracked flag
- `ApprovalRequest` — agent, operation, target, context, createdAt, snoozedUntil
- `Rule` — domain (email/files/agents), grammar (subject/verb/object), glob / predicate, enabled, seeded flag, created-by
- `ScopeEntry` — unified folder + mailbox access entry tied to an agent
- `FileNode` extensions — per-file inclusion flags + exclusion trace (rule / manual / smart default / override)
- `DenialEvent` — structured denial record for blast-radius charts
- `SessionHistory` — past-session index + drift computation for reload

---

## 2. What gets deleted

Concrete file-by-file deletion list. Paths relative to `ManifoldApp/ManifoldApp/`. Every entry is replaced by a named new surface; no feature regresses.

### Views — deleted entirely

| File | Replaced by |
|---|---|
| `Views/MainView.swift` | `Views/LedgerWindowView.swift` |
| `Views/OverviewView.swift` | menu bar headline + Activity |
| `Views/AgentPolicyCard.swift` | `Views/MenuBar/...AgentRow.swift` + Access inspector |
| `Views/AgentFocusControl.swift` | agent filter chips in Activity/Mail toolbars |
| `Views/ActivityView.swift` | `Views/Activity/ActivityWindowView.swift` |
| `Views/ActivityRow.swift` | `Views/Activity/EventTable.swift` row rendering |
| `Views/ActivityDrawer.swift` | `Views/Activity/EvidenceInspector.swift` |
| `Views/FilesView.swift` | `Views/Access/FilesFlatView.swift` |
| `Views/FilesDashboardView.swift` | `Views/Access/EmptyFoldersView.swift` |
| `Views/FilesSidebar.swift` | 5-item nav + Access matrix |
| `Views/SourcesTableView.swift` | `Views/Access/FoldersMatrixView.swift` |
| `Views/ReviewAccessSheet.swift` | `Views/Requests/PendingQueueView.swift` (non-modal) |
| `Views/ReviewChangesSheet.swift` | Activity revert flow in `EvidenceInspector` |
| `Views/WorkBlockBannerView.swift` | `SessionChip` in toolbar + `Views/MenuBar/States/TrackedEdit.swift` |
| `Views/CommandPaletteView.swift` | *deferred* — keep or delete after ⌘K decision |

### Versions — replaced by Access Files version timeline

| File | Replaced by |
|---|---|
| `Views/Versions/VersionsView.swift` | `Views/Access/FilesFlatView.swift` |
| `Views/Versions/VersionDetailView.swift` | `Views/Access/VersionTimelineInspector.swift` |
| `Views/Versions/SnapshotRow.swift` | timeline `vnode` renderer |

### Email — entire tree replaced by Mail surface (23 files)

Everything under `Views/Email/` is replaced by `Views/Mail/`:

- `Views/Email/EmailView.swift`
- `Views/Email/MessageList/EmailMessageList.swift`, `EmailMessageRow.swift`, `InlineMessagePreview.swift`, `MessageFilterBar.swift`, `SelectionActionBar.swift`
- `Views/Email/ReadingPane/*` (6 files) — reading pane is **explicitly deleted** per Stage 8 (Active Backup, not Mail client)
- `Views/Email/Rules/*` (7 files — `ContactRulesView`, `DomainRulesView`, `EmailPolicyView`, `EmailRulesView`, `KeywordRulesView`, `RulesDashboardView`, `ShieldDetailView`) — replaced by global `Views/Rules/EmailRulesView.swift` + per-mailbox inspector in `MailboxInspector`
- `Views/Email/ShareWithCowork/ShareWithCoworkSheet.swift` — replaced by thread-level checkboxes in `ThreadTable` and bulk action bar
- `Views/Email/Sidebar/AccountTreeSection.swift`, `AddAccountButton.swift`, `EmailSidebar.swift`, `QuickFilterSection.swift`, `SharedEmailsRow.swift`, `UnifiedInboxRow.swift` — replaced by `Views/Mail/SenderRail.swift`
- `Views/Email/SmartMailbox/SmartMailboxEditor.swift` — subsumed by global Rules

### Library

| File | Replaced by |
|---|---|
| `Views/Library/EmailAccountSetupView.swift` | `Views/Mail/EmptyMailView.swift` + `Views/Setup/AddMailAccountSheet.swift` |

### Setup — rebuilt, some kept

| File | Disposition |
|---|---|
| `Views/Setup/SetupAssistantView.swift` | **Rewritten** as `Views/FirstRun/FirstRunFlow.swift` |
| `Views/Setup/ConnectClaudeSheet.swift` | **Kept** — visual refresh using new tokens |
| `Views/Setup/ConnectCodexSheet.swift` | **Kept** — visual refresh using new tokens |
| `Views/Setup/AddMailAccountSheet.swift` | **Kept** — visual refresh (OAuth / IMAP flow) |

### Settings — kept as-is, copy + visual pass later

`Views/Settings/*` — all kept. Stage 3 §L closes with "needs a copy pass, not a visual rebuild." Apply new tokens automatically; update microcopy in a later minor pass.

### Components — deleted or refactored

| File | Disposition |
|---|---|
| `Components/DesignTokens.swift` | **Rewritten** — new palette / gradients / materials / shadows |
| `Components/Spacing.swift` | **Rewritten** — 4pt baseline, 8pt grid |
| `Components/AgentBadge.swift` | **Delete** — replaced by `GradientAvatar` |
| `Components/Badge.swift` | **Delete** — replaced by `PillLibrary` |
| `Components/StatusBadge.swift` | **Delete** — replaced by `PillLibrary` + `AgentStatusDot` |
| `Components/ColorIndicator.swift` | **Delete** — replaced by `AgentStatusDot` |
| `Components/DetailLine.swift` | **Delete** — replaced by inspector meta-row pattern |
| `Components/LiveCheckRow.swift` | **Delete** — tied to old setup/review |
| `Components/RuleFormComponents.swift` | **Delete** — replaced by `RuleBuilder` in new-rule sheet |
| `Components/TrackChangesToolbarContent.swift` | **Delete** — replaced by `SessionChip` |
| `Components/DiffView.swift` | **Keep** — used by Activity + Access Files |
| `Components/TimeLabel.swift` | **Keep** |
| `Components/ActionFormatting.swift` | **Keep** — still supplies icon + color for event types |

### Models — kept, with extensions

All current `Models/*` files stay. The Stage-6 session primitive and Stage-7 rule grammar are **additive**; they do not remove types, they add new ones alongside. Three notes:

- `EmailRulesModel.swift` — the *data* is kept (rule storage), but its UI consumers move. After Phase 5/7 it is used by `MailboxInspector` and `RulesWindowView`, not by a standalone Email Rules surface.
- `PolicyModel.swift` — the internal `activeWorkBlock` concept is **renamed** to `activeSession` with the Stage-6 shape. A thin adapter preserves any external callers during the migration; the adapter is deleted in Phase 10.
- `CommandCenter.swift` — keep for command-palette infrastructure even if `CommandPaletteView` is deferred.

### App entry

`ManifoldApp.swift` — **keep**, update to host `LedgerWindowView` and the new `MenuBarPanelView`. Scene configuration gains an `LSUIElement`-driven dock-icon policy (Stage 3 §A decision deferred; default on for now).

### Intents / FinderSync

`Intents/ManifoldIntents.swift` and `ManifoldFinderSync/FinderSync.swift` — **keep**. Finder Sync is the roadmap entry point for drag-a-folder flows (Stage 6 deferred). App Intents remain valid.

---

## 3. Sequencing — phased, each phase ships

Each phase leaves `main` green and buildable. No half-deleted surface at any point. Feature flag `NEW_UI` gates the new Ledger window until Phase 10 (the flag is then deleted).

### Phase 0 — Tokens + Liquid Glass foundation (1–2 days)

**Build:**
- Rewrite `Components/DesignTokens.swift` — fixed `ManifoldPalette`, gradients, shadows, type roles, motion primitives
- Rewrite `Components/Spacing.swift` — 4pt baseline
- New `Components/Primitives/LiquidGlassMaterial.swift` — NSVisualEffectView wrapper
- New `Components/Primitives/GradientAvatar.swift`, `AgentStatusDot.swift`, `PillLibrary.swift`, `KbdLabel.swift`
- Add `NEW_UI` environment flag plumbing

**Delete:** nothing yet.

**Verify:** `swift build`, `swift test`, `xcodebuild` — all green.

### Phase 1 — Data primitives (2–3 days)

**Build:**
- `Session` struct in ManifoldRuntime (or `ManifoldKit`) with all Stage-6 fields
- `ApprovalRequest` — persistent queue entity
- `Rule` — domain-tagged rule with glob + predicate + blast-radius evaluator
- `ScopeEntry`, `DenialEvent`, `SessionHistory`
- `PolicyModel` extensions: `activeSession` (adapter from `activeWorkBlock`), `pendingRequests`, `recentSessions`, `drift(for:)`
- `ManifoldStore` surfaces the new primitives
- Unit tests for Session reload drift math and Rule evaluation

**Delete:** nothing yet.

**Verify:** `swift build`, `swift test` (new test targets pass).

### Phase 2 — Shell + Menu bar rebuild (3–5 days)

**Build:**
- `Views/LedgerWindowView.swift` (behind `NEW_UI`)
- `Views/Chrome/NavSidebar.swift`, `IntegratedToolbar.swift`, `StatusBar.swift`
- Rebuilt `Views/MenuBar/MenuBarPanelView.swift` — 4 states
- `Views/MenuBar/States/Idle.swift`, `IdleWithRecent.swift`, `ActiveWithQueue.swift`, `TrackedEdit.swift`
- All 5 sidebar destinations route to placeholder empty states initially

**Delete:** nothing yet (old `MainView.swift` still live behind flag-off).

**Verify:** launch with and without `NEW_UI`. Both paths work; flag-on shows shell with empty destinations.

### Phase 3 — Activity (3–4 days)

**Build:**
- `Views/Activity/ActivityWindowView.swift`
- `Views/Activity/SessionRail.swift` — per-session sparklines, sticky headers
- `Views/Activity/EventTable.swift` — 7-column dense, denial leading edge
- `Views/Activity/EvidenceInspector.swift` — diff, history strip, related files, revert
- Reuse `Components/DiffView.swift` and `ActionFormatting.swift`
- Deep-link from menu bar "Open Ledger" and ⌘O

**Delete at end of phase:**
- `Views/ActivityView.swift`
- `Views/ActivityRow.swift`
- `Views/ActivityDrawer.swift`

**Verify:** `xcodebuild`, launch, scroll through real events, select, revert.

### Phase 4 — Access (4–5 days)

**Build:**
- `Views/Access/AccessWindowView.swift` with tab routing
- `FoldersMatrixView.swift` with bulk select + `BulkActionBar`
- `FileTreeInspector.swift` with `TriStateCheckbox` and exclusion traces
- `FilesFlatView.swift` with version chips
- `VersionTimelineInspector.swift`
- `SessionDiffView.swift`
- `HistoryListView.swift` with resume action
- `SessionDetailInspector.swift` with drift preview
- `EmptyFoldersView.swift`

**Delete at end of phase:**
- `Views/FilesView.swift`
- `Views/FilesDashboardView.swift`
- `Views/FilesSidebar.swift`
- `Views/SourcesTableView.swift`
- `Views/Versions/VersionsView.swift`
- `Views/Versions/VersionDetailView.swift`
- `Views/Versions/SnapshotRow.swift`

**Verify:** add folder, drill into file tree, trigger a denial, reload a past session, resume with drift.

### Phase 5 — Mail (4–5 days)

**Build:**
- `Views/Mail/MailWindowView.swift`
- `MailboxesMatrixView.swift` with `SensitivitySelector`
- `MailboxInspector.swift` with senders, labels, rules banner
- `ThreadsView.swift` — Active Backup layout
- `SenderRail.swift`, `ThreadTable.swift`, `ThreadInspector.swift`
- `MailSessionView.swift`, `MailHistoryView.swift`, `EmptyMailView.swift`

**Delete at end of phase:**
- Entire `Views/Email/` subtree (23 files enumerated above)
- `Views/Library/EmailAccountSetupView.swift`
- Any navigation entry points to Email/* in MainView

**Verify:** connect mailbox via `AddMailAccountSheet`, pick sender, check threads, start session, review state, finish, reload.

### Phase 6 — Requests (2–3 days)

**Build:**
- `Views/Requests/RequestsWindowView.swift`
- `PendingQueueView.swift`, `ApprovalCard.swift` with `CommitLadder`
- `RecentAnswersView.swift`
- `PatternDetectionInspector.swift` — auto-rule suggestion
- `EmptyRequestsView.swift`
- Wire runtime request-emission to `ApprovalRequest` queue
- Replace any remaining modal approval call sites with queue-insert

**Delete at end of phase:**
- `Views/ReviewAccessSheet.swift`
- `Views/ReviewChangesSheet.swift`
- `Views/WorkBlockBannerView.swift`
- `Components/TrackChangesToolbarContent.swift`

**Verify:** trigger an agent read outside scope → card appears in queue → keyboard ↩ denies, ⌘↩ promotes to default, ⌥↩ for session. No modal fires.

### Phase 7 — Rules (2–3 days)

**Build:**
- `Views/Rules/RulesWindowView.swift`
- `FilesRulesView.swift`, `EmailRulesView.swift`, `AgentsRulesView.swift`
- `RuleCard.swift`, `BlastRadiusPreview.swift`
- `NewRuleSheet.swift` + `RuleBuilder.swift` + `LiveMatchPreview.swift`
- Seed migration: on first launch under new UI, seed the default safe rules (*.env, *.pem, .ssh/, credit-card, SSN redaction, never-write-to-.git/) if user has none

**Delete at end of phase:**
- `Views/Email/Rules/*` (7 files, if still present — likely already deleted in Phase 5 as part of the Email subtree purge)
- `Components/RuleFormComponents.swift`
- `Views/Email/SmartMailbox/SmartMailboxEditor.swift` (if still present)

**Verify:** create new rule, see live blast count, toggle on/off, create auto-rule from Pattern Detection inspector.

### Phase 8 — First-run + Session sheets (1–2 days)

**Build:**
- `Views/FirstRun/FirstRunFlow.swift` + 3 panel views
- `Views/Session/SessionStartSheet.swift`
- `Views/Session/ReloadDriftSheet.swift`
- Hook first-run flow to `Views/Setup/SetupAssistantView.swift` replacement path
- Wire ⌘N from menu bar to `SessionStartSheet`

**Delete at end of phase:**
- Contents of `Views/Setup/SetupAssistantView.swift` (replaced by `FirstRunFlow`) — delete the file after the replacement is verified

**Verify:** fresh install → first-run flow walks correctly → skippable → idle menu bar → start session via ⌘N → reload from Recent shows drift preview.

### Phase 9 — Settings copy pass (1 day)

**Build:**
- Apply new tokens to `Views/Settings/*` — picks up palette automatically
- Copy pass on each pane; move anything engineering-flavored to `Advanced`
- New microcopy from Stage-5 strings catalog where one exists

**Delete:** nothing.

**Verify:** `xcodebuild`, visit each pane, confirm nothing regresses.

### Phase 10 — Cleanup + flag removal (1 day)

**Build / change:**
- Remove `NEW_UI` feature flag; promote new shell to default (and only) path
- Reduce `ManifoldApp.swift` to the new Scene graph (LedgerWindow + MenuBarExtra + Settings + First-run presentation rules)
- Collapse `PolicyModel` work-block adapter — rename to `activeSession` throughout
- Update `ManifoldIntents.swift` strings where they referenced old surface names

**Delete:**
- `Views/MainView.swift`
- `Views/OverviewView.swift`
- `Views/AgentPolicyCard.swift`
- `Views/AgentFocusControl.swift`
- `Components/AgentBadge.swift`
- `Components/Badge.swift`
- `Components/StatusBadge.swift`
- `Components/ColorIndicator.swift`
- `Components/DetailLine.swift`
- `Components/LiveCheckRow.swift`
- Anything still referencing "work block" in source (all replaced by Session)
- Dead tests and fixtures tied to the deleted views

If Command Palette is kept, leave `Views/CommandPaletteView.swift` and `Models/CommandCenter.swift`. If deferred, delete both.

**Verify:** `xcodebuild` is clean with zero references to any deleted type. `swift test` passes. `git grep -l "WorkBlock\|OverviewView\|ReviewAccessSheet\|ActivityDrawer"` returns no source file results. Launch from a clean DerivedData.

---

## 4. Running verification commands

Per `CLAUDE.md`, every phase ends with at least one of:

- **Runtime / package changes** (Phases 0, 1, 10):
  ```
  env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
      SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
      swift build && swift test
  ```
- **App / UI / Xcode project changes** (Phases 2–9):
  ```
  env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
      SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
      xcodebuild -project Manifold.xcodeproj -scheme Manifold \
                 -configuration Debug \
                 -derivedDataPath /tmp/manifold-derived-data \
                 build CODE_SIGNING_ALLOWED=NO
  ```
- **Launch/runtime** verification on every phase that changes app startup or XPC surface — not just compile, per the project rule.

Each phase's PR description must name the exact commands that ran.

---

## 5. Guardrails

- **No half-migrated main.** Every phase's PR leaves `main` buildable and launch-able. If the flag is on, the new path works; if off, the old path works. Phase 10 removes the flag only once.
- **Deletion is part of the same PR as replacement.** A phase doesn't end "in two weeks we'll delete X." The deletion and the replacement land together, at the end of that phase.
- **One composition root.** All new surfaces reach runtime via `ManifoldStore` / `AppRuntimeClient`, per `CLAUDE.md` §Editing Rules. No new call sites that bypass XPC.
- **Tokens are the only styling layer.** No ad-hoc colors or paddings in new view files. If a value isn't in `DesignTokens.swift`, add it there first.
- **Strings catalog.** Every user-visible string in new views resolves through one file. Per Stage 5, no engineering vocabulary leaks.
- **Accessibility is acceptance, not polish.** Every new row / card / button has a label + keyboard path + a second channel beyond color. Enforced in the PR template checklist per phase.

---

## 6. Rollback strategy

- Phases 0–1 are additive. Rollback = revert the PR.
- Phases 2–9 ship behind `NEW_UI`. Rollback = unset the flag; new code remains inert but present.
- Phase 10 is the only non-rollback-safe step. It happens last, after every earlier phase has been lived with for at least one full work session with the flag on.

A single-commit "kill switch": if the app detects a runtime mismatch with the new Session primitives (e.g. corrupt persisted state), it reverts to read-only default scope, surfaces a `Views/Chrome/FallbackBanner.swift`, and disables session creation — honest state per Principle 10.

---

## 7. Effort estimate

Single-engineer calendar days with AI pairing:

| Phase | Days |
|---|---|
| 0 · Tokens / glass | 1–2 |
| 1 · Data primitives | 2–3 |
| 2 · Shell + Menu bar | 3–5 |
| 3 · Activity | 3–4 |
| 4 · Access (5 sub-views) | 4–5 |
| 5 · Mail (5 sub-views) | 4–5 |
| 6 · Requests | 2–3 |
| 7 · Rules | 2–3 |
| 8 · First-run + session sheets | 1–2 |
| 9 · Settings copy | 1 |
| 10 · Cleanup | 1 |
| **Total** | **24–34 days** |

Highest-risk phases: 1 (data primitives — if `Session` is wrong, every subsequent view will be wrong) and 5 (Mail — largest surface, deletes most files). Do Phase 1 carefully; Phase 5 can be split into 5a Mailboxes and 5b Threads if it gets unwieldy.

---

## 8. Acceptance — end-of-migration checklist

- [ ] Every file in §2 is deleted from `ManifoldApp/ManifoldApp/`.
- [ ] `git grep` finds zero references to any deleted type across the codebase, including tests and fixtures.
- [ ] `xcodebuild -project Manifold.xcodeproj -scheme Manifold -configuration Release` succeeds.
- [ ] `swift test` passes with no `@available`-gated fallbacks to deleted code paths.
- [ ] App launches from a clean `DerivedData` and a fresh user home; first-run flow renders correctly.
- [ ] Menu bar panel shows each of the 4 states when the corresponding runtime state is present.
- [ ] All 5 sidebar destinations render content; empty states are reached and look correct.
- [ ] Agents can request access; request appears in `RequestsWindowView`; no modal fires on any code path.
- [ ] Sessions can be started, resumed, finished; reload shows drift preview honestly.
- [ ] Rules: create, toggle, live blast preview updates, seed defaults were applied on first run.
- [ ] `NEW_UI` flag is fully removed; no conditional UI branching remains.
- [ ] Accessibility audit (VoiceOver, keyboard-only, reduce-motion, increase-contrast) passes every surface.

When all boxes are checked, the old UI is gone and the designed UI is what ships.
