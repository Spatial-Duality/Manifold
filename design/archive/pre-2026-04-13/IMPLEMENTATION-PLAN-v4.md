# Manifold v4.1 Implementation Plan

> **Purpose**: Complete implementation guide for Claude Code to build the v4.1 UI. Contains the current-state audit, open question resolutions, file-by-file implementation plan, phase ordering, and final recommendation summary.
>
> **Companion to**: LAYOUT-SPEC-v4.md (v4.1 — the authoritative UI spec). This document is the *how*; LAYOUT-SPEC-v4.md is the *what*.
>
> **Revision 4.1**: Updated to reflect all 8 critique integrations — no Overview sidebar, all broadening through Review sheet, full-height attached sheet, each surface one job, Agent Focus Rule, first-class Work Block Banner, accessibility/material rules, updated copy.

---

## 1. CURRENT-STATE AUDIT

### 1.1 What exists today (v2 wireframe + codebase)

**Navigation model**: 5-item vertical sidebar (Home, Files, Emails, History, Sources) via `SidebarView.swift`. `MainView.swift` uses a three-column `NavigationSplitView` with sidebar → detail → inspector. This is fundamentally sound but needs to change from sidebar nav to top-bar segmented control with 3 tabs.

**Session lifecycle**: `SessionModel.swift` (809 lines) is the heaviest model. It owns `activeGrant`, `activeGrantSources`, `selectedPreset`, `SessionPreview`. Calls `GrantStore.startGrant()` → `MaterializationEngine.materialize()` → polling → `PromoteEngine.promote()`. The entire flow assumes a session *must* be started before any agent access. This is the primary thing that needs to change — standing access means grants are persistent, not session-gated.

**File access controls**: `SourcesView.swift` manages source folders with pause/resume/remove context menus. `FilesView.swift` is a file explorer with search. Neither currently has per-agent checkbox columns — agent access is implied by session scope. The v2 wireframe shows Claude/Codex checkbox columns in the Files sidebar, but the codebase hasn't implemented this.

**Email tab**: `EmailView.swift` is a full `NavigationSplitView` (sidebar → message list → reading pane). `EmailSidebar` shows accounts, smart mailboxes, and a "Session Email Access" stats section. No domain-level access control table exists — the wireframe shows per-email "visible this session" badges but no domain management surface. `EmailSensitivityFilter` exists in ManifoldKit but the UI only exposes it via a single sensitivity dropdown in the sidebar.

**History tab**: `HistoryView.swift` has three modes (Sessions/Timeline/Files). Session-centric. `ActivityView.swift` (479 lines) is robust with filters, search, session grouping, diff viewer, revert buttons. This is good infrastructure that can be repurposed as the Activity drawer.

**MCP bridge**: `ManifoldBridge.swift` calls `requireGrant()` on every tool invocation. Fail-closed. Currently resolves access through active grant → materialization root. Needs adaptation for standing access (resolve `AgentAccessPolicy` directly).

**Dashboard**: `DashboardView.swift` + sub-components show session banner, sources, recent activity. Session-start is the primary CTA. This needs to become the Overview tab with agent policy cards — full-width, no sidebar.

### 1.2 Gap analysis: v2 → v4.1

| Area | v2 State | v4.1 Target | Gap |
|------|----------|-------------|-----|
| **Navigation** | 5-item sidebar | 3-tab segmented top bar | Structural change: sidebar → TabView |
| **Access model** | Session-gated grants | Standing access + opt-in work blocks | New `AgentAccessPolicy` entity, `SessionModel` refactored |
| **File access controls** | Implicit from session scope | Per-agent checkbox on Sources table, Agent Focus segmented control | New Sources mode with Claude/Codex/Compare |
| **Email access** | Per-email reading pane badges | Domain-level table with per-agent checkbox, Agent Focus segmented control | New Domains mode, new domain data model |
| **Sensitivity** | Single dropdown, session-scoped | Per-agent persistent dropdown in Domains **toolbar** (not sidebar) | UI + persistence change |
| **Review Access sheet** | "Review Session Scope" card | Full-height attached sheet for **ALL** broadening events | New sheet view, trigger logic on every broadening action |
| **Work Blocks** | The *only* mode (sessions = work blocks) | Opt-in mode with global persistent banner | `WorkBlockRecord` type, `WorkBlockBannerView`, refactored snapshot flow |
| **History** | Top-level tab with 3 modes | Activity drawer (replaces right inspector) | Demote to drawer, keep `ActivityView` internals |
| **MCP bridge** | `requireGrant()` per call | `resolvePolicy()` per call | New resolution path in ManifoldBridge |
| **Overview** | Dashboard with session banner | Full-width agent policy cards, **no sidebar** | New `OverviewView` with `AgentPolicyCard` |
| **Pause/Resume** | Source-level pause | Agent-level pause (emergency control) | New `isPaused` on `AgentAccessPolicy` |
| **Temporary reveals** | Not implemented | Single-email temp visibility | New `TemporaryReveal` type + UI in reading pane |
| **Agent focus** | Not implemented | Claude / Codex / Compare segmented control on Files and Emails | New `AgentFocusControl` component, single-column vs. dual-column table switching |

