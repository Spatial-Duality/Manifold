# Manifold UI ↔ Backend Gap Audit

> Full codebase audit: every Swift view, model, and component compared against the April 13 product model and the current implementation. Organized by severity and layer.

---

## The Core Problem

The UI has two separate realities:

1. **The runtime layer is real.** Sources, file enumeration, policies, email accounts, message fetch/search, sharing, work blocks — all backed by XPC calls to ManifoldRuntime. This works.

2. **The rules/governance layer is fake.** `EmailRulesModel` (shields, domain/contact/keyword rules, default policies) exists purely in memory. Rules are never persisted, never evaluated, never enforced. The entire email governance system the UI displays is a disconnected mock.

Your backend rewrite needs to bridge this gap. Below is every issue, mapped to what the backend needs to provide.

---

## LAYER 1: Data Model Gaps (Backend Must Solve)

### 1.1 — Email Rules Engine Has Zero Runtime Connection
**Severity: CRITICAL — blocks entire email governance feature**

`EmailRulesModel.swift` is a local `@Observable` class with arrays of rules in memory. It has:
- No `configure(client:)` method
- No XPC calls to persist rules
- No evaluation logic to match rules against emails
- Shield `blockedCount` hardcoded to 0, `recentMatches` always empty
- Rules lost on app restart

**What the backend must provide:**
- CRUD API for domain rules, contact rules, keyword rules (create, read, update, delete)
- Persistence layer (SQLite or whatever the runtime uses)
- Rule evaluation engine that runs when emails are fetched: Contact → Keyword → Domain → Shield → Default
- Per-agent rule scoping: a rule can apply to Claude only, Codex only, or both
- Shield statistics: how many emails each shield has blocked, last N matches
- Default policy per agent: "allow unless blocked" vs "block unless allowed"
- A `rulesState()` or similar XPC method that returns the full rules configuration + statistics

**UI files that depend on this:**
- `EmailRulesModel.swift` — needs `configure(client:)` + load/save methods
- `RulesDashboardView.swift` — needs real shield stats and recent activity
- `ShieldDetailView.swift` — needs real match counts and recent matches
- `DomainRulesView.swift` — needs CRUD wired to runtime
- `ContactRulesView.swift` — same
- `KeywordRulesView.swift` — same
- `DefaultPolicyView.swift` — needs per-agent policy persistence

### 1.2 — No Per-Agent Email Sharing
**Severity: CRITICAL — blocks dual-agent email governance**

Current state: `shareEmails(emailIDs:)` shares globally. There's no way to say "share this email with Claude but not Codex."

The XPC client (`AppRuntimeClient`) has:
- `shareEmails(emailIDs:)` — global, no agent parameter
- `sharedEmailIDs()` — returns all shared, no agent filter
- `sharedEmails()` — same

**What the backend must provide:**
- `shareEmails(emailIDs:, with agent:)` — per-agent sharing
- `unshareEmails(emailIDs:, from agent:)` — per-agent unsharing
- `sharedEmailIDs(for agent:)` — query shared set per agent
- `sharedEmails(for agent:)` — fetch shared messages per agent
- OR: make sharing a property on each email record with a `Set<TargetApp>` field

**UI files that depend on this:**
- `EmailMessageList.swift` — needs per-agent shared status dots
- `InlineMessagePreview.swift` — needs per-agent "Share with…" popover
- `SelectionActionBar.swift` — bulk share needs agent targeting
- `SharePopover` (in `RuleFormComponents.swift`) — already designed for dual-agent, needs backend

### 1.3 — No Per-Agent Email Domain Targeting
**Severity: HIGH — blocks per-agent domain rules**

`PolicyModel.addEmailDomain()` adds a domain to one agent's policy, but there's no method to *block* a domain for one agent while allowing it for another. The current model is:
- Add domain → agent can see emails from that domain
- Remove domain → agent can't

But the spec's rule system requires:
- Domain rule: `@stripe.com` → Block for all agents
- Domain rule: `@github.com` → Allow for Claude, Allow for Codex
- Domain rule: `@figma.com` → Allow for Codex only

