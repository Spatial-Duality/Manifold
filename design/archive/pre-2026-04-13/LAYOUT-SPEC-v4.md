# Manifold UI Layout Specification v4.1

> **Purpose**: Authoritative reference for Claude Code when building Manifold's SwiftUI interface. Replaces LAYOUT-SPEC v2 and v4.0. Maps every feature to a specific UI location. Built around the Standing Access + Optional Tracked Work Blocks model.
>
> **Design language**: macOS 26 Liquid Glass. SF Pro + SF Mono. System semantic colors. Base-4 spacing (4/8/12/16/24/32). Glass for toolbar/sheet chrome and navigation surfaces. Stable opaque surfaces for data rows and content.
>
> **Core design principle**: Manifold's UI must make the trust boundary visible at all times. The user should always be able to answer: "What can this AI see right now?" Access controls live where the data lives. Every surface has one job.
>
> **Revision 4.1 changes**: Integrates 8-point critique — removes Overview sidebar, makes all broadening go through Review Access sheet, promotes sheet to full-height, gives each surface one job, adds per-agent focus with Compare mode, adds first-class work block active state, refines accessibility and material, updates copy.

---

## Product Model: Standing Access + Optional Tracked Work Blocks

### Standing Access (default)
Each AI agent has a persistent access policy. The user can see and adjust it anytime from the Files and Emails tabs. No session start/end ceremony.

### Tracked Work Blocks (opt-in safety mode)
When the user wants change tracking, snapshots, and rollback:
1. User clicks "Start Tracked Work Block" from Overview or Review & Update Access sheet
2. Manifold takes a baseline snapshot of all included sources
3. AI works in materialized workspace (existing MaterializationEngine)
4. User ends block → Review Changes → Promote/Rollback (existing PromoteEngine)

### Intentionality Rule (revised)
- **Narrowing access** (uncheck folder, uncheck domain, tighten sensitivity) → inline, immediate, reversible with undo toast
- **Broadening access** (ANY addition: add folder, add domain, loosen sensitivity) → **always** opens Review & Update Access sheet. No inline broadening. The sheet is pre-focused on the specific change being made.

This is Apple's privacy model: every grant is deliberate. The sheet is the product's commitment surface.

### Agent Focus Rule
The user works with one agent at a time by default. Files and Emails tabs show a segmented control: **Claude | Codex | Compare**. In Claude or Codex mode, the table shows one access column for the focused agent. In Compare mode, both columns appear. This keeps the tables calm and focused unless the user explicitly wants comparison.

---

## App Shell Structure

```
┌─────────────────────────────────────────────────────────────────┐
│ TOP BAR (Liquid Glass)                                          │
│ [M Manifold]    [Overview | Files | Emails]    [🔍 ⌘K] [● Claude ● Codex] │
├────────────┬───────────────────────────────────────┬────────────┤
│            │                                       │            │
│  LEFT      │      MAIN CONTENT                     │  INSPECTOR │
│  SIDEBAR   │      (tab-specific)                   │  (hidden   │
│  (only on  │                                       │  by default)│
│  Files and │                                       │            │
│  Emails    │                                       │            │
│  tabs)     │                                       │            │
├────────────┤                                       └────────────┤
│ [AG] Amar  │                                                    │
│ ⚙ Settings │                                                    │
└────────────┴────────────────────────────────────────────────────┘
```

### Top Bar (Liquid Glass)
- **Left**: App icon + "Manifold" label
- **Center**: Segmented control with 3 tabs: **Overview**, **Files**, **Emails**
  - History is NOT a top-level tab. Activity is a drawer.
- **Right**: Search (⌘K), agent connection indicators
  - Blue dot + "Claude" if connected
  - Purple dot + "Codex" if connected
  - Both shown if both connected

### Left Sidebar (240pt)
- **Overview tab**: NO sidebar. Full-width content.
- **Files tab**: Source navigation, version filters, activity link
- **Emails tab**: Account navigation, smart mailboxes, activity link
- Profile/settings footer always visible at bottom (on tabs that have sidebar)

### Main Content
- Full remaining width, or splits into NavigationSplitView columns per tab