### 1.3 What to keep (reusable as-is or near-as-is)

- **EmailView.swift** internal structure (3-pane NavigationSplitView) — add Domains mode alongside Messages mode
- **ActivityView.swift** core (filters, search, event rows, diff viewer) — wrap in drawer container
- **VersionsView.swift** + **VersionDetailView.swift** — move into Files Inspector
- **Components**: `AgentBadge`, `StatusBadge`, `DiffView`, `TimeLabel`, `Spacing` — all reusable
- **ManifoldKit stores**: ContentStore, SnapshotStore, AuditStore, EmailStore, EmailSyncEngine, ContextEngine, DiffEngine, EmailSensitivityFilter — all unchanged or minimal adaptation
- **ManifoldStore.swift** — refactor, don't rewrite. Remove session ceremony, add policy management

---

## 2. OPEN QUESTION RESOLUTIONS

### Q1: How often should the Review Access sheet appear?

**Resolution: ALWAYS for broadening. NEVER for narrowing.**

The Review & Update Access sheet opens when:
- Checking ANY unchecked source for an agent (every time, not just the first)
- Checking ANY unchecked email domain for an agent
- Loosening email sensitivity (e.g., Strict → Moderate)
- Bulk adding multiple sources/domains at once
- User explicitly clicks "Review & Update Access" (from Overview card, or ⌘⇧R)
- Starting a Tracked Work Block
- Copying access policy between agents

It does NOT open for:
- Unchecking a source (narrowing → inline + undo toast)
- Unchecking a domain (narrowing → inline + undo toast)
- Tightening sensitivity (narrowing → inline + undo toast)
- Pausing access (immediate, no sheet)

**Why**: The original v4.0 plan used "first-grant-per-agent + explicit-only" to avoid sheet fatigue. The critique correctly identified this as the wrong tradeoff — this is a privacy/trust product, and the Review sheet is the product's core commitment surface. Making ALL broadening go through the sheet means every grant is deliberate. This mirrors Apple's privacy model: you don't get to skip the permission dialog after the first time.

**Second-order effect**: The sheet MUST be fast and lightweight. If it's slow or cluttered, this design fails because users will resent it. Pre-populate the sheet with the specific change, highlight "What's Changing" in a green-tinted section, make the confirm button immediately reachable. The sheet should take under 2 seconds to review and confirm for a simple single-source addition.

### Q2: Where should advanced settings live?

**Resolution: Settings window (⌘,), not in Review Access sheet.**

Advanced settings (work block notes capture mode, inactivity timeout for work blocks, presets) should live in the Settings window under a "Work Blocks" tab. The Review Access sheet includes only a disclosure triangle labeled "Advanced" that shows work block options inline for convenience, but the canonical home is Settings.

**Why**: Putting advanced settings in the Review Access sheet creates two problems: (1) it makes the sheet feel heavier than it needs to be (critical now that every broadening goes through the sheet), and (2) users who want to change these settings outside of a grant flow have no way to find them. Settings window is the macOS-standard location for persistent preferences.

### Q3: Where should sensitivity controls live?

**Resolution: Domains table toolbar, scoped to the focused agent. NOT in the sidebar.**

The sidebar's job is pure navigation (account tree, smart mailboxes). The sensitivity dropdown governs data that appears in the Domains table, so it lives in the Domains toolbar, right next to the Agent Focus segmented control. Label: "Sensitivity: [Moderate ▼]". The dropdown value is scoped to whichever agent is focused.

**Why (from critique point 4)**: Each surface must have ONE job. The sidebar is navigation. The toolbar is for controls that govern the table's data. Mixing navigation and data controls in the sidebar violates this principle and buries an important control under a fold the user might not scroll to.

### Q4: How should History/Activity be accessed?

**Resolution: Activity drawer (right-side, replaces Inspector when open).**

