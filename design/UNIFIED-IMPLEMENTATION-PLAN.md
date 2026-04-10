# Manifold v4.1 — Unified Implementation Plan

> **What this is**: A single, audited implementation plan merging phases 0–14. Each phase states what's already built, what needs work, and what to build fresh. This replaces `CLAUDE-CODE-IMPLEMENTATION-PLAN.md` and `CLAUDE-CODE-SETTINGS-SETUP-PLAN.md` as the operative build document.
>
> **Source of truth**: `design/LAYOUT-SPEC-v4.md` defines WHAT. This document defines HOW and IN WHAT ORDER.
>
> **Required skill**: Invoke `swiftui-pro` before writing any SwiftUI view code.
>
> **Target**: macOS 26, Swift 6 strict concurrency, Liquid Glass, `@Observable`, `NavigationSplitView`.

---

## Codebase Audit Summary

### Already Built (keep, modify where noted)

| File | Lines | Status | Notes |
|------|-------|--------|-------|
| `MainView.swift` | 270 | **Modify** | Has tab structure + work block banner. No dedicated TopBarView — tabs inline. Fine. |
| `OverviewView.swift` | 131 | **Modify** | Agent cards + empty states exist. Needs empty state polish. |
| `FilesView.swift` | 321 | **Modify** | Dual-agent comparison, filtering. Serves as FilesTabView. |
| `FilesSidebar.swift` | 61 | **Modify** | Exists but minimal. Needs source navigation, version filters. |
| `EmailView.swift` | 269 | **Keep** | Full email tab with sidebar integration. |
| `EmailSidebar.swift` | 107 | **Modify** | Remove sensitivity picker (moves to Domains toolbar). |
| `WorkBlockBannerView.swift` | 112 | **Keep** | Global banner with finish/pause/stop. |
| `ReviewAccessSheet.swift` | 286 | **Modify** | Exists. Verify "What's Changing" section and broadening triggers. |
| `SourcesTableView.swift` | 232 | **Modify** | Exists. Verify Intentionality Rule wiring (broadening → sheet). |
| `DomainsTableView.swift` | 351 | **Modify** | Exists. Verify category grouping and sensitivity picker placement. |
| `AgentPolicyCard.swift` | 131 | **Keep** | Summary card per agent. |
| `ActivityDrawer.swift` | 38 | **Modify** | Stub. Needs agent filter, timeline. |
| `CommandPaletteView.swift` | 129 | **Keep** | ⌘K palette works. |
| `PolicyModel.swift` | 184 | **Keep** | View model for policy management. |
| `ManifoldTypes.swift` | 64 | **Keep** | Has `AppTab`, `AgentFocus`. |
| `ManifoldStore.swift` | 614 | **Modify** | Central store. Needs `IntegrationHealthModel` wiring. |
| `SetupModel.swift` | 91 | **Slim** | Remove MCP/agent config booleans → preferences only. |
| `OnboardingView.swift` | 392 | **Delete** | Replaced by SetupAssistantView. |
| `SetupView.swift` | 350 | **Delete** | Replaced by SettingsView. |

### Already Built in ManifoldKit (backend)

| File | Lines | Status |
|------|-------|--------|
| `PolicyStore.swift` | 187 | **Keep** — CRUD for AgentAccessPolicy |
| `WorkBlockStore.swift` | 139 | **Keep** — Work block lifecycle |
| `AgentAccessPolicy.swift` | 230 | **Keep** — Policy model + types |
| `GrantStore.swift` | 432 | **Modify** — Add standing grant support |
| `GrantTypes.swift` | 745 | **Keep** — TargetApp enum lives here |
| `ConfigWriter.swift` | 144 | **Keep** — Writes claude_desktop_config.json + config.toml |
| `OAuthManager.swift` | 313 | **Keep** — Full PKCE OAuth2 for Gmail/Microsoft |
| `EmailAccountModel.swift` | 359 | **Keep** — Email account state + sync |