### Inspector (300pt, hidden by default)
- Appears on demand (click file row, click domain, etc.)
- Close via ✕ or Escape
- Contextual: file details, version history, domain metadata, access explanation
- Replaced by Activity drawer when Activity is open

### Profile/Settings Footer
- User avatar (initials), display name
- Gear icon → Settings window

### Work Block Banner (global, when active)
When a Tracked Work Block is active, a persistent banner appears below the top bar across all tabs:
```
┌────────────────────────────────────────────────────────────────┐
│ 🔵 Work Block — Claude · 1h 28m · 12 modified · 3 new        │
│                         [Finish & Review]  [Pause Access]  [Stop Now ⨉] │
└────────────────────────────────────────────────────────────────┘
```
- Banner uses the agent's color (blue for Claude, purple for Codex)
- "Finish & Review" = primary action (blue button)
- "Pause Access" = secondary (gray button)
- "Stop Now" = destructive (red text, requires confirmation alert: "Stop this work block? All changes since baseline will be discarded.")
- Banner is visible on ALL tabs — it is app-wide state

---

## Tab 1: OVERVIEW

Overview is a full-width, calm status surface. It answers the trust question. **No sidebar.**

### Layout
```
┌─────────────────────────────────────────────────────────────────┐
│ TOP BAR                                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌───────────────────────────────────────────────────────┐     │
│   │ ● Claude (Cowork)              connected   [Pause Access]│  │
│   │                                                         │   │
│   │ 2 of 3 sources · 225 files · 1.2 GB                   │   │
│   │ 8 domains · 1,089 emails visible · Moderate            │   │
│   │                                                         │   │
│   │ [Review & Update Access]   [View Activity →]           │   │
│   └───────────────────────────────────────────────────────┘     │
│                                                                 │
│   ┌───────────────────────────────────────────────────────┐     │
│   │ ● Codex                        connected   [Pause Access]│  │
│   │                                                         │   │
│   │ 1 of 3 sources · 182 files · 1.1 GB                   │   │
│   │ 2 domains · 312 emails visible · Strict                │   │
│   │                                                         │   │
│   │ [Review & Update Access]   [View Activity →]           │   │
│   └───────────────────────────────────────────────────────┘     │
│                                                                 │
│   [Start Tracked Work Block]                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Agent Card (simplified)
Each agent card is a glanceable badge, not a dashboard. Contents:

1. **Header**: Agent name + color dot + connection status badge + "Pause Access" button
2. **Files summary**: One line. "2 of 3 sources · 225 files · 1.2 GB"
3. **Email summary**: One line. "8 domains · 1,089 emails visible · Moderate"
4. **Actions**: "Review & Update Access" button, "View Activity →" link

**What is NOT in the agent card:**
- No ✓/✗ per-source list (that's in the Files tab)
- No domain counts visible/hidden (that's in the Emails tab)
- No activity feed (that's in the Activity drawer)
- No work block status (that's in the global Work Block banner)
- No "Start Tracked Work Block" (that's below the cards, or in the Review sheet)

**Pause Access button**: This is the emergency control. Styled as text-only in the agent's color by default. On hover, turns red. On click, immediately suspends all access. The MCP bridge returns "access paused" for any tool call. Reversible — button becomes "Resume Access" in green.

### Empty states
**No agents connected**: "No AI agents connected. Manifold will appear here when Claude or Codex connects via MCP."
**Agent connected, no access**: "Claude is connected but can't access any files or emails. [Review & Update Access] to get started."

---

## Tab 2: FILES

Files is the primary ownership surface for file/folder access control. Pattern: Finder/Xcode — sidebar selects scope, center shows content, inspector gives context.

### Agent Focus Control
Toolbar contains a segmented control: **Claude | Codex | Compare**
- In Claude/Codex mode: one access column, more horizontal breathing room
- In Compare mode: both access columns visible

### Left Sidebar Content
```
SECTION: Sources
  [📁 web-app]        [● agent-color dot]
  [📁 specs]          [● agent-color dot]
  [📁 assets]         [○ gray]
  [+ Add Folder…]

DIVIDER