Activity is a utility surface, not a primary navigation destination. The user goes to Activity to answer "what did this agent do?" — usually in the context of reviewing a specific file or agent. Making it a drawer means:
- It's accessible from any tab (via sidebar "View Activity →" link, Overview "View Activity →", ⌘⇧A)
- It doesn't compete with the core ownership tabs (Overview, Files, Emails)
- It can show agent-specific activity when opened from an agent card
- It can show file-specific activity when opened from the Files inspector

### Q5: How to handle mixed-content domains like gmail.com?

**Resolution: Treat gmail.com as a single domain with a category tag. Do not sub-split.**

The domain table shows `@gmail.com` as one row. Its category is auto-detected as "Personal" by the `EmailSensitivityFilter` heuristics. The user can override the category. If checked, *all* emails from gmail.com addresses become visible to that agent.

For v1, this is honest and simple. The sensitivity filter still blocks emails that match 2FA/banking patterns regardless of domain.

**Future improvement (v2+)**: Allow per-sender overrides within a domain. Show in Inspector when a domain row is clicked. Not in the main table.

### Q6: How to display concurrent agents?

**Resolution: Agent Focus segmented control — one agent at a time by default, Compare mode for side-by-side.**

Files and Emails tabs show a segmented control in the toolbar: **Claude | Codex | Compare**.

- **Claude mode** (or Codex mode): Single "Access" column. The table is calm and focused. Sidebar source dots show this agent's state. Row tinting uses this agent's color.
- **Compare mode**: Two labeled columns — "Claude" and "Codex". Row tinting is disabled (too noisy with two colors). User explicitly opts into the wider view.

**Why (from critique point 5)**: The v4.0 approach of always showing two columns creates visual noise. Most of the time the user is working with one agent. The Compare mode is there for the "let me make sure both agents have the right access" workflow, which is less frequent.

**Connection state**: Even if only Claude is connected, Codex mode is available (dimmed column but still shows persistent policy). Access policy is persistent regardless of connection state.

### Q7: How should Work Block state be represented visually?

**Resolution: Global persistent banner below top bar — visible on ALL tabs.**

When a Work Block is active:
- **Work Block Banner** appears below the top bar, above all tab content, spanning full width
- Banner shows: agent dot + name, duration, modified file count, new file count, action buttons
- Banner is visible on Overview, Files, AND Emails tabs — it's app-wide state
- Agent card on Overview does NOT show work block status (the banner does that job)

When NO work block is active (the common case with standing access):
- No banner, no special states, no ceremony
- "Start Tracked Work Block" button appears below agent cards on Overview

**Why (from critique point 6)**: Work block status is critical operational context. Burying it in an agent card (one of two) on one tab (Overview) means the user loses awareness when they navigate to Files or Emails. The global banner keeps this front and center without cluttering any individual surface.

---

## 3. FILE-BY-FILE IMPLEMENTATION PLAN

### 3.1 Files to DELETE (session-first artifacts)

| File | Reason |
|------|--------|
| `Views/SessionView.swift` (308 lines) | Session file browser → replaced by Files tab Sources/Files modes |
| `Views/PresetPickerView.swift` | Session preset selection → moved to Settings window |
| `Models/SessionModel.swift` (809 lines) | Session lifecycle → replaced by `PolicyModel.swift` + `WorkBlockModel.swift` |

### 3.2 Files to CREATE