### Must Create (doesn't exist yet)

| File | Purpose |
|------|---------|
| `Views/Settings/SettingsView.swift` | 4-tab Settings window root |
| `Views/Settings/GeneralSettingsPane.swift` | Launch at login, notifications |
| `Views/Settings/AIAppsSettingsPane.swift` | Two agent cards with live health checks |
| `Views/Settings/MailSettingsPane.swift` | Email accounts list + add/remove |
| `Views/Settings/StorageSettingsPane.swift` | Location, size, maintenance |
| `Views/Setup/SetupAssistantView.swift` | 4-screen first-run assistant |
| `Views/Setup/ConnectClaudeSheet.swift` | 3 live checks for Claude Desktop |
| `Views/Setup/ConnectCodexSheet.swift` | 2 live checks for Codex CLI |
| `Views/Setup/AddMailAccountSheet.swift` | Provider-first email setup |
| `Models/IntegrationHealthModel.swift` | Per-agent connection state machine |
| `Models/AgentConnectionState.swift` | State enum + live-check logic |
| `Components/LiveCheckRow.swift` | Reusable health check row |
| `Components/AgentSettingsCard.swift` | Agent card for Settings/Setup |
| `Components/CheckRow.swift` | Status row for Settings panes |

### Must Delete

| File | Why |
|------|-----|
| `Views/SetupView.swift` | Replaced by `Settings/SettingsView.swift` |
| `Views/OnboardingView.swift` | Replaced by `Setup/SetupAssistantView.swift` |
| `Views/SidebarView.swift` | Old 5-item global sidebar — tabs replaced this |
| `Views/SessionView.swift` | Session model removed |
| `Views/PresetPickerView.swift` | Session presets removed |
| `Models/SessionModel.swift` | Session lifecycle removed |
| `Views/Dashboard/` | Replaced by OverviewView |
| `Views/HomeView.swift` | Replaced by OverviewView |

---

## Build Order

The phases below are ordered by dependency. Each phase says what's new vs. what's a modification of existing code.

### Phase 0: Data Layer Polish (ManifoldKit only, no UI)

**What exists**: PolicyStore, WorkBlockStore, AgentAccessPolicy, GrantStore all exist.

**What to do**:
1. Verify `PolicyStore` has `createDefaultPolicy(for:)` → if missing, add it
2. Verify `WorkBlockStore` has `activeBlock(for:)` and `startBlock()/endBlock()` → if missing, add
3. Add standing grant support to `GrantStore`: `createStandingGrant()`, `standingGrant(for:)`
4. Verify DB migration exists for `agent_access_policies`, `temporary_reveals`, `work_block_records` tables
5. Run `swift test` — all pass

**Estimate**: Small. Mostly verification + gap-fill.

### Phase 1: MCP Bridge Adaptation

**What exists**: ManifoldBridge.swift (1459 lines) with grant-based access.

**What to do**:
1. Add `PolicyStore` to `ManifoldBridge`
2. Create dual-path `resolveAccess()`: work block → materialized workspace; standing → direct reads
3. Update tool handlers (`listFiles`, `readFile`, `writeFile`, `searchFiles`) to use new resolution
4. Update `getStatus()` to return policy state
5. Write integration tests

**Estimate**: Medium. Core backend change.

### Phase 2: Navigation Verification

**What exists**: MainView.swift already has tab-based navigation (Overview/Files/Emails), work block banner integration, and command palette overlay. No dedicated TopBarView — tabs are inline in MainView.

**What to do**:
1. Verify `AppTab` enum exists in ManifoldTypes.swift or ManifoldStore.swift
2. Verify MainView switches correctly between Overview (full-width), Files (NavigationSplitView), Emails (NavigationSplitView)
3. Verify `.sheet()` for ReviewAccessSheet is owned by MainView (accessible from any tab)
4. Add any missing keyboard shortcuts: ⌘1/2/3 (tabs), ⌘⇧R (Review sheet), ⌘⇧W (work block), ⌘⇧P (pause), ⌘⇧A (activity), ⌘I (inspector)
5. Apply Liquid Glass to top bar area if not already present