SECTION: Versions
  [Recently Modified]   [12]
  [AI-Touched Files]    [8]
  [Conflicts]           [2]

DIVIDER

  [View Activity →]     → opens Activity drawer
```

**Sidebar behavior**: The sidebar is pure navigation.
- Clicking a source → main content shows that source's files (file browser)
- Clicking nothing / clicking section header → main content shows Sources overview table
- No view mode toggle. The sidebar IS the mode switch.
- Agent dots on each source show the focused agent's access state (filled = access, hollow = no access)

### Main Content — Sources Overview (default, no source selected)

The primary access management view for files.

```
TOOLBAR: [Claude | Codex | Compare]  [Search sources…]  [+ Add Folder…]

TABLE (single-agent mode, e.g. Claude):
┌──────────────────────────────────────────────────────────────┐
│ Name          Path                    Items   Size    Access │
├──────────────────────────────────────────────────────────────┤
│ 📁 web-app    ~/Projects/web-app      182    1.1 GB   ☑     │
│ 📁 specs      ~/Documents/specs        43    89 MB    ☑     │
│ 📁 assets     ~/Desktop/assets         22    156 MB   ☐     │
└──────────────────────────────────────────────────────────────┘

TABLE (Compare mode):
┌──────────────────────────────────────────────────────────────────┐
│ Name          Path                    Items   Size    Claude Codex│
├──────────────────────────────────────────────────────────────────┤
│ 📁 web-app    ~/Projects/web-app      182    1.1 GB   ☑      ☑  │
│ 📁 specs      ~/Documents/specs        43    89 MB    ☑      ☐  │
│ 📁 assets     ~/Desktop/assets         22    156 MB   ☐      ☐  │
└──────────────────────────────────────────────────────────────────┘

FOOTER: 3 sources · 247 files · 1.3 GB total
        Claude: 225 files (1.2 GB)
```

**Row tinting**: When a source is checked for the focused agent, the row gets a subtle background tint in the agent's color (very light blue for Claude, very light purple for Codex). Unchecked rows have no tint. This makes the trust boundary visible at the row level, not just the checkbox.

**Checkbox behavior — ALL broadening goes through Review & Update Access**:
- **Checking a box** (broadening access): Does NOT immediately toggle. Opens Review & Update Access sheet, pre-focused on this specific addition ("+ Adding web-app to Claude"). User confirms in the sheet. Only then does the checkbox reflect the new state.
- **Unchecking a box** (narrowing access): Immediate. Row tint fades. Undo toast: "Removed Claude access to web-app · Undo"
- **Right-click context menu**: Reveal in Finder, View Activity, Start Tracked Work Block for this source
- **Bulk actions**: Select multiple rows → toolbar shows "Add to [Agent]" / "Remove Access" buttons. Adding triggers Review sheet with all selected sources.

### Main Content — File Browser (source selected in sidebar)

Shows files within the selected source. Standard file browser.

```
TOOLBAR: [← Sources]  [Source: web-app]  [Sort ▼]  [Filter files…]  [182 files]

TABLE:
  Name              Size     Modified    Versions   AI
  Header.tsx        4.2 KB   2m ago      3 ✨        ●
  auth.ts           2.1 KB   3m ago      1           ●
  index.ts          1.8 KB   1h ago      2           ○
```

- "✨" = AI has modified this file
- "●" = accessible by focused agent (colored dot)
- "← Sources" breadcrumb returns to Sources overview
- Click row → opens Inspector with file details, version history, diff

**v1 constraint**: No per-file grant controls. Files inherit access from their source folder. Inspector shows inherited access state clearly.

### Inspector (opens on file click)
```
FILE DETAILS
  Header.tsx
  web-app/src/components/

  Size: 4.2 KB    Type: TSX

ACCESS
  Accessible because web-app is shared with Claude.
  [also shared with Codex]

VERSION HISTORY
  [✏ Modified by Claude]     2m ago
  [✏ Modified by Claude]     Yesterday 3:15 PM
  [B Baseline]               Yesterday 2:14 PM