| File | Purpose | Approximate Lines |
|------|---------|-------------------|
| **Models/PolicyModel.swift** | `@Observable`. Manages `AgentAccessPolicy` per agent. Methods: `loadPolicies()`, `updateFileAccess()`, `updateEmailAccess()`, `updateSensitivity()`, `pauseAgent()`, `resumeAgent()`. Replaces session ceremony with direct policy CRUD. | ~250 |
| **Models/WorkBlockModel.swift** | `@Observable`. Manages `WorkBlockRecord` lifecycle. Methods: `startBlock()`, `finishBlock()`, `pauseBlock()`, `stopBlock()`. Wraps `MaterializationEngine` + `SnapshotStore` + `PromoteEngine`. | ~200 |
| **Models/DomainModel.swift** | `@Observable`. Computes domain aggregates from `EmailStore`. Properties: domain list with counts, category assignments, visibility per agent. Methods: `computeDomains()`, `toggleDomain()`, `bulkToggle()`. | ~150 |
| **Views/OverviewView.swift** | Overview tab main content. **Full-width, no sidebar.** Two `AgentPolicyCard` views centered with max-width constraint. "Start Tracked Work Block" button below cards. | ~100 |
| **Views/AgentPolicyCard.swift** | Simplified glanceable agent badge. Header (agent dot + name + connection + "Pause Access"), files summary line, email summary line, action buttons ("Review & Update Access", "View Activity →"). NO per-source lists, NO activity feed, NO work block status. | ~150 |
| **Views/ReviewAccessSheet.swift** | **Full-height attached `.sheet()`** for ALL broadening. Agent switcher header, "What's Changing" tinted diff section, Files \| Emails internal tab bar, source/domain checklists, sensitivity picker (on Emails tab), Advanced disclosure (collapsed), sticky footer with counts + CTAs ("Update Access" / "Start Tracked Work Block"). | ~400 |
| **Views/ReviewChangesSheet.swift** | `.sheet()` for Work Block end. Shows PromoteEngine.dryRun() results: Applied, Conflicts, New, Skipped sections. Per-file approve/rollback + bulk actions. | ~200 |
| **Views/SourcesTableView.swift** | Files tab Sources overview mode (default when no source selected in sidebar). Table with Name, Path, Items, Size, Access column(s). Single column in focused agent mode, two columns in Compare mode. Row tinting in agent color for checked rows. | ~200 |
| **Views/DomainsTableView.swift** | Emails tab Domains overview mode (default when "All Mail" selected). Table with Domain, Category, Emails, +Future (inline text), Access column(s). Category grouping (Work, Automated, Personal, Hidden by sensitivity). Sensitivity dropdown in toolbar. | ~280 |
| **Views/ActivityDrawer.swift** | Right-side drawer wrapping `ActivityView` internals. Agent filter, timeline, export. Replaces Inspector when open. | ~100 |
| **Views/FilesSidebar.swift** | Files tab sidebar: Sources list with agent-colored dots, Versions section, Activity link. **No view mode toggle** — sidebar IS the mode switch (click source → file browser, click nothing → Sources overview). | ~100 |
| **Views/EmailsSidebar.swift** | Emails tab sidebar: Accounts tree, Smart Mailboxes, Activity link. **No sensitivity controls** (those are in toolbar). **No view mode toggle** — sidebar IS the mode switch (click account/mailbox → Messages, click All Mail → Domains overview). | ~100 |
| **Views/TopBarView.swift** | Top bar: App icon + "Manifold" label, segmented control (3 tabs), search button (⌘K), agent connection indicators (colored dots + names). | ~80 |
| **Views/WorkBlockBannerView.swift** | **Global persistent banner** below top bar when work block is active. Agent color accent, duration timer, modified/new file counts, "Finish & Review" (primary), "Pause Access" (secondary), "Stop Now" (destructive). Visible on ALL tabs. | ~120 |
| **Views/AgentFocusControl.swift** | Reusable segmented control: Claude \| Codex \| Compare. Used in Files toolbar and Emails toolbar. Drives single-column vs. dual-column table layout. | ~60 |
| **ManifoldKit/AgentAccessPolicy.swift** | New data types: `AgentAccessPolicy`, `TemporaryReveal`, `WorkBlockRecord`, `WorkBlockStatus`. SQLite persistence via Codable. | ~200 |
| **ManifoldKit/PolicyStore.swift** | Actor for CRUD on `AgentAccessPolicy`. Methods: `policy(for:)`, `updatePolicy()`, `allPolicies()`. SQLite-backed. | ~180 |
| **ManifoldKit/WorkBlockStore.swift** | Actor for CRUD on `WorkBlockRecord`. Methods: `startBlock()`, `endBlock()`, `activeBlock(for:)`. SQLite-backed. | ~150 |

**Removed from v4.0 plan**: `OverviewSidebar.swift` — Overview has no sidebar in v4.1.

**Added in v4.1**: `WorkBlockBannerView.swift` (global banner), `AgentFocusControl.swift` (reusable segmented control).

### 3.3 Files to MODIFY