**Estimate**: Small. Mostly verification.

### Phase 3: View Models Verification

**What exists**: PolicyModel.swift (184 lines).

**What to do**:
1. Verify PolicyModel has `loadPolicies()`, `updateFileAccess()`, `updateEmailAccess()`, `updateSensitivity()`, `pauseAgent()`, `resumeAgent()`
2. Create `Models/WorkBlockModel.swift` if not present — observable wrapper around WorkBlockStore
3. Create `Models/DomainModel.swift` if not present — computes domain aggregates from EmailStore
4. Wire into ManifoldStore: `let policy: PolicyModel`, `let workBlock: WorkBlockModel`, `let domainModel: DomainModel`
5. Remove SessionModel references

**Estimate**: Small–Medium.

### Phase 4: Agent Focus Control + Work Block Banner Verification

**What exists**: WorkBlockBannerView.swift (112 lines). AgentFocus likely in ManifoldTypes.swift.

**What to do**:
1. Verify `AgentFocusMode` enum (claude/codex/compare) exists or create `Components/AgentFocusControl.swift`
2. Verify WorkBlockBannerView has: agent dot, elapsed time, file counts, Finish & Review / Pause Access / Stop Now buttons
3. Verify "Stop Now" has confirmation dialog
4. Verify banner animation: `spring(response: 0.4, dampingFraction: 0.85)`

**Estimate**: Small. Verification + polish.

### Phase 5: Overview Tab Verification

**What exists**: OverviewView.swift (131 lines), AgentPolicyCard.swift (131 lines).

**What to do**:
1. Verify Overview is full-width (no NavigationSplitView)
2. Verify AgentPolicyCard shows summary lines (source count, file count, domain count) NOT per-source lists
3. Verify "Review & Update Access" button triggers `store.requestReviewSheet()`
4. Implement empty states if missing:
   - No agents connected → connect prompt
   - Connected, no access → "Review & Update Access to get started"

**Estimate**: Small.

### Phase 6: Files Tab — Intentionality Rule Audit

**What exists**: FilesView.swift (321 lines), FilesSidebar.swift (61 lines), SourcesTableView.swift (232 lines).

**What to do**:
1. **Critical**: Verify `AccessCheckbox` implements the Intentionality Rule:
   - Checking (broadening) → opens Review sheet, does NOT immediately toggle
   - Unchecking (narrowing) → immediate + undo toast
2. Verify SourcesTableView has AgentFocusControl in toolbar
3. Verify row tinting for checked rows in focused agent's color
4. Verify sidebar mode-switching: click source → file browser; deselect → Sources table
5. Expand FilesSidebar to include source navigation, version filters, "View Activity →" link

**Estimate**: Medium. The Intentionality Rule is the most important interaction.

### Phase 7: Emails Tab — Domains Audit

**What exists**: DomainsTableView.swift (351 lines), EmailView.swift (269 lines), EmailSidebar.swift (107 lines).

**What to do**:
1. Verify Domains table has category grouping (Work, Automated, Personal, Hidden)
2. Verify "+ future mail" text on checked domains, disabled checkboxes on hidden domains
3. Move SensitivityPicker to Domains toolbar (out of sidebar)
4. Verify Intentionality Rule: checking domain → Review sheet; unchecking → immediate + undo
5. Verify loosening sensitivity → Review sheet; tightening → immediate + undo
6. Remove sensitivity pickers from EmailSidebar
7. Add "Reveal temporarily" and "Allow domain" actions for hidden emails in reading pane

**Estimate**: Medium.

### Phase 8: Review & Update Access Sheet Audit

**What exists**: ReviewAccessSheet.swift (286 lines).