**What the backend must provide:**
- Domain rules with per-agent allow/block semantics (not just "added to policy" / "removed from policy")
- This replaces the current `addEmailDomain`/`removeEmailDomain` approach with a rules-based approach

### 1.4 — No Rule Evaluation Feedback
**Severity: MEDIUM — blocks "why was this blocked?" UI**

When a user sees a blocked email, they need to know *why*: was it a shield, a domain rule, a keyword match? Currently there's no API to answer this.

**What the backend must provide:**
- Per-email: `evaluationResult` — which rule matched, why it was blocked/allowed
- This enables "Blocked by: Financial Shield" badges on email rows
- This enables "Override: Allow this sender →" quick actions

### 1.5 — Email Message Record Lacks Agent Sharing Detail
**Severity: HIGH — blocks per-agent UI indicators**

`EmailMessageRecord` (in ManifoldTypes or wherever defined) likely has a boolean `isShared` or similar. The spec needs:
- `sharedWith: Set<TargetApp>` — which agents can see this email
- `blockedBy: RuleEvaluationResult?` — why it's blocked (if blocked)
- `sensitivity: ShieldCategory?` — which shield category flagged it

**What the backend must provide:**
- Enrich email records with per-agent sharing state and rule evaluation results
- Return this in `emailMessages()` and `searchEmailMessages()` responses

---

## LAYER 2: View-Level Gaps (UI Must Fix After Backend Ships)

### 2.1 — Work Block Banner Not Rendered
**Severity: HIGH**

`WorkBlockBannerView.swift` exists. `PolicyModel.activeWorkBlock` has real data. But `MainView.swift` never renders the banner persistently across tabs.

**Fix:** Add `WorkBlockBannerView` to `MainView.swift` as a persistent element below the tab bar when `store.policy.activeWorkBlock != nil`. No backend change needed.

### 2.2 — FilesView Missing Agent Focus Control
**Severity: HIGH**

`FilesView.swift` has no `AgentFocusControl` in its toolbar. The spec requires Claude | Codex | Compare segmented control for:
- Row tinting based on focused agent
- Compare mode showing dual access columns
- Filtering by agent access state

`SourcesTableView.swift` already has this correct (agent focus + compare mode). But `FilesView.swift` (the file-level table) doesn't.

**Fix:** Add `AgentFocusControl` to FilesView toolbar. Add agent-colored row tinting. No backend change needed.

### 2.3 — EmailView Missing Domains Overview as Primary View
**Severity: MEDIUM — design decision needed**

The spec says the email tab's primary view should be a Domains governance table (like Files → Sources). Currently `EmailView.swift` routes directly to `EmailMessageList`.

However — with the Rules tab now existing as a separate sub-nav, the Domains governance surface IS the Rules tab. So the question is: when the user selects Emails, should they land on Rules (governance) or Messages (browse)?

**Current behavior:** Emails tab has Rules | Messages sub-nav. Rules is default. This may already be correct.

**Decision needed:** Is the sub-nav the right pattern, or should governance be embedded into the Messages view as a toolbar/filter?

### 2.4 — Agent Source File Counts Are Zero
**Severity: MEDIUM**

`AgentPolicyCard.swift` and `OverviewView.swift` show source folders with file counts, but counts are always 0. The data is available from `enumerateSourceFiles()` but isn't cached per-source for the overview cards.

**Fix:** After file enumeration completes, cache per-source file counts in `ManifoldStore`. No backend change needed — the data exists, just needs caching.

### 2.5 — SharedEmailIDs Set Never Updates
**Severity: HIGH**

`EmailMessageList.swift` loads `sharedEmailIDs` once in `.task` and never refreshes. If user shares emails, UI won't update until navigation change.

**Fix:** Use `@Observable` pattern — derive shared status from a model that updates when share operations complete. Wire `shareEmails()` completion to trigger a reload of shared IDs.

### 2.6 — No Context Menus on Email Rules
**Severity: LOW**