DIFF PREVIEW
  - export function Header() {
  + export function Header(props) {

ACTIONS
  [Restore] [Reveal in Finder] [Quick Look]
```

---

## Tab 3: EMAILS

Emails is the primary ownership surface for email access control. Pattern: Mail.app — sidebar for accounts/mailboxes, center for content, inspector for context.

### Agent Focus Control
Toolbar contains a segmented control: **Claude | Codex | Compare**

### Left Sidebar Content
```
SECTION: Accounts
  [📬 All Mail]           [1,247]
  [📧 work@company.com]
    └ Inbox               [342]
    └ Sent
    └ Archive
  [📧 personal@gmail.com]
    └ Inbox               [905]

DIVIDER

SECTION: Smart Mailboxes
  [📎 Has Attachments]
  [🏷 Flagged]
  [+] ← create smart mailbox

DIVIDER

  [+ Add Account…]
  [View Activity →]
```

**Sidebar behavior**: Pure navigation. No settings, no sensitivity controls.
- Clicking "All Mail" or top-level → main content shows Domains overview table
- Clicking a specific account/mailbox → main content shows Messages for that context
- No view mode toggle. The sidebar IS the mode switch.

**What is NOT in the sidebar**: Sensitivity controls. Those live in the Domains table toolbar where they govern the data directly.

### Main Content — Domains Overview (default, "All Mail" selected)

The primary access management view for email.

```
TOOLBAR: [Claude | Codex | Compare]  [Search domains…]  [Show: All ▼]
         Sensitivity: [Moderate ▼]   (per focused agent, lives in toolbar)

TABLE (single-agent mode, e.g. Claude):
┌──────────────────────────────────────────────────────────────┐
│ Domain               Category    Emails   + Future    Access │
├──────────────────────────────────────────────────────────────┤
│ 🏢 @company.com      Work        247      + future      ☑   │
│ 👥 @team.com         Work        189      + future      ☑   │
│ 📋 @linear.app       Work         34      + future      ☑   │
│ 🤖 @github.com       Automated   312      + future      ☑   │
│ 🔄 @circleci.com     Automated    89      + future      ☑   │
│ 📰 @substack.com     Automated    15                    ☐   │
│ 👤 @gmail.com        Personal     78                    ☐   │
│ 🛒 @amazon.com       Personal     23                    ☐   │
│ ─── Hidden by sensitivity ─────────────────────────────────  │
│ 🏦 @bankofamerica.com  12          —        ☐ disabled  banking │
│ 🏥 @myhealth.com       27          —        ☐ disabled  health  │
│ 🔐 2FA emails           89          —        ☐ disabled  2FA     │
└──────────────────────────────────────────────────────────────┘

FOOTER: 14 domains · 8 visible · 6 hidden by sensitivity
        Claude: 1,089 emails visible · 158 hidden
```

**Column changes from v4.0** (per critique point 5 and 8):
- "Archived" → "Emails" (count of archived emails, the snapshot number)
- "Future" column eliminated as a separate column. Instead, checked/active domains show "+ future" as inline text after the count, communicating that new mail from this domain will also be visible. Unchecked domains show no future indicator. Hidden domains show "—".
- "Note" column for hidden domains shows the reason (banking, health, 2FA)

**Sensitivity control**: Lives in the toolbar, scoped to the focused agent. "Sensitivity: Moderate ▼". Changing from stricter to looser → triggers Review & Update Access sheet (broadening). Changing from looser to stricter → immediate (narrowing) with undo toast.

**Checkbox behavior — same as Files**:
- **Checking a domain** (broadening): Opens Review & Update Access sheet, pre-focused on "+ Adding @company.com to Claude (247 archived now, + future mail)"
- **Unchecking** (narrowing): Immediate. Undo toast.
- **Hidden domains**: Checkboxes are disabled (grayed out, not emoji). Row uses reduced weight text and disabled control treatment (NOT opacity reduction). Note column shows reason.

**Category grouping**: Rows are grouped by category with subtle section headers (Work, Automated, Personal, Hidden by sensitivity). This replaces the "Category" column — the grouping IS the categorization.

### Main Content — Messages (specific account/mailbox selected)

Two-pane: message list (360pt) + reading pane. Same as v4.0 but with updated copy:

- "Visible to Claude" → access badge on visible emails
- "Hidden: banking" → badge on hidden emails with reason
- **"Reveal temporarily"**: Button on hidden emails. Makes this single email visible to the focused agent. Expires when current run or work block ends. Logged in activity.
- **"Allow domain"**: Button on hidden emails. Opens Review & Update Access sheet pre-focused on this domain.

---

## Review & Update Access Sheet

A **full-height attached sheet** that opens for ALL broadening access changes. This is the product's commitment surface.

### When it opens (broadening triggers — NO exceptions):
- Checking any unchecked source for an agent
- Checking any unchecked email domain for an agent
- Loosening sensitivity (e.g., Moderate → Open)
- Bulk adding multiple folders/domains
- User explicitly clicks "Review & Update Access"
- Starting a Tracked Work Block
- Copying access policy from one agent to another

### When it does NOT open (narrowing = always inline):
- Unchecking a folder → immediate + undo toast
- Unchecking a domain → immediate + undo toast
- Tightening sensitivity → immediate + undo toast
- Pausing access → immediate

### Layout — Full-Height Attached Sheet

```
┌───────────────────────────────────────────────────────────────┐
│ REVIEW & UPDATE ACCESS                                        │
│ Review what Claude can access          [Claude ● | ○ Codex]   │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│ ─── WHAT'S CHANGING ─────────── (tinted green background)     │
│ + Adding 📁 web-app (182 files, 1.1 GB)                      │
│                                                               │
│ ─── FILES ──────────────────── [Files | Emails] tab bar       │
│                                                               │
│ ☑ web-app          182 files · 1.1 GB          (current)     │
│ ☑ specs             43 files · 89 MB            (current)     │
│ ☑ assets            22 files · 156 MB           (new ✦)      │
│                                                               │
│ ─── EMAILS ─────────────────── (or switch via tab bar)        │
│ Sensitivity: [Moderate ▼]                                     │
│ ☑ @company.com        247 archived now · + future mail        │
│ ☑ @team.com           189 archived now · + future mail        │
│ ☑ @github.com         312 archived now · + future mail        │
│ ☐ @gmail.com           78 archived now                        │
│ ☐ @bankofamerica.com   12 archived now    (disabled: banking) │
│                                                               │
│ ▶ Advanced (collapsed by default)                             │
│   Work block options: notes, timeout                          │
│                                                               │
├───────────────────────────────────────────────────────────────┤
│ 247 files · 1,089 emails visible · 158 hidden    (sticky)    │
│                                                               │
│ [Cancel]               [Update Access]  [Start Tracked Work Block] │
└───────────────────────────────────────────────────────────────┘
```

**Key changes from v4.0:**
1. **Full-height**: Attached to the window edge, not a centered 560px overlay. More air, more consequence.
2. **Files | Emails tab bar**: The sheet has its own internal tabs so the user can review files and emails separately rather than scrolling one long list.
3. **"What's Changing" has a tinted background**: Light green for additions, making the delta visually distinct from the full list.
4. **Existing grants are labeled "(current)"**: So the user can distinguish new additions (marked "new ✦") from existing policy.
5. **Advanced is collapsed by default**: Only shows when opening. Contains work block options, NOT "session notes" (that label is retired).
6. **Two CTAs**: "Update Access" (primary) and "Start Tracked Work Block" (secondary). Both visible.
7. **"Archived now" and "+ future mail"**: Updated copy per critique point 8.

**Primary button labels by context:**
- First grant: "Allow Access"
- Updating existing: "Update Access"
- Starting work block: "Start Tracked Work Block"
- Copying from other agent: "Copy Access"

---

## Tracked Work Blocks

### Starting a Work Block
1. User clicks "Start Tracked Work Block" from Overview or Review & Update Access sheet
2. Review & Update Access sheet opens (if not already open) with "Start Tracked Work Block" as the CTA
3. User confirms scope → clicks "Start Tracked Work Block"
4. Manifold: takes baseline snapshot (SnapshotStore), materializes workspace (MaterializationEngine)
5. **Work Block Banner appears** below the top bar across all tabs

### During a Work Block — Global Banner
The Work Block Banner is a persistent status strip visible on every tab:
```
┌────────────────────────────────────────────────────────────────┐
│ ● Work Block — Claude · 1h 28m · 12 modified · 3 new         │
│                    [Finish & Review]  [Pause Access]  [Stop Now ⨉] │
└────────────────────────────────────────────────────────────────┘
```
- Uses agent color as accent
- "Finish & Review" = primary (blue)
- "Pause Access" = secondary (gray)
- "Stop Now" = destructive (red text). Requires confirmation: "Stop this work block? All changes since baseline will be discarded. This cannot be undone." with "Discard Changes" (destructive) and "Cancel" buttons.

### Ending a Work Block
**"Finish & Review"** (normal end):
1. PromoteEngine.dryRun() → shows preview
2. Review Changes sheet:
   - Applied: files safely written back
   - Conflicts: files changed externally AND by agent
   - New: agent-created files
   - Skipped: untouched files
3. User approves → PromoteEngine.promote()
4. Work block ends. Banner disappears. Standing access continues.

**"Pause Access"**: Immediately suspends agent access. Work block stays open. Banner shows "Paused" state. Can resume.

**"Stop Now"** (emergency): Confirmation alert → Ends work block. Discards materialized workspace. Does NOT promote. Banner disappears.

---

## Animation Language

All state transitions should use SwiftUI spring animations. Specific curves:

| Transition | Duration | Curve |
|-----------|----------|-------|
| Tab switch | 0.2s | ease-in-out |
| Sidebar content change | 0.15s | crossfade |
| Checkbox state change | 0.12s | spring(response: 0.3, dampingFraction: 0.7) |
| Row tint appear/fade | 0.2s | ease-in-out |
| Inspector open/close | 0.25s | spring(response: 0.35, dampingFraction: 0.85) |
| Sheet present | 0.3s | spring(response: 0.4, dampingFraction: 0.85) |
| Sheet dismiss | 0.2s | ease-in |
| Toast appear | 0.2s | spring(response: 0.3, dampingFraction: 0.8) |
| Toast dismiss | 0.15s | ease-out |
| Work Block Banner appear | 0.3s | spring(response: 0.4, dampingFraction: 0.85) |
| Agent focus switch | 0.15s | ease-in-out |

---

## Accessibility & Material Rules

### Material discipline
- **Liquid Glass**: Top bar, sheet chrome, inspector frame edges. Glass is for controls and navigation.
- **Stable opaque surfaces**: Data rows, content areas, cards, table cells. Content sits on stable backgrounds.
- **Never use glass for content rows** — the user's data must be legible, not decorative.

### Hidden-state treatment
Hidden domains/emails must NOT rely primarily on opacity reduction. Instead:
- **Label**: "Hidden: banking" in the Note column
- **Icon**: Disabled checkbox (grayed out native control, not emoji)
- **Text weight**: Secondary color (`var(--text-secondary)`) but still readable
- **Row background**: Neutral, same as other rows. The disabled controls and labels communicate the state.
- Test in both light mode and dark mode. Hidden rows must pass WCAG AA contrast on both.

### Checkbox states
Custom checkbox styling must maintain sufficient contrast in both checked and unchecked states. Use native `Toggle` style checkboxes (`.toggleStyle(.checkbox)`) in SwiftUI — they handle accessibility automatically.

### Touch targets
All interactive elements must meet 44pt minimum (Apple HIG for macOS pointer-and-keyboard). Checkbox cells should be at minimum 44×44pt click targets, not just the 16×16 checkbox visual.

---

## Keyboard Shortcuts

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘K | Open command palette | Global |
| ⌘1 | Switch to Overview | Global |
| ⌘2 | Switch to Files | Global |
| ⌘3 | Switch to Emails | Global |
| ⌘⇧R | Open Review & Update Access | Global |
| ⌘⇧W | Start/Finish Tracked Work Block | Global |
| ⌘⇧P | Pause/Resume agent access | Global |
| ⌘I | Toggle Inspector | Files/Emails |
| ⌘⇧A | Toggle Activity drawer | Global |
| Escape | Close inspector/sheet/drawer | Global |
| ⌘, | Open Settings | Global |
| Tab | Cycle agent focus (Claude → Codex → Compare) | Files/Emails |

---

## State Machines

### Agent Access State
```
no_sources → (user checks box) → review_sheet → (allow) → active
active → (user pauses) → paused
paused → (user resumes) → active
active → (user removes all sources via unchecking) → no_sources
active → (user starts tracked work block) → work_block_active [banner appears]
work_block_active → (finish & review) → promoting → (complete) → active [banner disappears]
work_block_active → (pause) → work_block_paused [banner shows "Paused"]
work_block_active → (stop now + confirm) → active [banner disappears, workspace discarded]
```

### Source Access State (per agent)
```
excluded [☐] → (user checks box) → review_sheet → (confirmed) → included [☑, row tinted]
included [☑] → (user unchecks) → excluded [☐, row neutral] immediately + undo toast
```
Note: ALL transitions from excluded → included go through the Review sheet. No inline broadening.

### Connection State
```
disconnected [gray dot]
  → (agent connects) → connected [colored dot]
connected → (agent disconnects) → disconnected
Note: connection state is independent of access state.
An agent can be connected but have no access (no sources checked).
Access policy is persistent regardless of connection.
```

---

## Backend Adaptation Notes

### New: AgentAccessPolicy
```swift
/// Persistent standing access policy per agent.
struct AgentAccessPolicy: Codable {
    let agent: TargetApp
    var allowedSourceIDs: Set<String>
    var allowedEmailDomains: Set<String>
    var emailSensitivity: EmailSensitivity
    var isPaused: Bool
    var hasCompletedFirstGrant: Bool  // tracks whether the first-grant ceremony has occurred
    var updatedAt: Date
}
```

### New: TemporaryReveal
```swift
/// Single-email temporary visibility override.
struct TemporaryReveal: Codable {
    let id: String
    let agent: TargetApp
    let messageID: String
    let expiresAtRunID: String?
    let createdAt: Date
}
```

### New: WorkBlockRecord
```swift
/// Optional tracked work block with snapshot/promote lifecycle.
struct WorkBlockRecord: Codable {
    let id: String
    let agent: TargetApp
    let baselineSnapshotIDs: [String]
    let policyAtStart: AgentAccessPolicy
    let startedAt: Date
    var endedAt: Date?
    var status: WorkBlockStatus
}

enum WorkBlockStatus: String, Codable {
    case active, paused, reviewing, promoted, discarded
}
```

### Reuse Existing Stores
| Existing Store | Reuse Strategy |
|----------------|---------------|
| GrantStore | Wrap with AgentAccessPolicy. Standing access grants have no timeout. |
| AccessStore | Keep as-is. Presets map to policies. |
| MaterializationEngine | Used only for Tracked Work Blocks. Standing access doesn't materialize. |
| PromoteEngine | Used only for Tracked Work Block end. |
| SnapshotStore | Records versions regardless of model. |
| AuditStore | Unchanged. Logs all actions. |
| EmailStore | Unchanged. |
| EmailSensitivityFilter | Unchanged. Now with persistent per-agent sensitivity. |
| WorkspaceLeaseManager | Maps to Work Block lifecycle. |
| ContentStore | Unchanged. |
| ContextEngine | Unchanged. |

### MCP Bridge Adaptation
ManifoldBridge currently calls `requireGrant()` on every tool call. Adapt:
- Standing access: bridge resolves `AgentAccessPolicy` for the connecting agent. If `isPaused`, deny. Otherwise, check if requested file is in an allowed source.
- Work Block active: bridge resolves the work block's materialized workspace for writes.
- No active policy (no sources checked): deny with "no access configured" error.

---

## Feature → Location Map

| Feature | Tab | Panel | Element |
|---------|-----|-------|---------|
| **Access overview** | | | |
| What can Claude see now? | Overview | Main (full-width) | Claude agent card |
| What can Codex see now? | Overview | Main (full-width) | Codex agent card |
| Pause/Resume access | Overview | Main | "Pause Access" on agent card |
| Review & Update Access | Overview + Files + Emails | Various | Button → sheet |
| **File access** | | | |
| Source list with access column | Files | Main (Sources overview) | Table with agent checkbox |
| Agent focus switch | Files | Toolbar | Claude / Codex / Compare segmented |
| Add source folder | Files | Sidebar + Toolbar | "+ Add Folder…" |
| Remove source | Files | Sources overview | Right-click context menu |
| File browsing | Files | Main (source selected) | File table |
| File version history | Files | Inspector | Version timeline |
| File diff preview | Files | Inspector | Diff block |
| File restore | Files | Inspector | Restore button |
| **Email access** | | | |
| Domain list with access column | Emails | Main (Domains overview) | Table with agent checkbox |
| Agent focus switch | Emails | Toolbar | Claude / Codex / Compare segmented |
| Sensitivity per agent | Emails | Toolbar (Domains overview) | Dropdown scoped to focused agent |
| Email browsing | Emails | Main (account selected) | Message list + reading pane |
| Temporary email reveal | Emails | Reading pane | "Reveal temporarily" button |
| Allow domain | Emails | Reading pane | "Allow domain" → Review sheet |
| Smart mailboxes | Emails | Sidebar | Smart Mailbox list + editor |
| **Review & Update Access sheet** | | | |
| What's changing diff | Sheet | Top section (green tint) | Added/removed items |
| Files / Emails tabs | Sheet | Tab bar | Separate review panes |
| Sensitivity picker | Sheet | Emails tab | Dropdown |
| Advanced (collapsed) | Sheet | Bottom | Work block options |
| Scope summary footer | Sheet | Sticky footer | File/email counts + CTAs |
| **Tracked Work Blocks** | | | |
| Start tracked work block | Overview + Sheet | Various | Button → Review sheet |
| Work block status | Global | Work Block Banner | Persistent strip below top bar |
| Finish & Review | Global | Work Block Banner | Button → Review Changes sheet |
| Stop Now (destructive) | Global | Work Block Banner | Red text → confirmation alert |
| **Activity** | | | |
| Activity drawer | Any tab | Right drawer | Chronological audit trail |
| Activity per file | Files | Inspector | File-specific event log |
| **System** | | | |
| Connection status | Top bar | Right | Agent dots + names |
| Command palette | Overlay | — | ⌘K |
| Settings | Settings window | — | Tabs |
| Storage / MCP Status | Settings window | System tab | NOT in Overview |

---

## Copy / Label Guide

| Old (remove) | New |
|--------------|-----|
| Home | Overview |
| Pause | **Pause Access** |
| Review Access... | **Review & Update Access** |
| Start Work Block... | **Start Tracked Work Block** |
| Archived (column) | **Emails** (count) or **Archived now** |
| Future: Included | **+ future mail** (inline after count) |
| Future: Excluded | *(nothing — absence of "+ future" is the signal)* |
| Start Session | *(removed — standing access)* |
| Session Email Access | *(removed)* |
| Visible this session | Visible to [Agent] |
| Auto-hidden | Hidden by sensitivity |
| History | Activity |
| Save as Defaults | *(removed)* |
| End Session | Finish & Review (for work blocks) |
| Advanced: Session notes, timeout, preset | **Advanced: Work block options** |

---

## Design References

- macOS 26 Liquid Glass design language
- Apple Human Interface Guidelines (modality, sidebars, inspectors, sheets, alerts, accessibility)
- Apple privacy patterns (Selected Photos, Allow Once, per-app permission grants)
- The Design of Everyday Things (Norman): discoverability, feedback, conceptual models
- Don't Make Me Think (Krug): clear hierarchy, mindless unambiguous choices
- About Face (Cooper): commensurate effort, mental model matching, designing for intermediates
- Designing Interfaces (Tidwell): single organizing principle per surface
- Refactoring UI (Wathan & Schoger): type scale ratios, visual hierarchy through size
- The Visual Display of Quantitative Information (Tufte): data-ink ratio, smallest effective difference
- Dieter Rams: 10 principles of good design (as little design as possible)
- LoveFrom / Jony Ive: care as signal, invisible details communicate trustworthiness