**What to do**:
1. Verify "What's Changing" section with green tint showing proposed additions
2. Verify dynamic primary button label (Allow Access / Update Access / Start Tracked Work Block)
3. Verify sheet opens on ALL broadening triggers: source check, domain check, sensitivity loosen, "Review & Update Access" button, "Start Tracked Work Block"
4. Verify `ReviewSheetReason` enum in ManifoldStore with all cases
5. Verify sheet has `.presentationDetents([.large])` for full-height
6. Verify Cancel dismisses with no state change

**Estimate**: Medium.

### Phase 9: Tracked Work Blocks

**What exists**: WorkBlockBannerView, WorkBlockStore.

**What to do**:
1. Wire WorkBlockModel to MaterializationEngine + SnapshotStore + PromoteEngine
2. Implement start flow: Review sheet confirm → MaterializationEngine creates workspace → SnapshotStore baseline → banner appears
3. Create `Views/ReviewChangesSheet.swift` for "Finish & Review": dry run preview, per-file approve/rollback, "Promote" button
4. Wire banner actions: Finish & Review, Pause Access, Stop Now (with confirmation)

**Estimate**: Medium–Large. New view + engine wiring.

### Phase 10: Activity Drawer + Cleanup

**What exists**: ActivityDrawer.swift (38 lines — stub), ActivityView.swift, ActivityRow.swift.

**What to do**:
1. Expand ActivityDrawer: agent filter (Claude/Codex/All), chronological timeline, wrap existing ActivityView internals
2. Wire ⌘⇧A, Overview "View Activity →", sidebar links
3. Delete session artifacts: SessionView, PresetPickerView, SessionModel, Dashboard/, HomeView, SidebarView, HistoryView (standalone)
4. Polish pass: animations per spec, VoiceOver labels, material discipline, dark mode, copy audit

**Estimate**: Medium.

### Phase 11: IntegrationHealthModel (NEW — no UI yet)

**What to create**:
1. `Models/AgentConnectionState.swift` — per-agent health state
   - Claude: 3 checks (app installed, MCP configured, connection verified)
   - Codex: 2 checks (CLI installed, Manifold added to config.toml)
   - No Codex "signed in" check — auth is in Keychain, inaccessible to us
2. `Models/IntegrationHealthModel.swift` — runs all checks, reads ManifoldStore.isConnected for Claude live connection
   - `weak var store: ManifoldStore?` for back-reference
   - `checkClaude()`, `checkCodex()`, `checkAll()`
3. Wire into ManifoldStore: `let integrationHealth = IntegrationHealthModel()`
4. Add compatibility shims: `mcpInstalled`, `claudeDesktopConfigured`, `codexConfigured`
5. Slim SetupModel to preferences only

**Key research-backed decisions**:
- Claude "MCP configured" reads `claude_desktop_config.json` for `"manifold"` key — covers both ConfigWriter and .mcpb install paths
- Codex "Manifold added" reads `~/.codex/config.toml` for `[mcp_servers.manifold]`
- Live connection reads existing `ManifoldStore.isConnected` + `connectedAgent` — does not duplicate notification/polling

**Estimate**: Medium.

### Phase 12: Settings Window (NEW)

**What to create**: `Views/Settings/` directory with 4 panes.

1. **SettingsView.swift** — 4-tab TabView (General, AI Apps, Mail, Storage), 520×460
2. **GeneralSettingsPane.swift** — Launch at login, notifications toggles
3. **AIAppsSettingsPane.swift** — Two `AgentSettingsCard`s with live health checks + "Set Up" buttons that open connection sheets. Re-checks on appear (Rule 6).
4. **MailSettingsPane.swift** — Port email accounts list from old EmailBackupTab. Add account → opens AddMailAccountSheet.
5. **StorageSettingsPane.swift** — Port from old StorageTab. Drop About content (version info → macOS standard About window).
6. **Components**: `AgentSettingsCard`, `CheckRow`, `OverallStatusBadge`
7. Register in ManifoldApp.swift: `Settings { SettingsView().environment(store) }`
8. Delete `Views/SetupView.swift`