| File | Changes |
|------|---------|
| **ManifoldApp.swift** | Remove Cmd+Shift+S/E (start/end session). Add Cmd+Shift+R (Review & Update Access), Cmd+Shift+W (Work Block toggle), Cmd+Shift+P (Pause Access). Change TabView to 3 tabs (Overview/Files/Emails). Remove "Sessions" from menu bar extra — replace with agent status + pause controls. Add Tab key binding for cycling agent focus. |
| **MainView.swift** | Replace `NavigationSplitView` sidebar navigation with top-bar `TabView` routing to 3 tab views. Overview renders full-width (no sidebar column). Files and Emails each manage their own sidebar via internal `NavigationSplitView`. Work Block Banner lives here, above tab content, below top bar. Inspector panel logic remains but add Activity drawer toggle. |
| **ManifoldStore.swift** | Remove `SessionModel` dependency. Add `PolicyModel`, `WorkBlockModel`, `DomainModel` as sub-models. Remove session polling. Add policy change observation. Keep source management, file enumeration, email account management. |
| **HomeView.swift** → rename to **OverviewView.swift** | Replace session banner + start button with two agent policy cards, full-width, centered. Add "Start Tracked Work Block" button below cards. Remove sidebar (Overview has no sidebar). |
| **SidebarView.swift** | Delete entirely — sidebar is now per-tab, not global. Files gets `FilesSidebar.swift`, Emails gets `EmailsSidebar.swift`, Overview gets nothing. |
| **FilesView.swift** | Restructure around sidebar-as-mode-switch pattern. When no source selected → show `SourcesTableView` (Sources overview). When source selected → show file browser. Add Agent Focus segmented control in toolbar. Remove session-specific badge logic. Add row tinting. |
| **SourcesView.swift** | Refactor into `SourcesTableView.swift`. Add agent-scoped access column (single in focused mode, dual in Compare). Wire checkbox checking to ALWAYS open Review & Update Access sheet (no inline broadening). Wire unchecking to inline + undo toast. Add row tinting for checked rows. Add bulk action toolbar. |
| **EmailView.swift** | Restructure around sidebar-as-mode-switch pattern. When "All Mail" or top-level selected → show `DomainsTableView`. When specific account/mailbox selected → show Messages. Add Agent Focus segmented control in toolbar. Move sensitivity from sidebar to Domains toolbar. Add "Reveal temporarily" and "Allow domain" actions in reading pane for hidden emails. |
| **EmailSidebar** | Remove "Session Email Access" stats section. Remove sensitivity pickers (moved to Domains toolbar). Remove view mode toggle. Keep: accounts tree, smart mailboxes, activity link. Sidebar = pure navigation. |
| **HistoryView.swift** | Demote: contents move into `ActivityDrawer.swift`. The standalone view is removed as a tab. |
| **ActivityView.swift** | Minimal changes — wrap in drawer container. Add agent filter prop. Add file-context filter prop. |
| **DashboardView.swift** | Replace with `OverviewView.swift`. Delete. |
| **ManifoldBridge.swift** | Replace `requireGrant()` with `resolvePolicy()`. Check `AgentAccessPolicy.isPaused` first. Then check `allowedSourceIDs` for file operations, `allowedEmailDomains` + sensitivity for email operations. For work blocks: if active, use materialized workspace for writes. For standing access: reads/searches go direct to original files (no materialization). |
| **GrantStore.swift** | Keep for backward compatibility and work block grants. Add methods: `createStandingGrant()` (no timeout), `standingGrant(for:)`. Standing grants never expire. Work block grants use existing timeout/lifecycle. |
| **WorkspaceLeaseManager.swift** | Rename "runs" concept to "work blocks" in method names. `startRun()` → `startWorkBlock()`. Keep internals. |
| **ManifoldKit/DatabaseMigrator.swift** | Add migration for new tables: `agent_access_policies`, `temporary_reveals`, `work_block_records`. |

### 3.4 Unchanged files (no modifications needed)