Domain/Contact/Keyword rule rows have no right-click context menu for Edit or Delete. The design spec calls for this.

**Fix:** Add `.contextMenu` with Edit and Delete actions to each rule table row.

### 2.7 — SharePopover Built But Not Wired
**Severity: MEDIUM**

`RuleFormComponents.swift` contains a complete `SharePopover` component with dual-agent toggles, change preview, and Apply button. But it's not used anywhere in the app. All sharing still goes through the old single-agent `ShareWithCoworkSheet` or `ReviewAccessSheet`.

**Fix (after 1.2 is solved):** Replace `ShareWithCoworkSheet` usages with `SharePopover`. Add `SharePopover` to file/email row actions and bulk action bars.

### 2.8 — No "Open in Mail" Verification
**Severity: LOW**

`InlineMessagePreview.swift` has an "Open" button that calls `NSWorkspace.shared.open(emlFileURL)`. No check if the .eml file exists or if a default mail app is configured.

**Fix:** Guard the Open action with a file existence check. Show error if file is missing.

---

## LAYER 3: Component Gaps

### 3.1 — Design Token Layer: COMPLETE ✓
No gaps. `DesignTokens.swift` has all colors, typography, opacity, shadow, and animation presets matching the spec.

### 3.2 — Spacing Layer: COMPLETE ✓
No gaps. `Spacing.swift` has all values plus glass helpers.

### 3.3 — Badge System: COMPLETE ✓
All variants, sizes, and accessibility labels present.

### 3.4 — Rule Form Components: COMPLETE ✓
`AgentCheckboxSelector`, `ActionSegmented`, `RulePreviewStrip`, `SharePopover` all built and matching spec.

### 3.5 — Missing: Unified Error Banner Component
**Severity: LOW**

The spec describes a structured error banner system (Connection/Permission/Database/Network/Validation categories with auto-dismiss timers). No centralized error banner component exists — errors are handled ad-hoc per view.

**Fix:** Create `ErrorBanner.swift` component implementing DESIGN-STANDARDS §9.

### 3.6 — Missing: Undo Toast as Reusable Component
**Severity: LOW**

`SourcesTableView` and `DomainsTableView` both implement inline undo toasts. These should be extracted into a shared `UndoToast` component.

---

## LAYER 4: Dead Code / Superseded Files

### 4.1 — `ShareWithCoworkSheet.swift` → Replace with SharePopover
Single-agent only. Hardcoded to Cowork/Claude. Should be replaced by `SharePopover` once per-agent sharing (1.2) is implemented.

### 4.2 — `DomainsTableView.swift` → Relationship to Rules System
This is the OLD domains governance table (pre-Rules tab). It shows domains with per-agent toggles using the *policy-based* model (`addEmailDomain`/`removeEmailDomain`). The new Rules tab has `DomainRulesView.swift` which uses the *rules-based* model (`EmailRulesModel.domainRules`).

**Decision needed:** When the backend ships rules, does `DomainsTableView` get retired entirely, or does it serve a different purpose (e.g., domain discovery/aggregation vs. rule management)?

### 4.3 — `EmailReadingPane.swift` → Partially Superseded
The Synology-style inline preview (`InlineMessagePreview.swift`) handles the click-to-expand pattern. `EmailReadingPane.swift` still exists as a standalone reading pane for potential three-pane layouts. If the Synology pattern is the final design, the reading pane can be retired or kept for accessibility (some users prefer persistent panes).

### 4.4 — Activity in Overview Cards → Should Be Removed
`AgentPolicyCard.swift` shows "Recent Activity" with 3 entries. The spec says activity belongs in the Activity drawer only. This section should be removed from the cards.

---

## LAYER 5: XPC Boundary / Backend API Surface

### What Exists and Works (No Changes Needed)