**Estimate**: Medium.

### Phase 13: Setup Assistant (NEW)

**What to create**: `Views/Setup/SetupAssistantView.swift` — 4-screen first-run flow.

| Screen | Headline | Primary Action |
|--------|----------|---------------|
| Welcome | "Manifold controls what AI agents see on your Mac." | Get Started |
| Connect AI Apps | "Connect Claude or Codex." | Set Up (per card) |
| Add Your Data | "Choose what to share." | Add Folder / Add Email |
| Review & Finish | "You're ready." | Open Manifold |

Each screen follows LoveFrom rules: one sentence, one primary action, big status, technical detail behind disclosure.

1. Progress: 4 dots (not a progress bar)
2. Transitions: asymmetric move + opacity
3. Screen 2 reuses `SetupAgentCard` (compact `AgentSettingsCard`), opens ConnectClaudeSheet / ConnectCodexSheet
4. Screen 3 uses existing `store.addSourceFromPicker()` and email account setup
5. Screen 4 shows summary, "Open Manifold" sets `hasCompletedOnboarding`
6. Wire in ManifoldApp.swift: `.sheet(isPresented: !store.hasCompletedOnboarding)`
7. Delete `Views/OnboardingView.swift`

**Estimate**: Medium.

### Phase 14: Connection Sheets (NEW)

**What to create**: Three modal sheets for integration setup.

1. **ConnectClaudeSheet.swift** (460×420)
   - 3 live checks: app installed, MCP configured, connection verified
   - Install action: ConfigWriter as primary (one-click silent), .mcpb as manual alternative in disclosure
   - "Check Again" button, "Done" when configured
   - Technical details behind `DisclosureGroup`

2. **ConnectCodexSheet.swift** (460×380 — shorter, 2 checks)
   - 2 live checks: CLI installed, Manifold added
   - "Add to Codex" runs `codex mcp add manifold -- /path/to/binary`
   - Surfaces stderr on failure (e.g., "Not signed in — run `codex login`")
   - No "signed in" check — let Codex handle its own auth

3. **AddMailAccountSheet.swift** (460×440)
   - Phase flow: Choose Provider → Authenticate → Import Settings → Starting Protection → Done
   - Gmail/Outlook: triggers existing `OAuthManager` OAuth flow
   - Other: manual IMAP form
   - Wraps existing `OAuthManager` + `EmailAccountModel` infrastructure

4. **Components**: `LiveCheckRow`, `DetailLine`, `ProviderButton`

**Estimate**: Medium–Large.

---

## LoveFrom Quality Rules (applies to ALL phases)

| # | Rule | Enforcement |
|---|------|------------|
| 1 | No carousels, no horizontal paging | Every screen is one complete thought |
| 2 | One sentence per screen | Headline sentence + `.secondary` supporting text |
| 3 | Big status, small explanation | Status icons 36pt+, explanation `.callout`/`.caption` |
| 4 | One primary action per screen | One `.borderedProminent`, everything else `.bordered`/`.plain` |
| 5 | Technical detail behind disclosure | Paths, configs, CLI commands in `DisclosureGroup` |
| 6 | Return state re-check | Settings/sheets re-run health checks on appear |
| 7 | Liquid Glass only in chrome | `.glassEffect()` on toolbar, sheet frame. Stable opaque for content |
| 8 | Write like Apple | Short. Declarative. "Connected" not "Successfully connected!" |

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘1/2/3 | Switch tabs (Overview/Files/Emails) |
| ⌘K | Command palette |
| ⌘⇧R | Review & Update Access |
| ⌘⇧W | Toggle Work Block |
| ⌘⇧P | Pause/Resume access |
| ⌘I | Toggle Inspector |
| ⌘⇧A | Toggle Activity drawer |
| Escape | Close topmost overlay |
| Tab | Cycle agent focus (Files/Emails only) |