- ContentStore.swift, SnapshotStore.swift, AuditStore.swift, EmailStore.swift, EmailSyncEngine.swift
- ContextEngine.swift, DiffEngine.swift, GlobMatcher.swift, IMAPConnection.swift, IMAPParser.swift
- MIMEParser.swift, MailDiscoveryService.swift, MailProviderDetector.swift, OAuthManager.swift
- ProfileManager.swift, EmailAccount.swift, EmailSyncState.swift, Extensions.swift
- ManifoldError.swift, ManifoldNotifications.swift, ArtifactIndex.swift, ConfigWriter.swift
- Components: AgentBadge.swift, StatusBadge.swift, DiffView.swift, TimeLabel.swift, Spacing.swift
- Views: OnboardingView.swift, SetupView.swift, CommandPaletteView.swift
- Views/Versions/VersionsView.swift, VersionDetailView.swift, SnapshotRow.swift (move into Files Inspector)
- Views/Email/* (internal structure — add Domains mode alongside existing Messages mode)

---

## 4. IMPLEMENTATION PHASES

### Phase 1: Data layer (no UI changes yet)
**Goal**: New types and stores, backward-compatible. All existing tests pass.

1. Create `AgentAccessPolicy.swift` with struct definitions (`AgentAccessPolicy`, `TemporaryReveal`, `WorkBlockRecord`, `WorkBlockStatus`)
2. Create `PolicyStore.swift` actor with SQLite CRUD
3. Create `WorkBlockStore.swift` actor with SQLite CRUD
4. Add database migration in `DatabaseMigrator.swift`
5. Update `GrantStore.swift` to support standing grants (no timeout)
6. Write tests for PolicyStore, WorkBlockStore, standing grants

**Validation**: `swift test` passes. No UI changes visible.

### Phase 2: MCP bridge adaptation
**Goal**: Bridge resolves access via PolicyStore instead of requiring active grant.

1. Add `resolvePolicy()` method to `ManifoldBridge.swift`
2. Dual-path: if standing access → resolve via PolicyStore; if work block → resolve via materialization
3. Update `getStatus()` to show policy state
4. Update `listFiles()` / `readFile()` / `writeFile()` / `searchFiles()` access checks
5. Write integration tests: standing access allows reads, paused denies, work block routes writes to workspace

**Validation**: MCP tools work with standing access policy. No session start required.

### Phase 3: Navigation restructure
**Goal**: 3-tab layout replaces 5-item sidebar. Overview is full-width.

1. Create `TopBarView.swift` with segmented control
2. Modify `MainView.swift`: replace sidebar NavigationSplitView with TabView routing to 3 tab views
3. Create `FilesSidebar.swift` (sources list, versions, activity link — pure navigation)
4. Create `EmailsSidebar.swift` (accounts tree, smart mailboxes, activity link — pure navigation)
5. Delete `SidebarView.swift`
6. Overview tab renders full-width — no NavigationSplitView, no sidebar column
7. Update `ManifoldApp.swift` keyboard shortcuts (Cmd+1/2/3 for 3 tabs)

**Validation**: App launches with 3 tabs. Overview is full-width. Files and Emails have per-tab sidebars. Content areas show placeholder or existing views.

### Phase 4: Agent Focus + reusable components
**Goal**: Agent Focus segmented control and Work Block Banner built as reusable components.

1. Create `AgentFocusControl.swift` — segmented control: Claude | Codex | Compare
2. Create `WorkBlockBannerView.swift` — global banner with agent color, duration, actions
3. Wire Work Block Banner into `MainView.swift` (below top bar, above tab content)
4. Wire Agent Focus control into Files and Emails toolbar areas
5. Add `@State` for focused agent in Files and Emails tab views

**Validation**: Agent Focus segmented control toggles between modes. Work Block Banner appears/disappears based on model state.

### Phase 5: Overview tab
**Goal**: Agent policy cards replace session dashboard.

1. Create `PolicyModel.swift`
2. Create `OverviewView.swift` — full-width, centered max-width content
3. Create `AgentPolicyCard.swift` — simplified: header, files summary, email summary, action buttons
4. Wire to PolicyStore for live data
5. Implement "Pause Access" button (immediate, no sheet — changes `isPaused`)
6. Add empty states: no agents connected, agent connected but no access
7. Add "Start Tracked Work Block" button below cards
8. Remove `DashboardView.swift`

**Validation**: Overview shows live agent access summaries. Pause/Resume works immediately. Empty states render correctly.

### Phase 6: Files tab — Sources mode with access controls
**Goal**: Per-agent checkbox column on source table. ALL broadening through sheet.

1. Create `SourcesTableView.swift` with agent-scoped access column(s)
2. Wire Agent Focus control: single "Access" column in focused mode, "Claude" + "Codex" columns in Compare mode
3. **Checking a box** → opens Review & Update Access sheet pre-focused on this addition. Change is NOT applied until sheet confirms.
4. **Unchecking a box** → immediate removal + undo toast
5. Add row tinting: checked rows get subtle agent-color background
6. Add bulk actions toolbar (select multiple → "Add to [Agent]" triggers sheet, "Remove Access" → immediate + undo)
7. Integrate existing file browser as source-selected mode (sidebar click → file browser)
8. Implement sidebar-as-mode-switch: no source selected → Sources overview; source selected → file browser; "← Sources" breadcrumb to return

**Validation**: User can check/uncheck source access per agent. Checking ALWAYS opens Review sheet. Unchecking is inline + undo. Row tinting reflects state. MCP bridge reflects changes immediately after sheet confirm.

### Phase 7: Emails tab — Domains mode with access controls
**Goal**: Domain-level access table with per-agent checkboxes. Sensitivity in toolbar.

1. Create `DomainModel.swift`
2. Create `DomainsTableView.swift` with category grouping (Work, Automated, Personal, Hidden by sensitivity)
3. Wire Agent Focus control: single "Access" column in focused mode, dual columns in Compare mode
4. Move sensitivity dropdown from sidebar to Domains toolbar, scoped to focused agent
5. **Checking a domain** → opens Review & Update Access sheet pre-focused on this domain
6. **Unchecking** → immediate + undo toast
7. **Loosening sensitivity** → opens Review sheet (broadening)
8. **Tightening sensitivity** → immediate + undo toast (narrowing)
9. Add "Reveal temporarily" and "Allow domain" actions in reading pane for hidden emails
10. Add `TemporaryReveal` support in ManifoldBridge
11. Implement sidebar-as-mode-switch: "All Mail" / top-level → Domains overview; specific account/mailbox → Messages

**Validation**: User can manage email access at domain level. Sensitivity is persistent per-agent. All broadening triggers sheet.

### Phase 8: Review & Update Access sheet
**Goal**: Full-height attached sheet for ALL broadening events.

1. Create `ReviewAccessSheet.swift` as `.sheet()` with `presentationDetents([.large])` or equivalent full-height modifier
2. Agent switcher in header (Claude ● | ○ Codex)
3. "What's Changing" section with green tinted background — shows specific additions being proposed
4. Files | Emails internal tab bar within the sheet
5. Source checklist with (current) and (new ✦) labels
6. Domain checklist with "archived now" counts and "+ future mail" inline text
7. Sensitivity picker on Emails tab
8. Advanced disclosure (collapsed by default) — work block options
9. Sticky footer: scope summary counts + "Cancel" / "Update Access" / "Start Tracked Work Block"
10. Dynamic primary button label: "Allow Access" (first grant), "Update Access" (updating), "Start Tracked Work Block" (if toggled), "Copy Access" (copying between agents)
11. Wire trigger logic: every broadening action opens the sheet pre-focused on the specific change
12. Connect to PolicyModel: changes only committed on confirm, cancelled on dismiss

**Validation**: Sheet appears on EVERY broadening action. Changes only apply on confirm. Sheet is fast to review and confirm for simple single-item additions.

### Phase 9: Tracked Work Blocks
**Goal**: Optional snapshot/promote lifecycle with global banner.

1. Create `WorkBlockModel.swift`
2. Wire to MaterializationEngine, SnapshotStore, PromoteEngine
3. Create `ReviewChangesSheet.swift` for work block end (Applied, Conflicts, New, Skipped sections)
4. "Start Tracked Work Block" button on Overview + as secondary CTA in Review sheet
5. Starting a work block → Review sheet opens (if not already) with "Start Tracked Work Block" as CTA
6. Work Block Banner appears on confirm — visible on all tabs
7. "Finish & Review" → PromoteEngine.dryRun() → Review Changes sheet → promote
8. "Pause Access" → immediate pause, banner shows "Paused"
9. "Stop Now" → confirmation alert ("Discard Changes" destructive button) → discard + remove banner

**Validation**: User can start work block → agent writes to workspace → user reviews and promotes. Banner is visible on ALL tabs during active block.

### Phase 10: Activity drawer + cleanup
**Goal**: Activity as drawer, remove History tab, polish.

1. Create `ActivityDrawer.swift` wrapping ActivityView
2. Wire drawer toggle from Overview "View Activity →", Files sidebar "View Activity →", agent cards, ⌘⇧A
3. Remove History tab from navigation
4. Delete `SessionModel.swift`, `PresetPickerView.swift`, `SessionView.swift`
5. Update keyboard shortcuts, menu bar extra
6. Polish empty states, loading states, error states
7. Verify all copy changes from LAYOUT-SPEC-v4.md Copy/Label Guide are applied
8. Verify animation timings match Animation Language table in spec

**Validation**: Full v4.1 flow works end-to-end. No session artifacts remain. All 8 critique changes verified.

---

## 5. DESIGN ARTIFACTS CHECKLIST

| Artifact | File | Status |
|----------|------|--------|
| UI Specification | `design/LAYOUT-SPEC-v4.md` (v4.1) | ✅ Complete |
| Implementation Plan | `design/IMPLEMENTATION-PLAN-v4.md` (v4.1) | ✅ This document |
| Navigation Flows | `design/navigation-flows-v4.mermaid` | 🔄 Needs v4.1 update |
| Interactive Wireframe | `design/manifold-wireframe-v4.html` | 🔄 Needs v4.1 rebuild |
| Original Wireframe (reference) | `design/manifold-wireframe.html` | ✅ Existing v2 |
| Design Critique | `design/DESIGN-CRITIQUE-v4.md` | ✅ Complete |
| Access Grant Summary | `design/ACCESS-GRANT-SUMMARY.md` | ✅ Existing (v3, reference) |
| LoveFrom Review | `design/access-grant-lovefrom-review.html` | ✅ Existing (reference) |
| Full Context (for external AI) | `design/MANIFOLD-FULL-CONTEXT.md` | ✅ Existing |

---

## 6. FINAL RECOMMENDATION SUMMARY

### The core shift
Manifold v4.1 moves from **session-gated access** to **standing access with optional tracked work blocks**. This aligns with how Claude/Cowork and Codex actually work (folder-based persistent access) and removes unnecessary ceremony from the daily workflow.

### What makes this work

1. **The Intentionality Rule** is the single most important design decision. ALL broadening access requires deliberation (Review & Update Access sheet opens every time). Narrowing access is instant and reversible. This asymmetry matches the actual risk profile: granting new access is consequential, removing it is safe. There are no exceptions, no "inline broadening after first grant" — every grant is deliberate.

2. **Each surface has one job.** Overview answers the trust question. Files tab owns file access control. Emails tab owns email access control. Sidebars are pure navigation. Toolbars hold data controls. The Review sheet is the commitment surface. The Work Block Banner shows operational state. No surface tries to do two things.

3. **Agent Focus reduces noise.** Most of the time, the user works with one agent. The Claude | Codex | Compare segmented control keeps tables calm and readable by default, with explicit opt-in to the comparison view.

4. **Work Blocks are opt-in, not the default.** Most agent interactions don't need snapshot/promote lifecycle. Standing access with audit logging is sufficient. Work blocks exist for high-stakes work where rollback matters. The global banner ensures the user never forgets a work block is active.

5. **The Review sheet must be fast.** Since every broadening triggers the sheet, the sheet's UX is critical path. Pre-populate with the specific change, highlight "What's Changing" visually, make confirm reachable in one click. A single-source addition should take under 2 seconds to review and confirm. If the sheet feels slow or heavy, the entire product feels slow.

### What to watch for during implementation

- **PolicyStore ↔ GrantStore coexistence**: Phase 1 must ensure both work during the transition. Standing grants should be distinct from work block grants in the database.
- **MCP bridge dual-path**: The bridge must handle both standing access (direct file reads) and work block (materialized workspace reads/writes). Test edge cases: what happens if a work block is active and the user narrows standing access? Answer: work block scope is frozen at start, standing access changes don't affect active work blocks.
- **Review sheet performance**: Since EVERY broadening opens the sheet, it must present fast. Pre-compute the "What's Changing" diff before animation starts. The sheet's data should be ready before the spring animation completes.
- **Agent Focus state persistence**: The focused agent should persist across tab switches (if I'm focused on Claude in Files and switch to Emails, Emails should also show Claude). Store in `ManifoldStore` or `@SceneStorage`.
- **Row tinting implementation**: Use `.listRowBackground()` with a very low-opacity agent color. Test in both light and dark mode. The tint should be barely perceptible — it reinforces the checkbox state, it's not a highlight.
- **Domain computation performance**: `DomainModel.computeDomains()` aggregates from EmailStore. With 10k+ emails, this needs to be cached and incrementally updated. Don't recompute on every EmailStore change — debounce.
- **Toast undo timing**: Undo toasts for narrowing actions should last 5 seconds. After that, the change is committed. During the undo window, the MCP bridge should already reflect the change (fail-closed: narrowing is immediate even before undo expires).
- **Sidebar-as-mode-switch selection state**: When no source is selected in Files sidebar, the Sources overview shows. Need to handle the "deselect" gesture — clicking the section header or a dedicated "All Sources" item at the top of the sidebar list.

### Risk assessment

- **Lowest risk**: Phases 1-2 (data layer + bridge). Additive, testable, no UI breakage.
- **Medium risk**: Phases 3-4 (navigation + agent focus + banner). Structural UI change but conceptually clean.
- **Highest risk**: Phases 6-8 (Sources/Domains tables with agent checkboxes + Review sheet). This is the core interaction loop — check a box → sheet opens → confirm → state updates → row tints. If ANY part of this chain feels sluggish or confusing, the product fails. Every broadening going through the sheet raises the stakes on sheet UX. Prototype and dogfood this loop obsessively.
- **Clean-up risk**: Phase 10 (deleting session artifacts). Don't do this until everything else works. Keep SessionModel alive as dead code until the v4.1 path is fully validated.