| API Method | Description | Status |
|---|---|---|
| `ping()` | Health check | ✓ |
| `dashboardState()` | Full state snapshot | ✓ |
| `listSources()` / `addSource()` / `removeSource()` | Source CRUD | ✓ |
| `pauseAgent()` / `resumeAgent()` | Agent lifecycle | ✓ |
| `addSource(to:)` / `removeSource(from:)` | Per-agent source policy | ✓ |
| `emailMessages()` / `searchEmailMessages()` | Email fetch/search | ✓ |
| `shareEmails()` / `unshareEmails()` | Email sharing (global) | ✓ |
| `startTrackedRun()` / `applyTrackedRun()` | Work blocks | ✓ |
| `recentActivity()` / `sessionEvents()` | Audit trail | ✓ |
| `trackedFiles()` / `fileHistory()` / `snapshotData()` | Version history | ✓ |
| Smart mailbox CRUD | Custom filters | ✓ |

### What the Backend Must Add

| API Method | Description | Blocks |
|---|---|---|
| `emailRulesState()` | Returns full rules config + statistics | Rules Dashboard, all rule views |
| `addDomainRule(domain:action:agents:category:)` | Create domain rule | DomainRulesView inline form |
| `updateDomainRule(id:...)` | Update existing rule | DomainRulesView edit |
| `deleteDomainRule(id:)` | Delete rule | Context menu delete |
| `addContactRule(name:email:action:agents:)` | Create contact rule | ContactRulesView |
| `updateContactRule(id:...)` | Update | ContactRulesView edit |
| `deleteContactRule(id:)` | Delete | Context menu |
| `addKeywordRule(pattern:matchLocation:action:agents:isRegex:)` | Create keyword rule | KeywordRulesView |
| `updateKeywordRule(id:...)` | Update | KeywordRulesView edit |
| `deleteKeywordRule(id:)` | Delete | Context menu |
| `updateShieldState(shieldID:enabled:)` | Toggle shield | ShieldDetailView |
| `updateDefaultPolicy(agent:policy:)` | Set per-agent default | DefaultPolicyView |
| `evaluateEmail(emailID:)` | Returns which rule matched | "Why blocked?" UI |
| `shieldStatistics()` | Returns blocked counts + recent matches per shield | RulesDashboard, ShieldDetail |
| `shareEmails(emailIDs:with:)` | Per-agent email sharing | SharePopover, bulk share |
| `unshareEmails(emailIDs:from:)` | Per-agent email unsharing | SharePopover |
| `sharedEmailIDs(for:)` | Query per-agent shared set | Messages sidebar smart filters |
| `sharedEmails(for:)` | Fetch per-agent shared messages | Agent access filters |

---

## Implementation Priority Order

### Phase 1: Backend Foundation (Must ship first)
1. **Rules persistence** — CRUD for domain/contact/keyword rules + default policies
2. **Per-agent email sharing** — `shareEmails(with:)` / `sharedEmailIDs(for:)`
3. **Shield state persistence** — toggle shields on/off, persist across restart
4. **Rules state query** — `emailRulesState()` returns everything for the UI

### Phase 2: Rule Evaluation Engine
5. **Rule matching** — evaluate Contact → Keyword → Domain → Shield → Default on email fetch
6. **Shield statistics** — count blocked emails, track recent matches
7. **Evaluation feedback** — return "blocked by Shield X" / "allowed by Contact rule Y" per email

### Phase 3: UI Wiring (After backend ships)
8. Wire `EmailRulesModel.configure(client:)` to load rules from runtime
9. Wire CRUD forms to call runtime methods (already built, just need backend calls)
10. Wire `SharePopover` to per-agent sharing API
11. Replace `ShareWithCoworkSheet` with `SharePopover`
12. Add agent-colored row tinting to `FilesView` and `EmailMessageList`
13. Add `WorkBlockBannerView` to `MainView`
14. Remove activity section from `AgentPolicyCard`
15. Fix `sharedEmailIDs` reactivity in `EmailMessageList`

### Phase 4: Polish
16. Add context menus to rule table rows
17. Extract undo toast into shared component
18. Add unified error banner component
19. Verify all empty states, loading states, error states per DESIGN-STANDARDS definition of done