---

## Animation Curves

```swift
.animation(.easeInOut(duration: 0.2), value: selectedTab)           // Tab switch
.animation(.easeInOut(duration: 0.15), value: selectedSource)       // Sidebar
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: isIncluded)  // Checkbox
.animation(.easeInOut(duration: 0.2), value: isIncluded)            // Row tint
.animation(.spring(response: 0.35, dampingFraction: 0.85), value: showInspector)
.animation(.spring(response: 0.4, dampingFraction: 0.85), value: showSheet)
.animation(.spring(response: 0.3, dampingFraction: 0.8), value: showToast)
.animation(.spring(response: 0.4, dampingFraction: 0.85), value: hasActiveBlock)  // Banner
.animation(.easeInOut(duration: 0.15), value: agentFocus)
```

---

## Testing Strategy

| Phase | What to test |
|-------|-------------|
| 0 | PolicyStore gap-fill, standing grants, migration |
| 1 | Bridge resolves standing access, paused denies, work block routes |
| 2 | Tab switching, shortcuts |
| 3 | PolicyModel loads/updates, DomainModel computes |
| 4–5 | Overview renders, cards correct, empty states |
| 6 | Intentionality Rule: broadening → sheet, narrowing → immediate, row tinting |
| 7 | Domain checkbox same, sensitivity, category grouping |
| 8 | Sheet opens on all broadening, changes only on confirm |
| 9 | Work block start/finish/stop, promote, banner on all tabs |
| 10 | No session references compile, full E2E flow |
| 11 | IntegrationHealthModel checks all agents, compatibility shims |
| 12 | Settings 4-tab, health checks on appear, sheets open |
| 13 | Setup Assistant 4-screen flow, first launch, subsequent skip |
| 14 | Connection sheets: live checks, install actions, error surfacing |

---

## Effort Summary

| Phase | Effort | New Code vs. Modification |
|-------|--------|--------------------------|
| 0 | Small | Verify + gap-fill existing ManifoldKit stores |
| 1 | Medium | Modify ManifoldBridge (1459 lines) |
| 2 | Small | Verify existing MainView tab structure |
| 3 | Small–Med | Verify PolicyModel, create WorkBlockModel + DomainModel |
| 4 | Small | Verify existing components |
| 5 | Small | Verify OverviewView + empty states |
| 6 | Medium | Audit FilesView Intentionality Rule wiring |
| 7 | Medium | Audit DomainsTable, move sensitivity to toolbar |
| 8 | Medium | Audit ReviewAccessSheet triggers + content |
| 9 | Med–Large | Wire work block lifecycle + ReviewChangesSheet |
| 10 | Medium | Expand ActivityDrawer, delete session artifacts |
| 11 | Medium | **New**: IntegrationHealthModel + AgentConnectionState |
| 12 | Medium | **New**: 4-tab Settings window |
| 13 | Medium | **New**: 4-screen Setup Assistant |
| 14 | Med–Large | **New**: 3 connection sheets |

**Total**: Phases 0–10 are ~60% verification/modification of existing code, ~40% new. Phases 11–14 are 100% new code. The codebase is further along than a greenfield project — the core navigation, policy model, and data layer are built. The main gaps are Settings, Setup Assistant, connection sheets, and the Intentionality Rule wiring across existing views.

---

## Reference Documents

| Document | Use for |
|----------|---------|
| `design/LAYOUT-SPEC-v4.md` | Source of truth — what every screen looks like, all copy, all rules |
| `design/manifold-wireframe-v4.html` | Visual reference only — open in browser |
| `design/navigation-flows-v4.mermaid` | Navigation graph (Settings section outdated — use this plan) |
| `design/DESIGN-CRITIQUE-v4.md` | The 8-point critique — explains WHY each decision was made |
| `swiftui-pro` skill | Invoke before writing code — macOS 26 Liquid Glass patterns |
